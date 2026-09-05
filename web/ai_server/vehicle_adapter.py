"""Per-Vehicle Adapter for VinFast smart charging personalization.

Combines a pre-trained global base model with per-vehicle calibration parameters:
- global_time_scale: overall speed ratio vs global fleet
- global_time_bias_minutes: systematic offset
- soc_bands: calibration parameters for 0-20%, 20-80%, and 80-100% ranges
- effective_capacity_wh: measured battery capacity
- personalization_stage: 'base' (<5), 'calibrating' (5-29), 'personalized' (>=30)
"""
from __future__ import annotations

import json
import logging
import math
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

logger = logging.getLogger("VehicleAdapter")


class VehicleAdapter:
    def __init__(self, data: dict[str, Any]) -> None:
        self.data = data
        self.vehicle_id = str(data.get("vehicle_id", "unknown"))
        self.version = str(data.get("adapter_version", "v1"))
        self.global_time_scale = float(data.get("global_time_scale", 1.0))
        self.global_time_bias_minutes = float(data.get("global_time_bias_minutes", 0.0))
        self.power_scale = float(data.get("power_scale", 1.0))
        self.soc_bands = data.get("soc_bands") or {
            "0-20": {"scale": 1.0, "bias": 0.0},
            "20-80": {"scale": 1.0, "bias": 0.0},
            "80-100": {"scale": 1.0, "bias": 0.0},
        }
        self.effective_capacity_wh = float(data.get("effective_capacity_wh", 3500.0))
        self.wh_per_soc_avg = float(data.get("wh_per_soc_avg", 35.0))
        self.validation_mape = float(data.get("validation_mape", 0.0))
        self.session_count = int(data.get("session_count", 0))
        self.data_days = int(data.get("data_days", 0))
        self.personalization_stage = str(data.get("personalization_stage", "base"))
        self.trained_at = str(data.get("trained_at", datetime.now(timezone.utc).isoformat()))

    def to_dict(self) -> dict[str, Any]:
        return {
            "vehicle_id": self.vehicle_id,
            "adapter_version": self.version,
            "global_time_scale": round(self.global_time_scale, 4),
            "global_time_bias_minutes": round(self.global_time_bias_minutes, 2),
            "power_scale": round(self.power_scale, 4),
            "soc_bands": self.soc_bands,
            "effective_capacity_wh": round(self.effective_capacity_wh, 1),
            "wh_per_soc_avg": round(self.wh_per_soc_avg, 2),
            "validation_mape": round(self.validation_mape, 2),
            "session_count": self.session_count,
            "data_days": self.data_days,
            "personalization_stage": self.personalization_stage,
            "trained_at": self.trained_at,
        }

    def adjust_prediction(
        self,
        base_seconds: float,
        start_soc: float,
        target_soc: float,
    ) -> float:
        """Applies adapter adjustments and blends with base prediction according to stage."""
        if target_soc <= start_soc:
            return 0.0

        total_delta = target_soc - start_soc

        # Compute overlap with bands: 0-20, 20-80, 80-100
        bands_def = [
            ("0-20", 0.0, 20.0),
            ("20-80", 20.0, 80.0),
            ("80-100", 80.0, 100.0),
        ]

        weighted_band_scale = 0.0
        weighted_band_bias_s = 0.0

        for band_key, band_low, band_high in bands_def:
            overlap_low = max(start_soc, band_low)
            overlap_high = min(target_soc, band_high)
            overlap = max(0.0, overlap_high - overlap_low)

            fraction = overlap / total_delta if total_delta > 0 else 0.0
            band_info = self.soc_bands.get(band_key, {"scale": 1.0, "bias": 0.0})
            scale = float(band_info.get("scale", 1.0))
            bias_min = float(band_info.get("bias", 0.0))

            weighted_band_scale += fraction * scale
            weighted_band_bias_s += fraction * (bias_min * 60.0)

        # Scale by global time scale
        effective_scale = weighted_band_scale * self.global_time_scale
        effective_bias_s = weighted_band_bias_s + (self.global_time_bias_minutes * 60.0)

        adapted_seconds = max(60.0, (base_seconds * effective_scale) + effective_bias_s)

        # Blend weights by stage
        if self.personalization_stage == "base" or self.session_count < 5:
            return round(base_seconds, 1)
        elif self.personalization_stage == "calibrating":
            # 30% adapter, 70% global
            blended = 0.70 * base_seconds + 0.30 * adapted_seconds
            return round(blended, 1)
        else:
            # personalized: 70% adapter, 30% global
            blended = 0.30 * base_seconds + 0.70 * adapted_seconds
            return round(blended, 1)


class VehicleAdapterTrainer:
    """Trains a VehicleAdapter using verified charging history sessions for a vehicle."""

    def __init__(self, adapters_dir: str | Path = "models/vehicle_adapters") -> None:
        self.adapters_dir = Path(adapters_dir)
        self.adapters_dir.mkdir(parents=True, exist_ok=True)

    def _adapter_file(self, vehicle_id: str) -> Path:
        clean_id = "".join(c for c in vehicle_id if c.isalnum() or c in ("-", "_"))
        return self.adapters_dir / f"{clean_id}.json"

    def load_adapter(self, vehicle_id: str) -> VehicleAdapter | None:
        path = self._adapter_file(vehicle_id)
        if not path.exists():
            return None
        try:
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)
            return VehicleAdapter(data)
        except Exception as e:
            logger.error("Failed to load adapter for %s: %s", vehicle_id, e)
            return None

    def save_adapter(self, adapter: VehicleAdapter) -> None:
        path = self._adapter_file(adapter.vehicle_id)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(adapter.to_dict(), f, indent=2, ensure_ascii=False)

    def list_all_adapters(self) -> list[dict[str, Any]]:
        results: list[dict[str, Any]] = []
        for path in self.adapters_dir.glob("*.json"):
            try:
                with open(path, "r", encoding="utf-8") as f:
                    results.append(json.load(f))
            except Exception:
                continue
        return results

    def train_adapter(
        self,
        vehicle_id: str,
        sessions: list[dict[str, Any]],
        base_model_predict_fn: Any | None = None,
    ) -> VehicleAdapter:
        """Trains a new adapter for a vehicle given its historical sessions."""
        valid_sessions: list[dict[str, Any]] = []
        timestamps: list[float] = []

        for s in sessions:
            start_soc = float(s.get("start_soc") or 0)
            actual_end_soc = s.get("actual_end_soc")
            end_soc = float(actual_end_soc) if actual_end_soc is not None else float(s.get("target_soc") or 0)
            delta = end_soc - start_soc
            energy_wh = float(s.get("energy_used_wh") or s.get("energyWh") or 0)
            dur_s = float(s.get("actual_duration_seconds") or 0)

            if dur_s <= 0 and s.get("started_at") and s.get("stopped_at"):
                try:
                    t0 = datetime.fromisoformat(str(s["started_at"]).replace("Z", "+00:00")).timestamp()
                    t1 = datetime.fromisoformat(str(s["stopped_at"]).replace("Z", "+00:00")).timestamp()
                    dur_s = max(60.0, t1 - t0)
                except Exception:
                    pass

            if delta >= 5.0 and dur_s >= 300 and energy_wh > 0:
                valid_sessions.append({
                    "start_soc": start_soc,
                    "end_soc": end_soc,
                    "delta_soc": delta,
                    "energy_wh": energy_wh,
                    "duration_s": dur_s,
                    "wh_per_soc": energy_wh / delta,
                })
                # Collect date
                date_val = s.get("created_at") or s.get("started_at")
                if date_val:
                    try:
                        ts = datetime.fromisoformat(str(date_val).replace("Z", "+00:00")).timestamp()
                        timestamps.append(ts)
                    except Exception:
                        pass

        session_count = len(valid_sessions)
        data_days = 0
        if len(timestamps) >= 2:
            data_days = max(1, int((max(timestamps) - min(timestamps)) / 86400.0))

        # Determine stage
        if session_count < 5:
            stage = "base"
        elif session_count < 30 or data_days < 14:
            stage = "calibrating"
        else:
            stage = "personalized"

        if session_count == 0:
            adapter = VehicleAdapter({
                "vehicle_id": vehicle_id,
                "session_count": 0,
                "personalization_stage": "base",
            })
            self.save_adapter(adapter)
            return adapter

        # Compute effective capacity Wh & Wh/SOC
        wh_per_soc_list = [vs["wh_per_soc"] for vs in valid_sessions]
        avg_wh_per_soc = sum(wh_per_soc_list) / len(wh_per_soc_list)
        effective_capacity_wh = avg_wh_per_soc * 100.0

        # Compute ratio of actual duration vs base predicted duration
        ratios: list[float] = []
        errors_min: list[float] = []

        # Band-specific ratios
        band_ratios: dict[str, list[float]] = {"0-20": [], "20-80": [], "80-100": []}

        for vs in valid_sessions:
            start_s = vs["start_soc"]
            end_s = vs["end_soc"]
            delta = vs["delta_soc"]
            actual_s = vs["duration_s"]

            # Expected duration from base model or physics
            if base_model_predict_fn is not None:
                try:
                    pred_s = float(base_model_predict_fn(start_s, end_s))
                except Exception:
                    pred_s = delta * (3600.0 / 22.5)
            else:
                pred_s = delta * (3600.0 / 22.5)

            if pred_s > 0:
                ratio = actual_s / pred_s
                ratios.append(ratio)
                errors_min.append((actual_s - pred_s) / 60.0)

                # Segment into bands
                if start_s < 20.0:
                    band_ratios["0-20"].append(ratio)
                if start_s < 80.0 and end_s > 20.0:
                    band_ratios["20-80"].append(ratio)
                if end_s > 80.0:
                    band_ratios["80-100"].append(ratio)

        global_time_scale = max(0.5, min(2.0, sum(ratios) / len(ratios))) if ratios else 1.0
        global_time_bias_min = (sum(errors_min) / len(errors_min)) if errors_min else 0.0

        soc_bands = {}
        for b_name in ("0-20", "20-80", "80-100"):
            b_list = band_ratios[b_name]
            b_scale = max(0.6, min(2.5, sum(b_list) / len(b_list))) if b_list else 1.0
            soc_bands[b_name] = {"scale": round(b_scale, 3), "bias": 0.0}

        # Calculate validation MAPE
        mapes: list[float] = []
        for vs in valid_sessions:
            actual_s = vs["duration_s"]
            # Base prediction
            pred_s = vs["delta_soc"] * (3600.0 / 22.5)
            adapted_s = pred_s * global_time_scale + (global_time_bias_min * 60.0)
            err = abs(actual_s - adapted_s) / actual_s if actual_s > 0 else 0.0
            mapes.append(err * 100.0)

        validation_mape = sum(mapes) / len(mapes) if mapes else 10.0

        adapter_data = {
            "vehicle_id": vehicle_id,
            "adapter_version": f"v{int(datetime.now(timezone.utc).timestamp())}",
            "global_time_scale": global_time_scale,
            "global_time_bias_minutes": global_time_bias_min,
            "power_scale": 1.0,
            "soc_bands": soc_bands,
            "effective_capacity_wh": effective_capacity_wh,
            "wh_per_soc_avg": avg_wh_per_soc,
            "validation_mape": validation_mape,
            "session_count": session_count,
            "data_days": data_days,
            "personalization_stage": stage,
            "trained_at": datetime.now(timezone.utc).isoformat(),
        }

        adapter = VehicleAdapter(adapter_data)
        self.save_adapter(adapter)
        logger.info(
            "[VehicleAdapter] Saved adapter for %s (sessions: %d, stage: %s, MAPE: %.1f%%)",
            vehicle_id,
            session_count,
            stage,
            validation_mape,
        )
        return adapter
