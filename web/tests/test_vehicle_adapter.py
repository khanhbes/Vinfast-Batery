import os
import shutil
import tempfile
from datetime import datetime, timedelta, timezone
from ai_server.vehicle_adapter import VehicleAdapter, VehicleAdapterTrainer
from ai_server.fine_tune import run_vehicle_adapter_training
from ai_server.lifecycle import vehicle_adapter_quality_gate
from ai_server.training_snapshot_service import TrainingSnapshotService


def test_vehicle_adapter_prediction_blending():
    # Base stage (<5 sessions) -> 100% base model
    adapter_base = VehicleAdapter({
        "vehicle_id": "VF_TEST_01",
        "personalization_stage": "base",
        "session_count": 2,
        "global_time_scale": 1.2,
    })
    pred = adapter_base.adjust_prediction(base_seconds=3600.0, start_soc=20, target_soc=80)
    assert pred == 3600.0

    # Calibrating stage -> 70% base, 30% adapted
    adapter_calib = VehicleAdapter({
        "vehicle_id": "VF_TEST_01",
        "personalization_stage": "calibrating",
        "session_count": 10,
        "global_time_scale": 1.1,
        "global_time_bias_minutes": 0.0,
    })
    # adapted = 3600 * 1.1 = 3960
    # blended = 0.70 * 3600 + 0.30 * 3960 = 2520 + 1188 = 3708.0
    pred = adapter_calib.adjust_prediction(base_seconds=3600.0, start_soc=20, target_soc=80)
    assert abs(pred - 3708.0) < 1.0

    # Personalized stage -> 30% base, 70% adapted
    adapter_pers = VehicleAdapter({
        "vehicle_id": "VF_TEST_01",
        "personalization_stage": "personalized",
        "session_count": 35,
        "global_time_scale": 1.1,
        "global_time_bias_minutes": 0.0,
    })
    # blended = 0.30 * 3600 + 0.70 * 3960 = 1080 + 2772 = 3852.0
    pred = adapter_pers.adjust_prediction(base_seconds=3600.0, start_soc=20, target_soc=80)
    assert abs(pred - 3852.0) < 1.0


def test_vehicle_adapter_soc_bands():
    adapter = VehicleAdapter({
        "vehicle_id": "VF_BAND_TEST",
        "personalization_stage": "personalized",
        "session_count": 30,
        "global_time_scale": 1.0,
        "soc_bands": {
            "0-20": {"scale": 1.2, "bias": 0.0},
            "20-80": {"scale": 1.0, "bias": 0.0},
            "80-100": {"scale": 1.5, "bias": 0.0},
        }
    })
    # Test charging purely in 80-100 band: scale should be 1.5
    pred = adapter.adjust_prediction(base_seconds=1000.0, start_soc=80, target_soc=100)
    # adapted = 1000 * 1.5 = 1500. blended = 0.3 * 1000 + 0.7 * 1500 = 300 + 1050 = 1350
    assert abs(pred - 1350.0) < 1.0


def test_vehicle_adapter_trainer_stages():
    tmp_dir = tempfile.mkdtemp()
    try:
        trainer = VehicleAdapterTrainer(adapters_dir=tmp_dir)

        # 1. Zero/few sessions -> stage 'base'
        adapter = trainer.train_adapter("VEHICLE_A", [])
        assert adapter.personalization_stage == "base"
        assert adapter.session_count == 0

        # 2. 6 sessions over 2 days -> stage 'calibrating' (count >= 5, but < 30)
        now = datetime.now(timezone.utc)
        sessions_6 = []
        for i in range(6):
            t_start = (now - timedelta(days=2 - i * 0.3)).isoformat()
            t_stop = (now - timedelta(days=2 - i * 0.3) + timedelta(hours=2)).isoformat()
            sessions_6.append({
                "start_soc": 20,
                "target_soc": 80,
                "actual_end_soc": 80,
                "energy_used_wh": 2100,
                "actual_duration_seconds": 7200,
                "started_at": t_start,
                "stopped_at": t_stop,
                "created_at": t_start,
            })
        adapter_calib = trainer.train_adapter("VEHICLE_A", sessions_6)
        assert adapter_calib.personalization_stage == "calibrating"
        assert adapter_calib.session_count == 6

        # 3. 32 sessions over 20 days -> stage 'personalized' (count >= 30 and days >= 14)
        sessions_32 = []
        for i in range(32):
            t_start = (now - timedelta(days=20 - i * 0.6)).isoformat()
            t_stop = (now - timedelta(days=20 - i * 0.6) + timedelta(hours=2)).isoformat()
            sessions_32.append({
                "start_soc": 25,
                "target_soc": 85,
                "actual_end_soc": 85,
                "energy_used_wh": 2100,
                "actual_duration_seconds": 7200,
                "started_at": t_start,
                "stopped_at": t_stop,
                "created_at": t_start,
            })
        adapter_pers = trainer.train_adapter("VEHICLE_A", sessions_32)
        assert adapter_pers.personalization_stage == "personalized"
        assert adapter_pers.session_count == 32
        assert adapter_pers.data_days >= 14

        # 4. Save and reload verification
        loaded = trainer.load_adapter("VEHICLE_A")
        assert loaded is not None
        assert loaded.vehicle_id == "VEHICLE_A"
        assert loaded.personalization_stage == "personalized"

        # List all
        all_adapters = trainer.list_all_adapters()
        assert len(all_adapters) == 1
        assert all_adapters[0]["vehicle_id"] == "VEHICLE_A"
    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)


def test_vehicle_adapter_quality_gate():
    # Under 5 sessions -> reject
    res1 = vehicle_adapter_quality_gate({"session_count": 3, "validation_mape": 5.0})
    assert res1["promoted"] is False
    assert "ít nhất 5" in res1["reason"]

    # High MAPE (>15%) -> reject
    res2 = vehicle_adapter_quality_gate({"session_count": 10, "validation_mape": 18.5})
    assert res2["promoted"] is False
    assert "vượt ngưỡng" in res2["reason"]

    # Valid session count and low MAPE -> promote
    res3 = vehicle_adapter_quality_gate({"session_count": 10, "validation_mape": 8.2})
    assert res3["promoted"] is True
    assert "Đạt chuẩn" in res3["reason"]


def test_training_snapshot_service():
    tmp_dir = tempfile.mkdtemp()
    try:
        service = TrainingSnapshotService(storage_dir=tmp_dir)

        # Save snapshot 1
        service.save_snapshot(
            vehicle_id="VIN_001",
            version="v1",
            session_ids=["s1", "s2", "s3"],
            adapter_weights={"scale": 1.05},
            metrics={"mape": 7.5},
            feature_summary={"effective_capacity_wh": 3500.0},
        )

        # Save snapshot 2
        service.save_snapshot(
            vehicle_id="VIN_001",
            version="v2",
            session_ids=["s1", "s2", "s3", "s4", "s5"],
            adapter_weights={"scale": 1.08},
            metrics={"mape": 6.2},
            feature_summary={"effective_capacity_wh": 3480.0},
        )

        snapshots = service.get_snapshots("VIN_001")
        assert len(snapshots) == 2
        assert snapshots[0]["version"] == "v2"
        assert snapshots[1]["version"] == "v1"

        latest = service.get_latest_snapshot("VIN_001")
        assert latest is not None
        assert latest["version"] == "v2"
        assert latest["session_ids_count"] == 5
    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)


def test_run_vehicle_adapter_training_helper():
    tmp_dir = tempfile.mkdtemp()
    try:
        res = run_vehicle_adapter_training(
            vehicle_id="VIN_INTEG_01",
            sessions=[
                {
                    "start_soc": 10,
                    "target_soc": 80,
                    "actual_end_soc": 80,
                    "energy_used_wh": 2450,
                    "actual_duration_seconds": 8400,
                }
            ],
            output_dir=tmp_dir,
        )
        assert res["success"] is True
        assert res["vehicle_id"] == "VIN_INTEG_01"
        assert "adapter" in res
        assert res["adapter"]["vehicle_id"] == "VIN_INTEG_01"
    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)
