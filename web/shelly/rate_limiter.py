from __future__ import annotations

import threading
import time
from collections import defaultdict


class PerDeviceRateLimiter:
    """Serializes requests per device and enforces a minimum interval."""

    def __init__(self, interval_seconds: float = 1.0, clock=time.monotonic, sleeper=time.sleep):
        self.interval_seconds = interval_seconds
        self._clock = clock
        self._sleep = sleeper
        self._locks: dict[str, threading.Lock] = defaultdict(threading.Lock)
        self._last: dict[str, float] = {}

    def run(self, device_id: str, operation):
        with self._locks[device_id]:
            last = self._last.get(device_id)
            if last is not None:
                wait = self.interval_seconds - (self._clock() - last)
                if wait > 0:
                    self._sleep(wait)
            try:
                return operation()
            finally:
                self._last[device_id] = self._clock()

