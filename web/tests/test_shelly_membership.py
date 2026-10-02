import base64
from concurrent.futures import ThreadPoolExecutor

import pytest

from shelly.connection_codes import ConnectionCodeStore
from shelly.repositories import SmartChargeRepository
from shelly.providers import FakeShellyProvider
from shelly.service import SmartChargeService
from shelly.routes import create_blueprint
from flask import Flask


def enrollment(monkeypatch):
    monkeypatch.setenv('SHELLY_PROFILE_MASTER_KEY', base64.urlsafe_b64encode(b't' * 32).decode())
    repo = SmartChargeRepository()
    store = ConnectionCodeStore()
    entry = store.generate(device_id='test-plug', device_name='Plug', model='S3PL-00112EU',
        cloud_host='https://shelly.cloud', cloud_auth_key='test-only', created_by='test-admin')
    return repo, store, entry


def test_two_concurrent_members_only_and_same_uid_does_not_take_extra_slot():
    repo = SmartChargeRepository()
    with ThreadPoolExecutor(max_workers=3) as pool:
        results = list(pool.map(lambda uid: repo.claim_device_owner(uid, 'AA:BB:CC'), ['a', 'b', 'c']))
    assert sum(results) == 2
    winner = ['a', 'b', 'c'][results.index(True)]
    assert repo.claim_device_owner(winner, 'aabbcc')


def test_legacy_owner_is_preserved_as_first_member():
    repo = SmartChargeRepository()
    key = repo._device_owner_doc_id('test-plug')
    repo._device_owners[key] = 'legacy'
    assert repo.claim_device_owner('new-member', 'test-plug')
    assert repo.device_owned_by('legacy', 'test-plug')
    assert not repo.claim_device_owner('third', 'test-plug')


def test_device_operation_is_global_and_membership_cannot_be_removed_while_locked():
    repo = SmartChargeRepository()
    repo.claim_device_owner('a', 'AABB')
    repo.claim_device_owner('b', 'AA:BB')
    assert repo.claim_device_session('a', 'AABB', 'operation-a')
    assert not repo.claim_device_session('b', 'AA:BB', 'operation-b')
    assert not repo.release_device_owner('b', 'AABB')
    repo.release_device_session('a', 'AA:BB', 'operation-a')
    assert repo.release_device_owner('b', 'AABB')
    assert repo.claim_device_owner('c', 'AABB')


def test_enrollment_is_idempotent_and_does_not_lose_verification_on_code_rotation(monkeypatch):
    repo, store, entry = enrollment(monkeypatch)
    first = repo.enroll_connection_code('a', entry, 'op-a')
    first['noLoadTestVerified'] = True
    repo._synced_profiles[('a', entry.device_id)] = first
    repo.enroll_connection_code('a', entry, 'op-a')
    assert entry.redemption_count == 1
    repo.enroll_connection_code('b', entry, 'op-b')
    with pytest.raises(PermissionError, match='DEVICE_MEMBER_LIMIT_REACHED'):
        repo.enroll_connection_code('c', entry, 'op-c')
    rotated = store.generate(device_id=entry.device_id, device_name='Plug', model=entry.model,
        cloud_host=entry.cloud_host, cloud_auth_key='test-only', created_by='test-admin')
    assert entry.is_revoked
    assert rotated.code_version == entry.code_version + 1
    restored = repo.enroll_connection_code('a', rotated, 'op-new')
    assert restored['noLoadTestVerified'] is True
    assert len(repo._device_members[repo._device_owner_doc_id(entry.device_id)]) == 2
    with pytest.raises(ValueError, match='connectionCodeUnavailable'):
        repo.enroll_connection_code('a', entry, 'old-replay')


def test_vault_failure_does_not_consume_code_or_member_slot(monkeypatch):
    repo, store, entry = enrollment(monkeypatch)
    def fail(*args, **kwargs):
        raise RuntimeError('test failure')
    monkeypatch.setattr(repo._profile_vault, 'encrypt', fail)
    with pytest.raises(RuntimeError):
        repo.enroll_connection_code('a', entry, 'op-a')
    assert entry.redemption_count == 0
    assert not repo.device_owned_by('a', entry.device_id)


def test_second_member_stops_shared_device_without_receiving_private_history():
    repo = SmartChargeRepository()
    provider = FakeShellyProvider()
    service = SmartChargeService(repo, provider, lambda _: {'predictedDurationSeconds': 300}, sleeper=lambda _: None)
    for uid in ['a', 'b']:
        binding = provider.list_devices(uid)[0]
        repo.save_binding(uid, binding)
        repo.register_vehicle_owner(uid, f'vehicle-{uid}')
    session = service.manual_on('a', 300, 'operation-a', 'vehicle-a', 20)
    app = Flask(__name__)
    app.register_blueprint(create_blueprint(service, repo, lambda: ('b', None, 'user')))
    response = app.test_client().post('/api/smart-charging/off')
    assert response.status_code == 200
    assert response.json['data'] is None
    assert response.json['relayOffVerified'] is True
    assert 'vehicle-a' not in response.get_data(as_text=True)
    assert repo.get_session('a', session.session_id).state == 'cancelled'
    assert repo.get_session('b', session.session_id) is None
    assert provider.status.relay is False
