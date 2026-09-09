# Web QA — khắc phục và kiểm chứng ngày 09/09/2026

## Phạm vi và kết luận

Đối chiếu `PLAN2.md` và `VINFAST_BATTERY_WEB_MASTER_QA_UIUX_AUDIT.md`.
Người dùng yêu cầu **sửa**, nên đợt này triển khai bản sửa local thay vì chỉ viết fix proposal như kế hoạch audit ban đầu.
Thực hiện trong worktree hiện tại, baseline HEAD `6e595a4`; không tạo nhánh/commit, không chỉnh thay đổi app đang diễn ra song song.

**BLOCK RELEASE** cho toàn bộ master audit. Những bản sửa dưới đây đã có kiểm chứng trong phạm vi ghi rõ, nhưng không đồng nghĩa 87 mục và 40 giả thuyết đã được nghiệm thu đầy đủ.
Không deploy, không điều khiển relay, không training/deploy model thật, không thay credential hoặc dữ liệu runtime.

## Các bản sửa

| Mục audit | Vấn đề / bản sửa | Bằng chứng |
|---|---|---|
| H1, H5, H22 | Khóa dev không còn mặc nhiên vượt Firebase. Chỉ dùng khi opt-in, không production, client loopback và không gửi Bearer. Bearer user không bị nâng quyền bởi khóa dev. | `test_remediation.py`, auth matrix |
| H2 | Wildcard email không nâng mọi user thành admin. | Auth matrix |
| H3, H4, H12 | GET telemetry/charge logs yêu cầu đăng nhập, lọc owner cho user thường; sync battery/trip lấy owner từ identity. | Tests query scope và owner derivation |
| H3, H4, H12, H22 | Personal AI theo xe (degradation/pattern/train/profile status/charge feedback) yêu cầu identity và kiểm tra chủ xe; feedback lấy `ownerUid` từ token. Flutter charge-feedback gửi Bearer token để giữ luồng hợp lệ. | Tests anonymous 401 và User A đọc xe User B nhận 403 |
| H12, H13 | Sync vehicle/full kiểm tra owner và xe liên quan trong cùng transaction với ghi dữ liệu; mọi read trước write. Từ chối cả batch nếu gặp bản ghi của người khác. | Tests fake transaction, endpoint IDOR, malformed batch |
| H15 | Full sync yêu cầu ID ổn định; không dùng vehicleId làm ID chung cho nhiều log, không tạo ID ngẫu nhiên mỗi retry. Đây không phải chứng nhận idempotency cho toàn API. | Test reject missing ID; cần contract E2E bổ sung |
| H8, H24 | Upload/validate-file qua mạng chỉ nhận ONNX/TFLite, giới hạn file 64 MiB; file rỗng/quá lớn bị từ chối và dọn phần tạm. Runtime không thử pickle khi extension không biết. | Upload policy tests; kiểm tra mã cả hai ingress |
| H24, H25 | Kiểm tra version/extension và đường dẫn thực trước truy cập model store. Xóa đúng extension gốc trước khi mất metadata. | Path traversal và remove ONNX regression |
| H9–H11 | Deploy/activate/rollback kiểm tra candidate trước; ghi manifest thành công mới publish predictor. Lifecycle mutation dùng lock cùng runtime. Không xóa active model. Reset không nuốt lỗi rồi báo thành công giả. | Tests validation failure, manifest failure, concurrent deploy, active delete, reset |
| H9, UX-H29, mục 61 | Flask gọi AI deploy, không tự ghi active pointer. Chỉ lưu deployment metadata sau khi AI xác nhận đúng version. | Test upstream failure và wrong-version confirmation |
| WEB-BUG-001 | Bổ sung `safety_policy_version` mà service và serialization đã sử dụng. | Toàn bộ Smart Charge Python tests |
| UX-H28 | Portal không mount trang có dữ liệu quản trị trước khi `/api/auth/me` xác nhận admin đúng UID. Kiểm tra lại khi token thay đổi; user thường có trang giải thích. | Unit test policy; chưa có Firebase Emulator browser E2E |
| UX-H29, H30, H40 | HTTP client có timeout, chỉ retry GET/HEAD với lỗi tạm thời; không retry mutation/401/403/429. Không đưa raw backend exception lên UI. Từ chối HTML giả API response. | `portal-safety.test.ts` |
| H6, H26 | API và hai Caddy gateway bổ sung CSP, HSTS tại biên HTTPS, frame denial, nosniff, referrer/permissions policy; API response không cache. Nginx đồng bộ header và nới multipart ingress từ 50M thành 65M để khớp policy artifact 64 MiB. | Regression test header; `caddy validate`; `nginx -t` trong container tạm |
| H14, H23 | Prediction và model mutation có sliding-window limiter, trả `429` kèm `Retry-After`. CSV export chung và dataset trung hòa text bắt đầu bằng formula marker, kể cả sau khoảng trắng; số âm vẫn giữ kiểu số. | Unit test limiter và CSV formula injection |
| Mục 45–47 | Upload ghi đúng Upload → Test → Deploy, không báo tự kích hoạt. Kiểm tra định dạng/dung lượng/version; giữ form khi lỗi; khóa gửi lặp đồng bộ bằng ref. | Upload policy unit tests + browser fixture |
| UX-H29 | Deploy/delete/deactivate có khóa mutation tức thời; UI không hướng dẫn xóa active model. | Code review; cần mutation E2E thêm |
| UX-H33 | Escape đóng đúng modal con; sau unmount trả focus về nút mở trong modal cha. | Browser: `dialogs=1`, `activeElement.tagName=BUTTON`, text `Upload model` |
| UX-H27, H32, H38 | Dialog có vùng chạm tối thiểu 48px; upload không tràn ngang 320px; danh sách version chọn card/table theo chiều rộng container thực, không theo viewport. Drawer hẹp vẫn hiện đủ nút ở desktop. | Ảnh Chromium fixture, số đo dialog |
| Mục 36, 41, 44, 61 | Dashboard bỏ KPI năng lượng/đường công suất giả lập và các mức tăng tự đặt; không gọi snapshot là realtime. Adapter giữ SOC/SoH thiếu hoặc sai là `null`, không đổi thành 100/0; lỗi Firestore không bị nuốt thành empty state. Cảnh báo không còn gắn giờ hiện tại giả hoặc suy diễn “hệ thống an toàn”. | Regression test normalize, typecheck/build; chưa E2E toàn Dashboard |
| Mục 28–35, 52–60 | Users dùng danh bạ Firebase Auth thật, không dựng email/tên/ngày; bỏ avatar bên thứ ba và hành động giả. Audit dùng `/api/admin/audit-logs`, không biến telemetry thành log có timestamp hiện tại. Settings bỏ CPU/version/2FA/backup giả và nút chết; Smart Charger có label, validation, trạng thái lỗi/thành công và xác nhận thu hồi; AI Studio dẫn tới AI Center. | Typecheck/build; review nguồn dữ liệu và route |
| Tinh gọn runtime | Xóa nhánh legacy không được route/import: `AdminPortal.jsx`, `TelemetryDashboard.jsx`, `SOCChart.tsx`, `socTestService.ts`. Nhánh này chứa UI và dữ liệu mẫu cũ, không tham gia bundle production. | Tìm toàn repo không còn consumer; build production đạt |
| Laptop-only | Xóa script deploy Linux VPS orphan và IP DigitalOcean cũ khỏi Android network security. Cleartext chỉ còn phục vụ Shelly LAN theo kiểm tra đích riêng của Dart; URL public tiếp tục dùng HTTPS Tailscale. | Quét repo không còn URL/IP cũ ngoài ghi chú quyết định trong `PLAN2.md`; XML parse đạt |

## Kiểm chứng đã chạy

- Python: `python -m pytest tests -q --basetemp=<thư mục mới trong workspace> -p no:cacheprovider`.
  Lượt chốt sau ownership Personal AI và cleanup limiter: **154 passed**, 9,40 giây.
- Frontend: `node --import tsx --test tests/*.test.ts`: **27 passed**.
- `npm run lint`: đạt sau các sửa cuối.
- `npm run build`: đạt sau các sửa cuối (27,51 giây). Entry chunk giảm từ **1.003,95 kB / gzip 277,89 kB** còn **159,37 kB / gzip 45,25 kB**; chunk lớn nhất là charts **375,29 kB / gzip 111,64 kB**, không còn cảnh báo >500 kB.
- `git diff --check -- web`: đạt sau khi sửa whitespace; chỉ còn cảnh báo LF/CRLF.
- Compose laptop: `config --quiet` đạt. `caddy validate` xác nhận `Caddyfile.laptop` hợp lệ; `nginx -t` xác nhận cấu hình dashboard hợp lệ khi cấp hostname API fixture. Không in resolved environment/secret.
- AI/API/dashboard đang chạy: healthy. Đây là image cũ, không xác nhận deployment của source vừa sửa.
- Smoke read-only Tailscale `/api/health`: HTTP 200. Không thử endpoint ghi production.
- Android `network_security_config.xml` parse đạt sau khi bỏ IP VPS. Cả `flutter analyze --no-pub` và `dart analyze` theo file lượt cuối đều không trả output sau khoảng hai phút nên đã dừng; không ghi nhận các lượt này là đạt hay thất bại.

### Bằng chứng UI

Ảnh trong `dashboard/output/playwright/`:

- `ai-manager-375-2026-09-09.png`: drawer, nút và version card trên mobile.
- `ai-upload-375-2026-09-09.png`: upload, nhãn trường và hướng dẫn đúng server truth.
- `manager-{320,375,768,1440}-2026-09-09.png`: matrix chụp trước bản chỉnh bảng cuối. Ảnh desktop đã giúp phát hiện header/badge bị bẻ chữ, không được dùng làm golden đạt.
- `upload-320-2026-09-09.png`: chụp trong entrance animation; không dùng làm golden ổn định.
- `manager-final-{320,375,768,1440}-2026-09-09.png`: lượt kiểm tra trước khi đổi breakpoint sang container. Assertion `dialog.scrollWidth <= dialog.clientWidth` đạt tại cả bốn viewport, nhưng ảnh cho thấy drawer desktop cần card để tránh phải cuộn tới nút. Đã đổi sang card khi container <700px, dù viewport desktop rộng.
- `upload-final-320-2026-09-09.png`: ảnh upload ổn định. Assertion Escape giữ một dialog và trả focus về `Upload model` đạt sau lượt này.
- `manager-container-final-{320,375,768,1440}-2026-09-09.png`: bằng chứng sau sửa cuối. Assertions card hiển thị và nút Deactivate nằm trọn chiều ngang viewport đạt tại cả bốn kích thước; đã xem ảnh desktop cuối, không cần cuộn ngang tới hành động.
- `login-320-final-2026-09-09.png`: smoke giao diện đăng nhập ở 320×800 sau lượt build cuối; `body.scrollWidth == body.clientWidth == 320`, snapshot có nhãn trường/nút hiện mật khẩu và console không có error/warning.

Số đo thực tại viewport 320: drawer client/scroll **320/320**, upload **296/296**. Không có tràn ngang của hai dialog trong fixture này.
Fixture cô lập có dữ liệu giả và chặn fetch thật; không chứng minh auth/role, Firestore rules, network production hay model accuracy.

## Thay đổi tương thích cần biết trước triển khai

1. Portal, dataset và global fine-tune cần tài khoản admin do backend xác nhận. Developer Mode trong app không thay thế quyền admin.
2. `DEV_ADMIN_KEY` không còn là cách vào production. Không tự sửa `.env.laptop`; dùng Firebase token/admin claim hoặc allowlist được cấu hình hợp lệ.
3. Upload web chỉ nhận `.onnx`/`.tflite` ≤64 MiB. Model pickle/joblib cũ trên máy vẫn được giữ; không tự chuyển đổi hoặc xóa. Chỉ provision artifact đáng tin cậy từ kênh quản trị ngoài web.
4. Full sync: các collection con phải có `id` ổn định; tối đa 400 bản ghi mỗi request. Request thiếu ID hoặc chứa owner khác trả lỗi thay vì ghi đè/ghi trùng. Cần đối chiếu mọi client ngoài repo trước rollout.
5. Model activation bắt buộc smoke validation đạt; nút bỏ smoke khi upload chỉ lưu candidate, không vượt kiểm tra deploy.
6. Lock lifecycle bảo vệ trong **một AI process**. Chưa chứng minh an toàn multi-worker/multi-host cùng ghi store. Không mở rộng số worker khi chưa có lock liên tiến trình.
7. Rate limiter hiện tại là in-process, phù hợp topology laptop một API process để chặn gửi lặp và abuse cơ bản. Nếu tăng nhiều worker/host, phải chuyển counter sang ingress hoặc kho chia sẻ như Redis.

## Phần chưa hoàn thành / điều kiện release

- Chưa chạy Firebase Auth/Firestore Emulator với User A/B/Admin và transaction contention thực; mock transaction không chứng minh rules hay SDK retry E2E.
- Chưa bao phủ authorization toàn bộ route, revoked token, email verification, SOC history, các ingress telemetry ghi và mọi luồng global training. Nhóm Personal AI chính đã có owner check, nhưng chưa kết luận hệ thống hết IDOR/data leak nếu chưa chạy matrix Emulator đầy đủ.
- Chưa kiểm tra ingress multipart trước khi FastAPI parse/spool toàn request, rate limiting chia sẻ cho multi-worker và bộ dependency security. CSV formula injection đã có regression test; CSP/HSTS đã validate cấu hình nhưng chưa browser-smoke trên image mới.
- Chưa kiểm chứng model artifact thật, lỗi inference khi deploy, upload–reset đồng thời, nhiều Flask worker cập nhật deployment metadata và recovery khi process bị kill.
- Users/Audit/Settings đã có loading/empty/error/retry và bỏ dữ liệu/hành động giả; nhánh Telemetry legacy không được mount đã bị xóa. Chưa hoàn tất E2E các state này sau Firebase Auth thật, network throttling, browser zoom 200%, Firefox/WebKit, screen reader, axe và visual regression tự động.
- Chưa profile 10.000 bản ghi, CLS, long tasks và memory. Bundle đã tách theo route/vendor và hết cảnh báo chunk >500 kB; Dashboard vẫn cần pipeline telemetry thật và chuẩn hóa đầy đủ missing/malformed data tại Firebase adapter.
- Chưa build/recreate Docker stack từ source mới; không dùng health của stack cũ để đánh dấu release mới đạt.

Ưu tiên tiếp: auth/ownership E2E và contract client → ingress/model lifecycle isolation → UI/browser matrix → performance → deployment kiểm soát.
