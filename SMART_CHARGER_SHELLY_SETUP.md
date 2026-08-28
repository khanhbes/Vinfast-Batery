# Thiết lập Sạc thông minh với Shelly Plug S Gen3

## Điều kiện an toàn

- Chỉ dùng Shelly Plug S Gen3; tải sạc đã xác nhận không vượt `12A / 2500W`.
- Thêm thiết bị vào Wi‑Fi và Shelly Cloud bằng app/web Shelly chính thức trước.
- Không đưa Cloud Authorization Key vào `.env`, Git, Firestore, log hoặc tham số build.
- Mỗi phiên bị giới hạn tuyệt đối 6 giờ. SOC trong app luôn là ước tính, không
  phải dữ liệu BMS.

## Kết nối trong app

1. Mở **Cài đặt → Smart Charger → Kết nối Shelly**.
2. Nhập Server URI HTTPS thuộc miền `*.shelly.cloud`, Cloud Authorization Key
   và Device ID lấy từ Shelly app.
3. Khi điện thoại cùng Wi‑Fi, quét mDNS hoặc nhập IP riêng/hostname `.local` để
   bật LAN fallback. Nhập mật khẩu local nếu thiết bị đã bật auth.
4. Chạy kiểm tra Cloud/LAN. App đối chiếu Device ID, chỉ nhận Plug S Gen3 và
   kiểm tra power meter.
5. Chạy **Cấu hình khởi động OFF** qua LAN.
6. Rút toàn bộ tải, xác nhận rồi chạy test ON 5 giây → OFF.

Cloud là đường chính. Nếu Cloud không dùng được, app thử cùng lệnh qua LAN.
Timer tự ngắt nằm trên Shelly nên tiếp tục hoạt động khi app bị đóng hoặc điện
thoại mất Wi‑Fi sau khi timer đã được xác minh.

## Quy trình test thiết bị thật bắt buộc

Không cắm sạc xe cho tới khi test không tải đã thành công và relay OFF được đọc
lại. Sau đó kiểm tra lần lượt: phiên sạc ngắn + kill app; mất Internet với LAN;
mất Wi‑Fi sau khi arm; mất điện/khởi động lại; nút OFF vật lý; và rà soát log/APK
để chắc chắn không có Cloud key hay mật khẩu local.

## Build và cập nhật app

`app/build_apk.ps1` vẫn tăng version, tạo APK, upload và cập nhật
`web/app_config.json` như trước. Script không còn nhận hoặc nhúng
`SMART_CHARGER_API_BASE_URL`; hồ sơ Shelly được nhập sau khi cài app và lưu bằng
Android secure storage.

Gateway FastAPI trong `smart_charger_gateway/` là legacy/diagnostic và không còn
là runtime dependency của ứng dụng.
