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
# CONSUMPTION MODEL LOADER (ev_soc_pipeline.pkl)
# ═══════════════════════════════════════════════════════════════
_consumption_model = None
_consumption_model_status = 'not_loaded'
_consumption_model_error = None

def _load_consumption_model():
    """Load sklearn Pipeline from ev_soc_pipeline.pkl.
    Search order: EV_SOC_MODEL_PATH env, then relative paths."""
    global _consumption_model, _consumption_model_status, _consumption_model_error
    if not joblib:
        _consumption_model_status = 'dependency_missing'
        _consumption_model_error = 'joblib not installed'
        print('⚠ Consumption model: joblib not available')
        return

    root = os.path.dirname(os.path.abspath(__file__))
    candidates = []
    env_path = os.environ.get('EV_SOC_MODEL_PATH', '').strip()
    if env_path:
        candidates.append(env_path)
    candidates += [
        os.path.join(root, 'ev_soc_pipeline.pkl'),
        os.path.join(root, '..', 'ev_soc_pipeline.pkl'),
        os.path.join(root, 'models', 'ev_soc_pipeline.pkl'),
    ]

    for path in candidates:
        if os.path.isfile(path):
            try:
                _consumption_model = joblib.load(path)
                _consumption_model_status = 'loaded'
                print(f'✅ Consumption model loaded: {path}')
                return
            except Exception as e:
                _consumption_model_error = str(e)
                _consumption_model_status = 'load_error'
                print(f'⚠ Consumption model load error: {e}')
                return

    _consumption_model_status = 'file_not_found'
    _consumption_model_error = 'ev_soc_pipeline.pkl not found'
    print('⚠ Consumption model: file not found')

_load_consumption_model()

# 19 feature names expected by ev_soc_pipeline
_CONSUMPTION_FEATURES = [
    'distance_km', 'duration_min', 'speed_avg_kmh', 'speed_max_kmh',
    'acceleration_avg', 'deceleration_avg', 'altitude_gain_m', 'altitude_loss_m',
    'temperature_c', 'payload_kg', 'tire_pressure_psi', 'hvac_on',
    'headlights_on', 'rain', 'traffic_factor', 'road_type',
    'soc_start', 'vehicle_age_months', 'odometer_km',
]

def _build_consumption_features(body: dict) -> list:
    """Build 19-dim feature vector from request body.
    Supports two modes:
    1. Full features: client sends all 19 fields.
    2. Minimal context: client sends distance, payload, speed/efficiency
       history — server infers the rest with fixed rules + clamp.
    Returns (features_list, inferred_count)."""
    features = body.get('features', {})
    inferred = 0

    # Convenience aliases
    distance = features.get('distance_km', body.get('distance', body.get('distanceKm', 0)))
    soc_start = features.get('soc_start', body.get('socStart', body.get('currentBattery', 80)))
    payload_kg = features.get('payload_kg', body.get('payloadKg', 75))  # default 1 người ~75kg
    speed_avg = features.get('speed_avg_kmh', body.get('avgSpeed', 0))
    odometer = features.get('odometer_km', body.get('odometerKm', body.get('odometer', 5000)))
    vehicle_age = features.get('vehicle_age_months', body.get('vehicleAgeMonths', 12))

    # Auto-infer missing fields
    if speed_avg <= 0:
        speed_avg = max(25.0, min(60.0, distance / max(distance / 30.0, 0.1)))
        inferred += 1

    duration = features.get('duration_min')
    if duration is None:
        duration = (distance / max(speed_avg, 1)) * 60  # minutes
        inferred += 1

    speed_max = features.get('speed_max_kmh')
    if speed_max is None:
        speed_max = speed_avg * 1.6
        inferred += 1

    acc_avg = features.get('acceleration_avg')
    if acc_avg is None:
        acc_avg = 0.8  # m/s^2 moderate
        inferred += 1

    dec_avg = features.get('deceleration_avg')
    if dec_avg is None:
        dec_avg = -0.9
        inferred += 1

    alt_gain = features.get('altitude_gain_m', 0)
    alt_loss = features.get('altitude_loss_m', 0)
    if alt_gain == 0 and alt_loss == 0:
        alt_gain = distance * 2.0  # mild terrain assumption
        alt_loss = distance * 2.0
        inferred += 2

    temp = features.get('temperature_c')
    if temp is None:
        temp = 30.0  # Vietnam average
        inferred += 1

    tire = features.get('tire_pressure_psi')
    if tire is None:
        tire = 32.0
        inferred += 1

    hvac = features.get('hvac_on', 0)
    headlights = features.get('headlights_on', 0)
    rain = features.get('rain', 0)
    traffic = features.get('traffic_factor', 1.0)
    road_type = features.get('road_type', 1)  # 0=highway 1=urban 2=mixed

    row = [
        float(distance), float(duration), float(speed_avg), float(speed_max),
        float(acc_avg), float(dec_avg), float(alt_gain), float(alt_loss),
        float(temp), float(payload_kg), float(tire), int(hvac),
        int(headlights), int(rain), float(traffic), int(road_type),
        float(soc_start), float(vehicle_age), float(odometer),
    ]
    return row, inferred

def _heuristic_consumption(distance: float, soc_start: float, payload_kg: float,
                           speed_avg: float) -> dict:
    """Rule-based fallback when ML model is unavailable."""
    # Base: ~1.2 km per 1% for VinFast Feliz
    base_efficiency = 1.2
    # Payload adjustment: +30% drain per extra 75kg above solo rider
    payload_factor = 1.0 + max(0, (payload_kg - 75) / 75) * 0.3
    # Speed penalty: above 45 km/h, efficiency drops
    speed_factor = 1.0 + max(0, (speed_avg - 45) / 45) * 0.15

    drain_pct = (distance / base_efficiency) * payload_factor * speed_factor
    drain_pct = max(0.0, min(100.0, drain_pct))
    remaining = max(0.0, soc_start - drain_pct)
    enough = remaining >= 5.0

    return {
        'predictedConsumptionPercent': round(drain_pct, 2),
        'estimatedBatteryDrainPercent': round(drain_pct, 2),
        'predictedRemainingSocPercent': round(remaining, 2),
        'isEnoughForTrip': enough,
        'confidence': 35.0,
        'modelSource': 'heuristic-fallback',
        'inferredFeatureCount': 19,
    }

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
        'version': '4.1',
        'firebaseConnected': _firebase_available,
        'consumptionModel': {
            'status': _consumption_model_status,
            'available': _consumption_model is not None,
            'error': _consumption_model_error,
        },
        'endpoints': [
            'GET  /api/health',
            'POST /api/auth/set-admin',
            'GET  /api/user/vehicles',
            'CRUD /api/admin/...',
            'POST /api/ai/predict-degradation',
            'POST /api/ai/predict-consumption',
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

    # Auto-refresh insight after train
    insight_ok, insight_err = _refresh_vehicle_insight(vehicle_id)

    return jsonify({
        'success': True,
        'data': profile,
        'insightRefreshed': insight_ok,
        'insightError': insight_err,
    })


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


# ═══════════════════════════════════════════════════════════════
# AI ENDPOINT — Predict Consumption (ML model)
# ═══════════════════════════════════════════════════════════════
@app.route('/api/ai/predict-consumption', methods=['POST'])
def ai_predict_consumption():
    """Predict battery consumption for a planned trip using ev_soc_pipeline.
    Accepts full 19-feature input or minimal context (distance, payload, etc.).
    Falls back to heuristic when model/dependencies unavailable."""
    body = request.get_json() or {}

    # Extract convenience fields for heuristic fallback
    features_raw = body.get('features', {})
    distance = features_raw.get('distance_km', body.get('distance', body.get('distanceKm', 0)))
    soc_start = features_raw.get('soc_start', body.get('socStart', body.get('currentBattery', 80)))
    payload_kg = features_raw.get('payload_kg', body.get('payloadKg', 75))
    speed_avg = features_raw.get('speed_avg_kmh', body.get('avgSpeed', 25))

    # Validate minimum input
    if distance <= 0:
        return jsonify({
            'success': False,
            'error': 'distance (km) phải > 0',
        }), 400

    # Try ML model first
    if _consumption_model is not None and pd is not None:
        try:
            row, inferred_count = _build_consumption_features(body)
            df = pd.DataFrame([row], columns=_CONSUMPTION_FEATURES)
            pred = _consumption_model.predict(df)
            drain_pct = float(pred[0])
            # Clamp to sane range
            drain_pct = max(0.0, min(100.0, drain_pct))
            remaining = max(0.0, float(soc_start) - drain_pct)
            enough = remaining >= 5.0
            confidence = max(50.0, 95.0 - inferred_count * 3.0)

            return jsonify({
                'success': True,
                'data': {
                    'predictedConsumptionPercent': round(drain_pct, 2),
                    'estimatedBatteryDrainPercent': round(drain_pct, 2),
                    'predictedRemainingSocPercent': round(remaining, 2),
                    'isEnoughForTrip': enough,
                    'confidence': round(confidence, 1),
                    'modelSource': 'ev_soc_pipeline',
                    'inferredFeatureCount': inferred_count,
                },
            })
        except Exception as e:
            print(f'⚠ ML prediction error, falling back to heuristic: {e}')
            # Fall through to heuristic

    # Heuristic fallback
    result = _heuristic_consumption(
        float(distance), float(soc_start), float(payload_kg), float(speed_avg)
    )
    return jsonify({'success': True, 'data': result})


# ═══════════════════════════════════════════════════════════════
# AI ENDPOINT — Predict Charging Time
# ═══════════════════════════════════════════════════════════════
def _predict_charging_time(current_battery: float, target_battery: float,
                           battery_health: float = 100.0,
                           temperature: float = 25.0,
                           charger_type: str = 'standard',
                           battery_capacity_wh: float = 1440.0) -> dict:
    """Heuristic charging time prediction with CC-CV simulation.
    
    VinFast Feliz LFP battery characteristics:
    - Nominal: 1440 Wh (48V × 30Ah)
    - Standard charger: ~200W (48V × ~4.2A)
    - Fast charger: ~400W (higher amperage)
    
    CC-CV profile: constant current to ~80%, then taper to target.
    """
    if current_battery >= target_battery:
        return {
            'estimatedMinutes': 0,
            'estimatedHours': 0.0,
            'formattedTime': '0 phút',
            'chargeRatePercentPerHour': 0,
            'chargeGainPercent': 0,
            'energyNeededWh': 0,
            'chargePowerW': 0,
            'recommendations': ['Pin đã đạt mức mong muốn.'],
            'confidence': 95.0,
            'modelSource': 'heuristic-v1',
            'chargingCurve': [],
        }

    # ── Charger power (watts) ──
    charger_powers = {
        'standard': 200.0,   # 48V × ~4.2A
        'fast': 400.0,       # 2× standard
        'slow': 100.0,       # trickle / weak outlet
    }
    base_power = charger_powers.get(charger_type, 200.0)

    # ── Derating factors ──
    # SoH: degraded battery charges slower
    soh_factor = max(0.6, battery_health / 100.0)
    
    # Temperature: optimal 20-30°C, drops outside
    if temperature < 10:
        temp_factor = 0.7
    elif temperature < 20:
        temp_factor = 0.85
    elif temperature <= 35:
        temp_factor = 1.0
    else:
        temp_factor = 0.85  # heat throttle

    effective_power = base_power * soh_factor * temp_factor

    # ── Effective capacity ──
    effective_capacity_wh = battery_capacity_wh * soh_factor

    # ── CC-CV simulation: simulate per-percent charging time ──
    charge_gain = target_battery - current_battery
    energy_needed = effective_capacity_wh * (charge_gain / 100.0)
    
    charging_curve = []
    total_minutes = 0.0
    soc = current_battery

    while soc < target_battery:
        # CC phase: full power up to ~80%
        # CV phase: power tapers linearly from 80% to 100%
        if soc < 80:
            phase_power = effective_power
        else:
            # Taper: at 80% → 100% power, at 100% → 20% power
            taper = 1.0 - 0.8 * ((soc - 80.0) / 20.0)
            phase_power = effective_power * max(0.2, taper)

        # Energy for 1% of battery
        energy_per_pct = effective_capacity_wh / 100.0
        # Time for this % in hours
        time_hours = energy_per_pct / max(phase_power, 1.0)
        minutes_for_pct = time_hours * 60.0
        
        total_minutes += minutes_for_pct
        soc += 1.0

        # Record curve point every 5%
        if int(soc) % 5 == 0 or soc >= target_battery:
            charging_curve.append({
                'soc': round(min(soc, target_battery), 1),
                'minutesElapsed': round(total_minutes, 1),
                'powerW': round(phase_power, 0),
            })

    total_minutes = round(total_minutes, 1)
    hours = total_minutes / 60.0
    avg_rate = charge_gain / max(hours, 0.001)  # %/hour

    # Format time
    h = int(total_minutes // 60)
    m = int(total_minutes % 60)
    if h > 0:
        formatted = f'{h} giờ {m} phút'
    else:
        formatted = f'{m} phút'

    # Recommendations
    recs = []
    if target_battery > 90:
        recs.append('Sạc đến 80-90% sẽ nhanh hơn đáng kể do pha CV taper.')
    if temperature > 35:
        recs.append('Nhiệt độ cao — để xe nơi mát để sạc nhanh hơn.')
    elif temperature < 10:
        recs.append('Nhiệt độ thấp — thời gian sạc sẽ lâu hơn bình thường.')
    if battery_health < 80:
        recs.append('SoH thấp — cân nhắc kiểm tra pin tại trung tâm dịch vụ.')
    if charger_type == 'standard' and charge_gain > 60:
        recs.append('Sạc lượng lớn — cân nhắc dùng sạc nhanh nếu có.')
    if not recs:
        recs.append('Điều kiện sạc tốt, thời gian ước tính đáng tin cậy.')

    # Confidence: affected by how many assumptions
    confidence = 85.0
    if battery_health < 80:
        confidence -= 10
    if temperature < 10 or temperature > 40:
        confidence -= 5

    return {
        'estimatedMinutes': total_minutes,
        'estimatedHours': round(hours, 2),
        'formattedTime': formatted,
        'chargeRatePercentPerHour': round(avg_rate, 1),
        'chargeGainPercent': round(charge_gain, 1),
        'energyNeededWh': round(energy_needed, 1),
        'chargePowerW': round(effective_power, 0),
        'recommendations': recs,
        'confidence': round(confidence, 1),
        'modelSource': 'heuristic-v1',
        'chargingCurve': charging_curve,
        'factors': {
            'sohFactor': round(soh_factor, 2),
            'tempFactor': round(temp_factor, 2),
            'chargerType': charger_type,
            'effectivePowerW': round(effective_power, 0),
        },
    }


def _format_duration(seconds: float) -> str:
    """Format seconds to hours/minutes string."""
    hours = int(seconds // 3600)
    mins = int((seconds % 3600) // 60)
    if hours > 0:
        return f"{hours} giờ {mins} phút"
    return f"{mins} phút"


def _ai_predict_charging_time(current: float, target: float, ambient_temp_c: float = 25.0) -> dict:
    """Call AI Center charging_time model. Returns (result_dict, is_success)."""
    if _http is None:
        return None, False
    
    url = f'{AI_SERVER_URL}/v1/models/charging_time/predict'
    payload = {
        'start_soc': current,
        'end_soc': target,
        'ambient_temp_c': ambient_temp_c,
    }
    try:
        resp = _http.post(
            url,
            json=payload,
            headers=_ai_headers({'Content-Type': 'application/json'}),
            timeout=AI_SERVER_TIMEOUT,
        )
        if resp.status_code != 200:
            return None, False
        data = resp.json()
        if not data.get('success'):
            return None, False
        result = data.get('data', {})
        # Extract prediction in seconds (AI model returns seconds)
        predicted_sec = result.get('predictionSeconds') or result.get('prediction', 0)
        if predicted_sec <= 0:
            return None, False
        return {
            'predictedDurationSec': predicted_sec,
            'predictedDurationMin': predicted_sec / 60.0,
            'formattedDuration': _format_duration(predicted_sec),
            'modelVersion': result.get('modelVersion', 'unknown'),
            'rawPrediction': result.get('rawPrediction'),
            'processedInput': result.get('processedInput'),
            'chartData': result.get('chartData'),
            'warnings': result.get('warnings', []),
        }, True
    except Exception as e:
        print(f'[AI Charging] Error calling AI model: {e}')
        return None, False


def _heuristic_predict_charging_time(current: float, target: float, 
                                     battery_health: float = 100.0,
                                     temperature: float = 25.0,
                                     charger_type: str = 'standard',
                                     battery_capacity_wh: float = 1440.0) -> dict:
    """Fallback heuristic charging time prediction."""
    result = _predict_charging_time(current, target, battery_health, temperature, 
                                    charger_type, battery_capacity_wh)
    # Convert minutes to seconds for consistent output
    estimated_sec = result['estimatedMinutes'] * 60
    return {
        'predictedDurationSec': estimated_sec,
        'predictedDurationMin': estimated_sec / 60.0,
        'formattedDuration': result['formattedTime'],
        'chargeRatePercentPerHour': result['chargeRatePercentPerHour'],
        'chargeGainPercent': result['chargeGainPercent'],
        'energyNeededWh': result['energyNeededWh'],
        'chargePowerW': result['chargePowerW'],
        'recommendations': result['recommendations'],
        'confidence': result['confidence'],
        'chargingCurve': result['chargingCurve'],
        'factors': result['factors'],
    }


def _guardrail_check(ai_result: dict, heuristic_result: dict, 
                     current: float, target: float) -> tuple[dict, str]:
    """Check AI result against guardrails. Returns (result, source)."""
    predicted_sec = ai_result.get('predictedDurationSec', 0)
    
    # Guardrail conditions
    if math.isnan(predicted_sec) or predicted_sec <= 0:
        return heuristic_result, 'heuristic_guardrail_nan'
    if predicted_sec < 300:  # < 5 minutes
        return heuristic_result, 'heuristic_guardrail_too_short'
    if predicted_sec > 43200:  # > 12 hours
        return heuristic_result, 'heuristic_guardrail_too_long'
    
    # Compare with heuristic - if deviation too large (>50%), use heuristic
    heuristic_sec = heuristic_result['predictedDurationSec']
    if heuristic_sec > 0:
        deviation_ratio = abs(predicted_sec - heuristic_sec) / heuristic_sec
        if deviation_ratio > 0.5:  # > 50% deviation
            return heuristic_result, 'heuristic_guardrail_deviation'
    
    return ai_result, 'ai_model'


@app.route('/api/ai/predict-charging-time', methods=['POST'])
def ai_predict_charging_time():
    """Predict charging time — uses AI Center model with heuristic fallback.
    
    Request: { vehicleId, currentBattery, targetBattery, ambientTempC? }
    Response: { predictedDurationSec, predictedDurationMin, formattedDuration,
                modelSource, modelVersion, isBeta, confidence, warnings, ... }
    """
    body = request.get_json() or {}
    current = float(body.get('currentBattery', 20))
    target = float(body.get('targetBattery', 80))
    ambient_temp_c = float(body.get('ambientTempC', 25.0))
    
    # For fallback heuristic
    health = float(body.get('batteryHealth', 100))
    charger = body.get('chargerType', 'standard')
    capacity = float(body.get('batteryCapacityWh', 1440))

    # Validation
    if current < 0 or current > 100 or target < 0 or target > 100:
        return jsonify({'success': False, 'error': 'Battery % phải từ 0 đến 100'}), 400
    if current >= target:
        return jsonify({'success': False, 'error': 'Target phải lớn hơn current battery'}), 400

    try:
        # Try AI model first
        ai_result, ai_success = _ai_predict_charging_time(current, target, ambient_temp_c)
        
        # Always compute heuristic for comparison and fallback
        heuristic_result = _heuristic_predict_charging_time(current, target, health, 
                                                              ambient_temp_c, charger, capacity)
        
        if ai_success:
            # Apply guardrails
            final_result, source = _guardrail_check(ai_result, heuristic_result, current, target)
            warnings = list(ai_result.get('warnings', []))
            if source != 'ai_model':
                warnings.append(f'AI output bị chặn bởi guardrail, dùng {source}')
        else:
            # AI failed, use heuristic
            final_result = heuristic_result
            source = 'heuristic_fallback'
            warnings = ['AI model không khả dụng, dùng heuristic']
        
        # Build standardized response
        response_data = {
            'predictedDurationSec': round(final_result['predictedDurationSec'], 1),
            'predictedDurationMin': round(final_result['predictedDurationMin'], 1),
            'formattedDuration': final_result['formattedDuration'],
            'modelSource': source,
            'modelVersion': final_result.get('modelVersion', 'heuristic-v1'),
            'isBeta': True,
            'confidence': final_result.get('confidence', 70.0),
            'warnings': warnings,
            'analyzedAt': _utcnow(),
            # Backward compat fields
            'estimatedMinutes': round(final_result['predictedDurationMin'], 1),
            'formattedTime': final_result['formattedDuration'],
        }
        
        # Include heuristic details if using fallback
        if source != 'ai_model':
            response_data['heuristicDetails'] = {
                'chargeRatePercentPerHour': heuristic_result['chargeRatePercentPerHour'],
                'chargeGainPercent': heuristic_result['chargeGainPercent'],
                'energyNeededWh': heuristic_result['energyNeededWh'],
                'chargePowerW': heuristic_result['chargePowerW'],
                'recommendations': heuristic_result['recommendations'],
            }
        
        return jsonify({'success': True, 'data': response_data})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


# Backward-compat: redirect old AI endpoints (ai_api.py used /api/ prefix)
@app.route('/api/predict-degradation', methods=['POST'])
def compat_predict():
    return ai_predict()


@app.route('/api/predict-consumption', methods=['POST'])
def compat_predict_consumption():
    return ai_predict_consumption()


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
# AI VEHICLE INSIGHTS — Web-managed cache for app
# ═══════════════════════════════════════════════════════════════
def _build_vehicle_insight(vehicle_id: str) -> dict:
    """Build composite AiVehicleInsights document from profile + charge/trip data."""
    profile = _get_profile(vehicle_id)
    if not profile or not profile.get('trainedAt'):
        return None

    # Fetch charge logs for degradation prediction
    charge_logs = []
    owner_uid = None
    if _fs():
        docs = list(
            _fs().collection('ChargeLogs')
            .where('vehicleId', '==', vehicle_id)
            .where('isDeleted', '==', False)
            .stream()
        )
        for d in docs:
            rec = d.to_dict()
            charge_logs.append(rec)
            if not owner_uid:
                owner_uid = rec.get('ownerUid')

    if not owner_uid and _fs():
        vdoc = _fs().collection('Vehicles').document(vehicle_id).get()
        if vdoc.exists:
            owner_uid = vdoc.to_dict().get('ownerUid')

    # Run models
    pred = degradation_model.predict_degradation(charge_logs) if len(charge_logs) >= 3 else {}
    patt = pattern_analyzer.analyze(charge_logs) if len(charge_logs) >= 3 else {}

    adj = profile.get('healthAdjustment', 0)
    raw_score = pred.get('healthScore', 100.0)
    health = round(max(0, min(100, raw_score + adj)), 1)

    if health >= 80:
        status = 'Tốt'
    elif health >= 60:
        status = 'Khá'
    elif health >= 40:
        status = 'Trung bình'
    else:
        status = 'Cần thay pin'

    insight = {
        'vehicleId': vehicle_id,
        'ownerUid': owner_uid or '',
        'hasTrained': True,
        'trainedAt': profile.get('trainedAt'),
        'profileVersion': profile.get('version', '2.0'),
        'dataPoints': profile.get('dataPoints', 0),
        'healthAdjustment': adj,
        'healthScore': health,
        'healthStatus': status,
        'estimatedLifeMonths': pred.get('estimatedLifeMonths'),
        'confidence': round(pred.get('confidence', 0), 1),
        'peakChargingHour': patt.get('peakChargingHour'),
        'peakChargingDay': patt.get('peakChargingDay'),
        'chargeFrequencyPerWeek': patt.get('chargeFrequencyPerWeek'),
        'avgSessionDuration': patt.get('avgSessionDuration'),
        'recommendations': pred.get('recommendations', []),
        'equivalentCycles': pred.get('equivalentCycles'),
        'remainingCycles': pred.get('remainingCycles'),
        'avgDoD': pred.get('avgDoD'),
        'avgChargeRate': pred.get('avgChargeRate'),
        'patterns': patt.get('patterns', []),
        'lastInferenceAt': _utcnow(),
        'lastInferenceStatus': 'ok',
        'lastInferenceError': None,
        'updatedAt': _utcnow(),
        'schemaVersion': 'insight-v1',
    }
    return insight


def _write_vehicle_insight(vehicle_id: str, insight: dict):
    """Write AiVehicleInsights doc to Firestore."""
    if not _fs():
        return False
    try:
        _fs().collection('AiVehicleInsights').document(vehicle_id).set(insight, merge=True)
        return True
    except Exception as e:
        print(f'\u26a0 Failed to write insight for {vehicle_id}: {e}')
        return False


def _refresh_vehicle_insight(vehicle_id: str) -> tuple:
    """Build + write insight. Returns (success: bool, error: str|None)."""
    try:
        insight = _build_vehicle_insight(vehicle_id)
        if not insight:
            return False, 'No trained profile found'
        ok = _write_vehicle_insight(vehicle_id, insight)
        return ok, None if ok else 'Firestore write failed'
    except Exception as e:
        # Write error status
        if _fs():
            try:
                _fs().collection('AiVehicleInsights').document(vehicle_id).set({
                    'vehicleId': vehicle_id,
                    'lastInferenceAt': _utcnow(),
                    'lastInferenceStatus': 'error',
                    'lastInferenceError': str(e),
                    'updatedAt': _utcnow(),
                }, merge=True)
            except Exception:
                pass
        return False, str(e)


@app.route('/api/admin/ai/refresh-insights', methods=['POST'])
@require_admin
def ai_refresh_insights():
    """Manually refresh AiVehicleInsights for a specific vehicle."""
    data = request.get_json() or {}
    vehicle_id = data.get('vehicleId', '')
    if not vehicle_id:
        return jsonify({'success': False, 'error': 'vehicleId là bắt buộc'}), 400

    ok, err = _refresh_vehicle_insight(vehicle_id)
    if ok:
        _audit('ai_refresh_insights', 'AiVehicleInsights', vehicle_id,
               request._uid, request._email)
        return jsonify({'success': True, 'message': f'Insight refreshed cho {vehicle_id}'})
    return jsonify({'success': False, 'error': err or 'Refresh failed'}), 400


@app.route('/api/admin/ai/status', methods=['GET'])
@require_admin
def ai_center_status():
    """KPI vận hành cơ bản cho AI Center."""
    profile_count = 0
    insight_count = 0
    last_refresh = None

    if _fs():
        try:
            profile_count = len(list(_fs().collection('AiVehicleProfiles').limit(100).stream()))
        except Exception:
            pass
        try:
            insight_docs = list(
                _fs().collection('AiVehicleInsights')
                .order_by('updatedAt', direction='DESCENDING')
                .limit(1)
                .stream()
            )
            insight_count = len(list(_fs().collection('AiVehicleInsights').limit(100).stream()))
            if insight_docs:
                last_doc = insight_docs[0].to_dict()
                last_refresh = last_doc.get('updatedAt')
        except Exception:
            pass

    return jsonify({
        'success': True,
        'data': {
            'consumptionModel': {
                'status': _consumption_model_status,
                'available': _consumption_model is not None,
                'error': _consumption_model_error,
            },
            'firebase': {
                'connected': _firebase_available,
            },
            'profileCount': profile_count,
            'insightCount': insight_count,
            'lastRefresh': last_refresh,
        },
    })


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
# SOC PREDICTION ENDPOINTS — proxy to FastAPI AI server
# ═══════════════════════════════════════════════════════════════
try:
    import requests as _http
except Exception:
    _http = None

AI_SERVER_URL = os.environ.get('AI_SERVER_URL', 'http://127.0.0.1:8001').rstrip('/')
AI_SERVER_TOKEN = os.environ.get('AI_SERVER_INTERNAL_TOKEN', 'dev-local-token')
AI_SERVER_TIMEOUT = float(os.environ.get('AI_SERVER_TIMEOUT', '15'))


def _ai_headers(extra=None):
    h = {'X-Internal-Token': AI_SERVER_TOKEN}
    if extra:
        h.update(extra)
    return h


def _ai_proxy_json(method, path, *, json_body=None, params=None):
    """Forward JSON request to FastAPI; surface upstream status/body."""
    if _http is None:
        return jsonify({'success': False, 'error': 'requests library not installed'}), 500
    url = f'{AI_SERVER_URL}{path}'
    try:
        resp = _http.request(
            method, url,
            json=json_body, params=params,
            headers=_ai_headers({'Content-Type': 'application/json'}) if json_body is not None else _ai_headers(),
            timeout=AI_SERVER_TIMEOUT,
        )
    except Exception as e:
        return jsonify({'success': False, 'error': f'AI server unavailable: {e}'}), 502
    try:
        data = resp.json()
    except Exception:
        return jsonify({'success': False, 'error': f'invalid AI server response (HTTP {resp.status_code})'}), 502
    return jsonify(data), resp.status_code


@app.route('/api/soc/predict', methods=['POST'])
def soc_predict():
    """Predict SOC — delegated to FastAPI; contract unchanged for callers."""
    body = request.get_json() or {}
    resp, status_code = _ai_proxy_json('POST', '/v1/soc/predict', json_body=body)
    # Mirror legacy side effect: persist to Firestore when successful.
    if status_code == 200 and _firestore_db:
        try:
            payload = resp.get_json()
            if payload and payload.get('success'):
                _firestore_db.collection('soc_predictions').add({
                    'input': body,
                    'result': payload.get('data'),
                    'createdAt': datetime.now(timezone.utc),
                })
        except Exception as e:
            print(f'⚠️ Failed to save SOC prediction: {e}')
    return resp, status_code


@app.route('/api/soc/status', methods=['GET'])
def soc_status():
    """Proxy AI server status."""
    return _ai_proxy_json('GET', '/v1/soc/status')


# ── Admin Model Management (proxy, per-type) ─────────────────────
@app.route('/api/admin/ai/types', methods=['GET'])
@require_admin
def admin_ai_types():
    """List registered model types with status."""
    return _ai_proxy_json('GET', '/v1/types')


@app.route('/api/admin/ai/models/<type_key>', methods=['GET'])
@require_admin
def admin_list_models_for_type(type_key):
    return _ai_proxy_json('GET', f'/v1/models/{type_key}')


@app.route('/api/admin/ai/models/<type_key>/status', methods=['GET'])
@require_admin
def admin_status_for_type(type_key):
    return _ai_proxy_json('GET', f'/v1/models/{type_key}/status')


@app.route('/api/admin/ai/models/<type_key>/rollback', methods=['POST'])
@require_admin
def admin_rollback_model_for_type(type_key):
    return _ai_proxy_json('POST', f'/v1/models/{type_key}/rollback', json_body=request.get_json() or {})


@app.route('/api/admin/ai/models/<type_key>/load-active', methods=['POST'])
@require_admin
def admin_load_active_model(type_key):
    """Ensure the active model version is loaded into memory."""
    return _ai_proxy_json('POST', f'/v1/models/{type_key}/load-active')


@app.route('/api/admin/ai/models/<type_key>/deactivate', methods=['POST'])
@require_admin
def admin_deactivate_model(type_key):
    """Deactivate the current active model (clear active version)."""
    return _ai_proxy_json('POST', f'/v1/models/{type_key}/deactivate')


@app.route('/api/admin/ai/models/<type_key>/validate-version', methods=['POST'])
@require_admin
def admin_validate_version(type_key):
    """Validate a version can be loaded without activating it."""
    return _ai_proxy_json('POST', f'/v1/models/{type_key}/validate-version', json_body=request.get_json() or {})


@app.route('/api/admin/ai/models/<type_key>/predict', methods=['POST'])
@require_admin
def admin_quick_predict(type_key):
    """Admin-facing quick prediction for testing a model from the UI."""
    return _ai_proxy_json('POST', f'/v1/models/{type_key}/predict', json_body=request.get_json() or {})


# NOTE: This generic /<version> route MUST come after all specific routes
# to avoid shadowing paths like /deactivate, /validate-version, etc.
@app.route('/api/admin/ai/models/<type_key>/<version>', methods=['DELETE'])
@require_admin
def admin_delete_model_for_type(type_key, version):
    return _ai_proxy_json('DELETE', f'/v1/models/{type_key}/{version}')


@app.route('/api/admin/ai/models/<type_key>/upload', methods=['POST'])
@require_admin
def admin_upload_model_for_type(type_key):
    """Forward multipart upload to FastAPI (per type)."""
    if _http is None:
        return jsonify({'success': False, 'error': 'requests library not installed'}), 500
    if 'file' not in request.files:
        return jsonify({'success': False, 'error': 'file field is required'}), 400
    upload = request.files['file']
    version = (request.form.get('version') or '').strip()
    note = request.form.get('note') or ''
    if not version:
        return jsonify({'success': False, 'error': 'version field is required'}), 400

    files = {'file': (upload.filename or 'model.pkl', upload.stream, upload.mimetype or 'application/octet-stream')}
    skip_smoke = request.form.get('skipSmokeTest') or 'false'
    data = {'version': version, 'note': note, 'skipSmokeTest': skip_smoke}
    try:
        resp = _http.post(
            f'{AI_SERVER_URL}/v1/models/{type_key}/upload',
            files=files, data=data, headers=_ai_headers(),
            timeout=max(AI_SERVER_TIMEOUT, 60),
        )
    except Exception as e:
        return jsonify({'success': False, 'error': f'AI server unavailable: {e}'}), 502

    # Audit log
    try:
        if _firestore_db:
            _firestore_db.collection('AuditLogs').add({
                'action': 'ai.model.upload',
                'type': type_key,
                'version': version,
                'note': note,
                'status': resp.status_code,
                'actor': getattr(request, 'user_email', None) or 'unknown',
                'timestamp': datetime.now(timezone.utc),
            })
    except Exception:
        pass

    try:
        return jsonify(resp.json()), resp.status_code
    except Exception:
        return jsonify({'success': False, 'error': f'invalid AI server response (HTTP {resp.status_code})'}), 502


# ── Legacy (type=soc) aliases kept for backward compat ────────────
@app.route('/api/admin/ai/models', methods=['GET'])
@require_admin
def admin_list_models_legacy():
    return _ai_proxy_json('GET', '/v1/models/soc')


@app.route('/api/admin/ai/models/rollback', methods=['POST'])
@require_admin
def admin_rollback_legacy():
    return _ai_proxy_json('POST', '/v1/models/soc/rollback', json_body=request.get_json() or {})


@app.route('/api/admin/ai/models/upload', methods=['POST'])
@require_admin
def admin_upload_model_legacy():
    return admin_upload_model_for_type('soc')

@app.route('/api/soc/history', methods=['GET'])
def soc_history():
    """Get SOC prediction history for a vehicle."""
    try:
        vehicle_id = request.args.get('vehicleId')
        limit = int(request.args.get('limit', 10))
        
        if not vehicle_id:
            return jsonify({
                'success': False,
                'error': 'vehicleId parameter required'
            }), 400
        
        if not _firestore_db:
            return jsonify({
                'success': False,
                'error': 'Firestore not available'
            }), 503
        
        # Get predictions from Firestore
        docs = (_firestore_db.collection('soc_predictions')
                .order_by('createdAt', direction='DESCENDING')
                .limit(limit)
                .get())
        
        predictions = []
        for doc in docs:
            data = doc.to_dict()
            if 'result' in data:
                predictions.append(data['result'])
        
        return jsonify({
            'success': True,
            'data': {
                'vehicleId': vehicle_id,
                'predictions': predictions,
                'count': len(predictions)
            }
        })
        
    except Exception as e:
        print(f'❌ SOC history error: {e}')
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


# ═══════════════════════════════════════════════════════════════
# TRIP PREDICTION ENDPOINTS
# ═══════════════════════════════════════════════════════════════
@app.route('/api/trip/predict', methods=['POST'])
def trip_predict():
    """Predict battery consumption for a trip using AI or heuristic."""
    try:
        body = request.get_json() or {}
        
        # Validate required fields
        required_fields = ['vehicleId', 'from', 'to', 'distance', 'currentBattery']
        for field in required_fields:
            if field not in body:
                return jsonify({
                    'success': False,
                    'error': f'Missing required field: {field}'
                }), 400
        
        vehicle_id = body['vehicleId']
        from_location = body['from']
        to_location = body['to']
        distance = float(body['distance'])
        current_battery = float(body['currentBattery'])
        temperature = float(body.get('temperature', 25.0))
        rider_weight = float(body.get('riderWeight', 70.0))
        weather = body.get('weather', 'sunny')
        
        # Validate ranges
        if distance <= 0:
            return jsonify({
                'success': False,
                'error': 'Distance must be greater than 0'
            }), 400
            
        if not (0 <= current_battery <= 100):
            return jsonify({
                'success': False,
                'error': 'Current battery must be between 0 and 100'
            }), 400
        
        # Calculate prediction
        prediction = _calculate_trip_prediction(
            distance=distance,
            current_battery=current_battery,
            temperature=temperature,
            rider_weight=rider_weight,
            weather=weather
        )
        
        # Create response
        result = {
            'vehicleId': vehicle_id,
            'from': from_location,
            'to': to_location,
            'distance': distance,
            'predictedConsumption': prediction['consumption'],
            'predictedEndBattery': prediction['end_battery'],
            'estimatedDuration': prediction['duration'],
            'isSafe': prediction['is_safe'],
            'reasoningText': prediction['reasoning_text'],
            'reasoningScore': prediction['reasoning_score'],
            'confidence': prediction['confidence'],
            'weather': weather,
            'temperature': temperature,
            'riderWeight': rider_weight,
            'timestamp': datetime.now(timezone.utc).isoformat(),
            'status': 'planned'
        }
        
        # Store prediction in Firestore if available
        if _firestore_db:
            try:
                doc_ref = _firestore_db.collection('trip_predictions').add({
                    'vehicleId': vehicle_id,
                    'from': from_location,
                    'to': to_location,
                    'distance': distance,
                    'duration': prediction['duration'],
                    'consumption': prediction['consumption'],
                    'reasoning': prediction['reasoning_score'],
                    'reasoningText': prediction['reasoning_text'],
                    'confidence': prediction['confidence'],
                    'startBattery': current_battery,
                    'endBattery': prediction['end_battery'],
                    'isSafe': prediction['is_safe'],
                    'weather': weather,
                    'temperature': temperature,
                    'riderWeight': rider_weight,
                    'timestamp': datetime.now(timezone.utc),
                    'status': 'planned'
                })
                print(f'✅ Trip prediction saved: {doc_ref[1].id}')
            except Exception as e:
                print(f'⚠️ Failed to save trip prediction: {e}')
        
        return jsonify({
            'success': True,
            'data': result
        })
        
    except Exception as e:
        print(f'❌ Trip prediction error: {e}')
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

@app.route('/api/trip/history', methods=['GET'])
def trip_history():
    """Get trip prediction history for a vehicle."""
    try:
        vehicle_id = request.args.get('vehicleId')
        limit = int(request.args.get('limit', 10))
        
        if not vehicle_id:
            return jsonify({
                'success': False,
                'error': 'vehicleId parameter required'
            }), 400
        
        if not _firestore_db:
            return jsonify({
                'success': False,
                'error': 'Firestore not available'
            }), 503
        
        # Get predictions from Firestore
        docs = (_firestore_db.collection('trip_predictions')
                .where('vehicleId', '==', vehicle_id)
                .order_by('timestamp', direction='DESCENDING')
                .limit(limit)
                .get())
        
        predictions = []
        for doc in docs:
            data = doc.to_dict()
            predictions.append({
                'id': doc.id,
                **data
            })
        
        return jsonify({
            'success': True,
            'data': {
                'vehicleId': vehicle_id,
                'predictions': predictions,
                'count': len(predictions)
            }
        })
        
    except Exception as e:
        print(f'❌ Trip history error: {e}')
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

def _calculate_trip_prediction(distance, current_battery, temperature, rider_weight, weather):
    """Calculate trip prediction using AI or heuristic."""
    
    # Base consumption: 0.8% per km for VinFast Feliz Neo
    base_consumption = distance * 0.8
    
    # Temperature factor
    temp_factor = 1.0
    if temperature < 10:
        temp_factor = 1.2  # Cold weather increases consumption
    elif temperature > 35:
        temp_factor = 1.1  # Hot weather increases consumption
    
    # Weight factor
    weight_factor = 1.0 + ((rider_weight - 70) / 70) * 0.3  # 30% more for every 70kg above base
    
    # Weather factor
    weather_factor = 1.0
    if weather.lower() in ['rain', 'mưa']:
        weather_factor = 1.3
    elif weather.lower() in ['cloudy', 'nhiều mây']:
        weather_factor = 1.1
    
    # Calculate final consumption
    consumption = base_consumption * temp_factor * weight_factor * weather_factor
    consumption = round(consumption, 2)
    
    # Calculate end battery
    end_battery = max(0, current_battery - consumption)
    
    # Calculate duration (average speed 30 km/h)
    duration = int((distance / 30) * 60)
    
    # Check if safe
    is_safe = end_battery > 15
    
    # Generate reasoning text
    temp_desc = 'thời tiết lạnh' if temperature < 10 else 'thời tiết nóng' if temperature > 35 else 'thời tiết lý tưởng'
    weight_desc = 'nặng' if rider_weight > 80 else 'nhẹ' if rider_weight < 60 else 'trung bình'
    weather_desc = 'mưa' if weather.lower() in ['rain', 'mưa'] else 'nhiều mây' if weather.lower() in ['cloudy', 'nhiều mây'] else 'nắng'
    
    reasoning_text = f'Dự đoán dựa trên quãng đường {distance}km với {temp_desc}, trọng lượng {weight_desc} và thời tiết {weather_desc}. Tiêu hao pin ước tính là {consumption}%.'
    
    return {
        'consumption': consumption,
        'end_battery': end_battery,
        'duration': duration,
        'is_safe': is_safe,
        'reasoning_text': reasoning_text,
        'reasoning_score': 0.8,
        'confidence': 0.85
    }

# ═══════════════════════════════════════════════════════════════
# WEB SYNC ENDPOINTS
# ═══════════════════════════════════════════════════════════════
@app.route('/api/web/sync/battery-state', methods=['POST'])
def web_sync_battery_state():
    """Sync battery state from mobile app to web dashboard."""
    try:
        body = request.get_json() or {}
        
        if not _firestore_db:
            return jsonify({
                'success': False,
                'error': 'Firestore not available'
            }), 503
        
        # Store battery state
        doc_ref = _firestore_db.collection('battery_states').add({
            **body,
            'syncedAt': datetime.now(timezone.utc),
            'source': 'mobile_app'
        })
        
        print(f'✅ Battery state synced from mobile: {doc_ref[1].id}')
        
        return jsonify({
            'success': True,
            'data': {
                'id': doc_ref[1].id,
                'syncedAt': datetime.now(timezone.utc).isoformat()
            }
        })
        
    except Exception as e:
        print(f'❌ Battery sync error: {e}')
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

@app.route('/api/web/sync/trip-prediction', methods=['POST'])
def web_sync_trip_prediction():
    """Sync trip prediction from mobile app to web dashboard."""
    try:
        body = request.get_json() or {}
        
        if not _firestore_db:
            return jsonify({
                'success': False,
                'error': 'Firestore not available'
            }), 503
        
        # Store trip prediction
        doc_ref = _firestore_db.collection('trip_predictions').add({
            **body,
            'syncedAt': datetime.now(timezone.utc),
            'source': 'mobile_app'
        })
        
        print(f'✅ Trip prediction synced from mobile: {doc_ref[1].id}')
        
        return jsonify({
            'success': True,
            'data': {
                'id': doc_ref[1].id,
                'syncedAt': datetime.now(timezone.utc).isoformat()
            }
        })
        
    except Exception as e:
        print(f'❌ Trip prediction sync error: {e}')
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

# ═══════════════════════════════════════════════════════════════
# RUN
# ═══════════════════════════════════════════════════════════════
if __name__ == '__main__':
    print('\n⚡ VinFast Battery — Unified API Server v4.1')
    print('📡 Endpoints:')
    print('   Auth:   GET /api/auth/me, POST /api/auth/set-admin')
    print('   User:   GET /api/user/vehicles|charge-logs|trip-logs|maintenance')
    print('   Admin:  CRUD /api/admin/<entity>, /api/admin/users, /api/admin/audit-logs')
    print('   Export: GET /api/admin/export?entity=&format=json|csv')
    print('   Import: POST /api/admin/import?entity=&mode=upsert')
    print('   AI:     /api/ai/predict-degradation|predict-consumption|analyze-patterns|train-vehicle-profile')
    print('   Admin AI: /api/admin/ai/normalize-dataset|train|test')
    print('   SOC:    /api/soc/predict|status|history  (proxy → AI server)')
    print('   Models: GET/POST /api/admin/ai/models[/upload|/rollback|/<ver>]')
    print('   Trip:   /api/trip/predict|history')
    print('   Sync:   /api/web/sync/battery-state|trip-prediction')
    print('   Legacy: POST /api/admin/migrate-legacy')
    print(f'   AI server URL: {AI_SERVER_URL}')
    print(f'   Consumption model: {_consumption_model_status}')
    print(f'🌐 http://localhost:5000\n')
    debug_mode = os.environ.get('FLASK_DEBUG', '1').lower() in ('1', 'true', 'yes')
    use_reloader = os.environ.get('FLASK_USE_RELOADER', '0').lower() in ('1', 'true', 'yes')
    app.run(debug=debug_mode, use_reloader=use_reloader, host='0.0.0.0', port=5000)
