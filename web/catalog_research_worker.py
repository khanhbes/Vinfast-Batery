"""Durable worker for administrator-initiated EV catalog research jobs."""

from __future__ import annotations

import json
import os
import time
import base64

import firebase_admin
from firebase_admin import credentials, firestore

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
    idle_seconds = max(1.0, float(os.environ.get("CATALOG_RESEARCH_POLL_SECONDS", "3")))
    while True:
        worked = claim_and_process_research_job(db)
        if not worked:
            time.sleep(idle_seconds)


if __name__ == "__main__":
    main()
