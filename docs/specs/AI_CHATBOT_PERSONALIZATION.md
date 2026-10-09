# AI Chatbot Cá Nhân Hóa — Đặc Tả Kỹ Thuật & Kế Hoạch Triển Khai

> **Phiên bản**: v1.1.0 — 07/10/2026
> **Mục tiêu hiện hành**: BatteryBot local, kiến thức app và công cụ có xác nhận; dự đoán từ model mobile hợp lệ, lịch nhắc local-first và học adapter nhỏ opt-in. Gemini/SSE bên dưới là thiết kế lịch sử, không phải cấu hình production hiện hành.

## Worker fencing/readiness — Task99 (09/10/2026)

- Tiếp nối98: `smartChargeWorkerLeases/{scope}` là transaction server-only, một worker holder/epoch, TTL180s; epoch tombstone không xóa sau release. Heartbeat≤90s chỉ hợp lệ khi worker/epoch khớp lease live đọc từ Firestore. Client không đọc/ghi lease/heartbeat; UUID/epoch không được coi là quyền điều khiển phần cứng của người dùng.
- Worker kiểm lease trước/sau readback, trước backup OFF và sau thời gian chờ limiter ngay trước HTTP dispatch. Holder cũ không poll hoặc invalidate heartbeat holder mới; không tự giải phóng device/session unknown. Request đã gửi không thể thu hồi, nên fencing chưa thay thế device lock, timer và readback.
- Probe private `/health` là liveness, `/ready` chỉ successful scan + lease/freshness; lỗi/stale/startup trả503. Probe CLI nhẹ không import API/AI. Worker entry vẫn import server factory, chưa có boot/RAM/image benchmark. Không diễn giải probe200 là “đã kết nối Shelly”.
- Guard dùng read-only fence mới, không renew/ghi Firestore cho mỗi request khi lease còn>60s. Scan bình thường không làm readiness flapping; lỗi scan thực vẫn báo unavailable. Firestore reads/writes và AI dependency hiện tại phải được tính riêng trước pilot, không chỉ compute20USD.
- Backend435Pass/10skips đã kiểm; Rules45 assertions/transaction10Pass local, kết quả source-final tại PROJECT_STATUS99.3. Không deploy Azure/Rules, không APK mới, không ON/OFF thật. Bộ gate cũ của mobile137 không chứng minh backend mới.
- Fresh Safe Boot/config fingerprint mỗi ON, shared polling/OFF priority, image0,5GiB/pilot/two-runtime và supervised hardware vẫn **Blocked/Planned**. Chat chỉ qua adapter backend-authorized có xác nhận; worker khỏe không cho LLM bỏ qua safety hoặc tự tạo lệnh.

## Cổng điều khiển Shelly — Task98 (09/10/2026)

- Backend bổ sung heartbeat reconciliation server-only theo môi trường (`SMART_CHARGE_WORKER_SCOPE`, freshness≤90s). Thiếu/lỗi/stale khóa ON, safety-test và LAN authorization; OFF/recovery vẫn giữ đường an toàn. `workerUnavailable` là lý do khóa điều khiển, không làm mất membership hoặc bằng chứng verification lịch sử. Azure staging policy vẫn khóa phần cứng kể cả heartbeat khỏe.
- Worker dùng Device ID bất biến của phiên, không binding xe vừa đổi. Readback thiếu/wrong-device/offline/relay không boolean không phải bằng chứng OFF. Unknown/stopping giữ lease; transaction không cho stale active ghi đè terminal/unknown. Lease LAN có kind riêng, chỉ release sau readback server OFF và transaction kiểm exact UID/operation/membership; boolean client không phải evidence.
- Legacy env-backed Cloud không cấp ON; giữ đọc/OFF phục hồi với parser strict dùng chung vault. Enrollment/vault đã kiểm mới là hướng bật sạc. Không lấy settings/evidence cache hoặc nhãn “đã liên kết” làm quyền ON.
- Hardware worker không tự chạy ingestion/train AI; các hàm legacy còn giữ riêng. AI/chat vẫn local theo quyết định trước; guard worker không cấp cho LLM quyền tạo lệnh hoặc bỏ qua thẻ xác nhận.
- **Automated verified hẹp:** backend411Pass/9skip (9 Emulator chạy riêng), Rules43 assertions và transaction9Pass; source297files0findings. **Chưa deploy** backend/rules hoặc build APK mới. OnePlus137 là artifact cũ củaTask96.9. Chi tiết log/exit, Fail trung gian và blocker ở `PROJECT_STATUS.md` Task98.
- **Blocked:** exclusive worker lease/health/image/RAM, fresh config/fingerprint mỗi ON, shared OFF priority/polling, pilot cloud và hardware supervised readback. Ngân sách worker~20USD không phải permission deploy/ON; chatbot điều khiển thật chưa được chứng nhận.

## Tiếp nối — Task 95 (07/10/2026)

- **Automated verified; Runtime verified hẹp trên QA +131/OnePlus:** chatbot có đề xuất đổi ngày/hủy lịch qua allowlist `edit_reminder/cancel_reminder`. Chỉ chọn khi người dùng nêu loại lịch, ngày cũ (và ngày mới khi sửa), khớp đúng một lịch của xe hiện tại; không tự chọn lịch đầu tiên. Mọi thay đổi cần thẻ xác nhận và context UID/xe còn hợp lệ. Đã tạo lịch QA riêng → đổi ngày → restart giữ ngày mới → hủy → restart/readback không còn active. Chưa có màn chỉnh sửa riêng, chưa hỗ trợ sửa tiêu đề hoặc mốc nhắc tùy chỉnh; notification delivery/deep-link, offline/two-runtime/reboot chưa nghiệm thu.
- Lịch có optional `state=active/cancelled`, `operationId` và revision; local thêm `syncConflict` không upload. Firestore transaction chấp nhận revision kế tiếp hoặc receipt giống hệt, từ chối edit tái tạo document đã xóa và terminal quay lại active. Lưu local trước network/OS, hủy pending không bị giấu thành danh sách empty; bản conflict giữ để phục hồi nhưng không phát nhắc. Cần cơ chế chọn bản khi conflict và test đa máy trước sign-off; không tự giải quyết bằng cách ghi đè.
- Rules giữ tương thích legacy không có state/operationId, chặn hard-delete tombstone để bản offline cũ không tái tạo lịch. Emulator toàn ruleset **41 assertions/exit0**, gồm concurrent edit/cancel từ hai client cùng UID chỉ một winner. Lỗi cleanup thông báo không nuốt thành thành công; retry pending receipt xử lý lại OS cleanup, startup/resume xử lý tombstone không phát lệnh relay. Nhắc ngày vẫn 7/1 ngày09:00 Asia/Ho_Chi_Minh, không cam kết phút chính xác. Đã đọc/backup/diff production rồi hỏi trước deploy; người dùng duyệt toàn diff, deploy rules-only exit0, active ruleset `5c384356-0660-488c-97e4-feb511ed38a3` source/hash khớp. Không đổi indexes/backend/ON policy. Kết quả và rollback evidence tại Task95 PROJECT_STATUS; lịch QA hủy bằng tombstone, không hard-delete.
- **Bổ sung provenance người dùng:** khoảng80 chuyến đo thực tế của **một VinFast Feliz 2025**, SOC **nhập tay**. Nhãn manual không phải BMS. Audit raw109/processed77 nhóm cần đối soát trước split/training; không suy model dùng được cho xe khác. JSON evidence mới giữ riêng, không sửa dataset gốc hoặc bản audit cũ. Charging900 vẫn synthetic từ6phiên, chưa đạt held-out measured gate.
- Task95 sau phục hồi quyền: **894 Flutter Pass/exit0**, related235Pass; direct Dart analyzer toàn `lib test` no issues/exit0, Flutter CLI root vẫn **timeout120s/exit1**. Backend344Pass/4skipped, gateway59Pass, dashboard lint/build exit0, source275files0findings. APK **1.1.9+131** đã build/cài giữ data trên OnePlus, installed hash khớp artifact; preview đúng lịch QA đã kiểm trực tiếp. Chưa suy preview/automated Pass thành reminder notification/two-device hoặc toàn AI gate Pass. Bằng chứng, deploy/runtime/hardware và blockers đầy đủ xem `PROJECT_STATUS.md` Task95. Ghi nhận revoked token đầu lượt được giữ như lịch sử, không còn là blocker hiện hành.

## Đối chiếu dữ liệu và OnePlus — Task 94 (07/10/2026)

- Đã nhận đúng OnePlus 9 Pro/LE2125/API34 và cập nhật giữ dữ liệu lên QA +127; các kiểm tra read-only cho pin/FAQ, ngoài phạm vi và preview/hủy lịch hoạt động. Yêu cầu bật sạc không phát relay: tài khoản/xe hiện chưa có binding server phù hợp, Azure ON/rearm vẫn khóa. Chưa coi phần cứng hoặc LLM đã nghiệm thu.
- Header chatbot bản sửa +128 tách tên xe/nguồn pin khỏi nhóm nút 48dp để không cắt tên xe; lời chào và unavailable message ngắn, không mô tả pipeline kỹ thuật. HTTP service được tái sử dụng theo account/vehicle context và đóng khi invalidated, không fallback Direct Cloud.
- Runtime +128 phát hiện gợi ý server xuất hiện muộn và chào sai buổi. Bản sửa +129 chuyển provider gợi ý sang local-only, không upload UID/xe/SOC; chỉ hiển thị khi hội thoại còn idle và chưa nhập, bỏ kết quả đến muộn sau tương tác/đổi UID. Gợi ý pin thấp chỉ điều hướng, không cấp quyền hoặc chuẩn bị relay. Không dùng runtime +128 làm bằng chứng sửa +129; test/artifact/runtime tương ứng được ghi riêng tại Task94.
- Runtime +129 phát hiện lịch sử rỗng sau reopen dù có dữ liệu trong phiên. Bản sửa +130 thống nhất Android encrypted storage cho history/reminders/calibration với session/Shelly, giữ namespace và không bật reset-on-error. Plugin9.2.4 có migration khỏi legacy store nên không trộn bare default(false) với encrypted(true). Unit mocks không mô phỏng được đầy đủ migration native: phải kiểm reopen/process restart trên đúng APK, không dùng unit Pass thay runtime. Không tự xóa credential, lịch sử hoặc bật học cá nhân.
- QA +130 đã cài giữ dữ liệu, installed APK hash khớp artifact; toàn Flutter876Pass/exit0. OnePlus đọc lại history11tin từ +129 qua close/reopen và process restart, mở nội dung đúng và giữ thẻ đã hủy; FAQ mới/nút về Tổng quan hoạt động. Đây là nghiệm thu hẹp cho history/FAQ/lifecycle, không phải native LLM, mọi lịch legacy, reminder ghi/nhắc thật hoặc phần cứng. Hash/test/runtime ledger và blocker đầy đủ tại Task94; +128/+129 giữ nguyên làm bằng chứng lỗi trung gian.
- Người dùng cung cấp `EV_AI_Model/data/raw` và `data/processed`. Audit chỉ đọc, không sửa nguồn hoặc ghi tọa độ/ID từng dòng vào log. `charging.csv` có **6 phiên**; `charging_900.csv` có **900 dòng tăng cường/mô phỏng từ dữ liệu đó**, SOC nhập tay (người dùng xác nhận). Không dùng 900 dòng này làm independent measured holdout hoặc bằng chứng độ chính xác thực tế.
- `trips_enriched.csv`:77.108 dòng nhưng **77 chuyến**; `trip3.csv`:77 dòng/77 chuyến; raw trips:111.091 dòng/109 chuyến. Provenance của nhãn chuyến chưa được xác minh. Các đoạn cùng chuyến/descendant cùng phiên phải cùng split. Không tự gọi tất cả dòng là số mẫu độc lập hoặc nguồn BMS.
- Pipeline **ngoài repository** `EV_AI_Model/scripts/train_charging_time.py` vẫn suy `avg_charge_rate` từ `duration_min` là target; dùng test cho early stopping/model selection. Fix `web/ai_server/fine_tune.py` trong Task93 không tự sửa pipeline bên ngoài. Script consumption dùng thống kê tốc độ/gia tốc thực tế sau chuyến; không mặc định các feature này đã biết trước chuyến cần dự đoán. File gốc giữ nguyên.
- Bước model tiếp theo: tạo dataset manifest có nguồn SOC/nhãn và nhóm phiên gốc, bỏ feature từ target/feature chưa biết tại inference, tạo train/validation/test theo thời gian và nhóm; cần >=20 phiên đo độc lập chỉ dành test ngoài train/validation trước sign-off. Dữ liệu mô phỏng chỉ dùng nghiên cứu, không tự đặt `qualityVerified=true`; hiện prediction mobile vẫn unavailable. Evidence: `batterybot-phone-dataset-audit-20261007.log`, `batterybot-phone-dataset-provenance-20261007.json` trong thư mục QA hiện có.
- Qwen native/download, hiệu chỉnh tự động có thermal/battery/job gates, sửa/hủy lịch và notification deep-link vẫn là các task riêng chưa hoàn tất; kiểm trên điện thoại không tự làm những gate này đạt. Artifact/hash/runtime cuối của lượt này xem Task94 `PROJECT_STATUS.md`.

## Triển khai BatteryBot local v1 — Task 93 (07/10/2026)

### Ranh giới đã triển khai

`InteractiveAssistantSheet / ChatController → ChatApiService(localOnly) → LocalChatEngine → ChatToolGateway`.

- `local_chat_engine.dart`: interface `LocalChatEngine`, `AppKnowledgeRepository`, FAQ tiếng Việt, intent allowlist và proposal trong RAM. Đọc dữ liệu không ghi; tạo lịch/ON/OFF chỉ qua thẻ xác nhận. Arguments thực thi không serialize vào lịch sử. Logout/đổi xe hủy proposal; thẻ khôi phục từ lịch sử không tự có quyền thực thi. Một proposal được consume trước await, không resend ON sau lỗi/timeout.
- `app_chat_tool_gateway.dart`: lấy UID/xe từ context app, không từ câu trả lời model; gọi **ServerSmartChargerRepository** cho phần cứng, không fallback Direct Cloud. Kiểm lại binding/device và live capabilities trước ON, session ID/device/version trước Stop; chỉ nói thành công sau readback. Request guard được kiểm lại trước lấy token và trước gửi request. Timeout/cancel vô hiệu tác vụ đang chờ. Azure staging vẫn khóa ON/rearm: adapter này không thay thế worker/safety gate backend.
- `chat_message_bubble.dart` và `action_confirmation_card.dart`: thẻ thời gian có giây nguồn làm tròn lên phút, model version/thời điểm và nhãn ước tính; thiếu/NaN/malformed data không tạo số. Thẻ hành động wrap, nút 48dp, unknown không mang nhãn thành công. Câu hỏi nhạy cảm bị chặn **trước** khi lưu tin nhắn. Lịch sử local giữ tối đa 50 tin nhắn mỗi session, không upload mặc định.
- `account_reminder_service.dart`: tạo lịch bảo hành/bảo dưỡng/lịch hẹn bằng operation ID, Secure Storage UID-scoped trước network; offline giữ pending. Theo dõi `users/{uid}/reminders`, revision, hủy/reschedule khi remote thay đổi/xóa; không coi lỗi remote là empty thật. Mặc định ngày cụ thể dd/mm/yyyy, giờ Việt Nam, nhắc trước 7/1 ngày lúc 09:00, inexact alarm, không tự xin quyền và không chứa nội dung tài khoản trong notification. ID notification được cấp từ registry bền vững để xử lý va chạm hash. Rules mới chỉ kiểm bằng emulator, **chưa deploy production**.
- `behavior_tracker.dart`: consent mặc định tắt theo UID; có bật/tắt/reset trong UI, không cập nhật thói quen khi chưa đồng ý. Memory thống kê hiện dùng SharedPreferences UID-scoped; không gọi đó là dataset mã hóa. Dataset/adapter nhỏ có `LocalCalibrationStore` dùng Secure Storage, chưa có pipeline tự thu mẫu/publish.

### Dự đoán và học cá nhân: bằng chứng, không suy đoán

- Ba PKL đã audit bytecode mà không `pickle.load`: cùng hash, thiếu provenance và metadata train/eval. **Chưa chuyển/đóng gói model quãng đường hoặc thời gian sạc đã kiểm chứng**. SOC service bỏ mô phỏng, không upload SOC/SoH/confidence giả; giữ API legacy nhưng trả unavailable.
- `fine_tune.py` bỏ feature tốc độ suy từ chính actual duration, dùng feature `reference_charge_rate=22.5` giống inference. Contract mới `charging_time/v2`, output seconds, `qualityVerified=false` cho đến đánh giá. Fix leakage làm artifact cũ không còn được tự chấp nhận; không chứng minh model mới đã chính xác.
- Runtime charging chỉ nhận manifest đúng task/schema/feature order/output, quality marker và SHA-256/file size. Native TFLite load vẫn bắt buộc. Manifest/hashes không phải safety evidence hoặc quyền ON; chưa có artifact production vượt contract này.
- `local_personal_calibration.dart`: ridge adapter thời gian sạc; loại nhãn chưa verified, nonfinite và session trùng. Tối thiểu 60 mẫu để tách >=30 train/10 validation/20 test và >=14 ngày, chia thời gian không chồng; MAE cải thiện >=2%, RMSE không xấu hơn 3%, absolute bias không tăng trên validation **và** test. Đây là thuật toán standalone đã test, **chưa phải tính năng học tự động đã chạy trên điện thoại**.

### Phần còn lại phải triển khai/nghiệm thu độc lập

1. Corpus hướng dẫn có version/route và bộ đánh giá câu trả lời 200 câu riêng biệt. Bộ test intent hiện có 200 biến thể (25 câu × 8 prefix), không phải benchmark chất lượng LLM tiếng Việt.
2. Dataset/model gốc có provenance, applicability theo xe, preprocessing, parity và held-out quality; export TFLite thật, manifest đáng tin cậy. Interface prediction typed đầy đủ nguồn SOC, freshness đầu vào, Wh vào ổ/pin và giá điện xác nhận; quãng đường/chi phí hiện chưa khả dụng.
3. UI/công cụ sửa/hủy lịch có preview; timezone/lead time tùy chọn, transaction conflict/receipt; deep-link notification tới đúng lịch. Reboot/upgrade/đa máy/force-stop phải test trên Android thật, không suy từ unit tests.
4. Adapter control: thêm tests fault injection ở gateway thật, binding/membership revision và hai runtime; backend worker luôn chạy, device timer/readback, ON policy phải nghiệm thu riêng. Không tạo tài nguyên Azure có phí hoặc tự mở khóa ON trong Task 93.
5. Native llama.cpp: pin revision/license/ABI, bridge Flutter không HTTP localhost; model manager consent/resume/SHA-256, Qwen3-1.7B Q8_0 khoảng 1,83GB; context 2048, max256, no-thinking, timeout30s/cancel/low-memory/unload theo UID. **Chưa có bridge, downloader hoặc weights được nghiệm thu**. Không tăng minSdk app để ép mọi thiết bị dùng LLM.
6. Dataset UID+xe mã hóa, nhãn thật không dùng SOC ước tính; consent riêng cho học model, lấy mẫu có provenance; scheduler đang sạc điện thoại/pin>=50%/không nóng/không phiên Shelly pending-active-unknown, tối đa một job/ngày, deadline60s; atomic candidate/active, rollback/reset và range adapter. **Chưa nối calibration vào inference hoặc tự huấn luyện**.

### Cổng nghiệm thu

Ba gate riêng: **LLM local**, **học/prediction local**, **Shelly backend**. FAQ/công cụ/lịch tự động test đạt không làm các gate kia đạt. Kiểm OnePlus 9 Pro >=8GB, model đã load p95 token đầu<=5s, tổng<=30s, không OOM/ANR, đổi UID không rò, không chặn Stop. Lịch phải xin quyền sau thao tác người dùng; không cam kết nhắc đúng phút khi máy tắt/force-stop. APK QA mới không là release sign-off; kết quả/hash/exit code tại Task 93 của `PROJECT_STATUS.md`.

## Đính chính kiến trúc hiện hành — 07/10/2026

Nội dung Gemini/SSE/cloud training bên dưới được giữ để đối soát phiên bản cũ; không được dùng làm chỉ dẫn bật lại cloud AI mặc định. Người dùng đã chọn AI, chatbot và cá nhân hóa trên điện thoại; web/Azure quản lý tài khoản, xe, Shelly và quyền điều khiển phần cứng. Kết quả triển khai/test hiện hành ở Tasks 91–93 của `PROJECT_STATUS.md`; phần Task 93 ở trên ưu tiên hơn mô tả cũ bên dưới.

- Chatbot hiện dùng FAQ local; lịch sử và behavior không upload trong provider production. Chưa có LLM hoặc fine-tune LLM được nghiệm thu. Không gọi FAQ là model sinh văn bản.
- Forecast sạc local chỉ để tham khảo (`isDisplayOnly`); confidence chưa đo phải để trống. Không dùng forecast làm safety evidence, preview receipt hoặc quyền ON. Điều khiển hẹn giờ/Stop giữ auth, ownership, timer/readback và policy backend. Không tự chuyển forecast thành lệnh relay.
- Không tự gửi mẫu huấn luyện lên cloud; queue training cũ được giữ, chưa migrate sang dataset local. Xác nhận SOC cuối phục vụ lịch sử dùng luồng riêng. Chưa triển khai thuật toán học/cá nhân hóa mới; không khẳng định đã train trên điện thoại.
- Người dùng chấp nhận tải model riêng khoảng **1–2 GB**, ưu tiên tiếng Việt. Ứng viên cần benchmark: [Qwen3-1.7B](https://huggingface.co/Qwen/Qwen3-1.7B) (Apache-2.0, multilingual), bản [GGUF Q8_0 chính thức khoảng 1,83 GB](https://huggingface.co/Qwen/Qwen3-1.7B-GGUF/tree/main). Đây là lựa chọn thử nghiệm, không phải bảo đảm chất lượng tiếng Việt/RAM/tốc độ. Chưa tải hoặc đóng gói weights vào APK.
- Runtime dự kiến tham khảo [Android binding của llama.cpp](https://github.com/ggml-org/llama.cpp/blob/master/docs/android.md), native ARM64 chạy trong ứng dụng, không localhost HTTP server. Phải pin revision nguồn, kiểm giấy phép, SHA-256 weights, ABI và page-size trước dùng. Context/token budget khởi điểm cần thử nhỏ; giới hạn thực tế chỉ chốt sau benchmark bộ nhớ, nhiệt, pin, hủy inference và background/resume trên điện thoại thật.
- Cá nhân hóa hội thoại local (memory/retrieval/style) và hiệu chỉnh model dự đoán nhỏ là hai hạng mục riêng với fine-tune trọng số LLM. Không đánh đồng chúng. Fine-tune LLM trên điện thoại chưa có runtime/training-memory/thermal evidence; không cam kết chỉ từ dung lượng weights.
- Backend vẫn là nguồn cấp quyền Shelly; model chỉ đưa thông tin hoặc yêu cầu mở màn xác nhận. Không dùng văn bản/model-generated tool args để bỏ qua ownership hoặc safety gate. Chưa thay đổi cloud deployment hoặc xóa model/dữ liệu legacy.

### Cổng trước khi tích hợp LLM local

1. Xác minh RAM/ABI/storage trống trên điện thoại thử, chọn weights có revision/hash/giấy phép cố định; tải có consent, progress/cancel và kiểm toàn vẹn trước load.
2. Tích hợp native runtime có stream cancellation, timeout, unload và teardown khi UID đổi; không gửi prompt/history lên cloud nếu lỗi.
3. Benchmark tiếng Việt với FAQ sản phẩm, câu không biết, prompt injection và câu điều khiển nguy hiểm. Không bịa số đo, không phát lệnh relay, không in credential/UID/host nội bộ.
4. Thử offline, low-memory, nhiệt cao, background/resume và APK release đúng hash; chỉ gọi LLM local hoạt động sau bằng chứng runtime. FAQ vẫn là fallback an toàn.

> **Đối chiếu triển khai 06/10/2026:** Các dấu `[x]` bên dưới là ghi nhận lịch sử, không chứng nhận nghiệm thu runtime. Xem Task 66 trong `PROJECT_STATUS.md` cho kết quả hiện hành. Đã sửa auth/UID isolation, SSE/error handling, dữ liệu giả và xác nhận lệnh giả; chưa nghiệm thu Gemini thật, dữ liệu lịch sử đa máy, retention/TTL thực tế hoặc adapter điều khiển sạc. Lưu chat local hiện dùng Secure Storage theo UID, chưa phải Hive/Isar. Văn bản Gemini được đệm để kiểm duyệt trước khi phát, chưa đạt streaming từng token như thiết kế. Nhập giọng nói chưa có recognizer thật và được vô hiệu hóa; chatbot không gửi lệnh relay.

> **Kiểm tra tiếp theo 06/10/2026:** Task 67 trong `PROJECT_STATUS.md` bổ sung regression UID/token, phản hồi và lịch sử, hủy stream/action theo vòng đời session, guardrail an toàn và dependency Gemini trong image. Người dùng đã cho phép QA Gemini giả lập và restart riêng AI sau khi cấu hình private env. Chưa chạy Gemini thật hoặc nối adapter điều khiển sạc; các giới hạn Task 66 vẫn áp dụng.

---

## 1. Kiến Trúc Tổng Thể

```text
                   ┌──────────────────────────────────────────────────────────┐
                   │                  FLUTTER MOBILE APP                      │
                   │                                                          │
                   │  ┌─────────────────┐  ┌────────────────────────────────┐ │
                   │  │ BatteryBot       │  │ Behavior Tracker               │ │
                   │  │ (Upgraded AI)    │  │ - Charging habits observer     │ │
                   │  │ - Floating Mascot│  │ - Trip pattern analyzer        │ │
                   │  │ - Chat Sheet     │  │ - App usage logger             │ │
                   │  │ - Rich Cards     │  │ - Interaction feedback store   │ │
                   │  │ - SSE Streaming  │  │ - Settings preferences cache  │ │
                   │  │ - Voice Input    │  └──────────┬─────────────────────┘ │
                   │  └────────┬────────┘              │                      │
                   │           │                       │  Sync khi có mạng    │
                   │  ┌────────┴────────┐  ┌──────────┴─────────────────────┐ │
                   │  │ Local Chat DB   │  │ Local Behavior Cache           │ │
                   │  │ (Hive/Isar)     │  │ (Hive/Isar)                    │ │
                   │  └────────┬────────┘  └──────────┬─────────────────────┘ │
                   └───────────┼───────────────────────┼──────────────────────┘
                               │ HTTPS + SSE            │ HTTPS (batch sync)
                               ▼                        ▼
                   ┌──────────────────────────────────────────────────────────┐
                   │              UNIFIED FLASK API (server.py : 5000)        │
                   │                                                          │
                   │  ┌─────────────────────────────────────────────────────┐ │
                   │  │ /api/chat/*          → Chat Proxy & Session Mgr    │ │
                   │  │ /api/behavior/*      → Behavior Ingestion & Query  │ │
                   │  │ /api/chat/feedback/* → Feedback Collection          │ │
                   │  └──────────┬──────────────────────────────────────────┘ │
                   └─────────────┼────────────────────────────────────────────┘
                                 │ Internal HTTP (Port 8001)
                                 ▼
                   ┌──────────────────────────────────────────────────────────┐
                   │           FASTAPI AI SERVICE (ai_server : 8001)          │
                   │                                                          │
                   │  ┌─────────────────────────────────────────────────────┐ │
                   │  │ ChatEngine                                          │ │
                   │  │ - Google Gemini 2.0 Flash / Pro API client          │ │
                   │  │ - System Prompt Builder (behavior + vehicle ctx)    │ │
                   │  │ - Function Calling Dispatcher                      │ │
                   │  │ - SSE Response Streamer                             │ │
                   │  │ - Conversation Memory Manager (sliding window)     │ │
                   │  ├─────────────────────────────────────────────────────┤ │
                   │  │ BehaviorAnalyzer                                    │ │
                   │  │ - User Profile Aggregator (patterns, preferences)  │ │
                   │  │ - Proactive Suggestion Generator                   │ │
                   │  │ - Feedback-weighted Response Tuner                 │ │
                   │  ├─────────────────────────────────────────────────────┤ │
                   │  │ ToolRegistry (Function Calling)                     │ │
                   │  │ - get_battery_status      → Telemetry Service      │ │
                   │  │ - get_charging_history     → Firestore             │ │
                   │  │ - start_smart_charging     → Gateway (8002) + HITL │ │
                   │  │ - schedule_charging        → Scheduler             │ │
                   │  │ - get_trip_summary         → Firestore             │ │
                   │  │ - get_maintenance_schedule → Vehicle Catalog       │ │
                   │  │ - get_energy_tips          → BehaviorAnalyzer      │ │
                   │  └─────────────────────────────────────────────────────┘ │
                   │                                                          │
                   │  ┌────────────┐  ┌──────────────┐  ┌─────────────────┐  │
                   │  │ Firestore  │  │ Gemini API   │  │ Gateway :8002   │  │
                   │  │ (behavior  │  │ (LLM calls)  │  │ (Shelly relay)  │  │
                   │  │  + chat)   │  │              │  │                 │  │
                   │  └────────────┘  └──────────────┘  └─────────────────┘  │
                   └──────────────────────────────────────────────────────────┘
```

---

## 2. Behavior Learning System — Hệ Thống Học Hành Vi

### 2.1. Dữ Liệu Hành Vi Thu Thập

| Danh mục | Sự kiện cụ thể | Cách thu thập | Tần suất |
|---|---|---|---|
| **Thói quen sạc** | Thời điểm bắt đầu/kết thúc sạc, mốc SoC mục tiêu, tần suất sạc/tuần, sạc ban ngày vs ban đêm | `SmartChargingControlScreen` callbacks + Gateway telemetry | Mỗi phiên sạc |
| **Lịch sử chuyến đi** | Khoảng cách, tiêu thụ Wh/km, tuyến thường xuyên, thời gian di chuyển | `TripPlannerScreen` + GPS tracking | Mỗi chuyến |
| **Thời gian dùng app** | Tab nào mở nhiều nhất, thời lượng mỗi phiên, giờ mở app thường xuyên | `NavigationObserver` + `AppLifecycleState` | Real-time |
| **Tương tác chatbot** | Câu hỏi thường hỏi, chủ đề quan tâm, phản hồi 👍/👎, action chips đã chọn | `ChatSession` event logger | Mỗi tương tác |
| **Tùy chọn cài đặt** | Ngôn ngữ, theme, thông báo bật/tắt, xe đang active | `SettingsScreen` change listener | Khi thay đổi |

### 2.2. Behavior Profile Schema (Firestore)

```
Firestore Path: users/{uid}/behaviorProfile/current
```

```json
{
  "schemaVersion": "behavior-profile/v1",
  "userId": "uid-abc-123",
  "vehicleId": "VF-EVO200-001",
  "updatedAt": "2026-10-02T15:00:00Z",
  "syncedAt": "2026-10-02T15:05:00Z",

  "chargingPatterns": {
    "preferredStartHour": 22,
    "preferredEndHour": 6,
    "avgTargetSoc": 80,
    "avgSessionsPerWeek": 4.2,
    "preferNightCharging": true,
    "avgChargeDurationMinutes": 195,
    "lastChargingEvent": "2026-10-01T22:30:00Z"
  },

  "tripPatterns": {
    "avgDailyDistanceKm": 18.5,
    "avgEnergyConsumptionWhPerKm": 32.4,
    "frequentRoutes": [
      {"name": "Nhà → Công ty", "distanceKm": 12.3, "count": 45},
      {"name": "Nhà → Siêu thị", "distanceKm": 3.8, "count": 12}
    ],
    "peakUsageHours": [7, 8, 17, 18],
    "totalTrips": 127
  },

  "appUsage": {
    "avgSessionMinutes": 4.2,
    "mostVisitedTabs": ["dashboard", "smart_charging", "battery_monitor"],
    "preferredTheme": "dark",
    "appOpenHours": [7, 12, 18, 22],
    "totalSessions": 312
  },

  "chatPreferences": {
    "topTopics": ["charging_schedule", "battery_health", "energy_tips"],
    "feedbackStats": {
      "totalThumbsUp": 45,
      "totalThumbsDown": 3,
      "topRatedTopics": ["charging_schedule", "maintenance_reminder"]
    },
    "preferredResponseLength": "concise",
    "languagePreference": "vi"
  },

  "personalInsights": {
    "batteryHealthTrend": "stable",
    "chargingEfficiencyScore": 0.87,
    "estimatedMonthlyCostVND": 185000,
    "nextMaintenanceOdoKm": 10000,
    "currentOdoKm": 8750
  }
}
```

### 2.3. Cơ Chế Lưu Trữ Hybrid (Local + Firestore)

```text
┌─────────────────────────────────────────────────────────────────┐
│                    Behavior Data Flow                            │
│                                                                 │
│  [Event xảy ra]                                                 │
│       │                                                         │
│       ▼                                                         │
│  ┌─────────────┐    Ghi ngay     ┌───────────────┐              │
│  │ Tracker      │ ──────────────► │ Local Hive DB │              │
│  │ (in-memory)  │                 │ (behaviorBox) │              │
│  └─────────────┘                 └───────┬───────┘              │
│                                          │                      │
│                              Debounce 5 phút / khi app pause    │
│                                          │                      │
│                                          ▼                      │
│                                  ┌───────────────┐              │
│                                  │ Sync Engine   │              │
│                                  │ - Merge local │              │
│                                  │   + remote    │              │
│                                  │ - Conflict:   │              │
│                                  │   latest wins │              │
│                                  └───────┬───────┘              │
│                                          │                      │
│                              Khi có mạng (connectivity check)   │
│                                          │                      │
│                                          ▼                      │
│                                  ┌───────────────┐              │
│                                  │ Firestore     │              │
│                                  │ behaviorProfile│             │
│                                  └───────────────┘              │
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. Chat Engine — Backend AI Service

### 3.1. Google Gemini API Integration

```python
# web/ai_server/chat_engine.py (Cấu trúc module mới)

# Gemini Model: gemini-2.0-flash (nhanh, rẻ) hoặc gemini-1.5-pro (phức tạp)
# Authentication: GOOGLE_API_KEY env variable
# Rate limit: 15 RPM (free) / 1000 RPM (pay-as-you-go)
# Context window: 1M tokens (flash) — đủ cho multi-turn + behavior context
```

**System Prompt Template** (được inject behavior profile):

```text
Bạn là BatteryBot — trợ lý AI thông minh chuyên về pin xe máy điện VinFast.

## Thông tin xe hiện tại:
- Xe: {vehicle_model} ({vehicle_id})
- Pin: {soc}% (SoH: {soh}%)
- Trạng thái sạc: {charging_status}
- ODO: {odo_km} km

## Hồ sơ hành vi người dùng:
- Thường sạc lúc: {preferred_start_hour}h - {preferred_end_hour}h
- Mốc SoC yêu thích: {avg_target_soc}%
- Quãng đường hàng ngày: {avg_daily_distance_km} km
- Tiêu thụ trung bình: {avg_energy_consumption} Wh/km
- Tab thường dùng: {most_visited_tabs}
- Chủ đề hay hỏi: {top_topics}

## Quy tắc:
1. Trả lời ngắn gọn, thân thiện, bằng tiếng Việt.
2. Gợi ý dựa trên hành vi thực tế của người dùng, không phải thông tin chung chung.
3. Khi đề xuất hành động (bật sạc, đặt lịch...), PHẢI dùng function calling, KHÔNG tự ý thực hiện.
4. Cảnh báo an toàn: dòng sạc ≤12A / 2500W, không khuyến khích sạc >90% thường xuyên.
5. Khi không chắc chắn, nói rõ và hỏi thêm thông tin.
```

### 3.2. Function Calling — Tool Registry

| Tool Name | Mô tả | Parameters | Safety Gate |
|---|---|---|---|
| `get_battery_status` | Lấy trạng thái pin hiện tại (SoC, SoH, V, T°C) | `vehicle_id` | Không |
| `get_charging_history` | Lịch sử sạc N ngày gần nhất | `vehicle_id`, `days` (default 7) | Không |
| `start_smart_charging` | **Bật sạc** với mốc SoC mục tiêu | `vehicle_id`, `target_soc`, `max_amps` | **Human-in-the-Loop** |
| `stop_smart_charging` | **Tắt sạc** | `vehicle_id` | **Human-in-the-Loop** |
| `schedule_charging` | Hẹn giờ sạc tương lai | `vehicle_id`, `start_time`, `target_soc` | **Human-in-the-Loop** |
| `get_trip_summary` | Tóm tắt chuyến đi gần đây | `vehicle_id`, `days` | Không |
| `get_maintenance_info` | Lịch bảo dưỡng tiếp theo | `vehicle_id` | Không |
| `get_energy_tips` | Mẹo tiết kiệm pin cá nhân hóa | `vehicle_id` | Không |
| `get_weather_impact` | Ảnh hưởng thời tiết đến pin | `location` | Không |

**Human-in-the-Loop Flow** (cho các tool có Safety Gate):

```text
Gemini trả function_call ──► Backend tạo ActionConfirmation ──► Flutter render Rich Card
                                                                        │
                                                            Người dùng bấm [XÁC NHẬN]
                                                                        │
                                                                        ▼
                                                            Backend verify lease + safety
                                                                        │
                                                                        ▼
                                                            Gateway execute (Port 8002)
                                                                        │
                                                                        ▼
                                                            Kết quả trả về chat stream
```

### 3.3. Conversation Memory — Multi-turn Context

```python
# Sliding window: giữ 20 messages gần nhất trong context
# System prompt + behavior profile: ~800 tokens
# Total context budget per request: ~4000 tokens
# Chiến lược:
#   1. System prompt (cố định, inject behavior)
#   2. Summary of older messages (nếu session > 20 messages)
#   3. Last 20 messages verbatim
#   4. Current user message
```

---

## 4. API Endpoints — Chat Service

### 4.1. Flask Proxy Routes (server.py)

```
POST   /api/chat/send              → Gửi tin nhắn, nhận SSE stream
GET    /api/chat/sessions          → Danh sách phiên chat (paginated)
GET    /api/chat/sessions/{id}     → Chi tiết 1 phiên với messages
DELETE /api/chat/sessions/{id}     → Xóa phiên chat
POST   /api/chat/feedback          → Gửi 👍/👎 cho 1 message
POST   /api/chat/action/confirm    → Xác nhận thực hiện function call
POST   /api/behavior/sync          → Đồng bộ behavior profile từ mobile
GET    /api/behavior/profile       → Lấy behavior profile hiện tại
GET    /api/behavior/suggestions   → Lấy danh sách gợi ý proactive
```

### 4.2. Chat Send Request/Response

**Request** `POST /api/chat/send`:
```json
{
  "sessionId": "session-2026-10-02-001",
  "message": "Pin mình còn bao nhiêu phần trăm?",
  "vehicleContext": {
    "vehicleId": "VF-EVO200-001",
    "currentSoc": 65,
    "currentSoh": 97,
    "chargingStatus": "idle",
    "odoKm": 8750
  }
}
```

**Response** (Server-Sent Events stream):
```
event: message_start
data: {"messageId": "msg-abc-123", "sessionId": "session-2026-10-02-001"}

event: text_delta
data: {"delta": "Pin xe "}

event: text_delta
data: {"delta": "Evo200 của bạn "}

event: text_delta
data: {"delta": "đang ở mức **65%** "}

event: text_delta
data: {"delta": "(SoH: 97%). "}

event: text_delta
data: {"delta": "Với quãng đường hàng ngày ~18.5 km, bạn còn đủ cho khoảng **2 ngày** nữa trước khi cần sạc. "}

event: text_delta
data: {"delta": "Bạn thường sạc lúc 22h — muốn mình hẹn giờ sạc tối nay không? 🔋"}

event: message_end
data: {"messageId": "msg-abc-123", "usage": {"inputTokens": 856, "outputTokens": 67}}
```

**Response khi có Function Call**:
```
event: function_call
data: {
  "callId": "call-xyz-789",
  "toolName": "start_smart_charging",
  "args": {"vehicle_id": "VF-EVO200-001", "target_soc": 80, "max_amps": 10},
  "requiresConfirmation": true,
  "confirmationCard": {
    "title": "Bật sạc thông minh",
    "description": "Sạc xe Evo200 đến 80%, giới hạn 10A / 2200W",
    "estimatedTime": "~3 giờ 15 phút",
    "safetyNote": "Tự ngắt khi đạt mốc hoặc phát hiện bất thường",
    "actions": ["confirm", "cancel"]
  }
}
```

### 4.3. Feedback Request

**Request** `POST /api/chat/feedback`:
```json
{
  "sessionId": "session-2026-10-02-001",
  "messageId": "msg-abc-123",
  "rating": "thumbs_up",
  "comment": null
}
```

---

## 5. Chat History — Lưu Trữ Hybrid

### 5.1. Local Database Schema (Hive/Isar)

```dart
// Chat Session
@HiveType(typeId: 20)
class ChatSession {
  @HiveField(0) String sessionId;
  @HiveField(1) String title;           // Auto-generated từ message đầu
  @HiveField(2) DateTime createdAt;
  @HiveField(3) DateTime lastMessageAt;
  @HiveField(4) int messageCount;
  @HiveField(5) bool syncedToCloud;
  @HiveField(6) String? vehicleId;
}

// Chat Message
@HiveType(typeId: 21)
class ChatMessage {
  @HiveField(0) String messageId;
  @HiveField(1) String sessionId;
  @HiveField(2) String content;         // Markdown text
  @HiveField(3) bool fromBot;
  @HiveField(4) DateTime timestamp;
  @HiveField(5) String? functionCallId; // Nếu là action card
  @HiveField(6) String? feedbackRating; // thumbs_up / thumbs_down / null
  @HiveField(7) bool syncedToCloud;
}
```

### 5.2. Firestore Schema

```
Firestore Path: users/{uid}/chatSessions/{sessionId}
```

```json
{
  "sessionId": "session-2026-10-02-001",
  "title": "Kiểm tra pin và hẹn sạc",
  "vehicleId": "VF-EVO200-001",
  "createdAt": "2026-10-02T15:00:00Z",
  "lastMessageAt": "2026-10-02T15:05:00Z",
  "messageCount": 8,
  "messages": [
    {
      "messageId": "msg-001",
      "role": "user",
      "content": "Pin mình còn bao nhiêu?",
      "timestamp": "2026-10-02T15:00:01Z"
    },
    {
      "messageId": "msg-002",
      "role": "assistant",
      "content": "Pin xe Evo200 đang ở mức **65%**...",
      "timestamp": "2026-10-02T15:00:03Z",
      "feedbackRating": "thumbs_up"
    }
  ],
  "expiresAt": "2026-11-01T15:00:00Z"
}
```

### 5.3. Sync Strategy

| Trigger | Hành động |
|---|---|
| Tin nhắn mới (online) | Gửi API + lưu local đồng thời |
| Tin nhắn mới (offline) | Chỉ lưu local, đánh dấu `syncedToCloud = false` |
| App resume từ background | Sync tất cả messages chưa sync |
| Mỗi 15 phút (app foreground) | Batch sync sessions đã thay đổi |
| Đăng nhập thiết bị mới | Pull toàn bộ sessions từ Firestore |

---

## 6. Proactive Suggestions — Gợi Ý Chủ Động

### 6.1. Suggestion Engine (Backend)

BehaviorAnalyzer chạy cron job phân tích profile và tạo danh sách gợi ý:

| Rule ID | Điều kiện | Gợi ý | Ưu tiên |
|---|---|---|---|
| `R001` | SoC < 20% + không có lịch sạc | "Pin còn {soc}%. Hẹn sạc tối nay nhé?" | HIGH |
| `R002` | Chưa sạc > 3 ngày + SoC < 40% | "Đã {days} ngày chưa sạc. Nên sạc sớm!" | HIGH |
| `R003` | ODO sắp chạm mốc bảo dưỡng (< 500km) | "Còn {remaining}km đến kỳ bảo dưỡng" | MEDIUM |
| `R004` | SoH giảm > 2% trong 30 ngày | "SoH giảm {delta}%. Xem phân tích chi tiết?" | MEDIUM |
| `R005` | Hay sạc > 90% | "Sạc 80% giúp kéo dài tuổi thọ pin ~20%" | LOW |
| `R006` | Tiêu thụ Wh/km tăng > 15% | "Tiêu thụ tăng. Kiểm tra áp suất lốp?" | LOW |
| `R007` | Tuyến đi lặp lại > 5 lần | "Lộ trình '{route}' quen thuộc. Xem ước tính pin?" | LOW |
| `R008` | Sáng mở app (06:00-08:30) | "Chào buổi sáng! Pin {soc}%, đủ cho {est_km}km" | LOW |

### 6.2. Rate Limiting

- Tối đa **1 proactive bubble / 30 phút** trên client.
- Tối đa **5 gợi ý/ngày** (tránh làm phiền).
- Người dùng có thể tắt proactive trong Settings.
- Gợi ý đã dismiss không hiện lại trong 24h.

---

## 7. Feedback Loop — Vòng Phản Hồi Cải Thiện

### 7.1. Dữ liệu feedback thu thập

```json
{
  "feedbackId": "fb-001",
  "userId": "uid-abc-123",
  "sessionId": "session-2026-10-02-001",
  "messageId": "msg-002",
  "rating": "thumbs_up",
  "messageContent": "Pin xe Evo200 đang ở mức 65%...",
  "userQuery": "Pin mình còn bao nhiêu?",
  "topics": ["battery_status"],
  "timestamp": "2026-10-02T15:00:05Z"
}
```

### 7.2. Sử dụng feedback

1. **Short-term**: Điều chỉnh `preferredResponseLength` trong behavior profile (nhiều 👍 cho câu ngắn → ưu tiên concise).
2. **Medium-term**: Ranking `topRatedTopics` để ưu tiên gợi ý proactive phù hợp.
3. **Long-term**: Tổng hợp feedback toàn hệ thống → cải thiện system prompt, thêm/bớt tools, fine-tune RAG knowledge base.

---

## 8. Flutter UI — Nâng Cấp BatteryBot

### 8.1. Cấu Trúc File Mới

```text
app/lib/features/ai/
├── assistant_sheet.dart          # ← NÂNG CẤP: SSE streaming + rich cards
├── controllers/
│   ├── chat_controller.dart      # [MỚI] Riverpod controller cho chat state
│   └── behavior_tracker.dart     # [MỚI] Thu thập & sync behavior data
├── models/
│   ├── chat_session.dart         # [MỚI] Chat session model + Hive adapter
│   ├── chat_message.dart         # [MỚI] Chat message model + Hive adapter
│   ├── behavior_profile.dart     # [MỚI] Behavior profile model
│   └── function_call_action.dart # [MỚI] Action confirmation model
├── services/
│   ├── chat_api_service.dart     # [MỚI] HTTP + SSE client cho chat
│   ├── behavior_sync_service.dart# [MỚI] Hybrid sync engine
│   └── suggestion_service.dart   # [MỚI] Proactive suggestion client
├── widgets/
│   ├── chat_message_bubble.dart  # [MỚI] Bubble với markdown + feedback
│   ├── action_confirmation_card.dart # [MỚI] Rich card cho function call
│   ├── streaming_text_widget.dart    # [MỚI] Animated streaming text
│   ├── chat_input_bar.dart       # [MỚI] Input + voice + send button
│   ├── quick_action_chips.dart   # [MỚI] Context-aware suggestion chips
│   └── battery_bot_mascot.dart   # ← CẬP NHẬT: thêm proactive bubble
└── smart_charging_control_screen.dart  # Không thay đổi
```

### 8.2. UI Components

#### Chat Message Bubble
```
┌──────────────────────────────────────────┐
│  🤖 BatteryBot                    15:00  │
│                                          │
│  Pin xe Evo200 đang ở mức **65%**        │
│  (SoH: 97%). Với quãng đường hàng ngày  │
│  ~18.5 km, bạn còn đủ cho khoảng        │
│  **2 ngày** nữa trước khi cần sạc.      │
│                                          │
│  Bạn thường sạc lúc 22h — muốn mình     │
│  hẹn giờ sạc tối nay không? 🔋           │
│                                          │
│                            👍  👎        │
└──────────────────────────────────────────┘
```

#### Action Confirmation Card
```
┌──────────────────────────────────────────┐
│  ⚡ Bật sạc thông minh                   │
│  ─────────────────────────               │
│  🔋 Sạc xe Evo200 đến 80%               │
│  ⚡ Giới hạn: 10A / 2200W               │
│  ⏱️ Ước tính: ~3 giờ 15 phút            │
│  🛡️ Tự ngắt khi đạt mốc hoặc bất thường│
│                                          │
│  ┌──────────┐  ┌─────────────────────┐   │
│  │   HỦY    │  │  ✅ XÁC NHẬN SẠC   │   │
│  └──────────┘  └─────────────────────┘   │
└──────────────────────────────────────────┘
```

#### Streaming Text Animation
```
Pin xe Evo200 đang ở mức █    ← cursor nhấp nháy khi streaming
```

---

## 9. Backend Module — File Map

### 9.1. Cấu Trúc Module Mới

```text
web/ai_server/
├── main.py                     # ← CẬP NHẬT: thêm chat routes
├── chat_engine.py              # [MỚI] Gemini API wrapper + prompt builder
├── chat_tools.py               # [MỚI] Function calling tool definitions
├── chat_memory.py              # [MỚI] Conversation context manager
├── behavior_analyzer.py        # [MỚI] User behavior aggregation
├── suggestion_engine.py        # [MỚI] Proactive suggestion rules
├── chat_schemas.py             # [MỚI] Pydantic models cho chat API
└── ...existing files...

web/
├── server.py                   # ← CẬP NHẬT: thêm /api/chat/* và /api/behavior/* proxy routes
└── ...existing files...
```

### 9.2. Dependencies Mới

```
# Backend (requirements.txt additions)
google-genai>=1.0.0              # Google Gemini Python SDK

# Flutter (pubspec.yaml additions)
hive: ^2.2.3
hive_flutter: ^1.1.0
path_provider: ^2.1.0
speech_to_text: ^7.0.0           # Voice input
flutter_markdown: ^0.7.0          # Render markdown in bubbles
```

---

## 10. Kế Hoạch Triển Khai — 4 Phases

### Phase 1: MVP Foundation (Tuần 1-2)
**Mục tiêu**: Chat cơ bản hoạt động end-to-end.

| Task | File | Ước lượng |
|---|---|---|
| Setup Google Gemini API key + client wrapper | `chat_engine.py` | 2h |
| Chat API endpoints (send + SSE stream) | `main.py`, `server.py` | 4h |
| Conversation memory (sliding window 20 msgs) | `chat_memory.py` | 2h |
| Chat schemas (Pydantic) | `chat_schemas.py` | 1h |
| Flutter: Nâng cấp `assistant_sheet.dart` với SSE | `assistant_sheet.dart` | 6h |
| Flutter: Chat API service | `chat_api_service.dart` | 3h |
| Flutter: Chat message bubble (markdown + timestamp) | `chat_message_bubble.dart` | 3h |
| Flutter: Streaming text widget | `streaming_text_widget.dart` | 2h |
| Flutter: Input bar | `chat_input_bar.dart` | 2h |
| Context injection (vehicle state vào system prompt) | `chat_engine.py` | 2h |
| Backend + Flutter tests | `test/` | 4h |
| **Tổng Phase 1** | | **~31h** |

**Tiêu chí hoàn thành Phase 1**:
- [x] Gửi tin nhắn → nhận phản hồi streaming từ Gemini
- [x] Context xe/pin được inject vào prompt
- [x] Multi-turn conversation hoạt động (nhớ 20 msg)
- [x] UI hiển thị markdown, streaming text animation
- [x] Backend tests ≥ 90% pass, Flutter tests pass (100% pass)

### Phase 2: Behavior Learning + History (Tuần 3-4)
**Mục tiêu**: Thu thập hành vi, lưu lịch sử, cá nhân hóa prompt.

| Task | File | Ước lượng |
|---|---|---|
| Behavior Tracker (event observers) | `behavior_tracker.dart` | 6h |
| Behavior Profile model + Hive adapter | `behavior_profile.dart` | 2h |
| Behavior sync service (hybrid local+Firestore) | `behavior_sync_service.dart` | 4h |
| Backend behavior ingestion endpoint | `server.py`, `behavior_analyzer.py` | 3h |
| System prompt personalization từ behavior | `chat_engine.py` | 3h |
| Chat session model + Hive persistence | `chat_session.dart`, `chat_message.dart` | 3h |
| Chat history UI (session list, load older) | `assistant_sheet.dart` | 4h |
| Firestore chat backup (30-day TTL) | `server.py` | 2h |
| Feedback buttons (👍/👎) + API | `chat_message_bubble.dart`, `server.py` | 3h |
| Backend + Flutter tests | `test/` | 4h |
| **Tổng Phase 2** | | **~34h** |

**Tiêu chí hoàn thành Phase 2**:
- [x] Behavior profile được tạo và cập nhật tự động
- [x] Prompt có chứa thông tin cá nhân hóa → câu trả lời khác biệt theo user
- [x] Chat history persist qua restart app
- [x] Feedback ghi nhận và ảnh hưởng behavior profile
- [x] Sync hybrid hoạt động (offline → online merge)

### Phase 3: Function Calling + Proactive (Tuần 5-6)
**Mục tiêu**: Chatbot thực hiện hành động thật và chủ động gợi ý.

| Task | File | Ước lượng |
|---|---|---|
| Tool registry definitions cho Gemini | `chat_tools.py` | 4h |
| Tool execution dispatcher | `chat_engine.py` | 4h |
| Human-in-the-Loop action confirmation flow | `chat_engine.py`, `server.py` | 3h |
| Action confirmation card widget | `action_confirmation_card.dart` | 4h |
| Connect tools → real services (telemetry, gateway) | `chat_tools.py` | 4h |
| Proactive suggestion engine (rules R001-R008) | `suggestion_engine.py` | 4h |
| Suggestion API endpoint | `server.py` | 2h |
| Flutter suggestion service + proactive bubble | `suggestion_service.dart`, mascot | 4h |
| Quick action chips (context-aware) | `quick_action_chips.dart` | 3h |
| Rate limiting (1/30min, 5/day) | `suggestion_service.dart` | 2h |
| Backend + Flutter tests | `test/` | 5h |
| **Tổng Phase 3** | | **~39h** |

**Tiêu chí hoàn thành Phase 3**:
- [x] Chatbot gọi được function (get_battery_status, start_charging...)
- [x] Action card hiển thị → user confirm → relay bật thật qua Gateway
- [x] Proactive bubble xuất hiện đúng context (pin thấp, buổi sáng...)
- [x] Rate limit hoạt động, không spam user (1/30min, 5/day, dismiss 24h)
- [x] Safety gate: không bao giờ bật sạc mà không qua confirm (≤ 12A / 2500W hardware limit)

### Phase 4: Voice + Polish (Tuần 7-8)
**Mục tiêu**: Voice input, UX polish, performance.

| Task | File | Ước lượng |
|---|---|---|
| Speech-to-text integration (tiếng Việt) | `chat_input_bar.dart` | 6h |
| Voice recording UI (animated waveform) | `chat_input_bar.dart` | 3h |
| Chat controller (Riverpod state management) | `chat_controller.dart` | 4h |
| Performance: lazy load sessions, pagination | `assistant_sheet.dart` | 3h |
| Offline mode: queue messages, show status | `chat_api_service.dart` | 3h |
| Error handling & retry logic | toàn bộ | 3h |
| Accessibility (screen reader, large fonts) | widgets | 2h |
| Integration testing end-to-end | `test/` | 6h |
| **Tổng Phase 4** | | **~30h** |

**Tiêu chí hoàn thành Phase 4**:
- [x] Voice input tiếng Việt hoạt động (speech-to-text) & Animated Voice Waveform
- [x] Offline: message queue + retry khi có mạng (`ChatController`, `isQueued`, `onRetry`)
- [x] Performance: < 200ms UI response, < 1s first token, session pagination (`limit`/`offset`)
- [x] Tất cả tests pass (26/26 Flutter, 19/19 backend), analyzer clean (0 issues)
- [x] APK build thành công (`assembleDebug`)

### Phase 5: Advanced AI Agent & Personalization (Tuần 9-11)
**Mục tiêu**: Nâng cấp lên AI Agent với Native Function Calling, Auto-execute read tools, Guardrails, Adaptive Personality và Rich Media Cards.

#### Phase 5A: Native Function Calling & Streaming Tool Execution
- [x] Chuyển `TOOL_DECLARATIONS` sang Gemini SDK `types.Tool` format (`get_gemini_tools()`).
- [x] Cấu hình `tools` trong `GenerateContentConfig`, Gemini tự quyết định gọi tool.
- [x] Read tools auto-execution loop: Gemini gọi `get_battery_status` → backend tự thực thi → inject `FunctionResponse` → Gemini tiếp tục stream câu trả lời tự nhiên.
- [x] Control tools (Safety-Gated: `start_smart_charging`, `stop_smart_charging`, `schedule_charging`): chặn tự động chạy, emit `ActionConfirmationCard` (≤ 12A / 2500W).
- [x] SSE events mới `event: tool_call` và `event: tool_result` cho client tracking.
- [x] Client Flutter `ChatApiService` hỗ trợ `onToolCall` và `onToolResult` callbacks.
- [x] Backend tests (`test_function_calling_and_proactive.py` 10/10 PASS), Flutter tests (5/5 PASS, 0 analyzer issues).

#### Phase 5B: Guardrails & Adaptive Personality
- [x] `chat_guardrails.py`: Kiểm duyệt thông số xe vs `VehicleCatalog`, an toàn dòng/áp ≤12A/2500W, nhiệt độ ≤75°C, che PII (CCCD/SĐT).
- [x] `personality_adapter.py`: Tự động điều chỉnh giọng văn (concise/detailed/friendly/professional) theo tỷ lệ 👍/👎 và phong cách yêu thích.
- [x] Schema `BehaviorProfile` bổ sung `personalityStyle` và `guardrailViolationCount`, đồng bộ hybrid.
- [x] Test suite `test_guardrails_and_personality.py` đạt 12/12 PASS (100%).

#### Phase 5C: Rich Media Cards & UX Polish
- [x] Schema `RichCardData` và SSE `event: rich_card` với structured payload cho BatteryStatus, ChargingProgress, TripSummary.
- [x] `ChatEngine` tích hợp `_build_rich_card` từ tool output và `_detect_rich_card_intent` cho offline fallback mode.
- [x] Flutter widgets: `BatteryStatusCard` (mini gauge tròn, SoC/SoH/V/T°C/km), `ChargingProgressCard` (tiến độ sạc, W/kW, dòng điện A ≤ 12A, ETA), `TripSummaryCard` (km, Wh, Wh/km, CO₂ saved).
- [x] `QuickReplyChips` động theo ngữ cảnh (pin yếu < 20% -> sạc ngay, đang sạc -> ngắt/tiến độ, mặc định -> hỏi pin/tips).
- [x] `ChatMessageBubble` tự động render các thẻ Rich Media Cards bên dưới nội dung tin nhắn.
- [x] `ChatApiService` và `ChatController` hỗ trợ callback `onRichCard` và gắn vào `ChatMessage.richCards`.
- [x] Bộ test Phase 5C đạt 100% PASS (8/8 backend, 8/8 Flutter, 42/42 tổng backend chatbot, 34/34 tổng Flutter AI).

---

## 11. Bảo Mật & Quyền Riêng Tư

| Concern | Giải pháp |
|---|---|
| Chat content gửi lên Gemini | Chỉ gửi context cần thiết, không gửi PII (tên, SĐT, địa chỉ) |
| Behavior profile | Mã hóa local (Hive encryption), Firestore rules `owner-only` |
| Function calling safety | Human-in-the-Loop bắt buộc cho mọi hành động vật lý |
| API key Gemini | Chỉ lưu trên backend (env), không embed trong app |
| Chat history | TTL 30 ngày trên Firestore, user có thể xóa bất kỳ lúc nào |
| Rate limiting | Backend enforce, chống abuse |

---

## 12. Metrics & KPIs

| Metric | Mục tiêu | Cách đo |
|---|---|---|
| Chat engagement rate | > 30% DAU dùng chat | Sessions/DAU |
| Avg messages per session | 4-6 | Total messages / sessions |
| Thumbs up rate | > 85% | 👍 / (👍 + 👎) |
| Proactive suggestion CTR | > 15% | Clicks / suggestions shown |
| Function call success rate | > 95% | Successful executions / total calls |
| First token latency (P95) | < 800ms | SSE timing |
| Behavior profile completeness | > 70% fields filled after 7 days | Profile audit |

---

## 13. Tham Chiếu Liên Quan

- [BATTERYBOT_ASSISTANT.md](BATTERYBOT_ASSISTANT.md) — Đặc tả UI/UX gốc của BatteryBot (context engine, floating mascot)
- [AI_LIFECYCLE.md](AI_LIFECYCLE.md) — Quy trình huấn luyện, drift, canary AI
- [TELEMETRY_SCHEMA.md](TELEMETRY_SCHEMA.md) — Schema chuẩn pin & sạc
- [VEHICLE_CATALOG.md](VEHICLE_CATALOG.md) — Danh mục xe và định mức pin
## Đồng bộ và adapter điều khiển Shelly — Task96 (07/10/2026)

- BatteryBot dùng repository API backend-authorized, scoped UID/xe và expectedDeviceId; không Direct Cloud fallback. HTTP status/binding/caps/readback cập nhật coordinator chung với Settings/Setup/Charging, không tạo boolean kết nối riêng trong chat.
- Bật theo thời gian có thẻ xác nhận, guard UID/xe/device/revision, một operation và một ON; timeout giữ unknown, bỏ readback OFF cũ trong UI, không retry ON. Stop thành viên thứ hai có thể xử lý relay ON không có phiên riêng bằng backend OFF + readback, không nhận lịch sử/xe riêng của thành viên kia.
- Online/evidence không tự cấp quyền ON. Caps backend chặn phiên active/unknown theo thiết bị; đổi mã/lỗi nhập mã không xóa binding/evidence đã có. Restore thiếu evidence giữ context cho safety test có xác nhận, không tự phát ON/OFF.
- 909 Flutter tests/352 backend Pass trong Task96, Firestore concurrency5cases; đây là tự động/mock/emulator, chưa phải phần cứng. Azure vẫn khóa enrollment/safety/ON vì worker chưa nghiệm thu; người dùng yêu cầu trình chi phí trước deploy. Phương án0,25vCPU/0,5GiB always-on khoảng5,83–19,44USD/tháng compute tùy idle/active khi không còn grant, chưa gồm dịch vụ phụ, không cam kết tổng10USD. Chi tiết gates/nguồn/bằng chứng tại PROJECT_STATUS Task96.

### Tiếp tục Task96 — 09/10/2026, QA 1.1.9+137

- Giữ binding/evidence legacy `advancedDirect` dưới trạng thái **“Đã liên kết · Cần kết nối qua máy chủ”**, không tự chuyển sang server enrollment hoặc cấp quyền ON. Settings/Setup/Sạc pin/BatteryBot đọc cùng coordinator; link, online và control readiness là các khái niệm riêng. Offline không tự yêu cầu chạy lại no-load test.
- Sạc hẹn giờ/kế hoạch subscribe cùng snapshot với header; lý do khóa ưu tiên snapshot. Unlinked, legacy hoặc unknown không mở Start dù capabilities riêng nói ready. Sau consent phải kiểm lại kết nối; tool/repository/backend vẫn kiểm UID/xe/device/revision và readback, không Direct fallback. Hướng dẫn mã quản trị không yêu cầu điện thoại cùng LAN.
- Full Flutter source137 **912Pass/exit0**, direct Dart toàn `lib/test` **No issues/exit0**; kết quả909tests07/10 bên trên là lịch sử. Flutter CLI root còn Timeout riêng. Artifact/runtime được ghi ở `PROJECT_STATUS.md`96.9; automated Pass không chứng nhận enrollment/relay thật.
- APK137 build/cài đúng hash trên OnePlusLE2125/API34; sau restart Sạc pin/Cài đặt giữ cùng nhãn legacy, Setup không tự test. Chat đọc trạng thái từ máy chủ; yêu cầu bật5phút bị chặn trước thẻ ON; snapshot vẫn đúng sau chat. **0relay commands**, chỉ runtime read-only/khóa, chưa điều khiển Shelly thật. Metadata/hash/scope tại `shelly-sync-apk-137-20261009.json` và Status96.9.
- Người dùng chấp nhận khoảng **20USD/tháng cho worker compute**. Giá EastAsia kiểm lại09/10 không đổi; tổng còn API/registry/lưu trữ/log/Firebase. Đây **không phải quyền deploy hay mở ON**. Worker cần immutable session identity, heartbeat/lease và fail-closed, OFF recovery, shared limiter, bỏ AI training server, rồi fault/concurrency/smoke tests và duyệt pilot riêng. Azure staging policy vẫn khóa phần cứng.
