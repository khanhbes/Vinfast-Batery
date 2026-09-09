"""Regression tests use fake identity/storage only; no live Firebase or relay."""
from unittest.mock import MagicMock

import pytest
import server
from ai_server.model_store import ModelStore


def test_csv_export_neutralizes_spreadsheet_formulas_without_changing_numbers():
    from csv_security import csv_text
    import csv
    import io

    rendered = csv_text([
        {'note': '=HYPERLINK("https://example.invalid")', 'power': -400, 'meta': {'source': '@user'}},
        {'note': '  +SUM(1,2)', 'power': 250, 'extra': '\t=cmd'},
    ])
    rows = list(csv.DictReader(io.StringIO(rendered)))
    assert rows[0]['note'].startswith("'=")
    assert rows[0]['power'] == '-400'
    assert rows[0]['meta'].startswith('{')
    assert rows[1]['note'].startswith("'  +")
    assert rows[1]['extra'].startswith("'\t")


def test_api_security_headers_and_https_only_hsts(client):
    plain = client.get('/api/health')
    assert plain.headers['X-Content-Type-Options'] == 'nosniff'
    assert plain.headers['X-Frame-Options'] == 'DENY'
    assert plain.headers['Content-Security-Policy'].startswith("default-src 'none'")
    assert plain.headers['Cache-Control'] == 'no-store'
    assert 'Strict-Transport-Security' not in plain.headers

    forwarded_https = client.get('/api/health', headers={'X-Forwarded-Proto': 'https'})
    assert forwarded_https.headers['Strict-Transport-Security'] == 'max-age=31536000'


def test_sliding_window_limiter_returns_retry_after_and_recovers():
    from request_limits import SlidingWindowLimiter

    now = [100.0]
    limiter = SlidingWindowLimiter(clock=lambda: now[0])
    assert limiter.check('prediction:user-a', 2, 60) is None
    assert limiter.check('prediction:user-a', 2, 60) is None
    assert limiter.check('prediction:user-a', 2, 60) == 60
    assert limiter.check('prediction:user-b', 2, 60) is None
    now[0] = 161.0
    assert limiter.check('prediction:user-a', 2, 60) is None


def test_limiter_cleanup_respects_each_buckets_window():
    from request_limits import SlidingWindowLimiter

    now = [0.0]
    limiter = SlidingWindowLimiter(clock=lambda: now[0])
    assert limiter.check('fine-tune:user-a', 1, 3600) is None
    now[0] = 120.0
    for index in range(255):
        assert limiter.check(f'prediction:{index}', 2, 60) is None
    assert limiter.check('fine-tune:user-a', 1, 3600) == 3480


@pytest.mark.parametrize('production,opt_in', [(True, 'true'), (False, 'false')])
def test_dev_key_never_implicitly_grants_admin(client, monkeypatch, production, opt_in):
    monkeypatch.setattr(server, '_IS_PRODUCTION', production)
    monkeypatch.setattr(server, '_DEV_ADMIN_KEY', 'fixture-only-key')
    monkeypatch.setenv('ALLOW_DEV_ADMIN_KEY', opt_in)
    assert client.get('/api/admin/ai/status', headers={'X-Admin-Key': 'fixture-only-key'}).status_code == 401


def test_bearer_user_cannot_be_elevated_by_dev_key(client, monkeypatch):
    monkeypatch.setattr(server, '_IS_PRODUCTION', False)
    monkeypatch.setattr(server, '_DEV_ADMIN_KEY', 'fixture-only-key')
    monkeypatch.setenv('ALLOW_DEV_ADMIN_KEY', 'true')
    monkeypatch.setattr(server, '_verify_token', lambda: ('user-a', 'a@test.invalid', 'user'))
    response = client.get('/api/admin/ai/status', headers={'X-Admin-Key': 'fixture-only-key', 'Authorization': 'Bearer fixture'})
    assert response.status_code == 403


def test_explicit_dev_key_is_rejected_for_non_loopback_client(client, monkeypatch):
    monkeypatch.setattr(server, '_IS_PRODUCTION', False)
    monkeypatch.setattr(server, '_DEV_ADMIN_KEY', 'fixture-only-key')
    monkeypatch.setenv('ALLOW_DEV_ADMIN_KEY', 'true')
    response = client.get('/api/admin/ai/status', headers={'X-Admin-Key': 'fixture-only-key'}, environ_overrides={'REMOTE_ADDR': '192.0.2.10'})
    assert response.status_code == 401


@pytest.mark.parametrize('method,path', [
    ('get', '/api/ai/dataset'), ('get', '/api/ai/dataset/export-csv'),
    ('post', '/api/ai/dataset/records'), ('put', '/api/ai/dataset/records/fixture'),
    ('post', '/api/ai/models/charging_time/fine-tune'),
])
@pytest.mark.parametrize('role,expected', [(None, 401), ('user', 403)])
def test_dataset_and_global_training_require_admin(client, monkeypatch, method, path, role, expected):
    monkeypatch.setattr(server, '_verify_token', lambda: ('user-a', 'a@test.invalid', role) if role else (None, None, None))
    assert getattr(client, method)(path, json={}).status_code == expected


@pytest.mark.parametrize('endpoint', ['battery-state', 'trip-prediction'])
def test_sync_derives_owner_from_identity(client, monkeypatch, endpoint):
    db = MagicMock()
    db.collection.return_value.add.return_value = (None, MagicMock(id='fixture'))
    monkeypatch.setattr(server, '_firestore_db', db)
    monkeypatch.setattr(server, '_verify_token', lambda: ('user-a', 'a@test.invalid', 'user'))
    response = client.post('/api/web/sync/' + endpoint, json={'ownerUid': 'user-b', 'vehicleId': 'fixture-vehicle', 'soc': 50})
    assert response.status_code == 200
    assert db.collection.return_value.add.call_args.args[0]['ownerUid'] == 'user-a'


@pytest.mark.parametrize('version,ext', [('a/../../outside', '.pkl'), ('a', '/../outside'), ('..', '.onnx'), ('a' * 129, '.onnx')])
def test_store_rejects_invalid_paths(tmp_path, version, ext):
    with pytest.raises(ValueError):
        ModelStore(str(tmp_path)).path_of(version, ext)


def test_remove_uses_original_extension(tmp_path):
    store = ModelStore(str(tmp_path))
    source = tmp_path / 'upload.onnx'
    source.write_bytes(b'harmless fixture')
    store.save_from_temp(str(source), 'v1', '', '.onnx')
    artifact = store.path_of('v1')
    store.remove('v1')
    from pathlib import Path
    assert not Path(artifact).exists()
    assert store.list_versions() == []


@pytest.mark.parametrize('filename', ['model.pkl', 'model.joblib', 'model.onnx.pkl', 'model.pt', 'model.unknown'])
def test_network_upload_rejects_executable_serialization(filename):
    from ai_server.upload_policy import validate_upload
    with pytest.raises(ValueError):
        validate_upload(filename, 'v1')


def test_upload_size_and_empty_file_cleanup(tmp_path, monkeypatch):
    import io
    import tempfile
    from ai_server.upload_policy import copy_upload
    monkeypatch.setattr(tempfile, 'tempdir', str(tmp_path))
    for contents in [b'', b'12345']:
        with pytest.raises(ValueError):
            copy_upload(io.BytesIO(contents), '.onnx', limit=4)
        assert list(tmp_path.iterdir()) == []


def test_sync_transaction_rejects_entire_batch_before_writes():
    from sync_writes import commit_owned_writes
    db, transaction = MagicMock(), MagicMock()
    first, second = MagicMock(), MagicMock()
    db.collection.return_value.document.side_effect = [first, second]
    first.get.return_value.exists = False
    second.get.return_value.exists = True
    second.get.return_value.to_dict.return_value = {'ownerUid': 'user-b'}
    with pytest.raises(PermissionError):
        commit_owned_writes(db, [('Vehicles', 'a', {}), ('Vehicles', 'b', {})], 'user-a', runner=lambda fn: fn(transaction))
    transaction.set.assert_not_called()


def test_sync_checks_related_vehicle_owner_before_creating_child():
    from sync_writes import commit_owned_writes
    db, transaction = MagicMock(), MagicMock()
    child, vehicle = MagicMock(), MagicMock()
    db.collection.return_value.document.side_effect = [child, vehicle]
    child.get.return_value.exists = False
    vehicle.get.return_value.exists = True
    vehicle.get.return_value.to_dict.return_value = {'ownerUid': 'user-b'}
    with pytest.raises(PermissionError):
        commit_owned_writes(db, [('ChargeLogs', 'log-a', {'vehicleId': 'b'})], 'user-a', runner=lambda fn: fn(transaction))
    transaction.set.assert_not_called()


def test_owner_sync_reads_then_writes_with_server_identity():
    from sync_writes import commit_owned_writes
    db, transaction = MagicMock(), MagicMock()
    db.collection.return_value.document.return_value.get.return_value.exists = False
    commit_owned_writes(db, [('Vehicles', 'a', {'ownerUid': 'spoofed'})], 'user-a', runner=lambda fn: fn(transaction))
    assert transaction.set.call_args.args[1]['ownerUid'] == 'user-a'


def test_full_sync_rejects_malformed_without_committing(client, monkeypatch):
    monkeypatch.setattr(server, '_verify_token', lambda: ('user-a', '', 'user'))
    monkeypatch.setattr(server, '_firestore_db', MagicMock())
    commit = MagicMock()
    monkeypatch.setattr(server, 'commit_owned_writes', commit)
    for payload in [[], {'vehicles': [None]}, {'profile': [], 'vehicles': []}, {'chargeLogs': [{'vehicleId': 'a'}]}]:
        assert client.post('/api/web/sync/full', json=payload).status_code == 400
    commit.assert_not_called()


@pytest.mark.parametrize('path', ['/api/telemetry', '/api/charge-logs'])
def test_telemetry_history_requires_login(client, path):
    assert client.get(path).status_code == 401


@pytest.mark.parametrize('path', ['/api/telemetry', '/api/charge-logs'])
def test_history_query_is_scoped_to_verified_owner(client, monkeypatch, path):
    db = MagicMock()
    query = db.collection.return_value
    query.where.return_value = query
    query.order_by.return_value = query
    query.limit.return_value = query
    query.stream.return_value = []
    monkeypatch.setattr(server, '_firestore_db', db)
    monkeypatch.setattr(server, '_verify_token', lambda: ('user-a', '', 'user'))
    assert client.get(path + '?ownerUid=user-b').status_code == 200
    query.where.assert_any_call('ownerUid', '==', 'user-a')


@pytest.mark.parametrize('method,path', [
    ('post', '/api/ai/predict-degradation'),
    ('post', '/api/ai/analyze-patterns'),
    ('post', '/api/ai/train-vehicle-profile'),
    ('get', '/api/ai/profile-status/vehicle-a'),
    ('post', '/api/ai/charge-feedback'),
])
def test_personal_ai_routes_require_identity(client, method, path):
    assert getattr(client, method)(path, json={}).status_code == 401


def test_personal_ai_rejects_other_users_vehicle(client, monkeypatch):
    db = MagicMock()
    vehicle = db.collection.return_value.document.return_value.get.return_value
    vehicle.exists = True
    vehicle.to_dict.return_value = {'ownerUid': 'user-b'}
    monkeypatch.setattr(server, '_firestore_db', db)
    monkeypatch.setattr(server, '_verify_token', lambda: ('user-a', '', 'user'))
    response = client.get('/api/ai/profile-status/vehicle-a')
    assert response.status_code == 403


def test_admin_data_snapshot_requires_admin(client, monkeypatch):
    monkeypatch.setattr(server, '_verify_token', lambda: ('user-a', 'a@test.invalid', 'user'))
    assert client.get('/api/admin/data-snapshot').status_code == 403


def test_admin_data_snapshot_exposes_shared_datasets_without_secrets(client, monkeypatch):
    db = MagicMock()
    db.collection.return_value.limit.return_value.stream.return_value = []
    db.collection_group.return_value.limit.return_value.stream.return_value = []
    monkeypatch.setattr(server, '_firestore_db', db)
    monkeypatch.setattr(server, '_verify_token', lambda: ('admin-a', 'admin@test.invalid', 'admin'))

    response = client.get('/api/admin/data-snapshot?limit=25')
    assert response.status_code == 200
    payload = response.get_json()['data']
    assert payload['schemaVersion'] == 'admin-data-snapshot-v1'
    assert payload['limitPerDataset'] == 25
    assert {'accounts', 'vehicles', 'chargeLogs', 'tripLogs', 'telemetry', 'aiProfiles', 'aiInsights'} <= set(payload['datasets'])

    redacted = server._redact_admin_snapshot({
        'name': 'charger',
        'cloudAuthKey': 'must-not-leak',
        'nested': {'access_token': 'must-not-leak-either'},
    })
    assert redacted == {
        'name': 'charger',
        'cloudAuthKey': '[redacted]',
        'nested': {'access_token': '[redacted]'},
    }


@pytest.fixture
def runtime_fixture(tmp_path, monkeypatch):
    from ai_server.model_runtime import ModelRuntime
    store = ModelStore(str(tmp_path))
    for version in ['a', 'b', 'c']:
        source = tmp_path / f'{version}.upload'
        source.write_bytes(b'not a real model; loader is stubbed')
        store.save_from_temp(str(source), version, '', '.onnx')
    runtime = ModelRuntime(store)
    monkeypatch.setattr(runtime, 'try_load_version', lambda version, **kw: {
        'model': version, 'predictor': version, 'validation': {'ok': True},
    })
    runtime.deploy_version('a')
    return runtime


def test_failed_validation_preserves_active_runtime_and_manifest(runtime_fixture, monkeypatch):
    runtime = runtime_fixture
    def fail(*args, **kwargs):
        raise RuntimeError('fixture validation failure')
    monkeypatch.setattr(runtime, 'try_load_version', fail)
    with pytest.raises(RuntimeError):
        runtime.deploy_version('b')
    assert runtime._current_ref() == ('a', 'a')
    assert runtime.store.active_version() == 'a'


def test_failed_manifest_write_preserves_active_runtime(runtime_fixture, monkeypatch):
    runtime = runtime_fixture
    def fail(*args, **kwargs):
        raise OSError('fixture disk failure')
    monkeypatch.setattr(runtime.store, '_write_manifest', fail)
    with pytest.raises(OSError):
        runtime.deploy_version('b')
    assert runtime._current_ref() == ('a', 'a')
    assert runtime.store.active_version() == 'a'


def test_deploy_and_delete_active_are_consistent(runtime_fixture):
    runtime_fixture.deploy_version('b')
    with pytest.raises(ValueError):
        runtime_fixture.remove_version('b')
    assert runtime_fixture._current_ref() == ('b', 'b')
    assert runtime_fixture.store.active_version() == 'b'


def test_concurrent_deploys_publish_same_manifest_and_runtime(runtime_fixture):
    from concurrent.futures import ThreadPoolExecutor
    with ThreadPoolExecutor(max_workers=2) as executor:
        list(executor.map(runtime_fixture.deploy_version, ['b', 'c'] * 10))
    predictor, version = runtime_fixture._current_ref()
    assert predictor == version == runtime_fixture.store.active_version()


def test_reset_clears_runtime_and_removes_only_registered_artifacts(runtime_fixture):
    runtime = runtime_fixture
    assert set(runtime.reset_versions()) == {'a', 'b', 'c'}
    assert runtime._current_ref() == (None, None)
    assert runtime.store.active_version() is None
    assert runtime.store.list_versions() == []


def test_flask_does_not_write_manifest_before_ai_confirmation(client, monkeypatch):
    monkeypatch.setattr(server, '_verify_token', lambda: ('admin-a', '', 'admin'))
    store_factory = MagicMock()
    persist_status = MagicMock()
    monkeypatch.setattr(server, '_model_store_for', store_factory)
    monkeypatch.setattr(server, '_save_model_deployment_status', persist_status)
    response = client.post('/api/admin/ai/models/charging_time/deploy', json={'version': 'b'})
    assert response.status_code == 502
    store_factory.assert_not_called()
    persist_status.assert_not_called()


def test_flask_deploy_requires_exact_version_confirmation(client, monkeypatch):
    monkeypatch.setattr(server, '_verify_token', lambda: ('admin-a', '', 'admin'))
    monkeypatch.setattr(server, '_ai_request_json', lambda *a, **kw: ({'success': True, 'data': {'activeVersion': 'wrong-version'}}, 200))
    persist_status = MagicMock()
    monkeypatch.setattr(server, '_save_model_deployment_status', persist_status)
    assert client.post('/api/admin/ai/models/charging_time/deploy', json={'version': 'b'}).status_code == 502
    persist_status.assert_not_called()
