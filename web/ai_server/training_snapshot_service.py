"""Training Snapshot Service for preserving extracted features and metrics forever.

Even if raw telemetry TTL expires on Firestore/SQLite, extracted feature snapshots
ensure per-vehicle models can always be retrained and calibrated.
"""
from __future__ import annotations

import json
import logging
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

logger = logging.getLogger("TrainingSnapshotService")


class TrainingSnapshotService:
    def __init__(self, storage_dir: str | Path = "models/training_snapshots") -> None:
        self.storage_dir = Path(storage_dir)
        self.storage_dir.mkdir(parents=True, exist_ok=True)

    def _vehicle_dir(self, vehicle_id: str) -> Path:
        clean_id = "".join(c for c in vehicle_id if c.isalnum() or c in ("-", "_"))
        vdir = self.storage_dir / clean_id
        vdir.mkdir(parents=True, exist_ok=True)
        return vdir

    def save_snapshot(
        self,
        vehicle_id: str,
        version: str,
        session_ids: list[str],
        adapter_weights: dict[str, Any],
        metrics: dict[str, Any],
        feature_summary: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        """Saves a permanent snapshot of training run data and weights."""
        vdir = self._vehicle_dir(vehicle_id)
        snapshot_file = vdir / f"{version}.json"

        snapshot = {
            "vehicle_id": vehicle_id,
            "version": version,
            "saved_at": datetime.now(timezone.utc).isoformat(),
            "session_ids_count": len(session_ids),
            "session_ids": session_ids,
            "adapter_weights": adapter_weights,
            "metrics": metrics,
            "feature_summary": feature_summary or {},
        }

        try:
            with open(snapshot_file, "w", encoding="utf-8") as f:
                json.dump(snapshot, f, indent=2, ensure_ascii=False)
            logger.info(
                "[TrainingSnapshot] Saved snapshot %s for vehicle %s (sessions: %d)",
                version,
                vehicle_id,
                len(session_ids),
            )
        except Exception as e:
            logger.error("Failed to write training snapshot: %s", e)

        return snapshot

    def get_snapshots(self, vehicle_id: str) -> list[dict[str, Any]]:
        """Lists all snapshots for a vehicle, newest first."""
        vdir = self._vehicle_dir(vehicle_id)
        snapshots: list[dict[str, Any]] = []
        for file in sorted(vdir.glob("*.json"), reverse=True):
            try:
                with open(file, "r", encoding="utf-8") as f:
                    snapshots.append(json.load(f))
            except Exception:
                continue
        return snapshots

    def get_latest_snapshot(self, vehicle_id: str) -> dict[str, Any] | None:
        all_snapshots = self.get_snapshots(vehicle_id)
        return all_snapshots[0] if all_snapshots else None
