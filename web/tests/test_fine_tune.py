import os
import shutil
import tempfile
import sys
from ai_server.fine_tune import run_fine_tuning, extract_features_from_session


def test_extract_features():
    session = {
        "start_soc": 20,
        "target_soc": 80,
        "actual_end_soc": 80,
        "actual_duration_seconds": 3600,
        "ambient_temp_start_c": 32,
    }
    res = extract_features_from_session(session)
    assert res is not None
    features, duration = res
    assert len(features) == 6
    assert features[0] == 20
    assert features[1] == 80
    assert features[2] == 60
    assert duration == 3600
    assert features[4] == 22.5
    other_features, other_duration = extract_features_from_session({**session, "actual_duration_seconds": 7200})
    assert other_features == features  # No target-duration leakage.
    assert other_duration != duration


def test_fine_tune_pipeline(monkeypatch):
    monkeypatch.setenv("ENABLE_TF_CONVERTER", "false")
    tmp_dir = tempfile.mkdtemp()
    try:
        sessions = [
            {
                "start_soc": 20,
                "target_soc": 80,
                "actual_end_soc": 80,
                "actual_duration_seconds": 3600,
                "ambient_temp_start_c": 30,
            },
            {
                "start_soc": 30,
                "target_soc": 70,
                "actual_end_soc": 70,
                "actual_duration_seconds": 2400,
                "ambient_temp_start_c": 28,
            },
        ]
        result = run_fine_tuning(sessions, tmp_dir, new_version="test_v1")
        assert result["success"] is True
        assert result["version"] == "test_v1"
        assert os.path.exists(result["joblibPath"])
        assert result["tflitePath"] is None
        assert result["tfliteGenerated"] is False
        assert result["mobileExportStatus"] == "unavailable"
        assert not os.path.exists(os.path.join(tmp_dir, "test_v1.tflite"))
        assert "mape" in result["metrics"]
        assert "rmseSeconds" in result["metrics"]
        monkeypatch.setenv("ENABLE_TF_CONVERTER", "true")
        monkeypatch.setitem(sys.modules, "tensorflow", None)
        failed_export = run_fine_tuning(sessions, tmp_dir, new_version="no_converter")
        assert failed_export["success"] is True  # Server joblib remains valid.
        assert failed_export["tfliteGenerated"] is False
        assert failed_export["tflitePath"] is None
        assert not os.path.exists(os.path.join(tmp_dir, "no_converter.tflite"))
    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)
