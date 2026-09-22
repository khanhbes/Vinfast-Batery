# VINFAST BATTERY WEB — MASTER QA / SECURITY / LOGIC / AI / UIUX AUDIT

**Repository:** `https://github.com/khanhbes/Vinfast-Batery`  
**Primary scope:** `web/`  
**Subsystems:** Flask backend + FastAPI AI service + React/Vite dashboard + Firebase/Firestore + Docker/Nginx  
**Version:** Consolidated QA + UI/UX Edition  
**Date:** 2026-09-07

---

# 0. ROLE

Bạn là một nhóm Senior gồm:

- Senior Full-stack Engineer
- Senior Python Backend Engineer
- Senior React/TypeScript Engineer
- Senior QA/SDET
- Senior UI/UX/Product Designer
- Accessibility Specialist
- Application Security Engineer
- Firebase/Firestore Security Engineer
- ML/MLOps Engineer
- DevOps/SRE Engineer
- API Contract Reviewer

Nhiệm vụ:

> đọc toàn bộ `web/` → hiểu Flask/FastAPI/React/Firebase/Docker/Nginx → lập trust boundary → map API/data contract → audit logic/security/AI → audit UI/UX → chạy test → cố tình phá assumptions → tạo regression test → đưa ra release gate.

Không được coi:

```text
npm run build
python server.py
```

là bằng chứng hệ thống đúng.

---

# 1. PHẠM VI

Audit toàn bộ:

```text
web/
  server.py
  ai_server/
  dashboard/
  Dockerfile*
  docker-compose.yml
  nginx*
  requirements.txt
  .env*
  scripts/
  model/artifact storage
```

Dashboard hiện cần ưu tiên các vùng:

```text
src/
  App.tsx
  AdminPortal.jsx
  TelemetryDashboard.jsx
  api.js
  firebase.js / firebase.ts

  components/
    layout/
      Sidebar.tsx
      Topbar.tsx

    ui/
      button.tsx
      card.tsx
      input.tsx
      table.tsx
      dropdown-menu.tsx
      progress.tsx
      sonner.tsx
      ...

    ai-center/
      ChargingTimeEstimator.tsx
      ModelCatalog.tsx
      ModelDetailPanel.tsx
      ModelTypeCard.tsx
      PredictionResultChart.tsx
      RangePredictionLab.tsx
      UploadDialog.tsx

  pages/
    Dashboard
    AiCenter
    AuditSystem
    ...
```

---

# 2. MỤC TIÊU

Phải xác minh:

## Security / Backend

- Anonymous đọc được gì?
- User thường gọi admin API được không?
- User A đọc/sửa User B được không?
- Có IDOR/BOLA qua vehicleId/tripId/sessionId không?
- `X-Admin-Key` có bypass Firebase auth không?
- `DEV_ADMIN_KEY=dev-local-token` có reachable production không?
- `ADMIN_EMAILS=*` có biến mọi user thành admin không?
- Public telemetry/charge API có lộ GPS/history không?
- Backend có tin `ownerUid` client gửi không?
- Firebase init fail có fail closed không?
- CORS có quá rộng không?
- Có secret/token thật bị commit không?
- AI internal token có default yếu không?
- Model upload có unsafe deserialize/path traversal không?
- Deploy/rollback có corrupt manifest/runtime không?
- API retry có duplicate dữ liệu không?
- Nginx/Docker có production default nguy hiểm không?

## UI/UX

- Dashboard có responsive thật hay chỉ desktop?
- Sidebar/Topbar có hoạt động ở 320/375/768/1024/1440 không?
- Bảng có usable trên mobile/tablet không?
- AI model upload/deploy/rollback có state feedback rõ không?
- Destructive admin action có confirm và undo/recovery phù hợp không?
- Loading/error/empty/partial/offline có đầy đủ không?
- Unauthorized user nhìn thấy admin navigation không?
- Token expiry có làm blank screen không?
- Chart có readable, có unit, legend, empty state không?
- Table có keyboard navigation/focus phù hợp không?
- Modal/dialog có focus trap và ESC không?
- Toast có đủ rõ, không biến mất trước khi user đọc không?
- UI có stale-request race không?
- Vietnamese/English/text scaling/browser zoom có phá layout không?
- Accessibility có đủ contrast, focus visible, labels, semantics không?
- Animation có gây layout shift hoặc feedback sai không?
- Web có visual regression tests không?

---

# 3. QUY TẮC

Không test nguy hiểm trên production.

Dùng:

- localhost;
- Docker local;
- Firebase Emulator/test project;
- mocks;
- local model fixtures.

Phân loại:

- `CONFIRMED BUG`
- `HIGH-CONFIDENCE LOGIC ISSUE`
- `SECURITY MISCONFIGURATION RISK`
- `UI/UX DEFECT`
- `ACCESSIBILITY DEFECT`
- `PERFORMANCE DEFECT`
- `TESTABILITY GAP`
- `EXPECTED BEHAVIOR`
- `BLOCKED`

---

# 4. INVENTORY

Tạo:

`web/QA_ARCHITECTURE_INVENTORY.md`

Phải map:

## Flask

| Route | Method | Auth | Input | Output | Firestore | AI dependency | Side effect |

## AI

| Endpoint | Auth | Model type | Input | Output | Artifact | Mutates state? |

## Dashboard

| Page/Component | API | Auth token | Admin only | Loading | Empty | Error |

## Deployment

| Service | Port | Network | Volume | Env | Secret-like env | Health |

---

# 5. TRUST BOUNDARY

Vẽ:

```text
Browser
  -> Nginx
  -> Flask
  -> Firebase Auth
  -> Firestore
  -> FastAPI AI
  -> Model Runtime
  -> Model Store / Filesystem

Flutter App
  -> Flask API
```

Tại mỗi boundary ghi:

- trusted identity;
- untrusted input;
- authentication;
- authorization;
- validation;
- secret transfer;
- logging risk.

---

# 6. BASELINE

```bash
git status
git rev-parse HEAD
git branch --show-current

python --version
node --version
npm --version
docker --version
docker compose version
```

Python:

```bash
cd web
python -m venv .venv-audit
python -m pip install --upgrade pip
pip install -r requirements.txt
python -m compileall .
pytest -v
```

Nếu chưa có pytest:

`NO BACKEND AUTOMATED TEST HARNESS`

Dashboard:

```bash
cd web/dashboard
npm ci
npm run build
npx tsc --noEmit
```

Chạy mọi script test/lint có trong `package.json`.

Nếu chưa có test:

`NO FRONTEND AUTOMATED TEST HARNESS`

Docker:

```bash
cd web
docker compose config
docker compose build
docker compose up -d
docker compose ps
```

---

# 7. TEST HARNESS

Nếu thiếu:

## Flask/FastAPI

- pytest
- Flask test client
- FastAPI TestClient/httpx
- Firebase Emulator/mock
- temporary model store

## React

Ưu tiên:

- Vitest
- React Testing Library
- Playwright

## UI Visual

Ưu tiên:

- Playwright screenshots
- visual snapshot comparison

Không refactor architecture lớn chỉ để test; ghi `TESTABILITY GAP` nếu cần.

---

# 8. AUTH MATRIX

Với mọi endpoint nhạy cảm, test:

1. Anonymous
2. Normal Firebase user
3. Firebase admin
4. Malformed bearer token
5. Expired token
6. Wrong audience/project token
7. Revoked token nếu có
8. Correct dev admin key
9. Wrong dev admin key
10. Admin key không bearer
11. Normal token + admin key
12. Empty Authorization
13. `Bearer ` empty
14. weird header casing

Document expected/actual.

---

# 9. ADMIN AUTH — P0 PRIORITY

Audit `require_admin` và tương tự.

## WEB-H1

Nếu:

```text
DEV_ADMIN_KEY=dev-local-token
```

và:

```text
X-Admin-Key: dev-local-token
```

anonymous có vào admin API không?

Nếu production reachable với default:

`P0 CRITICAL`.

## WEB-H2

Nếu:

```text
ADMIN_EMAILS=*
```

mọi Firebase user có thành admin không?

## WEB-H3

Firebase init fail có fail closed không?

Phải deny.

## WEB-H4

Bearer + admin key cùng request, precedence thế nào?

Không được có unexpected bypass.

---

# 10. ADMIN UI KHÔNG PHẢI AUTHORIZATION

Test normal user login rồi truy cập trực tiếp:

- AI Model Management
- Upload
- Activate
- Deploy
- Rollback
- Delete
- Reset
- User admin
- Audit system
- Sensitive statistics

Hai lớp:

## UI
Có hide/disable đúng không?

## API
Backend có block thực sự không?

UI hiện admin controls nhưng API block:

UX/security-boundary issue.

Backend cho phép:

P0.

---

# 11. PUBLIC API / IDOR / BOLA

Tạo:

- User A / Vehicle A / Trip A / Charge A
- User B / Vehicle B / Trip B / Charge B

Từ anonymous/User A thử ID của B.

Đặc biệt:

- telemetry;
- GPS;
- trip;
- charge;
- vehicle;
- battery;
- history;
- statistics.

Cross-user sensitive read:

P0/P1 theo dữ liệu.

---

# 12. OWNERUID SPOOFING

Nếu endpoint nhận:

- ownerUid
- uid
- userId

test:

User A authenticated nhưng body gửi UID B.

Backend phải derive identity từ verified token.

---

# 13. FIRESTORE DATA INTEGRITY

Test:

- missing field;
- null;
- wrong type;
- malformed timestamp;
- deleted record;
- 0/negative/huge number;
- SOC >100;
- NaN/Infinity nếu layer cho phép;
- unknown enum.

Một bad document không crash entire response/page.

---

# 14. SOFT DELETE

Tìm `isDeleted` và biến thể.

Deleted record phải được xử lý đúng ở:

- API;
- statistics;
- AI training;
- dashboard;
- export;
- history.

---

# 15. INPUT VALIDATION

Test JSON:

- empty;
- `{}`;
- invalid;
- array;
- string;
- null;
- nested huge.

Number:

- negative;
- zero;
- boundary;
- huge;
- string-number;
- float;
- NaN;
- Infinity.

String:

- empty;
- whitespace;
- huge;
- Unicode;
- emoji;
- HTML;
- script;
- path traversal.

Client invalid input nên 4xx, không 500.

---

# 16. RESPONSE CONTRACT

Mỗi endpoint phải có schema ổn định cho:

- success;
- validation error;
- 401;
- 403;
- 404;
- 409;
- 429;
- 500;
- 502/503.

Không HTTP 200 “success giả” trừ khi contract intentional.

Không leak traceback/path/credential/token.

---

# 17. PAGINATION / FILTER / SORT

Test:

```text
limit=0
limit=-1
limit=1
limit=100
limit=1000000
```

Test:

- invalid cursor;
- cursor user khác;
- bad date;
- future date;
- reversed range;
- unsupported sort.

Không unbounded query không cần thiết.

---

# 18. CONCURRENCY / IDEMPOTENCY

Test đồng thời:

- same vehicle update;
- same session stop;
- same charge feedback;
- same counter;
- Flutter retry;
- web mutation double click.

Server xử lý thành công nhưng response bị mất -> client retry.

Không được sinh duplicate business record.

---

# 19. APP ↔ WEB CONTRACT

Đọc `app/` read-only.

Lập bảng:

| Flutter endpoint | Method | Payload | Flask route | Expected schema | Match? |

Kiểm tra:

- key names;
- casing;
- int/double;
- timestamp;
- nullability;
- ownerUid;
- sessionId;
- model source;
- confidence;
- version.

---

# 20. AI SERVICE AUTH

Inventory `/api/admin/ai/...` và internal endpoints.

Test:

- no token;
- wrong token;
- default token;
- normal Firebase token;
- Flask proxy;
- direct host access.

AI admin API intended internal không nên public unnecessarily.

---

# 21. MODEL UPLOAD SECURITY

Test:

- supported extension;
- unsupported;
- uppercase;
- double extension;
- huge file;
- empty file;
- corrupt file;
- duplicate version;
- Unicode filename;
- path traversal;
- absolute path.

Không trust MIME type.

---

# 22. UNSAFE DESERIALIZATION

Audit:

- pickle;
- joblib;
- other unsafe loaders.

Không tạo RCE payload thật.

Nếu untrusted uploader có thể upload rồi runtime deserialize unsafe format:

Critical risk.

Khuyến nghị:

- trusted artifact pipeline;
- signature/checksum;
- restrict format;
- isolate runtime;
- least privilege.

---

# 23. MODEL STATE MACHINE

```text
uploaded
 -> registered
 -> inactive
 -> active
 -> previous/rollback
 -> deleted
```

Test invalid transitions:

- activate missing;
- activate corrupt;
- delete active;
- rollback no previous;
- deploy same twice;
- delete rollback target;
- reset while inference running.

---

# 24. RUNTIME VS MANIFEST

Mandatory:

Manifest A -> deploy B -> runtime B load fail.

Không được kết thúc:

```text
manifest=B
runtime=A
```

mà hệ thống báo success.

Test reverse ordering nếu implementation khác.

---

# 25. MODEL CONCURRENCY

Concurrent:

- deploy B + deploy C;
- deploy + rollback;
- deploy + delete;
- activate + reset.

Không corrupt manifest/JSON.

Atomic write/locking phải được đánh giá.

---

# 26. AI INPUT / OUTPUT

Input:

- missing;
- extra;
- wrong type;
- wrong shape;
- null;
- NaN;
- Infinity;
- extremes.

Output:

- finite;
- SOC 0..100;
- duration >=0;
- probability 0..1 nếu relevant;
- confidence valid.

Fallback phải có source rõ.

---

# 27. AI DOWN / TIMEOUT / BAD RESPONSE

Tắt AI local.

Mock delay:

- 1s
- 5s
- 30s
- >timeout

Mock:

- 200 invalid JSON;
- missing field;
- 500;
- empty.

Flask không treo worker vô hạn.

Dashboard không spinner vô hạn.

---

# 28. TRAINING PIPELINE

Dataset:

- empty;
- one sample;
- missing column;
- NaN;
- duplicates;
- outlier;
- deleted data;
- mixed users.

Check leakage:

- train/test;
- temporal leakage;
- per-user/global boundary.

---

# 29. DASHBOARD API CLIENT

Audit `api.js` và wrappers.

Test response:

- 200 valid;
- 200 empty;
- 200 HTML;
- malformed JSON;
- 400;
- 401;
- 403;
- 404;
- 409;
- 429;
- 500;
- 502;
- 503;
- timeout;
- offline.

Không:

- infinite spinner;
- blank page;
- unhandled Promise rejection.

---

# 30. TOKEN REFRESH / LOGIN / LOGOUT

Test:

- valid login;
- bad login;
- network fail;
- double submit;
- token expiry;
- refresh;
- logout;
- Back after logout;
- multi-tab logout propagation.

Protected data không được còn usable từ cache sau logout nếu security model không cho.

---

# 31. CORS / CSRF / XSS

CORS:

- production origin;
- localhost;
- evil origin;
- null;
- OPTIONS.

CORS không thay auth.

CSRF:

chỉ report nếu cookie/session architecture thực sự relevant.

XSS:

test data:

```html
<script>alert(1)</script>
<img src=x onerror=alert(1)>
```

Kiểm tra:

- dangerouslySetInnerHTML;
- tooltip;
- custom HTML;
- href/src injection;
- third-party chart rendering.

---

# 32. SECRET / LOGGING

Search:

```text
api_key
secret
token
password
private_key
serviceAccount
BEGIN PRIVATE KEY
dev-local-token
```

Không coi Firebase browser API key mặc định là secret.

Không log:

- bearer token;
- admin key;
- password;
- service-account private key.

---

# 33. DOCKER / NGINX

Audit:

- resolved env;
- default secrets;
- exposed ports;
- root containers;
- writable filesystem;
- health;
- restart;
- production debug;
- proxy headers;
- SPA fallback;
- API routing;
- file upload limits.

Mandatory:

```bash
docker compose config
```

Phân loại default:

- `SAFE DEV DEFAULT`
- `DANGEROUS PRODUCTION DEFAULT`

Production nên fail startup nếu critical secret vẫn default.

---

# 34. SECURITY HEADERS

Production boundary:

- CSP
- HSTS
- X-Content-Type-Options
- Referrer-Policy
- frame protection
- Permissions-Policy nếu phù hợp

Không đánh fail HSTS trên localhost HTTP.

---

# 35. UI/UX AUDIT — DESIGN SYSTEM

Audit:

- Tailwind config;
- `index.css`;
- reusable `components/ui/*`;
- Sidebar;
- Topbar;
- cards;
- buttons;
- inputs;
- tables;
- dropdown;
- progress;
- toast;
- dialog;
- AI components.

Tạo token inventory:

- color;
- typography;
- spacing;
- radius;
- shadow;
- border;
- z-index;
- breakpoint;
- focus ring;
- transition;
- status colors.

Tìm:

- hard-coded inconsistent styles;
- duplicate button variants;
- status colors inconsistent;
- arbitrary spacing;
- unreadable dark background;
- z-index conflicts.

---

# 36. UI/UX — INFORMATION ARCHITECTURE

Kiểm tra navigation hierarchy:

- Dashboard
- Telemetry
- AI Center
- Audit/System
- Admin sections
- user/menu

Câu hỏi:

1. User hiểu mình đang ở đâu?
2. Active nav có rõ?
3. Page title có nhất quán?
4. Có page overlap chức năng?
5. Có action quan trọng bị chôn sâu?
6. Admin-only section có được phân nhóm rõ?
7. Breadcrumb có cần không?

Không thêm complexity nếu không cần.

---

# 37. UI/UX — RESPONSIVE MATRIX

Bắt buộc:

```text
320px
375px
480px
768px
1024px
1280px
1440px
1920px
```

Test browser zoom:

```text
80%
100%
125%
150%
200%
```

Kiểm tra:

- Sidebar;
- Topbar;
- cards;
- tables;
- charts;
- modal;
- upload dialog;
- AI detail panel;
- telemetry;
- filters.

Không:

- horizontal body overflow;
- fixed sidebar che content;
- modal vượt viewport;
- sticky header conflict;
- chart zero-width;
- CTA mất.

---

# 38. UI/UX — MOBILE WEB

Nếu dashboard không intended mobile-first vẫn phải degrade hợp lý.

Test:

- collapsed sidebar;
- menu open/close;
- outside click;
- ESC;
- scroll lock;
- focus;
- table horizontal strategy;
- chart fit;
- card stack.

Không giả định admin chỉ dùng desktop nếu requirement không nói vậy.

---

# 39. UI/UX — SCREEN STATE MATRIX

Mỗi page/component:

| State | Expected UX |
|---|---|
| initial | không flash wrong user/data |
| loading | skeleton/progress |
| success | content |
| empty | explanation |
| error | actionable retry |
| unauthorized | clear forbidden/redirect |
| offline | network state |
| stale | visible timestamp/state |
| partial | usable sections remain |
| mutation pending | button locked |
| mutation success | confirmation |
| mutation fail | preserve input + retry |

---

# 40. UI/UX — LOADING

Phân biệt:

- initial page loading;
- background refresh;
- button mutation;
- model upload;
- deploy;
- rollback;
- telemetry refresh.

Không dùng full-page spinner khi chỉ một card update.

Button mutation:

- disable;
- progress;
- retain label context;
- prevent duplicate click.

---

# 41. UI/UX — EMPTY VS ERROR

Empty:

> “Chưa có model.”

Error:

> “Không tải được danh sách model.”

Hai trạng thái phải khác visual/copy.

Không dùng red danger cho empty state bình thường.

---

# 42. UI/UX — ERROR COPY

Không hiển thị raw:

```text
403
500
AxiosError
FirebaseError
Traceback
```

cho user bình thường.

Error UI cần:

- what happened;
- what user can do;
- whether data/action was saved;
- retry path.

Admin technical details có thể ở expandable diagnostics, không phải primary copy.

---

# 43. UI/UX — TABLES

Audit table:

- header;
- sorting;
- filtering;
- empty;
- loading;
- pagination;
- long strings;
- IDs;
- timestamps;
- badges;
- row action menu.

Responsive:

- column priority;
- horizontal scroll;
- sticky first column nếu thật sự cần;
- mobile card alternative nếu hợp lý.

Accessibility:

- proper table semantics;
- sortable header labels;
- keyboard;
- focus.

---

# 44. UI/UX — CHARTS

SOC/telemetry/prediction charts.

Test:

- 0 point;
- 1 point;
- 1000 point;
- duplicate timestamp;
- out-of-order;
- NaN;
- extreme.

Phải có:

- title;
- unit;
- legend;
- tooltip;
- readable axis;
- empty state;
- text summary cho critical insight.

Không phụ thuộc màu duy nhất để phân biệt series.

---

# 45. UI/UX — AI CENTER

Audit:

- Model Type Card
- Model Catalog
- Model Detail Panel
- Upload Dialog
- Charging Time Estimator
- Range Prediction Lab
- Prediction Result Chart

User phải phân biệt rõ:

- model type;
- version;
- active/inactive;
- uploaded/deployed;
- source;
- metric;
- last updated;
- destructive action.

Không để “Activate”/“Deploy”/“Rollback” dùng copy mơ hồ.

---

# 46. UI/UX — MODEL UPLOAD

State:

```text
idle
file selected
validating
uploading
uploaded
processing
success
error
```

Test:

- drag/drop nếu có;
- file picker cancel;
- unsupported extension;
- oversized;
- duplicate version;
- network fail;
- 50% upload fail;
- retry.

Không reset form mất hết input sau server error nếu không cần.

Progress phải phản ánh thật nếu có.

---

# 47. UI/UX — DESTRUCTIVE ADMIN ACTION

Cho:

- delete model;
- reset;
- rollback;
- delete user/object nếu có.

Phải có:

- clear target;
- consequences;
- confirm;
- pending state;
- success;
- failure.

Không dùng generic “Are you sure?” nếu có thể nói rõ:

> “Rollback model Charge Duration từ v2 sang v1?”

Double click không gửi hai request.

---

# 48. UI/UX — AUTHORIZATION FEEDBACK

Normal user:

Nếu route admin không được phép:

- không blank page;
- không infinite redirect;
- không render toàn admin UI rồi mới báo 403;
- không leak data trong skeleton/cached state.

UI nên có clear `Forbidden` hoặc redirect phù hợp.

Backend vẫn là authority.

---

# 49. UI/UX — SIDEBAR / TOPBAR

Sidebar:

- active state;
- collapsed state;
- long labels;
- mobile drawer;
- scroll;
- icon labels;
- focus.

Topbar:

- account;
- logout;
- notifications nếu có;
- responsive action;
- long email/name;
- menu alignment.

Test 200% zoom.

---

# 50. UI/UX — KEYBOARD ACCESS

Toàn dashboard phải dùng được bằng keyboard ở core flow.

Test:

- Tab;
- Shift+Tab;
- Enter;
- Space;
- Escape;
- Arrow keys nơi component pattern cần.

Không keyboard trap.

Dropdown/dialog:

- focus enters;
- focus stays inside modal;
- focus returns trigger khi close.

---

# 51. UI/UX — FOCUS VISIBLE

Không remove outline mà không có replacement.

Mọi:

- link;
- button;
- input;
- menu;
- table row action;
- dialog action

phải có focus visible đủ contrast.

---

# 52. ACCESSIBILITY

Target hợp lý: WCAG 2.1/2.2 AA cho core UI nếu feasible.

Audit:

- contrast;
- headings;
- labels;
- landmarks;
- form errors;
- aria-live;
- dialog roles;
- menu semantics;
- table semantics;
- icon-only buttons;
- toast announcements;
- keyboard order.

Không dùng color-only status.

---

# 53. SCREEN READER

Test tối thiểu bằng browser accessibility tree / NVDA/VoiceOver nếu environment có.

AI model card cần đọc:

- model name;
- version;
- state;
- action.

Chart cần alternate summary cho insight quan trọng.

Toast lỗi quan trọng nên announce.

---

# 54. COLOR / CONTRAST

Test:

- normal text;
- muted text;
- disabled;
- badges;
- success;
- warning;
- danger;
- links;
- focus ring;
- chart series.

Đặc biệt dark-on-dark/light gray text.

---

# 55. TEXT LENGTH / LOCALIZATION

Ngay cả khi web hiện chủ yếu một ngôn ngữ, test string expansion:

- 30%;
- 50%;
- very long user/model names;
- Vietnamese diacritics;
- email dài;
- version dài.

Không để fixed-width button cắt meaning.

---

# 56. UI/UX — TOAST / NOTIFICATION

Toast phải:

- không che primary action;
- không overlap;
- có enough duration;
- không duplicate spam;
- announce accessibility;
- distinguish success/error.

Critical destructive failure không chỉ dựa toast nếu user cần context.

---

# 57. UI/UX — MODAL / DIALOG

Test:

- open;
- close;
- ESC;
- outside click;
- focus trap;
- screen resize;
- zoom 200%;
- long error;
- scroll content;
- double open.

Không để body scroll background nếu modal design cần lock.

---

# 58. UI/UX — FORM VALIDATION

Test:

- empty;
- whitespace;
- Unicode;
- long;
- paste;
- autofill;
- Enter submit;
- double submit;
- server validation;
- field error.

Validation phải ở frontend cho UX nhưng backend vẫn validate.

Không disable Submit mà không giải thích field lỗi.

---

# 59. UI/UX — STALE REQUEST RACE

Mandatory.

Scenario:

- select Vehicle A;
- request A;
- immediately Vehicle B;
- request B;
- B returns first;
- A returns later.

UI cuối phải là B.

Lặp cho:

- telemetry;
- model detail;
- filters;
- date range;
- statistics;
- prediction.

---

# 60. UI/UX — OPTIMISTIC UPDATE

Chỉ optimistic khi safe.

Không optimistic cho:

- model deploy;
- rollback;
- delete;
- privileged operation

nếu backend confirmation là critical.

Nếu dùng optimistic:

failure phải rollback UI.

---

# 61. UI/UX — VISUAL FEEDBACK VS SERVER TRUTH

Đặc biệt Admin AI:

Không hiển thị:

> Active

chỉ vì user click Activate.

Chỉ update after confirmed API success.

Nếu request timeout và state unknown:

UI phải có “refresh/reconcile”.

---

# 62. UI/UX — PERFORMANCE

Đo:

- initial bundle/load;
- Dashboard render;
- Telemetry with large dataset;
- AI Model detail;
- large table;
- charts;
- modal open.

Browser tools:

- Performance panel;
- React Profiler;
- Lighthouse nếu phù hợp.

Tìm:

- unnecessary rerender;
- huge DOM;
- chart redraw;
- layout thrashing;
- giant bundle;
- unoptimized image.

---

# 63. LAYOUT SHIFT

Kiểm tra CLS-like issues:

- font load;
- chart resize;
- table load;
- skeleton -> content;
- image;
- sidebar.

Không để primary button nhảy vị trí đúng lúc user click.

---

# 64. ANIMATION / MOTION

Audit transitions:

- sidebar;
- dropdown;
- dialog;
- progress;
- toast;
- cards.

Respect:

```css
prefers-reduced-motion
```

Không animation trang trí làm chậm admin operation.

Không spinner tiếp tục sau request complete.

---

# 65. VISUAL REGRESSION

Thiết lập Playwright screenshot cho tối thiểu:

- Login
- Dashboard
- Telemetry
- AI Center
- Model Catalog
- Model Detail
- Upload Dialog
- Audit/System page nếu có

Viewport:

- 375
- 768
- 1440

States:

- loaded;
- empty;
- error;
- unauthorized;
- modal open.

Visual test không thay functional test.

---

# 66. BROWSER MATRIX

Tối thiểu:

- Chrome/Chromium
- Edge/Chromium
- Firefox
- Safari/WebKit qua Playwright nếu có

Test:

- latest stable;
- responsive;
- keyboard;
- file upload;
- chart;
- dropdown/dialog.

Nếu browser không officially supported, ghi rõ.

---

# 67. NETWORK UX

DevTools throttling:

- Fast 3G-like;
- Slow 3G-like;
- offline;
- 500ms latency.

Kiểm tra:

- skeleton;
- timeout;
- stale data;
- user feedback;
- duplicate click.

Không assume localhost speed.

---

# 68. HUGE DATA UX

Fixture:

- 10
- 100
- 1,000
- 10,000 records nếu local phù hợp.

Đánh giá:

- pagination;
- virtualization;
- filter latency;
- chart degradation;
- browser memory.

Không fetch/render toàn lịch sử nếu không cần.

---

# 69. CSV / EXPORT UX & SECURITY

Nếu export:

- progress;
- cancel nếu long;
- filename;
- error;
- empty result.

Security:

CSV formula injection:

```text
=HYPERLINK(...)
+cmd
@SUM(...)
```

Sanitize nếu threat model cần.

---

# 70. LOCATION PRIVACY UI

Nếu Telemetry hiển thị GPS:

- admin/user scope rõ;
- không lộ cho anonymous;
- UI cho biết time freshness;
- không nhầm stale GPS là current;
- copy/export permission đúng.

---

# 71. RATE LIMIT / ABUSE UX

Nếu API 429:

Dashboard phải:

- hiển thị retry delay hoặc thông báo;
- không infinite retry;
- không spam toast;
- không hammer endpoint.

---

# 72. HEALTH / DEPENDENCY UX

Nếu AI down nhưng backend/dashboard còn phần khác:

UI nên degrade partial.

Ví dụ:

AI card error nhưng Vehicle/Telemetry vẫn usable.

Không biến partial outage thành full blank page.

---

# 73. PRODUCTION FAIL-CLOSED

Nếu production:

- default admin key;
- default AI token;
- missing Firebase credentials;
- critical secret empty

server nên fail startup hoặc block privileged function rõ ràng.

Không silently insecure.

---

# 74. HIGH-RISK HYPOTHESES — WEB

Bắt buộc test:

### WEB-H1
Default `DEV_ADMIN_KEY` bypass admin?

### WEB-H2
`ADMIN_EMAILS=*` biến normal user thành admin?

### WEB-H3
Public telemetry lộ GPS cross-user?

### WEB-H4
Public charge logs lộ history?

### WEB-H5
Non-admin nhìn/trigger admin UI?

### WEB-H6
Demo credentials có phải real privileged account?

### WEB-H7
AI default internal token usable trực tiếp?

### WEB-H8
Unsafe pickle/joblib upload/load path?

### WEB-H9
Manifest B nhưng runtime A sau deploy fail?

### WEB-H10
Concurrent deploy/rollback corrupt state?

### WEB-H11
Delete active model làm restart fail?

### WEB-H12
Backend tin `ownerUid` client?

### WEB-H13
Vehicle IDOR?

### WEB-H14
Soft-deleted record bị trả public?

### WEB-H15
Flutter retry duplicate log/counter?

### WEB-H16
Flutter/Flask schema mismatch?

### WEB-H17
NaN/Infinity corrupt AI/statistics?

### WEB-H18
AI down làm Flask treo?

### WEB-H19
CORS quá permissive?

### WEB-H20
Production Nginx thiếu security header quan trọng?

### WEB-H21
APK update integrity yếu?

### WEB-H22
Firebase auth dependency fail-open?

### WEB-H23
Prediction/admin API abuse làm CPU/RAM spike?

### WEB-H24
Model upload thiếu size/path limit?

### WEB-H25
Artifact write + manifest write không atomic?

### WEB-UX-H26
Sidebar vỡ ở 320/375px?

### WEB-UX-H27
Table admin unusable ở tablet/mobile?

### WEB-UX-H28
Unauthorized route render cached admin data trước 403?

### WEB-UX-H29
Double-click Deploy gửi hai mutation?

### WEB-UX-H30
Upload fail làm mất form/file metadata không cần thiết?

### WEB-UX-H31
Stale request A overwrite selection B?

### WEB-UX-H32
200% zoom che destructive CTA/modal footer?

### WEB-UX-H33
Keyboard focus trap/dropdown/dialog lỗi?

### WEB-UX-H34
Chart chỉ dùng màu, thiếu label/unit?

### WEB-UX-H35
prefers-reduced-motion không được tôn trọng?

### WEB-UX-H36
Toast lỗi biến mất quá nhanh hoặc spam?

### WEB-UX-H37
Partial AI outage làm full dashboard blank?

### WEB-UX-H38
Long email/model version phá Topbar/card/table?

### WEB-UX-H39
Loading skeleton gây large layout shift?

### WEB-UX-H40
Error copy leak raw backend/security details?

---

# 75. REGRESSION TEST-FIRST

Khi xác nhận bug:

1. minimal reproduction;
2. fail test;
3. xác nhận fail;
4. document;
5. fix proposal;
6. verify pass.

Không refactor lớn trước reproduction.

---

# 76. TEST STRUCTURE ĐỀ XUẤT

```text
web/
  tests/
    backend/
      test_auth.py
      test_admin_auth.py
      test_user_isolation.py
      test_validation.py
      test_idempotency.py
      test_public_endpoints.py

    ai/
      test_ai_auth.py
      test_model_store.py
      test_model_runtime.py
      test_model_lifecycle.py
      test_prediction_validation.py
      test_model_concurrency.py

  dashboard/
    src/
      __tests__/
    e2e/
      auth.spec.ts
      dashboard.spec.ts
      telemetry.spec.ts
      ai-center.spec.ts
      responsive.spec.ts
      accessibility.spec.ts
      visual.spec.ts
```

---

# 77. AUTOMATED UI/UX TESTS

React Testing Library:

- loading;
- error;
- empty;
- role-based rendering;
- disabled/loading button;
- form validation;
- keyboard.

Playwright:

- real navigation;
- login;
- unauthorized;
- responsive;
- zoom;
- dialog;
- upload;
- stale network;
- screenshot;
- browser matrix.

Accessibility:

- axe-core nếu phù hợp;
- manual keyboard;
- accessibility tree.

Không phụ thuộc duy nhất automated a11y scanner.

---

# 78. BUG FORMAT

```markdown
### WEB-BUG-XXX — Title

Status:
Severity:
Confidence:

Subsystem:
Endpoint/Page:
File:
Function/Region:

Preconditions:

Steps:
1.
2.
3.

Expected:

Actual:

Evidence:

Root cause:

Auth impact:
Data impact:
Security impact:
AI impact:
UX impact:

Regression test:

Suggested fix:

Verification:
```

---

# 79. UI/UX DEFECT FORMAT

```markdown
### WEB-UX-XXX — Title

Severity:
Page/Component:
Viewport:
Browser:
Zoom:
State:

User goal:

Observed:

Expected:

Accessibility impact:

Screenshot/video:

Design-system cause:

Suggested fix:

Regression test:
```

---

# 80. SECURITY FINDING FORMAT

```markdown
### SEC-XXX — Title

Severity:
CWE:
OWASP:
Exploitability:
Required access:

Affected endpoint/config:

Attack path:

Observed:

Expected:

Impact:

Safe reproduction:

Remediation:

Regression test:
```

Không ép CWE nếu không chắc.

---

# 81. SEVERITY

## P0 — Critical

- admin bypass;
- unauthenticated sensitive data;
- arbitrary cross-user write/delete;
- RCE;
- real privileged secret leak;
- malicious model execution;
- arbitrary file write/delete.

## P1 — High

- sensitive cross-user read;
- data corruption;
- model deployment corruption;
- major auth failure;
- production outage;
- core admin flow inaccessible;
- severe a11y blocker for primary flow.

## P2 — Medium

- wrong stats;
- stale dashboard;
- significant responsive issue;
- important loading/error defect;
- role UI confusion;
- recoverable API bug.

## P3 — Low

- cosmetic;
- spacing;
- minor copy;
- non-critical visual inconsistency.

---

# 82. RELEASE GATE — SECURITY / LOGIC

Không `READY FOR RELEASE` nếu còn:

- P0;
- P1 authorization;
- cross-user leak;
- reachable default admin bypass;
- unsafe untrusted model deserialize;
- model state corruption;
- data-loss/duplicate bug;
- critical app↔backend mismatch;
- production debug/secrets unsafe.

---

# 83. RELEASE GATE — UI/UX

Không `READY FOR RELEASE` nếu:

- core admin/dashboard screen unusable 768/1024/1440;
- mobile layout intended/support claim nhưng vỡ 320/375;
- browser zoom 200% che core action;
- keyboard không dùng được core admin flow;
- modal focus trap hoặc escape làm user mắc kẹt;
- unauthorized user thấy sensitive cached data;
- loading/error state làm user không biết mutation đã thành công hay chưa;
- Deploy/Rollback/Delete thiếu pending guard/confirmation;
- stale response làm hiển thị sai vehicle/model;
- core chart thiếu unit/meaning nghiêm trọng;
- contrast/focus làm core action inaccessible;
- visual regression tồn tại ở primary screen.

---

# 84. FINAL REPORT

Tạo:

`web/QA_AUDIT_REPORT.md`

Report:

1. Executive Summary
2. Commit SHA / Environment
3. Architecture
4. Threat Model
5. API Inventory
6. Auth Matrix
7. Security Findings
8. Cross-user Isolation
9. Public API
10. Firestore/Data Integrity
11. Sync/App Contract
12. AI Model Security
13. AI Model Lifecycle
14. Prediction Correctness
15. Docker/Nginx
16. Dashboard Functional Findings
17. UI/UX Design System
18. Information Architecture
19. Responsive Matrix
20. Browser/Zoom Matrix
21. Accessibility
22. Keyboard/Focus
23. Forms/Dialogs/Tables
24. Charts/Telemetry
25. AI Center UX
26. Network/Partial Failure UX
27. Motion/Performance
28. Visual Regression
29. Dependency Findings
30. Regression Tests Added
31. Blocked Checks
32. Remaining Risks
33. Fix Plan
34. Release Recommendation

Recommendation:

- `BLOCK RELEASE`
- `RELEASE WITH CONDITIONS`
- `READY FOR RELEASE`

---

# 85. EXECUTION PHASES

Không hỏi xác nhận từng phase.

### Phase 1 — Inventory / trust boundary
### Phase 2 — Baseline / build / tests
### Phase 3 — Auth / admin / IDOR
### Phase 4 — Firestore / validation / idempotency
### Phase 5 — AI auth / model security
### Phase 6 — AI lifecycle / concurrency
### Phase 7 — Flutter↔Web contract
### Phase 8 — Dashboard functional QA
### Phase 9 — UI/UX design system
### Phase 10 — Responsive / tables / charts
### Phase 11 — Keyboard / accessibility / zoom
### Phase 12 — Loading / error / partial outage / stale race
### Phase 13 — Docker / Nginx / production config
### Phase 14 — Visual regression / browser matrix
### Phase 15 — Regression tests / final report

Nếu bị block:

ghi `BLOCKED`, lý do chính xác, tiếp tục phần khác.

---

# 86. DEFINITION OF DONE

Audit WEB chỉ hoàn tất khi:

- toàn `web/` inventory;
- commit SHA;
- Python baseline;
- frontend typecheck/build;
- Docker config/build;
- auth matrix;
- admin-key/default config test;
- normal user/admin test;
- User A/B isolation;
- public telemetry/charge test;
- ownerUid spoof;
- malformed Firestore;
- idempotency/retry;
- Flutter contract;
- AI auth;
- upload/path/unsafe deserialize audit;
- model lifecycle;
- manifest/runtime consistency;
- concurrent deploy/rollback;
- AI invalid input/output;
- AI down/timeout;
- CORS/XSS/secret audit;
- Nginx/Docker security;
- every primary page có state matrix;
- 320/375/768/1024/1440 responsive;
- 125/150/200% zoom;
- Chrome/Firefox/WebKit hoặc support matrix rõ;
- keyboard;
- focus;
- screen reader/accessibility tree;
- table/chart QA;
- modal/dialog QA;
- AI Center UX QA;
- stale-response race;
- reduced motion;
- performance profile;
- visual regression;
- mọi P0/P1 có reproduction;
- confirmed bug có regression test nếu feasible;
- final report hoàn thành.

---

# 87. MỤC TIÊU THỰC SỰ

Không chỉ tìm backend bug.

Phải tìm cả những trường hợp:

- backend từ chối đúng nhưng UI làm user tưởng mình có quyền;
- server thành công nhưng UI báo lỗi;
- server thất bại nhưng UI báo success;
- stale response hiển thị sai vehicle/model;
- admin double click tạo hai mutation;
- chart đẹp nhưng truyền đạt sai đơn vị;
- modal đẹp nhưng keyboard không thoát được;
- dashboard đẹp desktop nhưng vỡ tablet/mobile;
- error copy leak chi tiết security;
- model deploy state không phản ánh server truth;
- partial outage làm toàn portal unusable.

**Chỉ gọi WEB READY khi security, data integrity, AI lifecycle và UI/UX cùng đạt release gate.**
