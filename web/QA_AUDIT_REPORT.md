# MASTER QA, SECURITY, LOGIC & UI/UX AUDIT REPORT
## VinFast Battery Web Ecosystem

- **Target Systems:** Flask Unified Backend (`server.py`) + FastAPI AI Service (`ai_server/`) + React 18 / Vite Dashboard (`dashboard/`) + Caddy Ingress + Firebase / Firestore Integration
- **Execution Date:** 2026-09-08
- **Audit Branch:** `qa/web-master-audit-2026-09-07` | **Baseline Commit:** `37256f0`
- **Environment:** Windows 11, Python 3.12.10, Node v24.14.1, npm 11.11.0, Docker 29.7.2, Vite 6.4.2

---

## 1. Executive Summary & Release Gate Verdict

### 🛑 RELEASE GATE VERDICT: **BLOCK RELEASE**

Deploying the current codebase to production poses immediate, severe risks to user confidentiality, cloud infrastructure integrity, and system stability. The audit identified **5 Critical (P0)** security vulnerabilities, **4 High (P1)** defects, and **3 Medium (P2)** UI/UX & performance issues that must be remediated before any production release.

```text
╔══════════════════════════════════════════════════════════════════════════════════╗
║                             RELEASE GATE VERDICT                                 ║
║                                                                                  ║
║                              🛑 BLOCK RELEASE                                    ║
║                                                                                  ║
║   Must NOT be released until P0/P1 security bypasses, IDOR vehicle takeovers,    ║
║   unsafe pickle deserializations, and constructor signature crashes are fixed.   ║
╚══════════════════════════════════════════════════════════════════════════════════╝
```

---

## 2. Key Findings Summary Table

| Finding ID | Severity | Category | Target Component | Summary of Impact |
|---|---|---|---|---|
| **SEC-001** | **P0 (Critical)** | Authentication | `web/server.py` | `DEV_ADMIN_KEY` bypasses Firebase Auth, allowing anyone with header `X-Admin-Key` to act as full administrator. |
| **SEC-002** | **P0 (Critical)** | Authorization | `web/server.py` | Wildcard `*` in `ADMIN_EMAILS` automatically grants administrator privileges to every user who logs in. |
| **SEC-003** | **P0 (Critical)** | Data Security | `web/server.py` | Public unauthenticated write on `/api/web/sync/battery-state` & `/api/web/sync/trip-prediction` floods Firestore. |
| **SEC-004** | **P0 (Critical)** | Data Leak / Tampering | `web/server.py` | `/api/ai/dataset` & `/export-csv` are completely public; PUT `/records/<id>` allows unauthenticated tampering of ML training data. |
| **SEC-006** | **P0 (Critical)** | RCE / Deserialization | `web/ai_server/model_runtime.py` | `_load_model_file` executes `pickle.load` / `joblib.load` on uploaded files, enabling Remote Code Execution. |
| **SEC-007** | **P0 (Critical)** | IDOR / Account Takeover | `web/server.py` | `/api/web/sync/vehicle` & `/api/web/sync/full` overwrite vehicle ownership without verifying existing owner. |
| **WEB-BUG-001** | **P1 (High)** | Runtime Crash | `web/shelly/models.py` | `ChargingSession.__init__()` missing `safety_policy_version` argument, causing 22 test failures in Smart Charge suite. |
| **SEC-008** | **P1 (High)** | CORS Security | `web/server.py` | Permissive CORS configuration reflects arbitrary origins (e.g. `https://evil.com`) in `Access-Control-Allow-Origin`. |
| **SEC-010** | **P1 (High)** | Path Traversal | `web/ai_server/model_store.py` | `ModelStore.path_of` fails to sanitize version strings, allowing `sub/../../outside` directory traversal. |
| **WEB-UX-002** | **P1 (High)** | Responsive UI | `web/dashboard/Sidebar.tsx` | Fixed 220px/80px Sidebar breaks layout on mobile viewports (<480px), crowding out content on phones. |
| **WEB-CODE-001** | **P2 (Medium)** | Build / Lint | `web/dashboard/Settings.tsx` | TypeScript TS7016 error due to missing declaration types for `src/api.js`. |
| **WEB-PERF-001** | **P2 (Medium)** | Performance | `web/dashboard/dist` | Monolithic 1.51MB bundle generated without dynamic code-splitting. |

---

## 3. Deep-Dive Defect & Vulnerability Analysis

### 🚨 SEC-001: Static `DEV_ADMIN_KEY` Bypasses Firebase Authentication (P0)
- **Location:** `web/server.py:L427-L432`
- **Root Cause:**
  ```python
  admin_key = request.headers.get('X-Admin-Key', '')
  if admin_key and admin_key == _DEV_ADMIN_KEY:
      request._uid = 'dev-admin'
      request._email = 'dev@local'
      request._role = 'admin'
      return f(*args, **kwargs)
  ```
- **Exploitation:** Any external client sending `X-Admin-Key` matching `DEV_ADMIN_KEY` gains instant root administrative control over user records, audit trails, and model deployment without valid Firebase Auth credentials.
- **Evidence:** Verified by `test_web_h1_dev_admin_key_bypasses_firebase_auth` in `web/tests/qa_audit/test_qa_auth_matrix.py`.

---

### 🚨 SEC-006: Arbitrary Python Object Deserialization via Model Upload (P0)
- **Location:** `web/ai_server/model_runtime.py:L78-L98`, `web/ai_server/model_store.py:L95-L103`
- **Root Cause:** `_load_model_file` automatically dispatches `.pkl`, `.joblib`, `.pickle` and any unknown extension to `_load_pickle_file`, which invokes `joblib.load()` and `pickle.load()` on untrusted uploaded bytes.
- **Exploitation:** An authenticated or key-holding attacker can upload a crafted serialized payload that executes arbitrary operating system commands inside the container environment.
- **Evidence:** Verified by `test_web_h8_unsafe_deserialization_fallback` in `web/tests/qa_audit/test_qa_ai_upload_lifecycle.py`.

---

### 🚨 SEC-007: Vehicle IDOR & Account Takeover via `sync_vehicle` (P0)
- **Location:** `web/server.py:L4413-L4436`
- **Root Cause:**
  ```python
  vehicle_id = body.get('vehicleId') or body.get('id')
  payload['ownerUid'] = uid
  _fs().collection('Vehicles').document(vehicle_id).set(payload, merge=True)
  ```
- **Exploitation:** User A sends a POST request with `vehicleId: "vehicle_of_user_b"`. The backend executes `.set(payload, merge=True)` without checking if `Vehicles/{vehicle_id}` already exists with another `ownerUid`. User A takes complete ownership of User B's vehicle and telemetry history.
- **Evidence:** Verified by `test_web_h13_vehicle_idor_takeover_in_sync_vehicle` in `web/tests/qa_audit/test_qa_idor_data_integrity.py`.

---

### 🚨 SEC-004: Unauthenticated Training Dataset Exfiltration & Tampering (P0)
- **Location:** `web/server.py:L3688-L3760`
- **Root Cause:** Routes `/api/ai/dataset`, `/api/ai/dataset/export-csv`, `/api/ai/dataset/records/<id>` (PUT), and `/api/ai/dataset/records` (POST) lack `@require_auth` or `@require_admin` decorators.
- **Exploitation:** Any unauthenticated actor on the network can download the full historical training dataset with customer driving/charging habits as CSV, and submit forged ground-truth actual SOC records via PUT/POST to poison future model fine-tuning.
- **Evidence:** Verified by `test_unauthenticated_ai_dataset_access_and_export` and `test_unauthenticated_ai_dataset_tampering_put` in `web/tests/qa_audit/test_qa_idor_data_integrity.py`.

---

### 🐛 WEB-BUG-001: Shelly `ChargingSession` Crash on `safety_policy_version` (P1)
- **Location:** `web/shelly/service.py:L220, L729` vs `web/shelly/models.py:L42-L75`
- **Root Cause:** `service.py` calls `ChargingSession(..., safety_policy_version=...)`, but `ChargingSession.__init__()` does not accept this keyword argument, triggering `TypeError: ChargingSession.__init__() got an unexpected keyword argument 'safety_policy_version'`.
- **Impact:** 22 tests in the existing Smart Charge test suite failed during baseline execution; charging sessions crash upon activation or manual start.
- **Evidence:** Captured in `web/qa-evidence/logs/baseline_pytest.log` and verified by `test_shelly_charging_session_safety_policy_version_defect` in `web/tests/qa_audit/test_qa_validation_contracts.py`.

---

### 📱 WEB-UX-002: Fixed Sidebar Width Breaks Layout on Mobile Screens (P1)
- **Location:** `web/dashboard/src/components/layout/Sidebar.tsx:L31-L38`
- **Root Cause:** The `<motion.aside>` element is always rendered with fixed widths (80px collapsed / 220px expanded) and `sticky top-0 z-50` without responsive hiding classes (`hidden md:flex`) or a mobile navigation drawer.
- **Impact:** On 320px–375px viewports, the sidebar occupies up to 70% of screen width, causing extreme horizontal overflow and rendering dashboard metric cards and charts unusable.
- **Evidence:** Documented in `web/QA_TRACEABILITY_MATRIX.md` (WEB-UX-H26).

---

## 4. Test Harness & Baseline Execution Metrics

### Python Test Suite Execution
- **Existing Suite Baseline:** 82 tests run ➔ **22 Failed**, **60 Passed** (due to `WEB-BUG-001`).
- **QA Master Audit Suite:** 20 tests run ➔ **20 Passed** (all 20 vulnerability reproductions and security hypotheses validated).
- **Compilation Check:** `python -m compileall -x "(\.venv|node_modules)" web` ➔ **0 syntax errors**.

### Frontend Baseline Execution
- **TypeScript Lint:** `npm run lint` ➔ **Failed with 1 error** (`TS7016: Could not find declaration file for module '@/api'`).
- **Production Build:** `npm run build` ➔ **Succeeded with warnings** (Generated `dist/assets/index-B67LigeW.js` = 1,511.30 kB > 500 kB chunk threshold).

### Container / Compose Configuration Check
- `docker compose -f docker-compose.yml config` ➔ Valid config (flagged plaintext Base64 secret in environment).
- `docker compose -f docker-compose.laptop.yml config` ➔ Failed when run standalone (missing `vinfast_net` definition). Succeeded when combined with `-f docker-compose.yml`.

---

## 5. Remediation Roadmap (Fix Proposals)

### Phase 1: Security & Auth Hardening (P0 Immediate Priority)
1. **Remove `DEV_ADMIN_KEY` from Production:** Disable the `X-Admin-Key` header check whenever `APP_ENV == 'production'`, or restrict it exclusively to local offline unit tests.
2. **Remove Wildcard Support in `ADMIN_EMAILS`:** Reject any configuration containing `*` in `ADMIN_EMAILS` to prevent global privilege elevation.
3. **Enforce Ownership Verification in Sync Routes:**
   - In `/api/web/sync/vehicle` and `/api/web/sync/full`, query `Vehicles/{id}` first; if it exists and `doc.ownerUid != caller_uid`, return `403 Forbidden`.
4. **Protect Dataset & Sync Endpoints:** Add `@require_admin` to `/api/ai/dataset/*` and `@require_auth` to `/api/web/sync/battery-state` and `/api/web/sync/trip-prediction`.
5. **Sanitize Model Uploads & Disable Dangerous Deserializers:**
   - Whitelist only safe model formats (`.tflite`, `.onnx`).
   - Disallow `.pkl` / `.joblib` uploads from untrusted web clients.
   - Enforce regex `^[a-zA-Z0-9._-]+$` on `version` to eliminate path traversal.

### Phase 2: Runtime Bug Fixes & Code Quality (P1 Priority)
1. **Fix `ChargingSession` Constructor:** Add `safety_policy_version: Optional[str] = "v2.0"` to `ChargingSession` in `web/shelly/models.py`.
2. **Create `src/api.d.ts`:** Declare types for `src/api.js` exports to resolve TypeScript TS7016 error.
3. **Restrict CORS:** Set `Access-Control-Allow-Origin` strictly to authorized domain origins configured in `CORS_ORIGINS`, denying wildcard `*` or untrusted origins.

### Phase 3: UI/UX & Responsive Redesign (P1/P2 Priority)
1. **Implement Mobile Navigation Drawer:** Add a hamburger button in `Topbar.tsx` for `< 768px` viewports, and render `Sidebar.tsx` inside a dismissable sheet overlay on mobile.
2. **Add Role Guard to Client Router:** In `App.tsx`, wrap `/users` and `/audit` routes in a `<ProtectedRoute role="admin">` component.
3. **Code-Split Frontend Bundles:** Use `React.lazy()` and `Suspense` for `AiCenter`, `AuditSystem`, and `UserManagement` to reduce initial bundle size below 300 kB.

---

## 6. Audit Artifacts & Evidence Index

All evidence files, logs, and route inventories have been generated and archived:
- `web/QA_ARCHITECTURE_INVENTORY.md` — Complete route, entity, and boundary inventory.
- `web/QA_TRACEABILITY_MATRIX.md` — 87 checklist sections and 40 hypotheses mapped to results.
- `web/qa-evidence/logs/baseline_pytest.log` — Baseline execution log with 22 failed tests.
- `web/qa-evidence/logs/qa_audit_pytest.log` — Execution log for 20 automated QA audit tests.
- `web/qa-evidence/logs/baseline_frontend_lint.log` — TypeScript TS7016 lint failure log.
- `web/qa-evidence/logs/baseline_frontend_build.log` — Vite production build chunk log.
- `web/qa-evidence/api/routes_inventory.json` — Machine-readable inventory of 70+ Flask & 19 FastAPI routes.
