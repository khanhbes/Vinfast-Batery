"""QA 142: the dashboard scan also reads the battery temperature (0–100 °C)
and the ODO up to six digits."""
from __future__ import annotations

import pytest

from shelly.service import SmartChargeError
from tests.test_task127_learning import _service


def test_a_reading_keeps_the_battery_temperature():
    service, repo, _provider, _clock = _service()
    written = {}
    repo.update_vehicle_fields = lambda uid, vehicle_id, fields: written.update(fields)
    result = service.add_battery_reading(
        "owner", "car", {"soc": 68, "odoKm": 4818, "batteryTempC": 31, "source": "photo"})
    assert result["reading"]["batteryTempC"] == 31
    assert written["batteryTempC"] == 31 and written["batteryTempAt"]


def test_temperature_and_six_digit_odo_are_range_checked():
    service, _repo, _provider, _clock = _service()
    with pytest.raises(SmartChargeError) as caught:
        service.add_battery_reading("owner", "car", {"soc": 50, "batteryTempC": 120})
    assert caught.value.code == "invalidTemp"
    saved = service.add_battery_reading("owner", "car", {"odoKm": 999999})
    assert saved["reading"]["odoKm"] == 999999
    with pytest.raises(SmartChargeError) as caught:
        service.add_battery_reading("owner", "car", {"odoKm": 1000000})
    assert caught.value.code == "invalidOdo"
