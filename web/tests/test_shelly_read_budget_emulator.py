"""Firestore read budget for polling (Task108). Emulator only; never production."""
import base64
import os
import uuid
from copy import deepcopy
from unittest.mock import Mock

import pytest
from flask import Flask
from google.auth.credentials import AnonymousCredentials
from google.cloud import firestore
from google.cloud.firestore_v1 import collection as fs_collection
from google.cloud.firestore_v1 import document as fs_document
from google.cloud.firestore_v1 import query as fs_query

from shelly.connection_codes import ConnectionCodeStore
from shelly.providers.vault_cloud import VaultCloudControlProvider
from shelly.repositories import SmartChargeRepository
from shelly.service import SmartChargeService

pytestmark = pytest.mark.skipif(
    not os.environ.get('FIRESTORE_EMULATOR_HOST'), reason='Requires isolated Firestore Emulator',
)


class ReadCounter:
    """Counts billed document reads: one per returned doc, one for an empty query."""

    def __init__(self, monkeypatch):
        self.reads = 0
        original_get = fs_document.DocumentReference.get
        counter = self

        def counted_get(ref, *args, **kwargs):
            counter.reads += 1
            return original_get(ref, *args, **kwargs)

        def wrap_stream(original):
            def counted_stream(self_, *args, **kwargs):
                count = 0
                for item in original(self_, *args, **kwargs):
                    count += 1
                    yield item
                counter.reads += max(1, count)
            return counted_stream

        monkeypatch.setattr(fs_document.DocumentReference, "get", counted_get)
        monkeypatch.setattr(fs_query.Query, "stream", wrap_stream(fs_query.Query.stream))
        monkeypatch.setattr(fs_collection.CollectionReference, "stream",
                            wrap_stream(fs_collection.CollectionReference.stream))


def device_snapshot(device_id):
    return {"id": device_id, "code": "S3PL-00112EU", "gen": "G2", "type": "relay", "online": 1,
            "settings": {"switch:0": {"initial_state": "off", "auto_on": False, "auto_off": False}},
            "status": {"switch:0": {"output": False, "apower": 0, "voltage": 230,
                                    "current": 0, "aenergy": {"total": 0}}}}


@pytest.fixture
def live_service(monkeypatch):
    host = os.environ['FIRESTORE_EMULATOR_HOST'].split(':')[0]
    assert host in ('localhost', '127.0.0.1'), 'Refuse non-local emulator'
    monkeypatch.delenv("AZURE_STAGING_HARDWARE_DISABLED", raising=False)
    monkeypatch.setenv('SHELLY_PROFILE_MASTER_KEY', base64.urlsafe_b64encode(b'r' * 32).decode())
    db = firestore.Client(project='vinfast-rules-test', credentials=AnonymousCredentials())
    uid, vehicle = 'budget-' + uuid.uuid4().hex, 'veh-' + uuid.uuid4().hex
    device = 'b' + uuid.uuid4().hex[:11]
    scope = 'budget-' + uuid.uuid4().hex
    db.collection('Vehicles').document(vehicle).set({'ownerUid': uid})
    code = ConnectionCodeStore(db).generate(device_id=device, device_name='Budget plug', model='S3PL-00112EU',
        cloud_host='https://shelly.cloud', cloud_auth_key='test-only', created_by='test-admin')
    repo = SmartChargeRepository(db, worker_scope=scope)
    repo.enroll_connection_code(uid, code, 'op-budget', vehicle_id=vehicle)
    worker = SmartChargeRepository(db, worker_scope=scope)
    worker.claim_worker_lease('budget-worker')
    worker.publish_worker_heartbeat('budget-worker', healthy=True)
    http = Mock()

    def post(url, **kwargs):
        response = Mock(status_code=200)
        response.json.return_value = [deepcopy(device_snapshot(device))]
        return response

    http.post.side_effect = post
    provider = VaultCloudControlProvider(repo, session=http)
    service = SmartChargeService(repo, provider, lambda _: {})
    yield service, uid, vehicle, http
    db.close()


def test_warm_idle_live_poll_stays_within_read_budget(live_service, monkeypatch):
    service, uid, vehicle, http = live_service
    first = service.live(uid, vehicle)  # cold: fills profile/docs/status/capabilities caches
    assert first["status"]["online"] is True and first["capabilities"] is not None
    counter = ReadCounter(monkeypatch)
    cloud_calls = http.post.call_count
    # Production polls are HTTP requests: the shellyDevices read is memoised
    # per request, never across requests or processes.
    with Flask(__name__).test_request_context('/api/smart-charging/live'):
        second = service.live(uid, vehicle)
    assert second["status"]["relay"] is False
    print(f"warm idle live reads={counter.reads}")
    # Measured budget for a warm idle poll: binding/session/membership only.
    assert counter.reads <= 6, counter.reads
    # Idle status is reused within its TTL: no extra Shelly Cloud request.
    assert http.post.call_count == cloud_calls


def test_internal_status_reads_write_no_restore_audit(live_service):
    service, uid, vehicle, _ = live_service
    for _ in range(3):
        service.live(uid, vehicle)
    audits = service.repository.db.collection('smartChargingAudit').where('uid', '==', uid).stream()
    events = [doc.to_dict().get('event') for doc in audits]
    assert 'shelly_profile_restored' not in events
