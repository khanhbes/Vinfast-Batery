"""Chat regressions use mock data only; never call Gemini or a relay."""
import json
import os
import pytest
os.environ.setdefault('APP_ENV', 'testing')

from ai_server.chat_engine import ChatEngine
from ai_server.chat_memory import ChatMemoryManager
from ai_server.chat_schemas import ChatSendRequest, VehicleContext, BehaviorProfile
from ai_server.chat_tools import ChatToolDispatcher


def test_memory_isolates_owner_and_refuses_session_takeover():
    memory = ChatMemoryManager()
    sid = memory.get_or_create_session('owned-session', 'account-a')
    memory.add_message(sid, 'user', 'Private question')
    assert len(memory.list_sessions(user_id='account-a')) == 1
    assert memory.list_sessions(user_id='account-b') == []
    with pytest.raises(PermissionError):
        memory.get_or_create_session(sid, 'account-b')
    with pytest.raises(PermissionError):
        memory.assert_owner(sid, 'account-b')


def test_issued_action_binds_owner_session_arguments_and_replay():
    engine = ChatEngine()
    card = engine._create_confirmation_card(
        user_id='account-a', session_id='session-a', tool_name='start_smart_charging',
        args={'vehicle_id': 'vehicle-a', 'target_soc': 80}, vehicle_context={'vehicleId': 'vehicle-a'})
    args = card['args']
    request = dict(call_id=card['callId'], tool_name=card['toolName'], args=args,
                   user_id='account-a', session_id='session-a', confirmed=True)
    assert engine.confirm_action(**{**request, 'user_id': 'account-b'})['code'] == 'actionInvalid'
    assert engine.confirm_action(**{**request, 'args': {**args, 'target_soc': 99}})['code'] == 'actionInvalid'
    result = engine.confirm_action(**request)
    assert result['success'] is False
    assert result['result']['status'] == 'unavailable'
    assert engine.confirm_action(**request) == result


def test_missing_readings_are_not_fabricated_and_zero_is_preserved():
    dispatcher = ChatToolDispatcher()
    result = dispatcher.execute_tool('get_battery_status', {}, {'currentSoc': 0, 'voltage': 0})
    assert result['soc'] == 0 and result['voltage'] == 0
    assert 'estimatedRemainingKm' not in result and 'soh' not in result
    assert ChatEngine()._build_rich_card('get_battery_status', result) is None
    assert dispatcher.execute_tool('get_trip_summary', {})['status'] == 'unavailable'


def test_default_behavior_is_not_presented_as_observed_habit():
    prompt = ChatEngine().build_system_prompt(None, BehaviorProfile(userId='new-account'))
    assert 'Thường sạc lúc: 22h' not in prompt
    assert '18.5 km' not in prompt
    assert VehicleContext().chargingStatus is None


def test_chat_provider_configuration_reaches_ai_container_without_defaults():
    from pathlib import Path
    root = Path(__file__).resolve().parents[1]
    ai_service = (root / 'docker-compose.yml').read_text(encoding='utf-8').split('  api:', 1)[0]
    assert 'GEMINI_API_KEY: ${GEMINI_API_KEY:-}' in ai_service
    assert 'GEMINI_CHAT_MODEL: ${GEMINI_CHAT_MODEL:-}' in ai_service
    for name in ['.env.docker.example', '.env.laptop.example']:
        example = (root / name).read_text(encoding='utf-8')
        assert '\nGEMINI_API_KEY=\n' in example
        assert '\nGEMINI_CHAT_MODEL=\n' in example
    requirements = (root / 'requirements-chat.txt').read_text(encoding='utf-8')
    assert 'google-genai==2.27.0' in requirements
    dockerfile = (root / 'Dockerfile.ai').read_text(encoding='utf-8')
    assert 'from google import genai' in dockerfile
    assert 'ARG AI_RUNTIME_BASE=python:3.11-slim' in dockerfile
    assert 'COPY requirements-chat.txt .' in dockerfile
    assert '-r requirements-chat.txt' in dockerfile
    assert 'COPY assets/vinfast_specs_fallback.json' in dockerfile


def test_input_is_redacted_before_memory_or_model():
    engine = ChatEngine()
    engine._client = None
    list(engine.stream_chat(ChatSendRequest(sessionId='privacy-test', userId='account-a',
         message='email: qa@example.test password: mock-secret')))
    saved = engine.memory.get_all_messages('privacy-test')[0].content
    assert 'qa@example.test' not in saved and 'mock-secret' not in saved


def test_model_cannot_claim_control_success_before_confirmation(monkeypatch):
    from types import SimpleNamespace
    monkeypatch.setattr('ai_server.chat_engine.DEFAULT_MODEL', 'mock-model')
    call = SimpleNamespace(name='start_smart_charging',
                           args={'vehicle_id': 'vehicle-a', 'target_soc': 80}, id='call-a')
    chunk = SimpleNamespace(text='Đã bật sạc thành công', function_calls=[call])
    engine = ChatEngine(memory=ChatMemoryManager())
    engine._client = SimpleNamespace(models=SimpleNamespace(
        generate_content_stream=lambda **kwargs: iter([chunk])))
    events = list(engine.stream_chat(ChatSendRequest(userId='account-a',
        message='Bật sạc', vehicleContext=VehicleContext(vehicleId='vehicle-a'))))
    text = ''.join(e for e in events if e.startswith('event: text_delta'))
    assert 'Đã bật sạc thành công' not in text
    assert 'Chưa bật sạc' in text
    assert engine.memory.get_all_messages(json.loads(events[0].split('data: ')[1])['sessionId'])[-1].content.startswith('Chưa bật sạc')


def test_public_routes_require_auth_and_no_shadow_registration(monkeypatch):
    import server
    monkeypatch.setattr(server, '_verify_token', lambda: (None, None, None))
    client = server.app.test_client()
    for path in ['/api/chat/send', '/api/chat/backup', '/api/chat/feedback', '/api/chat/action/confirm', '/api/behavior/sync']:
        assert client.post(path, json={'userId': 'spoofed'}).status_code == 401
    for path in ['/api/chat/sessions', '/api/chat/history', '/api/behavior/profile', '/api/behavior/suggestions']:
        assert client.get(path + '?userId=spoofed').status_code == 401
    rules = list(server.app.url_map.iter_rules())
    assert len([r for r in rules if r.rule == '/api/chat/send']) == 1


def test_public_chat_uses_verified_uid_and_closes_failed_upstream(monkeypatch):
    import server
    from unittest.mock import Mock
    monkeypatch.setattr(server, '_verify_token', lambda: ('account-a', None, 'user'))
    upstream = Mock(status_code=503)
    transport = Mock()
    transport.post.return_value = upstream
    monkeypatch.setattr(server, '_http', transport)
    response = server.app.test_client().post('/api/chat/send', json={
        'message': 'Help', 'userId': 'account-b', 'model': 'client-model',
        'behaviorProfile': {'userId': 'account-b'}})
    assert response.status_code == 503
    forwarded = transport.post.call_args.kwargs['json']
    assert forwarded['userId'] == 'account-a'
    assert forwarded['behaviorProfile']['userId'] == 'account-a'
    assert 'model' not in forwarded
    upstream.close.assert_called_once()


@pytest.mark.parametrize('value', [float('nan'), float('inf'), -1, 101])
def test_context_rejects_invalid_soc(value):
    with pytest.raises(ValueError):
        VehicleContext(currentSoc=value)


@pytest.mark.parametrize('path', ['/api/chat/send', '/api/chat/feedback',
    '/api/chat/backup', '/api/chat/action/confirm', '/api/behavior/sync'])
def test_chat_routes_reject_non_object_body_without_internal_errors(monkeypatch, path):
    import server
    monkeypatch.setattr(server, '_verify_token', lambda: ('qa-a', None, 'user'))
    response = server.app.test_client().post(path, json=['invalid'])
    assert response.status_code == 400
    assert response.json['success'] is False
    assert 'Traceback' not in response.get_data(as_text=True)


def test_behavior_sync_hides_upstream_failure_and_rejects_invalid_profile(monkeypatch):
    import server
    monkeypatch.setattr(server, '_verify_token', lambda: ('qa-a', None, 'user'))
    def fail(*args, **kwargs):
        raise RuntimeError('private-host credential-content')
    monkeypatch.setattr(server, '_ai_request_json', fail)
    client = server.app.test_client()
    assert client.post('/api/behavior/sync', json={'profile': 'bad'}).status_code == 400
    response = client.post('/api/behavior/sync', json={'profile': {}})
    assert response.status_code == 503
    assert 'private-host' not in response.get_data(as_text=True)


def test_feedback_aliases_retry_and_reversal_contribute_one_vote():
    from ai_server.behavior_analyzer import BehaviorAnalyzer
    memory = ChatMemoryManager()
    analyzer = BehaviorAnalyzer()
    sid = memory.get_or_create_session('feedback-test', 'qa-a')
    msg = memory.add_message(sid, 'model', 'QA response')
    def vote(rating):
        return memory.set_feedback(sid, 'qa-a', msg.id, rating,
            on_change=lambda old, new: analyzer.replace_feedback('qa-a', old, new))
    assert vote('up') is True
    assert vote('like') is False
    assert vote('down') is True
    assert vote('dislike') is False
    stats = analyzer.get_or_create_profile('qa-a').chatPreferences.feedbackStats
    assert stats['totalThumbsUp'] == 0 and stats['totalThumbsDown'] == 1


def test_concurrent_feedback_updates_keep_a_single_vote():
    from concurrent.futures import ThreadPoolExecutor
    from ai_server.behavior_analyzer import BehaviorAnalyzer
    memory, analyzer = ChatMemoryManager(), BehaviorAnalyzer()
    sid = memory.get_or_create_session('concurrent-feedback', 'qa-a')
    message = memory.add_message(sid, 'model', 'QA reply')
    def vote(rating):
        memory.set_feedback(sid, 'qa-a', message.id, rating,
            on_change=lambda old, new: analyzer.replace_feedback('qa-a', old, new))
    with ThreadPoolExecutor(max_workers=4) as pool:
        list(pool.map(vote, ['like', 'down', 'up', 'dislike'] * 20))
    stats = analyzer.get_or_create_profile('qa-a').chatPreferences.feedbackStats
    assert stats['totalThumbsUp'] + stats['totalThumbsDown'] == 1
    assert stats['totalThumbsUp'] >= 0 and stats['totalThumbsDown'] >= 0


@pytest.mark.parametrize('recreate', [False, True])
def test_late_stream_cannot_restore_deleted_session_or_write_new_epoch(recreate):
    memory = ChatMemoryManager()
    engine = ChatEngine(memory=memory)
    engine._client = None
    stream = engine.stream_chat(ChatSendRequest(sessionId='deleted-qa', userId='qa-a', message='Chào bạn'))
    next(stream)
    with pytest.raises(PermissionError):
        memory.delete_session('deleted-qa', owner_uid='qa-b', check_owner=True)
    memory.delete_session('deleted-qa', owner_uid='qa-a', check_owner=True)
    if recreate:
        memory.get_or_create_session('deleted-qa', 'qa-a')
    with pytest.raises(PermissionError):
        list(stream)
    assert memory.get_all_messages('deleted-qa') == []


def test_deleted_session_invalidates_issued_control_confirmation():
    memory = ChatMemoryManager()
    engine = ChatEngine(memory=memory)
    card = engine._create_confirmation_card(user_id='qa-a', session_id='cancelled-card',
        tool_name='start_smart_charging', args={'vehicle_id': 'qa-vehicle'},
        vehicle_context={'vehicleId': 'qa-vehicle'})
    memory.delete_session('cancelled-card', owner_uid='qa-a', check_owner=True)
    memory.get_or_create_session('cancelled-card', 'qa-a')
    result = engine.confirm_action(card['callId'], card['toolName'], card['args'],
        user_id='qa-a', session_id='cancelled-card')
    assert result['success'] is False and result['code'] == 'actionInvalid'


@pytest.mark.parametrize('recreate', [False, True])
def test_late_control_stream_cannot_recreate_deleted_session(recreate):
    memory = ChatMemoryManager()
    engine = ChatEngine(memory=memory)
    engine._client = None
    stream = engine.stream_chat(ChatSendRequest(sessionId='deleted-control', userId='qa-a',
        message='Bật sạc', vehicleContext=VehicleContext(vehicleId='qa-vehicle')))
    next(stream)
    memory.delete_session('deleted-control', owner_uid='qa-a', check_owner=True)
    if recreate:
        memory.get_or_create_session('deleted-control', 'qa-a')
    with pytest.raises(PermissionError):
        list(stream)
    assert memory.get_all_messages('deleted-control') == []
    assert engine._pending_actions == {}


@pytest.mark.parametrize('http_status,expected_code', [
    (400, 'providerUnavailable'), (401, 'providerAuthRejected'),
    (403, 'providerAuthRejected'), (404, 'providerModelUnavailable'),
    (429, 'providerRateLimited'), (500, 'providerUnavailable'),
])
def test_provider_failure_metadata_never_claims_gemini_success(monkeypatch, http_status, expected_code):
    from types import SimpleNamespace
    monkeypatch.setattr('ai_server.chat_engine.DEFAULT_MODEL', 'mock-model')
    class ProviderError(Exception):
        code = http_status
    def fail(**kwargs):
        raise ProviderError('credential/private-host content must never reach metadata')
    engine = ChatEngine(memory=ChatMemoryManager())
    engine._client = SimpleNamespace(models=SimpleNamespace(generate_content_stream=fail))
    frames = list(engine.stream_chat(ChatSendRequest(userId='qa-metadata', message='Chào bạn')))
    usage = json.loads(frames[-1].split('data: ')[1])['usage']
    assert usage['source'] == usage['model'] == 'offline-guidance'
    assert usage['providerStatus'] == 'failed'
    assert usage['providerErrorCode'] == expected_code
    assert usage['providerHttpStatus'] == http_status
    assert 'private-host' not in json.dumps(usage)


@pytest.mark.parametrize('scenario', ['success', 'empty', 'timeout', 'notConfigured'])
def test_provider_origin_metadata_tracks_real_outcome(monkeypatch, scenario):
    from types import SimpleNamespace
    monkeypatch.setattr('ai_server.chat_engine.DEFAULT_MODEL', 'mock-model')
    def generate(**kwargs):
        if scenario == 'timeout':
            raise TimeoutError('private details')
        return iter([SimpleNamespace(text='Xin chào bạn.' if scenario == 'success' else '', function_calls=[])])
    engine = ChatEngine(memory=ChatMemoryManager())
    engine._client = None if scenario == 'notConfigured' else SimpleNamespace(
        models=SimpleNamespace(generate_content_stream=generate))
    frames = list(engine.stream_chat(ChatSendRequest(userId='qa-metadata', message='Chào bạn')))
    usage = json.loads(frames[-1].split('data: ')[1])['usage']
    if scenario == 'success':
        assert usage['source'] == 'gemini' and usage['model'] == 'mock-model'
        assert usage['providerStatus'] == 'succeeded' and usage['providerErrorCode'] is None
    else:
        assert usage['source'] == usage['model'] == 'offline-guidance'
        expected = {'empty': 'providerEmptyResponse', 'timeout': 'providerTimeout',
                    'notConfigured': 'providerNotConfigured'}
        assert usage['providerErrorCode'] == expected[scenario]
        assert usage['providerStatus'] == ('unavailable' if scenario == 'notConfigured' else 'failed')
