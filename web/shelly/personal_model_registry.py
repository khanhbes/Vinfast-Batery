"""Candidate-first registry for per-vehicle Personal AI adapters.

The registry deliberately stores only lightweight duration calibration, never a
copy of the global Keras artifact.  A candidate is validated against held-out
session samples before replacing the promoted version and every promotion is
rollbackable through the previous version snapshot.
"""
from __future__ import annotations

from copy import deepcopy
from dataclasses import dataclass, asdict
from datetime import datetime, timezone
import math
import statistics
from typing import Any


@dataclass(frozen=True)
class PersonalProfileVersion:
    profile_version: int
    owner_uid: str
    vehicle_id: str
    base_model_version: str
    status: str
    global_time_scale: float
    global_time_bias_minutes: float
    power_scale: float
    median_power_w: float | None
    validation_mape: float | None
    validation_mae_minutes: float | None
    guardrail_pass_rate: float
    valid_sessions: int
    source_session_ids: tuple[str, ...]
    created_at: datetime
    promotion_reason: str | None = None
    rejection_reason: str | None = None

    def to_dict(self) -> dict[str, Any]:
        value = asdict(self)
        value["createdAt"] = self.created_at.isoformat()
        value.pop("created_at", None)
        value["profileVersion"] = value.pop("profile_version")
        value["ownerUid"] = value.pop("owner_uid")
        value["vehicleId"] = value.pop("vehicle_id")
        value["baseModelVersion"] = value.pop("base_model_version")
        value["globalTimeScale"] = value.pop("global_time_scale")
        value["globalTimeBiasMinutes"] = value.pop("global_time_bias_minutes")
        value["powerScale"] = value.pop("power_scale")
        value["medianPowerW"] = value.pop("median_power_w")
        value["validationMape"] = value.pop("validation_mape")
        value["validationMaeMinutes"] = value.pop("validation_mae_minutes")
        value["guardrailPassRate"] = value.pop("guardrail_pass_rate")
        value["validSessions"] = value.pop("valid_sessions")
        value["sourceSessionIds"] = list(value.pop("source_session_ids"))
        value["promotionReason"] = value.pop("promotion_reason")
        value["rejectionReason"] = value.pop("rejection_reason")
        return value


@dataclass(frozen=True)
class CandidateValidationResult:
    mape: float
    mae_minutes: float
    guardrail_pass_rate: float
    sample_count: int
    finite: bool
    physical_bounds_ok: bool

    @property
    def passed_guardrails(self) -> bool:
        return self.finite and self.physical_bounds_ok and self.guardrail_pass_rate >= 0.95


@dataclass(frozen=True)
class PromotionDecision:
    status: str
    reason: str
    candidate: PersonalProfileVersion
    previous_version: PersonalProfileVersion | None = None


class PersonalModelRegistry:
    """Owner/vehicle scoped candidate and promoted-version storage."""

    def __init__(self, firestore_db=None):
        self.db = firestore_db
        self._promoted: dict[tuple[str, str], PersonalProfileVersion] = {}
        self._history: dict[tuple[str, str], list[PersonalProfileVersion]] = {}

    def promoted(self, owner_uid: str, vehicle_id: str) -> PersonalProfileVersion | None:
        key = (owner_uid, vehicle_id)
        if key in self._promoted:
            return self._promoted[key]
        if not self.db:
            return None
        snap = (self.db.collection("users").document(owner_uid)
                .collection("personalProfileVersions").document(vehicle_id)
                .get())
        if not snap.exists:
            return None
        data = snap.to_dict() or {}
        if data.get("ownerUid") != owner_uid or data.get("vehicleId") != vehicle_id:
            return None
        version = _from_dict(data)
        self._promoted[key] = version
        return version

    def build_candidate(self, profile, owner_uid: str, vehicle_id: str,
                        rows: list[dict[str, Any]], base_model_version: str,
                        source_session_id: str | None = None) -> tuple[Any, PersonalProfileVersion]:
        candidate_profile = deepcopy(profile)
        usable = _usable_rows(rows)
        biases = [(_actual_minutes(row) - _predicted_minutes(row)) / _predicted_minutes(row)
                  for row in usable]
        bias = max(-0.35, min(0.50, statistics.median(biases))) if biases else 0.0
        candidate_profile.global_time_scale = 1.0 + bias
        candidate_profile.eta_bias_ratio = bias
        candidate_profile.profile_version = max(1, profile.profile_version + 1)
        candidate_profile.adapter_version = f"candidate-v{candidate_profile.profile_version}"
        candidate_profile.active = False
        validation = validate_candidate(candidate_profile, usable)
        version = PersonalProfileVersion(
            profile_version=candidate_profile.profile_version,
            owner_uid=owner_uid,
            vehicle_id=vehicle_id,
            base_model_version=base_model_version,
            status="candidate",
            global_time_scale=candidate_profile.global_time_scale,
            global_time_bias_minutes=candidate_profile.global_time_bias_minutes,
            power_scale=candidate_profile.power_scale,
            median_power_w=candidate_profile.median_power_w,
            validation_mape=validation.mape,
            validation_mae_minutes=validation.mae_minutes,
            guardrail_pass_rate=validation.guardrail_pass_rate,
            valid_sessions=candidate_profile.valid_sessions,
            source_session_ids=tuple(str(row.get("sessionId")) for row in usable if row.get("sessionId")) + ((source_session_id,) if source_session_id else ()),
            created_at=datetime.now(timezone.utc),
        )
        return candidate_profile, version

    def promote_or_reject(self, candidate_profile, candidate: PersonalProfileVersion,
                          validation: CandidateValidationResult | None = None) -> PromotionDecision:
        key = (candidate.owner_uid, candidate.vehicle_id)
        previous = self._promoted.get(key) or self.promoted(*key)
        validation = validation or CandidateValidationResult(
            mape=candidate.validation_mape or math.inf,
            mae_minutes=candidate.validation_mae_minutes or math.inf,
            guardrail_pass_rate=candidate.guardrail_pass_rate,
            sample_count=len(candidate.source_session_ids), finite=True,
            physical_bounds_ok=True,
        )
        if not validation.passed_guardrails:
            rejected = _replace(candidate, status="rejected", rejection_reason="guardrail_failed")
            self._record(rejected)
            return PromotionDecision("rejected", "guardrail_failed", rejected, previous)
        if previous and previous.validation_mape is not None and (
            candidate.validation_mape is None or candidate.validation_mape + 0.25 >= previous.validation_mape
        ):
            rejected = _replace(candidate, status="rejected", rejection_reason="candidate_did_not_improve")
            self._record(rejected)
            return PromotionDecision("rejected", "candidate_did_not_improve", rejected, previous)
        if previous:
            # Keep the prior promoted pointer as an immutable history record so
            # rollback remains possible after a worker/process restart.
            self._record(_replace(previous, status="superseded", promotion_reason="superseded_by_candidate"))
        promoted = _replace(candidate, status="promoted", promotion_reason="validated_improvement" if previous else "initial_candidate")
        self._promoted[key] = promoted
        self._record(promoted)
        if self.db:
            self.db.collection("users").document(candidate.owner_uid).collection("personalProfileVersions").document(candidate.vehicle_id).set(promoted.to_dict(), merge=True)
        return PromotionDecision("promoted", promoted.promotion_reason or "promoted", promoted, previous)

    def rollback(self, owner_uid: str, vehicle_id: str) -> PersonalProfileVersion | None:
        key = (owner_uid, vehicle_id)
        if key not in self._history and self.db:
            # A new worker must hydrate the immutable version history before
            # selecting the previous promoted pointer. Without this read,
            # rollback would silently become a no-op after process restart.
            try:
                snapshots = (self.db.collection("users").document(owner_uid)
                             .collection("personalProfileVersionHistory")
                             .stream())
                loaded: list[PersonalProfileVersion] = []
                for snapshot in snapshots:
                    data = snapshot.to_dict() or {}
                    if data.get("ownerUid") != owner_uid or data.get("vehicleId") != vehicle_id:
                        continue
                    try:
                        loaded.append(_from_dict(data))
                    except (TypeError, ValueError):
                        continue
                self._history[key] = sorted(loaded, key=lambda item: item.created_at)
            except Exception:
                self._history[key] = []
        versions = [item for item in self._history.get(key, []) if item.status in ("promoted", "superseded")]
        if len(versions) < 2:
            return self._promoted.get(key)
        previous = versions[-2]
        self._promoted[key] = _replace(previous, status="promoted", promotion_reason="rollback")
        return self._promoted[key]

    def _record(self, version: PersonalProfileVersion) -> None:
        self._history.setdefault((version.owner_uid, version.vehicle_id), []).append(version)
        if self.db:
            self.db.collection("users").document(version.owner_uid).collection("personalProfileVersionHistory").document(f"v{version.profile_version}-{version.status}").set(version.to_dict(), merge=True)


def validate_candidate(profile, rows: list[dict[str, Any]]) -> CandidateValidationResult:
    if not rows:
        return CandidateValidationResult(math.inf, math.inf, 0.0, 0, False, False)
    errors: list[float] = []
    abs_minutes: list[float] = []
    physical_ok = True
    for row in rows:
        predicted = _predicted_minutes(row) * profile.global_time_scale
        actual = _actual_minutes(row)
        if not math.isfinite(predicted) or predicted <= 0 or predicted > 600:
            physical_ok = False
        errors.append(abs(actual - predicted) / max(actual, 1e-6) * 100)
        abs_minutes.append(abs(actual - predicted))
    return CandidateValidationResult(
        mape=statistics.mean(errors), mae_minutes=statistics.mean(abs_minutes),
        guardrail_pass_rate=1.0 if physical_ok else 0.0,
        sample_count=len(rows), finite=all(math.isfinite(value) for value in errors),
        physical_bounds_ok=physical_ok,
    )


def _usable_rows(rows):
    return [row for row in rows if _predicted_minutes(row) > 0 and _actual_minutes(row) > 0]


def _predicted_minutes(row):
    return float(row.get("predictedMinutes") or 0)


def _actual_minutes(row):
    return float(row.get("durationSeconds") or 0) / 60


def _replace(version: PersonalProfileVersion, **changes):
    values = {field: getattr(version, field) for field in version.__dataclass_fields__}
    values.update(changes)
    return PersonalProfileVersion(**values)


def _from_dict(data):
    return PersonalProfileVersion(
        profile_version=int(data.get("profileVersion") or 0),
        owner_uid=str(data.get("ownerUid") or ""), vehicle_id=str(data.get("vehicleId") or ""),
        base_model_version=str(data.get("baseModelVersion") or "unknown"), status=str(data.get("status") or "promoted"),
        global_time_scale=float(data.get("globalTimeScale") or 1), global_time_bias_minutes=float(data.get("globalTimeBiasMinutes") or 0),
        power_scale=float(data.get("powerScale") or 1), median_power_w=data.get("medianPowerW"),
        validation_mape=data.get("validationMape"), validation_mae_minutes=data.get("validationMaeMinutes"),
        guardrail_pass_rate=float(data.get("guardrailPassRate") or 0), valid_sessions=int(data.get("validSessions") or 0),
        source_session_ids=tuple(data.get("sourceSessionIds") or ()),
        created_at=_date(data.get("createdAt")), promotion_reason=data.get("promotionReason"), rejection_reason=data.get("rejectionReason"),
    )


def _date(value):
    if isinstance(value, datetime):
        return value
    if isinstance(value, str):
        try:
            return datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            pass
    return datetime.now(timezone.utc)
