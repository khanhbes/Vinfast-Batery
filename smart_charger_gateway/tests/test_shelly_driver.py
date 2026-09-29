import pytest

from shelly import ShellyClient, ShellyUnavailableError


def test_on_requires_timer_and_uses_toggle_after(monkeypatch):
    client = ShellyClient(ip="127.0.0.1")
    calls = []
    relay = False

    def rpc(method, params):
        nonlocal relay
        calls.append((method, params.copy()))
        if method == "Switch.Set":
            relay = params["on"]
            return {}
        return {"output": relay}

    monkeypatch.setattr(client, "_rpc", rpc)
    with pytest.raises(ShellyUnavailableError):
        client.set_relay(True)
    assert not any(method == "Switch.Set" for method, _ in calls)

    result = client.set_relay(True, auto_off_delay_seconds=5)
    assert result.success
    on_commands = [params for method, params in calls if method == "Switch.Set"]
    assert on_commands == [{"id": 0, "on": True, "toggle_after": 5}]


def test_ambiguous_on_failure_is_never_retried(monkeypatch):
    client = ShellyClient(ip="127.0.0.1")
    on_count = 0

    def rpc(method, params):
        nonlocal on_count
        if method == "Switch.Set":
            on_count += 1
            raise ShellyUnavailableError("timeout")
        return {"output": False}

    monkeypatch.setattr(client, "_rpc", rpc)
    with pytest.raises(ShellyUnavailableError):
        client.set_relay(True, auto_off_delay_seconds=5)
    assert on_count == 1


def test_missing_relay_output_is_not_off(monkeypatch):
    client = ShellyClient(ip="127.0.0.1")
    monkeypatch.setattr(client, "_rpc", lambda method, params: {"apower": 0})
    with pytest.raises(ShellyUnavailableError):
        client.get_status()
