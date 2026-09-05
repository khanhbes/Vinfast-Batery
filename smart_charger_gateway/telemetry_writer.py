from __future__ import annotations

import json
import logging
from pathlib import Path
import threading
from typing import Any

logger = logging.getLogger(__name__)

MAX_TELEMETRY_FILE_BYTES = 50 * 1024 * 1024  # 50 MB safety limit


class TelemetryWriter:
    """Thread-safe append-only JSONL telemetry recorder for charging sessions."""

    def __init__(self, base_dir: Path | str = "state/telemetry") -> None:
        self.base_dir = Path(base_dir)
        self.base_dir.mkdir(parents=True, exist_ok=True)
        self._lock = threading.Lock()

    def _file_path(self, session_id: str) -> Path:
        # Sanitize session_id to avoid path traversal
        clean_id = "".join(c for c in session_id if c.isalnum() or c in ("-", "_"))
        return self.base_dir / f"{clean_id}.jsonl"

    def append(self, session_id: str, sample: dict[str, Any]) -> int:
        """Appends a sample as a JSON line and returns the current total sample count."""
        path = self._file_path(session_id)
        with self._lock:
            # Check safety file size
            if path.exists() and path.stat().st_size > MAX_TELEMETRY_FILE_BYTES:
                logger.warning(
                    "Telemetry file for session %s exceeded %d bytes; rotating or skipping",
                    session_id,
                    MAX_TELEMETRY_FILE_BYTES,
                )
                return self.count(session_id)

            line = json.dumps(sample, default=str)
            with path.open("a", encoding="utf-8") as f:
                f.write(line + "\n")

        return self.count(session_id)

    def count(self, session_id: str) -> int:
        """Returns the number of samples recorded for the given session."""
        path = self._file_path(session_id)
        if not path.exists():
            return 0
        try:
            with path.open("r", encoding="utf-8") as f:
                return sum(1 for line in f if line.strip())
        except Exception as e:
            logger.error("Failed to count telemetry samples for %s: %s", session_id, e)
            return 0

    def read_all(self, session_id: str) -> list[dict[str, Any]]:
        """Reads and parses all telemetry samples recorded for the given session."""
        path = self._file_path(session_id)
        if not path.exists():
            return []
        samples: list[dict[str, Any]] = []
        with self._lock:
            try:
                with path.open("r", encoding="utf-8") as f:
                    for line in f:
                        line = line.strip()
                        if line:
                            samples.append(json.loads(line))
            except Exception as e:
                logger.error("Failed to read telemetry for session %s: %s", session_id, e)
        return samples
