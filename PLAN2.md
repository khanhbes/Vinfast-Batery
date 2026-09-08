# Master QA/UIUX Audit cho VinFast Battery Web

## Tóm tắt

Audit toàn bộ `web/` theo 87 mục và 40 giả thuyết trong `VINFAST_BATTERY_WEB_MASTER_QA_UIUX_AUDIT.md`, gồm Flask API, FastAPI AI, React dashboard, Firebase/Firestore, model lifecycle, Docker/Caddy/Nginx, Tailscale và hợp đồng Flutter ↔ Web.

Audit chạy trên môi trường local cô lập. Tailscale Funnel chỉ dùng cho smoke test read-only. Đợt này chỉ tái hiện lỗi, thêm regression test, thu thập bằng chứng và viết fix proposal; không sửa production code.

## 1. Cô lập và chốt phiên bản audit

- Giữ nguyên nhánh App audit đang dang dở.
- Tạo worktree và nhánh riêng `qa/web-master-audit-2026-09-07`.
- Đưa các thay đổi source thuộc `web/` vào snapshot audit nhưng loại trừ:
  - `.env*` và Firebase credential;
  - model/dataset runtime;
  - APK, cache và log.
- Ghi commit SHA, branch, dirty state, Python, Node, npm, Docker và Compose version.
- Khởi động Docker Desktop; dùng `npm.cmd`/`npx.cmd` để tránh PowerShell execution-policy.
- Tạo:
  - `web/QA_ARCHITECTURE_INVENTORY.md`;
  - `web/QA_TRACEABILITY_MATRIX.md`;
  - `web/QA_AUDIT_REPORT.md`;
  - `web/qa-evidence/`.

Traceability matrix phải ánh xạ đủ 87 phần checklist và `WEB-H1…WEB-UX-H40` tới test case, evidence và trạng thái `PASS/FAIL/BLOCKED/N/A`.

## 2. Test harness và interface

### Backend/AI

- Tổ chức test thành `backend`, `ai`, `contracts`, `security` và `fixtures`.
- Dùng pytest, Flask test client, FastAPI TestClient/httpx.
- Dùng Firebase Auth/Firestore Emulator với User A, User B, Admin A và dữ liệu tách biệt.
- Dùng model store, manifest, APK store và dataset tạm; tuyệt đối không mount dữ liệu runtime thật.
- Dùng fake clock, UUID, HTTP client và fault injection để kiểm tra timeout, retry, duplicate và race.
- Không tạo payload RCE thật; kiểm tra pickle/joblib bằng code audit và model fixture vô hại.

### Dashboard

Bổ sung test-only dependencies:

- Vitest.
- React Testing Library.
- MSW.
- Playwright.
- axe-core.

Tạo test suite cho auth, authorization, Dashboard, Telemetry, AI Center, model lifecycle, responsive, accessibility, network failure và visual regression.

### Interface công khai

- Không thay đổi API/schema production trong đợt audit.
- Tạo bảng hợp đồng Flutter ↔ Flask gồm endpoint, method, payload, response, nullability, unit, timestamp, source/confidence/model version.
- Nếu production code thiếu dependency injection hoặc emulator hook, ghi `TESTABILITY GAP` và đề xuất thay đổi; không refactor trong audit.

## 3. Các giai đoạn audit

### Giai đoạn 1 — Inventory và trust boundary

- Inventory mọi Flask/FastAPI route: method, auth, input, output, Firestore, AI dependency và side effect.
- Map dashboard page/component với API, token và role.
- Map container, port, network, volume, environment, secret và healthcheck.
- Vẽ trust boundary:

```text
Browser → Caddy/Nginx → Flask → Firebase/Firestore
                              → FastAPI → Model runtime/store
Flutter App ──────────────────→ Flask
```

- Xác định identity, dữ liệu không tin cậy, validation, secret transfer và logging risk tại từng boundary.

### Giai đoạn 2 — Baseline

Chạy và lưu nguyên output:

```powershell
python -m compileall .
python -m pytest -v

npm.cmd ci
npm.cmd run lint
npm.cmd run build

docker compose config
docker compose build
docker compose up -d
docker compose ps
```

Không che warning, lỗi dependency, test fail hoặc cấu hình mặc định nguy hiểm.

### Giai đoạn 3 — Authentication và admin authorization

Chạy auth matrix trên mọi endpoint nhạy cảm:

- Anonymous.
- User thường.
- Firebase admin.
- Token malformed, hết hạn, revoked hoặc sai project.
- Admin key đúng, sai và rỗng.
- Bearer kết hợp admin key.
- Firebase unavailable.

Bắt buộc kiểm chứng:

- `DEV_ADMIN_KEY` mặc định không bypass production.
- `ADMIN_EMAILS=*` không hợp lệ trong production.
- Firebase init lỗi phải fail-closed.
- UI không thay thế backend authorization.
- Logout/Back/multi-tab không để lộ cached admin data.
- Normal user không gọi được upload, deploy, rollback, reset, delete hoặc Audit System API.

### Giai đoạn 4 — IDOR, Firestore và dữ liệu

- User A thử đọc/sửa Vehicle, Trip, Charge, Telemetry và Model của User B.
- Backend phải derive UID từ verified token, không tin `ownerUid`, `uid` hoặc `userId` trong body.
- Kiểm tra public telemetry, GPS, charge history và statistics.
- Kiểm tra soft-delete tại API, dashboard, export, history và AI training.
- Fixture malformed gồm null, missing, sai kiểu, timestamp/enum lỗi, SOC ngoài giới hạn, NaN/Infinity và số cực lớn.
- Một document lỗi không được làm hỏng toàn response/page.

### Giai đoạn 5 — Validation, contract và idempotency

- Test JSON rỗng, array/string thay object, nested payload lớn, Unicode, HTML/script và path traversal.
- Invalid input phải trả 4xx, không biến thành 500.
- Kiểm tra contract cho 200/400/401/403/404/409/429/500/503.
- Không trả HTTP 200 giả thành công hoặc leak traceback/token/path.
- Test pagination, filter, sort, cursor khác user và query không giới hạn.
- Mô phỏng server xử lý thành công nhưng client mất response rồi retry.
- Double-click/retry không tạo duplicate record hoặc counter.

### Giai đoạn 6 — AI auth và upload security

- Kiểm tra auth của `/api/admin/ai/*` và `/v1/*`.
- AI container/internal endpoint không được public ngoài ý muốn.
- Kiểm tra upload:
  - extension hợp lệ/không hợp lệ;
  - uppercase/double extension;
  - file rỗng, hỏng, quá lớn;
  - duplicate version;
  - Unicode filename;
  - path traversal và absolute path.
- Không tin MIME type.
- Audit mọi chỗ dùng pickle/joblib và quyền ghi/read của model store.
- Nếu user không tin cậy có thể upload rồi kích hoạt deserialization, phân loại theo P0/P1.

### Giai đoạn 7 — Model lifecycle và concurrency

Kiểm tra state machine:

```text
uploaded → registered → inactive → active
                                  → previous/rollback
                                  → deleted
```

Test:

- Activate model thiếu/hỏng.
- Delete active model.
- Rollback khi không có previous.
- Deploy cùng version hai lần.
- Delete rollback target.
- Reset khi inference đang chạy.
- Deploy B thành công trên manifest nhưng runtime load B thất bại.
- Deploy B/C, deploy/rollback, deploy/delete và activate/reset đồng thời.
- Atomic write, lock và rollback không được corrupt manifest.
- Runtime và manifest phải phản ánh cùng model hoặc báo lỗi/recovery rõ.

### Giai đoạn 8 — Prediction và training pipeline

- Test AI input missing, extra, null, sai kiểu/shape, NaN, Infinity và extreme.
- Output phải hữu hạn; SOC `0..100`, duration không âm, confidence `0..1`.
- Fallback phải có source/version rõ.
- Mô phỏng delay 1, 5, 30 giây và vượt timeout; invalid JSON, missing field, 500 và empty response.
- Flask không treo worker và dashboard không spinner vô hạn.
- Dataset test: empty, một sample, missing column, duplicate, outlier, deleted data và mixed users.
- Kiểm tra train/validation/test leakage, temporal leakage và per-user/global boundary.

### Giai đoạn 9 — Flutter ↔ Web contract

Đối chiếu tự động:

```text
Flutter endpoint/method/payload
↕
Flask route/validation/response
```

Kiểm tra:

- Key name và casing.
- `int`/`double`.
- Timestamp và nullability.
- Vehicle/session/owner ID.
- W và Wh.
- Prediction source, confidence và model version.
- Error/fallback schema.

Contract mismatch quan trọng phải có regression test Python và Dart nếu khả thi.

### Giai đoạn 10 — Dashboard functional và UI state

Mỗi page/component phải có state matrix:

- Initial.
- Loading.
- Success.
- Empty.
- Error.
- Unauthorized.
- Offline.
- Stale.
- Partial outage.
- Mutation pending/success/failure.

Kiểm tra Login, Dashboard, Telemetry, User Management, AI Center, Audit System và Settings.

Đặc biệt:

- Không flash dữ liệu sai user trước khi auth hoàn tất.
- Deploy/rollback/delete có confirm và pending guard.
- UI chỉ đổi trạng thái sau server confirmation.
- Request A đến trễ không ghi đè selection B.
- AI outage không làm toàn portal trắng.
- Error copy không hiện raw Firebase/backend exception.
- CSV export chống formula injection và không vượt quyền user.

### Giai đoạn 11 — Responsive, browser và accessibility

Viewport:

```text
320, 375, 480, 768, 1024, 1280, 1440, 1920px
```

Zoom:

```text
80%, 100%, 125%, 150%, 200%
```

Browser:

- Chromium.
- Microsoft Edge.
- Firefox.
- WebKit.

Kiểm tra:

- Sidebar/drawer và Topbar.
- Table, chart, filter và modal.
- Không mất CTA, body overflow hoặc modal vượt viewport.
- Keyboard: Tab, Shift+Tab, Enter, Space, Escape và arrow keys.
- Focus trap và focus restoration.
- WCAG 2.2 AA cho core flow.
- Heading, landmark, label, table semantics, aria-live và toast.
- Không dùng màu làm tín hiệu duy nhất.
- Tôn trọng `prefers-reduced-motion`.

### Giai đoạn 12 — Network, dữ liệu lớn và performance

Mô phỏng:

- Offline.
- 500 ms latency.
- Fast/Slow 3G.
- 429, 500, 502 và 503.
- AI-only/Firebase-only outage.
- Response malformed hoặc HTML thay JSON.

Dataset:

```text
10, 100, 1.000, 10.000 record
```

Đo:

- Initial bundle/load.
- Dashboard render.
- Large table/chart.
- Modal open.
- React rerender và DOM size.
- Layout shift và memory.

Ngưỡng ghi defect:

- Core interaction p95 trên 500 ms với dữ liệu local.
- Main-thread long task trên 50 ms.
- CLS trên 0,1.
- Slow request gây duplicate mutation/retry hoặc toast spam.
- Memory tăng liên tục khi thay filter/page.
- Table/chart treo hoặc không usable với fixture lớn.

### Giai đoạn 13 — Docker, ingress và fail-closed

- Audit resolved Compose environment nhưng redact toàn bộ secret.
- Kiểm tra container root, writable filesystem, volume và port exposure.
- API/AI không public trực tiếp trong laptop-only architecture.
- Kiểm tra upload/request size limit.
- CORS với production origin, localhost, evil origin, null origin và OPTIONS.
- Kiểm tra CSP, HSTS tại HTTPS boundary, frame protection, Referrer-Policy, `X-Content-Type-Options` và Permissions-Policy.
- Missing/default admin key, AI token hoặc Firebase credential phải fail startup hoặc deny privileged operation.
- Không sử dụng DigitalOcean/VPS.

Chỉ smoke test read-only:

```text
https://khanhbes.tailaafca5.ts.net/api/health
```

### Giai đoạn 14 — Visual regression

Playwright screenshot tối thiểu:

- Login.
- Dashboard.
- Telemetry.
- AI Center.
- Model Catalog.
- Model Detail.
- Upload Dialog.
- Audit/System.
- Unauthorized.
- Partial outage.

Chạy tại 375, 768 và 1440 px; bao phủ loaded, empty, error, unauthorized và modal-open khi phù hợp.

## 4. Evidence và báo cáo

Lưu bằng chứng tại:

```text
web/qa-evidence/
  api/
  screenshots/
  traces/
  videos/
  accessibility/
  performance/
  logs/
  visual-diffs/
```

Bằng chứng phải redact token, UID thật, admin key, Firebase credential và đường dẫn chứa secret.

Mỗi phát hiện dùng đúng mẫu:

- `WEB-BUG-XXX`.
- `WEB-UX-XXX`.
- `SEC-XXX`.

Báo cáo cuối gồm architecture, threat model, API/auth matrix, security, user isolation, AI lifecycle, Flutter contract, Docker, dashboard UI/UX, responsive, accessibility, performance, regression tests, blocked checks, fix plan và remaining risks.

## Test hoàn tất và release gate

Audit chỉ hoàn tất khi:

- Đủ 87 mục và 40 giả thuyết có kết quả.
- Python/frontend/Docker baseline đã chạy.
- Auth matrix, IDOR, owner spoof và soft-delete đã kiểm tra.
- Model upload/lifecycle/concurrency đã kiểm tra bằng store tạm.
- Flutter ↔ Web contract đã đối chiếu.
- Mọi primary page có state matrix.
- Responsive, zoom, browser, keyboard và accessibility matrix đã chạy.
- P0/P1 có reproduction và evidence.
- Bug xác nhận có regression test nếu khả thi.

Kết luận chỉ dùng một trong:

```text
BLOCK RELEASE
RELEASE WITH CONDITIONS
READY FOR RELEASE
```

Không được `READY FOR RELEASE` nếu còn admin bypass, cross-user leak, unsafe model loading, model corruption, duplicate mutation, production fail-open, cached admin data leak, stale response sai vehicle/model hoặc core dashboard không usable bằng keyboard/viewport hỗ trợ.

## Giả định đã chốt

- Web audit dùng worktree riêng và không ảnh hưởng App audit.
- Môi trường chính là local Docker + Firebase Emulator + model/data tạm.
- Tailscale chỉ smoke test read-only.
- Không dùng DigitalOcean.
- Không kiểm thử phá hoại trên production.
- Không sửa production code trong audit; chỉ thêm test harness, regression test, evidence và fix proposal.
