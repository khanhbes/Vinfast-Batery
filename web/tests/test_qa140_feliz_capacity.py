"""QA 140: the Feliz 2025 fix changes only values still at the old spec."""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))

import qa140_feliz_capacity as fix  # noqa: E402


def test_catalog_fields_at_the_old_spec_move_to_2400_wh_and_50_ah():
    data = {
        "battery": {"usableCapacityWh": 2600, "calculationCapacityWh": 2600.0, "capacityAh": 54, "voltageV": 48},
        "appDefaults": {"calculationCapacityWh": 2600, "maxSafeChargePowerW": 600},
    }
    assert fix.catalog_changes(data) == {
        "battery.usableCapacityWh": 2400.0,
        "battery.calculationCapacityWh": 2400.0,
        "battery.capacityAh": 50.0,
        "appDefaults.calculationCapacityWh": 2400.0,
    }


def test_a_capacity_the_owner_typed_is_left_alone():
    assert fix.vehicle_changes({"nominalCapacityWh": 2350, "batteryCapacityWh": 2350}) == {}
    assert fix.vehicle_changes({"nominalCapacityWh": "abc"}) == {}


def test_a_vehicle_on_the_catalog_default_gets_every_copy_fixed():
    data = {"nominalCapacityWh": 2600, "batteryCapacity": 2600.0, "nominalCapacityAh": 54,
            "catalogSnapshot": {"calculationCapacityWh": 2600, "displayName": "Feliz 2025"}}
    assert fix.vehicle_changes(data) == {
        "nominalCapacityWh": 2400.0,
        "batteryCapacity": 2400.0,
        "nominalCapacityAh": 50.0,
        "catalogSnapshot.calculationCapacityWh": 2400.0,
    }


def test_relinking_or_publishing_writes_every_capacity_field():
    """QA 140: the server reads nominalCapacityWh first; a relink used to
    write only batteryCapacity, so the old 2600 Wh stayed in use."""
    import vehicle_catalog

    fields = vehicle_catalog._capacity_fields(
        {"calculationCapacityWh": 2400}, {"capacityAh": 50, "chemistry": "LFP"})
    assert fields == {"nominalCapacityWh": 2400.0, "batteryCapacityWh": 2400.0, "nominalCapacityAh": 50.0}
    assert vehicle_catalog._capacity_fields({}, {}) == {}
