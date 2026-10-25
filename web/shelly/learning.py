"""Per-vehicle learning data and owner-triggered training (Task 127).

Data is collected silently:

* charging: every finished charge with a known end % (the owner's reading, or
  the full-battery power tail seen by the server) is queued on the charge
  profile (``charge_model.queue_sample``);
* rides: trips recorded from the trip planner, rides imported from a CSV, and
  odometer segments between two battery/ODO readings with no charge between.

The estimates change only when the owner presses "Huấn luyện" (finetune) or
"Huấn luyện lại" (retrain); both keep the current model if the new one is not
better. Readiness (enough new data) is reported so the app can tell the owner.
"""

from __future__ import annotations

import hashlib
import math
import re
import uuid
from datetime import datetime, timedelta, timezone

from . import charge_model


class _LazyTripModel:
    """assistant.trip_model is imported on first use: the worker image ships
    only shelly/ and never needs the trip model."""

    def __getattr__(self, name):
        from assistant import trip_model as module
        return getattr(module, name)


trip_model = _LazyTripModel()
_TRIP_ID_TIME = re.compile(r"(\d{4}-\d{2}-\d{2})T(\d{2})(\d{2})(\d{2})")

READING_SOURCES = {"manual", "chat", "photo", "charge_end", "trip_start", "trip_end"}
MAX_IMPORT_ROWS = 500
# A reading pair this far apart is still one ride segment if no charge ran.
MAX_SEGMENT_DAYS = 14
MIN_SEGMENT_USED_PCT = 3.0


def _iso(value: datetime) -> str:
    return value.astimezone(timezone.utc).isoformat()


def _parse(value) -> datetime | None:
    if isinstance(value, datetime):
        return value if value.tzinfo else value.replace(tzinfo=timezone.utc)
    try:
        parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except (TypeError, ValueError):
        return None
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)


def _float(value, low: float, high: float) -> float | None:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    return number if math.isfinite(number) and low <= number <= high else None


class VehicleLearningMixin:
    """Mixed into SmartChargeService (needs repository, clock, _owned_vehicle)."""

    # -- helpers -------------------------------------------------------------
    def _learning_error(self, code: str, message: str, status: int = 400):
        from .service import SmartChargeError
        return SmartChargeError(code, message, status)

    def _charge_base(self, vehicle: dict, session=None) -> float | None:
        capacity = (_float(vehicle.get("nominalCapacityWh"), 1, 1e6)
                    or (session.nominal_capacity_wh if session else None)
                    or (session.effective_capacity_wh if session else None))
        return charge_model.default_wh_per_pct(capacity, _float(vehicle.get("stateOfHealth"), 1, 120))

    def _catalog_km_per_pct(self, vehicle: dict) -> float | None:
        efficiency = (_float(vehicle.get("kmPerPercent"), 0.05, 10)
                      or _float(vehicle.get("defaultEfficiency"), 0.05, 10))
        soh = _float(vehicle.get("stateOfHealth"), 1, 100) if vehicle.get("hasSohData") is not False else None
        return trip_model.catalog_km_per_pct(efficiency, soh)

    def current_trip_params(self, uid: str, vehicle_id: str, vehicle: dict | None = None,
                            profile=None) -> trip_model.TripModelParams | None:
        """Trained model > ODO-learned km/% > catalog."""
        vehicle = vehicle if vehicle is not None else self._owned_vehicle(uid, vehicle_id)
        profile = profile or self.repository.get_personal_profile(uid, vehicle_id)
        trained = trip_model.TripModelParams.from_dict(profile.trip_model if profile else None)
        if trained is not None:
            return trained
        catalog = self._catalog_km_per_pct(vehicle)
        readings = [{"endedAt": _iso(item.stopped_at) if item.stopped_at else "",
                     "startSoc": item.start_soc, "actualEndSoc": item.actual_end_soc,
                     "odoKm": item.end_odo_km}
                    for item in self.repository.history(uid, limit=40)
                    if item.vehicle_id == vehicle_id]
        learned, _ = trip_model.learned_km_per_pct(readings, catalog)
        if learned:
            return trip_model.params_from_km_per_pct(learned, "odo")
        if catalog:
            return trip_model.params_from_km_per_pct(catalog, "catalog")
        return None

    # -- charging data -------------------------------------------------------
    def queue_charge_label(self, uid: str, session, *, label_source: str) -> str:
        """Queue a finished charge with a known end % for the next training."""
        if session.energy_quality == "meter_reset":
            return "energy_invalid"
        profile = self.repository.get_personal_profile(uid, session.vehicle_id)
        if profile is not None and not profile.consent_enabled:
            return "consent_disabled"
        try:
            vehicle = self._owned_vehicle(uid, session.vehicle_id)
        except Exception:
            return "vehicle_unavailable"
        if profile is None:
            # Typing the battery % to improve the estimate is the opt-in; the
            # Personal AI switch can still turn learning off.
            profile = self.personal_profile(uid, session.vehicle_id)
            profile.consent_enabled = True
            profile.consent_source = "default"
        end_pct = 100.0 if label_source == "taper_full" else float(session.actual_end_soc or 0)
        base = self._charge_base(vehicle, session)
        learned = charge_model.LearnedProfile.from_dict(profile.learned)
        sample_wh = charge_model.wh_per_pct_sample(session.energy_used_wh, session.start_soc, end_pct)
        taper = (charge_model.learn_taper(session.telemetry_samples, session.start_soc, sample_wh)
                 if sample_wh else None)
        now = self.clock()
        queued, decision = charge_model.queue_sample(learned, {
            "sessionId": session.session_id,
            "energyWh": session.energy_used_wh,
            "startPct": session.start_soc,
            "actualEndPct": end_pct,
            "estimatedEndPct": session.estimated_soc,
            "avgPowerW": session.average_power_w,
            "at": (session.stopped_at or now).isoformat(),
            "taperStartPct": taper[0] if taper else None,
            "taperPowerRatio": taper[1] if taper else None,
            "labelSource": label_source,
        }, base_wh_per_pct=base, now=now)
        if decision != "queued":
            return decision
        profile.learned = queued.to_dict()
        profile.updated_at = now
        self.repository.save_personal_profile(profile)
        self.repository.append_audit(uid, "charge_label_queued", session_id=session.session_id,
                                     label_source=label_source)
        return decision

    # -- readings ------------------------------------------------------------
    def add_battery_reading(self, uid: str, vehicle_id: str, body: dict, *,
                            with_status: bool = True) -> dict:
        vehicle = self._owned_vehicle(uid, vehicle_id)
        soc = _float(body.get("soc"), 0, 100) if body.get("soc") not in (None, "") else None
        odo = _float(body.get("odoKm"), 0, 500000) if body.get("odoKm") not in (None, "") else None
        if body.get("soc") not in (None, "") and soc is None:
            raise self._learning_error("invalidSoc", "% pin phải từ 0 đến 100.")
        if body.get("odoKm") not in (None, "") and odo is None:
            raise self._learning_error("invalidOdo", "ODO không hợp lệ.")
        if soc is None and odo is None:
            raise self._learning_error("readingEmpty", "Nhập % pin hoặc ODO.")
        source = str(body.get("source") or "manual")
        if source not in READING_SOURCES:
            source = "manual"
        now = self.clock()
        at = _parse(body.get("at")) or now
        if at > now + timedelta(minutes=5) or at < now - timedelta(days=7):
            at = now
        previous = self.repository.battery_readings(uid, vehicle_id, limit=5)
        last_odo = next((float(item["odoKm"]) for item in previous if item.get("odoKm") is not None), None)
        current_odo = _float(vehicle.get("currentOdo"), 0, 500000)
        floor = max([value for value in (last_odo, current_odo) if value is not None], default=None)
        if odo is not None and floor is not None and odo < floor - 0.5:
            raise self._learning_error(
                "odoDecreased",
                f"ODO mới ({odo:.0f} km) nhỏ hơn số đã lưu ({floor:.0f} km). Kiểm tra lại số trên đồng hồ.",
                409)
        reading = {
            "id": uuid.uuid4().hex[:20], "at": _iso(at), "soc": soc, "odoKm": odo,
            "source": source, "sessionId": str(body.get("sessionId") or "") or None,
            "createdAt": _iso(now),
        }
        saved = self.repository.add_battery_reading(uid, vehicle_id, reading)
        fields = {"lastReadingAt": _iso(at)}
        if soc is not None:
            # batteryDataUpdatedAt too (QA 129): without it a charge that
            # ended earlier but was finalized later overwrote this reading.
            fields.update({"currentBattery": int(round(soc)), "lastBatteryPercent": int(round(soc)),
                           "hasBatteryData": True, "batteryDataUpdatedAt": at,
                           "batteryDataSource": f"reading_{source}"})
        if odo is not None:
            fields.update({"currentOdo": int(round(odo)), "hasOdoData": True})
        updater = getattr(self.repository, "update_vehicle_fields", None)
        if updater is not None:
            updater(uid, vehicle_id, fields)
        segment = self._segment_from_readings(uid, vehicle_id, saved, previous)
        # The confirmation path does not show the status: skipping it saves
        # several reads on a request that took ~9.5 s (QA 129).
        return {"reading": saved, "segment": segment,
                "training": self.learning_status(uid, vehicle_id, vehicle=vehicle)
                if with_status else None}

    def void_battery_reading(self, uid: str, vehicle_id: str, reading_id: str) -> dict:
        self._owned_vehicle(uid, vehicle_id)
        if not self.repository.void_battery_reading(uid, vehicle_id, reading_id):
            raise self._learning_error("readingNotFound", "Không tìm thấy lần nhập này.", 404)
        return {"voided": True}

    def _segment_from_readings(self, uid: str, vehicle_id: str, reading: dict,
                               previous: list[dict]) -> dict | None:
        """Two readings with % and ODO and no charge between = one ride."""
        if reading.get("soc") is None or reading.get("odoKm") is None:
            return None
        if reading.get("source") == "trip_end":
            return None  # the recorded ride itself is the sample
        before = next((item for item in previous
                       if item.get("soc") is not None and item.get("odoKm") is not None), None)
        if before is None:
            return None
        start, end = _parse(before.get("at")), _parse(reading.get("at"))
        if start is None or end is None or end <= start or end - start > timedelta(days=MAX_SEGMENT_DAYS):
            return None
        km = float(reading["odoKm"]) - float(before["odoKm"])
        used = float(before["soc"]) - float(reading["soc"])
        if km < 1 or used < MIN_SEGMENT_USED_PCT:
            return None
        for session in self.repository.history(uid, limit=40):
            if session.vehicle_id != vehicle_id:
                continue
            began = session.created_at if session.created_at.tzinfo else session.created_at.replace(tzinfo=timezone.utc)
            if start <= began <= end:
                return None  # a charge in between: % went up, not a ride
        sample = trip_model.normalize_sample({"distanceKm": km, "socUsed": used,
                                              "startSoc": before["soc"], "endSoc": reading["soc"]})
        if sample is None:
            return None
        sample.update({"id": f"seg_{reading['id']}", "source": "odo_segment", "at": reading["at"]})
        self.repository.save_trip_samples(uid, vehicle_id, [sample])
        return sample

    # -- rides ---------------------------------------------------------------
    def add_trip_samples(self, uid: str, vehicle_id: str, rows: list, *, source: str) -> dict:
        vehicle = self._owned_vehicle(uid, vehicle_id)
        if not isinstance(rows, list) or not rows:
            raise self._learning_error("tripsEmpty", "Không có chuyến đi nào để lưu.")
        if len(rows) > MAX_IMPORT_ROWS:
            raise self._learning_error("tooManyTrips", f"Mỗi lần nhập tối đa {MAX_IMPORT_ROWS} chuyến.")
        now = self.clock()
        accepted, rejected = [], 0
        for raw in rows:
            if not isinstance(raw, dict):
                rejected += 1
                continue
            sample = trip_model.normalize_sample(raw)
            if sample is None:
                rejected += 1
                continue
            key = str(raw.get("clientId") or raw.get("trip_id") or "").strip()[:120]
            if not key:
                key = f"{raw.get('at') or ''}|{sample['distanceKm']}|{sample['socUsed']}"
            digest = hashlib.sha256(f"{vehicle_id}|{key}".encode()).hexdigest()[:24]
            at = _parse(raw.get("at")) or _trip_id_time(key) or now
            sample.update({"id": f"{'csv' if source == 'csv' else 'trip'}_{digest}",
                           "source": "csv" if source == "csv" else "trip", "at": _iso(at)})
            for name in ("predictedUsePct", "riders", "cargoKg"):
                value = _float(raw.get(name), 0, 1000)
                if value is not None:
                    sample[name] = value
            accepted.append(sample)
        added = self.repository.save_trip_samples(uid, vehicle_id, accepted) if accepted else 0
        self.repository.append_audit(uid, "trip_samples_added", vehicle_id=vehicle_id,
                                     source=source, added=added, rejected=rejected)
        return {"accepted": len(accepted), "added": added, "duplicates": len(accepted) - added,
                "rejected": rejected,
                "training": self.learning_status(uid, vehicle_id, vehicle=vehicle)}

    # -- status & training ---------------------------------------------------
    def learning_status(self, uid: str, vehicle_id: str, *, vehicle: dict | None = None) -> dict:
        vehicle = vehicle if vehicle is not None else self._owned_vehicle(uid, vehicle_id)
        profile = self.repository.get_personal_profile(uid, vehicle_id)
        learned = charge_model.LearnedProfile.from_dict(profile.learned if profile else None)
        charge = charge_model.training_status(learned)
        charge.update({"whPerPct": learned.wh_per_pct, "powerW": learned.power_w,
                       "report": (profile.training_reports or {}).get("charge") if profile else None,
                       # What the model learned from and what waits (Task 127).
                       "samples": [_charge_row(item) for item in learned.samples],
                       "pendingSamples": [_charge_row(item) for item in learned.pending]})
        rides = self.repository.trip_samples(uid, vehicle_id)
        trained_ids = set(profile.trip_trained_ids) if profile else set()
        trip = trip_model.trip_training_status(rides, trained_ids)
        params = self.current_trip_params(uid, vehicle_id, vehicle, profile)
        trip.update({"model": params.to_dict() if params else None,
                     "kmPerPct": round(params.km_per_pct, 3) if params else None,
                     "report": (profile.training_reports or {}).get("trip") if profile else None,
                     "sources": _count_sources(rides)})
        return {"vehicleId": vehicle_id,
                "consentEnabled": profile.consent_enabled if profile else True,
                "charge": charge, "trip": trip}

    def battery_health(self, uid: str, vehicle_id: str) -> dict:
        """% pin chai (QA 135, Pro): from the confirmed charges, plus the
        owner's guided test (charge from ≤ 30 % until the battery is full)."""
        vehicle = self._owned_vehicle(uid, vehicle_id)
        self.require_feature(uid, "battery_health")
        profile = self.repository.get_personal_profile(uid, vehicle_id)
        learned = charge_model.LearnedProfile.from_dict(profile.learned if profile else None)
        nominal = _float(vehicle.get("nominalCapacityWh"), 1, 1e6)
        result = charge_model.battery_health([*learned.samples, *learned.pending], nominal)
        result.update({
            "vehicleId": vehicle_id,
            "vehicleSohPct": _float(vehicle.get("stateOfHealth"), 1, 120),
            "consentEnabled": profile.consent_enabled if profile else True,
            "testMaxStartPct": charge_model.HEALTH_TEST_MAX_START_PCT,
        })
        return result

    def train_model(self, uid: str, vehicle_id: str, model: str, mode: str = "finetune") -> dict:
        if model not in ("charge", "trip"):
            raise self._learning_error("invalidModel", "Mô hình không hợp lệ.")
        mode = "retrain" if mode == "retrain" else "finetune"
        vehicle = self._owned_vehicle(uid, vehicle_id)
        self.require_feature(uid, "learning_train")
        profile = self.personal_profile(uid, vehicle_id)
        if not profile.consent_enabled:
            raise self._learning_error("consentDisabled", "AI cá nhân đang tắt. Bật lại để huấn luyện.", 409)
        now = self.clock()
        if model == "charge":
            learned = charge_model.LearnedProfile.from_dict(profile.learned)
            if not learned.pending and mode == "finetune":
                raise self._learning_error("nothingNew", "Chưa có dữ liệu sạc mới để huấn luyện.", 409)
            updated, report = charge_model.train(learned, base_wh_per_pct=self._charge_base(vehicle),
                                                 now=now, mode=mode)
            profile.learned = updated.to_dict()
            profile.valid_sessions = len(updated.samples)
            profile.median_power_w = updated.power_w
            profile.validation_mape = updated.soc_mae
            profile.active = updated.wh_per_pct is not None
            if report["decision"] == "promoted":
                profile.profile_version += 1
                profile.adapter_version = f"personal-v{profile.profile_version}"
        else:
            rides = self.repository.trip_samples(uid, vehicle_id)
            trained_ids = set(profile.trip_trained_ids)
            if mode == "finetune" and not any(str(item.get("id")) not in trained_ids for item in rides):
                raise self._learning_error("nothingNew", "Chưa có chuyến đi mới để huấn luyện.", 409)
            current = self.current_trip_params(uid, vehicle_id, vehicle, profile)
            if current is None:
                current = trip_model.params_from_km_per_pct(1.2, "catalog")
            params, report = trip_model.train_trip_model(rides, current, mode=mode,
                                                         trained_ids=trained_ids)
            if report["decision"] == "promoted":
                profile.trip_model = params.to_dict()
            profile.trip_trained_ids = [str(item.get("id")) for item in rides][-2000:]
        report = {**report, "model": model, "at": _iso(now)}
        profile.training_reports = {**(profile.training_reports or {}), model: report}
        profile.last_trained_at = now
        profile.updated_at = now
        self.repository.save_personal_profile(profile)
        self.repository.append_audit(uid, "personal_model_trained", vehicle_id=vehicle_id,
                                     model=model, mode=mode, decision=report["decision"])
        return {"report": report, "status": self.learning_status(uid, vehicle_id, vehicle=vehicle)}


def _charge_row(item: dict) -> dict:
    return {"at": str(item.get("at") or "")[:10], "startPct": item.get("startPct"),
            "actualEndPct": item.get("actualEndPct"), "energyWh": item.get("energyWh"),
            "labelSource": item.get("labelSource") or "user", "censored": bool(item.get("censored"))}


def _trip_id_time(key: str) -> datetime | None:
    """The owner's logger ids start with the ride time, e.g.
    ``2026-04-10T033921054363Z_1351_bebf0734``."""
    match = _TRIP_ID_TIME.match(key or "")
    if not match:
        return None
    return _parse(f"{match.group(1)}T{match.group(2)}:{match.group(3)}:{match.group(4)}+00:00")


def _count_sources(rides: list[dict]) -> dict:
    counts: dict[str, int] = {}
    for item in rides:
        key = str(item.get("source") or "trip")
        counts[key] = counts.get(key, 0) + 1
    return counts
