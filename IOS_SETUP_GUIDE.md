# VinFast Battery iOS / TestFlight checklist

Nhánh `feature/ios-platform` giữ nguyên Android và bổ sung iPhone portrait-only
(iOS 15+), bundle ID `com.khanhbes.vinfastbattery`. Vì Windows không có Xcode,
workflow `.github/workflows/ios.yml` chạy trên macOS để xác nhận unsigned build.

## Firebase và APNs

1. Trong Firebase Console project `vinfast-873db`, thêm iOS app với bundle ID
   `com.khanhbes.vinfastbattery` và tải `GoogleService-Info.plist` thật vào
   `app/ios/Runner/`.
2. Trên máy Mac chạy `flutterfire configure --platforms=ios` để thay
   `app/lib/firebase_options.dart` bằng app ID iOS chính xác.
3. Trong Apple Developer tạo App ID, bật Push Notifications và Background Modes
   (Location updates, Background fetch, Remote notifications). Tạo APNs
   Authentication Key rồi liên kết Team ID/key trong Firebase Cloud Messaging.
4. Device thật là bắt buộc để kiểm tra APNs; simulator chỉ kiểm tra UI/unsigned
   build.

## Local Network và vị trí

`Info.plist` đã khai báo `NSLocalNetworkUsageDescription`, Bonjour
`_shelly._tcp`, ATS `NSAllowsLocalNetworking` (không mở arbitrary loads), và
location usage descriptions. iOS xin When-In-Use trước, sau đó chỉ xin Always
khi người dùng bắt đầu trip nền. Shelly/backend là safety authority; iOS không
chạy vòng lặp Smart Charge 30 giây liên tục.

## Push và API

App đăng ký token qua:

- `PUT /api/mobile/push-tokens/{deviceId}` với token, platform, bundleId,
  appVersion, locale.
- `DELETE /api/mobile/push-tokens/{deviceId}` khi logout/tắt notification.

`deviceId` là UUID trong Keychain/Keystore. Backend lưu token ở
`users/{uid}/pushTokens/{deviceId}` bằng Admin SDK; Firestore rules từ chối mọi
truy cập client. Payload dùng `eventKey = smart_charge:{sessionId}:{state}` để
chống gửi trùng và tự dọn token invalid.

## CI và TestFlight nội bộ

Workflow unsigned chạy `flutter analyze`, toàn bộ Flutter tests, CocoaPods và
`flutter build ios --release --no-codesign`, đồng thời chạy Android regression.
Khi đã có Apple Developer và Mac, cấu hình certificate/provisioning cùng
App Store Connect API key trong GitHub Secrets, kiểm tra bundle ID rồi bật
`ENABLE_IOS_SIGNING=true` cho workflow signing template. Sau khi archive/upload,
thêm internal testers trong App Store Connect và kiểm tra Firebase Auth,
Firestore, APNs, location khi khóa màn hình, Shelly LAN, Smart Charge suspend,
TFLite, PDF/share và deep-link notification trên thiết bị thật.

Không commit Firebase Admin JSON, APNs private key hoặc signing certificate.
