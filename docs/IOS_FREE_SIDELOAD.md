# Cài VinFast Battery lên iPhone miễn phí từ Windows

Đây là bản cài thử cá nhân, không phải bản App Store/TestFlight. GitHub Actions
biên dịch ứng dụng trên macOS, sau đó công cụ sideload trên Windows ký ứng dụng
bằng Apple ID miễn phí.

## Giới hạn

- Chứng nhận miễn phí thường hết hạn sau 7 ngày; cần cắm iPhone và cài/ký lại.
- iOS giới hạn số ứng dụng sideload đồng thời với tài khoản miễn phí.
- Push notification/APNs không hoạt động trong bản miễn phí này.
- Các chức năng Firebase chỉ hoạt động sau khi cấu hình iOS app thật trong
  Firebase Console.

## 1. Cấu hình Firebase miễn phí

1. Mở Firebase Console, chọn project `vinfast-873db`.
2. Thêm iOS app với bundle ID `com.khanhbes.vinfastbattery`.
3. Tải `GoogleService-Info.plist` và thay file
   `app/ios/Runner/GoogleService-Info.plist` trong repo.
4. Thay `apiKey` và `appId` iOS trong `app/lib/firebase_options.dart` bằng giá
   trị từ cấu hình Firebase vừa tải.

Không sử dụng hoặc commit file Firebase Admin SDK JSON vào ứng dụng.

## 2. Tạo IPA trên GitHub

1. Mở repository `Vinfast-Batery` trên GitHub.
2. Chọn **Actions** > **iOS free sideload IPA** > **Run workflow**.
3. Chờ job hoàn tất.
4. Mở job, tải artifact **VinFast-Battery-iOS-free-sideload** và giải nén để
   lấy `VinFast-Battery-unsigned.ipa`.

## 3. Ký và cài từ Windows

1. Cài iTunes và iCloud bản tải trực tiếp từ Apple nếu công cụ sideload yêu cầu.
2. Cài Sideloadly từ trang chính thức của dự án.
3. Kết nối iPhone bằng cáp, mở khóa máy và chọn **Trust This Computer**.
4. Kéo `VinFast-Battery-unsigned.ipa` vào Sideloadly.
5. Dùng một Apple ID riêng dành cho sideload, thực hiện xác thực hai lớp nếu
   được yêu cầu, rồi bắt đầu cài.
6. Trên iPhone, bật **Developer Mode** nếu iOS yêu cầu và tin cậy ứng dụng tại
   **Settings > General > VPN & Device Management**.

Khi ứng dụng hết hạn, lặp lại bước ký/cài. Dữ liệu trên máy có thể bị mất nếu
gỡ ứng dụng, vì vậy nên đồng bộ dữ liệu quan trọng với backend trước.
