"""Real Firestore transaction tests. Never connect to production/ADC."""
import base64
import os
import uuid
from concurrent.futures import ThreadPoolExecutor
from unittest.mock import patch

import pytest
from google.auth.credentials import AnonymousCredentials
from google.cloud import firestore

from shelly.connection_codes import ConnectionCodeStore
from shelly.repositories import SmartChargeRepository

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
