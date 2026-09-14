"""Durable worker for administrator-initiated EV catalog research jobs."""

from __future__ import annotations

import json
import os
import time
import base64
import random

import firebase_admin
from firebase_admin import credentials, firestore

try:
    from google.api_core.exceptions import DeadlineExceeded, ResourceExhausted, ServiceUnavailable
except Exception:  # pragma: no cover - dependency is present in production
    DeadlineExceeded = ResourceExhausted = ServiceUnavailable = ()

from vehicle_catalog import claim_and_process_research_job


def initialize_firestore():
    if not firebase_admin._apps:
        raw = os.environ.get("FIREBASE_CREDENTIALS_JSON", "").strip()
        if raw:
            # Compose production supplies the same base64 value used by the
            # API; local development may use raw JSON. Never log either form.
            payload = raw if raw.startswith("{") else base64.b64decode(raw, validate=True).decode("utf-8")
            firebase_admin.initialize_app(credentials.Certificate(json.loads(payload)))
        else:
            path = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS", "").strip()
            if path:
                firebase_admin.initialize_app(credentials.Certificate(path))
            else:
                firebase_admin.initialize_app()
    return firestore.client()


def main() -> None:
    db = initialize_firestore()
    idle_seconds = max(15.0, float(os.environ.get("CATALOG_RESEARCH_POLL_SECONDS", "60")))
    max_backoff = max(idle_seconds, float(os.environ.get("CATALOG_RESEARCH_MAX_BACKOFF_SECONDS", "900")))
    backoff = 0.0
    while True:
        try:
            worked = claim_and_process_research_job(db)
            backoff = 0.0
            if not worked:
                time.sleep(idle_seconds)
        except (ResourceExhausted, DeadlineExceeded, ServiceUnavailable) as exc:
            backoff = min(max_backoff, max(idle_seconds, backoff * 2 or idle_seconds))
            delay = backoff + random.uniform(0, min(5.0, backoff * 0.1))
            print(f"Catalog worker backing off after Firestore transient error: {type(exc).__name__}; retrying in {delay:.1f}s", flush=True)
            time.sleep(delay)
        except Exception as exc:
            # Keep the worker healthy for transient SDK/network failures that
            # do not expose one of the typed google.api_core exceptions.
            name = type(exc).__name__.lower()
            if any(token in name or token in str(exc).lower() for token in ('quota', 'resourceexhausted', 'unavailable', 'deadline', 'timeout')):
                backoff = min(max_backoff, max(idle_seconds, backoff * 2 or idle_seconds))
                delay = backoff + random.uniform(0, min(5.0, backoff * 0.1))
                print(f"Catalog worker backing off after transient error: {type(exc).__name__}; retrying in {delay:.1f}s", flush=True)
                time.sleep(delay)
            else:
                print(f"Catalog worker job failed; retrying in {idle_seconds:.1f}s: {type(exc).__name__}: {exc}", flush=True)
                time.sleep(idle_seconds)


if __name__ == "__main__":
    main()
