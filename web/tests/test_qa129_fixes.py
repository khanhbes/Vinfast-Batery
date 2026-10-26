"""QA 129: server-side fixes found by the full on-device test (18/10/2026)."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

from assistant.engine import PERSONA, AssistantEngine
from assistant.knowledge import BUILTIN, KnowledgeBase
from assistant.memory import AssistantMemory
from shelly.providers.fake import FakeShellyProvider
from shelly.push_notifications import terminal_title, write_inbox_item
from shelly.repositories import SmartChargeRepository
from shelly.service import SmartChargeService


class _Doc:
    def __init__(self, store, key):
        self.store, self.key = store, key

    def get(self):
        return type("Snap", (), {"exists": self.key in self.store})()

    def set(self, data, merge=False):
        if merge and self.key in self.store:
            self.store[self.key].update(data)
        else:
            self.store[self.key] = dict(data)


class _Db:
    def __init__(self):
        self.store: dict[str, dict] = {}

    def collection(self, name):
        db = self

        class _Col:
            def document(self, key):
                return _Doc(db.store, f"{name}/{key}")
        return _Col()


def test_server_ended_session_reaches_the_inbox_once_with_the_reason():
    db = _Db()
    write_inbox_item(db, "u1", session_id="s1", state="completed", vehicle_id="car",
                     target_percent=80, stop_reason="target_reached", estimated_soc=79.4)
    item = db.store["UserNotifications/u1_sc_s1_completed"]
    assert item["title"] == "Đã sạc đến khoảng 79%"
    assert "ổ cắm đã tự ngắt" in item["message"]
    assert item["status"] == "unread" and item["userId"] == "u1"
    assert item["actionTarget"] == "/smart-charge?vehicleId=car&sessionId=s1"
    # The app already wrote the generic copy and the owner read it: the text
    # becomes precise, the read state stays.
    item["status"] = "read"
    write_inbox_item(db, "u1", session_id="s1", state="completed", stop_reason="battery_full")
    assert item["status"] == "read" and item["title"] == "Pin đã đầy"
    assert len(db.store) == 1


def test_terminal_titles_say_why():
    assert terminal_title("completed") == "Đã sạc xong theo hẹn giờ"
    assert terminal_title("completed", stop_reason="charger_idle") == "Xe đã ngừng nhận điện"
    assert terminal_title("interrupted", stop_reason="ceiling_timer") == "Đã ngắt theo giới hạn an toàn"
    assert terminal_title("cancelled") == "Đã dừng sạc"


def test_reading_moves_the_battery_timestamp_so_an_older_charge_cannot_overwrite_it():
    written = []

    class Repo(SmartChargeRepository):
        def update_vehicle_fields(self, uid, vehicle_id, fields):
            written.append(fields)

    repo = Repo()
    provider = FakeShellyProvider()
    repo.register_vehicle_owner("owner", "car", verified_capacity_wh=2340)
    service = SmartChargeService(repo, provider, None, sleeper=lambda _: None)
    service.add_battery_reading("owner", "car", {"soc": 64, "source": "chat"})
    fields = written[-1]
    assert fields["currentBattery"] == 64
    assert isinstance(fields["batteryDataUpdatedAt"], datetime)
    assert fields["batteryDataSource"] == "reading_chat"


def _engine(history):
    now = datetime(2026, 10, 18, 4, 0, tzinfo=timezone.utc)
    return AssistantEngine(gemini=None, knowledge=KnowledgeBase(), memory=AssistantMemory(),
                           history_reader=lambda uid, vehicle, limit: history, clock=lambda: now)


def _session(day, hour, wh, minutes, state="completed"):
    start = datetime(2026, day[0], day[1], hour, 0, tzinfo=timezone.utc)
    return {"state": state, "created_at": start.isoformat(),
            "stopped_at": (start + timedelta(minutes=minutes)).isoformat(), "energy_used_wh": wh}


def test_month_summary_matches_the_history_tab():
    history = [_session((10, 17), 4, 576, 77), _session((10, 16), 11, 886, 120),
               _session((9, 12), 3, 1560, 300), _session((10, 18), 2, 0.2, 3, state="active")]
    eng = _engine(history)
    october = eng._run_server_tool("u1", "get_charging_summary", {}, {"vehicleId": "car"}, {})
    assert october["month"] == "10/2026" and october["sessions"] == 2
    assert october["energyKwh"] == 1.46 and october["chargingTime"] == "3 giờ 17 phút"
    september = eng._run_server_tool("u1", "get_charging_summary", {"month": "2026-09"}, {}, {})
    assert september["sessions"] == 1 and september["energyWh"] == 1560


def test_bot_knows_training_is_owner_triggered_and_keeps_safe_requests_actionable():
    learning = next(entry for entry in BUILTIN if entry["id"] == "charge-learning")
    assert "Huấn luyện" in learning["body"] and "học ngay" not in learning["body"]
    assert "VẪN gọi hàm hành động" in PERSONA and "bên dưới" in PERSONA
    assert "get_charging_summary" in PERSONA and "dấu chấm" in PERSONA


class _VehicleDb:
    """Just enough Firestore for ``upsert_charge_log``."""

    def __init__(self, vehicles):
        self.docs = {f"Vehicles/{key}": dict(value) for key, value in vehicles.items()}

    def collection(self, name):
        db = self

        class _Ref:
            def __init__(self, key):
                self.key = key

            def get(self):
                data = db.docs.get(self.key)
                return type("Snap", (), {"exists": data is not None,
                                         "to_dict": lambda _self: dict(data or {})})()

            def set(self, data, merge=False):
                base = db.docs.get(self.key, {}) if merge else {}
                db.docs[self.key] = {**base, **data}

        class _Col:
            def document(self, key):
                return _Ref(f"{name}/{key}")
        return _Col()


def test_a_no_load_test_session_does_not_relabel_the_battery_reading():
    """QA 130: the 02:44 ON/OFF test (0.21 Wh) turned the owner's typed 79 %
    into "Ước tính sau phiên sạc · lúc 02:44"."""
    repo = SmartChargeRepository()
    provider = FakeShellyProvider()
    binding = provider.list_devices("owner")[0]
    binding.vehicle_id = "car"
    repo.register_vehicle_owner("owner", "car", verified_capacity_wh=2340)
    repo.save_binding("owner", binding)
    repo.claim_worker_lease("qa-worker")
    repo.publish_worker_heartbeat("qa-worker", healthy=True)
    service = SmartChargeService(repo, provider, None, sleeper=lambda _: None)
    session = service.manual_on("owner", 1800, "qa130-test", vehicle_id="car", current_soc=79)
    session = service.stop("owner", session.session_id)
    assert session.energy_used_wh < 30
    db = _VehicleDb({"car": {"ownerUid": "owner", "currentBattery": 79,
                             "batteryDataSource": "reading_chat"}})
    repo.db = db
    repo.upsert_charge_log("owner", session)
    assert db.docs["Vehicles/car"]["batteryDataSource"] == "reading_chat"
    # A real charge still advances the vehicle reading.
    session.energy_used_wh = 576
    session.estimated_soc = 100.0
    repo.upsert_charge_log("owner", session)
    assert db.docs["Vehicles/car"]["batteryDataSource"] == "smart_charge_estimated"
    assert db.docs["Vehicles/car"]["currentBattery"] == 100
