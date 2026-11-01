"""QA 141: trip-planner map tiles through Pinova (OpenStreetMap is blocked
by Vietnamese carriers, so the map was black)."""
from __future__ import annotations

import requests
from flask import Flask

from assistant.routing import RoutingUnavailable, TileProxy
from assistant.trip_routes import create_trip_route_blueprint
from billing.entitlements import EntitlementService


class _Response:
    def __init__(self, body=b"PNG", status=200):
        self.content, self.status_code = body, status

    def raise_for_status(self):
        if self.status_code >= 400:
            raise requests.HTTPError(str(self.status_code))


class _Session:
    def __init__(self, status=200):
        self.status, self.urls = status, []

    def get(self, url, headers=None, timeout=None):
        self.urls.append((url, headers))
        return _Response(status=self.status)


def _app(tiles, uid="owner", tier="pro"):
    plans = EntitlementService(enforced=True)
    if tier != "free":
        plans.grant("owner", tier, period="month")
    app = Flask(__name__)
    app.register_blueprint(create_trip_route_blueprint(
        router=object(), auth_resolver=lambda: (uid, None, "user"), entitlements=plans, tiles=tiles))
    return app.test_client()


def test_a_tile_is_fetched_once_with_pinova_user_agent_and_cached():
    session = _Session()
    tiles = TileProxy(session=session, url="https://tiles.example/{z}/{x}/{y}.png")
    client = _app(tiles)
    first = client.get("/api/trip/tiles/12/3251/1800.png")
    assert first.status_code == 200 and first.data == b"PNG"
    assert first.mimetype == "image/png" and "max-age" in first.headers["Cache-Control"]
    client.get("/api/trip/tiles/12/3251/1800.png")
    assert len(session.urls) == 1
    url, headers = session.urls[0]
    assert url == "https://tiles.example/12/3251/1800.png" and "Pinova" in headers["User-Agent"]


def test_tiles_are_pro_signed_in_and_valid():
    session = _Session()
    tiles = TileProxy(session=session)
    assert _app(tiles, uid=None).get("/api/trip/tiles/1/0/0.png").status_code == 401
    assert _app(tiles, tier="free").get("/api/trip/tiles/1/0/0.png").status_code == 403
    assert _app(tiles).get("/api/trip/tiles/2/4/0.png").status_code == 400
    assert _app(tiles).get("/api/trip/tiles/20/0/0.png").status_code == 400
    assert not session.urls


def test_an_upstream_failure_is_a_503_not_a_broken_image():
    tiles = TileProxy(session=_Session(status=502))
    response = _app(tiles).get("/api/trip/tiles/3/1/1.png")
    assert response.status_code == 503
    assert response.get_json()["code"] == "tileUnavailable"
    try:
        tiles.tile(3, 1, 1)
    except RoutingUnavailable:
        pass
    else:
        raise AssertionError("expected RoutingUnavailable")
