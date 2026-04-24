"""PredictionService — validates input, runs inference, formats the response.

Formula for time-series / recommendations keeps the legacy Flask behavior to avoid
breaking the app contract. The ML model's `predict()` result is used as the
*initial-hour drain* factor; the rest is heuristic decay so the shape of the
timeSeries stays comparable to what the mobile app already renders.
"""
from __future__ import annotations

from datetime import datetime, timezone
from typing import List

from .model_runtime import ModelRuntime
from .schemas import PredictRequest, PredictResponse


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


class PredictionService:
    def __init__(self, runtime: ModelRuntime) -> None:
        self.runtime = runtime

    def predict(self, req: PredictRequest) -> PredictResponse:
        # ── Consumption rate: prefer ML model, fallback to heuristic ─────
        base_rate = 0.5 + (req.avgSpeed / 100.0) + (req.temperature / 100.0)
        if req.weatherCondition == "rain":
            base_rate += 0.3
        elif req.weatherCondition == "hot":
            base_rate += 0.2

        version = "heuristic-1.0"
        if self.runtime.is_loaded:
            try:
                drain_pct, version, _warning = self.runtime.predict_raw(req.model_dump())
                # Use ML output as *total* 24h drain signal; convert to hourly rate
                hourly_from_model = max(0.05, float(drain_pct) / 24.0)
                # Blend to avoid wild divergence from heuristic
                base_rate = 0.5 * base_rate + 0.5 * hourly_from_model
            except Exception as e:
                # Graceful fallback: still return a prediction
                version = f"heuristic-fallback ({e})"

        # ── Time series (24 hours) ───────────────────────────────────────
        series: List[float] = []
        soc = float(req.currentBattery)
        for _ in range(24):
            soc = max(0.0, soc - base_rate)
            series.append(round(soc, 3))

        # ── Battery health heuristic (kept for API compat) ───────────────
        health = 100.0
        health -= req.odometer / 1000.0
        if req.temperature > 35:
            health -= 10
        if req.current > 50:
            health -= 5
        health = max(0.0, min(100.0, health))

        # ── Recommendations ──────────────────────────────────────────────
        recs: List[str] = []
        if req.temperature > 35:
            recs.append("Nhiệt độ pin cao, nên đỗ xe trong bóng mát")
        if req.currentBattery < 20:
            recs.append("Pin yếu, nên sạc sớm")
        if health < 80:
            recs.append("Sức khỏe pin giảm, cân nhắc bảo dưỡng")
        if req.avgSpeed > 60:
            recs.append("Tốc độ cao, tiêu thụ pin tăng")

        return PredictResponse(
            predictedSOC=series[-1] if series else float(req.currentBattery),
            confidence=round(85.0 + (health / 20.0), 2),
            timeSeries=series,
            batteryHealth=round(health, 2),
            recommendations=recs,
            timestamp=_utc_now_iso(),
            modelVersion=version,
        )
