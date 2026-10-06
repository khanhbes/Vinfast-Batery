"""Deadline regression tests; no cloud, network or existing process changes."""
import importlib.util
from pathlib import Path
import subprocess

import pytest


spec = importlib.util.spec_from_file_location(
    "quality_gate_deadline_under_test",
    Path(__file__).resolve().parents[2] / "tools" / "run_quality_gate.py",
)
assert spec is not None and spec.loader is not None
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)


class FakeProcess:
    args = ["qa-only"]

    def __init__(self, completes=False):
        self.completed = False
        self.completes = completes
        self.waits = []

    def poll(self):
        return 0 if self.completed else None

    def wait(self, timeout):
        self.waits.append(timeout)
        if self.completes:
            self.completed = True
            return 0
        raise subprocess.TimeoutExpired(self.args, timeout)


def test_resume_past_deadline_does_not_start_another_long_wait(monkeypatch):
    timestamps = iter([0, 300])
    monkeypatch.setattr(gate.time, "monotonic", lambda: next(timestamps))
    process = FakeProcess()
    with pytest.raises(subprocess.TimeoutExpired) as error:
        gate.wait_with_deadline(process, timeout=120, started=0)
    assert error.value.timeout == 120
    assert process.waits == [1.0]


def test_remaining_fraction_is_not_rounded_up(monkeypatch):
    timestamps = iter([0.75, 1.25])
    monkeypatch.setattr(gate.time, "monotonic", lambda: next(timestamps))
    process = FakeProcess()
    with pytest.raises(subprocess.TimeoutExpired):
        gate.wait_with_deadline(process, timeout=1, started=0)
    assert process.waits == [0.25]


def test_success_before_deadline_is_preserved(monkeypatch):
    monkeypatch.setattr(gate.time, "monotonic", lambda: 1)
    process = FakeProcess(completes=True)
    gate.wait_with_deadline(process, timeout=10, started=0)
    assert process.completed
    assert process.waits == [1.0]


def test_already_exited_does_not_wait(monkeypatch):
    process = FakeProcess()
    process.completed = True
    monkeypatch.setattr(gate.time, "monotonic", lambda: pytest.fail("Unnecessary wait"))
    gate.wait_with_deadline(process, timeout=10, started=0)
    assert process.waits == []
