"""Task 126: trip battery-use model shared with the app."""
from __future__ import annotations

import json
from pathlib import Path

import pytest

from assistant.trip_model import (
    TripConditions,
    TripModelParams,
    catalog_km_per_pct,
    learned_km_per_pct,
    plan_trip,
)

VECTORS = json.loads((Path(__file__).parent / "fixtures" / "trip_model_vectors.json")
                     .read_text(encoding="utf-8"))


@pytest.mark.parametrize("vector", VECTORS["plans"], ids=lambda item: item["name"])
def test_trip_plan_vectors(vector):
    data = dict(vector["input"])
    conditions = TripConditions(**data.pop("conditions"))
    if "model" in data:
        data["model"] = TripModelParams.from_dict(data["model"])
    plan = plan_trip(conditions=conditions, **data).to_dict()
    assert plan == vector["expect"]


def test_learning_from_odo_pairs():
    learning = VECTORS["learning"]
    km, pairs = learned_km_per_pct(learning["sessions"], learning["catalog"])
    assert pairs == learning["pairs"]
    assert km == pytest.approx(learning["kmPerPct"], abs=1e-4)


def test_learning_needs_two_pairs_and_ignores_typos():
    one_pair = [
        {"endedAt": "2026-09-01", "startSoc": 20, "actualEndSoc": 90, "odoKm": 1000},
        {"endedAt": "2026-09-04", "startSoc": 30, "actualEndSoc": 85, "odoKm": 1054},
    ]
    assert learned_km_per_pct(one_pair, 0.9) == (None, 1)
    typo = one_pair + [{"endedAt": "2026-09-07", "startSoc": 25, "actualEndSoc": 80, "odoKm": 9999}]
    assert learned_km_per_pct(typo, 0.9)[1] == 1


def test_catalog_value_scales_with_soh():
    assert catalog_km_per_pct(1.0, 90) == pytest.approx(0.9)
    assert catalog_km_per_pct(None, 90) is None


def test_insufficient_trip_always_offers_a_way_forward():
    plan = plan_trip(distance_km=45, current_soc=30, km_per_pct=0.9, km_per_pct_source="catalog")
    assert plan.verdict == "insufficient"
    kinds = {item["kind"] for item in plan.suggestions}
    assert "charge_first" in kinds
