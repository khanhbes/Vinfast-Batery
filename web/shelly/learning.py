"""Per-vehicle learning data and owner-triggered training (Task 127).

Data is collected silently:

* charging: every finished charge with a known end % (the owner's reading, or
  the full-battery power tail seen by the server) is queued on the charge
  profile (``charge_model.queue_sample``);
* rides: trips recorded from the trip planner, rides imported from a CSV, and
  odometer segments between two battery/ODO readings with no charge between.

Charge estimates change on "Huấn luyện" (finetune), "Huấn luyện lại" (retrain) or,
unless the owner switched it off, by themselves once enough new charges wait
(QA 148). All keep the current model if the new one is not better. Rides still train
only on the button. Every plan learns its own Wh/%; the layers on top of it and the
buttons come with the plan that can train.
"""

from __future__ import annotations

import hashlib
import math
import re
import sys
import uuid
from datetime import datetime, timedelta, timezone

from . import charge_ai, charge_model
from .habits import charge_habits, is_lead_acid


# QA 142: the cluster shows up to six ODO digits.
MAX_ODO_KM = 999999


class _LazyTripModel:
    """assistant.trip_model is imported on first use: the worker image ships
    only shelly/ and never needs the trip model."""

    def __getattr__(self, name):
        from assistant import trip_model as module
        return getattr(module, name)


trip_model = _LazyTripModel()
_TRIP_ID_TIME = re.compile(r"(\d{4}-\d{2}-\d{2})T(\d{2})(\d{2})(\d{2})")

READING_SOURCES = {"manual", "chat", "photo", "charge_end", "trip_start", "trip_end"}
# QA 166 (owner, 18/11/2026): the scooter shuts off when its gauge reaches 0 %.
# A reading saved as "the scooter just shut off" is a physical 0 %, so a charge
# from it to the charger's full signal measures the capacity with no gauge
# reading at either end. Only offered at a low %.
CUTOFF_MAX_PCT = 5.0
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
        typed = label_source == "user"
        # QA 166 (2): a full % typed after the charger's own full signal
        # confirms it; it must not turn the measured end into a censored one
        # (1/11/2026: 0 -> 100 % stopped by battery_full, then left out).
        if (typed and float(session.actual_end_soc or 0) >= charge_model.GAUGE_RESET_END_PCT
                and (session.full_detected_at is not None or session.stop_reason == "battery_full")):
            label_source = "taper_full"
        end_pct = 100.0 if label_source == "taper_full" else float(session.actual_end_soc or 0)
        base = self._charge_base(vehicle, session)
        learned = charge_model.LearnedProfile.from_dict(profile.learned)
        sample_wh = charge_model.wh_per_pct_sample(session.energy_used_wh, session.start_soc, end_pct)
        taper = (charge_model.learn_taper(session.telemetry_samples, session.start_soc, sample_wh)
                 if sample_wh else None)
        now = self.clock()
        at = (session.stopped_at or now).isoformat()
        wh_in_use = session.model_wh_per_pct or learned.wh_per_pct or base
        carried, next_offset = _gauge_shadow(learned, session, end_pct, at, wh_in_use)
        # Collected for later: nothing reads it yet (QA 147).
        temperature = _recent_battery_temp(vehicle, session)
        # QA 158: how far the gauge was from its last full charge when this
        # charge began. Every real charge counts, timed ones too.
        sessions = _vehicle_sessions(self.repository, uid, session.vehicle_id)
        trust = charge_ai.gauge_trust(learned, sessions, before=session.created_at,
                                      now=now, wh_per_pct=wh_in_use)
        trust_level = session.gauge_trust_level or trust["level"]
        queued, decision = charge_model.queue_sample(learned, {
            "sessionId": session.session_id,
            "energyWh": session.energy_used_wh,
            "startPct": session.start_soc,
            "actualEndPct": end_pct,
            "estimatedEndPct": session.estimated_soc,
            "avgPowerW": session.average_power_w,
            "at": at,
            "taperStartPct": taper[0] if taper else None,
            "taperPowerRatio": taper[1] if taper else None,
            "labelSource": label_source,
            "shadowOffsetPct": carried,
            "shadowWhPerPct": wh_in_use if carried is not None else None,
            "batteryTempC": temperature,
            "trust": trust_level,
            # QA 166: what battery health needs to weigh this charge, measured
            # rather than assumed.
            "startSource": session.start_soc_source,
            "startAgeMin": session.start_soc_age_min,
            "endAfterMin": charge_end_read_after(session, now) if typed else None,
            "tailWh": charge_model.idle_energy_wh(session.telemetry_samples, session.energy_used_wh),
            "plateauW": charge_model.plateau_power_w(session.telemetry_samples),
        }, base_wh_per_pct=base, now=now)
        if decision != "queued":
            return decision
        if next_offset is not None:
            queued.gauge_offset_pct = next_offset
            queued.gauge_offset_at = at
        cross = _cross_entry(session, sessions, at)
        if cross is not None:
            queued.cross_log = [*[item for item in queued.cross_log
                                  if item.get("sessionId") != cross["sessionId"]],
                                cross][-charge_model.MAX_CROSS_LOG:]
        profile.learned = queued.to_dict()
        profile.updated_at = now
        self.repository.save_personal_profile(profile)
        self.repository.append_audit(uid, "charge_label_queued", session_id=session.session_id,
                                     label_source=label_source)
        full = None
        # A vehicle that has learned nothing yet waits for its first training.
        if end_pct >= charge_model.GAUGE_RESET_END_PCT and learned.wh_per_pct:
            full = {"sample": next((item for item in queued.pending
                                    if item.get("sessionId") == session.session_id), None),
                    "exact": label_source == "taper_full" or session.stop_reason == "battery_full",
                    "trust": trust}
        self._auto_train_charge(uid, profile, queued, base, now, full=full)
        return decision

    def _auto_train_charge(self, uid: str, profile, learned, base: float | None, now: datetime,
                           full: dict | None = None) -> None:
        """QA 148: people who never open the training screen still get an estimate
        that follows their vehicle. The label is already saved; a failure here only
        leaves it waiting for the next one."""
        if not profile.auto_train or not profile.consent_enabled:
            return
        # QA 158: a charge that reached full is the moment the gauge is right:
        # recalibrate then, without waiting for more charges.
        if full is None or full.get("sample") is None:
            full = None
            if not charge_model.training_status(learned)["ready"]:
                return
        try:
            entitlements = getattr(self, "entitlements", None)
            # The worker does not know the plan: it leaves the layer as it is.
            layers = entitlements.allows(uid, "learning_train") if entitlements is not None else None
            _, report = self._train_charge(profile, learned, base, now, mode="finetune", layers=layers,
                                           full=full)
            profile.training_reports = {**(profile.training_reports or {}),
                                        "charge": {**report, "model": "charge", "auto": True, "at": _iso(now)}}
            profile.last_trained_at = now
            profile.updated_at = now
            self.repository.save_personal_profile(profile)
            self.repository.append_audit(uid, "personal_model_trained", vehicle_id=profile.vehicle_id,
                                         model="charge", mode="auto", decision=report["decision"])
        except Exception as error:
            print(f"[learning] automatic training failed ({type(error).__name__})",
                  file=sys.stderr, flush=True)

    @staticmethod
    def _train_charge(profile, learned, base: float | None, now: datetime, *, mode: str,
                      layers: bool | None, full: dict | None = None
                      ) -> tuple[charge_model.LearnedProfile, dict]:
        """One training on ``profile``. ``layers``: True selects the layer, False
        returns to the plain Wh/% (the model stays for a later plan), None keeps it."""
        if full is not None:
            trust = full.get("trust") or {}
            updated, report = charge_model.recalibrate(
                learned, base_wh_per_pct=base, now=now, full=full["sample"],
                exact=bool(full.get("exact")),
                sessions_since=int(trust.get("sessionsSinceFull") or 0),
                fulls_since=trust.get("fullsSinceFull"), days_since=trust.get("daysSinceFull"))
        else:
            updated, report = charge_model.train(learned, base_wh_per_pct=base, now=now, mode=mode)
        if layers:
            updated, layer = charge_ai.select_layer(updated, base=base, now=now)
            report = {**report, "layer": layer}
        elif layers is False:
            updated = charge_model.LearnedProfile(**{**updated.__dict__, "layer": "base", "layer_mae": None})
        profile.learned = updated.to_dict()
        profile.valid_sessions = len(updated.samples)
        profile.median_power_w = updated.power_w
        profile.validation_mape = updated.soc_mae
        profile.active = updated.wh_per_pct is not None
        if report["decision"] == "promoted":
            profile.profile_version += 1
            profile.adapter_version = f"personal-v{profile.profile_version}"
        return updated, report

    def set_auto_train(self, uid: str, vehicle_id: str, enabled: bool) -> dict:
        self._owned_vehicle(uid, vehicle_id)
        profile = self.personal_profile(uid, vehicle_id)
        profile.auto_train = bool(enabled)
        profile.updated_at = self.clock()
        self.repository.save_personal_profile(profile)
        self.repository.append_audit(uid, "personal_ai_auto_train_changed", vehicle_id=vehicle_id,
                                     enabled=bool(enabled))
        return {"vehicleId": vehicle_id, "autoTrain": profile.auto_train}

    # -- readings ------------------------------------------------------------
    def add_battery_reading(self, uid: str, vehicle_id: str, body: dict, *,
                            with_status: bool = True) -> dict:
        vehicle = self._owned_vehicle(uid, vehicle_id)
        soc = _float(body.get("soc"), 0, 100) if body.get("soc") not in (None, "") else None
        odo = _float(body.get("odoKm"), 0, MAX_ODO_KM) if body.get("odoKm") not in (None, "") else None
        # QA 142: battery temperature read on the cluster (0–100 °C).
        temp = _float(body.get("batteryTempC"), 0, 100) if body.get("batteryTempC") not in (None, "") else None
        if body.get("soc") not in (None, "") and soc is None:
            raise self._learning_error("invalidSoc", "% pin phải từ 0 đến 100.")
        if body.get("odoKm") not in (None, "") and odo is None:
            raise self._learning_error("invalidOdo", "ODO không hợp lệ.")
        if body.get("batteryTempC") not in (None, "") and temp is None:
            raise self._learning_error("invalidTemp", "Nhiệt độ pin phải từ 0 đến 100 °C.")
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
        current_odo = _float(vehicle.get("currentOdo"), 0, MAX_ODO_KM)
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
        if temp is not None:
            reading["batteryTempC"] = round(temp)
        # QA 166: "the scooter just shut off" marks a physical 0 % (low % only).
        cutoff = body.get("cutoff") is True and soc is not None and soc <= CUTOFF_MAX_PCT
        if cutoff:
            reading["cutoff"] = True
        saved = self.repository.add_battery_reading(uid, vehicle_id, reading)
        fields = {"lastReadingAt": _iso(at)}
        if soc is not None:
            # batteryDataUpdatedAt too (QA 129): without it a charge that
            # ended earlier but was finalized later overwrote this reading.
            fields.update({"currentBattery": int(round(soc)), "lastBatteryPercent": int(round(soc)),
                           "hasBatteryData": True, "batteryDataUpdatedAt": at,
                           "batteryDataSource": f"reading_{source}",
                           "batteryCutoff": cutoff})
        if odo is not None:
            fields.update({"currentOdo": int(round(odo)), "hasOdoData": True})
        if temp is not None:
            fields.update({"batteryTempC": int(round(temp)), "batteryTempAt": at})
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
        consent = profile.consent_enabled if profile else True
        charge["learning"]["state"] = _learning_state(charge["learning"], learned, consent)
        charge["model"] = charge_ai.status(learned, _vehicle_sessions(self.repository, uid, vehicle_id),
                                            now=self.clock())
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
        entitlements = getattr(self, "entitlements", None)
        return {"vehicleId": vehicle_id,
                "consentEnabled": profile.consent_enabled if profile else True,
                "autoTrain": profile.auto_train if profile else True,
                # QA 138 (QA-07): the app nudges "train now" only when the
                # plan can train; the data stays collected either way.
                "trainAllowed": entitlements is None or entitlements.allows(uid, "learning_train"),
                "charge": charge, "trip": trip}

    def battery_health(self, uid: str, vehicle_id: str) -> dict:
        """% pin chai (QA 135): from the confirmed charges, plus the owner's
        guided test (charge from ≤ 30 % until the battery is full). QA 140:
        every plan sees the estimate; the per-charge trend and the guided
        test stay Pro/Ultra (``full``), as the owner chose."""
        vehicle = self._owned_vehicle(uid, vehicle_id)
        entitlements = getattr(self, "entitlements", None)
        full = entitlements is None or entitlements.allows(uid, "battery_health")
        profile = self.repository.get_personal_profile(uid, vehicle_id)
        learned = charge_model.LearnedProfile.from_dict(profile.learned if profile else None)
        nominal = _float(vehicle.get("nominalCapacityWh"), 1, 1e6)
        # QA 166: measured inputs when there are some. The gauge % at which the
        # scooter shut off (0 on the owner's), a charger measured with DC
        # readings, a rating read off the battery's own label.
        calibration = vehicle.get("chargerCalibration")
        # QA 166 (2): the charger's rated output against the wall power this
        # vehicle charges at caps the wall-to-battery factor; the gauge's
        # drift between full charges sets the error of a charge to full.
        result = charge_model.battery_health(
            [*learned.samples, *learned.pending], nominal,
            history=learned.ledger, now=self.clock(), log=learned.health_log,
            cutoff_pct=self._cutoff_pct(uid, vehicle_id),
            factor=calibration if isinstance(calibration, dict) else None,
            nominal_source="label" if vehicle.get("nominalCapacitySource") == "label" else None,
            charger_rated_w=self._charger_rated_w(vehicle),
            wall_power_w=learned.power_w,
            drift_log=learned.drift_log)
        result.update({
            "vehicleId": vehicle_id,
            "vehicleSohPct": _float(vehicle.get("stateOfHealth"), 1, 120),
            "consentEnabled": profile.consent_enabled if profile else True,
            "testMaxStartPct": charge_model.HEALTH_TEST_MAX_START_PCT,
            "full": full,
        })
        if not full:
            result["trend"] = []
            result["test"] = None
            result["baseline"] = None
            result["charges"] = []
            # QA 164: Free sees the main figure; the months are the trend.
            if isinstance(result.get("tracking"), dict):
                result["tracking"] = {**result["tracking"], "monthly": []}
        return result

    def _charger_rated_w(self, vehicle: dict) -> float | None:
        """QA 166 (2): the rated output of the charger this vehicle came with:
        set on the vehicle (``chargerRatedW``), else its catalog's
        ``charging.maxDcPowerW``; ``None`` when neither says."""
        own = _float(vehicle.get("chargerRatedW"), 50, 5000)
        if own is not None:
            return own
        lookup = getattr(self.repository, "catalog_charging", None)
        if lookup is None:
            return None
        try:
            charging = lookup(vehicle) or {}
        except Exception:
            return None
        return _float(charging.get("maxDcPowerW"), 50, 5000)

    def _cutoff_pct(self, uid: str, vehicle_id: str) -> float | None:
        """QA 166: the median % of the latest readings saved as "the scooter
        just shut off"; ``None`` when there is none (or they cannot be read)."""
        try:
            readings = self.repository.battery_readings(uid, vehicle_id, limit=30)
        except Exception:
            return None
        values = [float(item["soc"]) for item in readings
                  if item.get("cutoff") is True and item.get("soc") is not None][:3]
        if not values:
            return None
        values.sort()
        return values[len(values) // 2]

    def charge_assessment(self, uid: str, vehicle_id: str) -> dict:
        """Đánh giá tổng quát (QA 140): charging habits of the last 60 days,
        a score with comments built only from those numbers, charts and a
        suggested schedule. Every plan sees the score and its main comment;
        the charts, all comments and the schedule come with battery health
        (Pro and Ultra), as the owner chose."""
        vehicle = self._owned_vehicle(uid, vehicle_id)
        sessions = [s for s in self.repository.history(uid, limit=200)
                    if s.vehicle_id == vehicle_id]
        profile = self.repository.get_personal_profile(uid, vehicle_id)
        learned = charge_model.LearnedProfile.from_dict(profile.learned if profile else None)
        powers = [float(s.average_power_w) for s in sessions if s.average_power_w]
        power = learned.power_w or (sorted(powers)[len(powers) // 2] if powers else None)
        wh = learned.wh_per_pct or self._charge_base(vehicle)
        result = charge_habits(sessions, now=self.clock(), wh_per_pct=wh, power_w=power,
                               lead_acid=is_lead_acid(vehicle.get("batteryType")
                                                      or vehicle.get("batteryChemistry")))
        entitlements = getattr(self, "entitlements", None)
        full = entitlements is None or entitlements.allows(uid, "battery_health")
        result.update({"vehicleId": vehicle_id, "full": full})
        if not full:
            result["comments"] = result["comments"][:1]
            result["suggestions"] = result["suggestions"][:1]
            result["charts"] = None
            result["schedule"] = None
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
            base = self._charge_base(vehicle)
            _, report = self._train_charge(profile, learned, base, now, mode=mode, layers=True)
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


def _learning_state(progress: dict, learned, consent: bool) -> str:
    """off | learning ("Đang học") | enough (data waits for a training) | learned."""
    if not consent:
        return "off"
    if not progress["done"]:
        return "learning"
    return "learned" if learned.wh_per_pct else "enough"


def _gauge_shadow(learned, session, end_pct: float, at: str,
                  wh_per_pct: float | None) -> tuple[float | None, float | None]:
    """The offset this charge started with and the one it leaves. ``(None, None)``
    when it cannot be scored (no Wh/%, or a charge older than the newest labelled
    one, whose start was not affected by that offset). A second reading of the same
    charge reuses its first starting offset."""
    if not wh_per_pct:
        return None, None
    previous = next((item for item in [*learned.samples, *learned.pending]
                     if item.get("sessionId") == session.session_id), None)
    if previous is not None and previous.get("shadowOffsetPct") is not None:
        carried = float(previous["shadowOffsetPct"])
    else:
        newest, this = _parse(learned.gauge_offset_at), _parse(at)
        if newest is not None and this is not None and this < newest:
            return None, None
        # QA 148: the charge's own record; the profile's was cleared when it ended.
        carried = (session.carried_offset_pct if session.carried_offset_pct is not None
                   else learned.gauge_offset_pct)
    return carried, charge_model.gauge_offset_after(
        session.start_soc, session.energy_used_wh, wh_per_pct, end_pct)


def start_reading_provenance(vehicle: dict | None, start_soc: float,
                             now: datetime) -> tuple[str | None, float | None]:
    """QA 166: where a charge's start % came from and how long before the
    charge it was read, from the vehicle's last saved reading. ``(None, None)``
    when the % sent is not that reading (typed only on the charge screen).
    ``cutoff`` = the scooter had just shut off (a physical 0 %)."""
    vehicle = vehicle or {}
    saved = _float(vehicle.get("currentBattery"), 0, 100)
    if saved is None or abs(saved - float(start_soc)) > 0.5:
        return None, None
    source = str(vehicle.get("batteryDataSource") or "") or None
    read_at = _parse(vehicle.get("batteryDataUpdatedAt"))
    age = None
    if read_at is not None:
        age = round(max(0.0, (now - read_at).total_seconds() / 60), 1)
    if vehicle.get("batteryCutoff") is True and float(start_soc) <= CUTOFF_MAX_PCT:
        source = "cutoff"
    return source, age


def charge_end_read_after(session, now: datetime) -> float | None:
    """QA 166: minutes between the end of a charge and the % typed for it."""
    ended = _parse(getattr(session, "stopped_at", None))
    if ended is None:
        return None
    return round(max(0.0, (now - ended).total_seconds() / 60), 1)


def _recent_battery_temp(vehicle: dict, session) -> float | None:
    """The cluster's battery temperature, when read close to this charge's start."""
    temperature = _float(vehicle.get("batteryTempC"), 0, 100)
    read_at, began = _parse(vehicle.get("batteryTempAt")), _parse(session.created_at)
    if temperature is None or read_at is None or began is None:
        return None
    return temperature if abs((began - read_at).total_seconds()) <= 3 * 3600 else None


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

def _vehicle_sessions(repository, uid: str, vehicle_id: str, limit: int = 60) -> list | None:
    """This vehicle's recent charges; None when the history cannot be read
    (the gauge's trust then counts the labelled charges only)."""
    try:
        return [item for item in repository.history(uid, limit=limit) if item.vehicle_id == vehicle_id]
    except Exception:
        return None


def _cross_entry(session, sessions: list | None, at: str) -> dict | None:
    """QA 158: what the gauge and the odometer said between the previous
    charge's end and this one's start. Collected only: km per 1 % comes from
    the trip model when the comparison is run, so the worker never needs it."""
    start_odo = getattr(session, "start_odo_km", None)
    if start_odo is None or not sessions:
        return None
    began = session.created_at if session.created_at.tzinfo else session.created_at.replace(tzinfo=timezone.utc)
    earlier = []
    for item in sessions:
        if item.session_id == session.session_id or item.stopped_at is None:
            continue
        ended = item.stopped_at if item.stopped_at.tzinfo else item.stopped_at.replace(tzinfo=timezone.utc)
        if ended <= began:
            earlier.append((ended, item))
    if not earlier:
        return None
    ended, previous = max(earlier, key=lambda pair: pair[0])
    if previous.actual_end_soc is None or previous.end_odo_km is None:
        return None
    km = float(start_odo) - float(previous.end_odo_km)
    if not 0 <= km <= 500:
        return None
    return {"at": at, "sessionId": session.session_id, "km": round(km, 1),
            "previousEndPct": float(previous.actual_end_soc), "previousEndAt": ended.isoformat(),
            "gaugeStartPct": float(session.start_soc), "startedAt": began.isoformat()}

