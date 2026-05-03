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

try:
    import pandas as pd
except Exception:
    pd = None

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

    # PLAN1: Upload chỉ lưu file, KHÔNG auto-activate.
    # Validation chỉ để cảnh báo thêm, không được chặn việc lưu version.
    model_path = meta.get("path") or st.path_of(version, ext)
    if skip_smoke:
        validation = {
            "ok": True,
            "sample": None,
            "predictorKind": None,
            "featureCount": None,
            "warnings": ["Skipped upload validation at user request."],
        }
    else:
        try:
            validation = rt._validate_and_create_predictor(rt._load_model(model_path))
        except Exception as e:
            validation = {
                "ok": False,
                "error": str(e),
                "predictorKind": None,
                "featureCount": None,
                "warnings": [],
            }
    
    # Get actual model feature info from validation
    model_features = {
        "count": validation.get("featureCount"),
        "names": None,  # Will be populated when actually loaded
    }
    
    # Compare with registry features
    registry_count = len(rt.smoke_input) if rt.smoke_input else None
    upload_message = "Model đã upload thành công. Vui lòng Test rồi Deploy để kích hoạt."
    if not validation.get("ok"):
        upload_message = (
            "Model đã được upload nhưng validation tạm thời thất bại. "
            "Version vẫn được lưu để bạn tiếp tục Test hoặc xử lý dependency rồi Deploy sau."
        )
    
    return _ok({
        "version": version,
        "activated": False,  # PLAN1: Upload không auto-activate
        "note": meta.get("note"),
        "uploadStored": True,
        "validation": validation,
        "modelFeatures": model_features,
        "registryFeatures": {
            "count": registry_count,
            "fields": list(rt.smoke_input.keys()) if rt.smoke_input else [],
        },
        "featureMismatch": model_features.get("count") != registry_count if (model_features.get("count") and registry_count) else None,
        "message": upload_message,
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


@app.post("/v1/models/{type_key}/activate")
def activate_model(
    type_key: str,
    payload: dict,
    x_internal_token: Optional[str] = Header(default=None),
):
    """Activate a specific model version (same as deploy but without confirmation)."""
    _check_token(x_internal_token)
    st = _get_store(type_key)
    rt = _get_runtime(type_key)
    
    version = (payload or {}).get("version", "").strip()
    if not version:
        return _err(400, "thiếu version")
    if not st.has_version(version):
        return _err(404, f"version '{version}' không tồn tại")
    
    try:
        # Activate in store and load into runtime
        smoke = rt.swap_to(version, require_smoke=False)
        st.activate(version)
        return _ok({"activeVersion": version, "smokeTest": smoke})
    except Exception as e:
        return _err(500, f"activate thất bại: {e}")


@app.post("/v1/models/{type_key}/deploy")
def deploy_model(
    type_key: str,
    payload: dict,
    x_internal_token: Optional[str] = Header(default=None),
):
    """Deploy (activate) a specific model version — called by the web dashboard's Deploy button.

    This is the canonical deployment endpoint used by the frontend ``aiDeployModel()``.
    It loads the version into the runtime (swap_to) AND persists the active pointer in
    the store manifest so the state survives server restarts.
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
        smoke = rt.swap_to(version, require_smoke=False)
        st.activate(version)
        return _ok({
            "status": "deployed",
            "activeVersion": version,
            "smokeTest": smoke,
            "message": f"Model '{type_key}' version '{version}' đã được triển khai thành công.",
        })
    except Exception as e:
        return _err(500, f"deploy thất bại: {e}")


@app.post("/v1/models/{type_key}/load-active")
def load_active_model(
    type_key: str,
    x_internal_token: Optional[str] = Header(default=None),
):
    """Load the currently-active version (from manifest) into runtime memory.

    Called by the Flask API server after it writes the active-version pointer to the
    manifest (e.g. during the ``/deploy`` flow).  Without this endpoint the FastAPI
    runtime never learns about the new active version and ``runtimeStatus.activeVersion``
    stays null, causing the UI to show the amber "Có version chưa active" warning
    indefinitely.
    """
    _check_token(x_internal_token)
    st = _get_store(type_key)
    rt = _get_runtime(type_key)

    active = st.active_version()
    if not active:
        return _err(404, f"Không có version nào đang active cho '{type_key}'")

    try:
        smoke = rt.swap_to(active, require_smoke=False)
        return _ok({
            "activeVersion": active,
            "smokeTest": smoke,
            "message": f"Đã tải version '{active}' vào runtime.",
        })
    except Exception as e:
        return _err(500, f"load-active thất bại: {e}")




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


@app.post("/v1/models/{type_key}/test-version")
async def test_version(
    type_key: str,
    payload: dict,
    x_internal_token: Optional[str] = Header(default=None),
):
    """Load a specific version temporarily, run prediction, then unload.
    
    PLAN1: Per-version quick test without activating.
    """
    _check_token(x_internal_token)
    
    version = payload.get("version")
    test_input = payload.get("testInput")
    
    if not version:
        return _err(400, "version required")

    st = _get_store(type_key)
    rt = _get_runtime(type_key)
    version = version.strip()

    if not st.has_version(version):
        return _err(404, f"version '{version}' không tồn tại")

    try:
        loaded = rt.try_load_version(version, require_smoke=False)
        temp_predictor = loaded.get("predictor")
        validation = loaded.get("validation") or {}
        if not temp_predictor:
            return _err(
                400,
                f"version '{version}' không thể nạp: {validation.get('error', 'unknown')}",
            )
    except Exception as e:
        return _err(400, f"failed to load version {version}: {e}")
    
    try:
        features_dict = test_input or rt.smoke_input or {}
        input_features, processed_input = _normalize_input_features(type_key, features_dict)
        prediction = _predict_with_predictor(temp_predictor, processed_input)
    except Exception as e:
        return _err(400, f"prediction failed: {e}")
    finally:
        try:
            rt.unload_version(version)
        except Exception:
            pass
    
    return _ok(
        _build_prediction_response(
            type_key,
            input_features=input_features,
            processed_input=processed_input,
            value=prediction,
            model_version=version,
            warning=temp_predictor.warning,
            feature_count=temp_predictor.feature_count,
        )
    )


@app.post("/v1/models/{type_key}/reset")
async def reset_model(
    type_key: str,
    x_internal_token: Optional[str] = Header(default=None),
):
    """Clear all versions for a model type (safety reset).
    
    PLAN1: Allows admin to clear old broken versions before re-uploading.
    """
    _check_token(x_internal_token)

    st = _get_store(type_key)
    rt = _get_runtime(type_key)

    try:
        st.deactivate()
    except Exception:
        pass

    try:
        rt.unload()
    except Exception:
        pass

    try:
        data = st._read_manifest()
        versions = data.get("versions", [])
        deleted_versions = [v.get("version") for v in versions if v.get("version")]
        for v in versions:
            try:
                st.remove(v["version"])
            except Exception:
                pass
        st._write_manifest({"active": None, "versions": []})
    except Exception as e:
        return _err(500, f"reset failed: {e}")
    
    return _ok({
        "typeKey": type_key,
        "cleared": True,
        "deletedVersions": deleted_versions,
        "message": "All versions cleared. Ready for fresh upload.",
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


def _normalize_input_features(type_key: str, payload: dict | None) -> tuple[dict, dict]:
    """Normalize raw input payload into model-ready features."""
    input_features = payload or {}

    if type_key == "charging_time":
        return input_features, _build_charging_time_features(input_features)

    processed_input: dict = {}
    for k, v in input_features.items():
        if isinstance(v, str):
            try:
                processed_input[k] = float(v)
            except ValueError:
                processed_input[k] = v
        else:
            processed_input[k] = v
    return input_features, processed_input


def _predict_with_predictor(predictor, processed_input: dict) -> float:
    """Run prediction with a predictor instance loaded temporarily."""
    feature_values = list(processed_input.values())

    if pd is not None:
        if predictor.feature_names:
            X = pd.DataFrame([feature_values], columns=predictor.feature_names)
        else:
            X = pd.DataFrame([feature_values])
    else:
        X = [feature_values]

    raw = predictor.predict(X)
    if hasattr(raw, "flatten"):
        raw = raw.flatten()
    if hasattr(raw, "__len__") and len(raw) > 0:
        return float(raw[0])
    return float(raw)


def _build_prediction_response(
    type_key: str,
    *,
    input_features: dict,
    processed_input: dict,
    value: float,
    model_version: str,
    warning: Optional[str] = None,
    feature_count: Optional[int] = None,
) -> dict:
    """Build a prediction response matching the deployed predict route."""
    chart_data = _build_chart_data(value, processed_input)
    warnings = []
    if warning:
        warnings.append(warning)
    if feature_count and len(processed_input) != feature_count:
        warnings.append(
            f"Input has {len(processed_input)} features but model expects {feature_count}"
        )

    response = {
        "prediction": value,
        "modelVersion": model_version,
        "input": input_features,
        "processedInput": processed_input,
        "chartData": chart_data,
        "warnings": warnings,
    }

    if type_key == "charging_time":
        minutes = value / 60.0
        response["rawPrediction"] = value
        response["predictionSeconds"] = value
        response["predictionMinutes"] = minutes
        response["formattedPrediction"] = _format_time_minutes(minutes)

    return response


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
        try:
            input_features, processed_input = _normalize_input_features(type_key, payload)
        except ValueError as e:
            return _err(400, str(e))
        
        value, version, warning = rt.predict_raw(processed_input)

        return _ok(
            _build_prediction_response(
                type_key,
                input_features=input_features,
                processed_input=processed_input,
                value=value,
                model_version=version,
                warning=warning,
                feature_count=rt.feature_count,
            )
        )
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
