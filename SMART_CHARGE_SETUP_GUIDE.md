# Thiết lập và sử dụng Sạc thông minh

## 1. Chuẩn bị phần cứng

1. Dùng **Shelly Plug S Gen3** chính hãng, firmware mới và tải sạc không vượt **12 A / 2500 W**.
2. Chưa cắm bộ sạc xe vào Shelly.
3. Cài **Shelly Smart Control**, thêm Plug S Gen3 vào Wi-Fi và bật Shelly Cloud.
4. Trong Shelly, đặt hành vi sau mất điện là **OFF** và tắt mọi auto-on/schedule cũ.
5. Điện thoại và Shelly nên cùng Wi-Fi trong lần kiểm tra đầu để LAN fallback hoạt động.

Ứng dụng VinFast Battery không provisioning SSID/password và không đọc SOC từ BMS. Mọi SOC suy ra đều được ghi rõ là **ước tính**.

## 2. Chọn một cách kết nối

### Cách A — Direct Cloud + LAN (khuyên dùng cho tài khoản cá nhân)

1. Mở **Cài đặt → Smart Charger** và chọn **Direct**.
2. Trong Shelly Cloud lấy đúng **Server URI**, **Authorization Cloud Key** và **Device ID** của Plug S Gen3.
3. Nhập Server URI dạng `https://...shelly.cloud`; không thêm path hoặc query.
4. Nhập Cloud Key và Device ID. Key chỉ được lưu trong Android Secure Storage.
5. Bấm **QUÉT** và cho phép quyền “Thiết bị Wi-Fi lân cận”. Nếu mDNS không tìm thấy, nhập IP riêng như `192.168.1.50` hoặc hostname `.local`.
6. Bấm **LƯU & KIỂM TRA KẾT NỐI**. App kiểm tra Cloud/LAN, `switch:0`, power meter và cấu hình khởi động OFF.
7. Khi hộp xác nhận xuất hiện, rút toàn bộ tải rồi chọn **ĐÃ RÚT TẢI · CHẠY TEST**. App sẽ ON 5 giây, OFF và đọc lại relay.
8. Chỉ khi màn hình báo **Sẵn sàng điều khiển** mới cắm bộ sạc xe. Nếu draft lỗi, hồ sơ tốt đang dùng không bị ghi đè.

Không gửi Cloud Key qua chat, log, Firestore hoặc commit Git. Nếu nghi key bị lộ, thu hồi/đổi key trong Shelly và xóa hồ sơ trong app.

### Cách B — Easy Connect / server pilot (một tài khoản cá nhân)

Đây là đường Cloud-first không nhập key vào APK. Quản trị viên server đặt secret trong biến môi trường:

```text
SHELLY_PROVIDER=legacy
SHELLY_LEGACY_HOST=https://<server-của-tài-khoản>.shelly.cloud
SHELLY_LEGACY_AUTH_KEY=<cloud-key>
SHELLY_LEGACY_DEVICE_ID=<device-id>
SHELLY_LEGACY_DEVICE_NAME=Shelly sạc xe
SMART_CHARGE_MAX_MINUTES=600
```

1. Lưu các giá trị trên trong secret manager hoặc environment file chỉ tài khoản service đọc được; không lưu vào repository/Docker image.
2. Cài dependency mới từ `web/requirements.txt`, rồi restart API/container.
3. Build app với `APP_API_BASE_URL` trỏ tới API server.
4. Đăng nhập app, mở **Cài đặt → Smart Charger → Easy / Server** rồi bấm **KIỂM TRA EASY**.
5. Chỉ khi backend trả đủ capability timer/status/OFF thì app mới cho điều khiển. Nếu chưa có Integrator credential, màn hình sẽ báo Easy chưa khả dụng và hướng dẫn dùng Direct.

`legacy` chỉ dành cho mô hình một Shelly Cloud account. Không dùng chung key này cho hệ thống nhiều khách hàng.

### Cách C — Shelly Integrator production

1. Đăng ký Shelly Integrator B2B và nhận Integrator tag/license.
2. Cấu hình `SHELLY_PROVIDER=integrator`, `SHELLY_INTEGRATOR_TAG` và callback HTTPS công khai trong `SHELLY_CONSENT_CALLBACK_URL`.
3. Callback phải giữ nguyên `state` và xác minh header `SCL-Trust` ES384 trước khi bind device.

Hiện public Integrator API chỉ tài liệu hóa relay ON/OFF, chưa tài liệu hóa device timer tương đương `toggle_after`. Vì vậy code **cố ý chặn Start** với `providerTimerUnsupported` trên provider Integrator. Chỉ bật production sau khi Shelly cấp và xác nhận cơ chế timer chạy trên thiết bị; không thay bằng countdown app/server.

## 3. Cách dùng mỗi lần sạc

1. Cắm bộ sạc xe vào Shelly và cắm Shelly vào nguồn; relay phải đang **OFF**.
2. Mở **Sạc thông minh** từ Dashboard hoặc AI Models.
3. Kiểm tra hàng trạng thái: tên Shelly, Cloud/LAN, Relay OFF và công suất.
4. Kiểm tra **SOC hiện tại (ước tính)**. Nếu sai, bấm **Chỉnh**.
5. Chọn mục tiêu **80%**, **90%** hoặc **100%**.
6. Bấm **DỰ ĐOÁN VỚI AI**. Kiểm tra thời lượng, giờ ngắt, nguồn dự đoán và confidence.
7. Nếu cần, mở **Nâng cao** và đặt “Dừng không muộn hơn”. Không phiên nào được vượt 10 giờ.
8. Bấm **SẠC THEO AI**, đọc cảnh báo và xác nhận SOC ước tính. Nếu model chỉ trả fallback, nút này bị khóa; hãy dùng **BẬT SẠC** và chọn timer thủ công.
9. Chờ đến khi app hiển thị **Timer đã cài trên Shelly**. Chỉ lúc đó phiên mới là Active; có thể đóng app.
10. Khi cần dừng sớm, bấm nút đỏ **NGẮT NGUỒN NGAY**. App chỉ báo hoàn tất sau khi đọc lại relay OFF.

## Lịch sử và biểu đồ sau khi sạc

- Ba phiên gần nhất nằm cuối màn **Smart Charge**. Kéo xuống để làm mới; nút reload trên AppBar đã được bỏ.
- Chọn **XEM TOÀN BỘ LỊCH SỬ** để lọc `Tất cả / Sạc AI / Thủ công`, mỗi trang 20 phiên.
- Chạm một phiên để xem biểu đồ công suất, điện áp, dòng điện, nhiệt độ và điện năng tích lũy. Chạm/kéo trên biểu đồ để xem số liệu theo thời điểm.
- Trong lúc relay ON, Android hiển thị notification **Đang theo dõi Smart Charge**. Đây là foreground service riêng, không ảnh hưởng Trip Tracking. Shelly vẫn tự OFF bằng timer trên thiết bị nếu app hoặc Firestore mất kết nối.
- App lấy mẫu status 5 giây, gộp một điểm biểu đồ mỗi 30 giây và ghi một chunk mỗi 5 phút. Summary được giữ lại; telemetry chi tiết có TTL 12 tháng.
- Năng lượng còn trong pin và SOC được ghi rõ là **ước tính, không phải dữ liệu BMS**. Có thể nhập SOC thực tế cuối phiên trong màn chi tiết; app chỉ tính dung lượng khả dụng khi phiên dài ít nhất 20 phút, SOC tăng ít nhất 10%, coverage đạt 70% và Shelly đo energy hợp lệ.
- Nếu hồ sơ xe chưa liên kết VinFast model/dung lượng pin, app hiển thị **Chưa có dữ liệu dung lượng pin** và không dùng giá trị mặc định.

Nếu app báo không xác minh được timer/relay, rút tải hoặc tắt Shelly vật lý ngay. Không bấm Start lặp lại liên tục.

## 4. Kiểm thử bắt buộc trước khi sạc dài

1. Test không tải ON 5 giây rồi OFF.
2. Sạc thử 5–10 phút, kill app và xác nhận Shelly vẫn tự OFF.
3. Sau khi arm timer, tắt Internet điện thoại; Shelly vẫn phải OFF đúng hạn.
4. Với Advanced Direct, mất Cloud nhưng cùng Wi-Fi phải đọc/điều khiển được qua LAN.
5. Rút điện và cấp lại; relay phải trở về OFF.
6. Nhấn nút vật lý OFF trên Shelly; app phải ghi nhận phiên bị gián đoạn.

## 5. Build và auto-update APK

Từ thư mục gốc của repo:

```powershell
.\run.ps1 3
```

Script chạy `pub get`, analyze và toàn bộ test **trước khi tăng version**; sau đó build APK arm64, sao chép `VinFastBattery_latest.apk` sang web server local. API release bắt buộc HTTPS, mặc định là `https://khanhbes.tailaafca5.ts.net`. Smart Charge không còn dùng `SMART_CHARGER_API_BASE_URL`; API chung lấy từ `APP_API_BASE_URL`.

## Runtime hiện tại

Hệ thống vận hành trên laptop với Docker và Tailscale Funnel. Dùng `.\run.ps1 2` (hoặc mở `run.bat` chọn [2])
ở root để build/khởi động stack local; không dùng VPS hoặc SSH. `smart_charger_gateway/`
là gateway legacy/diagnostic, không phải runtime dependency của app/web stack chính.
# AI cá nhân, ETA fusion và lịch sử realtime

## Bật AI cá nhân

1. Đăng nhập và chọn đúng xe trong Garage.
2. Mở **Cài đặt → AI cá nhân**.
3. Bật **Cho phép AI học từ phiên sạc**. Profile được tách riêng theo tài khoản và xe; hai tài khoản có cùng mã xe không dùng chung dữ liệu.
4. Sau mỗi phiên, mở chi tiết lịch sử và nhập SOC thực tế cuối phiên nếu có. SOC này là tùy chọn, nhưng cần thiết để một phiên trở thành mẫu học mục tiêu đầy đủ.
5. Màn hình hiển thị giai đoạn thân thiện: **AI đang làm quen với xe → AI đang học thói quen sạc → Đã cá nhân hóa**. Chi tiết kỹ thuật chỉ dành cho diagnostics.
6. Có thể tắt consent hoặc dùng **Xóa model & dữ liệu cá nhân**. Lịch sử sạc vẫn được giữ, nhưng profile và training sample của xe bị xóa.

Phiên đầy đủ cần kéo dài ít nhất 20 phút, telemetry phủ tối thiểu 70%, energy hợp lệ, SOC tăng ít nhất 10 điểm và SOC cuối do người dùng xác nhận. Phiên bị dừng giữa chừng chỉ có thể học công suất/hiệu suất, không được dùng làm nhãn “đạt mục tiêu”.

## Nhiều xe và binding Shelly

- Mỗi tài khoản có thể có tối đa số xe theo policy server (mặc định 2). Xóa xe trong Garage là **Lưu trữ**, không xóa lịch sử.
- Vehicle Switcher ở thanh trên cùng đổi context của nội dung; phiên đang sạc vẫn khóa với xe và Shelly ban đầu.
- Có thể dùng một Shelly cho nhiều xe ở chế độ shared, nhưng một Shelly vật lý không thể chạy hai phiên cùng lúc.
- Lịch sử mặc định là xe đang chọn; chọn **Tất cả xe** để xem các xe thuộc cùng tài khoản.

## Cách đọc ETA

Preview Smart Charge có thể hiển thị ba nguồn: AI toàn cục, dung lượng/công suất thực và AI cá nhân. ETA cuối là trung bình thích nghi theo độ tin cậy, chất lượng dung lượng, độ ổn định công suất, số phiên học và độ chính xác đã kiểm chứng. Không có dung lượng/công suất đáng tin thì app không tự đặt giá trị giả và chỉ dùng nguồn còn hợp lệ.

Sau 60 giây và tối thiểu 6 mẫu công suất ổn định, app có thể hiệu chỉnh timer nếu ETA lệch ít nhất 3 phút. Timer Shelly luôn là nguồn sự thật và không bao giờ vượt 10 giờ. `hardDeadlineAt` chỉ giới hạn timer khi người dùng chủ động chọn “Dừng không muộn hơn”.

## Dừng sạc và mất mạng

- **Dừng phiên** hỏi xác nhận và giải thích ảnh hưởng tới dữ liệu học.
- **NGẮT NGUỒN NGAY** gửi OFF ngay, không hỏi lại, sau đó readback relay.
- Khi mất Internet, app giữ dữ liệu cuối và hiện notice nổi. Timer đã arm vẫn chạy trên Shelly; nếu LAN còn hoạt động, status/OFF vẫn dùng LAN. Không tạo preview AI mới cho tới khi Internet trở lại.
- Năng lượng mỗi phiên hiển thị từ `0 Wh` bằng delta so với baseline. App không reset công tơ năng lượng trọn đời của Shelly.

## Ngưỡng an toàn mặc định

- Cảnh báo: dòng từ 10,5 A; công suất từ 2300 W; nhiệt độ từ 65 °C; điện áp ngoài 200–250 V.
- OFF tự động sau hai mẫu liên tiếp: dòng từ 11,5 A; công suất từ 2450 W; nhiệt độ từ 75 °C; điện áp ngoài 190–255 V.
- Fault quá nhiệt/quá tải do Shelly báo phải OFF ngay. Nếu không readback được OFF, rút tải hoặc ngắt nguồn vật lý và không tiếp tục sạc.

## Lịch sử realtime

Phiên đang chạy được ghim đầu màn Lịch sử với badge **ĐANG SẠC**, mục tiêu SOC, countdown, power và biểu đồ. Dữ liệu biểu đồ tổng hợp khoảng 30 giây/điểm; khi kết thúc, cùng `sessionId` chuyển sang log terminal nên không tạo bản ghi trùng. Telemetry chi tiết có TTL 12 tháng, summary được giữ lâu dài.
