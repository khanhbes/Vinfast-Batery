import copy
import os
import sys

import pytest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from vehicle_catalog import (
    CatalogValidationError,
    catalog_identity,
    commit_catalog_publish,
    create_user_vehicle,
    extract_candidate_from_text,
    legacy_projection,
    normalize_catalog_document,
    patch_personal_vehicle,
    validate_catalog_document,
    validate_official_sources,
    validate_research_url,
)


class FakeSnapshot:
    def __init__(self, ref, data=None):
        self.reference = ref
        self.id = ref.id
        self._data = copy.deepcopy(data)
        self.exists = data is not None

    def to_dict(self):
        return copy.deepcopy(self._data)


class FakeDocument:
    def __init__(self, db, collection, doc_id):
        self.db, self.collection_name, self.id = db, collection, doc_id

    def get(self, transaction=None):
        return FakeSnapshot(
            self,
            self.db.data.get(self.collection_name, {}).get(self.id),
        )

    def collection(self, name):
        return FakeCollection(self.db, f'{self.collection_name}/{self.id}/{name}')

    def set(self, value, merge=False):
        current = (
            self.db.data.setdefault(self.collection_name, {}).get(self.id, {})
            if merge
            else {}
        )
        self.db.data.setdefault(self.collection_name, {})[self.id] = {
            **current,
            **copy.deepcopy(value),
        }

    def update(self, value):
        self.db.data[self.collection_name][self.id].update(copy.deepcopy(value))

    def delete(self):
        self.db.data.get(self.collection_name, {}).pop(self.id, None)


class FakeCollection:
    def __init__(self, db, name):
        self.db, self.name = db, name

    def document(self, doc_id):
        return FakeDocument(self.db, self.name, doc_id)


class FakeDb:
    def __init__(self, data):
        self.data = copy.deepcopy(data)

    def collection(self, name):
        return FakeCollection(self, name)


class FakeTransaction:
    def set(self, ref, value, merge=False):
        ref.set(value, merge=merge)

    def delete(self, ref):
        ref.delete()


def complete_payload():
    return {
        'brandId': 'vinfast', 'brandName': 'VinFast', 'model': 'Evo',
        'variant': 'Evo200', 'modelYear': 2024, 'market': 'VN',
        'vehicleType': 'scooter',
        'localized': {
            'vi': {'displayName': 'VinFast Evo200'},
            'en': {'displayName': 'VinFast Evo200'},
        },
        'battery': {'calculationCapacityWh': 1872, 'chemistry': 'LFP'},
        'appDefaults': {
            'calculationCapacityWh': 1872,
            'defaultEfficiencyKmPerPercent': 1.2,
            'maxSafeChargePowerW': 480,
        },
        'sources': [{'url': 'https://vinfastauto.com/spec', 'publisher': 'VinFast'}],
    }


def test_normalization_and_identity_are_deterministic():
    first = normalize_catalog_document(complete_payload())
    second = normalize_catalog_document({**complete_payload(), 'brandName': '  VinFast  '})
    assert first['identityKey'] == second['identityKey'] == catalog_identity(first)
    assert first['appDefaults']['calculationCapacityWh'] == 1872


def test_publish_validation_requires_locales_source_and_safe_defaults():
    invalid = normalize_catalog_document({'brandName': 'Example'})
    errors = validate_catalog_document(invalid, for_publish=True)
    assert 'localized.vi.displayName is required' in errors
    assert 'at least one official source is required' in errors
    assert any('calculationCapacityWh' in error for error in errors)


def test_unresolved_conflict_blocks_publish():
    data = normalize_catalog_document({**complete_payload(), 'conflicts': [{'field': 'battery.voltageV', 'resolved': False}]})
    assert 'all source conflicts must be resolved before publishing' in validate_catalog_document(data, for_publish=True)


def test_publish_sources_must_use_approved_official_https_domains():
    data = normalize_catalog_document(complete_payload())
    assert validate_official_sources(data, ['vinfastauto.com']) == []
    assert validate_official_sources(data, []) == [
        'manufacturer official domains must be configured before publishing'
    ]
    data['sources'][0]['url'] = 'https://untrusted.example/spec'
    assert validate_official_sources(data, ['vinfastauto.com']) == [
        'sources[0].url must use an approved official HTTPS domain'
    ]


def test_research_url_blocks_off_domain_credentials_and_private_dns(monkeypatch):
    with pytest.raises(ValueError, match='approved official domain'):
        validate_research_url('https://untrusted.example/spec', ['vinfastauto.com'])
    with pytest.raises(ValueError, match='credential-free HTTPS'):
        validate_research_url(
            'https://admin:secret@vinfastauto.com/spec',
            ['vinfastauto.com'],
        )
    monkeypatch.setattr(
        'vehicle_catalog.socket.getaddrinfo',
        lambda *_args, **_kwargs: [
            (2, 1, 6, '', ('127.0.0.1', 443)),
        ],
    )
    with pytest.raises(ValueError, match='Private or non-routable'):
        validate_research_url('https://vinfastauto.com/spec', ['vinfastauto.com'])


def test_conservative_text_extraction_keeps_units_normalized():
    candidate = extract_candidate_from_text(
        'Battery capacity 82.5 kWh. Official range 500 km. Nominal voltage 400 V. Rated power 150 kW. Top speed 180 km/h.'
    )
    assert candidate['battery']['calculationCapacityWh'] == 82500
    assert candidate['performance']['rangeKm'] == 500
    assert candidate['performance']['ratedMotorPowerW'] == 150000
    assert candidate['appDefaults']['defaultEfficiencyKmPerPercent'] == 5


def test_legacy_projection_preserves_old_app_contract():
    data = normalize_catalog_document(complete_payload())
    data.update({'catalogId': 'evo200', 'revision': 3})
    legacy = legacy_projection(data)
    assert legacy['modelId'] == 'evo200'
    assert legacy['nominalCapacityWh'] == 1872
    assert legacy['specVersion'] == 3


def test_user_vehicle_is_created_from_catalog_not_client_specs():
    spec = normalize_catalog_document(complete_payload())
    spec.update({'catalogId': 'evo200', 'status': 'published', 'selectable': True, 'revision': 4})
    db = FakeDb({'VehicleCatalog': {'evo200': spec}, 'users': {'user-1': {'activeVehicleCount': 0}}})
    result, status = create_user_vehicle(db, 'user-1', {
        'catalogId': 'evo200', 'nickname': 'Daily ride', 'licensePlate': '29-AA',
        'batteryCapacity': 999999, 'initialOdo': 12,
    }, runner=lambda operation: operation(FakeTransaction()))
    assert status == 201
    vehicle = result['data']
    assert vehicle['batteryCapacity'] == 1872
    assert vehicle['vehicleName'] == 'Daily ride'
    assert vehicle['catalogRevisionAtSelection'] == 4
    assert vehicle['currentOdo'] == 12
    assert db.data['users']['user-1']['activeVehicleCount'] == 1


def test_archived_catalog_cannot_create_vehicle():
    spec = normalize_catalog_document(complete_payload())
    spec.update({'catalogId': 'evo200', 'status': 'published', 'selectable': False})
    db = FakeDb({'VehicleCatalog': {'evo200': spec}, 'users': {'user-1': {}}})
    _, status = create_user_vehicle(db, 'user-1', {'catalogId': 'evo200'})
    assert status == 409


def test_publish_transaction_writes_revision_meta_key_and_legacy_projection():
    draft = normalize_catalog_document(complete_payload())
    draft.update({'catalogId': 'evo200', 'status': 'draft', 'revision': 0})
    db = FakeDb({
        'VehicleCatalogDrafts': {'evo200': draft},
        'VehicleManufacturers': {
            'vinfast': {
                'name': 'VinFast',
                'officialDomains': ['vinfastauto.com'],
            },
        },
        'VehicleCatalogMeta': {'current': {'revision': 8}},
    })
    published, meta_revision, previous = commit_catalog_publish(
        db,
        'evo200',
        'admin-1',
        runner=lambda operation: operation(FakeTransaction()),
    )
    assert previous == {}
    assert published['status'] == 'published'
    assert published['revision'] == 1
    assert meta_revision == 9
    assert 'evo200' not in db.data['VehicleCatalogDrafts']
    assert db.data['VehicleCatalogKeys'][draft['identityKey']]['catalogId'] == 'evo200'
    assert db.data['VehicleCatalogHistory/evo200/revisions']['1']['snapshot']['catalogId'] == 'evo200'
    assert db.data['VinFastModelSpecs']['evo200']['nominalCapacityWh'] == 1872


def test_personal_patch_rejects_manufacturer_fields_and_checks_owner():
    db = FakeDb({'Vehicles': {'v1': {'ownerUid': 'user-1', 'vehicleName': 'Evo'}}})
    result, status = patch_personal_vehicle(db, 'user-1', 'v1', {'batteryCapacity': 999})
    assert status == 400
    assert result['fields'] == ['batteryCapacity']
    _, other_status = patch_personal_vehicle(db, 'other', 'v1', {'nickname': 'Mine'})
    assert other_status == 403


def test_personal_patch_preserves_technical_values():
    db = FakeDb({'Vehicles': {'v1': {'ownerUid': 'user-1', 'vehicleName': 'Evo', 'batteryCapacity': 1872, 'catalogSnapshot': {'displayName': 'VinFast Evo200'}}}})
    result, status = patch_personal_vehicle(db, 'user-1', 'v1', {'nickname': 'Commute', 'currentOdo': 150})
    assert status == 200 and result['success'] is True
    assert db.data['Vehicles']['v1']['batteryCapacity'] == 1872
    assert db.data['Vehicles']['v1']['vehicleName'] == 'Commute'
