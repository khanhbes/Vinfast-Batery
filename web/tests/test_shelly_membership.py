import base64
from concurrent.futures import ThreadPoolExecutor

import pytest
from unittest.mock import Mock
from google.api_core.exceptions import Aborted

from shelly.connection_codes import ConnectionCodeStore
from shelly.repositories import SmartChargeRepository
from shelly.providers import FakeShellyProvider
from shelly.service import SmartChargeService, SmartChargeError
from shelly.models import DeviceBinding, DeviceStatus
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


def test_metadata_contention_retry_is_bounded_and_does_not_retry_other_errors(monkeypatch):
    repo = SmartChargeRepository(Mock())
    monkeypatch.setattr('shelly.repositories.time.sleep', lambda _: None)
    action = Mock(side_effect=[Aborted('QA conflict'), Aborted('QA conflict'), 'committed'])
    assert repo._run_metadata_transaction(action) == 'committed'
    assert action.call_count == 3
    failure = Mock(side_effect=RuntimeError('QA storage failure'))
    with pytest.raises(RuntimeError):
        repo._run_metadata_transaction(failure)
    assert failure.call_count == 1
    exhausted = Mock(side_effect=Aborted('QA exhausted'))
    with pytest.raises(Aborted):
        repo._run_metadata_transaction(exhausted)
    assert exhausted.call_count == 3


def test_second_member_stops_shared_device_without_receiving_private_history():
    repo = SmartChargeRepository()
    repo.claim_worker_lease("qa-worker")
    repo.publish_worker_heartbeat("qa-worker", healthy=True)
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


def test_code_enrolls_only_selected_owned_vehicle_and_retry_keeps_evidence(monkeypatch):
    repo, _, entry = enrollment(monkeypatch)
    repo.register_vehicle_owner('a', 'vehicle-a')
    repo.register_vehicle_owner('a', 'vehicle-other')
    first = repo.enroll_connection_code('a', entry, 'op-a', vehicle_id='vehicle-a')
    assert first['vehicleId'] == 'vehicle-a'
    assert first['shared'] is False
    assert repo.get_binding('a', 'vehicle-a').device_id == entry.device_id
    assert repo.get_binding('a', 'vehicle-other') is None
    first['noLoadTestVerified'] = True
    repo._synced_profiles[('a', entry.device_id)] = first
    again = repo.enroll_connection_code('a', entry, 'op-a', vehicle_id='vehicle-a')
    assert again['noLoadTestVerified'] is True
    assert entry.redemption_count == 1
    with pytest.raises(ValueError, match='bindingVehicleConflict'):
        repo.enroll_connection_code('a', entry, 'op-other', vehicle_id='vehicle-other')
    assert repo.get_binding('a', 'vehicle-other') is None


def test_member_redeem_upgrades_legacy_direct_profile_to_server_cloud(monkeypatch):
    """Task108: an existing member with a legacy advanced_direct profile must not
    have the redeem silently keep legacy mode; it upgrades with fresh evidence."""
    repo, _, entry = enrollment(monkeypatch)
    repo.register_vehicle_owner('a', 'vehicle-a')
    first = repo.enroll_connection_code('a', entry, 'op-a', vehicle_id='vehicle-a')
    legacy = dict(first, connectionMode='advanced_direct', provider='direct_cloud_lan',
                  noLoadTestVerified=True)
    repo._synced_profiles[('a', entry.device_id)] = legacy
    repo._bindings['a'][entry.device_id] = DeviceBinding(
        device_id=entry.device_id, display_name='Plug', model=entry.model, generation=3,
        provider='direct_cloud_lan', connection_mode='advanced_direct', vehicle_id='vehicle-a',
        no_load_test_verified=True, owner_uid='a')
    upgraded = repo.enroll_connection_code('a', entry, 'op-upgrade', vehicle_id='vehicle-a')
    assert upgraded['connectionMode'] == 'server_cloud'
    assert upgraded['provider'] == 'vault_cloud'
    assert upgraded['vehicleId'] == 'vehicle-a'
    assert upgraded['noLoadTestVerified'] is False
    binding = repo.get_binding('a', 'vehicle-a')
    assert binding.connection_mode == 'server_cloud'
    assert binding.no_load_test_verified is False
    assert entry.redemption_count == 1
    assert len(repo._device_members[repo._device_owner_doc_id(entry.device_id)]) == 1
    # Server enrollments still keep their evidence on a later rotation/replay.
    upgraded['noLoadTestVerified'] = True
    repo._synced_profiles[('a', entry.device_id)] = upgraded
    again = repo.enroll_connection_code('a', entry, 'op-again', vehicle_id='vehicle-a')
    assert again['noLoadTestVerified'] is True


def test_invalid_or_archived_vehicle_consumes_no_member_slot(monkeypatch):
    repo, _, entry = enrollment(monkeypatch)
    repo.register_vehicle_owner('b', 'vehicle-b')
    with pytest.raises(PermissionError, match='vehicleForbidden'):
        repo.enroll_connection_code('a', entry, 'op-a', vehicle_id='vehicle-b')
    repo.set_vehicle_archived('b', 'vehicle-b')
    with pytest.raises(PermissionError, match='vehicleForbidden'):
        repo.enroll_connection_code('b', entry, 'op-b', vehicle_id='vehicle-b')
    assert entry.redemption_count == 0
    assert repo.device_member_count(entry.device_id) == 0


def test_exact_vehicle_binding_wins_and_ambiguous_binding_never_picks_first():
    repo = SmartChargeRepository()
    repo.register_vehicle_owner('a', 'vehicle-a')
    common = dict(model='S3PL-00112EU', generation=3, provider='fake')
    shared = DeviceBinding(device_id='shared', display_name='Shared', shared=True, **common)
    exact = DeviceBinding(device_id='exact', display_name='Exact', vehicle_id='vehicle-a', **common)
    repo.save_binding('a', shared)
    repo.save_binding('a', exact)
    assert repo.get_binding('a', 'vehicle-a') is exact
    assert repo.get_binding('a') is None
    duplicate = DeviceBinding(device_id='duplicate', display_name='Duplicate', vehicle_id='vehicle-a', **common)
    repo.save_binding('a', duplicate)
    assert repo.get_binding('a', 'vehicle-a') is None


def test_changed_confirmation_device_is_rejected_before_any_hardware_command():
    repo = SmartChargeRepository()
    provider = FakeShellyProvider()
    service = SmartChargeService(repo, provider, lambda _: {}, sleeper=lambda _: None)
    repo.save_binding('a', provider.list_devices('a')[0])
    repo.register_vehicle_owner('a', 'vehicle-a')
    with pytest.raises(SmartChargeError) as caught:
        service.manual_on('a', 300, 'op-a', 'vehicle-a', 20, expected_device_id='other')
    assert caught.value.code == 'bindingChanged'
    with pytest.raises(SmartChargeError) as caught:
        service.stop('a', vehicle_id='vehicle-a', expected_device_id='other')
    assert caught.value.code == 'bindingChanged'
    assert provider.command_count == 0


def test_shared_capabilities_block_new_on_and_hide_other_members_session(monkeypatch):
    monkeypatch.delenv('AZURE_STAGING_HARDWARE_DISABLED', raising=False)
    repo = SmartChargeRepository()
    repo.claim_worker_lease("qa-worker")
    repo.publish_worker_heartbeat("qa-worker", healthy=True)
    provider = FakeShellyProvider()
    service = SmartChargeService(repo, provider, lambda _: {}, sleeper=lambda _: None)
    for uid in ['a', 'b']:
        repo.save_binding(uid, provider.list_devices(uid)[0])
        repo.register_vehicle_owner(uid, f'vehicle-{uid}')
    session = service.manual_on('a', 300, 'op-a', 'vehicle-a', 20)
    caps = service.capabilities('b', 'vehicle-b')
    assert caps['canManualOn'] is False
    assert caps['canManualOff'] is True
    assert caps['controlBlockedCode'] == 'activeSessionConflict'
    assert session.session_id not in str(caps)
    assert 'vehicle-a' not in str(caps)
    session.state = 'unknown'
    repo.save_session('a', session)
    caps = service.capabilities('b', 'vehicle-b')
    assert caps['readyForControl'] is False
    assert caps['controlBlockedCode'] == 'relayUnverified'
    assert provider.command_count == 1


@pytest.mark.parametrize('online,device_id', [(False, 'test-plug'), (True, 'other-plug')])
def test_offline_or_wrong_device_off_readback_never_finalizes_session(online, device_id):
    repo = SmartChargeRepository()
    repo.claim_worker_lease("qa-worker")
    repo.publish_worker_heartbeat("qa-worker", healthy=True)
    provider = FakeShellyProvider()
    service = SmartChargeService(repo, provider, lambda _: {}, sleeper=lambda _: None)
    repo.save_binding('a', provider.list_devices('a')[0])
    repo.register_vehicle_owner('a', 'vehicle-a')
    session = service.manual_on('a', 300, 'op-a', 'vehicle-a', 20)
    provider.get_status = lambda _: DeviceStatus(online=online, relay=False, device_id=device_id)
    with pytest.raises(SmartChargeError):
        service.stop('a', session.session_id)
    assert repo.get_session('a', session.session_id).state in ('active', 'stopping', 'unknown')
    assert not repo.claim_device_session('a', session.device_id, 'second-on')
