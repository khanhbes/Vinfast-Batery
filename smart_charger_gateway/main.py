from __future__ import annotations

import asyncio
import logging
import os
import secrets
from contextlib import asynccontextmanager, suppress
from datetime import datetime, timezone
from uuid import uuid4

from fastapi import Depends, FastAPI, Header, HTTPException, Query, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from models import (
    AutomaticChargingSessionRequest,
    ChargerCommandResponse,
    ChargerStatus,
    ChargingSessionHistoryResponse,
    ChargingSessionPatchRequest,
    ChargingSessionRequest,
    ChargingSessionResponse,
    ChargingSessionStopRequest,
    CurrentChargingSessionResponse,
    SmartChargingSession,
    ActualSocUpdateRequest,
)
from session_store import SessionStore
from shelly import ShellyClient, ShellyUnavailableError
from smart_charging import GatewayError, build_smart_controller

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("SmartChargerGateway")

shelly_client = ShellyClient()
session_store = SessionStore(os.getenv("SMART_CHARGER_STATE_FILE"))
smart_controller = build_smart_controller(shelly_client)


def _error_response(error: GatewayError) -> JSONResponse:
    return JSONResponse(
        status_code=error.status_code,
        content={
            "error": {
                "code": error.code,
                "message": error.message,
                "retryable": error.retryable,
                "session_id": error.session_id,
            }
        },
    )


async def _scheduler(stop_event: asyncio.Event) -> None:
    while not stop_event.is_set():
        try:
            await asyncio.to_thread(smart_controller.tick)
        except Exception:  # A failed tick must never kill the scheduler.
            logger.exception("[Scheduler] tick failed")
        try:
            await asyncio.wait_for(stop_event.wait(), timeout=10.0)
        except TimeoutError:
            pass


@asynccontextmanager
async def lifespan(_: FastAPI):
    stop_event = asyncio.Event()
    try:
        await asyncio.to_thread(smart_controller.recover)
    except Exception:
        logger.exception("[Scheduler] recovery failed")
    task = asyncio.create_task(_scheduler(stop_event))
    try:
        yield
    finally:
        stop_event.set()
        task.cancel()
        with suppress(asyncio.CancelledError):
            await task


app = FastAPI(
    title="VinFast Smart Charger Gateway",
    version="2.0.0",
    lifespan=lifespan,
)


@app.exception_handler(GatewayError)
async def gateway_error_handler(_: Request, error: GatewayError) -> JSONResponse:
    return _error_response(error)


@app.exception_handler(RequestValidationError)
async def validation_error_handler(_: Request, _error: RequestValidationError) -> JSONResponse:
    return JSONResponse(
        status_code=422,
        content={
            "error": {
                "code": "INVALID_REQUEST",
                "message": "Dữ liệu phiên sạc không hợp lệ.",
                "retryable": False,
                "session_id": None,
            }
        },
    )


def require_bearer(authorization: str | None = Header(default=None)) -> None:
    configured = os.getenv("SMART_CHARGER_API_TOKEN", "").strip()
    if not configured:
        raise GatewayError(
            "AUTH_NOT_CONFIGURED",
            "Gateway chưa cấu hình SMART_CHARGER_API_TOKEN.",
            status_code=503,
        )
    prefix = "Bearer "
    supplied = authorization[len(prefix):].strip() if authorization and authorization.startswith(prefix) else ""
    if not supplied or not secrets.compare_digest(supplied, configured):
        raise GatewayError("UNAUTHORIZED", "Token Smart Charger không hợp lệ.", status_code=401)


def shelly_unavailable(exc: Exception) -> GatewayError:
    logger.warning("[Shelly] unavailable: %s", exc)
    return GatewayError(
        "SHELLY_UNAVAILABLE",
        "Gateway đang chạy nhưng không liên lạc được với Shelly.",
        status_code=503,
        retryable=True,
    )


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/api/charger/status", response_model=ChargerStatus, dependencies=[Depends(require_bearer)])
def charger_status() -> ChargerStatus:
    try:
        return shelly_client.get_status()
    except ShellyUnavailableError as exc:
        raise shelly_unavailable(exc) from exc


@app.post("/api/charger/on", response_model=ChargerCommandResponse, dependencies=[Depends(require_bearer)])
def charger_on() -> ChargerCommandResponse:
    if smart_controller.store.current() is not None:
        raise GatewayError("ACTIVE_SESSION_EXISTS", "Phiên sạc thông minh đang điều khiển relay.", status_code=409)
    try:
        result = shelly_client.set_relay(True)
    except ShellyUnavailableError as exc:
        raise shelly_unavailable(exc) from exc
    if not result.success:
        raise GatewayError("RELAY_VERIFICATION_FAILED", "Không thể xác minh nguồn sạc đã bật.", status_code=503, retryable=True)
    return result


@app.post("/api/charger/off", response_model=ChargerCommandResponse, dependencies=[Depends(require_bearer)])
def charger_off() -> ChargerCommandResponse:
    active = smart_controller.store.current()
    if active is not None:
        previous = active.relay_verified
        stopped = smart_controller.stop(active.session_id)
        return ChargerCommandResponse(success=True, relay=False, previous_state=previous and stopped.relay_verified)
    try:
        result = shelly_client.set_relay(False)
    except ShellyUnavailableError as exc:
        raise shelly_unavailable(exc) from exc
    if not result.success:
        raise GatewayError("RELAY_VERIFICATION_FAILED", "Không thể xác minh nguồn sạc đã ngắt.", status_code=503, retryable=True)
    return result


@app.post("/api/charging/session", response_model=ChargingSessionResponse, dependencies=[Depends(require_bearer)])
def start_monitoring_session(request: ChargingSessionRequest) -> ChargingSessionResponse:
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
    return ChargingSessionResponse(session_id=session_id, received_at=received_at)


@app.post("/api/charging/session/start", response_model=SmartChargingSession, dependencies=[Depends(require_bearer)])
def start_smart_session(
    request: AutomaticChargingSessionRequest,
    idempotency_key: str | None = Header(default=None, alias="Idempotency-Key"),
) -> SmartChargingSession:
    return smart_controller.start(request, idempotency_key or "")


@app.get("/api/charging/session/current", dependencies=[Depends(require_bearer)])
def current_session() -> dict[str, object]:
    smart = smart_controller.store.current()
    if smart is not None:
        return CurrentChargingSessionResponse(active=True, session=smart).model_dump(mode="json")
    legacy = session_store.load()
    return {"active": legacy is not None, "session": legacy}


@app.get("/api/charging/session/{session_id}", response_model=SmartChargingSession, dependencies=[Depends(require_bearer)])
def get_smart_session(session_id: str) -> SmartChargingSession:
    return smart_controller.get(session_id)


@app.patch("/api/charging/session/{session_id}", response_model=SmartChargingSession, dependencies=[Depends(require_bearer)])
def patch_smart_session(session_id: str, request: ChargingSessionPatchRequest) -> SmartChargingSession:
    return smart_controller.patch(session_id, request)


@app.post("/api/charging/session/{session_id}/stop", response_model=SmartChargingSession, dependencies=[Depends(require_bearer)])
def stop_smart_session(
    session_id: str,
    request: ChargingSessionStopRequest | None = None,
) -> SmartChargingSession:
    return smart_controller.stop(
        session_id,
        expected_version=request.expected_version if request else None,
        user_stop_reason=request.user_stop_reason if request else "none",
    )


@app.get("/api/charging/sessions", response_model=ChargingSessionHistoryResponse, dependencies=[Depends(require_bearer)])
def charging_sessions(limit: int = Query(default=20, ge=1, le=100)) -> ChargingSessionHistoryResponse:
    return ChargingSessionHistoryResponse(sessions=smart_controller.store.list(limit))


@app.get("/api/charging/session/{session_id}/telemetry", dependencies=[Depends(require_bearer)])
def get_session_telemetry(session_id: str) -> list[dict]:
    smart_controller.get(session_id)
    return smart_controller.telemetry_writer.read_all(session_id)


@app.post("/api/charging/session/{session_id}/actual-soc", response_model=SmartChargingSession, dependencies=[Depends(require_bearer)])
def update_actual_soc(session_id: str, request: ActualSocUpdateRequest) -> SmartChargingSession:
    return smart_controller.update_actual_end_soc(
        session_id=session_id,
        actual_soc=request.actual_end_soc,
        source=request.source,
    )
