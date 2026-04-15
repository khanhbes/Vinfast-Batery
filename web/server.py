"""
VinFast Battery — Unified API Server
Hợp nhất Data + AI + Admin vào 1 service duy nhất.
Firebase Auth middleware + RBAC (user/admin).

Port: 5000
"""
import os
import io
import csv
import uuid
import json
import math
import random
import functools
import glob
import numpy as np
from datetime import datetime, timedelta, timezone
from flask import Flask, request, jsonify, Response, redirect
from flask_cors import CORS
from werkzeug.exceptions import HTTPException

try:
    import joblib
except Exception:
    joblib = None

try:
    import pandas as pd
except Exception:
    pd = None

# ═══════════════════════════════════════════════════════════════
# FIREBASE ADMIN SDK
# ═══════════════════════════════════════════════════════════════
_firebase_available = False
_firestore_db = None
_firebase_auth = None
_allow_demo_data = os.environ.get('ALLOW_DEMO_DATA', '0').lower() in ('1', 'true', 'yes')

def _find_service_account_path() -> str | None:
    """
    Tìm file service-account hợp lệ theo thứ tự ưu tiên:
    1) GOOGLE_APPLICATION_CREDENTIALS
    2) Các tên file phổ biến trong thư mục project
    """
    root = os.path.dirname(os.path.abspath(__file__))
    env_path = os.environ.get('GOOGLE_APPLICATION_CREDENTIALS', '').strip()
    candidates = []
    if env_path:
        candidates.append(env_path)
    for name in (
        'serviceAccountKey.json',
        'service-account-key.json',
        'firebase-adminsdk.json',
        'firebase-service-account.json',
    ):
        candidates.append(os.path.join(root, name))
        candidates.append(os.path.join(root, 'secrets', name))

    for path in candidates:
        if path and os.path.isfile(path):
            return path

    # Fallback: tìm theo pattern phổ biến (ví dụ file tải từ Firebase Console)
    patterns = (
        os.path.join(root, '*firebase-adminsdk*.json'),
        os.path.join(root, '*service*account*.json'),
        os.path.join(root, 'secrets', '*firebase-adminsdk*.json'),
        os.path.join(root, 'secrets', '*service*account*.json'),
    )
    for pattern in patterns:
        matches = sorted(glob.glob(pattern))
        if matches:
            return matches[0]
    return None

try:
    import firebase_admin
    from firebase_admin import credentials, firestore, auth as fb_auth
    cred_path = _find_service_account_path()
    if cred_path:
        cred = credentials.Certificate(cred_path)
        firebase_admin.initialize_app(cred)
        os.environ['GOOGLE_APPLICATION_CREDENTIALS'] = cred_path
        print(f'✅ Firebase Admin SDK initialized with service account: {cred_path}')
    else:
        firebase_admin.initialize_app()
        print('✅ Firebase Admin SDK initialized with Application Default Credentials')
    _firestore_db = firestore.client()
    _firebase_auth = fb_auth
    _firebase_available = True
except Exception as e:
    print(f'⚠ Firebase Admin SDK not available: {e}')
    print('  → Sử dụng in-memory fallback')
    print('  → Để dùng Firestore thật: đặt file key (ví dụ "serviceAccountKey.json" hoặc "*firebase-adminsdk*.json") cạnh server.py')
    print('    hoặc set biến môi trường GOOGLE_APPLICATION_CREDENTIALS trỏ tới file key')

# ═══════════════════════════════════════════════════════════════
# FLASK APP
# ═══════════════════════════════════════════════════════════════
app = Flask(__name__)
CORS(app)
app.secret_key = os.urandom(24)


@app.route('/', methods=['GET'])
@app.route('/dashboard', methods=['GET'])
def open_dashboard():
    """Redirect root URL to React Admin Portal."""
    dashboard_url = os.environ.get('DASHBOARD_URL', 'http://localhost:3000')
    return redirect(dashboard_url, code=302)

def _parse_admin_emails(raw: str) -> set[str]:
    return {
        e.strip().lower()
        for e in (raw or '').split(',')
        if e.strip()
    }


# Admin email allowlist
# - Có thể truyền nhiều email bằng dấu phẩy
# - Hỗ trợ wildcard "*" cho môi trường local/dev
ADMIN_EMAILS = _parse_admin_emails(os.environ.get('ADMIN_EMAILS', 'admin@vinfast.local'))

# In-memory fallback stores
_local_profiles: dict = {}
_local_audit: list = []


# ═══════════════════════════════════════════════════════════════
# AUTH MIDDLEWARE
# ═══════════════════════════════════════════════════════════════
def _verify_token():
    """
    Verify Firebase ID token từ Authorization header.
    Trả (uid, email, role) hoặc (None, None, None) nếu không xác thực được.
    """
    auth_header = request.headers.get('Authorization', '')
    if not auth_header.startswith('Bearer '):
        return None, None, None

    token = auth_header[7:]
    if not _firebase_available or not _firebase_auth:
        return None, None, None

    try:
        decoded = _firebase_auth.verify_id_token(token)
        uid = decoded.get('uid', '')
        email = decoded.get('email', '')
        email_norm = (email or '').strip().lower()
        allow_all_admin = '*' in ADMIN_EMAILS
        # Admin check: custom claim hoặc allowlist email
        role = 'admin' if (
            decoded.get('admin') is True or allow_all_admin or email_norm in ADMIN_EMAILS
        ) else 'user'
        return uid, email, role
    except Exception:
        return None, None, None


def require_auth(f):
    """Decorator: yêu cầu đăng nhập."""
    @functools.wraps(f)
    def decorated(*args, **kwargs):
        uid, email, role = _verify_token()
        if not uid:
            return jsonify({'success': False, 'error': 'Unauthorized — cần đăng nhập'}), 401
        request._uid = uid
        request._email = email
        request._role = role
        return f(*args, **kwargs)
    return decorated


def require_admin(f):
    """Decorator: yêu cầu quyền admin."""
    @functools.wraps(f)
    def decorated(*args, **kwargs):
        uid, email, role = _verify_token()
        if not uid:
            return jsonify({'success': False, 'error': 'Unauthorized'}), 401
        if role != 'admin':
            return jsonify({'success': False, 'error': 'Forbidden — cần quyền admin'}), 403
        request._uid = uid
        request._email = email
        request._role = role
        return f(*args, **kwargs)
    return decorated


# ═══════════════════════════════════════════════════════════════
# AUDIT LOG HELPER
# ═══════════════════════════════════════════════════════════════
def _audit(action: str, entity: str, entity_id: str, actor_uid: str,
           actor_email: str = '', details: dict = None):
    entry = {
        'id': str(uuid.uuid4()),
        'action': action,
        'entity': entity,
        'entityId': entity_id,
        'actorUid': actor_uid,
        'actorEmail': actor_email,
        'details': details or {},
        'timestamp': datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z'),
    }
    if _firebase_available and _firestore_db:
        _firestore_db.collection('AuditLogs').add(entry)
    else:
        _local_audit.append(entry)


# ═══════════════════════════════════════════════════════════════
# FIRESTORE HELPERS
# ═══════════════════════════════════════════════════════════════
ENTITIES = {
    'vehicles': 'Vehicles',
    'charge-logs': 'ChargeLogs',
    'charge-samples': 'ChargeSamples',
    'trip-logs': 'TripLogs',
    'maintenance': 'MaintenanceTasks',
    'telemetry': 'TelemetryPoints',
}


def _fs():
    """Get Firestore client hoặc None."""
    return _firestore_db


def _utcnow():
    return datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')


def _hard_delete_collection(col_name: str, batch_size: int = 300) -> int:
    """Hard-delete toàn bộ document trong 1 collection."""
    deleted = 0
    if not _fs():
        return 0
    while True:
        docs = list(_fs().collection(col_name).limit(batch_size).stream())
        if not docs:
            break
        batch = _fs().batch()
        for doc in docs:
            batch.delete(doc.reference)
        batch.commit()
        deleted += len(docs)
        if len(docs) < batch_size:
            break
    return deleted


def _ensure_schema(data: dict, entity: str) -> dict:
    """Bổ sung các field chuẩn hóa nếu thiếu."""
    now = _utcnow()
    data.setdefault('createdAt', now)
    data['updatedAt'] = now
    data.setdefault('isDeleted', False)
    data.setdefault('deletedAt', None)
    data.setdefault('deletedBy', None)
    return data


# ═══════════════════════════════════════════════════════════════
# HEALTH CHECK
# ═══════════════════════════════════════════════════════════════
@app.route('/api/health', methods=['GET'])
def health_check():
    return jsonify({
        'status': 'ok',
        'service': 'VinFast Battery — Unified API',
        'version': '4.0',
        'firebaseConnected': _firebase_available,
        'endpoints': [
            'GET  /api/health',
            'POST /api/auth/set-admin',
            'GET  /api/user/vehicles',
            'CRUD /api/admin/...',
            'POST /api/ai/predict-degradation',
            'POST /api/ai/analyze-patterns',
            'POST /api/ai/train-vehicle-profile',
            'GET  /api/ai/profile-status/<vehicleId>',
        ],
    })


# ═══════════════════════════════════════════════════════════════
# AUTH ENDPOINTS
# ═══════════════════════════════════════════════════════════════
@app.route('/api/auth/me', methods=['GET'])
@require_auth
def auth_me():
    """Thông tin user hiện tại."""
    return jsonify({
        'success': True,
        'data': {
            'uid': request._uid,
            'email': request._email,
            'role': request._role,
        },
    })


@app.route('/api/auth/set-admin', methods=['POST'])
@require_admin
def set_admin():
    """Cấp quyền admin cho email (chỉ admin gọi được)."""
    data = request.get_json() or {}
    target_email = data.get('email', '').strip().lower()
    if not target_email:
        return jsonify({'success': False, 'error': 'email là bắt buộc'}), 400

    if _firebase_available and _firebase_auth:
        try:
            user = _firebase_auth.get_user_by_email(target_email)
            _firebase_auth.set_custom_user_claims(user.uid, {'admin': True})
            ADMIN_EMAILS.add(target_email)
            _audit('set_admin', 'User', user.uid, request._uid, request._email,
                   {'targetEmail': target_email})
            return jsonify({'success': True, 'message': f'{target_email} → admin'})
        except Exception as e:
            return jsonify({'success': False, 'error': str(e)}), 400

    ADMIN_EMAILS.add(target_email)
    return jsonify({'success': True, 'message': f'{target_email} → admin (local)'})


# ═══════════════════════════════════════════════════════════════
# USER DATA APIs — scoped by ownerUid
# ═══════════════════════════════════════════════════════════════
@app.route('/api/user/vehicles', methods=['GET'])
@require_auth
def user_vehicles():
    """Lấy danh sách xe của user hiện tại."""
    uid = request._uid
    if not _fs():
        return jsonify({'success': True, 'data': []})
    docs = _fs().collection('Vehicles') \
        .where('ownerUid', '==', uid) \
        .where('isDeleted', '==', False) \
        .stream()
    vehicles = []
    for doc in docs:
        d = doc.to_dict()
        d['vehicleId'] = doc.id
        vehicles.append(d)
    return jsonify({'success': True, 'data': vehicles})


@app.route('/api/user/vehicles', methods=['POST'])
@require_auth
def user_add_vehicle():
    """User tạo xe mới — tự gắn ownerUid."""
    data = request.get_json() or {}
    uid = request._uid
    data['ownerUid'] = uid
    data = _ensure_schema(data, 'vehicles')

    if _fs():
        vid = data.pop('vehicleId', None) or str(uuid.uuid4())
        _fs().collection('Vehicles').document(vid).set(data)
        data['vehicleId'] = vid
        _audit('create', 'Vehicles', vid, uid, request._email)
    return jsonify({'success': True, 'data': data}), 201


@app.route('/api/user/charge-logs', methods=['GET'])
@require_auth
def user_charge_logs():
    uid = request._uid
    vehicle_id = request.args.get('vehicleId', '')
    if not _fs():
        return jsonify({'success': True, 'data': []})

    q = _fs().collection('ChargeLogs') \
        .where('ownerUid', '==', uid) \
        .where('isDeleted', '==', False)
    if vehicle_id:
        q = q.where('vehicleId', '==', vehicle_id)
    docs = q.order_by('startTime', direction='DESCENDING').stream()
    logs = []
    for doc in docs:
        d = doc.to_dict()
        d['logId'] = doc.id
        logs.append(d)
    return jsonify({'success': True, 'data': logs})


@app.route('/api/user/trip-logs', methods=['GET'])
@require_auth
def user_trip_logs():
    uid = request._uid
    vehicle_id = request.args.get('vehicleId', '')
    if not _fs():
        return jsonify({'success': True, 'data': []})

    q = _fs().collection('TripLogs') \
        .where('ownerUid', '==', uid) \
        .where('isDeleted', '==', False)
    if vehicle_id:
        q = q.where('vehicleId', '==', vehicle_id)
    docs = q.order_by('startTime', direction='DESCENDING').stream()
    logs = [{'tripId': doc.id, **doc.to_dict()} for doc in docs]
    return jsonify({'success': True, 'data': logs})


@app.route('/api/user/maintenance', methods=['GET'])
@require_auth
def user_maintenance():
    uid = request._uid
    vehicle_id = request.args.get('vehicleId', '')
    if not _fs():
        return jsonify({'success': True, 'data': []})

    q = _fs().collection('MaintenanceTasks') \
        .where('ownerUid', '==', uid) \
        .where('isDeleted', '==', False)
    if vehicle_id:
        q = q.where('vehicleId', '==', vehicle_id)
    docs = q.stream()
    tasks = [{'taskId': doc.id, **doc.to_dict()} for doc in docs]
    return jsonify({'success': True, 'data': tasks})


# ═══════════════════════════════════════════════════════════════
# ADMIN CRUD APIs — toàn quyền trên mọi user data
# ═══════════════════════════════════════════════════════════════

# ── List all with filters ──
@app.route('/api/admin/<entity>', methods=['GET'])
@require_admin
def admin_list(entity):
    col_name = ENTITIES.get(entity)
    if not col_name:
        return jsonify({'success': False, 'error': f'Entity không hợp lệ: {entity}'}), 400
    if not _fs():
        return jsonify({'success': True, 'data': []})

    q = _fs().collection(col_name)
    # Optional filters
    owner = request.args.get('ownerUid')
    vehicle = request.args.get('vehicleId')
    include_deleted = request.args.get('includeDeleted', 'false') == 'true'

    if owner:
        q = q.where('ownerUid', '==', owner)
    if vehicle:
        q = q.where('vehicleId', '==', vehicle)
    if not include_deleted:
        q = q.where('isDeleted', '==', False)

    docs = q.stream()
    items = []
    for doc in docs:
        d = doc.to_dict()
        d['_id'] = doc.id
        items.append(d)
    return jsonify({'success': True, 'data': items, 'total': len(items)})


# ── Get single ──
@app.route('/api/admin/<entity>/<doc_id>', methods=['GET'])
@require_admin
def admin_get(entity, doc_id):
    col_name = ENTITIES.get(entity)
    if not col_name:
        return jsonify({'success': False, 'error': f'Entity không hợp lệ'}), 400
    if not _fs():
        return jsonify({'success': False, 'error': 'Firestore unavailable'}), 503

    doc = _fs().collection(col_name).document(doc_id).get()
    if not doc.exists:
        return jsonify({'success': False, 'error': 'Không tìm thấy'}), 404
    d = doc.to_dict()
    d['_id'] = doc.id
    return jsonify({'success': True, 'data': d})


# ── Create ──
@app.route('/api/admin/<entity>', methods=['POST'])
@require_admin
def admin_create(entity):
    col_name = ENTITIES.get(entity)
    if not col_name:
        return jsonify({'success': False, 'error': f'Entity không hợp lệ'}), 400

    data = request.get_json() or {}
    data = _ensure_schema(data, entity)

    if not _fs():
        return jsonify({'success': False, 'error': 'Firestore unavailable'}), 503

    doc_id = data.pop('_id', None) or str(uuid.uuid4())
    _fs().collection(col_name).document(doc_id).set(data)
    _audit('admin_create', col_name, doc_id, request._uid, request._email)
    data['_id'] = doc_id
    return jsonify({'success': True, 'data': data}), 201


# ── Update ──
@app.route('/api/admin/<entity>/<doc_id>', methods=['PUT'])
@require_admin
def admin_update(entity, doc_id):
    col_name = ENTITIES.get(entity)
    if not col_name:
        return jsonify({'success': False, 'error': f'Entity không hợp lệ'}), 400

    data = request.get_json() or {}
    data['updatedAt'] = _utcnow()
    data.pop('_id', None)

    if not _fs():
        return jsonify({'success': False, 'error': 'Firestore unavailable'}), 503

    _fs().collection(col_name).document(doc_id).update(data)
    _audit('admin_update', col_name, doc_id, request._uid, request._email,
           {'fields': list(data.keys())})
    return jsonify({'success': True, 'message': 'Cập nhật thành công'})


# ── Soft Delete ──
@app.route('/api/admin/<entity>/<doc_id>', methods=['DELETE'])
@require_admin
def admin_delete(entity, doc_id):
    col_name = ENTITIES.get(entity)
    if not col_name:
        return jsonify({'success': False, 'error': f'Entity không hợp lệ'}), 400
    if not _fs():
        return jsonify({'success': False, 'error': 'Firestore unavailable'}), 503

    _fs().collection(col_name).document(doc_id).update({
        'isDeleted': True,
        'deletedAt': _utcnow(),
        'deletedBy': request._uid,
        'updatedAt': _utcnow(),
    })
    _audit('admin_soft_delete', col_name, doc_id, request._uid, request._email)
    return jsonify({'success': True, 'message': 'Đã xóa mềm'})


# ── Restore ──
@app.route('/api/admin/<entity>/<doc_id>/restore', methods=['POST'])
@require_admin
def admin_restore(entity, doc_id):
    col_name = ENTITIES.get(entity)
    if not col_name:
        return jsonify({'success': False, 'error': f'Entity không hợp lệ'}), 400
    if not _fs():
        return jsonify({'success': False, 'error': 'Firestore unavailable'}), 503

    _fs().collection(col_name).document(doc_id).update({
        'isDeleted': False,
        'deletedAt': None,
        'deletedBy': None,
        'updatedAt': _utcnow(),
    })
    _audit('admin_restore', col_name, doc_id, request._uid, request._email)
    return jsonify({'success': True, 'message': 'Đã khôi phục'})


# ── Bulk Delete ──
@app.route('/api/admin/<entity>/bulk-delete', methods=['POST'])
@require_admin
def admin_bulk_delete(entity):
    col_name = ENTITIES.get(entity)
    if not col_name:
        return jsonify({'success': False, 'error': f'Entity không hợp lệ'}), 400
    if not _fs():
        return jsonify({'success': False, 'error': 'Firestore unavailable'}), 503

    ids = (request.get_json() or {}).get('ids', [])
    batch = _fs().batch()
    for did in ids:
        ref = _fs().collection(col_name).document(did)
        batch.update(ref, {
            'isDeleted': True, 'deletedAt': _utcnow(), 'deletedBy': request._uid,
        })
    batch.commit()
    _audit('admin_bulk_delete', col_name, ','.join(ids), request._uid, request._email,
           {'count': len(ids)})
    return jsonify({'success': True, 'message': f'Đã xóa mềm {len(ids)} bản ghi'})


# ── Audit Log ──
@app.route('/api/admin/audit-logs', methods=['GET'])
@require_admin
def admin_audit_logs():
    if _fs():
        docs = _fs().collection('AuditLogs') \
            .order_by('timestamp', direction='DESCENDING') \
            .limit(200).stream()
        logs = [{'_id': d.id, **d.to_dict()} for d in docs]
    else:
        logs = sorted(_local_audit, key=lambda x: x['timestamp'], reverse=True)[:200]
    return jsonify({'success': True, 'data': logs})


@app.route('/api/admin/reset-all', methods=['POST'])
@require_admin
def admin_reset_all_data():
    """Xóa toàn bộ dữ liệu nghiệp vụ cũ để làm sạch hệ thống."""
    force = (request.args.get('force', 'false') or '').lower() == 'true'
    if not force:
        return jsonify({
            'success': False,
            'error': 'Thiếu xác nhận force=true để reset toàn bộ dữ liệu',
        }), 400

    targets = ['Vehicles', 'ChargeLogs', 'ChargeSamples', 'TripLogs', 'MaintenanceTasks', 'TelemetryPoints']

    # Firestore mode
    if _fs():
        summary = {}
        for col in targets:
            summary[col] = _hard_delete_collection(col)

        # Dọn AI profile collections (nếu có)
        summary['AIProfiles'] = _hard_delete_collection('AIProfiles')
        summary['AiVehicleProfiles'] = _hard_delete_collection('AiVehicleProfiles')

        _audit(
            'admin_reset_all',
            'system',
            'all_collections',
            request._uid,
            request._email,
            {'deleted': summary},
        )
        return jsonify({'success': True, 'message': 'Đã xóa toàn bộ dữ liệu', 'data': summary})

    # In-memory fallback mode
    _telemetry_seed.clear()
    _local_profiles.clear()
    _local_audit.clear()
    return jsonify({
        'success': True,
        'message': 'Đã reset dữ liệu in-memory fallback',
        'data': {'mode': 'in-memory'},
    })


# ── Users list (Firebase Auth) ──
@app.route('/api/admin/users', methods=['GET'])
@require_admin
def admin_users():
    if not _firebase_available or not _firebase_auth:
        return jsonify({'success': True, 'data': []})
    users = []
    page = _firebase_auth.list_users()
    for u in page.iterate_all():
        users.append({
            'uid': u.uid,
            'email': u.email,
            'displayName': u.display_name,
            'disabled': u.disabled,
            'createdAt': u.user_metadata.creation_timestamp,
            'lastSignIn': u.user_metadata.last_sign_in_timestamp,
            'isAdmin': (u.custom_claims or {}).get('admin', False),
        })
    return jsonify({'success': True, 'data': users})


# ═══════════════════════════════════════════════════════════════
# IMPORT / EXPORT
# ═══════════════════════════════════════════════════════════════
@app.route('/api/admin/export', methods=['GET'])
@require_admin
def admin_export():
    entity = request.args.get('entity', '')
    fmt = request.args.get('format', 'json')
    col_name = ENTITIES.get(entity)
    if not col_name:
        return jsonify({'success': False, 'error': 'Entity không hợp lệ'}), 400
    if not _fs():
        return jsonify({'success': False, 'error': 'Firestore unavailable'}), 503

    q = _fs().collection(col_name)
    owner = request.args.get('ownerUid')
    vehicle = request.args.get('vehicleId')
    if owner:
        q = q.where('ownerUid', '==', owner)
    if vehicle:
        q = q.where('vehicleId', '==', vehicle)

    docs = q.stream()
    rows = []
    for doc in docs:
        d = doc.to_dict()
        d['_id'] = doc.id
        # Convert non-serializable types
        for k, v in d.items():
            if hasattr(v, 'isoformat'):
                d[k] = v.isoformat()
            elif hasattr(v, 'timestamp'):
                d[k] = v.isoformat() if hasattr(v, 'isoformat') else str(v)
        rows.append(d)

    if fmt == 'csv':
        if not rows:
            return Response('', mimetype='text/csv')
        output = io.StringIO()
        writer = csv.DictWriter(output, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)
        return Response(
            output.getvalue(),
            mimetype='text/csv',
            headers={'Content-Disposition': f'attachment; filename={entity}.csv'},
        )

    return jsonify({'success': True, 'data': rows, 'total': len(rows)})


@app.route('/api/admin/import', methods=['POST'])
@require_admin
def admin_import():
    entity = request.args.get('entity', '')
    mode = request.args.get('mode', 'upsert')
    col_name = ENTITIES.get(entity)
    if not col_name:
        return jsonify({'success': False, 'error': 'Entity không hợp lệ'}), 400
    if not _fs():
        return jsonify({'success': False, 'error': 'Firestore unavailable'}), 503

    # Support JSON body or file upload
    records = []
    if request.is_json:
        records = request.get_json() or []
        if isinstance(records, dict):
            records = records.get('data', [])
    elif 'file' in request.files:
        f = request.files['file']
        content = f.read().decode('utf-8')
        if f.filename.endswith('.csv'):
            reader = csv.DictReader(io.StringIO(content))
            records = list(reader)
        else:
            records = json.loads(content)
            if isinstance(records, dict):
                records = records.get('data', records)

    inserted = 0
    updated = 0
    rejected = 0
    errors = []

    for i, record in enumerate(records):
        try:
            record = _ensure_schema(record, entity)
            doc_id = record.pop('_id', None) or str(uuid.uuid4())

            if mode == 'upsert':
                _fs().collection(col_name).document(doc_id).set(record, merge=True)
                updated += 1
            else:
                _fs().collection(col_name).document(doc_id).set(record)
                inserted += 1
        except Exception as e:
            rejected += 1
            errors.append({'row': i, 'error': str(e)})

    _audit('admin_import', col_name, '', request._uid, request._email,
           {'inserted': inserted, 'updated': updated, 'rejected': rejected})

    return jsonify({
        'success': True,
        'data': {
            'inserted': inserted,
            'updated': updated,
            'rejected': rejected,
            'errorDetails': errors,
        },
    })


# ═══════════════════════════════════════════════════════════════
# TELEMETRY (public cho dashboard, dùng seed data khi chưa có auth)
# ═══════════════════════════════════════════════════════════════
_telemetry_seed = []


def _seed_telemetry():
    now = datetime.now(timezone.utc).replace(second=0, microsecond=0)
    trips = [
        {'trip_id': 'TRIP-001', 'base_lat': 21.0285, 'base_lng': 105.8542, 'soc_start': 95, 'offset_h': -8},
        {'trip_id': 'TRIP-002', 'base_lat': 21.0285, 'base_lng': 105.8542, 'soc_start': 82, 'offset_h': -6},
        {'trip_id': 'TRIP-003', 'base_lat': 21.0350, 'base_lng': 105.8400, 'soc_start': 68, 'offset_h': -2},
    ]
    for t in trips:
        lat, lng, soc = t['base_lat'], t['base_lng'], t['soc_start']
        for i in range(5):
            spd = random.randint(0, 60) if i > 0 else 0
            alt = random.randint(5, 40)
            ts = (now + timedelta(hours=t['offset_h'], minutes=i * 5)).strftime('%Y-%m-%dT%H:%M:%SZ')
            _telemetry_seed.append({
                'trip_id': t['trip_id'], 'timestamp': ts,
                'latitude': round(lat + i * 0.003 * random.uniform(0.5, 1.5), 6),
                'longitude': round(lng - i * 0.005 * random.uniform(0.5, 1.5), 6),
                'speed_kmh': spd, 'altitude_m': alt,
                'current_soc': max(0, soc - i * random.randint(1, 3)),
            })


_seed_telemetry()


@app.route('/api/telemetry', methods=['GET'])
def get_telemetry():
    """Trả telemetry — ưu tiên Firestore, chỉ fallback demo khi bật ALLOW_DEMO_DATA."""
    if _fs():
        q = _fs().collection('TelemetryPoints').where('isDeleted', '==', False)
        trip = request.args.get('trip_id')
        if trip:
            q = q.where('trip_id', '==', trip)
        docs = q.limit(500).stream()
        data = [{'_id': d.id, **d.to_dict()} for d in docs]
        return jsonify(data)
    if not _allow_demo_data:
        return jsonify([])
    # Fallback to seed only in demo mode
    trip = request.args.get('trip_id')
    data = [r for r in _telemetry_seed if not trip or r['trip_id'] == trip]
    return jsonify(data)


# Backward-compatible endpoints (cho dashboard hiện tại)
@app.route('/api/charge-logs', methods=['GET'])
def get_charge_logs():
    """Public charge logs — ưu tiên Firestore, chỉ fallback demo khi bật ALLOW_DEMO_DATA."""
    vid = request.args.get('vehicleId')
    if _fs():
        q = _fs().collection('ChargeLogs').where('isDeleted', '==', False)
        if vid:
            q = q.where('vehicleId', '==', vid)
        docs = q.order_by('startTime', direction='DESCENDING').limit(100).stream()
        logs = [{'logId': d.id, **d.to_dict()} for d in docs]
        return jsonify({'success': True, 'data': logs})
    if not _allow_demo_data:
        return jsonify({'success': True, 'data': []})
    # Seed fallback only in demo mode
    seed = _seed_charge_logs()
    logs = [l for l in seed if not vid or l['vehicleId'] == vid]
    return jsonify({'success': True, 'data': logs})


def _seed_charge_logs():
    now = datetime.now()
    out = []
    for sb, eb, odo, d in [(15, 100, 1230, 1), (30, 95, 1180, 3), (8, 100, 1100, 5),
                            (22, 88, 1020, 7), (5, 100, 950, 10)]:
        out.append({
            'logId': str(uuid.uuid4()), 'vehicleId': 'VF-OPES-001',
            'startTime': (now - timedelta(days=d, hours=8)).isoformat(),
            'endTime': (now - timedelta(days=d, hours=5)).isoformat(),
            'startBatteryPercent': sb, 'endBatteryPercent': eb, 'odoAtCharge': odo,
        })
    return out


# ═══════════════════════════════════════════════════════════════
# AI MODEL — Battery Degradation (chuyển nguyên từ ai_api.py)
# ═══════════════════════════════════════════════════════════════

class BatteryDegradationModel:
    MAX_CYCLES = 800
    NOMINAL_CAPACITY_KWH = 1.5
    CRITICAL_HEALTH = 60

    def predict_degradation(self, charge_logs: list) -> dict:
        if not charge_logs or len(charge_logs) < 3:
            return {
                'healthScore': 100.0, 'healthStatus': 'Chưa đủ dữ liệu',
                'healthStatusCode': 'insufficient_data',
                'equivalentCycles': 0, 'remainingCycles': self.MAX_CYCLES,
                'estimatedLifeMonths': None, 'avgChargeRate': 0, 'avgDoD': 0,
                'degradationFactors': [],
                'recommendations': ['Cần ít nhất 3 lần sạc để phân tích'],
                'confidence': 0.0,
            }

        equivalent_cycles = self._calc_eq_cycles(charge_logs)
        avg_dod = self._calc_avg_dod(charge_logs)
        avg_charge_rate = self._calc_avg_rate(charge_logs)
        charge_rate_trend = self._calc_rate_trend(charge_logs)
        total_odo = max((l.get('odoAtCharge', 0) for l in charge_logs), default=0)

        cycle_aging = (equivalent_cycles / self.MAX_CYCLES) * 100
        dod_stress = max(0, (avg_dod - 50) / 100.0) if avg_dod > 50 else 0
        rate_stress = max(0, (avg_charge_rate - 20) / 100.0) if avg_charge_rate > 20 else 0
        calendar_stress = self._calendar_stress(charge_logs)
        total_aging = cycle_aging * (1 + dod_stress + rate_stress) + calendar_stress
        health_score = max(0, min(100, 100 - total_aging))

        remaining_cycles = max(0, self.MAX_CYCLES - equivalent_cycles)
        cpm = self._cycles_per_month(charge_logs)
        est_life = round(remaining_cycles / cpm, 1) if cpm > 0 else None

        factors = self._factors(avg_dod, avg_charge_rate, charge_rate_trend, equivalent_cycles)
        recs = self._recommendations(health_score, avg_dod, avg_charge_rate, charge_rate_trend)
        confidence = min(1.0, len(charge_logs) / 50) * 100

        if health_score >= 80:
            status, code = 'Tốt', 'good'
        elif health_score >= 60:
            status, code = 'Khá', 'fair'
        elif health_score >= 40:
            status, code = 'Trung bình', 'average'
        else:
            status, code = 'Cần thay pin', 'poor'

        return {
            'healthScore': round(health_score, 1), 'healthStatus': status,
            'healthStatusCode': code,
            'equivalentCycles': round(equivalent_cycles, 1),
            'remainingCycles': round(remaining_cycles, 1),
            'estimatedLifeMonths': est_life,
            'avgChargeRate': round(avg_charge_rate, 2),
            'avgDoD': round(avg_dod, 1),
            'chargeRateTrend': round(charge_rate_trend, 3),
            'totalOdometer': total_odo,
            'degradationFactors': factors, 'recommendations': recs,
            'confidence': round(confidence, 1), 'modelVersion': '2.0-statistical',
        }

    def _calc_eq_cycles(self, logs):
        return sum((l['endBatteryPercent'] - l['startBatteryPercent']) / 100.0 for l in logs)

    def _calc_avg_dod(self, logs):
        return sum(100 - l['startBatteryPercent'] for l in logs) / len(logs) if logs else 0

    def _calc_avg_rate(self, logs):
        rates = []
        for l in logs:
            try:
                h = (datetime.fromisoformat(l['endTime']) - datetime.fromisoformat(l['startTime'])).total_seconds() / 3600
                if h > 0:
                    rates.append((l['endBatteryPercent'] - l['startBatteryPercent']) / h)
            except (ValueError, KeyError):
                pass
        return sum(rates) / len(rates) if rates else 0

    def _calc_rate_trend(self, logs):
        rates = []
        for l in sorted(logs, key=lambda x: x.get('startTime', '')):
            try:
                h = (datetime.fromisoformat(l['endTime']) - datetime.fromisoformat(l['startTime'])).total_seconds() / 3600
                if h > 0:
                    rates.append((l['endBatteryPercent'] - l['startBatteryPercent']) / h)
            except (ValueError, KeyError):
                pass
        if len(rates) < 3:
            return 0.0
        n = len(rates)
        xm = (n - 1) / 2
        ym = sum(rates) / n
        num = sum((i - xm) * (rates[i] - ym) for i in range(n))
        den = sum((i - xm) ** 2 for i in range(n))
        return num / den if den else 0

    def _calendar_stress(self, logs):
        try:
            times = [datetime.fromisoformat(l['startTime']) for l in logs]
            return max(0, ((datetime.now() - min(times)).days / 365) * 2.0) if times else 0
        except (ValueError, KeyError):
            return 0

    def _cycles_per_month(self, logs):
        try:
            times = sorted(datetime.fromisoformat(l['startTime']) for l in logs)
            if len(times) < 2:
                return 0
            months = max(1, (times[-1] - times[0]).days / 30)
            return self._calc_eq_cycles(logs) / months
        except (ValueError, KeyError):
            return 0

    def _factors(self, dod, rate, trend, cycles):
        f = []
        if cycles > self.MAX_CYCLES * 0.7:
            f.append({'factor': 'Số chu kỳ sạc cao', 'severity': 'high',
                       'detail': f'{cycles:.0f}/{self.MAX_CYCLES} chu kỳ'})
        if dod > 80:
            f.append({'factor': 'Xả pin quá sâu', 'severity': 'high',
                       'detail': f'DoD TB {dod:.0f}%'})
        elif dod > 60:
            f.append({'factor': 'Mức xả pin trung bình', 'severity': 'medium',
                       'detail': f'DoD TB {dod:.0f}%'})
        if trend < -0.1:
            f.append({'factor': 'Tốc độ sạc giảm dần', 'severity': 'medium',
                       'detail': f'Giảm {abs(trend):.2f} %/h/chu kỳ'})
        if rate > 30:
            f.append({'factor': 'Sạc quá nhanh', 'severity': 'medium',
                       'detail': f'TB {rate:.1f} %/h'})
        if not f:
            f.append({'factor': 'Không phát hiện vấn đề', 'severity': 'low',
                       'detail': 'Pin hoạt động bình thường'})
        return f

    def _recommendations(self, score, dod, rate, trend):
        r = []
        if dod > 80:
            r.append('🔋 Sạc pin sớm hơn — tránh để dưới 20%')
        if rate > 30:
            r.append('⚡ Giảm tốc độ sạc — sạc chậm bền hơn')
        if trend < -0.1:
            r.append('📉 Tốc độ sạc đang giảm — cân nhắc kiểm tra')
        if score < 60:
            r.append('🔧 Sức khỏe < 60% — nên đến VinFast kiểm tra')
        if not r:
            r.append('✅ Pin hoạt động tốt — duy trì thói quen hiện tại')
        return r


class ChargingPatternAnalyzer:
    def analyze(self, charge_logs: list) -> dict:
        if not charge_logs or len(charge_logs) < 3:
            return {
                'peakChargingHour': None, 'peakChargingDay': None,
                'avgCycleDays': None, 'chargeFrequencyPerWeek': None,
                'avgSessionDuration': None, 'preferredChargeRange': None,
                'patterns': [],
            }

        hour_counts = [0] * 24
        day_counts = [0] * 7
        day_names = ['Thứ 2', 'Thứ 3', 'Thứ 4', 'Thứ 5', 'Thứ 6', 'Thứ 7', 'Chủ nhật']
        durations = []
        starts_pct = []
        ends_pct = []

        for l in charge_logs:
            try:
                t = datetime.fromisoformat(l['startTime'])
                hour_counts[t.hour] += 1
                day_counts[t.weekday()] += 1
            except (ValueError, KeyError):
                pass
            try:
                s = datetime.fromisoformat(l['startTime'])
                e = datetime.fromisoformat(l['endTime'])
                durations.append((e - s).total_seconds() / 3600)
            except (ValueError, KeyError):
                pass
            starts_pct.append(l.get('startBatteryPercent', 50))
            ends_pct.append(l.get('endBatteryPercent', 100))

        peak_hour = hour_counts.index(max(hour_counts))
        peak_day = day_counts.index(max(day_counts))

        try:
            times = sorted(datetime.fromisoformat(l['startTime']) for l in charge_logs)
            gaps = [(times[i] - times[i - 1]).total_seconds() / 86400 for i in range(1, len(times))]
            avg_cycle = sum(gaps) / len(gaps) if gaps else None
        except (ValueError, KeyError):
            avg_cycle = None

        freq = (7 / avg_cycle) if avg_cycle and avg_cycle > 0 else None
        avg_dur = sum(durations) / len(durations) if durations else None
        pref = {
            'avgStart': round(sum(starts_pct) / len(starts_pct)) if starts_pct else 0,
            'avgEnd': round(sum(ends_pct) / len(ends_pct)) if ends_pct else 0,
        }

        patterns = []
        if peak_hour >= 22 or peak_hour <= 5:
            patterns.append('🌙 Thường sạc ban đêm')
        elif 6 <= peak_hour <= 9:
            patterns.append('🌅 Thường sạc buổi sáng')
        elif 17 <= peak_hour <= 21:
            patterns.append('🌆 Thường sạc buổi tối')
        if pref['avgStart'] < 20:
            patterns.append('⚠️ Thường xả pin rất sâu')
        elif pref['avgStart'] > 40:
            patterns.append('👍 Sạc khi còn nhiều pin')
        if pref['avgEnd'] >= 95:
            patterns.append('🔌 Thường sạc đầy 100%')

        return {
            'peakChargingHour': f'{peak_hour:02d}:00',
            'peakChargingDay': day_names[peak_day],
            'avgCycleDays': round(avg_cycle, 1) if avg_cycle else None,
            'chargeFrequencyPerWeek': round(freq, 1) if freq else None,
            'avgSessionDuration': round(avg_dur, 1) if avg_dur else None,
            'preferredChargeRange': pref,
            'patterns': patterns,
        }


degradation_model = BatteryDegradationModel()
pattern_analyzer = ChargingPatternAnalyzer()


# ═══════════════════════════════════════════════════════════════
# AI ENDPOINTS
# ═══════════════════════════════════════════════════════════════
def _get_profile(vehicle_id: str):
    if _fs():
        doc = _fs().collection('AiVehicleProfiles').document(vehicle_id).get()
        return doc.to_dict() if doc.exists else None
    return _local_profiles.get(vehicle_id)


def _save_profile(vehicle_id: str, profile: dict):
    if _fs():
        _fs().collection('AiVehicleProfiles').document(vehicle_id).set(profile, merge=True)
    else:
        _local_profiles[vehicle_id] = profile


def _to_dt(v):
    if v is None:
        return None
    if isinstance(v, datetime):
        return v
    if hasattr(v, 'to_datetime'):
        return v.to_datetime()
    if hasattr(v, 'isoformat') and not isinstance(v, str):
        return v
    if isinstance(v, str):
        try:
            return datetime.fromisoformat(v.replace('Z', '+00:00'))
        except ValueError:
            return None
    return None


def _build_training_dataset(vehicle_id: str):
    """Build dataset đầy đủ trường từ Firestore cho train AI."""
    if not _fs():
        return []

    charge_docs = list(
        _fs().collection('ChargeLogs')
        .where('vehicleId', '==', vehicle_id)
        .where('isDeleted', '==', False)
        .stream()
    )
    if not charge_docs:
        return []

    trip_docs = list(
        _fs().collection('TripLogs')
        .where('vehicleId', '==', vehicle_id)
        .where('isDeleted', '==', False)
        .stream()
    )
    telemetry_docs = list(
        _fs().collection('TelemetryPoints')
        .where('vehicleId', '==', vehicle_id)
        .where('isDeleted', '==', False)
        .limit(1000)
        .stream()
    )
    sample_docs = list(
        _fs().collection('ChargeSamples')
        .where('vehicleId', '==', vehicle_id)
        .where('isDeleted', '==', False)
        .limit(1500)
        .stream()
    )

    trips = []
    for d in trip_docs:
        x = d.to_dict() or {}
        x['_id'] = d.id
        x['_start'] = _to_dt(x.get('startTime'))
        x['_end'] = _to_dt(x.get('endTime'))
        trips.append(x)

    telemetry = []
    for d in telemetry_docs:
        x = d.to_dict() or {}
        x['_time'] = _to_dt(x.get('timestamp')) or _to_dt(x.get('createdAt'))
        telemetry.append(x)

    samples_by_session = {}
    for d in sample_docs:
        x = d.to_dict() or {}
        sid = x.get('sessionId')
        if sid:
            samples_by_session.setdefault(sid, []).append(x)

    records = []
    for d in charge_docs:
        c = d.to_dict() or {}
        start = _to_dt(c.get('startTime'))
        end = _to_dt(c.get('endTime'))
        if not start or not end:
            continue

        gain = (c.get('endBatteryPercent', 0) - c.get('startBatteryPercent', 0))
        hours = max((end - start).total_seconds() / 3600, 1e-6)
        avg_rate = gain / hours
        session_id = c.get('sessionId') or d.id
        samples = samples_by_session.get(session_id, [])

        recent_trips = [
            t for t in trips
            if t.get('_end') and t.get('_end') <= start and (start - t.get('_end')).days <= 14
        ]
        recent_trips = sorted(recent_trips, key=lambda x: x.get('_end'), reverse=True)[:5]
        avg_trip_distance = round(sum((t.get('distance') or 0) for t in recent_trips) / len(recent_trips), 3) if recent_trips else 0
        avg_trip_speed = round(sum((t.get('avgSpeedKmh') or 0) for t in recent_trips) / len(recent_trips), 3) if recent_trips else 0
        avg_trip_consumption = round(sum((t.get('batteryConsumed') or 0) for t in recent_trips) / len(recent_trips), 3) if recent_trips else 0

        telemetry_near = [
            p for p in telemetry
            if p.get('_time') and start - timedelta(hours=24) <= p.get('_time') <= end + timedelta(hours=2)
        ]

        rec = {
            'recordId': d.id,
            'vehicleId': vehicle_id,
            'ownerUid': c.get('ownerUid'),
            'sessionId': session_id,
            'startTime': start.isoformat(),
            'endTime': end.isoformat(),
            'startBatteryPercent': int(c.get('startBatteryPercent', 0)),
            'endBatteryPercent': int(c.get('endBatteryPercent', 0)),
            'chargeGainPercent': int(gain),
            'odoAtCharge': int(c.get('odoAtCharge', 0)),
            'targetBatteryPercent': c.get('targetBatteryPercent'),
            'durationHours': round(hours, 4),
            'avgChargeRate': round(avg_rate, 4),
            'chargeRatePerMin': round(avg_rate / 60.0, 6),
            'recentTripCount': len(recent_trips),
            'recentTripAvgDistanceKm': avg_trip_distance,
            'recentTripAvgSpeedKmh': avg_trip_speed,
            'recentTripAvgConsumptionPercent': avg_trip_consumption,
            'telemetryPointCountAroundSession': len(telemetry_near),
            'chargeSampleCount': len(samples),
            'dataQualityScore': 1.0,
            'source': c.get('source', 'app_live_charge'),
            'normalizedAt': _utcnow(),
            'schemaVersion': 'ai-dataset-v2',
        }
        records.append(rec)
    return records


@app.route('/api/admin/ai/dataset/<vehicle_id>', methods=['GET'])
@require_admin
def ai_dataset(vehicle_id):
    records = _build_training_dataset(vehicle_id)
    return jsonify({
        'success': True,
        'data': {
            'vehicleId': vehicle_id,
            'total': len(records),
            'schemaVersion': 'ai-dataset-v2',
            'requiredFields': [
                'startBatteryPercent', 'endBatteryPercent', 'startTime', 'endTime',
                'durationHours', 'avgChargeRate', 'chargeGainPercent',
                'recentTripAvgDistanceKm', 'recentTripAvgConsumptionPercent',
                'telemetryPointCountAroundSession',
            ],
            'records': records,
        },
    })


@app.route('/api/ai/predict-degradation', methods=['POST'])
def ai_predict():
    data = request.get_json() or {}
    charge_logs = data.get('chargeLogs', [])
    vehicle_id = data.get('vehicleId', '')
    if not charge_logs:
        return jsonify({'success': False, 'error': 'Cần cung cấp chargeLogs'}), 400
    try:
        pred = degradation_model.predict_degradation(charge_logs)
        pred['vehicleId'] = vehicle_id
        pred['analyzedAt'] = _utcnow()
        profile = _get_profile(vehicle_id) if vehicle_id else None
        if profile and profile.get('trainedAt'):
            adj = profile.get('healthAdjustment', 0)
            pred['healthScore'] = round(max(0, min(100, pred['healthScore'] + adj)), 1)
            pred['modelSource'] = 'personalized'
            pred['profileVersion'] = profile.get('version')
            pred['profileTrainedAt'] = profile.get('trainedAt')
        else:
            pred['modelSource'] = 'rule-based'
        return jsonify({'success': True, 'data': pred})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/api/ai/analyze-patterns', methods=['POST'])
def ai_analyze():
    data = request.get_json() or {}
    charge_logs = data.get('chargeLogs', [])
    vehicle_id = data.get('vehicleId', '')
    try:
        result = pattern_analyzer.analyze(charge_logs)
        result['vehicleId'] = vehicle_id
        result['analyzedAt'] = _utcnow()
        profile = _get_profile(vehicle_id) if vehicle_id else None
        result['modelSource'] = 'personalized' if profile and profile.get('trainedAt') else 'rule-based'
        return jsonify({'success': True, 'data': result})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/api/ai/train-vehicle-profile', methods=['POST'])
def ai_train():
    data = request.get_json() or {}
    vehicle_id = data.get('vehicleId', '')
    charge_logs = data.get('chargeLogs', [])
    if not vehicle_id:
        return jsonify({'success': False, 'error': 'vehicleId là bắt buộc'}), 400
    if len(charge_logs) < 5:
        return jsonify({'success': False, 'error': f'Cần ≥ 5 lần sạc (hiện {len(charge_logs)})'}), 400
    try:
        pred = degradation_model.predict_degradation(charge_logs)
        patt = pattern_analyzer.analyze(charge_logs)
        dod, rate, cyc = pred.get('avgDoD', 50), pred.get('avgChargeRate', 20), pred.get('equivalentCycles', 0)
        adj = 0.0
        if dod < 60: adj += 2.0
        elif dod > 85: adj -= 3.0
        if rate < 25: adj += 1.5
        elif rate > 35: adj -= 2.0

        profile = {
            'vehicleId': vehicle_id, 'trainedAt': _utcnow(), 'version': '1.0',
            'dataPoints': len(charge_logs), 'healthAdjustment': round(adj, 2),
            'stats': {
                'avgDoD': round(dod, 1), 'avgChargeRate': round(rate, 2),
                'equivalentCycles': round(cyc, 1),
                'peakChargingHour': patt.get('peakChargingHour'),
                'chargeFrequencyPerWeek': patt.get('chargeFrequencyPerWeek'),
            },
        }
        _save_profile(vehicle_id, profile)
        return jsonify({'success': True, 'data': profile,
                        'message': f'Profile trained cho {vehicle_id}'})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/api/ai/profile-status/<vehicle_id>', methods=['GET'])
def ai_profile_status(vehicle_id):
    profile = _get_profile(vehicle_id)
    if not profile:
        return jsonify({'success': True, 'data': {
            'vehicleId': vehicle_id, 'hasTrained': False,
            'trainedAt': None, 'version': None, 'dataPoints': 0,
        }})
    return jsonify({'success': True, 'data': {
        'vehicleId': vehicle_id, 'hasTrained': True,
        'trainedAt': profile.get('trainedAt'), 'version': profile.get('version'),
        'dataPoints': profile.get('dataPoints', 0),
        'healthAdjustment': profile.get('healthAdjustment', 0),
        'stats': profile.get('stats'),
    }})


# ── Admin AI: normalize + train + test ──
@app.route('/api/admin/ai/normalize-dataset', methods=['POST'])
@require_admin
def ai_normalize():
    """Chuẩn hóa dataset trước khi train."""
    data = request.get_json() or {}
    records = data.get('records', [])
    cleaned = []
    rejected = []
    for i, r in enumerate(records):
        try:
            # Validate required fields
            for k in ('startBatteryPercent', 'endBatteryPercent', 'startTime', 'endTime'):
                if k not in r:
                    raise ValueError(f'Thiếu field {k}')
            sb, eb = int(r['startBatteryPercent']), int(r['endBatteryPercent'])
            if not (0 <= sb <= 100 and 0 <= eb <= 100):
                raise ValueError('Pin phải 0-100')
            if eb <= sb:
                raise ValueError('endBattery phải > startBattery')
            datetime.fromisoformat(r['startTime'])
            datetime.fromisoformat(r['endTime'])
            r['dataQualityScore'] = 1.0
            r['normalizedAt'] = _utcnow()
            r['source'] = r.get('source', 'import')
            cleaned.append(r)
        except Exception as e:
            rejected.append({'row': i, 'error': str(e)})

    return jsonify({
        'success': True,
        'data': {'cleaned': len(cleaned), 'rejected': len(rejected),
                 'records': cleaned, 'errors': rejected},
    })


@app.route('/api/admin/ai/train', methods=['POST'])
@require_admin
def ai_admin_train():
    """Train model cho vehicle từ dataset đã normalize."""
    data = request.get_json() or {}
    vehicle_id = data.get('vehicleId', '')
    records = data.get('records', [])
    if not records and vehicle_id:
        records = _build_training_dataset(vehicle_id)
    if not vehicle_id or len(records) < 5:
        return jsonify({'success': False, 'error': 'Cần vehicleId + ≥ 5 records'}), 400

    pred = degradation_model.predict_degradation(records)
    patt = pattern_analyzer.analyze(records)
    dod, rate = pred.get('avgDoD', 50), pred.get('avgChargeRate', 20)
    adj = 0.0
    if dod < 60: adj += 2.0
    elif dod > 85: adj -= 3.0
    if rate < 25: adj += 1.5
    elif rate > 35: adj -= 2.0

    profile = {
        'vehicleId': vehicle_id, 'trainedAt': _utcnow(), 'version': '2.0',
        'modelType': 'vinfast-personalized-degradation',
        'schemaVersion': 'ai-profile-v2',
        'dataPoints': len(records), 'healthAdjustment': round(adj, 2),
        'featureSchema': [
            'startBatteryPercent', 'endBatteryPercent', 'durationHours',
            'avgChargeRate', 'recentTripAvgDistanceKm',
            'recentTripAvgConsumptionPercent', 'telemetryPointCountAroundSession',
        ],
        'stats': {
            'avgDoD': round(dod, 1), 'avgChargeRate': round(rate, 2),
            'equivalentCycles': round(pred.get('equivalentCycles', 0), 1),
            'peakChargingHour': patt.get('peakChargingHour'),
            'chargeFrequencyPerWeek': patt.get('chargeFrequencyPerWeek'),
            'avgSessionDuration': patt.get('avgSessionDuration'),
        },
        'trainingSummary': {
            'recordsUsed': len(records),
            'modelSource': 'firestore-auto' if data.get('records') in (None, []) else 'request-payload',
        },
    }
    _save_profile(vehicle_id, profile)
    _audit('ai_train', 'AiVehicleProfiles', vehicle_id, request._uid, request._email,
           {'dataPoints': len(records)})
    return jsonify({'success': True, 'data': profile})


@app.route('/api/admin/ai/test', methods=['POST'])
@require_admin
def ai_admin_test():
    """Test model đã train trên dataset."""
    data = request.get_json() or {}
    vehicle_id = data.get('vehicleId', '')
    records = data.get('records', [])
    if not records and vehicle_id:
        records = _build_training_dataset(vehicle_id)
    profile = _get_profile(vehicle_id)
    if not profile:
        return jsonify({'success': False, 'error': 'Chưa có profile — cần train trước'}), 400

    pred = degradation_model.predict_degradation(records)
    adj = profile.get('healthAdjustment', 0)
    pred['healthScore'] = round(max(0, min(100, pred['healthScore'] + adj)), 1)
    pred['modelSource'] = 'personalized'
    pred['testDataPoints'] = len(records)
    return jsonify({'success': True, 'data': pred})


# Backward-compat: redirect old AI endpoints (ai_api.py used /api/ prefix)
@app.route('/api/predict-degradation', methods=['POST'])
def compat_predict():
    return ai_predict()


@app.route('/api/analyze-patterns', methods=['POST'])
def compat_analyze():
    return ai_analyze()


@app.route('/api/train-vehicle-profile', methods=['POST'])
def compat_train():
    return ai_train()


@app.route('/api/profile-status/<vehicle_id>', methods=['GET'])
def compat_profile_status(vehicle_id):
    return ai_profile_status(vehicle_id)


# ═══════════════════════════════════════════════════════════════
# LEGACY MIGRATION
# ═══════════════════════════════════════════════════════════════
@app.route('/api/admin/migrate-legacy', methods=['POST'])
@require_admin
def migrate_legacy():
    """Đánh dấu bản ghi cũ không có ownerUid là legacy."""
    if not _fs():
        return jsonify({'success': False, 'error': 'Firestore unavailable'}), 503

    count = 0
    for col in ENTITIES.values():
        docs = _fs().collection(col).stream()
        batch = _fs().batch()
        batch_count = 0
        for doc in docs:
            d = doc.to_dict()
            if not d.get('ownerUid'):
                batch.update(doc.reference, {
                    'source': 'legacy', 'isLegacy': True,
                    'isDeleted': False, 'updatedAt': _utcnow(),
                })
                count += 1
                batch_count += 1
                if batch_count >= 400:
                    batch.commit()
                    batch = _fs().batch()
                    batch_count = 0
        if batch_count > 0:
            batch.commit()

    _audit('migrate_legacy', 'ALL', '', request._uid, request._email,
           {'documentsTagged': count})
    return jsonify({'success': True, 'message': f'Đã tag {count} bản ghi legacy'})


# ═══════════════════════════════════════════════════════════════
# GLOBAL ERROR HANDLERS
# ═══════════════════════════════════════════════════════════════
@app.errorhandler(HTTPException)
def handle_http_exception(err: HTTPException):
    if request.path.startswith('/api/'):
        return jsonify({
            'success': False,
            'error': err.description or 'HTTP error',
            'code': err.code,
        }), err.code
    return err


@app.errorhandler(Exception)
def handle_unexpected_exception(err: Exception):
    request_id = str(uuid.uuid4())[:8]
    print(f'❌ API error [{request_id}] {request.method} {request.path}: {err}')
    if request.path.startswith('/api/'):
        debug_mode = os.environ.get('FLASK_DEBUG', '1').lower() in ('1', 'true', 'yes')
        return jsonify({
            'success': False,
            'error': str(err) if debug_mode else 'Lỗi hệ thống, vui lòng thử lại',
            'requestId': request_id,
        }), 500
    raise err


# ═══════════════════════════════════════════════════════════════
# RUN
# ═══════════════════════════════════════════════════════════════
if __name__ == '__main__':
    print('\n⚡ VinFast Battery — Unified API Server v4.0')
    print('📡 Endpoints:')
    print('   Auth:   GET /api/auth/me, POST /api/auth/set-admin')
    print('   User:   GET /api/user/vehicles|charge-logs|trip-logs|maintenance')
    print('   Admin:  CRUD /api/admin/<entity>, /api/admin/users, /api/admin/audit-logs')
    print('   Export: GET /api/admin/export?entity=&format=json|csv')
    print('   Import: POST /api/admin/import?entity=&mode=upsert')
    print('   AI:     /api/ai/predict-degradation|analyze-patterns|train-vehicle-profile')
    print('   Admin AI: /api/admin/ai/normalize-dataset|train|test')
    print('   Legacy: POST /api/admin/migrate-legacy')
    print(f'🌐 http://localhost:5000\n')
    debug_mode = os.environ.get('FLASK_DEBUG', '1').lower() in ('1', 'true', 'yes')
    use_reloader = os.environ.get('FLASK_USE_RELOADER', '0').lower() in ('1', 'true', 'yes')
    app.run(debug=debug_mode, use_reloader=use_reloader, host='0.0.0.0', port=5000)
