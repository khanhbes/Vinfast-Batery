"""Bounded, transaction-backed Cloud admission. Never retries the operation.

All upgraded API/worker instances must use this protocol together. It cannot
fence an old binary or an HTTP request already dispatched outside this gate.
"""
from copy import deepcopy
from datetime import datetime, timedelta, timezone
from email.utils import parsedate_to_datetime
import math
import re
import time
import uuid


class CloudAdmissionError(RuntimeError):
    pass


def retry_after_seconds(raw, now=None):
    now = now or datetime.now(timezone.utc)
    try:
        seconds = float(raw)
    except (TypeError, ValueError):
        try:
            date = parsedate_to_datetime(raw)
            if date.tzinfo is None:
                raise ValueError()
            seconds = (date - now).total_seconds()
        except (TypeError, ValueError, OverflowError):
            seconds = 1.1
    return max(1.1, seconds) if math.isfinite(seconds) else 1.1


def normalized_state(data, now):
    if data is not None and not isinstance(data, dict):
        raise CloudAdmissionError("cloudLimiterMalformed")
    value = deepcopy(data or {})
    version = value.get("dispatchVersion")
    if version is not None and (type(version) is not int or version != 2):
        raise CloudAdmissionError("cloudLimiterMalformed")
    for field in ("nextAt", "leaseUntil", "cooldownUntil"):
        date = value.get(field)
        if date is not None and (not isinstance(date, datetime) or date.tzinfo is None):
            raise CloudAdmissionError("cloudLimiterMalformed")
    waiters = value.get("offWaiters", {})
    lease_id = value.get("leaseId")
    if bool(lease_id) != bool(value.get("leaseUntil")) or (lease_id is not None and
            (not isinstance(lease_id, str) or not re.fullmatch(r"[a-zA-Z0-9_-]{1,64}", lease_id))):
        raise CloudAdmissionError("cloudLimiterMalformed")
    if not isinstance(waiters, dict) or len(waiters) > 16:
        raise CloudAdmissionError("cloudLimiterMalformed")
    for request, until in waiters.items():
        if (not isinstance(request, str) or not re.fullmatch(r"[a-zA-Z0-9_-]{1,64}", request)
                or not isinstance(until, datetime) or until.tzinfo is None):
            raise CloudAdmissionError("cloudLimiterMalformed")
    value["offWaiters"] = {request: until for request, until in waiters.items() if until > now}
    value["dispatchVersion"] = 2
    return value


class CloudDispatchGate:
    def __init__(self, change, *, sleeper=time.sleep, clock=time.monotonic,
                 wall_clock=lambda: datetime.now(timezone.utc)):
        self.change, self.sleep, self.clock, self.now = change, sleeper, clock, wall_clock

    def run(self, operation, *, priority_off=False, guard=None, admission_budget=None):
        request = uuid.uuid4().hex
        budget = 8.0 if priority_off else 4.0
        # Admission waiting only; the operation itself still runs exactly once.
        if admission_budget is not None:
            budget = max(budget, min(15.0, float(admission_budget)))
        deadline = self.clock() + budget
        acquired = False

        def acquire(data, now):
            state = normalized_state(data, now)
            if priority_off:
                if request not in state["offWaiters"] and len(state["offWaiters"]) >= 16:
                    raise CloudAdmissionError("cloudQueueBusy")
                state["offWaiters"][request] = now + timedelta(seconds=10)
            active = state.get("leaseUntil") and state["leaseUntil"] > now
            wait_until = max(state.get("nextAt") or now, state.get("cooldownUntil") or now)
            if active or wait_until > now or (state["offWaiters"] and not priority_off):
                # Do not allocate a future slot. OFF can take the next free slot.
                return state, False
            state.update(leaseId=request, leaseUntil=now + timedelta(seconds=12))
            state["offWaiters"].pop(request, None)
            return state, True

        def release(data, now):
            state = normalized_state(data, now)
            state["offWaiters"].pop(request, None)
            if state.get("leaseId") == request:
                state.pop("leaseId", None)
                state.pop("leaseUntil", None)
                # Completion-based gap is conservative versus start-based spacing.
                state["nextAt"] = max(state.get("nextAt") or now, now + timedelta(seconds=1.1))
            return state, None

        def assert_live(data, now):
            state = normalized_state(data, now)
            if state.get("leaseId") != request or not state.get("leaseUntil") or state["leaseUntil"] <= now:
                raise CloudAdmissionError("cloudDispatchLeaseLost")
            return state, None

        try:
            while self.clock() < deadline:
                if guard:
                    guard()
                acquired = self.change(acquire)
                if acquired:
                    if guard:
                        guard()
                    # DB/authorization checks cannot silently consume the wait budget.
                    if self.clock() >= deadline:
                        raise CloudAdmissionError("cloudQueueBusy")
                    self.change(assert_live)
                    if guard:
                        guard()
                    if self.clock() >= deadline:
                        raise CloudAdmissionError("cloudQueueBusy")
                    return operation()  # exactly once, including timeout/429/5xx
                self.sleep(min(0.25, max(0, deadline - self.clock())))
            raise CloudAdmissionError("cloudQueueBusy")
        finally:
            # Cleanup never rewrites another holder's lease. On datastore failure
            # the short TTL remains; do not retry an ambiguous hardware operation.
            import sys
            already_failed = sys.exc_info()[0] is not None
            try:
                self.change(release)
            except Exception:
                if not already_failed:
                    raise CloudAdmissionError("cloudLimiterUnavailable") from None


def set_cooldown(data, now, seconds):
    state = normalized_state(data, now)
    try:
        until = now + timedelta(seconds=seconds)
    except OverflowError:
        until = datetime.max.replace(tzinfo=timezone.utc)
    state["cooldownUntil"] = max(state.get("cooldownUntil") or now, until)
    return state, None
