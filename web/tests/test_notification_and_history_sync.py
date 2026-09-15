import os
import sys


WEB_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
if WEB_DIR not in sys.path:
    sys.path.insert(0, WEB_DIR)

import server


class FakeReference:
    def __init__(self, collection, document_id):
        self.collection = collection
        self.id = document_id


class FakeDocument:
    def __init__(self, collection, document_id, data):
        self.id = document_id
        self.reference = FakeReference(collection, document_id)
        self._data = dict(data)

    def to_dict(self):
        return dict(self._data)


class FakeQuery:
    def __init__(self, collection, filters=None, maximum=None, descending=False):
        self.collection = collection
        self.filters = list(filters or [])
        self.maximum = maximum
        self.descending = descending

    def where(self, field, operator, value):
        assert operator == '=='
        return FakeQuery(
            self.collection,
            [*self.filters, (field, value)],
            self.maximum,
            self.descending,
        )

    def order_by(self, _field, direction=None):
        return FakeQuery(
            self.collection,
            self.filters,
            self.maximum,
            direction == 'DESCENDING',
        )

    def limit(self, maximum):
        return FakeQuery(
            self.collection,
            self.filters,
            maximum,
            self.descending,
        )

    def stream(self):
        documents = [
            FakeDocument(self.collection, document_id, data)
            for document_id, data in self.collection.documents.items()
            if all(data.get(field) == value for field, value in self.filters)
        ]
        documents.sort(
            key=lambda document: document.to_dict().get('startTime', ''),
            reverse=self.descending,
        )
        return iter(documents[:self.maximum] if self.maximum else documents)


class FakeCollection:
    def __init__(self):
        self.documents = {}

    def where(self, field, operator, value):
        return FakeQuery(self).where(field, operator, value)


class FakeBatch:
    def __init__(self):
        self.references = []

    def delete(self, reference):
        self.references.append(reference)

    def commit(self):
        for reference in self.references:
            reference.collection.documents.pop(reference.id, None)


class FakeFirestore:
    def __init__(self):
        self.collections = {}

    def collection(self, name):
        return self.collections.setdefault(name, FakeCollection())

    def batch(self):
        return FakeBatch()


def _client(monkeypatch, database, uid='uid-1'):
    monkeypatch.setattr(server, '_fs', lambda: database)
    monkeypatch.setattr(
        server,
        '_verify_token',
        lambda: (uid, f'{uid}@example.com', 'user'),
    )
    server.app.config['TESTING'] = True
    return server.app.test_client()


def test_delete_all_notifications_is_owner_scoped_and_idempotent(monkeypatch):
    database = FakeFirestore()
    notifications = database.collection('UserNotifications').documents
    notifications.update({
        'mine-1': {'userId': 'uid-1'},
        'mine-2': {'userId': 'uid-1'},
        'other': {'userId': 'uid-2'},
    })
    client = _client(monkeypatch, database)

    response = client.delete('/api/mobile/notifications')
    assert response.status_code == 200
    assert response.get_json()['data']['deleted'] == 2
    assert set(notifications) == {'other'}

    repeated = client.delete('/api/mobile/notifications')
    assert repeated.status_code == 200
    assert repeated.get_json()['data']['deleted'] == 0


def test_charge_history_includes_legacy_and_hides_deleted(monkeypatch):
    database = FakeFirestore()
    logs = database.collection('ChargeLogs').documents
    base = {
        'ownerUid': 'uid-1',
        'vehicleId': 'vehicle-1',
        'startBatteryPercent': 20,
        'endBatteryPercent': 60,
        'odoAtCharge': 100,
    }
    logs['legacy'] = {
        **base,
        'startTime': '2026-09-15T08:00:00+00:00',
        'endTime': '2026-09-15T09:00:00+00:00',
    }
    logs['deleted'] = {
        **base,
        'startTime': '2026-09-15T10:00:00+00:00',
        'endTime': '2026-09-15T11:00:00+00:00',
        'isDeleted': True,
    }
    logs['other'] = {
        **base,
        'ownerUid': 'uid-2',
        'startTime': '2026-09-15T12:00:00+00:00',
        'endTime': '2026-09-15T13:00:00+00:00',
    }
    client = _client(monkeypatch, database)

    response = client.get('/api/user/charge-logs?vehicleId=vehicle-1')
    assert response.status_code == 200
    data = response.get_json()['data']
    assert [item['logId'] for item in data] == ['legacy']

