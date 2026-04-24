"""ModelRuntime — in-memory model holder with atomic swap + read/write lock.

Features:
- `load(version)` validates a model (load + smoke inference) before swap.
- `swap_to(version)` activates the new model atomically (predictions never see a half-loaded state).
- `predict(features)` acquires a shared read reference; safe during concurrent swaps.
- Predictor adapter supports: sklearn/joblib, XGBoost, Keras, ONNX, and TorchScript.

File format dispatch:
- .pkl/.joblib: joblib.load or pickle
- .keras/.h5/.hdf5: tensorflow.keras.models.load_model
- .onnx: onnxruntime.InferenceSession
- .pt/.pth: torch.jit.load (TorchScript only)
"""
from __future__ import annotations

import os
import pickle
import threading
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Tuple, Callable

try:
    import joblib
except Exception:
    joblib = None

try:
    import numpy as np
except Exception:
    np = None

try:
    import pandas as pd
except Exception:
    pd = None

from .model_store import ModelStore


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


# ── File Format Dispatch ───────────────────────────────────────
# Load model files based on their extension, avoiding format mismatch errors.

_ML_SEARCH_MODULES = [
    "xgboost",
    "xgboost.core",
    "sklearn.base",
    "sklearn.ensemble",
    "sklearn.linear_model",
    "sklearn.pipeline",
    "sklearn.preprocessing",
]


def _load_model_file(path: str) -> Any:
    """Load a model file by dispatching on extension.
    
    - .pkl/.joblib: joblib.load or pickle
    - .keras/.h5/.hdf5: tensorflow.keras.models.load_model
    - .onnx: onnxruntime.InferenceSession
    - .pt/.pth: torch.jit.load (TorchScript only, not raw state_dict)
    
    Raises:
        FileNotFoundError: if path doesn't exist
        RuntimeError: if format is unsupported or loading fails
    """
    if not os.path.isfile(path):
        raise FileNotFoundError(path)
    
    ext = os.path.splitext(path)[1].lower()
    
    if ext in ('.pkl', '.joblib', '.pickle'):
        return _load_pickle_file(path)
    elif ext in ('.keras', '.h5', '.hdf5'):
        return _load_keras_file(path)
    elif ext == '.onnx':
        return _load_onnx_file(path)
    elif ext in ('.pt', '.pth'):
        return _load_torchscript_file(path)
    else:
        # Unknown extension: try pickle first, then keras
        try:
            return _load_pickle_file(path)
        except Exception:
            pass
        try:
            return _load_keras_file(path)
        except Exception:
            pass
        raise RuntimeError(f"Unsupported model format: {ext}")


def _load_pickle_file(path: str) -> Any:
    """Load pickle/joblib file with robust error handling."""
    if joblib is not None:
        try:
            return joblib.load(path, mmap_mode=None)
        except Exception:
            pass
    
    for encoding in ('latin1', 'bytes', 'ASCII'):
        try:
            with open(path, "rb") as f:
                return pickle.load(f, encoding=encoding, errors='ignore')
        except Exception:
            pass
    
    # Final attempt with custom unpickler
    with open(path, "rb") as f:
        class RobustUnpickler(pickle.Unpickler):
            def persistent_load(self, pid):
                return None
            def find_class(self, module, name):
                if module in ("__main__", "uvicorn.__main__", "__mp_main__"):
                    for lib_path in _ML_SEARCH_MODULES:
                        try:
                            parts = lib_path.split(".")
                            mod = __import__(lib_path, fromlist=[parts[-1]] if len(parts) > 1 else [])
                            if hasattr(mod, name):
                                return getattr(mod, name)
                        except ImportError:
                            pass
                    return type(name, (), {"__module__": module})
                return super().find_class(module, name)
        return RobustUnpickler(f).load()


def _load_keras_file(path: str) -> Any:
    """Load Keras/TensorFlow model."""
    try:
        import tensorflow as tf
        tf.get_logger().setLevel('ERROR')
        return tf.keras.models.load_model(path, compile=False)
    except ImportError:
        raise RuntimeError("tensorflow not installed, cannot load .keras/.h5 files")
    except Exception as e:
        raise RuntimeError(f"Failed to load Keras model: {e}")


def _load_onnx_file(path: str) -> Any:
    """Load ONNX model."""
    try:
        import onnxruntime as ort
        return ort.InferenceSession(path)
    except ImportError:
        raise RuntimeError("onnxruntime not installed, cannot load .onnx files")
    except Exception as e:
        raise RuntimeError(f"Failed to load ONNX model: {e}")


def _load_torchscript_file(path: str) -> Any:
    """Load TorchScript model (not raw state_dict)."""
    try:
        import torch
        model = torch.jit.load(path)
        if not isinstance(model, torch.jit.ScriptModule):
            raise RuntimeError("File is not a TorchScript model")
        return model
    except ImportError:
        raise RuntimeError("torch not installed, cannot load .pt/.pth files")
    except RuntimeError:
        raise
    except Exception as e:
        raise RuntimeError(f"Failed to load TorchScript model: {e}. Note: Only TorchScript format is supported, not raw state_dict.")


# ── Predictor Adapter ───────────────────────────────────────────
# Unified interface for different model types

class PredictorAdapter:
    """Adapter that provides a unified predict() interface for various model types."""
    
    def __init__(self, model: Any):
        self.model = model
        self.kind: str = "unknown"
        self.feature_count: Optional[int] = None
        self._predict_fn: Optional[Callable] = None
        self._feature_names: Optional[List[str]] = None
        self._warning: Optional[str] = None
        
        self._discover_predictor()
    
    def _discover_predictor(self):
        """Discover the predictor function from the model object."""
        model = self.model
        
        # Type 1: Keras/TensorFlow model
        if self._is_keras_model(model):
            self._predict_fn = self._create_keras_predictor(model)
            self.kind = "keras"
            return
        
        # Type 2: ONNX InferenceSession
        if self._is_onnx_session(model):
            self._predict_fn = self._create_onnx_predictor(model)
            self.kind = "onnx"
            return
        
        # Type 3: TorchScript model
        if self._is_torchscript_model(model):
            self._predict_fn = self._create_torchscript_predictor(model)
            self.kind = "torchscript"
            return
        
        # Type 4: sklearn Pipeline or estimator with .predict()
        if hasattr(model, "predict") and callable(model.predict):
            self._predict_fn = model.predict
            self.kind = "sklearn"
            self._extract_feature_names(model)
            return
        
        # Type 5: Object with .model.predict() wrapper
        if hasattr(model, "model") and hasattr(model.model, "predict"):
            self._predict_fn = model.model.predict
            self.kind = "wrapper"
            self._extract_feature_names(model.model)
            return
        
        # Type 6: XGBoost wrapper with booster_json
        if self._is_xgboost_booster_wrapper(model):
            self._predict_fn = self._create_xgboost_predictor(model)
            self.kind = "xgboost_booster"
            return
        
        # Type 7: Try to find any callable predict-like attribute
        for attr in ["predict", "predict_proba", "forecast", "infer"]:
            if hasattr(model, attr):
                fn = getattr(model, attr)
                if callable(fn):
                    self._predict_fn = fn
                    self.kind = f"fallback:{attr}"
                    return
        
        raise RuntimeError("model has no predict() method")
    
    # ----- Keras Support -----
    def _is_keras_model(self, model: Any) -> bool:
        """Check if model is a Keras model."""
        try:
            import tensorflow as tf
            return isinstance(model, (tf.keras.Model, tf.keras.Sequential))
        except ImportError:
            return False
    
    def _create_keras_predictor(self, model: Any) -> Callable:
        """Create predictor for Keras model."""
        import tensorflow as tf
        
        try:
            input_shape = model.input_shape
            if input_shape and len(input_shape) > 1:
                self.feature_count = input_shape[1]
        except:
            pass
        
        def predict_fn(X: Any):
            if hasattr(X, 'values'):
                X = X.values
            if isinstance(X, list):
                X = np.array(X) if np else X
            if hasattr(X, 'ndim') and X.ndim == 1:
                X = X.reshape(1, -1)
            return model.predict(X, verbose=0)
        
        return predict_fn
    
    # ----- ONNX Support -----
    def _is_onnx_session(self, model: Any) -> bool:
        """Check if model is an ONNX InferenceSession."""
        try:
            import onnxruntime as ort
            return isinstance(model, ort.InferenceSession)
        except ImportError:
            return False
    
    def _create_onnx_predictor(self, session: Any) -> Callable:
        """Create predictor for ONNX session."""
        import numpy as np
        
        input_meta = session.get_inputs()
        if input_meta:
            input_shape = input_meta[0].shape
            if input_shape and len(input_shape) > 1 and isinstance(input_shape[1], int):
                self.feature_count = input_shape[1]
        
        output_name = session.get_outputs()[0].name if session.get_outputs() else None
        
        def predict_fn(X: Any):
            if hasattr(X, 'values'):
                X = X.values
            if isinstance(X, list):
                X = np.array(X, dtype=np.float32)
            if hasattr(X, 'dtype') and X.dtype != np.float32:
                X = X.astype(np.float32)
            if hasattr(X, 'ndim') and X.ndim == 1:
                X = X.reshape(1, -1)
            return session.run([output_name], {input_meta[0].name: X})[0]
        
        return predict_fn
    
    # ----- TorchScript Support -----
    def _is_torchscript_model(self, model: Any) -> bool:
        """Check if model is a TorchScript ScriptModule."""
        try:
            import torch
            return isinstance(model, torch.jit.ScriptModule)
        except ImportError:
            return False
    
    def _create_torchscript_predictor(self, model: Any) -> Callable:
        """Create predictor for TorchScript model."""
        import torch
        import numpy as np
        
        try:
            graph_inputs = list(model.graph.inputs())
            if graph_inputs:
                first_input = graph_inputs[0]
                if hasattr(first_input, 'type') and hasattr(first_input.type(), 'sizes'):
                    sizes = first_input.type().sizes()
                    if sizes and len(sizes) > 1:
                        self.feature_count = sizes[1]
        except:
            pass
        
        def predict_fn(X: Any):
            if hasattr(X, 'values'):
                X = X.values
            if isinstance(X, list):
                X = np.array(X, dtype=np.float32)
            if hasattr(X, 'dtype') and X.dtype != np.float32:
                X = X.astype(np.float32)
            if hasattr(X, 'ndim') and X.ndim == 1:
                X = X.reshape(1, -1)
            
            tensor = torch.from_numpy(X)
            with torch.no_grad():
                output = model(tensor)
            
            if hasattr(output, 'numpy'):
                return output.numpy()
            return output
        
        return predict_fn
    
    # ----- Sklearn/XGBoost Support -----
    def _extract_feature_names(self, model: Any):
        """Try to extract feature names from the model."""
        try:
            if hasattr(model, "feature_names_in_"):
                self._feature_names = list(model.feature_names_in_)
                self.feature_count = len(self._feature_names)
            elif hasattr(model, "n_features_in_"):
                self.feature_count = int(model.n_features_in_)
        except Exception:
            pass
    
    def _is_xgboost_booster_wrapper(self, model: Any) -> bool:
        """Check if model is an XGBoost wrapper with booster_json attribute."""
        return (
            hasattr(model, "booster_json") 
            or hasattr(model, "_booster_json")
            or (hasattr(model, "booster") and hasattr(model.booster, "save_raw"))
        )
    
    def _create_xgboost_predictor(self, model: Any) -> Callable:
        """Create a predictor function for XGBoost booster wrapper."""
        try:
            import xgboost as xgb
            import numpy as np
            
            # Get booster from wrapper
            booster = None
            if hasattr(model, "booster"):
                booster = model.booster
            elif hasattr(model, "_booster"):
                booster = model._booster
            elif hasattr(model, "booster_json"):
                # Reconstruct from JSON bytes
                booster = xgb.Booster()
                booster.load_model(bytearray(model.booster_json, 'utf-8') if isinstance(model.booster_json, str) else model.booster_json)
            elif hasattr(model, "_booster_json"):
                booster = xgb.Booster()
                booster.load_model(bytearray(model._booster_json, 'utf-8') if isinstance(model._booster_json, str) else model._booster_json)
            
            if booster is None:
                raise RuntimeError("Cannot extract XGBoost booster from wrapper")
            
            # Get feature count from booster
            self.feature_count = booster.num_features()
            
            def predict_fn(X: Any):
                """Predict using XGBoost booster."""
                if hasattr(X, 'values'):
                    arr = X.values.astype(float)
                elif isinstance(X, list):
                    arr = np.array(X, dtype=float)
                elif isinstance(X, np.ndarray):
                    arr = X.astype(float)
                else:
                    arr = np.array(X, dtype=float)
                
                if arr.ndim == 1:
                    arr = arr.reshape(1, -1)
                
                dmatrix = xgb.DMatrix(arr)
                return booster.predict(dmatrix)
            
            return predict_fn
            
        except ImportError:
            raise RuntimeError("xgboost not installed, cannot load booster wrapper")
        except Exception as e:
            raise RuntimeError(f"failed to create XGBoost predictor: {e}")
    
    def predict(self, X: Any) -> Any:
        """Run prediction using the discovered predictor."""
        if self._predict_fn is None:
            raise RuntimeError("no predictor available")
        return self._predict_fn(X)
    
    @property
    def feature_names(self) -> Optional[List[str]]:
        """Return feature names if available, else None."""
        return self._feature_names
    
    @property
    def warning(self) -> Optional[str]:
        return self._warning


def _create_predictor(model: Any) -> PredictorAdapter:
    return PredictorAdapter(model)


class ModelRuntime:
    def __init__(self, store: ModelStore, smoke_input: Optional[Dict[str, Any]] = None,
                 type_key: Optional[str] = None) -> None:
        self.store = store
        self.type_key = type_key
        self.smoke_input = smoke_input or {}
        self._model: Optional[Any] = None
        self._predictor: Optional[PredictorAdapter] = None
        self._active_version: Optional[str] = None
        self._last_load_at: Optional[str] = None
        self._last_error: Optional[str] = None
        self._validation_error: Optional[str] = None
        self._lock = threading.RLock()

    # ── Properties ───────────────────────────────────────────────
    @property
    def is_loaded(self) -> bool:
        return self._predictor is not None

    @property
    def is_predictable(self) -> bool:
        """Returns True if the loaded model has a valid predictor."""
        return self._predictor is not None and self._predictor._predict_fn is not None

    @property
    def predictor_kind(self) -> Optional[str]:
        return self._predictor.kind if self._predictor else None

    @property
    def feature_count(self) -> Optional[int]:
        return self._predictor.feature_count if self._predictor else None

    @property
    def active_version(self) -> Optional[str]:
        return self._active_version

    @property
    def last_load_at(self) -> Optional[str]:
        return self._last_load_at

    @property
    def last_error(self) -> Optional[str]:
        return self._last_error

    @property
    def validation_error(self) -> Optional[str]:
        return self._validation_error

    @property
    def model_file(self) -> Optional[str]:
        if not self._active_version:
            return None
        return self.store.path_of(self._active_version)

    # ── Load / smoke test ────────────────────────────────────────
    def _load_model(self, path: str) -> Any:
        return _load_model_file(path)

    def _validate_and_create_predictor(self, model: Any) -> Dict[str, Any]:
        """Validate model by creating predictor and running smoke test.
        
        Validation FAILS if model feature count doesn't match registry.
        No silent padding/trimming - explicit error instead.
        
        Returns validation result with predictor metadata.
        """
        try:
            predictor = _create_predictor(model)
        except Exception as e:
            return {
                "ok": False,
                "error": str(e),
                "predictorKind": None,
                "featureCount": None,
            }
        
        model_feature_count = predictor.feature_count
        registry_count = len(self.smoke_input)
        
        # Validate feature count matches registry (if both are known)
        if model_feature_count is not None and registry_count > 0:
            if model_feature_count != registry_count:
                return {
                    "ok": False,
                    "error": f"Feature count mismatch: model expects {model_feature_count} features, but registry defines {registry_count} features. Please update registry or retrain model.",
                    "predictorKind": predictor.kind,
                    "featureCount": predictor.feature_count,
                }
        
        # Build smoke input
        if registry_count > 0:
            smoke_values = list(self.smoke_input.values())
        elif model_feature_count is not None:
            smoke_values = [0.0] * model_feature_count
        else:
            smoke_values = [0.0] * 8  # Default guess
        
        # Build input with proper column names for sklearn
        if pd is not None:
            if predictor.feature_names:
                X = pd.DataFrame([smoke_values], columns=predictor.feature_names)
            else:
                X = pd.DataFrame([smoke_values])
        else:
            X = [smoke_values]

        try:
            pred = predictor.predict(X)
            try:
                # Handle multi-dimensional arrays
                if hasattr(pred, 'flatten'):
                    pred = pred.flatten()
                if hasattr(pred, "__len__") and len(pred) > 0:
                    value = float(pred[0])
                else:
                    value = float(pred)
            except Exception:
                value = None
            
            return {
                "ok": True,
                "sample": value,
                "predictorKind": predictor.kind,
                "featureCount": predictor.feature_count,
                "warnings": [],
            }
        except Exception as e:
            return {
                "ok": False,
                "error": str(e),
                "predictorKind": predictor.kind,
                "featureCount": predictor.feature_count,
            }

    def try_load_version(self, version: str, *, require_smoke: bool = True) -> Dict[str, Any]:
        """Load a version off-line (doesn't swap). Returns validation result with predictor."""
        path = self.store.path_of(version)
        model = self._load_model(path)
        validation = self._validate_and_create_predictor(model)
        
        if require_smoke and not validation.get("ok"):
            raise RuntimeError(f"validation failed: {validation.get('error')}")
        
        return {
            "model": model,
            "validation": validation,
            "predictor": _create_predictor(model) if validation.get("ok") else None,
        }

    def swap_to(self, version: str, *, require_smoke: bool = True) -> Dict[str, Any]:
        loaded = self.try_load_version(version, require_smoke=require_smoke)
        with self._lock:
            self._model = loaded["model"]
            self._predictor = loaded.get("predictor")
            self._active_version = version
            self._last_load_at = _utc_now_iso()
            self._last_error = None
            self._validation_error = None if loaded["validation"].get("ok") else loaded["validation"].get("error")
        return loaded["validation"]

    def reload_active_from_disk(self) -> Optional[str]:
        """On startup: load whatever manifest says is active."""
        active = self.store.active_version()
        if not active:
            return None
        try:
            self.swap_to(active, require_smoke=True)  # Require validation on startup
            return active
        except Exception as e:
            self._last_error = f"startup load failed: {e}"
            return None

    def clear(self) -> None:
        """Clear the loaded model from memory (deactivate runtime)."""
        with self._lock:
            self._model = None
            self._predictor = None
            self._active_version = None
            self._last_error = None
            self._validation_error = None

    # ── Inference ────────────────────────────────────────────────
    def _current_ref(self) -> Tuple[Optional[PredictorAdapter], Optional[str]]:
        with self._lock:
            return self._predictor, self._active_version

    def predict_raw(self, features: Dict[str, Any]) -> Tuple[float, str, Optional[str]]:
        """Run prediction and return (value, version, warning).
        
        Raises error if feature count doesn't match model expectation.
        
        Raises:
            RuntimeError: if no model is loaded or predictor is invalid.
        """
        predictor, version = self._current_ref()
        if predictor is None:
            raise RuntimeError("no active model")

        feature_values = list(features.values())
        
        # Validate feature count matches (no silent padding)
        model_feature_count = predictor.feature_count
        input_count = len(feature_values)
        
        if model_feature_count is not None and input_count != model_feature_count:
            raise RuntimeError(
                f"Feature count mismatch: input has {input_count} features, but model expects {model_feature_count}"
            )

        # Build input with proper column names for sklearn
        if pd is not None and predictor.feature_names:
            X = pd.DataFrame([feature_values], columns=predictor.feature_names)
        elif pd is not None:
            X = pd.DataFrame([feature_values])
        else:
            X = [feature_values]
        
        pred = predictor.predict(X)
        try:
            # Handle multi-dimensional arrays (e.g., Keras returns [[value]])
            import numpy as np
            if hasattr(pred, 'flatten'):
                pred = pred.flatten()
            if hasattr(pred, "__len__") and len(pred) > 0:
                value = float(pred[0])
            else:
                value = float(pred)
        except Exception as e:
            raise RuntimeError(f"invalid model output: {e}")
        
        warning = predictor.warning
        
        return value, version or "unknown", warning
