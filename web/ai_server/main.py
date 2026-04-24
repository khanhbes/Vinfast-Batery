"""FastAPI entrypoint — multi-model-type AI server.

Endpoints:
    GET  /healthz
    GET  /v1/types                              → list registered model types + status

    # Generic per-type routes ────────────────────────────────────
    GET    /v1/models/{type}                    → list versions + active
    POST   /v1/models/{type}/upload             → multipart: file, version, note
    POST   /v1/models/{type}/rollback           → json: {"version": "..."}
    DELETE /v1/models/{type}/{version}
    GET    /v1/models/{type}/status
    POST   /v1/models/{type}/predict            → json passthrough → {prediction, modelVersion}

    # Backward-compat SOC routes (mobile app + legacy web) ───────
    GET  /v1/soc/status                         → alias for /v1/models/soc/status
    POST /v1/soc/predict                        → SOC-shaped response with timeSeries etc.

Auth: shared secret header `X-Internal-Token` matching env `AI_SERVER_INTERNAL_TOKEN`.
Only the Flask proxy should reach this service.
"""
from __future__ import annotations

import os
import shutil
import tempfile
from typing import Optional

from fastapi import FastAPI, File, Form, Header, HTTPException, UploadFile
from fastapi.responses import JSONResponse

from .model_runtime import ModelRuntime
from .model_store import ModelStore
from .prediction_service import PredictionService
from .registry import MODEL_TYPES, list_types, list_groups
from .schemas import ModelStatus, PredictRequest, UploadResult

# ── Paths & config ──────────────────────────────────────────────────
_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # .../web
MODELS_BASE_DIR = os.environ.get(
    "AI_SERVER_MODELS_DIR", os.path.join(_ROOT, "models")
)
INTERNAL_TOKEN = os.environ.get("AI_SERVER_INTERNAL_TOKEN", "dev-local-token")


def _find_legacy_pkl(filenames: list[str]) -> str:
    if not filenames:
        return ""
    candidates: list[str] = []
    for name in filenames:
        candidates.extend([
            os.path.join(_ROOT, name),
            os.path.join(os.path.dirname(_ROOT), name),
            os.path.join(_ROOT, "models", name),
        ])
    env = os.environ.get("EV_SOC_MODEL_PATH", "").strip()
    if env:
        candidates.insert(0, env)
    for p in candidates:
        if p and os.path.isfile(p):
            return p
    return ""


# ── Wiring: build per-type stores + runtimes ────────────────────────
_stores: dict[str, ModelStore] = {}
_runtimes: dict[str, ModelRuntime] = {}

for _key, _meta in MODEL_TYPES.items():
    _dir = os.path.join(MODELS_BASE_DIR, _key)
    _store = ModelStore(_dir)
    legacy = _find_legacy_pkl(list(_meta.get("legacy_pkl", [])))
    if legacy:
        seeded = _store.seed_from_legacy(legacy)
        if seeded:
            print(f"[ai_server:{_key}] seeded legacy → version '{seeded}' from {legacy}")
    _runtime = ModelRuntime(
        _store,
        smoke_input=_meta.get("smoke_input"),
        type_key=_key,
    )
    _runtime.reload_active_from_disk()
    _stores[_key] = _store
    _runtimes[_key] = _runtime

# SOC is still the only type with a rich PredictionService (timeSeries etc.)
_soc_svc = PredictionService(_runtimes["soc"]) if "soc" in _runtimes else None

app = FastAPI(title="VinFast Battery — AI Server", version="2.0.0")


# ── Helpers ─────────────────────────────────────────────────────────
def _check_token(x_internal_token: Optional[str]) -> None:
    if not INTERNAL_TOKEN:
        return
    if x_internal_token != INTERNAL_TOKEN:
        raise HTTPException(status_code=401, detail="invalid internal token")


def _get_runtime(type_key: str) -> ModelRuntime:
    rt = _runtimes.get(type_key)
    if rt is None:
        raise HTTPException(status_code=404, detail=f"unknown model type: {type_key}")
    return rt


def _get_store(type_key: str) -> ModelStore:
    st = _stores.get(type_key)
    if st is None:
        raise HTTPException(status_code=404, detail=f"unknown model type: {type_key}")
    return st


def _ok(data) -> JSONResponse:
    payload = data.model_dump() if hasattr(data, "model_dump") else data
    return JSONResponse({"success": True, "data": payload, "error": None})


def _err(status: int, msg: str) -> JSONResponse:
    return JSONResponse(
        {"success": False, "data": None, "error": msg}, status_code=status
    )


def _status_for(type_key: str) -> dict:
    rt = _get_runtime(type_key)
    st = _get_store(type_key)
    return {
        "isLoaded": rt.is_loaded,
        "isPredictable": rt.is_predictable,
        "activeVersion": rt.active_version,
        "modelFile": rt.model_file,
        "lastLoadAt": rt.last_load_at,
        "lastError": rt.last_error,
        "validationError": rt.validation_error,
        "predictorKind": rt.predictor_kind,
        "featureCount": rt.feature_count,
        "availableVersions": len(st.list_versions()),
    }


# ── Health / catalog ────────────────────────────────────────────────
@app.get("/healthz")
def healthz():
    return {
        "ok": True,
        "types": [
            {
                "key": k,
                "loaded": rt.is_loaded,
                "activeVersion": rt.active_version,
            }
            for k, rt in _runtimes.items()
        ],
    }


@app.get("/v1/types")
def types(x_internal_token: Optional[str] = Header(default=None)):
    _check_token(x_internal_token)
    out = []
    for meta in list_types():
        key = meta["key"]
        rt = _runtimes.get(key)
        st = _stores.get(key)
        meta["runtimeStatus"] = {
            "isLoaded": bool(rt and rt.is_loaded),
            "isPredictable": bool(rt and rt.is_predictable) if rt else False,
            "predictorKind": rt.predictor_kind if rt else None,
            "featureCount": rt.feature_count if rt else None,
            "validationError": rt.validation_error if rt else None,
            "activeVersion": rt.active_version if rt else None,
            "lastLoadAt": rt.last_load_at if rt else None,
            "lastError": rt.last_error if rt else None,
            "versionsCount": len(st.list_versions()) if st else 0,
        }
        out.append(meta)
    return _ok({"types": out, "groups": list_groups()})


# ── Generic per-type routes ─────────────────────────────────────────
@app.get("/v1/models/{type_key}")
def list_models(type_key: str, x_internal_token: Optional[str] = Header(default=None)):
    _check_token(x_internal_token)
    st = _get_store(type_key)
    return _ok({"versions": st.list_versions(), "active": st.active_version()})


@app.get("/v1/models/{type_key}/status")
def status_for_type(type_key: str, x_internal_token: Optional[str] = Header(default=None)):
    _check_token(x_internal_token)
    return _ok(_status_for(type_key))


@app.post("/v1/models/{type_key}/upload")
async def upload_model(
    type_key: str,
    file: UploadFile = File(...),
    version: str = Form(...),
    note: str = Form(""),
    skipSmokeTest: str = Form("false"),
    x_internal_token: Optional[str] = Header(default=None),
):
    _check_token(x_internal_token)
    st = _get_store(type_key)
    rt = _get_runtime(type_key)

    version = (version or "").strip()
    if not version or any(c in version for c in "/\\:"):
        return _err(400, "version không hợp lệ")
    if st.has_version(version):
        return _err(409, f"version '{version}' đã tồn tại")

    # Accept any file extension (.pkl, .h5, .pt, .onnx, etc.)
    filename = file.filename or "model.pkl"
    _, ext = os.path.splitext(filename)
    ext = ext or ".pkl"

    skip_smoke = skipSmokeTest.lower() in ("true", "1", "yes")

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=ext)
    try:
        shutil.copyfileobj(file.file, tmp)
        tmp.close()
    finally:
        file.file.close()

    try:
        meta = st.save_from_temp(tmp.name, version, note, ext=ext)
    except Exception as e:
        try:
            os.remove(tmp.name)
        except FileNotFoundError:
            pass
        return _err(400, f"lưu model thất bại: {e}")

    try:
        validation = rt.swap_to(version, require_smoke=(not skip_smoke))
    except Exception as e:
        # Validation failed - do NOT activate broken model
        try:
            st.remove(version)
        except Exception:
            pass
        return _err(400, f"validation failed: {e}")

    # Only activate if validation passed
    st.activate(version)
    
    # Get actual model feature info from runtime
    model_features = {
        "count": rt.feature_count,
        "names": rt._predictor.feature_names if rt._predictor else None,
    }
    
    # Compare with registry features
    registry_count = len(rt.smoke_input) if rt.smoke_input else None
    
    return _ok({
        "version": version,
        "activated": True,
        "note": meta.get("note"),
        "validation": validation,
        "modelFeatures": model_features,
        "registryFeatures": {
            "count": registry_count,
            "fields": list(rt.smoke_input.keys()) if rt.smoke_input else [],
        },
        "featureMismatch": rt.feature_count != registry_count if (rt.feature_count and registry_count) else None,
    })


@app.post("/v1/models/{type_key}/rollback")
def rollback_model(
    type_key: str,
    payload: dict,
    x_internal_token: Optional[str] = Header(default=None),
):
    _check_token(x_internal_token)
    st = _get_store(type_key)
    rt = _get_runtime(type_key)
    version = (payload or {}).get("version", "").strip()
    if not version:
        return _err(400, "thiếu version")
    if not st.has_version(version):
        return _err(404, f"version '{version}' không tồn tại")
    try:
        smoke = rt.swap_to(version, require_smoke=False)
        st.activate(version)
        return _ok({"activeVersion": version, "smokeTest": smoke})
    except Exception as e:
        return _err(500, f"rollback thất bại: {e}")


@app.delete("/v1/models/{type_key}/{version}")
def delete_model(
    type_key: str,
    version: str,
    x_internal_token: Optional[str] = Header(default=None),
):
    _check_token(x_internal_token)
    st = _get_store(type_key)
    rt = _get_runtime(type_key)
    try:
        # Check if trying to delete active version
        active = st.active_version()
        if active == version:
            # First deactivate, then delete
            st.deactivate()
            rt.clear()
        st.remove(version)
        return _ok({"deleted": version, "wasActive": active == version})
    except Exception as e:
        return _err(400, str(e))


@app.post("/v1/models/{type_key}/deactivate")
def deactivate_model(
    type_key: str,
    x_internal_token: Optional[str] = Header(default=None),
):
    """Deactivate the current active model (clear active version from store and unload from runtime)."""
    _check_token(x_internal_token)
    st = _get_store(type_key)
    rt = _get_runtime(type_key)
    
    active = st.active_version()
    if not active:
        return _ok({"status": "already_inactive", "message": "Không có model nào đang active"})
    
    try:
        st.deactivate()
        rt.clear()
        return _ok({"status": "deactivated", "previousVersion": active})
    except Exception as e:
        return _err(500, f"Deactivate thất bại: {e}")


@app.post("/v1/models/{type_key}/validate-version")
def validate_version(
    type_key: str,
    payload: dict,
    x_internal_token: Optional[str] = Header(default=None),
):
    """Validate a version can be loaded without activating it.
    
    Returns validation info including predictor kind, feature count, and smoke test result.
    """
    _check_token(x_internal_token)
    st = _get_store(type_key)
    rt = _get_runtime(type_key)
    
    version = (payload or {}).get("version", "").strip()
    if not version:
        return _err(400, "thiếu version")
    if not st.has_version(version):
        return _err(404, f"version '{version}' không tồn tại")
    
    try:
        # Try to load and validate without swapping
        result = rt.try_load_version(version, require_smoke=True)
        return _ok({
            "version": version,
            "valid": result["validation"].get("ok", False),
            "validation": result["validation"],
        })
    except Exception as e:
        return _ok({
            "version": version,
            "valid": False,
            "error": str(e),
        })


@app.post("/v1/models/{type_key}/validate-file")
async def validate_model_file(
    type_key: str,
    file: UploadFile = File(...),
    x_internal_token: Optional[str] = Header(default=None),
):
    """Validate a model file and return its metadata (feature count, feature names).
    
    Does NOT save or activate the model.
    """
    _check_token(x_internal_token)
    
    # Accept any file extension
    filename = file.filename or "model.pkl"
    _, ext = os.path.splitext(filename)
    ext = ext or ".pkl"

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=ext)
    try:
        shutil.copyfileobj(file.file, tmp)
        tmp.close()
    finally:
        file.file.close()

    try:
        # Load and validate the model
        from .model_runtime import _load_model_file, _create_predictor
        model = _load_model_file(tmp.name)
        predictor = _create_predictor(model)
        
        # Run smoke test
        smoke_input = {f"feature_{i}": 0.0 for i in range(predictor.feature_count or 6)}
        try:
            import pandas as pd
            X = pd.DataFrame([list(smoke_input.values())])
        except Exception:
            X = [list(smoke_input.values())]
        
        pred = predictor.predict(X)
        
        return _ok({
            "valid": True,
            "predictorKind": predictor.kind,
            "featureCount": predictor.feature_count,
            "featureNames": predictor.feature_names,
            "modelType": type(model).__name__,
        })
    except Exception as e:
        return _err(400, f"validation failed: {e}")
    finally:
        try:
            os.remove(tmp.name)
        except FileNotFoundError:
            pass


@app.post("/v1/models/{type_key}/load-active")
def load_active_model(
    type_key: str,
    x_internal_token: Optional[str] = Header(default=None),
):
    """Ensure the active version for this type is loaded into memory.

    If there is no active version at all, return a user-friendly error so the
    UI can show "Chưa có model này" instead of a generic 500.
    """
    _check_token(x_internal_token)
    rt = _get_runtime(type_key)
    st = _get_store(type_key)

    active = st.active_version()
    if not active:
        return _err(404, f"Chưa có model '{type_key}' — vui lòng upload và activate trước.")

    if rt.is_loaded and rt.active_version == active:
        return _ok({
            "status": "already_loaded",
            "activeVersion": active,
            "message": f"Model '{type_key}' version '{active}' đã sẵn sàng.",
        })

    try:
        rt.swap_to(active, require_smoke=False)
        return _ok({
            "status": "loaded",
            "activeVersion": active,
            "message": f"Đã nạp model '{type_key}' version '{active}' thành công.",
        })
    except Exception as e:
        return _err(500, f"Nạp model thất bại: {e}")


def _format_time_minutes(minutes: float) -> str:
    """Format minutes to hours/minutes string."""
    hours = int(minutes // 60)
    mins = int(minutes % 60)
    if hours > 0:
        return f"{hours} giờ {mins} phút"
    return f"{mins} phút"


def _build_charging_time_features(input_features: dict) -> dict:
    """Build 6 model features from 3 user inputs for charging_time.
    
    User inputs: start_soc, end_soc, ambient_temp_c
    Model features: start_soc, end_soc, delta_soc, ambient_temp_c, avg_charge_rate, temp_deviation
    """
    start_soc = float(input_features.get("start_soc", 0))
    end_soc = float(input_features.get("end_soc", 0))
    ambient_temp_c = float(input_features.get("ambient_temp_c", 0))
    
    # Validation
    if not (0 <= start_soc <= 100):
        raise ValueError("start_soc phải trong khoảng 0-100")
    if not (0 <= end_soc <= 100):
        raise ValueError("end_soc phải trong khoảng 0-100")
    if end_soc <= start_soc:
        raise ValueError("end_soc phải lớn hơn start_soc")
    if not (-20 <= ambient_temp_c <= 60):
        raise ValueError("ambient_temp_c phải trong khoảng -20 đến 60°C")
    
    delta_soc = end_soc - start_soc
    
    return {
        "start_soc": start_soc,
        "end_soc": end_soc,
        "delta_soc": delta_soc,
        "ambient_temp_c": ambient_temp_c,
        "avg_charge_rate": 22.5,
        "temp_deviation": abs(ambient_temp_c - 27),
    }


@app.post("/v1/models/{type_key}/predict")
def predict_generic(
    type_key: str,
    payload: dict,
    x_internal_token: Optional[str] = Header(default=None),
):
    """Generic passthrough prediction for non-SOC model types.

    Caller sends arbitrary key/value features; we forward them to the loaded
    model and return `{prediction, modelVersion, input, processedInput, chartData, warnings}`.
    SOC uses a dedicated richer route below.
    
    Special handling for charging_time: accepts 3 user inputs, builds 6 model features.
    """
    _check_token(x_internal_token)
    rt = _get_runtime(type_key)
    if not rt.is_loaded:
        return _err(503, f"model '{type_key}' chưa được nạp — upload & activate trước đã")
    
    try:
        # Build processed input (normalize numeric values)
        input_features = payload or {}
        
        # Special handling for charging_time: build 6 features from 3 user inputs
        if type_key == "charging_time":
            try:
                processed_input = _build_charging_time_features(input_features)
            except ValueError as e:
                return _err(400, str(e))
        else:
            processed_input = {}
            for k, v in input_features.items():
                if isinstance(v, str):
                    try:
                        num = float(v)
                        processed_input[k] = num
                    except ValueError:
                        processed_input[k] = v
                else:
                    processed_input[k] = v
        
        value, version, warning = rt.predict_raw(processed_input)
        
        # Build chart data based on output type
        chart_data = _build_chart_data(value, processed_input)
        
        warnings = []
        if warning:
            warnings.append(warning)
        if rt.feature_count and len(processed_input) != rt.feature_count:
            warnings.append(f"Input has {len(processed_input)} features but model expects {rt.feature_count}")
        
        # Build response
        response = {
            "prediction": value,
            "modelVersion": version,
            "input": input_features,
            "processedInput": processed_input,
            "chartData": chart_data,
            "warnings": warnings,
        }
        
        # Add formatted time output for charging_time
        # Model returns seconds, convert to minutes for display
        if type_key == "charging_time":
            minutes = value / 60.0  # Convert seconds to minutes
            response["rawPrediction"] = value
            response["predictionSeconds"] = value
            response["predictionMinutes"] = minutes
            response["formattedPrediction"] = _format_time_minutes(minutes)
        
        return _ok(response)
    except Exception as e:
        return _err(400, f"predict lỗi: {e}")


def _build_chart_data(prediction: float, input_features: dict) -> dict:
    """Build chart data structure based on prediction type."""
    # Default scalar chart (bar chart with single value)
    return {
        "type": "scalar",
        "data": [
            {"name": "Prediction", "value": prediction}
        ],
        "unit": "",
    }


# ── Backward-compat SOC endpoints (mobile app + legacy dashboard) ──
@app.get("/v1/soc/status")
def soc_status(x_internal_token: Optional[str] = Header(default=None)):
    _check_token(x_internal_token)
    return _ok(_status_for("soc"))


@app.post("/v1/soc/predict")
def soc_predict(req: PredictRequest, x_internal_token: Optional[str] = Header(default=None)):
    _check_token(x_internal_token)
    if _soc_svc is None:
        return _err(500, "SOC service chưa khởi tạo")
    try:
        return _ok(_soc_svc.predict(req))
    except Exception as e:
        return _err(500, str(e))
