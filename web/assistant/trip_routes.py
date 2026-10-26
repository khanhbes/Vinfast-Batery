"""Trip planner places and routes through Pinova (QA 138, QA-11).

The app used to call Nominatim and the public OSRM demo server straight from
the phone. Now it asks this API: one place to switch to a production router
(``ROUTING_OSRM_URL``), one User-Agent, spacing and a cache, and the Pro gate
(``trip_estimate``) is enforced by the server, not only by the app.
"""
from __future__ import annotations

import math

from flask import Blueprint, jsonify, request

from .routing import RoutingUnavailable


def _point(raw) -> dict | None:
    if not isinstance(raw, dict):
        return None
    try:
        lat, lon = float(raw.get("lat")), float(raw.get("lon"))
    except (TypeError, ValueError):
        return None
    if not (math.isfinite(lat) and math.isfinite(lon) and -90 <= lat <= 90 and -180 <= lon <= 180):
        return None
    return {"lat": lat, "lon": lon}


def create_trip_route_blueprint(*, router, auth_resolver, entitlements=None):
    bp = Blueprint("trip_routes", __name__)

    def fail(status, code, message):
        return jsonify({"success": False, "code": code, "userMessage": message,
                        "error": {"code": code, "message": message, "userMessage": message}}), status

    def gate():
        uid, _email, _role = auth_resolver()
        if not uid:
            return None, fail(401, "unauthorized", "Cần đăng nhập")
        if entitlements is not None and not entitlements.allows(uid, "trip_estimate"):
            return None, fail(403, "premiumRequired", "Lộ trình có trong gói Pro.")
        return uid, None

    @bp.get("/api/trip/places")
    def places():
        _uid, error = gate()
        if error:
            return error
        query = str(request.args.get("q") or "").strip()
        if len(query) < 3:
            return fail(400, "queryTooShort", "Nhập ít nhất 3 ký tự để tìm địa điểm.")
        try:
            items = router.search(query[:120], limit=6)
        except RoutingUnavailable:
            return fail(503, "routingUnavailable", "Chưa tìm được địa điểm lúc này. Hãy thử lại sau.")
        return jsonify({"success": True, "data": {"items": items}})

    @bp.post("/api/trip/routes")
    def routes():
        _uid, error = gate()
        if error:
            return error
        body = request.get_json(silent=True) or {}
        origin, destination = _point(body.get("from")), _point(body.get("to"))
        if origin is None or destination is None:
            return fail(400, "invalidPoint", "Điểm đi hoặc điểm đến không hợp lệ.")
        try:
            items = router.routes(origin, destination, geometry=True)
        except RoutingUnavailable:
            return fail(503, "routingUnavailable", "Chưa tính được tuyến đường lúc này. Hãy thử lại sau.")
        if not items:
            return fail(404, "noRoute", "Không tìm thấy tuyến đường phù hợp.")
        return jsonify({"success": True, "data": {"items": items}})

    return bp
