import logging
import os
from datetime import datetime, timezone
from uuid import uuid4

from fastapi import FastAPI, HTTPException

from models import (
    ChargerCommandResponse,
    ChargerStatus,
    ChargingSessionRequest,
    ChargingSessionResponse,
)
from session_store import SessionStore
from shelly import ShellyClient, ShellyUnavailableError

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("SmartChargerGateway")

app = FastAPI(title="VinFast Smart Charger Gateway", version="1.0.0")
shelly_client = ShellyClient()
session_store = SessionStore(os.getenv("SMART_CHARGER_STATE_FILE"))


def shelly_unavailable(exc: Exception) -> HTTPException:
    logger.warning("[Shelly] unavailable: %s", exc)
    return HTTPException(
        status_code=503,
        detail="Gateway đang chạy nhưng không liên lạc được với Shelly.",
    )


@app.get("/api/charger/status", response_model=ChargerStatus)
def charger_status() -> ChargerStatus:
    try:
        return shelly_client.get_status()
    except ShellyUnavailableError as exc:
        raise shelly_unavailable(exc) from exc


@app.post("/api/charger/on", response_model=ChargerCommandResponse)
def charger_on() -> ChargerCommandResponse:
    try:
        result = shelly_client.set_relay(True)
    except ShellyUnavailableError as exc:
        raise shelly_unavailable(exc) from exc
    if not result.success:
        raise HTTPException(status_code=503, detail="Không thể bật nguồn sạc.")
    return result


@app.post("/api/charger/off", response_model=ChargerCommandResponse)
def charger_off() -> ChargerCommandResponse:
    try:
        result = shelly_client.set_relay(False)
    except ShellyUnavailableError as exc:
        raise shelly_unavailable(exc) from exc
    if not result.success:
        raise HTTPException(status_code=503, detail="Không thể ngắt nguồn sạc.")
    return result


@app.post("/api/charging/session", response_model=ChargingSessionResponse)
def start_monitoring_session(
    request: ChargingSessionRequest,
) -> ChargingSessionResponse:
    received_at = datetime.now(timezone.utc)
    session_id = str(uuid4())
    session = {
        **request.model_dump(mode="json"),
        "session_id": session_id,
        "mode": "monitor_only",
        "received_at": received_at.isoformat(),
    }
    session_store.save(session)
    logger.info("[MonitorSession] saved session %s", session_id)
    return ChargingSessionResponse(
        session_id=session_id,
        received_at=received_at,
    )


@app.get("/api/charging/session/current")
def current_monitoring_session() -> dict[str, object]:
    session = session_store.load()
    return {"active": session is not None, "session": session}
