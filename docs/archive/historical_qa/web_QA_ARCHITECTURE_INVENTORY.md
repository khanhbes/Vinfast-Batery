# VinFast Battery Web — Master Architecture & Route Inventory

**Audit Snapshot Metadata:**
- **Repository:** `https://github.com/khanhbes/Vinfast-Batery`
- **Branch:** `qa/web-master-audit-2026-09-07`
- **Base Commit SHA:** `37256f0` (baseline commit from App audit)
- **Dirty State:** Clean (excluding test harness and audit artifacts)
- **Audit Date:** 2026-09-08
- **Environment Tools:**
  - Python: `3.12.10` (system) / Python `3.12.10` (`web/.venv`)
  - Node: `v24.14.1`
  - npm: `11.11.0`
  - Docker Engine: `29.7.2, build a7dcaa6`
  - Docker Compose: `v5.4.0`

---

## 1. System Overview & Component Topology

```text
                                       ┌──────────────────────────────────────────────┐
                                       │              CLIENT LAYER                    │
                                       │  - React 18 / Vite Admin Dashboard (Web)    │
                                       │  - Flutter Mobile App (Android/iOS)          │
                                       └──────────────────────┬───────────────────────┘
                                                              │
                                            HTTPS / Tailscale │ (Port 80/443 or 8080/5000)
                                                              ▼
                                       ┌──────────────────────────────────────────────┐
                                       │          REVERSE PROXY / INGRESS             │
                                       │  - Caddy 2.10 (prod) / Caddyfile.laptop      │
                                       │  - SSL Termination / Header Injection        │
                                       └──────────────────────┬───────────────────────┘
                                                              │
                                            Reverse Proxy     │ HTTP loopback:5000
                                                              ▼
                                       ┌──────────────────────────────────────────────┐
                                       │          UNIFIED FLASK API (server.py)       │
                                       │  - Firebase Auth Token Verification          │
                                       │  - RBAC Middleware (user / admin)            │
                                       │  - CRUD for Vehicles, Trips, ChargeLogs      │
                                       │  - Smart Charge Service Integration          │
                                       │  - App Remote Config & OTA APK Download      │
                                       └───────────┬──────────────────────┬───────────┘
                                                   │                      │
                                 gRPC / REST       │                      │ HTTP (internal network)
                                 (Service Account) │                      │ Port 8001
                                                   ▼                      ▼
                     ┌────────────────────────────────┐   ┌────────────────────────────────┐
                     │    FIREBASE / FIRESTORE        │   │    FASTAPI AI SERVICE          │
                     │  - Users, Vehicles, ChargeLogs │   │    (web/ai_server/main.py)     │
                     │  - TripLogs, Maintenance       │   │  - ModelStore & Registry       │
                     │  - TelemetryPoints             │   │  - ModelRuntime (Joblib/PKL)   │
                     │  - AuditLogs, ChargeFeedback   │   │  - PredictionService (SOC/DTE) │
                     └────────────────────────────────┘   └────────────────────────────────┘
```

---

## 2. Trust Boundaries & Threat Analysis

### Boundary 1: Browser / Mobile App ➔ Reverse Proxy (Caddy / Ingress)
- **Protocols:** HTTPS / HTTP
- **Authentication:** None at proxy level; passthrough to Flask backend.
- **Untrusted Input:** Headers (`Authorization`, `X-Admin-Key`, `Idempotency-Key`), JSON bodies, query strings.
- **Risks:** Weak TLS ciphers, missing CORS restrictions, missing security headers (`X-Content-Type-Options`, `Content-Security-Policy`), request size flooding.

### Boundary 2: Reverse Proxy ➔ Flask Unified API (`server.py`)
- **Protocols:** HTTP over Docker Bridge (`vinfast_net`) or local loopback (`127.0.0.1:5000`).
- **Identity Model:**
  - Bearer Firebase ID Token (`_verify_token`).
  - Hardcoded or static environment key `X-Admin-Key` matching `DEV_ADMIN_KEY`.
  - Email allowlist (`ADMIN_EMAILS`).
- **Critical Vulnerability Vectors:**
  - `DEV_ADMIN_KEY` bypasses all authentication, granting instantaneous `admin` role without Firebase validation.
  - `ADMIN_EMAILS=*` promotes all authenticated users to full administrator.
  - Multiple `/api/ai/*` and `/api/web/sync/*` endpoints lack any authentication decorators (`@require_auth` or `@require_admin`), allowing unauthenticated read/write/tamper access.
  - IDOR in `/api/web/sync/vehicle` and `/api/web/sync/full`: overwrites existing documents belonging to other users without ownership verification.

### Boundary 3: Flask API ➔ FastAPI AI Server (`ai_server/main.py`)
- **Protocols:** Internal HTTP (`http://ai:8001` or `http://localhost:8001`).
- **Identity Model:** Shared secret header `X-Internal-Token` matching `AI_SERVER_INTERNAL_TOKEN`.
- **Critical Vulnerability Vectors:**
  - If `AI_SERVER_INTERNAL_TOKEN` is unset in non-production, token check is bypassed entirely.
  - Model uploads via `/v1/models/{type}/upload` accept raw files and deserialize them using `joblib.load` and `pickle.load` (RCE risk).
  - Lack of strict path sanitization on `version` parameter in `ModelStore.path_of` enables directory traversal.

### Boundary 4: Flask API ➔ Firebase / Firestore
- **Protocols:** Google Cloud APIs / gRPC using `google-auth` service account credentials.
- **Credentials:** `FIREBASE_CREDENTIALS_JSON` environment variable or local `serviceAccountKey.json`.
- **Critical Vulnerability Vectors:**
  - Leakage of Base64 private keys via Docker Compose environment variables and stdout logs.
  - Fail-open fallback: when Firebase is unavailable, some services fall back to in-memory local data without persisting, leading to state inconsistencies.

---

## 3. Flask Route Inventory (`web/server.py`)

| Method | Endpoint | Handler | Decorator / Auth | Intended Role | Description & Side Effects |
|--------|----------|---------|------------------|---------------|-----------------------------|
| GET | `/` | `open_dashboard` | None | Public | Redirects to `/dashboard` |
| GET | `/dashboard` | `open_dashboard` | None | Public | Serves React dashboard HTML |
| GET | `/api/health` | `health_check` | None | Public | Returns system health (Firebase, AI, Model) |
| GET | `/api/auth/me` | `auth_me` | `@require_auth` | User/Admin | Returns caller UID, email, role |
| POST | `/api/auth/set-admin` | `set_admin` | `@require_admin` | Admin | Sets custom claims for user in Firebase Auth |
| GET | `/api/user/vehicles` | `user_vehicles` | `@require_auth` | User | Lists vehicles owned by caller UID |
| POST | `/api/user/vehicles` | `user_add_vehicle` | `@require_auth` | User | Inserts new vehicle stamped with caller UID |
| GET | `/api/user/charge-logs` | `user_charge_logs` | `@require_auth` | User | Lists charging logs filtered by caller UID |
| GET | `/api/user/trip-logs` | `user_trip_logs` | `@require_auth` | User | Lists trip logs filtered by caller UID |
| GET | `/api/user/maintenance` | `user_maintenance` | `@require_auth` | User | Lists maintenance tasks filtered by caller UID |
| GET | `/api/admin/users` | `admin_users` | `@require_admin` | Admin | Lists all users from Firebase Auth / Firestore |
| GET | `/api/admin/audit-logs` | `admin_audit_logs` | `@require_admin` | Admin | Lists system audit trail entries |
| GET | `/api/admin/export` | `admin_export` | `@require_admin` | Admin | Exports collection records (CSV / JSON) |
| POST | `/api/admin/import` | `admin_import` | `@require_admin` | Admin | Bulk upserts data into Firestore |
| GET | `/api/admin/<entity>` | `admin_list_entity` | `@require_admin` | Admin | Generic entity lister for admin table |
| POST | `/api/admin/<entity>` | `admin_create_entity`| `@require_admin`| Admin | Creates arbitrary entity record |
| PUT | `/api/admin/<entity>/<id>`| `admin_update_entity`| `@require_admin`| Admin | Updates arbitrary entity record |
| DELETE| `/api/admin/<entity>/<id>`| `admin_delete_entity`| `@require_admin`| Admin | Soft/Hard deletes entity record |
| POST | `/api/admin/migrate` | `admin_migrate_collections` | `@require_admin` | Admin | Migrates collections schema |
| POST | `/api/admin/migrate-legacy`| `migrate_legacy` | `@require_admin` | Admin | Migrates legacy data formats |
| GET | `/api/admin/ai/status` | `ai_center_status` | `@require_admin` | Admin | Returns status of all AI models |
| GET | `/api/admin/ai/types` | `admin_ai_types` | `@require_admin` | Admin | Lists registered model types |
| GET | `/api/admin/ai/models/<type_key>` | `admin_list_models_for_type` | `@require_admin` | Admin | Lists versions for model type |
| POST | `/api/admin/ai/models/<type_key>/deploy` | `admin_deploy_model` | `@require_admin` | Admin | Deploys/activates model version |
| POST | `/api/admin/ai/models/<type_key>/rollback` | `admin_rollback_model_for_type` | None (BUG) | Admin (Untrusted) | Rolls back model version |
| POST | `/api/admin/ai/models/<type_key>/reset` | `admin_reset_model` | `@require_admin` | Admin | Resets all versions for model type |
| POST | `/api/admin/ai/models/<type_key>/upload` | `admin_upload_model` | None (BUG) | Admin (Untrusted) | Uploads candidate model artifact |
| DELETE| `/api/admin/ai/models/<type_key>/<version>` | `admin_delete_model_for_type` | `@require_admin` | Admin | Deletes inactive model version |
| POST | `/api/admin/ai/models/<type_key>/test-version` | `admin_test_version` | `@require_admin` | Admin | Runs test prediction on candidate |
| POST | `/api/admin/ai/models/<type_key>/predict` | `admin_quick_predict` | `@require_admin` | Admin | Executes quick prediction |
| GET | `/api/user/ai/models` | `user_ai_models` | None (`_require_user_or_admin`) | User/Admin | Lists models catalog with flat schema |
| GET | `/api/user/ai/models/<type_key>/download` | `user_ai_model_download` | None (`_require_user_or_admin`) | User/Admin | Downloads `.tflite` model artifact |
| POST | `/api/user/ai/models/<type_key>/predict` | `user_ai_model_predict` | None (`_require_user_or_admin`) | User/Admin | Server-side proxy inference |
| GET | `/api/user/sync/overview` | `sync_overview` | None (`_require_user_or_admin`) | User/Admin | Bootstraps vehicles and logs for app |
| POST | `/api/web/sync/user` | `sync_user` | None (`_require_user_or_admin`) | User/Admin | Upserts user profile in Firestore |
| POST | `/api/web/sync/vehicle` | `sync_vehicle` | None (`_require_user_or_admin`) | User/Admin | Upserts vehicle (Vulnerable to IDOR takeover) |
| POST | `/api/web/sync/full` | `sync_full` | None (`_require_user_or_admin`) | User/Admin | Full sync batch (Vulnerable to IDOR) |
| POST | `/api/web/sync/battery-state` | `web_sync_battery_state` | None (BUG) | Unauthenticated | Ingests battery state into Firestore |
| POST | `/api/web/sync/trip-prediction` | `web_sync_trip_prediction` | None (BUG) | Unauthenticated | Ingests trip prediction into Firestore |
| POST | `/api/telemetry` | `ingest_telemetry` | None (`_require_user_or_admin`) | User/Admin | Ingests normalized telemetry |
| GET | `/api/ai/charging-model-status` | `ai_charging_model_status` | None | Public | Returns status and metrics of charging model |
| POST | `/api/ai/charge-feedback` | `ai_charge_feedback` | None | Public (Unauthenticated) | Stores user ground-truth SOC feedback |
| GET | `/api/ai/dataset` | `ai_get_dataset` | None (BUG) | Public (Data Leak) | Returns all training sessions & stats |
| GET | `/api/ai/dataset/export-csv` | `ai_export_dataset_csv` | None (BUG) | Public (Data Leak) | Dumps complete training dataset as CSV |
| PUT | `/api/ai/dataset/records/<id>` | `ai_update_dataset_record` | None (BUG) | Public (Data Tampering) | Modifies record in physical dataset |
| POST | `/api/ai/dataset/records` | `ai_add_dataset_record` | None (BUG) | Public (Data Injection) | Injects new record into physical dataset |
| POST | `/api/ai/models/charging_time/fine-tune` | `ai_fine_tune_charging_time` | None (`_require_user_or_admin`) | User/Admin | Triggers fine-tuning pipeline on server |
| POST | `/api/ai/predict-charging-time` | `ai_predict_charging_time` | None | Public | Predicts charging duration |
| POST | `/api/ai/predict-range` | `ai_predict_range` | None | Public | Predicts remaining range |
| POST | `/api/ai/predict-consumption` | `ai_predict_consumption` | None | Public | Predicts energy consumption |
| GET | `/api/app/config` | `app_config` | None | Public | Returns app remote config & update info |
| POST | `/api/app/config` | `update_app_config` | `@require_admin` | Admin | Updates remote configuration |
| GET | `/api/app/download` | `app_download` | None | Public | Serves or redirects to debug/release APK |

---

## 4. FastAPI AI Service Route Inventory (`web/ai_server/main.py`)

| Method | Endpoint | Handler | Authentication | Description |
|--------|----------|---------|----------------|-------------|
| GET | `/healthz` | `healthz` | None | Service liveness probe and loaded models summary |
| GET | `/v1/types` | `types` | `X-Internal-Token` | Lists all registered model types & runtime health |
| GET | `/v1/models/{type_key}` | `list_models` | `X-Internal-Token` | Lists available versions and active version |
| GET | `/v1/models/{type_key}/status` | `status_for_type` | `X-Internal-Token` | Detailed runtime/predictability status |
| POST | `/v1/models/{type_key}/upload` | `upload_model` | `X-Internal-Token` | Multipart upload for candidate model file |
| POST | `/v1/models/{type_key}/rollback` | `rollback_model` | `X-Internal-Token` | Reverts active version to previous version |
| DELETE | `/v1/models/{type_key}/{version}` | `delete_model` | `X-Internal-Token` | Deletes inactive model version |
| POST | `/v1/models/{type_key}/activate` | `activate_model` | `X-Internal-Token` | Marks version active in manifest |
| POST | `/v1/models/{type_key}/deactivate` | `deactivate_model`| `X-Internal-Token` | Unsets active version in manifest |
| POST | `/v1/models/{type_key}/load-active` | `load_active_model`| `X-Internal-Token` | Loads active version into memory runtime |
| POST | `/v1/models/{type_key}/deploy` | `deploy_model` | `X-Internal-Token` | Activates and reloads model in single step |
| POST | `/v1/models/{type_key}/reset` | `reset_model` | `X-Internal-Token` | Clears all model versions from disk |
| POST | `/v1/models/{type_key}/validate-version` | `validate_version` | `X-Internal-Token` | Runs smoke inference on specific version |
| POST | `/v1/models/{type_key}/test-version` | `test_version` | `X-Internal-Token` | Tests custom inputs against version |
| POST | `/v1/models/{type_key}/predict` | `predict_generic` | `X-Internal-Token` | Generic inference gateway for model type |
| GET | `/v1/soc/status` | `soc_status` | `X-Internal-Token` | Backward-compatible status for SOC model |
| POST | `/v1/soc/predict` | `soc_predict` | `X-Internal-Token` | Backward-compatible rich SOC prediction |

---

## 5. React Dashboard Page & Component Inventory (`web/dashboard/`)

| Page / Component | Route | Key Sub-components | API Endpoints Called | Roles Allowed |
|------------------|-------|--------------------|-----------------------|---------------|
| `Login.tsx` | `/login` | Email/Password Form, Google Sign-in | Firebase Auth Client SDK | Public |
| `Dashboard.tsx` | `/`, `/dashboard` | Metrics Cards, Battery Gauge, Quick Actions | `/api/user/vehicles`, `/api/user/charge-logs`, `/api/health` | Authenticated User / Admin |
| `AiCenter.tsx` | `/ai-center` | `ModelCatalog`, `ModelDetailPanel`, `RangePredictionLab`, `ChargingTimeEstimator` | `/api/admin/ai/status`, `/api/admin/ai/types`, `/api/user/ai/models`, `/api/ai/models/charging_time/*` | Authenticated User / Admin |
| `UploadDialog.tsx` | Dialog | File dropzone, Version input, Note input | `/api/admin/ai/models/{type}/upload` | Admin |
| `ModelManagerDrawer.tsx` | Drawer | `ModelVersionsList`, `ModelVersionActions` | `/api/admin/ai/models/{type}/deploy`, `/rollback`, `/reset`, `DELETE` | Admin |
| `UserManagement.tsx` | `/users` | User list table, Role toggle modal | `/api/admin/users`, `/api/auth/set-admin` | Admin only |
| `AuditSystem.tsx` | `/audit` | Audit log table, JSON details inspector | `/api/admin/audit-logs`, `/api/admin/export` | Admin only |
| `Settings.tsx` | `/settings` | System config, Theme, Token inspector | `/api/app/config`, `/api/health` | Authenticated User / Admin |

---

## 6. Docker & Container Ingress Topology

| Container Name | Image / Dockerfile | Published Ports | Networks | Mounts / Volumes | Secrets / Env Variables |
|----------------|---------------------|-----------------|----------|-------------------|--------------------------|
| `vinfast_caddy` | `caddy:2.10-alpine` | `80:80`, `443:443` (TCP/UDP) | `vinfast_net` | `Caddyfile` (ro), `caddy_data`, `caddy_config` | None directly |
| `vinfast_laptop_gateway` | `caddy:2.10-alpine` | `127.0.0.1:8080:80` | `vinfast_net` | `Caddyfile.laptop` (ro) | None directly |
| `vinfast_dashboard` | `Dockerfile.dashboard` | None (exposes 80) | `vinfast_net` | NGINX serving Vite build | Firebase Public Keys in build args |
| `vinfast_api` | `Dockerfile.api` | `127.0.0.1:5000:5000` (laptop) | `vinfast_net` | `models_data` (`/app/models`), `apk_data` (`/app/apk`), `ev_soc_pipeline.pkl` | `FIREBASE_CREDENTIALS_JSON`, `ADMIN_EMAILS`, `DEV_ADMIN_KEY`, `AI_SERVER_INTERNAL_TOKEN` |
| `vinfast_ai` | `Dockerfile.ai` | None (internal 8001) | `vinfast_net` | `models_data` (`/app/models`) | `AI_SERVER_INTERNAL_TOKEN`, `AI_SERVER_MODELS_DIR` |
