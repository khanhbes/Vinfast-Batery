"""Synthetic Firebase-authenticated staging chatbot QA, with scoped cleanup.

Never exports credentials/tokens; never supplies a physical device binding.
"""
import argparse
import json
import logging
import re
import sys
import uuid
import warnings

import requests


def frames(text):
    for block in text.replace('\r\n', '\n').split('\n\n'):
        event = next((line[6:].strip() for line in block.splitlines() if line.startswith('event:')), '')
        data = '\n'.join(line[5:].lstrip() for line in block.splitlines() if line.startswith('data:'))
        if data:
            yield event, json.loads(data)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--credential-file', required=True)
    parser.add_argument('--firebase-web-env', required=True)
    parser.add_argument('--api-url', required=True)
    args = parser.parse_args()
    expected = 'https://vinfast-api.nicestone-4d213368.eastasia.azurecontainerapps.io'
    if args.api_url != expected:
        raise ValueError('unexpectedStagingOrigin')
    logging.disable(logging.CRITICAL)
    warnings.filterwarnings('ignore')
    import firebase_admin
    from firebase_admin import auth, credentials, firestore
    credential = credentials.Certificate(args.credential_file)
    if credential.project_id != 'vinfast-873db':
        raise ValueError('unexpectedProject')
    firebase_admin.initialize_app(credential)
    web_key = None
    with open(args.firebase_web_env, encoding='utf-8-sig') as handle:
        for line in handle:
            match = re.match(r'^\s*VITE_FIREBASE_API_KEY\s*=\s*(.+?)\s*$', line)
            if match:
                web_key = match[1].strip('"\'')
    if not web_key:
        raise ValueError('missingWebConfiguration')
    uid = 'qa-chat-20261006-' + uuid.uuid4().hex[:12]
    session_id = 'qa-public-chat-' + uuid.uuid4().hex
    report = {'scope': 'public Firebase-authenticated staging chatbot', 'physicalDeviceCommands': 0, 'checks': []}
    created = False
    headers = {}
    with requests.Session() as http:
        try:
            auth.create_user(uid=uid, display_name='QA temporary chatbot')
            created = True
            custom = auth.create_custom_token(uid).decode()
            identity = http.post('https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken',
                params={'key': web_key}, json={'token': custom, 'returnSecureToken': True}, timeout=30)
            if identity.status_code != 200:
                raise ValueError('qaSignInFailed')
            token = identity.json()['idToken']
            headers = {'Authorization': 'Bearer ' + token}
            for question in ('Chào BatteryBot. Trả lời một câu ngắn bằng tiếng Việt, không emoji và không gọi công cụ.',
                             'Khi ứng dụng mất mạng, mình nên làm gì? Trả lời ngắn; không gọi công cụ.'):
                response = http.post(expected + '/api/chat/send', headers=headers,
                    json={'sessionId': session_id, 'message': question}, timeout=100)
                check = {'id': 'chat-send', 'httpStatus': response.status_code,
                         'requestIdPresent': bool(response.headers.get('X-Request-Id')), 'pass': False}
                report['checks'].append(check)
                if response.status_code == 200:
                    events = list(frames(response.text))
                    check['eventTypes'] = sorted({event for event, _ in events})
                    end = next((data for event, data in events if event == 'message_end'), {})
                    usage = end.get('usage', {})
                    check.update({key: usage.get(key) for key in ('source', 'providerStatus', 'providerErrorCode', 'providerHttpStatus')})
                    check['pass'] = usage.get('source') == 'gemini' and usage.get('providerStatus') == 'succeeded'
            # Negative policy test only: no action ID, device ID or command supplied.
            guard = http.post(expected + '/api/chat/action/confirm', headers=headers,
                              json={'actionId': 'qa-missing-action', 'confirmed': True}, timeout=30)
            report['checks'].append({'id': 'chat-hardware-policy', 'httpStatus': guard.status_code,
                                     'pass': guard.status_code == 503 and guard.json().get('code') == 'STAGING_HARDWARE_DISABLED'})
        except Exception as error:
            report['failureType'] = type(error).__name__
        finally:
            if headers:
                try:
                    deleted = http.delete(expected + '/api/chat/sessions/' + session_id, headers=headers, timeout=30)
                    report['sessionCleanupStatus'] = deleted.status_code
                except Exception:
                    report['sessionCleanupStatus'] = 'requestFailed'
            if created:
                # Remove only this synthetic account's test-owned Firestore subtree.
                try:
                    db = firestore.client()
                    for path in ('users', 'Users'):
                        db.recursive_delete(db.collection(path).document(uid))
                    auth.delete_user(uid)
                    try:
                        auth.get_user(uid)
                        report['qaAccountAbsent'] = False
                    except auth.UserNotFoundError:
                        report['qaAccountAbsent'] = True
                except Exception as error:
                    report['cleanupFailureType'] = type(error).__name__
                    # Identifier belongs exclusively to this generated QA account.
                    report['cleanupQaUid'] = uid
    report['pass'] = (bool(report['checks']) and all(c['pass'] for c in report['checks'])
                      and 'failureType' not in report and report.get('qaAccountAbsent') is True
                      and report.get('sessionCleanupStatus') in (200, 404))
    print(json.dumps(report))
    return 0 if report['pass'] else 1


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as error:
        print(json.dumps({'pass': False, 'failureType': type(error).__name__}))
        sys.exit(1)
