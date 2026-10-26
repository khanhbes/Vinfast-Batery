"""QA 138 review (26/10/2026), Medium findings.

QA-06: a night plan that cannot start is not a safety event: a normal push,
a plain reason, and a plan that ends before the night start is refused when
it is armed (not discovered at 3 a.m.). QA-07: the "train now" nudge only
for a plan that can train. QA-09: newest support tickets first, and every
armed night plan is seen however many there are.
"""
from __future__ import annotations

from datetime import datetime, timedelta

import pytest

from billing.entitlements import EntitlementService
from shelly import night
from shelly.service import SmartChargeError
from support.tickets import SupportService
from tests.test_qa135_night_charging import _at, _clock_at, _due
from tests.test_task126_charge_model import _service


def _ultra_until(service, clock, expires):
    plans = EntitlementService(enforced=True, clock=lambda: clock.now)
    plans._local["owner"] = {"tier": "ultra", "status": "trial", "expiresAt": expires}
    service.entitlements = plans
    return plans


def test_a_plan_ending_before_the_night_start_is_refused_when_armed():
    service, _repo, _provider, clock = _service()
    _clock_at(clock, _at(22))
    _ultra_until(service, clock, _at(1, day=26))  # trial ends at 01:00
    with pytest.raises(SmartChargeError) as caught:
        service.arm_night_plan("owner", "car", {"wakeAt": "06:30", "currentSoc": 30, "confirmed": True})
    assert caught.value.code == "planEndsBeforeStart"
    assert "01:00" in caught.value.message and "Sạc hẹn giờ" in caught.value.message


def test_a_plan_that_ended_meanwhile_cancels_quietly_with_a_reason():
    service, _repo, provider, clock = _service()
    alerts = []
    service.night_alert = lambda uid, **kw: alerts.append(kw)
    _clock_at(clock, _at(22))
    plans = _ultra_until(service, clock, _at(22, day=30))
    plan = service.arm_night_plan("owner", "car", {"wakeAt": "06:30", "currentSoc": 30, "confirmed": True})
    plans._local["owner"]["expiresAt"] = _at(23)  # revoked / ended after arming
    plans._cache.clear()
    _clock_at(clock, datetime.fromisoformat(plan["startAt"].replace("Z", "+00:00")) + timedelta(minutes=1))
    assert _due(service) == 0
    assert provider.status.relay is False
    assert service.night_plan("owner", "car")["state"] == "cancelled"
    assert alerts and alerts[0]["title"] == "Sạc đêm đã hủy"
    assert "cần gói" not in alerts[0]["body"]


def test_an_other_charge_running_skips_the_night_plan():
    service, _repo, provider, clock = _service()
    alerts = []
    service.night_alert = lambda uid, **kw: alerts.append(kw["title"])
    _clock_at(clock, _at(22))
    plan = service.arm_night_plan("owner", "car", {"wakeAt": "06:30", "currentSoc": 30, "confirmed": True})
    start = datetime.fromisoformat(plan["startAt"].replace("Z", "+00:00"))
    _clock_at(clock, start - timedelta(minutes=30))
    preview = service.create_preview("owner", {"vehicleId": "car", "currentSoc": 30, "targetSoc": 60,
                                               "historyPowerW": 440})
    service.repository.claim_worker_lease("qa-worker", now=clock.now)
    service.repository.publish_worker_heartbeat("qa-worker", healthy=True, now=clock.now)
    service.start("owner", preview.preview_id, "manual-1")
    _clock_at(clock, start + timedelta(minutes=1))
    _due(service)
    assert service.night_plan("owner", "car")["state"] == "skipped"
    assert alerts == ["Sạc đêm không bật"]


def test_night_alerts_never_use_the_alarm_channel():
    import inspect

    import server
    from shelly import worker_runtime
    for source in (inspect.getsource(worker_runtime), inspect.getsource(server)):
        start = source.index("night_alert")
        block = source[start:start + 900]
        assert "urgent=True" not in block and "'urgent': '1'" not in block and '"urgent": "1"' not in block


def test_train_nudge_only_when_the_plan_can_train():
    service, _repo, _provider, clock = _service()
    assert service.learning_status("owner", "car")["trainAllowed"] is True  # no billing: all on
    service.entitlements = EntitlementService(enforced=True, clock=lambda: clock.now)
    assert service.learning_status("owner", "car")["trainAllowed"] is False  # Free
    _ultra_until(service, clock, clock.now + timedelta(days=7))
    assert service.learning_status("owner", "car")["trainAllowed"] is True


class _Snap:
    def __init__(self, db, collection, doc_id):
        self.id, self._data = doc_id, db.docs.get((collection, doc_id))
        self.reference = _Ref(db, collection, doc_id)

    @property
    def exists(self):
        return self._data is not None

    def to_dict(self):
        return dict(self._data) if self._data is not None else None


class _Ref:
    def __init__(self, db, collection, doc_id):
        self.db, self.collection, self.id = db, collection, doc_id

    def get(self):
        return _Snap(self.db, self.collection, self.id)

    def set(self, data):
        self.db.docs[(self.collection, self.id)] = dict(data)

    def create(self, data):
        assert (self.collection, self.id) not in self.db.docs
        self.set(data)


class _Query:
    """Firestore semantics that matter here: without order_by the results
    come by document id ascending; limit cuts after ordering."""

    def __init__(self, db, collection, filters=(), order=None, cap=None, after=None):
        self.db, self.collection = db, collection
        self.filters, self.order, self.cap, self.after = filters, order, cap, after

    def _copy(self, **kw):
        values = dict(filters=self.filters, order=self.order, cap=self.cap, after=self.after)
        values.update(kw)
        return _Query(self.db, self.collection, **values)

    def where(self, field, op, value):
        assert op == "=="
        return self._copy(filters=self.filters + ((field, value),))

    def order_by(self, field, direction="ASCENDING"):
        return self._copy(order=(field, direction == "DESCENDING"))

    def limit(self, n):
        return self._copy(cap=n)

    def start_after(self, snapshot):
        assert self.order is None
        return self._copy(after=snapshot.id)

    def document(self, doc_id):
        return _Ref(self.db, self.collection, doc_id)

    def stream(self):
        ids = sorted(i for c, i in self.db.docs if c == self.collection)
        rows = [i for i in ids if all(self.db.docs[(self.collection, i)].get(f) == v for f, v in self.filters)]
        if self.order:
            field, desc = self.order
            rows.sort(key=lambda i: str(self.db.docs[(self.collection, i)].get(field)), reverse=desc)
        if self.after is not None:
            rows = [i for i in rows if i > self.after]
        for i in rows[: self.cap]:
            yield _Snap(self.db, self.collection, i)


class _Db:
    def __init__(self):
        self.docs = {}

    def collection(self, name):
        return _Query(self, name)


def _ticket(support, uid, day):
    support.clock = lambda: datetime(2026, 10, day, 9, 0, tzinfo=night.VN)
    return support.create(uid, f"{uid}@example.com",
                          {"subject": f"Hỏi ngày {day}", "message": "Ổ sạc không bật được."})


def test_newest_tickets_first_even_past_the_page_size(monkeypatch):
    import support.tickets as tickets
    support = SupportService(db=_Db())
    for day in range(1, 11):
        _ticket(support, f"u{day}", day)
    monkeypatch.setattr(tickets, "ADMIN_PAGE", 3)
    rows = support.admin_list()
    assert [r["subject"] for r in rows] == ["Hỏi ngày 10", "Hỏi ngày 9", "Hỏi ngày 8"]


def test_a_user_sees_their_newest_tickets():
    support = SupportService(db=_Db())
    for day in (3, 1, 2):
        _ticket(support, "owner", day)
    _ticket(support, "someone", 4)
    assert [r["subject"] for r in support.mine("owner")] == ["Hỏi ngày 3", "Hỏi ngày 2", "Hỏi ngày 1"]


def test_every_armed_plan_is_seen_page_by_page():
    store = night.NightPlanStore(_Db())
    for i in range(450):
        store.put({"uid": f"u{i:03d}", "vehicleId": "car", "state": "armed"})
    store.put({"uid": "done", "vehicleId": "car", "state": "started"})
    rows = store.armed(page=200)
    assert len(rows) == 450 and len({r["uid"] for r in rows}) == 450


def test_newest_promo_codes_first():
    from billing.promos import PromoService
    promos = PromoService(db=_Db())
    for i, code in enumerate(["AAAA1", "ZZZZ9", "MMMM5"]):
        promos.clock = lambda i=i: datetime(2026, 10, 1 + i, 9, 0, tzinfo=night.VN)
        promos.create({"code": code, "percentOff": 10, "validTo": "2031-01-01T00:00:00+07:00"})
    assert [p["code"] for p in promos.list(limit=2)] == ["MMMM5", "ZZZZ9"]


def test_replies_a_day_are_capped():
    from support.tickets import SupportError
    support = SupportService()
    ticket = _ticket(support, "owner", 5)
    for _ in range(10):
        support.user_reply("owner", ticket["id"], "Thêm thông tin.")
    with pytest.raises(SupportError) as caught:
        support.user_reply("owner", ticket["id"], "Lần thứ 11.")
    assert caught.value.code == "replyQuota"
    support.clock = lambda: datetime(2026, 10, 6, 9, 0, tzinfo=night.VN)
    support.user_reply("owner", ticket["id"], "Hôm sau.")


def test_email_sent_is_the_real_result():
    from tests.test_qa135_support import FakeHttp, mailer
    failing = SupportService(mailer=mailer(FakeHttp(status=500)))
    assert _ticket(failing, "owner", 5)["id"] and failing.admin_list()[0]["emailSent"] is False
    working = SupportService(mailer=mailer(FakeHttp(status=202)))
    _ticket(working, "owner", 5)
    assert working.admin_list()[0]["emailSent"] is True


# -- QA-11: the trip planner goes through the Pinova API ---------------------
class _Router:
    def __init__(self, fail=False):
        self.fail, self.calls = fail, []

    def search(self, query, limit=6):
        from assistant.routing import RoutingUnavailable
        self.calls.append(("search", query, limit))
        if self.fail:
            raise RoutingUnavailable("geocodeFailed")
        return [{"name": "Hồ Gươm", "lat": 21.03, "lon": 105.85}]

    def routes(self, origin, destination, geometry=False):
        self.calls.append(("routes", origin, destination, geometry))
        return [{"km": 12.5, "minutes": 31.0, "geometry": [[21.03, 105.85], [21.0, 105.8]]}]


def _trip_app(router, uid="owner", tier="pro"):
    from flask import Flask

    from assistant.trip_routes import create_trip_route_blueprint
    plans = EntitlementService(enforced=True)
    if tier != "free":
        plans.grant("owner", tier, period="month")
    app = Flask(__name__)
    app.register_blueprint(create_trip_route_blueprint(
        router=router, auth_resolver=lambda: (uid, None, "user"), entitlements=plans))
    return app.test_client()


def test_trip_places_and_routes_for_pro():
    router = _Router()
    client = _trip_app(router)
    places = client.get("/api/trip/places?q=Hồ Gươm").get_json()
    assert places["data"]["items"][0]["name"] == "Hồ Gươm"
    response = client.post("/api/trip/routes", json={"from": {"lat": 21.03, "lon": 105.85},
                                                     "to": {"lat": 21.0, "lon": 105.8}})
    assert response.status_code == 200
    assert response.get_json()["data"]["items"][0]["geometry"][0] == [21.03, 105.85]
    assert router.calls[-1][3] is True  # the map needs the road shape


def test_trip_routes_are_pro_on_the_server():
    router = _Router()
    assert _trip_app(router, tier="free").get("/api/trip/places?q=Hồ Gươm").status_code == 403
    assert _trip_app(router, uid=None).get("/api/trip/places?q=Hồ Gươm").status_code == 401
    assert not router.calls


def test_trip_routes_reject_bad_input_and_report_outages():
    client = _trip_app(_Router())
    assert client.get("/api/trip/places?q=Hồ").status_code == 400
    for body in ({}, {"from": {"lat": 91, "lon": 1}, "to": {"lat": 1, "lon": 1}},
                 {"from": {"lat": "x", "lon": 1}, "to": {"lat": 1, "lon": 1}}):
        assert client.post("/api/trip/routes", json=body).status_code == 400
    down = _trip_app(_Router(fail=True)).get("/api/trip/places?q=Hồ Gươm")
    assert down.status_code == 503 and down.get_json()["code"] == "routingUnavailable"


def test_router_returns_shapes_and_caches_routes():
    from assistant.routing import OsmRouter

    class _Response:
        def __init__(self, data):
            self.data = data

        def raise_for_status(self):
            return None

        def json(self):
            return self.data

    class _Session:
        def __init__(self):
            self.calls = []

        def get(self, url, params=None, **_):
            self.calls.append((url, params))
            if "route" in url:
                return _Response({"routes": [{"distance": 12500, "duration": 1860,
                                              "geometry": {"coordinates": [[105.85, 21.03], [105.8, 21.0]]}}]})
            return _Response([{"display_name": "A", "lat": "1", "lon": "2"},
                              {"display_name": "B", "lat": "3", "lon": "4"}])

    session = _Session()
    router = OsmRouter(session=session, clock=lambda: 100.0, sleeper=lambda _s: None)
    assert [p["name"] for p in router.search("Hồ Gươm", limit=6)] == ["A", "B"]
    first = router.routes({"lat": 21.03, "lon": 105.85}, {"lat": 21.0, "lon": 105.8}, geometry=True)
    again = router.routes({"lat": 21.03, "lon": 105.85}, {"lat": 21.0, "lon": 105.8}, geometry=True)
    assert first == again and first[0]["km"] == 12.5 and first[0]["geometry"][0] == [21.03, 105.85]
    route_calls = [c for c in session.calls if "route" in c[0]]
    assert len(route_calls) == 1 and route_calls[0][1]["geometries"] == "geojson"
