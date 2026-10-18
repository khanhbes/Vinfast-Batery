"""Task 126: BatteryBot trip and charge estimates (fake Gemini + fake OSM)."""
from __future__ import annotations

import pytest

from assistant.engine import AssistantEngine, validate_action
from assistant.knowledge import KnowledgeBase
from assistant.memory import AssistantMemory
from assistant.routing import OsmRouter


class FakeGemini:
    configured = True
    model = "fake"

    def __init__(self, script):
        self.script = list(script)
        self.calls = []

    def generate(self, *, system, contents, tools=None, **_):
        self.calls.append({"system": system, "contents": contents, "tools": [t["name"] for t in tools or []]})
        return self.script.pop(0) if self.script else [{"text": "ok"}]


class FakeRouter:
    def __init__(self):
        self.queries = []

    def geocode(self, query):
        self.queries.append(query)
        return {"name": f"{query}, Hà Nội", "lat": 21.0, "lon": 105.8} if query != "nowhere" else None

    def routes(self, origin, destination):
        return [{"km": 18.0, "minutes": 35.0}, {"km": 16.2, "minutes": 40.0}]


CONTEXT = {"vehicleId": "v1", "vehicle": {"name": "Feliz", "batteryPercent": 30, "kmPerPercent": 0.9,
                                           "sohPercent": 100}}


def _engine(script, **kwargs):
    return AssistantEngine(gemini=FakeGemini(script), knowledge=KnowledgeBase(), memory=AssistantMemory(),
                           **kwargs)


def _trip_call(**args):
    return [{"functionCall": {"name": "estimate_trip", "args": args}}]


def test_trip_question_routes_through_osm_and_returns_a_card():
    router = FakeRouter()
    eng = _engine([_trip_call(origin="Hồ Gươm", destination="Sân bay Nội Bài", round_trip=True),
                   [{"text": "Không đủ pin cho khứ hồi; bạn nên sạc trước."}]], router=router)
    result = eng.chat("u1", "đi Nội Bài rồi về được không", [], CONTEXT)
    assert router.queries == ["Hồ Gươm", "Sân bay Nội Bài"]
    card = result["card"]
    assert card["cardType"] == "trip_plan"
    data = card["data"]
    # 18 km x 2 at 0.882/0.9 %/km x1.014 (21 km/h solo, Task 127 shape)
    # = 35.8 % from 30 %: not enough, charge first.
    assert data["usePct"] == pytest.approx(35.8)
    assert data["verdict"] == "insufficient"
    assert data["kmPerPctSource"] == "catalog"
    assert any(item["kind"] == "shorter_route" for item in data["suggestions"])
    assert data["isEstimate"] is True
    # The tool result reached the model for its answer.
    tool_turn = eng.gemini.calls[1]["contents"][-1]["parts"][0]["functionResponse"]
    assert tool_turn["name"] == "estimate_trip"


def test_trip_without_origin_asks_instead_of_guessing():
    eng = _engine([_trip_call(destination="Nội Bài"), [{"text": "Bạn đi từ đâu?"}]], router=FakeRouter())
    result = eng.chat("u1", "đi Nội Bài được không", [], CONTEXT)
    response = eng.gemini.calls[1]["contents"][-1]["parts"][0]["functionResponse"]["response"]
    assert response["error"] == "originRequired"
    assert "card" not in result


def test_trip_needs_a_battery_reading():
    context = {"vehicleId": "v1", "vehicle": {"name": "Feliz", "kmPerPercent": 0.9}}
    eng = _engine([_trip_call(distance_km=10), [{"text": "Pin đang bao nhiêu %?"}]])
    eng.chat("u1", "đi 10 km được không", [], context)
    response = eng.gemini.calls[1]["contents"][-1]["parts"][0]["functionResponse"]["response"]
    assert response["error"] == "batteryUnknown"


def test_trip_uses_the_learned_km_per_percent():
    history = [
        {"stopped_at": "2026-09-01T10:00:00+00:00", "start_soc": 20, "actual_end_soc": 90, "end_odo_km": 1000},
        {"stopped_at": "2026-09-04T10:00:00+00:00", "start_soc": 30, "actual_end_soc": 85, "end_odo_km": 1054},
        {"stopped_at": "2026-09-07T10:00:00+00:00", "start_soc": 25, "actual_end_soc": 80, "end_odo_km": 1111},
    ]
    eng = _engine([_trip_call(distance_km=9.25), [{"text": "ok"}]],
                  history_reader=lambda uid, vehicle_id, limit: history)
    result = eng.chat("u1", "đi 9 km", [], CONTEXT)
    data = result["card"]["data"]
    assert data["kmPerPctSource"] == "odo" and data["learnedPairs"] == 2
    # 9.25 km / 0.925 km per % (mixed riding) x 0.882 x 1.014 (21 km/h solo).
    assert data["usePct"] == pytest.approx(8.9)


def test_trip_prefers_the_trained_trip_model():
    trained = {"refPctPerKm": 0.6, "speed": 0.0, "speed2": 0.0, "loadPer10Kg": 0.0,
               "rain": 0.0, "source": "model", "samples": 40, "spread": 0.1, "mae": 0.5}
    eng = _engine([_trip_call(distance_km=10), [{"text": "ok"}]],
                  trip_params_reader=lambda uid, vehicle_id: trained)
    data = eng.chat("u1", "đi 10 km", [], CONTEXT)["card"]["data"]
    assert data["kmPerPctSource"] == "model"
    assert data["usePct"] == pytest.approx(6.0)
    assert data["useHighPct"] == pytest.approx(6.6)


def test_charge_estimate_uses_the_injected_model():
    seen = {}

    def estimator(uid, vehicle_id, current, target, history_power):
        seen.update(uid=uid, vehicle=vehicle_id, current=current, target=target, power=history_power)
        return {"minutes": 110, "learnedSamples": 2, "socMae": 0.8}

    history = [{"average_power_w": 440}, {"average_power_w": 430}]
    eng = _engine([[{"functionCall": {"name": "estimate_charge", "args": {"to_soc": 80}}}],
                   [{"text": "Khoảng 1 giờ 50 phút."}]],
                  charge_estimator=estimator, history_reader=lambda *_: history)
    eng.chat("u1", "sạc lên 80% mất bao lâu", [], CONTEXT)
    assert seen == {"uid": "u1", "vehicle": "v1", "current": 30.0, "target": 80.0, "power": 435}


def test_target_charging_is_only_prepared_never_started():
    eng = _engine([[{"text": "Mình mở tab Sạc."},
                    {"functionCall": {"name": "prepare_target_charging", "args": {"percent": 80}}}]])
    result = eng.chat("u1", "sạc đến 80%", [], CONTEXT)
    assert result["actions"] == [{"name": "prepare_target_charging", "args": {"percent": 80}}]
    assert validate_action("prepare_target_charging", {"percent": 30}, CONTEXT) is None


def test_plan_trip_action_is_clamped():
    args = validate_action("plan_trip", {"destination": "Nội Bài", "distance_km": 5000, "passengers": 7,
                                         "speed": "warp", "round_trip": True}, CONTEXT)
    assert args["destination"] == "Nội Bài"
    assert "distance_km" not in args
    assert args["riders"] == 1 and args["speed"] == "normal" and args["round_trip"] is True


def test_osm_router_caches_and_spaces_requests():
    class _Response:
        def __init__(self, data):
            self.data = data

        def raise_for_status(self):
            return None

        def json(self):
            return self.data

    class _Session:
        def __init__(self):
            self.calls = 0

        def get(self, url, **_):
            self.calls += 1
            return _Response([{"display_name": "Hồ Gươm", "lat": "21.03", "lon": "105.85"}])

    sleeps = []
    clock = iter([0.0, 0.0, 0.5, 0.5, 2.0, 2.0])
    session = _Session()
    router = OsmRouter(session=session, clock=lambda: next(clock), sleeper=sleeps.append)
    assert router.geocode("Hồ Gươm")["lat"] == pytest.approx(21.03)
    assert router.geocode("hồ  gươm")["lon"] == pytest.approx(105.85)  # cache hit
    router.geocode("Nội Bài")
    assert session.calls == 2
    assert sleeps and sleeps[0] > 0
