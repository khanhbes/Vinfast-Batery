import os
import time
from typing import Any

import httpx

from models import ChargerCommandResponse, ChargerStatus


class ShellyUnavailableError(RuntimeError):
    pass


class ShellyClient:
    def __init__(self, ip: str | None = None, timeout_seconds: float = 3.0):
        self.ip = (ip or os.getenv("SHELLY_IP", "192.168.1.3")).strip()
        self.timeout_seconds = timeout_seconds

    def _rpc(self, method: str, params: dict[str, Any]) -> dict[str, Any]:
        try:
            response = httpx.get(
                f"http://{self.ip}/rpc/{method}",
                params=params,
                timeout=self.timeout_seconds,
            )
            response.raise_for_status()
            data = response.json()
        except (httpx.HTTPError, ValueError) as exc:
            raise ShellyUnavailableError("Shelly is unavailable") from exc
        if not isinstance(data, dict):
            raise ShellyUnavailableError("Shelly returned an invalid response")
        return data

    def _rpc_with_retry(
        self,
        method: str,
        params: dict[str, Any],
        attempts: int = 3,
        delays: list[float] | None = None,
    ) -> dict[str, Any]:
        if delays is None:
            delays = [1.0, 2.0, 4.0]
        last_exc: Exception | None = None
        for i in range(attempts):
            try:
                return self._rpc(method, params)
            except ShellyUnavailableError as exc:
                last_exc = exc
                if i < attempts - 1:
                    time.sleep(delays[min(i, len(delays) - 1)])
        raise ShellyUnavailableError(f"RPC {method} failed after {attempts} attempts") from last_exc

    def get_status(self) -> ChargerStatus:
        raw = self._rpc("Switch.GetStatus", {"id": 0})
        temperature = raw.get("temperature")
        temperature_c = (
            temperature.get("tC") if isinstance(temperature, dict) else None
        )
        energy = raw.get("aenergy")
        energy_wh = energy.get("total", 0) if isinstance(energy, dict) else 0
        return ChargerStatus(
            online=True,
            relay=bool(raw.get("output", False)),
            power_w=float(raw.get("apower") or 0),
            voltage_v=float(raw.get("voltage") or 0),
            current_a=float(raw.get("current") or 0),
            frequency_hz=float(raw.get("freq") or 0),
            temperature_c=float(temperature_c) if temperature_c is not None else None,
            energy_wh=float(energy_wh or 0),
        )

    def set_relay(
        self, on: bool, auto_off_delay_seconds: int | None = None
    ) -> ChargerCommandResponse:
        previous_state = self.get_status().relay
        params: dict[str, Any] = {"id": 0, "on": str(on).lower()}
        if on and auto_off_delay_seconds is not None and auto_off_delay_seconds > 0:
            params["auto_off"] = True
            params["auto_off_delay"] = auto_off_delay_seconds

        self._rpc_with_retry("Switch.Set", params)
        # Switch.Set returns the previous state on some firmware. Read back the
        # actual state so the gateway never claims a command succeeded blindly.
        relay = self.get_status().relay
        return ChargerCommandResponse(
            success=relay == on,
            relay=relay,
            previous_state=previous_state,
        )

