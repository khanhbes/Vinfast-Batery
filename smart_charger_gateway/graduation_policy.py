from __future__ import annotations

import json
import logging
from pathlib import Path
import sqlite3
import threading
from typing import Literal

logger = logging.getLogger(__name__)

GraduationState = Literal["shadow", "canary", "live"]


class GraduationPolicy:
    """Manages per-vehicle graduation state: shadow -> canary -> live with safety rollback."""

    def __init__(
        self,
        db_path: Path | str = "state/graduation.sqlite3",
        mape_threshold: float = 15.0,
        min_sessions_for_canary: int = 10,
        canary_sessions_needed: int = 3,
        regression_mape_threshold: float = 25.0,
    ) -> None:
        self.db_path = Path(db_path)
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self.mape_threshold = mape_threshold
        self.min_sessions_for_canary = min_sessions_for_canary
        self.canary_sessions_needed = canary_sessions_needed
        self.regression_mape_threshold = regression_mape_threshold
        self._lock = threading.RLock()
        self._init_db()

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path, timeout=5)
        conn.row_factory = sqlite3.Row
        return conn

    def _init_db(self) -> None:
        with self._connect() as conn:
            conn.execute("PRAGMA journal_mode=WAL")
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS vehicle_graduation (
                    vehicle_id TEXT PRIMARY KEY,
                    state TEXT NOT NULL,
                    successful_canary_count INTEGER NOT NULL DEFAULT 0,
                    last_evaluated_mape REAL,
                    safety_event_count INTEGER NOT NULL DEFAULT 0,
                    updated_at TEXT NOT NULL,
                    notes TEXT
                )
                """
            )

    def get_state(self, vehicle_id: str) -> GraduationState:
        """Returns the current graduation state for a vehicle. Defaults to 'shadow'."""
        with self._connect() as conn:
            row = conn.execute(
                "SELECT state FROM vehicle_graduation WHERE vehicle_id = ?",
                (vehicle_id,),
            ).fetchone()
            if row:
                return row["state"]
        return "shadow"

    def should_use_shadow_mode(self, vehicle_id: str) -> bool:
        """Returns True if the vehicle should operate in shadow mode (shadow = True)."""
        state = self.get_state(vehicle_id)
        return state == "shadow"

    def record_safety_event(self, vehicle_id: str, reason: str) -> None:
        """Any safety violation immediately demotes the vehicle back to shadow mode."""
        with self._lock, self._connect() as conn:
            logger.warning(
                "[GraduationPolicy] Vehicle %s encountered safety event '%s'. Reverting to SHADOW mode.",
                vehicle_id,
                reason,
            )
            from datetime import datetime, timezone
            now = datetime.now(timezone.utc).isoformat()
            conn.execute(
                """
                INSERT INTO vehicle_graduation (vehicle_id, state, successful_canary_count, safety_event_count, updated_at, notes)
                VALUES (?, 'shadow', 0, 1, ?, ?)
                ON CONFLICT(vehicle_id) DO UPDATE SET
                    state = 'shadow',
                    successful_canary_count = 0,
                    safety_event_count = safety_event_count + 1,
                    updated_at = excluded.updated_at,
                    notes = excluded.notes
                """,
                (vehicle_id, now, f"Rolled back due to: {reason}"),
            )

    def record_session_completed(
        self,
        vehicle_id: str,
        predicted_minutes: int,
        actual_minutes: float,
        validation_mape: float | None = None,
        total_eligible_sessions: int = 0,
    ) -> GraduationState:
        """Evaluates graduation transitions after a clean completed session."""
        from datetime import datetime, timezone
        now = datetime.now(timezone.utc).isoformat()

        with self._lock, self._connect() as conn:
            row = conn.execute(
                "SELECT * FROM vehicle_graduation WHERE vehicle_id = ?",
                (vehicle_id,),
            ).fetchone()

            current_state = row["state"] if row else "shadow"
            canary_count = row["successful_canary_count"] if row else 0

            # Calculate session error
            if actual_minutes > 0:
                session_mape = abs(predicted_minutes - actual_minutes) / actual_minutes * 100.0
            else:
                session_mape = 0.0

            mape = validation_mape if validation_mape is not None else session_mape

            # Check regression
            if current_state in ("canary", "live") and mape > self.regression_mape_threshold:
                logger.warning(
                    "[GraduationPolicy] Vehicle %s MAPE regressed to %.1f%%. Demoting to SHADOW.",
                    vehicle_id,
                    mape,
                )
                conn.execute(
                    """
                    INSERT INTO vehicle_graduation (vehicle_id, state, successful_canary_count, last_evaluated_mape, updated_at, notes)
                    VALUES (?, 'shadow', 0, ?, ?, 'Demoted due to MAPE regression')
                    ON CONFLICT(vehicle_id) DO UPDATE SET
                        state = 'shadow',
                        successful_canary_count = 0,
                        last_evaluated_mape = excluded.last_evaluated_mape,
                        updated_at = excluded.updated_at,
                        notes = excluded.notes
                    """,
                    (vehicle_id, mape, now),
                )
                return "shadow"

            # Check promotion
            new_state = current_state
            if current_state == "shadow":
                if total_eligible_sessions >= self.min_sessions_for_canary and mape <= self.mape_threshold:
                    new_state = "canary"
                    canary_count = 1
                    logger.info(
                        "[GraduationPolicy] Vehicle %s promoted from SHADOW to CANARY (sessions: %d, MAPE: %.1f%%)",
                        vehicle_id,
                        total_eligible_sessions,
                        mape,
                    )
            elif current_state == "canary":
                canary_count += 1
                if canary_count >= self.canary_sessions_needed and mape <= self.mape_threshold:
                    new_state = "live"
                    logger.info(
                        "[GraduationPolicy] Vehicle %s promoted from CANARY to LIVE (canary sessions: %d, MAPE: %.1f%%)",
                        vehicle_id,
                        canary_count,
                        mape,
                    )

            conn.execute(
                """
                INSERT INTO vehicle_graduation (vehicle_id, state, successful_canary_count, last_evaluated_mape, updated_at, notes)
                VALUES (?, ?, ?, ?, ?, 'Normal evaluation')
                ON CONFLICT(vehicle_id) DO UPDATE SET
                    state = excluded.state,
                    successful_canary_count = excluded.successful_canary_count,
                    last_evaluated_mape = excluded.last_evaluated_mape,
                    updated_at = excluded.updated_at
                """,
                (vehicle_id, new_state, canary_count, mape, now),
            )
            return new_state
