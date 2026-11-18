"""QA 166 (2): the Feliz 2025 catalog keeps only what VinFast publishes; the
script changes only the old unsourced figures and is a dry run by default."""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))

import pytest  # noqa: E402

# An ops script, not in the API image the Linux gate tests.
specs = pytest.importorskip("qa166_feliz_specs")

DELETE = object()


class _Snap:
    def __init__(self, db, path):
        self._db, self.path = db, path
        self.id = path.rsplit("/", 1)[-1]
        self.exists = path in db.docs
        self.reference = _Ref(db, path)

    def to_dict(self):
        return dict(self._db.docs.get(self.path) or {})


class _Ref:
    def __init__(self, db, path):
        self._db, self.path = db, path

    def get(self):
        return _Snap(self._db, self.path)

    def collection(self, name):
        return _Col(self._db, f"{self.path}/{name}")


class _Col:
    def __init__(self, db, path):
        self._db, self.path = db, path

    def document(self, doc_id):
        return _Ref(self._db, f"{self.path}/{doc_id}")

    def where(self, field, op, value):
        assert op == "=="
        parent = self

        class _Query:
            def stream(self):
                prefix = parent.path + "/"
                for path, data in list(parent._db.docs.items()):
                    if path.startswith(prefix) and "/" not in path[len(prefix):] and data.get(field) == value:
                        yield _Snap(parent._db, path)
        return _Query()


class _Batch:
    def __init__(self, db):
        self._db, self.ops = db, []

    def set(self, ref, values):
        self.ops.append(("set", ref.path, values))

    def update(self, ref, values):
        self.ops.append(("update", ref.path, values))

    def commit(self):
        for kind, path, values in self.ops:
            if kind == "set":
                self._db.docs[path] = dict(values)
                continue
            doc = self._db.docs.setdefault(path, {})
            for key, value in values.items():
                parts = key.split(".")
                target = doc
                for part in parts[:-1]:
                    target = target.setdefault(part, {})
                if value is DELETE:
                    target.pop(parts[-1], None)
                else:
                    target[parts[-1]] = value
        self._db.commits += 1


class _DB:
    def __init__(self, docs):
        self.docs, self.commits = docs, 0

    def collection(self, name):
        return _Col(self, name)

    def batch(self):
        return _Batch(self)


def _catalog():
    return {
        "revision": 4,
        "battery": {"chemistry": "LFP", "calculationCapacityWh": 2400, "voltageV": 48, "capacityAh": 50},
        "charging": {},
        "appDefaults": {"calculationCapacityWh": 2400, "maxSafeChargePowerW": 600,
                        "defaultEfficiencyKmPerPercent": 1.34},
    }


def test_only_what_vinfast_publishes_stays_in_the_catalog():
    assert specs.catalog_changes(_catalog()) == {
        "charging.maxDcPowerW": 400.0,
        "charging.chargeTimeMinutes": 390.0,
        "appDefaults.maxSafeChargePowerW": 450.0,
        "battery.voltageV": None,
        "battery.capacityAh": None,
    }
    # A figure an admin set (a label read, a fast charger) is left alone.
    edited = _catalog()
    edited["battery"].update(voltageV=60.8, capacityAh=40)
    edited["charging"] = {"maxDcPowerW": 1000, "chargeTimeMinutes": 120}
    edited["appDefaults"]["maxSafeChargePowerW"] = 1100
    assert specs.catalog_changes(edited) == {}


def test_the_legacy_projection_says_not_published_with_zero():
    assert specs.legacy_changes({"nominalVoltageV": 48, "nominalCapacityAh": 50, "maxChargePowerW": 600}) == {
        "nominalVoltageV": 0.0, "nominalCapacityAh": 0.0, "maxChargePowerW": 450.0,
        "chargerOutputW": 400.0, "chargeTimeMinutes": 390.0,
    }
    assert specs.legacy_changes({"nominalVoltageV": 0, "nominalCapacityAh": 0, "maxChargePowerW": 450,
                                 "chargerOutputW": 400, "chargeTimeMinutes": 390}) == {}


def test_the_owners_feliz_is_known_by_its_name_and_capacity():
    owner = {"model": "VinFast Feliz 2025", "nominalCapacityWh": 2400}
    assert specs.named_feliz_2025(owner)
    assert specs.named_feliz_2025({"catalogId": "feliz_2025"})
    # A Feliz S holds 3500 Wh: not this model.
    assert not specs.named_feliz_2025({"model": "VinFast Feliz S", "nominalCapacityWh": 3500})
    assert not specs.named_feliz_2025({"model": "VinFast Evo Grand", "nominalCapacityWh": 2400})
    assert specs.vehicle_changes({}) == {"chargerRatedW": 400.0}
    assert specs.vehicle_changes({"chargerRatedW": 1000}) == {}


def test_a_dry_run_writes_nothing_and_apply_writes_once():
    docs = {
        "VehicleCatalog/feliz_2025": _catalog(),
        "VinFastModelSpecs/feliz_2025": {"nominalVoltageV": 48, "nominalCapacityAh": 50, "maxChargePowerW": 600},
        "Vehicles/linked": {"catalogId": "feliz_2025", "nominalCapacityWh": 2400},
        "Vehicles/owner": {"model": "VinFast Feliz 2025", "nominalCapacityWh": 2400, "ownerUid": "u"},
        "Vehicles/other": {"model": "VinFast Evo200", "nominalCapacityWh": 3500},
    }
    db = _DB({path: dict(value) for path, value in docs.items()})
    report = specs.run(db, "owner", apply=False, delete_field=DELETE)
    assert report["mode"] == "dry-run" and db.commits == 0 and db.docs == docs
    assert report["vehicles"] == {"linked": {"chargerRatedW": 400.0}}
    assert report["named"]["feliz2025"] is True and report["named"]["changes"] == {"chargerRatedW": 400.0}
    assert "ownerUid" not in str(report) and "VinFast Feliz" not in str(report)

    applied = specs.run(db, "owner", apply=True, delete_field=DELETE)
    assert db.commits == 1 and applied["writes"] == 5
    catalog = db.docs["VehicleCatalog/feliz_2025"]
    assert "voltageV" not in catalog["battery"] and "capacityAh" not in catalog["battery"]
    assert catalog["charging"] == {"maxDcPowerW": 400.0, "chargeTimeMinutes": 390.0}
    assert catalog["appDefaults"]["maxSafeChargePowerW"] == 450.0 and catalog["revision"] == 5
    history = db.docs["VehicleCatalogHistory/feliz_2025/revisions/5"]
    assert "voltageV" not in history["snapshot"]["battery"] and history["publishedBy"] == "qa166-feliz-specs"
    assert db.docs["VinFastModelSpecs/feliz_2025"]["chargerOutputW"] == 400.0
    assert db.docs["Vehicles/owner"]["chargerRatedW"] == 400.0
    assert db.docs["Vehicles/linked"]["chargerRatedW"] == 400.0
    assert "chargerRatedW" not in db.docs["Vehicles/other"]
    # Run again: nothing left to change.
    again = specs.run(db, "owner", apply=True, delete_field=DELETE)
    assert again["writes"] == 0 and db.commits == 1
