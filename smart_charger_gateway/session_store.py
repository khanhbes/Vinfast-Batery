import json
import os
from pathlib import Path
from typing import Any


class SessionStore:
    def __init__(self, state_file: Path | str | None = None):
        self.state_file = Path(
            state_file
            or Path(__file__).resolve().parent / "state" / "current_session.json"
        )

    def save(self, session: dict[str, Any]) -> None:
        self.state_file.parent.mkdir(parents=True, exist_ok=True)
        temp_file = self.state_file.with_suffix(".tmp")
        with temp_file.open("w", encoding="utf-8") as handle:
            json.dump(session, handle, ensure_ascii=False, indent=2)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temp_file, self.state_file)

    def load(self) -> dict[str, Any] | None:
        if not self.state_file.exists():
            return None
        try:
            with self.state_file.open("r", encoding="utf-8") as handle:
                data = json.load(handle)
            return data if isinstance(data, dict) else None
        except (OSError, json.JSONDecodeError):
            return None
