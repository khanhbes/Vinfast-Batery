import os
import sys
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

os.environ.setdefault('APP_ENV', 'testing')

from server import app
import server


def test_push_token_requires_uuid_and_valid_platform(monkeypatch):
    monkeypatch.setattr(server, '_verify_token', lambda: ('uid-1', 'user@example.com', 'user'))
    client = app.test_client()
    invalid = client.put('/api/mobile/push-tokens/not-a-uuid', json={})
    assert invalid.status_code == 400
    bad_platform = client.put(
        '/api/mobile/push-tokens/123e4567-e89b-12d3-a456-426614174000',
        json={'token': 'fcm', 'platform': 'windows', 'bundleId': 'x', 'appVersion': '1'},
    )
    assert bad_platform.status_code == 400


def test_push_token_upsert_and_revoke_are_server_owned(monkeypatch):
    monkeypatch.setattr(server, '_verify_token', lambda: ('uid-1', 'user@example.com', 'user'))
    monkeypatch.setattr(server, '_firebase_available', False)
    client = app.test_client()
    device = '123e4567-e89b-12d3-a456-426614174000'
    result = client.put(
        f'/api/mobile/push-tokens/{device}',
        json={'token': 'fcm', 'platform': 'ios', 'bundleId': 'com.khanhbes.vinfastbattery', 'appVersion': '1.1.3+113', 'locale': 'vi_VN'},
    )
    assert result.status_code == 200
    assert ('uid-1', device) in server._local_push_tokens
    revoked = client.delete(f'/api/mobile/push-tokens/{device}')
    assert revoked.status_code == 200
    assert ('uid-1', device) not in server._local_push_tokens
