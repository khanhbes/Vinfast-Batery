"""OpenStreetMap place search and road distance for BatteryBot (Task 126)
and, since QA 138, the trip planner (the app no longer calls OSM itself).

Nominatim allows about one request per second with an identifying
User-Agent, so calls are serialized, spaced and cached. Only place names the
user typed are sent; never the phone's location. The services are set by
``ROUTING_NOMINATIM_URL`` / ``ROUTING_OSRM_URL`` (QA 138: the public OSRM
demo server is not meant for production; point this at a self-hosted OSRM
or a paid router without touching the app).
"""

from __future__ import annotations

import os
import threading
import time
from collections import OrderedDict

import requests

_HEADERS = {"User-Agent": "Pinova/1.3 (app com.bes.vinbatery; trip planner and Pinova Bot; server vinfast-api)",
            "Accept-Language": "vi,en;q=0.8"}
_NOMINATIM = os.environ.get("ROUTING_NOMINATIM_URL", "").strip() or "https://nominatim.openstreetmap.org/search"
_OSRM_BASE = (os.environ.get("ROUTING_OSRM_URL", "").strip() or "https://router.project-osrm.org").rstrip("/")
_OSRM = _OSRM_BASE + "/route/v1/driving/{a};{b}"
_MIN_INTERVAL = 1.1
_CACHE_SIZE = 256


class RoutingUnavailable(RuntimeError):
    pass


def _key(query) -> str:
    return " ".join(str(query or "").lower().split())[:120]


class OsmRouter:
    def __init__(self, session: requests.Session | None = None, clock=time.monotonic, sleeper=time.sleep):
        self._http = session or requests.Session()
        self._clock = clock
        self._sleep = sleeper
        self._lock = threading.Lock()
        self._last = 0.0
        self._cache: OrderedDict[str, object] = OrderedDict()

    def _remember(self, key: str, value):
        self._cache[key] = value
        while len(self._cache) > _CACHE_SIZE:
            self._cache.popitem(last=False)
        return value

    def _cached(self, key: str):
        if key in self._cache:
            self._cache.move_to_end(key)
            return True, self._cache[key]
        return False, None

    def _space(self) -> None:
        """One request a second to the public services (call under the lock)."""
        wait = _MIN_INTERVAL - (self._clock() - self._last)
        if wait > 0:
            self._sleep(wait)
        self._last = self._clock()

    def search(self, query: str, limit: int = 6) -> list[dict]:
        """Up to ``limit`` Vietnamese places ``{"name", "lat", "lon"}``."""
        key = _key(query)
        if len(key) < 3:
            return []
        limit = max(1, min(int(limit), 6))
        with self._lock:
            hit, value = self._cached(f"search:{limit}:{key}")
            if hit:
                return list(value)
            self._space()
            try:
                response = self._http.get(_NOMINATIM, headers=_HEADERS, timeout=8, params={
                    "q": key, "format": "jsonv2", "limit": limit, "countrycodes": "vn"})
                response.raise_for_status()
                rows = response.json()
            except (requests.RequestException, ValueError) as error:
                raise RoutingUnavailable("geocodeFailed") from error
            places = []
            for row in rows or []:
                try:
                    places.append({"name": str(row.get("display_name") or key)[:160],
                                   "lat": float(row["lat"]), "lon": float(row["lon"])})
                except (KeyError, TypeError, ValueError):
                    continue
            return list(self._remember(f"search:{limit}:{key}", places))

    def geocode(self, query: str) -> dict | None:
        """``{"name", "lat", "lon"}`` for a Vietnamese place, or ``None``."""
        places = self.search(query, limit=1)
        return places[0] if places else None

    def routes(self, origin: dict, destination: dict, geometry: bool = False) -> list[dict]:
        """Fastest route first, then up to two alternatives: km and minutes,
        and the road shape as ``[[lat, lon], ...]`` when ``geometry``."""
        a = f"{float(origin['lon']):.5f},{float(origin['lat']):.5f}"
        b = f"{float(destination['lon']):.5f},{float(destination['lat']):.5f}"
        key = f"route:{int(geometry)}:{a};{b}"
        with self._lock:
            hit, value = self._cached(key)
            if hit:
                return list(value)
            self._space()
            params = {"overview": "full" if geometry else "false", "alternatives": "true", "steps": "false"}
            if geometry:
                params["geometries"] = "geojson"
            try:
                response = self._http.get(_OSRM.format(a=a, b=b), headers=_HEADERS, timeout=10, params=params)
                response.raise_for_status()
                rows = response.json().get("routes") or []
            except (requests.RequestException, ValueError) as error:
                raise RoutingUnavailable("routeFailed") from error
            result = []
            for row in rows[:3]:
                item = {"km": float(row["distance"]) / 1000, "minutes": float(row["duration"]) / 60}
                if geometry:
                    coords = ((row.get("geometry") or {}).get("coordinates") or [])
                    item["geometry"] = [[round(float(p[1]), 6), round(float(p[0]), 6)] for p in coords]
                result.append(item)
            return list(self._remember(key, result))
