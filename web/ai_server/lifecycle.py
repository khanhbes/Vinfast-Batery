"""Model lifecycle controls for range prediction and charging-time prediction.

The module is dependency-light so it can be used during training and at runtime.
It intentionally never promotes a candidate model by itself: promotion requires a
quality gate and begins in canary mode.
"""
from __future__ import annotations

import hashlib
import json
import math
import os
from collections import defaultdict
from datetime import datetime, timezone
from typing import Any, Iterable

SUPPORTED_TASKS = {"range_prediction", "charging_time"}
MIN_PERSONAL_SAMPLES = 30
MIN_PERSONAL_DAYS = 14


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def _timestamp(row: dict[str, Any]) -> str:
    return str(row.get("measuredAt") or row.get("recordedAt") or row.get("createdAt") or row.get("startedAt") or "")


def dataset_manifest(task: str, rows: Iterable[dict[str, Any]]) -> dict[str, Any]:
    if task not in SUPPORTED_TASKS:
        raise ValueError("task phải là range_prediction hoặc charging_time")
    cleaned = [dict(r) for r in rows]
    canonical = json.dumps(cleaned, ensure_ascii=False, sort_keys=True, default=str, separators=(",", ":"))
    vehicles = sorted({str(r.get("vehicleId") or r.get("vehicle_id") or "unknown") for r in cleaned})
    timestamps = sorted(t for t in (_timestamp(r) for r in cleaned) if t)
    digest = hashlib.sha256(canonical.encode("utf-8")).hexdigest()
    return {
        "datasetVersion": f"{task}-ds-{digest[:12]}",
        "task": task,
        "fingerprint": digest,
        "rowCount": len(cleaned),
        "vehicleCount": len(vehicles),
        "vehicles": vehicles,
        "timeRange": {"start": timestamps[0] if timestamps else None, "end": timestamps[-1] if timestamps else None},
        "createdAt": utc_now(),
    }


def split_by_vehicle_and_time(rows: Iterable[dict[str, Any]], validation_ratio: float = 0.2, test_ratio: float = 0.2) -> dict[str, list[dict[str, Any]]]:
    """Chronological split inside each vehicle; future rows never train earlier rows.

    Vehicles with fewer than three rows remain in train and are reported by the
    manifest rather than being randomly leaked into validation/test.
    """
    if validation_ratio <= 0 or test_ratio <= 0 or validation_ratio + test_ratio >= 1:
        raise ValueError("validation_ratio + test_ratio phải nằm trong (0, 1)")
    grouped: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in rows:
        item = dict(row)
        grouped[str(item.get("vehicleId") or item.get("vehicle_id") or "unknown")].append(item)
    result = {"train": [], "validation": [], "test": []}
    for vehicle_rows in grouped.values():
        vehicle_rows.sort(key=_timestamp)
        count = len(vehicle_rows)
        if count < 3:
            result["train"].extend(vehicle_rows)
            continue
        test_n = max(1, int(math.ceil(count * test_ratio)))
        validation_n = max(1, int(math.ceil(count * validation_ratio)))
        train_n = count - test_n - validation_n
        if train_n < 1:
            train_n, validation_n, test_n = 1, 1, count - 2
        result["train"].extend(vehicle_rows[:train_n])
        result["validation"].extend(vehicle_rows[train_n:train_n + validation_n])
        result["test"].extend(vehicle_rows[train_n + validation_n:])
    return result


def regression_metrics(actual: Iterable[float], predicted: Iterable[float], *, task: str) -> dict[str, float]:
    actual_values, predicted_values = list(actual), list(predicted)
    if not actual_values or len(actual_values) != len(predicted_values):
        raise ValueError("actual và predicted phải có cùng số phần tử > 0")
    errors = [float(p) - float(a) for a, p in zip(actual_values, predicted_values)]
    absolute = [abs(e) for e in errors]
    mae = sum(absolute) / len(absolute)
    rmse = math.sqrt(sum(e * e for e in errors) / len(errors))
    result = {"mae": round(mae, 6), "rmse": round(rmse, 6), "bias": round(sum(errors) / len(errors), 6), "sampleCount": len(errors)}
    if task == "charging_time":
        result["timeErrorSeconds"] = round(mae, 3)
    if task == "range_prediction":
        result["rangeErrorKm"] = round(mae, 3)
    return result


def promotion_gate(candidate: dict[str, Any], baseline: dict[str, Any], *, task: str) -> dict[str, Any]:
    """Candidate must improve MAE and not materially worsen RMSE or bias."""
    c_mae, b_mae = float(candidate["mae"]), float(baseline["mae"])
    c_rmse, b_rmse = float(candidate["rmse"]), float(baseline["rmse"])
    c_bias = abs(float(candidate.get("bias", 0)))
    b_bias = abs(float(baseline.get("bias", 0)))
    reasons = []
    if int(candidate.get("sampleCount", 0)) < 20:
        reasons.append("test_sample_count_below_20")
    if c_mae > b_mae * 0.98:
        reasons.append("mae_not_improved_by_2_percent")
    if c_rmse > b_rmse * 1.03:
        reasons.append("rmse_regression_over_3_percent")
    if c_bias > max(b_bias * 1.1, 0.25):
        reasons.append("bias_regression")
    return {
        "task": task, "approved": not reasons, "mode": "canary" if not reasons else "rejected",
        "canaryTrafficPercent": 10 if not reasons else 0,
        "reasons": reasons,
        "candidateMetrics": candidate, "baselineMetrics": baseline, "evaluatedAt": utc_now(),
    }


def personal_ai_eligibility(rows: Iterable[dict[str, Any]]) -> dict[str, Any]:
    items = list(rows)
    verified = [r for r in items if r.get("actual_end_soc") is not None or r.get("actualValue") is not None]
    dates = {(_timestamp(r) or "")[:10] for r in verified if _timestamp(r)}
    reasons = []
    if len(verified) < MIN_PERSONAL_SAMPLES:
        reasons.append(f"need_{MIN_PERSONAL_SAMPLES - len(verified)}_more_verified_samples")
    if len(dates) < MIN_PERSONAL_DAYS:
        reasons.append(f"need_{MIN_PERSONAL_DAYS - len(dates)}_more_data_days")
    return {"eligible": not reasons, "verifiedSamples": len(verified), "dataDays": len(dates), "minimumSamples": MIN_PERSONAL_SAMPLES, "minimumDays": MIN_PERSONAL_DAYS, "reasons": reasons}


def detect_drift(baseline: Iterable[float], recent: Iterable[float], threshold: float = 0.20) -> dict[str, Any]:
    """Mean-shift detector for a monitored feature/error series.

    It is deliberately conservative: insufficient data is never marked healthy.
    """
    old, new = [float(v) for v in baseline], [float(v) for v in recent]
    if len(old) < 20 or len(new) < 20:
        return {"status": "insufficient_data", "baselineCount": len(old), "recentCount": len(new), "driftScore": None}
    old_mean = sum(old) / len(old)
    new_mean = sum(new) / len(new)
    scale = max(abs(old_mean), 1e-6)
    score = abs(new_mean - old_mean) / scale
    return {"status": "drift_detected" if score >= threshold else "stable", "baselineCount": len(old), "recentCount": len(new), "baselineMean": round(old_mean, 6), "recentMean": round(new_mean, 6), "driftScore": round(score, 6), "threshold": threshold, "checkedAt": utc_now()}


class LifecycleStore:
    """Small durable registry for datasets, deployment state and prediction audit."""
    def __init__(self, root: str):
        self.root = root
        os.makedirs(root, exist_ok=True)

    def _path(self, task: str) -> str:
        if task not in SUPPORTED_TASKS:
            raise ValueError("task không hỗ trợ")
        return os.path.join(self.root, f"{task}.lifecycle.json")

    def read(self, task: str) -> dict[str, Any]:
        try:
            with open(self._path(task), encoding="utf-8") as file:
                return json.load(file)
        except (OSError, json.JSONDecodeError):
            return {"task": task, "datasets": [], "deployments": [], "predictionAudit": [], "drift": {"status": "unknown"}}

    def write(self, task: str, data: dict[str, Any]) -> dict[str, Any]:
        temp = self._path(task) + ".tmp"
        with open(temp, "w", encoding="utf-8") as file:
            json.dump(data, file, ensure_ascii=False, indent=2)
        os.replace(temp, self._path(task))
        return data

    def register_dataset(self, task: str, rows: Iterable[dict[str, Any]]) -> dict[str, Any]:
        manifest = dataset_manifest(task, rows)
        data = self.read(task)
        if not any(d.get("datasetVersion") == manifest["datasetVersion"] for d in data["datasets"]):
            data["datasets"].append(manifest)
            data["datasets"] = data["datasets"][-20:]
            self.write(task, data)
        return manifest

    def evaluate_candidate(self, task: str, candidate: dict[str, Any], baseline: dict[str, Any], candidate_version: str, dataset: dict[str, Any]) -> dict[str, Any]:
        decision = promotion_gate(candidate, baseline, task=task)
        decision.update({"candidateVersion": candidate_version, "datasetVersion": dataset["datasetVersion"]})
        data = self.read(task)
        data["deployments"].append(decision)
        data["deployments"] = data["deployments"][-50:]
        self.write(task, data)
        return decision

    def record_prediction(self, task: str, model_version: str, value: float, confidence: float, reason: str, context: dict[str, Any] | None = None) -> dict[str, Any]:
        if not 0 <= float(confidence) <= 1:
            raise ValueError("confidence phải trong khoảng 0–1")
        item = {"predictionId": hashlib.sha256(f"{task}:{model_version}:{utc_now()}".encode()).hexdigest()[:16], "modelVersion": model_version, "value": value, "confidence": confidence, "reason": reason, "context": context or {}, "predictedAt": utc_now()}
        data = self.read(task)
        data["predictionAudit"] = (data["predictionAudit"] + [item])[-500:]
        self.write(task, data)
        return item


def vehicle_adapter_quality_gate(
    adapter: dict[str, Any],
    baseline_mape: float = 15.0,
) -> dict[str, Any]:
    """Quality gate deciding whether a vehicle adapter is qualified for promotion."""
    session_count = int(adapter.get("session_count", 0))
    val_mape = float(adapter.get("validation_mape", 99.0))
    stage = str(adapter.get("personalization_stage", "base"))

    if session_count < 5:
        return {
            "promoted": False,
            "stage": stage,
            "reason": f"Chưa đủ dữ liệu (cần ít nhất 5 phiên, hiện có {session_count})",
        }

    if val_mape > baseline_mape:
        return {
            "promoted": False,
            "stage": stage,
            "reason": f"MAPE ({val_mape:.1f}%) vượt ngưỡng tối đa ({baseline_mape:.1f}%)",
        }

    return {
        "promoted": True,
        "stage": stage,
        "reason": f"Đạt chuẩn chất lượng (MAPE: {val_mape:.1f}%, Sessions: {session_count})",
    }

