"""QA 140: changing a vehicle's model or publishing its catalog writes every
capacity field the server reads."""
from __future__ import annotations


def test_relinking_or_publishing_writes_every_capacity_field():
    """QA 140: the server reads nominalCapacityWh first; a relink used to
    write only batteryCapacity, so the old 2600 Wh stayed in use."""
    import vehicle_catalog

    fields = vehicle_catalog._capacity_fields(
        {"calculationCapacityWh": 2400}, {"capacityAh": 50, "chemistry": "LFP"})
    assert fields == {"nominalCapacityWh": 2400.0, "batteryCapacityWh": 2400.0, "nominalCapacityAh": 50.0}
    assert vehicle_catalog._capacity_fields({}, {}) == {}
