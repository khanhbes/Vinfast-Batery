import os
import sys
import pytest
from datetime import datetime, timezone, timedelta

# Ensure web/ directory is on sys.path
web_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if web_dir not in sys.path:
    sys.path.insert(0, web_dir)

import server
from server import validate_date_of_birth


def test_validate_date_of_birth():
    # Valid date
    ok, err = validate_date_of_birth("1995-08-15")
    assert ok is True
    assert err is None

    # Invalid formats
    ok, err = validate_date_of_birth("15-08-1995")
    assert ok is False
    assert "YYYY-MM-DD" in err

    ok, err = validate_date_of_birth("invalid")
    assert ok is False

    # Future date
    future_date = (datetime.now(timezone.utc).date() + timedelta(days=2)).strftime("%Y-%m-%d")
    ok, err = validate_date_of_birth(future_date)
    assert ok is False
    assert "tương lai" in err

    # Age > 120
    ok, err = validate_date_of_birth("1890-01-01")
    assert ok is False
    assert "120" in err


class FakeDoc:
    def __init__(self, doc_id, data, exists=True):
        self.id = doc_id
        self._data = data
        self.exists = exists

    def to_dict(self):
        return dict(self._data) if self._data else {}


class FakeDocRef:
    def __init__(self, collection, doc_id):
        self.collection = collection
        self.id = doc_id

    def get(self):
        return self.collection._docs.get(self.id, FakeDoc(self.id, {}, exists=False))

    def set(self, data, merge=False):
        existing = self.get().to_dict() if merge else {}
        existing.update(data)
        self.collection._docs[self.id] = FakeDoc(self.id, existing, exists=True)


class FakeCollection:
    def __init__(self, name):
        self.name = name
        self._docs = {}

    def document(self, doc_id):
        return FakeDocRef(self, doc_id)

    def doc(self, doc_id):
        return self.document(doc_id)

    def where(self, field, op, value):
        class Query:
            def __init__(self, docs, filter_fn):
                self._docs = docs
                self._filters = [filter_fn]

            def where(self, f, o, v):
                if o == '==':
                    self._filters.append(lambda d: d.get(f) == v)
                return self

            def stream(self):
                for d in self._docs.values():
                    doc_dict = d.to_dict()
                    if all(fn(doc_dict) for fn in self._filters):
                        yield d

        if op == '==':
            return Query(self._docs, lambda d: d.get(field) == value)
        return Query(self._docs, lambda d: True)


class FakeFirestore:
    def __init__(self):
        self._collections = {}

    def collection(self, name):
        if name not in self._collections:
            self._collections[name] = FakeCollection(name)
        return self._collections[name]


@pytest.fixture
def mock_fs(monkeypatch):
    fake = FakeFirestore()
    monkeypatch.setattr(server, '_fs', lambda: fake)
    return fake


@pytest.fixture
def client():
    server.app.config["TESTING"] = True
    return server.app.test_client()


def _unpack(res):
    if isinstance(res, tuple):
        return res[0], res[1]
    return res, res.status_code


def test_patch_user_profile(client, mock_fs, monkeypatch):
    monkeypatch.setattr(server, "_verify_token", lambda: ("test-uid-123", "user@test.vn", "user"))

    with client.application.test_request_context('/api/user/profile', method='PATCH', json={}):
        res, code = _unpack(server.patch_user_profile())
        assert code == 400
        assert "Không có trường thông tin nào" in res.json['error']

    # Using test client with valid profile fields
    with client.application.test_request_context('/api/user/profile', method='PATCH',
                                                json={'name': 'Nguyen Van A', 'dateOfBirth': '1992-04-12'}):
        res, code = _unpack(server.patch_user_profile())
        assert code == 200
        assert res.json['success'] is True
        assert res.json['data']['name'] == 'Nguyen Van A'
        assert res.json['data']['dateOfBirth'] == '1992-04-12'


def test_onboarding_flow(client, mock_fs, monkeypatch):
    uid = "test-onboarding-uid"
    monkeypatch.setattr(server, "_verify_token", lambda: (uid, "onboarding@test.vn", "user"))

    with client.application.test_request_context('/api/user/onboarding', method='GET'):
        # Step 0: Initially empty
        res, code = _unpack(server.get_user_onboarding())
        assert code == 200
        data = res.json['data']
        assert data['isCompleted'] is False
        assert data['profile']['isComplete'] is False
        assert data['vehicle']['hasVehicle'] is False

    # Attempt to complete without name and vehicle -> 400
    with client.application.test_request_context('/api/user/onboarding/complete', method='POST', json={}):
        res, code = _unpack(server.complete_user_onboarding())
        assert code == 400
        assert "họ tên" in res.json['error']

    # Set name
    mock_fs.collection('users').document(uid).set({
        'name': 'Tran Van B',
        'registrationFlowVersion': 2,
    })

    # Attempt to complete without vehicle -> 400
    with client.application.test_request_context('/api/user/onboarding/complete', method='POST', json={}):
        res, code = _unpack(server.complete_user_onboarding())
        assert code == 400
        assert "ít nhất một xe" in res.json['error']

    # Add active vehicle
    mock_fs.collection('Vehicles').document('veh-1').set({
        'vehicleId': 'veh-1',
        'ownerUid': uid,
        'vehicleName': 'VF 8 Plus',
        'isDeleted': False,
        'isArchived': False,
    })

    # Complete onboarding with skipped Shelly
    with client.application.test_request_context('/api/user/onboarding/complete', method='POST',
                                                json={'shellyStatus': 'skipped'}):
        res, code = _unpack(server.complete_user_onboarding())
        assert code == 200
        assert res.json['success'] is True
        assert res.json['data']['shellyOnboardingStatus'] == 'skipped'
        assert res.json['data']['onboardingCompletedAt'] is not None

    # Check onboarding status now reflects completed
    with client.application.test_request_context('/api/user/onboarding', method='GET'):
        res, code = _unpack(server.get_user_onboarding())
        assert code == 200
        assert res.json['data']['isCompleted'] is True
        assert res.json['data']['shelly']['status'] == 'skipped'


def test_registration_bootstrap_is_idempotent(client, mock_fs, monkeypatch):
    """An Auth-created account can recover a failed initial profile write."""
    uid = "bootstrap-uid"
    monkeypatch.setattr(server, "_verify_token", lambda: (uid, "new@test.vn", "user"))

    with client.application.test_request_context(
        '/api/mobile/registration-bootstrap', method='POST',
        json={'name': 'New Owner', 'phone': '0900000000'},
    ):
        res, code = _unpack(server.registration_bootstrap())
        assert code == 200
        assert res.json['data']['isCompleted'] is False

    # Retrying after a network failure must merge instead of resetting the
    # profile or creating a second account record.
    mock_fs.collection('users').document(uid).set(
        {'onboardingCompletedAt': '2026-09-15T00:00:00Z'}, merge=True,
    )
    with client.application.test_request_context(
        '/api/mobile/registration-bootstrap', method='POST', json={},
    ):
        res, code = _unpack(server.registration_bootstrap())
        assert code == 200
        assert res.json['data']['isCompleted'] is True
    saved = mock_fs.collection('users').document(uid).get().to_dict()
    assert saved['email'] == 'new@test.vn'
    assert saved['registrationFlowVersion'] == 2


def test_sync_batch_profile_whitelist(client, mock_fs, monkeypatch):
    uid = "test-sync-uid"
    monkeypatch.setattr(server, "_require_user_or_admin", lambda: (uid, "sync@test.vn"))
    # Call sync_full with malicious forged fields in profile
    body = {
        'profile': {
            'name': 'Good User',
            'accountStatus': 'admin', # Should be stripped
            'role': 'superadmin',      # Should be stripped
            'maxActiveVehicles': 999, # Should be stripped
            'registrationFlowVersion': 99, # Should be stripped
            'onboardingCompletedAt': 'fake-date', # Should be stripped
            'dateOfBirth': '1990-01-01', # Should be kept
        }
    }
    with client.application.test_request_context('/api/web/sync/full', method='POST', json=body):
        captured_writes = []
        original_commit = server.commit_owned_writes
        try:
            server.commit_owned_writes = lambda db, writes, user_id: captured_writes.extend(writes)
            resp = server.sync_full()
            assert resp.status_code == 200
            # Check profile write
            profile_write = [w for w in captured_writes if w[0] == 'users'][0]
            written_data = profile_write[2]
            assert written_data['name'] == 'Good User'
            assert written_data['dateOfBirth'] == '1990-01-01'
            assert 'accountStatus' not in written_data
            assert 'role' not in written_data
            assert 'maxActiveVehicles' not in written_data
            assert 'registrationFlowVersion' not in written_data
            assert 'onboardingCompletedAt' not in written_data
        finally:
            server.commit_owned_writes = original_commit
