"""Real Firestore transaction tests. Never connect to production/ADC."""
import base64
import hashlib
import os
import threading
import time
import uuid
from copy import deepcopy
from datetime import timedelta
from concurrent.futures import ThreadPoolExecutor
from unittest.mock import patch

import pytest
from google.auth.credentials import AnonymousCredentials
from google.cloud import firestore

from shelly.connection_codes import ConnectionCodeStore
from shelly.repositories import SmartChargeRepository
from shelly.models import ChargingSession, utcnow

pytestmark = pytest.mark.skipif(
    not os.environ.get('FIRESTORE_EMULATOR_HOST'), reason='Requires isolated Firestore Emulator',
)


@pytest.fixture
def fixture(monkeypatch):
    host = os.environ['FIRESTORE_EMULATOR_HOST'].split(':')[0]
    assert host in ('localhost', '127.0.0.1'), 'Refuse non-local emulator'
    monkeypatch.setenv('SHELLY_PROFILE_MASTER_KEY', base64.urlsafe_b64encode(b't' * 32).decode())
    db = firestore.Client(project='vinfast-rules-test', credentials=AnonymousCredentials())
    device = 'test-' + uuid.uuid4().hex
    store = ConnectionCodeStore(db)
    code = store.generate(device_id=device, device_name='Test plug', model='S3PL-00112EU',
        cloud_host='https://shelly.cloud', cloud_auth_key='test-only', created_by='test-admin')
    yield db, device, store, code
    db.close()


def test_two_members_across_independent_repository_workers(fixture):
    db, device, _, _ = fixture
    def claim(uid):
        return SmartChargeRepository(db).claim_device_owner(uid, device)
    with ThreadPoolExecutor(max_workers=3) as pool:
        results = list(pool.map(claim, ['account-a', 'account-b', 'account-c']))
    assert sum(results) == 2
    assert SmartChargeRepository(db).device_member_count(device) == 2


def test_atomic_enrollment_rotation_and_revoked_replay(fixture):
    db, device, store, code = fixture
    def enroll(uid):
        return SmartChargeRepository(db).enroll_connection_code(uid, code, 'op-' + uid)
    with ThreadPoolExecutor(max_workers=2) as pool:
        list(pool.map(enroll, ['account-a', 'account-b']))
    repo = SmartChargeRepository(db)
    assert repo.device_member_count(device) == 2
    assert db.collection('shellyConnectionCodes').document(code.code).get().to_dict()['redemptionCount'] == 2
    repo.enroll_connection_code('account-a', code, 'op-retry')
    assert db.collection('shellyConnectionCodes').document(code.code).get().to_dict()['redemptionCount'] == 2
    with pytest.raises(PermissionError, match='DEVICE_MEMBER_LIMIT_REACHED'):
        repo.enroll_connection_code('account-c', code, 'op-third')
    repo._profile_doc('account-a', device).set({'noLoadTestVerified': True, 'verificationFingerprint': 'test-evidence'}, merge=True)
    rotated = store.generate(device_id=device, device_name='Test plug', model=code.model,
        cloud_host=code.cloud_host, cloud_auth_key='test-only', created_by='test-admin')
    assert repo.device_membership('account-a', device)['codeRefreshRequired'] is True
    profile = repo.enroll_connection_code('account-a', rotated, 'op-new-code')
    assert profile['noLoadTestVerified'] is True
    assert profile['verificationFingerprint'] == 'test-evidence'
    assert repo.device_membership('account-a', device)['codeRefreshRequired'] is False
    assert repo.device_member_count(device) == 2
    with pytest.raises(ValueError, match='connectionCodeUnavailable'):
        repo.enroll_connection_code('account-a', code, 'op-old-code')


def test_unlink_races_device_operation_atomically(fixture):
    db, device, _, _ = fixture
    repo_a = SmartChargeRepository(db)
    repo_b = SmartChargeRepository(db)
    assert repo_a.claim_device_owner('account-a', device)
    with ThreadPoolExecutor(max_workers=2) as pool:
        unlink = pool.submit(repo_a.release_device_owner, 'account-a', device)
        start = pool.submit(repo_b.claim_device_session, 'account-a', device, 'op-start')
        released, started = unlink.result(), start.result()
    assert released != started


def test_failed_commit_leaves_no_partial_enrollment_or_consumed_code(fixture):
    db, device, _, code = fixture
    repo = SmartChargeRepository(db)
    transaction = db.transaction()
    with patch.object(db, 'transaction', return_value=transaction), patch.object(
        transaction, '_commit', side_effect=RuntimeError('Injected commit failure'),
    ):
        with pytest.raises(RuntimeError, match='Injected commit failure'):
            repo.enroll_connection_code('account-a', code, 'op-failed')
    assert repo.device_member_count(device) == 0
    assert not repo._profile_doc('account-a', device).get().exists
    assert db.collection('shellyConnectionCodes').document(code.code).get().to_dict()['redemptionCount'] == 0


def test_scoped_enrollment_and_binding_changes_are_visible_to_other_workers(fixture):
    db, device, _, code = fixture
    vehicle_id = 'qa-vehicle-' + uuid.uuid4().hex
    db.collection('Vehicles').document(vehicle_id).set({'ownerUid': 'account-a'})
    repo_a = SmartChargeRepository(db)
    repo_b = SmartChargeRepository(db)
    with pytest.raises(PermissionError, match='vehicleForbidden'):
        repo_a.enroll_connection_code('account-b', code, 'op-wrong-vehicle', vehicle_id=vehicle_id)
    assert repo_a.device_member_count(device) == 0
    profile = repo_a.enroll_connection_code('account-a', code, 'op-a', vehicle_id=vehicle_id)
    assert profile['vehicleId'] == vehicle_id
    assert profile['shared'] is False
    assert repo_b.get_binding('account-a', vehicle_id).no_load_test_verified is False
    # Worker B must not retain its pre-verification cache forever.
    repo_a._profile_doc('account-a', device).set({'noLoadTestVerified': True}, merge=True)
    assert repo_b.get_binding('account-a', vehicle_id).no_load_test_verified is True
    db.collection('Vehicles').document(vehicle_id).update({'isArchived': True})
    with pytest.raises(PermissionError, match='vehicleForbidden'):
        repo_a.enroll_connection_code('account-a', code, 'op-after-archive', vehicle_id=vehicle_id)
    assert db.collection('shellyConnectionCodes').document(code.code).get().to_dict()['redemptionCount'] == 1


def test_heartbeat_visible_across_api_worker_and_isolated_by_environment(fixture):
    db, _, _, _ = fixture
    scope = 'qa-' + uuid.uuid4().hex
    worker = SmartChargeRepository(db, worker_scope=scope)
    api = SmartChargeRepository(db, worker_scope=scope)
    other_environment = SmartChargeRepository(db, worker_scope='other-' + scope)
    now = utcnow()
    assert api.worker_health_ready(now) is False
    assert worker.claim_worker_lease('qa-worker', now=now) == 1
    worker.publish_worker_heartbeat('qa-worker', healthy=True, now=now)
    assert api.worker_health_ready(now) is True
    assert other_environment.worker_health_ready(now) is False
    assert api.worker_health_ready(now + timedelta(seconds=91)) is False
    worker.publish_worker_heartbeat('qa-worker', healthy=False, now=now)
    assert api.worker_health_ready(now) is False


def test_independent_worker_cannot_resurrect_terminal_session_or_change_device(fixture):
    db, device, _, _ = fixture
    repo_a, repo_b = SmartChargeRepository(db), SmartChargeRepository(db)
    now = utcnow()
    session = ChargingSession(
        session_id='qa-' + uuid.uuid4().hex, device_id=device, vehicle_id='qa-vehicle',
        state='active', start_soc=20, target_soc=20, predicted_minutes=5,
        predicted_duration_seconds=300, prediction_source='manual_timer',
        prediction_confidence=None, created_at=now, updated_at=now,
        ai_stop_at=now + timedelta(seconds=300), effective_stop_at=now + timedelta(seconds=300),
        absolute_safety_stop_at=now + timedelta(seconds=600), idempotency_key='qa-op',
        owner_uid='account-a', relay_verified=True,
    )
    repo_a.save_session('account-a', session)
    stale = deepcopy(repo_b.get_session('account-a', session.session_id))
    session.state, session.version = 'cancelled', 2
    repo_a.save_session('account-a', session)
    stale.version = 3
    with pytest.raises(RuntimeError, match='sessionAlreadyTerminal'):
        repo_b.save_session('account-a', stale)
    doc = db.collection('users').document('account-a').collection('smartChargingSessions').document(session.session_id)
    assert doc.get().to_dict()['state'] == 'cancelled'
    changed = deepcopy(session)
    changed.device_id = 'qa-wrong-device'
    with pytest.raises(PermissionError, match='sessionIdentityMismatch'):
        repo_b.save_session('account-a', changed)


def test_terminal_and_active_writes_race_without_terminal_regression(fixture):
    db, device, _, _ = fixture
    now = utcnow()
    session = ChargingSession(
        session_id='qa-' + uuid.uuid4().hex, device_id=device, vehicle_id='qa-vehicle',
        state='active', start_soc=20, target_soc=20, predicted_minutes=5,
        predicted_duration_seconds=300, prediction_source='manual_timer',
        prediction_confidence=None, created_at=now, updated_at=now,
        ai_stop_at=now, effective_stop_at=now, absolute_safety_stop_at=now,
        idempotency_key='qa-op', owner_uid='account-a', relay_verified=True,
    )
    SmartChargeRepository(db).save_session('account-a', session)
    terminal = deepcopy(session)
    terminal.state, terminal.version = 'cancelled', 2
    stale = deepcopy(session)
    stale.version = 2
    def write(candidate):
        try:
            SmartChargeRepository(db).save_session('account-a', candidate)
            return True
        except RuntimeError as error:
            assert str(error) == 'sessionAlreadyTerminal'
            return False
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(write, [terminal, stale]))
    assert results[0] is True
    saved = db.collection('users').document('account-a').collection('smartChargingSessions').document(session.session_id).get().to_dict()
    assert saved['state'] == 'cancelled'


def test_lan_release_is_exact_typed_operation_and_never_releases_charging(fixture):
    db, device, _, _ = fixture
    repo = SmartChargeRepository(db)
    assert repo.claim_device_owner('account-a', device)
    assert repo.claim_device_session('account-a', device, 'qa-lan', lease_kind='lan_control')
    other_process = SmartChargeRepository(db)
    assert other_process.release_lan_operation_after_off('account-a', device, 'qa-other') is False
    assert other_process.release_lan_operation_after_off('account-b', device, 'qa-lan') is False
    assert other_process.release_lan_operation_after_off('account-a', device, 'qa-lan') is True
    assert repo.claim_device_session('account-a', device, 'qa-charging')
    assert other_process.release_lan_operation_after_off('account-a', device, 'qa-charging') is False
    assert not other_process.claim_device_session('account-a', device, 'qa-second')


def test_concurrent_worker_lease_has_one_holder_and_fenced_takeover(fixture):
    db, _, _, _ = fixture
    scope = 'qa-lease-' + uuid.uuid4().hex
    repos = [SmartChargeRepository(db, worker_scope=scope) for _ in range(2)]
    now = utcnow()
    with ThreadPoolExecutor(max_workers=2) as pool:
        claims = list(pool.map(lambda index: repos[index].claim_worker_lease('qa-' + str(index), now=now), range(2)))
    assert sum(epoch is not None for epoch in claims) == 1
    winner = 0 if claims[0] else 1
    loser = 1 - winner
    repos[winner].publish_worker_heartbeat('qa-' + str(winner), healthy=True, now=now)
    assert repos[winner].worker_lease_deadline('qa-' + str(winner), now=now) == now + timedelta(seconds=180)
    assert repos[loser].worker_health_ready(now)
    later = now + timedelta(seconds=181)
    assert repos[loser].claim_worker_lease('qa-' + str(loser), now=later) == 2
    assert not repos[winner].worker_health_ready(later)
    with pytest.raises(RuntimeError, match='workerLeaseLost'):
        repos[winner].publish_worker_heartbeat('qa-' + str(winner), healthy=True, now=later)
    with pytest.raises(RuntimeError, match='workerLeaseLost'):
        repos[winner].renew_worker_lease('qa-' + str(winner), now=later)
    with pytest.raises(RuntimeError, match='workerLeaseLost'):
        repos[winner].worker_lease_deadline('qa-' + str(winner), now=later)
    assert not repos[winner].release_worker_lease('qa-' + str(winner), now=later)
    repos[loser].publish_worker_heartbeat('qa-' + str(loser), healthy=True, now=later)
    assert repos[winner].worker_health_ready(later)


def test_server_cloud_enrollment_restores_vault_and_safety_revision_is_transactional(fixture):
    db, device, _, code = fixture
    repo = SmartChargeRepository(db)
    enrolled = repo.enroll_connection_code('account-a', code, 'qa-enroll-safety')
    assert enrolled['connectionMode'] == 'server_cloud'
    # Regression: Firestore restore used to filter server_cloud out, whereas
    # its in-memory equivalent kept it. Never print decrypted QA credentials.
    restored = SmartChargeRepository(db).restore_synced_profile('account-a', device)
    assert restored is not None and restored['deviceId'] == device
    evidence = {'verifiedDeviceId': device, 'verifiedModel': code.model,
                'verificationFingerprint': 'qa-versioned-evidence', 'verificationFingerprintVersion': 1,
                **{key: True for key in ('cloudVerified', 'powerMeterVerified', 'safeBootVerified', 'noLoadTestVerified',
                                       'onObserved', 'timerObserved', 'timerAutoOffObserved', 'relayOffVerified')}}

    def verify(_):
        try:
            result = SmartChargeRepository(db).verify_synced_profile('account-a', device, evidence,
                                                                     expected_revision=enrolled['revision'])
            assert result is not None
            return True
        except RuntimeError as error:
            assert str(error) == 'profileRevisionConflict'
            return False

    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(verify, range(2)))
    assert sum(results) == 1
    saved = repo._profile_doc('account-a', device).get().to_dict()
    assert saved['revision'] == enrolled['revision'] + 1
    assert saved['verificationFingerprintVersion'] == 1 and saved['timerAutoOffObserved'] is True

    # Rotation advances metadata revision; a delayed safety-test completion
    # must not restore historical no-load evidence over the new credential.
    rotated = repo.save_synced_profile('account-a', {
        'deviceId': device, 'model': code.model, 'cloudHost': code.cloud_host,
        'cloudAuthKey': 'rotated-test-only',
    }, expected_revision=saved['revision'])
    with pytest.raises(RuntimeError, match='profileRevisionConflict'):
        repo.verify_synced_profile('account-a', device, evidence, expected_revision=saved['revision'])
    final = repo._profile_doc('account-a', device).get().to_dict()
    assert final['revision'] == rotated['revision'] and final['noLoadTestVerified'] is False


def test_shared_cloud_dispatch_off_priority_and_spacing(fixture):
    """Separate repositories/threads, real transactions, fake HTTP only."""
    db, device, _, _ = fixture
    fingerprint = hashlib.sha256(('qa-dispatch-' + device).encode()).hexdigest()
    ref = db.collection('shellyCloudRateLimits').document(fingerprint)
    repos = [SmartChargeRepository(db) for _ in range(3)]
    entered, release = threading.Event(), threading.Event()
    calls = []
    lock = threading.Lock()

    def http_fixture(name, hold=False):
        with lock:
            calls.append((name, time.monotonic()))
        if hold:
            entered.set()
            assert release.wait(5), 'Fixture release was not signalled'

    with ThreadPoolExecutor(max_workers=3) as pool:
        first = pool.submit(repos[0].run_cloud_request, fingerprint,
                            lambda: http_fixture('inflight', True))
        try:
            assert entered.wait(5)
            off = pool.submit(repos[1].run_cloud_request, fingerprint,
                              lambda: http_fixture('off'), priority_off=True)
            deadline = time.monotonic() + 3
            while time.monotonic() < deadline:
                if (ref.get().to_dict() or {}).get('offWaiters'):
                    break
                time.sleep(.05)
            else:
                pytest.fail('OFF was not registered within the fixture budget')
            read = pool.submit(repos[2].run_cloud_request, fingerprint,
                               lambda: http_fixture('read'))
            release.set()
            for future in (first, off, read):
                future.result(timeout=10)
        finally:
            release.set()
    assert [name for name, _ in calls] == ['inflight', 'off', 'read']
    assert all(b[1] - a[1] >= 1.1 for a, b in zip(calls, calls[1:]))
    state = ref.get().to_dict()
    assert not state.get('leaseId') and state['offWaiters'] == {}


def test_shared_cloud_cooldown_survives_independent_repository(fixture):
    db, device, _, _ = fixture
    fingerprint = hashlib.sha256(('qa-cooldown-' + device).encode()).hexdigest()
    first, second = SmartChargeRepository(db), SmartChargeRepository(db)
    first.defer_cloud_requests(fingerprint, 60)
    from shelly.cloud_dispatch import CloudAdmissionError
    with pytest.raises(CloudAdmissionError, match='cloudQueueBusy'):
        second.run_cloud_request(fingerprint, lambda: pytest.fail('HTTP must not run'),
                                 priority_off=True)
    state = db.collection('shellyCloudRateLimits').document(fingerprint).get().to_dict()
    assert state['cooldownUntil'] > utcnow() + timedelta(seconds=30)
    assert state['offWaiters'] == {} and not state.get('leaseId')
