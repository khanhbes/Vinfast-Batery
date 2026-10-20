"""OpenStreetMap place search and road distance for BatteryBot (Task 126).

Nominatim allows about one request per second with an identifying
User-Agent, so calls are serialized, spaced and cached. Only place names the
user typed are sent; never the phone's location.
"""

from __future__ import annotations

import threading
import time
from collections import OrderedDict

import requests

_HEADERS = {"User-Agent": "Pinova/1.3 (app com.bes.vinbatery; Pinova Bot trip estimate; server vinfast-api)",
            "Accept-Language": "vi,en;q=0.8"}
_NOMINATIM = "https://nominatim.openstreetmap.org/search"
_OSRM = "https://router.project-osrm.org/route/v1/driving/{a};{b}"
_MIN_INTERVAL = 1.1
_CACHE_SIZE = 256


class RoutingUnavailable(RuntimeError):
    pass


class OsmRouter:
    def __init__(self, session: requests.Session | None = None, clock=time.monotonic, sleeper=time.sleep):
        self._http = session or requests.Session()
        self._clock = clock
        self._sleep = sleeper
        self._lock = threading.Lock()
        self._last = 0.0
        self._cache: OrderedDict[str, dict | None] = OrderedDict()

    def geocode(self, query: str) -> dict | None:
        """``{"name", "lat", "lon"}`` for a Vietnamese place, or ``None``."""
        key = " ".join(str(query or "").lower().split())[:120]
        if len(key) < 3:
            return None
        with self._lock:
            if key in self._cache:
                self._cache.move_to_end(key)
                return self._cache[key]
            wait = _MIN_INTERVAL - (self._clock() - self._last)
            if wait > 0:
                self._sleep(wait)
            self._last = self._clock()
            try:
                response = self._http.get(_NOMINATIM, headers=_HEADERS, timeout=8, params={
                    "q": key, "format": "jsonv2", "limit": 1, "countrycodes": "vn"})
                response.raise_for_status()
                rows = response.json()
            except (requests.RequestException, ValueError) as error:
                raise RoutingUnavailable("geocodeFailed") from error
            place = None
            if rows:
                row = rows[0]
                place = {"name": str(row.get("display_name") or key)[:160],
                         "lat": float(row["lat"]), "lon": float(row["lon"])}
            self._cache[key] = place
            while len(self._cache) > _CACHE_SIZE:
                self._cache.popitem(last=False)
            return place

    def routes(self, origin: dict, destination: dict) -> list[dict]:
        """Fastest route first, then up to two alternatives: km and minutes."""
        url = _OSRM.format(a=f"{origin['lon']},{origin['lat']}", b=f"{destination['lon']},{destination['lat']}")
        try:
            response = self._http.get(url, headers=_HEADERS, timeout=10, params={
                "overview": "false", "alternatives": "true", "steps": "false"})
            response.raise_for_status()
            rows = response.json().get("routes") or []
        except (requests.RequestException, ValueError) as error:
            raise RoutingUnavailable("routeFailed") from error
        return [{"km": float(row["distance"]) / 1000, "minutes": float(row["duration"]) / 60}
                for row in rows[:3]]
