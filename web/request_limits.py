"""Small in-process request limiter for the laptop-only deployment.

This protects a single API worker from accidental loops and basic abuse. It is
not a replacement for a shared ingress limiter when the service is scaled to
multiple workers or hosts.
"""
from __future__ import annotations

import functools
import math
import threading
import time
from collections import defaultdict, deque
from collections.abc import Callable

from flask import current_app, jsonify, request


class SlidingWindowLimiter:
    def __init__(self, clock: Callable[[], float] = time.monotonic):
        self._clock = clock
        self._events: dict[str, deque[float]] = defaultdict(deque)
        self._windows: dict[str, int] = {}
        self._lock = threading.Lock()
        self._checks = 0

    def check(self, key: str, limit: int, window_seconds: int) -> int | None:
        """Return retry-after seconds when blocked, otherwise ``None``."""
        now = self._clock()
        cutoff = now - window_seconds
        with self._lock:
            events = self._events[key]
            self._windows[key] = window_seconds
            while events and events[0] <= cutoff:
                events.popleft()
            if len(events) >= limit:
                return max(1, math.ceil(events[0] + window_seconds - now))
            events.append(now)

            self._checks += 1
            if self._checks % 256 == 0:
                empty = []
                for stored_key, stored_events in self._events.items():
                    stored_cutoff = now - self._windows.get(stored_key, window_seconds)
                    while stored_events and stored_events[0] <= stored_cutoff:
                        stored_events.popleft()
                    if not stored_events:
                        empty.append(stored_key)
                for stored_key in empty:
                    self._events.pop(stored_key, None)
                    self._windows.pop(stored_key, None)
        return None


_limiter = SlidingWindowLimiter()


def rate_limit(limit: int, window_seconds: int):
    """Limit a route by verified UID, falling back to its direct peer address."""
    def decorate(function):
        @functools.wraps(function)
        def wrapped(*args, **kwargs):
            if current_app.config.get('TESTING'):
                return function(*args, **kwargs)
            identity = getattr(request, '_uid', None) or request.remote_addr or 'unknown'
            bucket = f'{request.endpoint}:{identity}'
            retry_after = _limiter.check(bucket, limit, window_seconds)
            if retry_after is not None:
                response = jsonify({
                    'success': False,
                    'error': 'Too many requests. Please wait before trying again.',
                    'retryAfterSeconds': retry_after,
                })
                response.status_code = 429
                response.headers['Retry-After'] = str(retry_after)
                return response
            return function(*args, **kwargs)
        return wrapped
    return decorate
