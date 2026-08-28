from __future__ import annotations

import json
import sqlite3
import threading
from pathlib import Path

from models import ChargingSessionState, SmartChargingSession


ACTIVE_STATES = (
    ChargingSessionState.STARTING.value,
    ChargingSessionState.ACTIVE.value,
    ChargingSessionState.STOPPING.value,
)


class SmartSessionStore:
    """Durable session store. Each update is one SQLite transaction."""

    def __init__(self, database_path: Path | str):
        self.database_path = Path(database_path)
        self.database_path.parent.mkdir(parents=True, exist_ok=True)
        self._lock = threading.RLock()
        self._initialize()

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.database_path, timeout=5)
        connection.row_factory = sqlite3.Row
        return connection

    def _initialize(self) -> None:
        with self._connect() as connection:
            connection.execute("PRAGMA journal_mode=WAL")
            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS smart_charging_sessions (
                    session_id TEXT PRIMARY KEY,
                    idempotency_key TEXT NOT NULL UNIQUE,
                    state TEXT NOT NULL,
                    version INTEGER NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    payload_json TEXT NOT NULL
                )
                """
            )
            connection.execute(
                "CREATE INDEX IF NOT EXISTS idx_smart_sessions_updated "
                "ON smart_charging_sessions(updated_at DESC)"
            )

    @staticmethod
    def _payload(session: SmartChargingSession) -> str:
        return json.dumps(session.model_dump(mode="json"), ensure_ascii=False)

    @staticmethod
    def _decode(row: sqlite3.Row | None) -> SmartChargingSession | None:
        if row is None:
            return None
        return SmartChargingSession.model_validate(json.loads(row["payload_json"]))

    def create(self, session: SmartChargingSession) -> SmartChargingSession:
        with self._lock, self._connect() as connection:
            connection.execute("BEGIN IMMEDIATE")
            connection.execute(
                """
                INSERT INTO smart_charging_sessions
                    (session_id, idempotency_key, state, version, created_at,
                     updated_at, payload_json)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    session.session_id,
                    session.idempotency_key,
                    session.state.value,
                    session.version,
                    session.created_at.isoformat(),
                    session.updated_at.isoformat(),
                    self._payload(session),
                ),
            )
        return session

    def save(self, session: SmartChargingSession) -> SmartChargingSession:
        with self._lock, self._connect() as connection:
            connection.execute("BEGIN IMMEDIATE")
            cursor = connection.execute(
                """
                UPDATE smart_charging_sessions
                SET state = ?, version = ?, updated_at = ?, payload_json = ?
                WHERE session_id = ?
                """,
                (
                    session.state.value,
                    session.version,
                    session.updated_at.isoformat(),
                    self._payload(session),
                    session.session_id,
                ),
            )
            if cursor.rowcount != 1:
                raise KeyError(session.session_id)
        return session

    def get(self, session_id: str) -> SmartChargingSession | None:
        with self._connect() as connection:
            return self._decode(connection.execute(
                "SELECT payload_json FROM smart_charging_sessions WHERE session_id = ?",
                (session_id,),
            ).fetchone())

    def get_by_idempotency_key(self, key: str) -> SmartChargingSession | None:
        with self._connect() as connection:
            return self._decode(connection.execute(
                "SELECT payload_json FROM smart_charging_sessions WHERE idempotency_key = ?",
                (key,),
            ).fetchone())

    def current(self) -> SmartChargingSession | None:
        placeholders = ",".join("?" for _ in ACTIVE_STATES)
        with self._connect() as connection:
            return self._decode(connection.execute(
                f"SELECT payload_json FROM smart_charging_sessions "
                f"WHERE state IN ({placeholders}) ORDER BY updated_at DESC LIMIT 1",
                ACTIVE_STATES,
            ).fetchone())

    def list(self, limit: int = 20) -> list[SmartChargingSession]:
        bounded = max(1, min(limit, 100))
        with self._connect() as connection:
            rows = connection.execute(
                "SELECT payload_json FROM smart_charging_sessions "
                "ORDER BY created_at DESC LIMIT ?", (bounded,),
            ).fetchall()
        result = [self._decode(row) for row in rows]
        return [session for session in result if session is not None]
