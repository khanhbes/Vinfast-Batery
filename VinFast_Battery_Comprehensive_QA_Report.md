# 🔋 VinFast Battery App — Báo Cáo QA & UX Toàn Diện
**Senior QA Lead & UX Researcher Report**

> **Phiên bản app:** 1.1.3 (Build 4) · **Commit tham chiếu:** `44194aa` (First-run) / `ba9df98` (Master Audit)
> **Ngày tổng hợp:** 18/09/2026 · **Nền tảng:** Flutter Android (Riverpod 2.6.1 · Firebase · Python Flask)
> **Phạm vi:** Flutter Mobile App (`app/`) — toàn bộ 15 feature modules, 25+ screens

---

## 📊 MỤC LỤC

1. [Tổng Quan Kết Quả Test](#1-tổng-quan-kết-quả-test)
2. [Đánh Giá Người Dùng Mới (First-time User)](#2-đánh-giá-người-dùng-mới)
3. [Đánh Giá Người Dùng Lâu Năm (Returning/Power User)](#3-đánh-giá-người-dùng-lâu-năm)
4. [Danh Sách Lỗi & Vấn Đề Phát Hiện](#4-danh-sách-lỗi--vấn-đề-phát-hiện)
5. [So Sánh Với Đối Thủ](#5-so-sánh-với-đối-thủ)
6. [Roadmap Cải Tiến Ưu Tiên](#6-roadmap-cải-tiến-ưu-tiên)
7. [Checklist Test Case Đầy Đủ](#7-checklist-test-case-đầy-đủ)

---

## 1. TỔNG QUAN KẾT QUẢ TEST

### 1.1 Dashboard Tổng Hợp

| Hạng mục | Số lượng | Pass | Fail / Issue |
|:---|:---:|:---:|:---:|
| Screens đã kiểm tra | 25 | — | — |
| Feature modules đã kiểm tra | 15 | — | — |
| Checklist items (CHK) | 59 | 54 | 5 |
| Giả thuyết rủi ro cao (H) | 25 | 23 | 2 |
| Test cases baseline (`flutter test`) | 237 | 233 | 4 |
| Test cases QA audit suite | 18 | 17 | 1 |
| **Tổng bugs xác nhận** | **9** | — | **9** |
| — P0 (Blocker) | 1 | — | 1 |
| — P1 (Critical) | 3 | — | 3 |
| — P2 (Major) | 3 | — | 3 |
| — P3 (Minor) | 2 | — | 2 |

### 1.2 Release Readiness Score

```
╔══════════════════════════════════════════════════════════════╗
║         RELEASE READINESS SCORE: 62 / 100                   ║
║                                                              ║
║  ████████████████████████░░░░░░░░░░░░░░  62%                ║
║                                                              ║
║  Khuyến nghị: ⚠️  RELEASE WITH CONDITIONS                   ║
║  Phát hành được SAU KHI vá xong P0 + P1 (4 bugs)           ║
╚══════════════════════════════════════════════════════════════╝
```

| Tiêu chí | Điểm | Trọng số | Điểm cộng |
|:---|:---:|:---:|:---:|
| Kiến trúc & An toàn kỹ thuật | 9/10 | 20% | 18 |
| Luồng Happy Path (FTUX) | 8/10 | 15% | 12 |
| Xử lý lỗi & Edge Cases | 5/10 | 15% | 7.5 |
| UI/UX & Thẩm mỹ | 6/10 | 20% | 12 |
| Hiệu năng & Bộ nhớ | 7/10 | 10% | 7 |
| Bảo mật & Privacy | 6/10 | 10% | 6 |
| Accessibility | 5/10 | 5% | 2.5 |
| Test Coverage | 8/10 | 5% | 4 |
| **TỔNG** | — | **100%** | **69 → 62*** |

> *Trừ 7 điểm do có 1 P0 Blocker chưa vá. Score sẽ trở lại 69+ sau khi vá P0.

### 1.3 So Sánh Score Trước/Sau Fix

| Giai đoạn | Score | Trạng thái |
|:---|:---:|:---:|
| Hiện tại (chưa vá gì) | **62/100** | ⚠️ Release with conditions |
| Sau khi vá P0 + P1 | **76/100** | 🟡 Beta-ready |
| Sau khi vá hết P2 + cải thiện UX | **88/100** | 🟢 Production-ready |
| Sau Đợt 3 (polish) | **95/100** | 🏆 Premium launch |

---

## 2. ĐÁNH GIÁ NGƯỜI DÙNG MỚI

> **Persona:** Chủ xe VinFast Feliz, 22–35 tuổi, lần đầu cài app sau khi mua xe. Không biết gì về Shelly relay hay AI model.

### 2.1 Luồng Cold Start → Đăng Nhập

| Bước | Trạng thái | Nhận xét |
|:---|:---:|:---|
| Splash screen | ✅ PASS | Dark theme ấn tượng, quả cầu phát sáng emerald đẹp |
| Hiển thị form đăng nhập | ✅ PASS | Rõ ràng, CTA nổi bật |
| Validation email/password | ✅ PASS | 5 thông báo lỗi tiếng Việt đồng thời, viền đỏ chuẩn |
| Bàn phím số điện thoại | ❌ FAIL | Mở QWERTY thay vì numpad — **ISSUE-04** |
| Nút Submit bị bàn phím che | ❌ FAIL | Hoàn toàn mất khỏi màn hình khi bàn phím lên — **ISSUE-03** |
| Khởi động lỗi (mất mạng) | ⚠️ RISK | ANR tiềm ẩn do Overlay chưa mount — **P0** |
| Cold start time | ⚠️ WARNING | >10s trên emulator, cần tối ưu — **P1** |

**Điểm mạnh:**
- Giao diện đăng nhập đẹp, hiện đại, theme dark luxury nhất quán
- Validation form hoạt động chuẩn, thông báo lỗi tiếng Việt rõ ràng
- Nút "Chưa có tài khoản? Đăng ký ngay" đặt đúng vị trí, dễ tìm

**Điểm yếu nghiêm trọng:**
- CTA bị bàn phím che → người dùng mới sẽ tưởng app bị lỗi
- Keyboard type sai → friction ngay ở bước nhập SĐT

### 2.2 Onboarding 8 Bước

| Bước | Nội dung | Trạng thái | Nhận xét |
|:---|:---|:---:|:---|
| 1/8 | Màn chào BatteryBot + 3 card tính năng | ✅ PASS | Tags tiếng Anh trên UI tiếng Việt — **ISSUE-06** |
| 2/8 | Chọn dòng xe (lưới 6 model) | ⚠️ MEDIUM | Avatar xe là chữ cái "E/F/K" thô sơ — **ISSUE-05** |
| 3/8 | Nhập nickname xe, ODO | ⚠️ MEDIUM | Dead space 40% màn hình — **ISSUE-07**; nút bị bàn phím che |
| 4/8 | Ngày sinh (tùy chọn) | ✅ PASS | Nút "Bỏ qua" rõ ràng, không ép buộc |
| 5/8 | Slider quãng đường hàng ngày | ✅ PASS | Tương tác tốt, BatteryBot phản hồi đúng context |
| 6/8 | Mục đích + ngưỡng sạc | ✅ PASS | Mốc khuyến nghị slider trực quan |
| 7/8 | Shelly setup | ✅ PASS | Nút "Thiết lập sau" rõ ràng — KHÔNG ép phần cứng |
| 8/8 | Tổng kết hồ sơ | ✅ PASS | Gamification tốt, cảm giác thành tựu rõ ràng |

**Đánh giá tổng thể Onboarding:** **7/10**
- Progress indicator 8 energy pills độc đáo, rõ luồng
- BatteryBot mascot thân thiện nhưng phong cách chưa "premium automotive"
- Khoảng trắng chết ở bước 3–7 làm app trông chưa xong

### 2.3 Empty States — Điểm Quan Trọng Nhất Với User Mới

| Màn hình | Empty State hiện tại | Đánh giá |
|:---|:---|:---:|
| Tab 1 — Sạc pin | Chỉ 1 dòng xám: *"Hãy chọn xe để sử dụng Smart Charge"*, không có nút | ❌ THẢM HỌA |
| Tab 2 — Lịch sử | Chỉ 1 dòng xám: *"Hãy chọn xe để xem lịch sử sạc"*, không có nút | ❌ THẢM HỌA |
| Tab 1 — AppBar | Tiêu đề AppBar biến mất, chỉ còn icon chuông trơ trọi | ❌ BUG |
| Charge Log | "Chưa có phiên sạc" — OK | ✅ PASS |
| AI Studio | "Chưa có mẫu xe" — OK | ✅ PASS |
| Maintenance | "Không có lịch bảo dưỡng" — OK | ✅ PASS |

> ⚠️ **NHẬN XÉT QUAN TRỌNG:** Người dùng mới sau khi hoàn tất onboarding 8 bước sẽ vào Tab 1 và thấy màn hình đen rỗng với 1 dòng chữ mờ. Đây là ngõ cụt (dead-end) — không có nút nào để thao tác tiếp. Tỷ lệ drop-off tại điểm này có thể lên đến **60-70%**.

### 2.4 Quyền Hệ Thống (Permissions)

| Quyền | Thời điểm xin | Giải thích lý do | Đánh giá |
|:---|:---|:---:|:---:|
| Location | Khi vào Trip Planner | Không có (chỉ xin quyền thẳng) | ⚠️ Cần thêm rationale |
| Notifications | Chưa rõ thời điểm | Chưa xác nhận | ❓ Cần kiểm tra |
| Bluetooth | Không áp dụng (Shelly qua LAN/Cloud) | N/A | ✅ OK |

### 2.5 Thông Báo Lỗi Với User Mới

| Lỗi | Thông báo hiện tại | Đánh giá |
|:---|:---|:---:|
| Mất mạng Firestore | *"TimeoutException after 0:00:08.000000: Không kết nối được Firestore (8s)..."* | ❌ LỘ KỸ THUẬT |
| Mạng yếu lúc đăng nhập | Banner đỏ inline | ✅ OK |
| SOC âm / >100% | Chặn và báo lỗi tiếng Việt | ✅ PASS |

### 2.6 Cảm Giác Tổng Thể First-time User

| Tiêu chí | Điểm (0–10) | Nhận xét |
|:---|:---:|:---|
| Tin tưởng (Trust) | 7 | Thẩm mỹ tốt, nhưng lỗi kỹ thuật lộ ra làm giảm niềm tin |
| Dễ hiểu (Clarity) | 6 | Onboarding tốt nhưng Tab 1/2 empty state gây confusion |
| Tốc độ setup | 7 | 8 bước onboarding nhưng không cảm thấy dài |
| Kỳ vọng được đặt đúng | 6 | Shelly được giải thích tốt, nhưng thiếu giải thích về AI |
| **Tổng thể First-run** | **6.5/10** | Cần sửa gấp empty states và keyboard issues |

---

## 3. ĐÁNH GIÁ NGƯỜI DÙNG LÂU NĂM

> **Persona:** Đã dùng app 3+ tháng, sở hữu 1–2 xe VinFast, có Shelly relay, dùng hàng ngày.

### 3.1 Đăng Nhập Lại (Re-authentication)

| Kịch bản | Trạng thái | Nhận xét |
|:---|:---:|:---|
| Tự động đăng nhập (Firebase token còn hạn) | ✅ PASS | AuthGate xử lý đúng |
| Token hết hạn → redirect về Login | ✅ PASS | State machine chuyển đúng |
| Quên mật khẩu | ❓ KHÔNG TÌM THẤY | Không thấy link "Quên mật khẩu" trong LoginScreen — **ISSUE-NEW-01** |
| Đổi thiết bị (logout thiết bị cũ) | ⚠️ RISK | Firebase Auth không tự revoke token cũ trên đa thiết bị |

### 3.2 Thao Tác Hàng Ngày — Friction Analysis

| Thao tác | Số bước | Đánh giá | Ghi chú |
|:---|:---:|:---:|:---|
| Xem % pin hiện tại | 1 (Tab 0 → nhìn) | ✅ TỐT | HomeScreen hiển thị ngay |
| Bắt đầu sạc (Smart Charge) | 4 bước | ⚠️ CÓ THỂ GIẢM | Tab 2 → chọn xe → Smart Charge → bật relay |
| Tắt sạc khẩn cấp | 2 bước | ✅ TỐT | Manual OFF có ưu tiên tối cao |
| Xem lịch sử sạc | 3 bước | ✅ OK | Tab 2 → Charge Log |
| Tìm trạm gần nhất | N/A | ❌ KHÔNG CÓ | App không có tính năng tìm trạm public — **ISSUE-NEW-02** |
| Chuyển giữa 2 xe | 3 bước | ✅ OK | `selectedVehicleProvider` hoạt động |
| Xem thống kê chi phí | 3 bước | ✅ OK | StatisticsScreen có biểu đồ |

### 3.3 Quản Lý Nhiều Xe

| Tính năng | Trạng thái | Nhận xét |
|:---|:---:|:---|
| Thêm xe thứ 2 | ✅ PASS | `vehicleContextControllerProvider` hỗ trợ |
| Chuyển xe nhanh | ✅ PASS | `selectedVehicleProvider` |
| Giới hạn số xe | ✅ PASS | `maxActiveVehicles` enforce trong Firestore rules |
| So sánh pin 2 xe cạnh nhau | ❌ KHÔNG CÓ | — |

### 3.4 Tính Năng Nâng Cao (Power User Features)

| Tính năng | Có không | Hoạt động | Nhận xét |
|:---|:---:|:---:|:---|
| Smart Charging 80% auto-stop | ✅ Có | ✅ Tốt | Safety readback đảm bảo |
| Lịch sạc tự động (schedule) | ✅ Có | ✅ Tốt | Có trong SmartChargingControlScreen |
| Cảnh báo pin yếu | ✅ Có | ✅ Tốt | NotificationsScreen + push |
| Thống kê chi phí điện | ✅ Có | ✅ Tốt | ChargeLogScreen kWh + cost |
| Dự đoán quãng đường AI | ✅ Có | ✅ Tốt | R²=0.9523, MAPE=7.54% |
| Fine-tune AI cá nhân hóa | ✅ Có | ✅ Tốt | Tính năng độc đáo — lợi thế cạnh tranh lớn |
| Nhật ký chuyến đi (Trip Log) | ✅ Có | ✅ Tốt | GPS tracking đầy đủ |
| Bảo dưỡng xe | ✅ Có | ✅ Tốt | Interval tracking |
| Chế độ offline | ✅ Có | ✅ Tốt | 6 dataset mẫu offline |
| Tìm trạm sạc công cộng | ❌ KHÔNG CÓ | — | **Thiếu so với đối thủ** |
| Chia sẻ xe với người khác | ❌ KHÔNG CÓ | — | **Thiếu so với đối thủ** |
| OTA firmware update xe | ❌ KHÔNG CÓ | — | **Dat Bike có, mình không có** |
| Khóa/mở xe từ xa | ❌ KHÔNG CÓ | — | **VinFast App chính thức có** |

### 3.5 Đồng Bộ Dữ Liệu Đa Thiết Bị

| Kịch bản | Trạng thái | Nhận xét |
|:---|:---:|:---|
| Login trên thiết bị mới → data đồng bộ | ✅ PASS | Firestore realtime sync |
| Offline → online → sync hàng chờ | ✅ PASS | Offline queue state machine |
| Conflict data (2 thiết bị cùng sửa) | ⚠️ RISK | Chưa có merge strategy rõ ràng |

### 3.6 Cài Đặt & Quản Lý Tài Khoản

| Tính năng | Trạng thái | Nhận xét |
|:---|:---:|:---|
| Cập nhật thông tin cá nhân | ✅ PASS | ProfileScreen |
| Đổi mật khẩu | ❓ KHÔNG RÕ | Cần xác nhận có trong SettingsScreen không |
| Quản lý thông báo | ✅ PASS | NotificationsScreen đầy đủ |
| Đăng xuất | ⚠️ ISSUE | Không thấy nút Đăng xuất nổi bật trong Tab 4 — **ISSUE-09** |
| Xóa tài khoản | ✅ PASS | Admin SDK purge script tồn tại |
| Chuyển ngôn ngữ Anh/Việt | ✅ PASS | `localeProvider` |
| Dark/Light theme | ⚠️ PARTIAL | Light theme chưa được kết nối đúng — **APP-CODE-001** |

### 3.7 Hiệu Năng Với Power User

| Tiêu chí | Kết quả | Đánh giá |
|:---|:---|:---:|
| Cold start (thiết bị thật) | ~1.2 giây | ✅ TỐT |
| Memory footprint | 85–110 MB | ✅ OK |
| Telemetry polling (smart charge) | 5s/lần | ✅ ĐÚNG — không gây jank |
| Frame rate animations | 60 fps | ✅ TỐT |
| Timer leak (SmartChargingScreen) | Confirmed | ❌ FAIL — **APP-BUG-002** |

---

## 4. DANH SÁCH LỖI & VẤN ĐỀ PHÁT HIỆN

### 4.1 Bảng Tổng Hợp Toàn Bộ Issues

> **Format:** `[Mức độ]` → Màn hình/Chức năng → Đối tượng bị ảnh hưởng → Mô tả → Đề xuất sửa

---

#### 🔴 P0 — BLOCKER (Phải vá trước khi bất kỳ ai dùng)

**P0-001 · Bootstrap Error Handler Loop gây ANR khi lỗi khởi động**
- **Màn hình:** Cold Start / Splash
- **Người dùng bị ảnh hưởng:** Cả hai nhóm
- **Mô tả:** `AppPopup.showError` được gọi từ `PlatformDispatcher.onError` khi `Overlay` chưa mount → vòng lặp đệ quy → ANR. Người dùng mở app khi mất mạng hoàn toàn có thể gặp app treo/crash ngay lập tức.
- **Đề xuất sửa:**
  ```dart
  // Thêm guard trước khi hiển thị popup toàn cục
  PlatformDispatcher.instance.onError = (error, stack) {
    if (WidgetsBinding.instance.rootElement != null) {
      Future.microtask(() => AppPopup.showError(error));
    } else {
      debugPrint('[BOOT ERROR] $error'); // fallback safe
    }
    return true;
  };
  ```
- **Tiêu chí nghiệm thu:** Khởi động app khi mất mạng hoàn toàn 10 lần liên tiếp → không có ANR, hiển thị màn hình fallback có nút Retry.

---

#### 🟠 P1 — CRITICAL (Phải vá trước khi release)

**P1-001 · Timer Leak trong SmartChargingControlScreen**
- **File:** `app/lib/features/smart_charging/smart_charging_control_screen.dart`
- **Người dùng bị ảnh hưởng:** Power users (dùng Smart Charging hàng ngày)
- **Mô tả:** `Timer` đếm ngược chế độ sạc hẹn giờ không được `cancel()` trong `dispose()`. Mỗi lần rời màn hình mà không dừng timer → memory leak tích lũy, vi phạm `!timersPending`.
- **Đề xuất sửa:**
  ```dart
  Timer? _countdownTimer;

  @override
  void dispose() {
    _countdownTimer?.cancel(); // THÊM DÒNG NÀY
    super.dispose();
  }
  ```
- **Tiêu chí nghiệm thu:** Test `smart_charging_control_screen_test.dart` pass 100%, không còn `!timersPending` assertion.

**P1-002 · Sai Công Thức Tính Dung Lượng Khả Dụng trong Smart Charge History**
- **File:** `app/lib/features/smart_charging/` (SmartChargeEnergySummary)
- **Người dùng bị ảnh hưởng:** Cả hai nhóm (hiển thị số liệu sai)
- **Mô tả:** `estimatedUsableCapacityWh` lệch 333 Wh so với giá trị chuẩn 3000 Wh trên xe Feliz (thực ra ra 3333.33 Wh). Lỗi do hệ số chia tỷ lệ delta SOC danh định sai.
- **Đề xuất sửa:** Hiệu chỉnh lại công thức:
  ```dart
  // Sai:
  estimatedUsableCapacityWh = deltaEnergyWh / (deltaSOC / 100);
  // Đúng (dùng deltaSOC danh định của xe, không dùng deltaSOC thực đo):
  estimatedUsableCapacityWh = deltaEnergyWh / (nominalSOCRange / 100);
  ```
- **Tiêu chí nghiệm thu:** Test `smart_charge_history_test.dart` pass, output = 3000 Wh ±5% cho xe Feliz.

**P1-003 · Lộ Chuỗi Exception Kỹ Thuật Ra Giao Diện Người Dùng**
- **Màn hình:** Tab 0 — Home Cockpit, bất kỳ màn hình nào có kết nối backend
- **Người dùng bị ảnh hưởng:** Chủ yếu first-time user
- **Mô tả:** App in nguyên văn `TimeoutException after 0:00:08.000000: Không kết nối được Firestore (8s). Kiểm tra mạng hoặc thử lại.` ra banner cho người dùng. Lộ tên thư viện backend (Firestore), timestamp micro-giây.
- **Đề xuất sửa:**
  ```dart
  class UserFriendlyErrorMapper {
    static String map(dynamic error) {
      if (error is TimeoutException || error.toString().contains('Firestore')) {
        return 'Chế độ ngoại tuyến — Đang hiển thị dữ liệu đã lưu gần nhất.';
      }
      if (error is SocketException) {
        return 'Không có kết nối Internet. Vui lòng kiểm tra WiFi hoặc dữ liệu di động.';
      }
      return 'Đã xảy ra lỗi. Vui lòng thử lại.';
    }
  }
  ```
- **Tiêu chí nghiệm thu:** Mọi banner lỗi chỉ hiển thị thông điệp thân thiện, không có bất kỳ tên exception, stacktrace hoặc tên thư viện nào.

---

#### 🟡 P2 — MAJOR (Cần vá trong sprint tiếp theo)

**P2-001 · Empty States Tab 1 (Sạc pin) & Tab 2 (Lịch sử) — Ngõ Cụt Nghiêm Trọng**
- **Màn hình:** SmartChargingScreen, ChargeLogScreen
- **Người dùng bị ảnh hưởng:** First-time user (ảnh hưởng đặc biệt nghiêm trọng)
- **Mô tả:** Khi chưa chọn xe, Tab 1 & Tab 2 hiển thị màn hình đen rỗng với 1 dòng text mờ. AppBar Tab 1 mất tiêu đề. Không có nút nào để người dùng thao tác tiếp → dead-end. Tỷ lệ churn ước tính cao.
- **Đề xuất sửa:**
  ```dart
  // Tạo PremiumEmptyState widget dùng chung
  PremiumEmptyState(
    illustration: LottieBuilder.asset('assets/lottie/charging_station.json'),
    title: 'Chưa có xe nào được kích hoạt',
    subtitle: 'Kết nối xe VinFast để bật Smart Charge 80% và theo dõi năng lượng.',
    cta: ElevatedButton(
      onPressed: () => context.push('/vehicle-detail'),
      child: const Text('+ Chọn xe ngay'),
    ),
  )
  ```
- **Tiêu chí nghiệm thu:** Mọi empty state có illustration + tiêu đề + mô tả + nút CTA dẫn hành động cụ thể.

**P2-002 · Tràn Giao Diện RenderFlex khi Phóng To Chữ 2.0x (Accessibility)**
- **File:** `app/lib/core/widgets/animated_battery_gauge.dart`
- **Người dùng bị ảnh hưởng:** Người dùng có vấn đề thị lực (cả 2 nhóm)
- **Mô tả:** `AnimatedBatteryGauge` overflow 73 pixels khi text scale 2.0x. Vi phạm WCAG 1.4.4 (Resize Text).
- **Đề xuất sửa:**
  ```dart
  // Bọc nội dung trung tâm
  FittedBox(
    fit: BoxFit.scaleDown,
    child: Column(/* gauge content */),
  )
  ```

**P2-003 · 40+ Lệnh print() Lộ Telemetry Ra Logcat Production**
- **Files:** `sync_service.dart`, `battery_state_service.dart`, `soc_api_service.dart`
- **Người dùng bị ảnh hưởng:** Tất cả (bảo mật)
- **Mô tả:** Hơn 40 `print()` in thông số pin, SOC, voltage, telemetry ra Android Logcat. Bất kỳ app nào có quyền READ_LOGS đều đọc được.
- **Đề xuất sửa:** Thay hàng loạt bằng:
  ```dart
  // Thay print() bằng:
  if (kDebugMode) debugPrint('[BatteryService] SOC: $soc');
  // Hoặc dùng logger với obfuscation
  ```

---

#### 🟢 P3 — MINOR (Có thể để lại sau release, xử lý trong maintenance)

**P3-001 · Tên Tab 4 Không Đồng Nhất ("Khác" vs "Cài đặt")**
- **Màn hình:** AppNavigation
- **Mô tả:** NavBar ghi "Cài đặt", AppBar ghi "Khác". Gây confusion nhẹ.
- **Đề xuất sửa:** Thống nhất thành "Cài đặt" ở cả hai nơi trong `tabTitles` và `destinations`.

**P3-002 · Icon ODO Dùng Nhầm Biểu Tượng Đồng Hồ Thời Gian**
- **Màn hình:** Tab 0 — thẻ ODO KM
- **Mô tả:** `Icons.access_time` (đồng hồ tròn = thời gian) dùng cho ODO (quãng đường). Semantic sai.
- **Đề xuất sửa:** Đổi sang `Icons.speed_rounded` hoặc `Icons.route_rounded`.

---

#### 🆕 ISSUES MỚI PHÁT HIỆN (Chưa có trong các audit trước)

**NEW-001 · Không Có Tính Năng "Quên Mật Khẩu"**
- **Màn hình:** LoginScreen
- **Mức độ:** P1
- **Mô tả:** Không tìm thấy link/button "Quên mật khẩu?" trong LoginScreen. Người dùng quên mật khẩu không có cách nào tự khôi phục trong app.
- **Đề xuất sửa:** Thêm `TextButton('Quên mật khẩu?')` gọi `FirebaseAuth.instance.sendPasswordResetEmail(email: email)`.

**NEW-002 · Không Có Tính Năng Tìm Trạm Sạc Công Cộng**
- **Mức độ:** P2 (Gap cạnh tranh nghiêm trọng)
- **Mô tả:** App quản lý pin/sạc nhưng KHÔNG có màn hình tìm trạm sạc gần đây. VinFast App, ChargePoint, PlugShare đều có. Người dùng phải dùng app khác để tìm trạm → trải nghiệm phân mảnh.
- **Đề xuất sửa:** Tích hợp Google Maps/OpenStreetMap + OCPP API hoặc API trạm sạc Việt Nam (EVN, VinFast network) vào TripPlannerScreen.

**NEW-003 · Không Có Tính Năng Chia Sẻ Xe**
- **Mức độ:** P3
- **Mô tả:** VinFast App chính thức và Dat Bike App cho phép chia sẻ quyền truy cập xe với người khác. App hiện không hỗ trợ.

**NEW-004 · Phím Back Hệ Thống Không Xử Lý Đúng Tại Tab Phụ**
- **Màn hình:** AppNavigation (Tab 1, 2, 3)
- **Mức độ:** P2
- **Mô tả:** Bấm Back vật lý/cử chỉ khi ở tab phụ không chuyển về Tab 0. Thiếu `PopScope`.
- **Đề xuất sửa:**
  ```dart
  PopScope(
    canPop: currentIndex == 0,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && currentIndex != 0) {
        setState(() => currentIndex = 0);
      }
    },
    child: /* scaffold */,
  )
  ```

**NEW-005 · Trường Số Điện Thoại Dùng Bàn Phím QWERTY Thay Vì Numpad**
- **Màn hình:** RegisterScreen
- **Mức độ:** P2
- **Mô tả:** Cho phép gõ ký tự chữ (ví dụ `"09QaT"`). Validation backend mới chặn, nhưng UX đã gây friction.
- **Đề xuất sửa:** `keyboardType: TextInputType.phone` + `FilteringTextInputFormatter.digitsOnly`.

**NEW-006 · Nút QA Debug "Điền dữ liệu mẫu" Cần Cô Lập Khỏi Production**
- **Màn hình:** RegisterScreen
- **Mức độ:** P2 (Security)
- **Mô tả:** Nút hiện dựa vào `kDebugMode`. Nếu build config nhầm, nút lọt ra production.
- **Đề xuất sửa:** Wrap bằng Dart flavor: chỉ build khi `--flavor dev` hoặc `--flavor qa`.

---

## 5. SO SÁNH VỚI ĐỐI THỦ

### 5.1 Bảng So Sánh Tính Năng Chi Tiết

| Tính năng | VinFast Battery *(app của bạn)* | Tesla App | VinFast E-Scooter App | Dat Bike App |
|:---|:---:|:---:|:---:|:---:|
| **Theo dõi % pin real-time** | ✅ | ✅ | ✅ | ✅ |
| **Dự đoán quãng đường AI** | ✅ 🏆 | ✅ | ❌ | ❌ |
| **Fine-tune AI cá nhân hóa** | ✅ 🏆 | ❌ | ❌ | ❌ |
| **Smart Charging (tự ngắt 80%)** | ✅ 🏆 | ✅ | ❌ | ❌ |
| **Lịch sạc tự động** | ✅ | ✅ | ❌ | ❌ |
| **Kiểm soát relay IoT (Shelly)** | ✅ 🏆 | ❌ | ❌ | ❌ |
| **Dự phòng Cloud → LAN** | ✅ 🏆 | ❌ | ❌ | ❌ |
| **Chế độ offline** | ✅ | ✅ | ❌ | Partial |
| **Thống kê chi phí điện** | ✅ | ✅ | ❌ | ❌ |
| **Nhật ký chuyến đi GPS** | ✅ | ✅ | ✅ | ✅ |
| **Bảo dưỡng xe** | ✅ | ✅ | ❌ | ❌ |
| **Cảnh báo pin yếu** | ✅ | ✅ | ✅ | ✅ |
| **Tìm trạm sạc công cộng** | ❌ | ✅ | ✅ | ❌ |
| **Khóa/mở xe từ xa** | ❌ | ✅ | ✅ | ✅ |
| **Chia sẻ xe với người khác** | ❌ | ✅ | ✅ | ✅ |
| **OTA firmware update** | ❌ | ✅ | ❌ | ✅ |
| **Bản đồ trạm sạc cộng đồng** | ❌ | ❌ | ❌ | ❌ |
| **Quên mật khẩu trong app** | ❌ | ✅ | ✅ | ✅ |
| **Đa ngôn ngữ** | ✅ (Vi/En) | ✅ | ✅ | Limited |
| **Dark mode cao cấp** | ✅ 🏆 | ✅ | ❌ | ❌ |
| **Mascot/Gamification** | ✅ (BatteryBot) | ❌ | ❌ | ❌ |
| **SoH (Battery Health)** | ✅ 🏆 | ✅ | ❌ | ❌ |
| **Phát hiện bất thường pin** | ✅ 🏆 | ✅ | ❌ | ❌ |
| **Admin Dashboard** | ✅ 🏆 | Internal | Internal | Internal |

> 🏆 = Tính năng mà VinFast Battery làm tốt hơn hoặc độc đáo hơn đối thủ

### 5.2 So Sánh UX Theo Từng Khía Cạnh

#### 5.2.1 Tốc Độ Thao Tác Hàng Ngày

| Thao tác | VinFast Battery | Tesla App | VinFast E-Scooter | Dat Bike |
|:---|:---:|:---:|:---:|:---:|
| Xem % pin | 1 tap (Tab 0) | 1 tap | 1 tap | 1 tap |
| Bắt đầu sạc | 4 bước | 2 bước | N/A | N/A |
| Tìm trạm sạc | ❌ Không có | 2 bước | 3 bước | ❌ Không có |
| Xem lịch sử | 3 bước | 2 bước | 3 bước | 2 bước |
| **Đánh giá tổng thể** | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐ |

#### 5.2.2 Hiển Thị Trạng Thái Pin

| Tiêu chí | VinFast Battery | Tesla App | Ghi chú |
|:---|:---:|:---:|:---|
| % pin số lớn, dễ đọc | ✅ | ✅ | |
| Animation pin "sống động" | ✅ (liquid) | ✅ (arc) | Tesla dùng HUD arc tinh tế hơn |
| SoH (Health %) | ✅ | ✅ | Đây là lợi thế lớn của bạn so với VN apps |
| Nhiệt độ pin | ✅ | ✅ | |
| Voltage/Current real-time | ✅ | ❌ (ẩn) | Lợi thế cho power users |
| Màu sắc cảnh báo % thấp | ✅ | ✅ | |

#### 5.2.3 Thẩm Mỹ Tổng Thể

| Tiêu chí | VinFast Battery | Tesla App | VinFast E-Scooter | Dat Bike |
|:---|:---:|:---:|:---:|:---:|
| Dark mode premium | ✅ Tốt | ✅ Xuất sắc | ❌ Không có | ❌ Không có |
| Tính nhất quán ngôn ngữ | ⚠️ Lẫn Anh/Việt | ✅ | ✅ | ✅ |
| Empty states chất lượng | ❌ Ngõ cụt | ✅ Đẹp | ✅ OK | ✅ OK |
| Độ hoàn thiện UX | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ |
| Animation & Motion | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐ | ⭐⭐ |

### 5.3 Điểm Mạnh Cạnh Tranh (Unique Selling Points)

> Đây là những thứ **CỰC KỲ HIẾM** trong thị trường xe điện Việt Nam:

1. **🏆 AI Personalization:** Fine-tune mô hình AI theo lịch sử của từng xe cụ thể — không app nào ở Việt Nam có
2. **🏆 IoT Smart Charging với Safety Readback:** Tự ngắt relay vật lý + xác nhận readback + fail-safe → an toàn hơn cả Tesla App
3. **🏆 SoH Prediction (Battery Health):** Dự đoán tuổi thọ pin — VinFast App chính thức không có
4. **🏆 Anomaly Detection:** Phát hiện bất thường từ voltage/current/temp — tính năng cấp enterprise
5. **🏆 Cloud + LAN Fallback:** Shelly vẫn hoạt động khi mất internet — resilience cao hơn cloud-only apps

### 5.4 Khoảng Trống Cạnh Tranh (Gaps to Address)

| Gap | Mức độ khẩn | Lý do quan trọng |
|:---|:---:|:---|
| Quên mật khẩu | 🔴 Cao | Tính năng cơ bản nhất của mọi app |
| Empty States có CTA | 🔴 Cao | Giữ chân user mới |
| Tìm trạm sạc công cộng | 🟡 Trung bình | Cạnh tranh trực tiếp với VinFast App |
| Khóa/mở xe từ xa | 🟡 Trung bình | Đòi hỏi tích hợp hardware VinFast API |
| Chia sẻ quyền truy cập xe | 🟢 Thấp | Nice-to-have |

---

## 6. ROADMAP CẢI TIẾN ƯU TIÊN

### Đợt 1 — "Vá Khẩn Cấp" (Sprint hiện tại, 1–2 tuần)
> Bắt buộc để đạt release readiness ≥75/100

- [ ] **P0-001** Fix Bootstrap ANR (guard trước Overlay mount)
- [ ] **P1-001** Fix Timer leak trong SmartChargingControlScreen
- [ ] **P1-002** Fix công thức tính dung lượng Smart Charge History
- [ ] **P1-003** Viết `UserFriendlyErrorMapper` — ẩn tất cả exception kỹ thuật
- [ ] **NEW-001** Thêm "Quên mật khẩu?" vào LoginScreen (Firebase Reset Email — 30 phút code)
- [ ] **NEW-004** Thêm `PopScope` cho AppNavigation — xử lý Back đúng
- [ ] **NEW-005** Fix `keyboardType: TextInputType.phone` cho trường SĐT
- [ ] **P3-001** Thống nhất tên Tab 4: "Cài đặt"

**Kết quả dự kiến:** Score 62 → **80/100**

### Đợt 2 — "UX Polish" (2–3 tuần sau)
> Nâng cấp trải nghiệm để user mới không bỏ app

- [ ] **P2-001** Xây dựng `PremiumEmptyState` widget — dùng chung Tab 1, Tab 2
- [ ] **P2-002** Fix accessibility (`FittedBox` cho AnimatedBatteryGauge ở 2.0x)
- [ ] **P2-003** Thay 40+ `print()` bằng logger có kDebugMode guard
- [ ] **NEW-002** Xây dựng màn hình tìm trạm sạc gần nhất (tích hợp Google Maps + dữ liệu trạm)
- [ ] **NEW-006** Cô lập nút QA debug vào flavor `dev`/`qa` riêng
- [ ] **ISSUE-06** Chuẩn hóa 100% thuật ngữ sang tiếng Việt (Trip Planner, CHARGE, ODO KM...)
- [ ] **ISSUE-05** Thay chữ cái "E/F/K" bằng silhouette vector xe VinFast
- [ ] **ISSUE-07** Thu hẹp dead space onboarding bước 3–7
- [ ] **ISSUE-03** Fix Submit CTA bị bàn phím che (CustomScrollView + viewInsets.bottom)
- [ ] Nâng cấp Tab 4 (Cài đặt): thêm Profile Header Card + nút Đăng xuất nổi bật

**Kết quả dự kiến:** Score → **90/100**

### Đợt 3 — "Premium Polish" (1 tháng sau)
> Đạt chuẩn premium automotive

- [ ] Nâng cấp BatteryBot → Holographic HUD aesthetic (viền phát sáng, scanning rings)
- [ ] Thêm Tactile Press Feedback (scale 0.97 → 1.0, haptic `lightImpact()`)
- [ ] Thống nhất bảng màu nền `#0A0C10` Deep Obsidian với viền ánh kim mờ 1px
- [ ] Thay hiệu ứng liquid pin bằng Cybernetic HUD Arc
- [ ] Kết nối `_buildLightTheme` → hỗ trợ hoàn chỉnh Light Mode
- [ ] Xem xét tích hợp OTA update hoặc remote lock (nếu VinFast API mở)

**Kết quả dự kiến:** Score → **95/100**

---

## 7. CHECKLIST TEST CASE ĐẦY ĐỦ

> Sử dụng bảng này sau **mỗi lần** cập nhật app. Đánh dấu ✅/❌/⚠️ vào cột "Kết quả".

### MODULE 1: AUTHENTICATION

| TC# | Test Case | Nhóm user | Kết quả |
|:---|:---|:---:|:---:|
| TC-AUTH-01 | Mở app lần đầu → hiện LoginScreen (không bị crash) | Mới | |
| TC-AUTH-02 | Đăng nhập với email/password đúng → vào Home thành công | Cả hai | |
| TC-AUTH-03 | Đăng nhập sai password → hiện lỗi tiếng Việt, không lộ exception | Cả hai | |
| TC-AUTH-04 | Đăng nhập khi mất mạng → hiện thông báo thân thiện, không crash | Cả hai | |
| TC-AUTH-05 | Đăng ký tài khoản mới với đầy đủ thông tin hợp lệ → thành công | Mới | |
| TC-AUTH-06 | Đăng ký để trống form → hiện đủ 5 thông báo lỗi tiếng Việt | Mới | |
| TC-AUTH-07 | Trường Số điện thoại → bàn phím numpad xuất hiện | Mới | |
| TC-AUTH-08 | Trường Số điện thoại → không nhập được chữ cái | Mới | |
| TC-AUTH-09 | Nút Submit (Đăng ký) visible khi bàn phím Android bung lên | Mới | |
| TC-AUTH-10 | Bấm "Quên mật khẩu?" → nhận được email reset | Lâu năm | |
| TC-AUTH-11 | Nút QA Debug "Điền dữ liệu mẫu" KHÔNG xuất hiện trên bản Release | Cả hai | |
| TC-AUTH-12 | Token Firebase hết hạn → tự động redirect về Login | Lâu năm | |
| TC-AUTH-13 | Login trên thiết bị mới → data Firestore đồng bộ đúng | Lâu năm | |

### MODULE 2: ONBOARDING (8 BƯỚC)

| TC# | Test Case | Nhóm user | Kết quả |
|:---|:---|:---:|:---:|
| TC-ONB-01 | Bước 1: BatteryBot hiển thị, 3 card tính năng đọc được | Mới | |
| TC-ONB-02 | Bước 2: Chọn VinFast Feliz → viền xanh nổi bật, checkmark xuất hiện | Mới | |
| TC-ONB-03 | Bước 2: Icon xe KHÔNG phải chữ cái thô sơ (E/F/K) | Mới | |
| TC-ONB-04 | Bước 2: Hàng xe cuối cùng KHÔNG bị nút CTA che khuất | Mới | |
| TC-ONB-05 | Bước 3: Nhập nickname xe → lưu và hiển thị đúng ở Home | Mới | |
| TC-ONB-06 | Bước 3: Nút CTA visible khi bàn phím xuất hiện | Mới | |
| TC-ONB-07 | Bước 4: Bỏ qua ngày sinh → tiếp tục onboarding không lỗi | Mới | |
| TC-ONB-08 | Bước 5: Slider quãng đường hoạt động, BatteryBot phản hồi | Mới | |
| TC-ONB-09 | Bước 6: Chọn mục đích + ngưỡng sạc → mascot thay đổi biểu cảm | Mới | |
| TC-ONB-10 | Bước 7: Chọn "Thiết lập sau" → KHÔNG kích hoạt relay thật | Mới | |
| TC-ONB-11 | Bước 8: Summary hiển thị đủ 8/8 thông số, nút "Khởi động Cockpit" | Mới | |
| TC-ONB-12 | Progress indicator: 8 energy pills, bước hiện tại mở rộng đúng | Mới | |
| TC-ONB-13 | Back từ bước 3 → về bước 2 mà không mất data đã nhập | Mới | |

### MODULE 3: HOME — TAB 0

| TC# | Test Case | Nhóm user | Kết quả |
|:---|:---|:---:|:---:|
| TC-HOME-01 | % pin hiển thị đúng và nổi bật ở đầu màn hình | Cả hai | |
| TC-HOME-02 | Quãng đường ước tính AI hiển thị và có nguồn model rõ ràng | Cả hai | |
| TC-HOME-03 | Thẻ ODO dùng icon đồng hồ tốc độ (không phải đồng hồ thời gian) | Cả hai | |
| TC-HOME-04 | Banner lỗi mạng chỉ hiển thị thông điệp thân thiện, không có "Firestore" | Cả hai | |
| TC-HOME-05 | Nút "Sync Now" → spinner → update data | Cả hai | |
| TC-HOME-06 | Nút "Trip Planner" → mở TripPlannerScreen | Cả hai | |
| TC-HOME-07 | Nút "Bảo dưỡng" → mở MaintenanceScreen | Cả hai | |
| TC-HOME-08 | Chuyển giữa 2 xe → Home update đúng dữ liệu xe được chọn | Lâu năm | |

### MODULE 4: SMART CHARGING — TAB 1 & 2

| TC# | Test Case | Nhóm user | Kết quả |
|:---|:---|:---:|:---:|
| TC-CHG-01 | Tab 1 khi chưa chọn xe: hiện EmptyState CÓ nút "Chọn xe ngay" | Mới | |
| TC-CHG-02 | Tab 1 khi chưa chọn xe: AppBar vẫn hiển thị tiêu đề "Sạc pin" | Mới | |
| TC-CHG-03 | Bắt đầu Smart Charge → spinner pending → relay bật → banner "Đang sạc" | Lâu năm | |
| TC-CHG-04 | Relay bật nhưng readback fail → hiển thị cảnh báo "Relay không phản hồi" | Cả hai | |
| TC-CHG-05 | Đặt target SOC 80% → relay tự ngắt khi đạt 80% | Lâu năm | |
| TC-CHG-06 | Bấm "Tắt khẩn cấp" → relay OFF ngay lập tức, không chờ AI | Cả hai | |
| TC-CHG-07 | Chuyển sang LAN khi Cloud timeout → không sinh lệnh kép | Lâu năm | |
| TC-CHG-08 | Thoát SmartChargingScreen → KHÔNG còn timer leak (timersPending = false) | Cả hai | |
| TC-CHG-09 | Hẹn giờ sạc → sạc bắt đầu đúng giờ đã đặt | Lâu năm | |
| TC-CHG-10 | Tab 2 khi chưa chọn xe: hiện EmptyState CÓ nút, KHÔNG màn đen rỗng | Mới | |
| TC-CHG-11 | Charge History: dung lượng khả dụng ước tính ≈ 3000 Wh trên Feliz (±5%) | Cả hai | |
| TC-CHG-12 | Thêm charge log thủ công: nhập SOC âm → bị chặn, hiện lỗi | Cả hai | |

### MODULE 5: AI & PREDICTIONS

| TC# | Test Case | Nhóm user | Kết quả |
|:---|:---|:---:|:---:|
| TC-AI-01 | AI dự đoán thời gian sạc → hiển thị nhãn nguồn model + version | Cả hai | |
| TC-AI-02 | AI server offline → fallback heuristic, KHÔNG crash | Cả hai | |
| TC-AI-03 | AI server timeout (>12s) → fallback + thông báo thân thiện | Cả hai | |
| TC-AI-04 | Personal AI Training: thêm training data → model accuracy cải thiện | Lâu năm | |
| TC-AI-05 | Developer AI Studio: ping backend → kết quả hiển thị rõ ràng | Lâu năm | |

### MODULE 6: TRIP PLANNER & GPS

| TC# | Test Case | Nhóm user | Kết quả |
|:---|:---|:---:|:---:|
| TC-TRIP-01 | Xin quyền location: hiển thị rationale TRƯỚC khi xin quyền | Mới | |
| TC-TRIP-02 | Từ chối quyền location → app không crash, hiển thị hướng dẫn bật quyền | Cả hai | |
| TC-TRIP-03 | Bắt đầu trip → lộ trình ghi đúng, loại điểm GPS bất thường | Cả hai | |
| TC-TRIP-04 | Kết thúc trip → tóm tắt: khoảng cách, kWh, chi phí hiển thị đúng | Cả hai | |
| TC-TRIP-05 | Trip 0 điểm GPS → không crash, hiển thị empty map đúng | Cả hai | |

### MODULE 7: LỊCH SỬ & THỐNG KÊ

| TC# | Test Case | Nhóm user | Kết quả |
|:---|:---|:---:|:---:|
| TC-HIST-01 | Charge Log: danh sách sạc hiển thị đúng thứ tự thời gian | Lâu năm | |
| TC-HIST-02 | Charge Log: xóa session khi trạng thái không phải active/arming | Lâu năm | |
| TC-HIST-03 | Statistics: biểu đồ energy/distance render không crash khi data rỗng | Cả hai | |
| TC-HIST-04 | Statistics: chi phí điện tính đúng theo kWh × đơn giá | Lâu năm | |

### MODULE 8: CÀI ĐẶT & TÀI KHOẢN

| TC# | Test Case | Nhóm user | Kết quả |
|:---|:---|:---:|:---:|
| TC-SET-01 | Tab 4: Nút "Đăng xuất" hiển thị rõ, bấm → confirm dialog → logout | Lâu năm | |
| TC-SET-02 | Cập nhật tên hiển thị → hiện đúng ở ProfileScreen | Lâu năm | |
| TC-SET-03 | Đổi mật khẩu → đăng nhập lại với mật khẩu mới thành công | Lâu năm | |
| TC-SET-04 | Chuyển Dark/Light theme → áp dụng ngay, không cần restart | Lâu năm | |
| TC-SET-05 | Chuyển ngôn ngữ Anh/Việt → toàn bộ UI cập nhật đồng bộ | Cả hai | |
| TC-SET-06 | Quản lý thông báo: bật/tắt cảnh báo pin yếu → hoạt động | Lâu năm | |
| TC-SET-07 | Tab 4 AppBar title = "Cài đặt" (đồng bộ với NavBar label) | Cả hai | |

### MODULE 9: OFFLINE & ĐỒNG BỘ

| TC# | Test Case | Nhóm user | Kết quả |
|:---|:---|:---:|:---:|
| TC-OFF-01 | Tắt WiFi → app hiển thị indicator "offline", data cached vẫn xem được | Cả hai | |
| TC-OFF-02 | Thao tác khi offline → hàng đợi → bật WiFi → đồng bộ tự động | Cả hai | |
| TC-OFF-03 | AI Studio khi offline → vẫn xem được 6 dataset mẫu | Lâu năm | |

### MODULE 10: NOTIFICATIONS

| TC# | Test Case | Nhóm user | Kết quả |
|:---|:---:|:---:|:---:|
| TC-NOTIF-01 | Pin xuống dưới ngưỡng → push notification hiển thị đúng nội dung | Cả hai | |
| TC-NOTIF-02 | Sạc hoàn thành → thông báo gửi, relay đã tắt | Lâu năm | |
| TC-NOTIF-03 | NotificationsScreen: danh sách đúng thứ tự, có thể đánh dấu đã đọc | Cả hai | |

### MODULE 11: LAYOUT & RESPONSIVE

| TC# | Test Case | Nhóm user | Kết quả |
|:---|:---|:---:|:---:|
| TC-UI-01 | Màn hình 320dp (nhỏ nhất): không có RenderFlex overflow | Cả hai | |
| TC-UI-02 | Text scale 1.5x: layout không bị vỡ | Cả hai | |
| TC-UI-03 | Text scale 2.0x: AnimatedBatteryGauge không overflow (sau khi vá) | Cả hai | |
| TC-UI-04 | Tên xe/trạm dài → không bị cắt "..." mất nghĩa (Ellipsis với Tooltip) | Cả hai | |
| TC-UI-05 | Khi bàn phím lên: không có nội dung quan trọng bị che khuất | Cả hai | |
| TC-UI-06 | Tất cả thông báo lỗi: không có chuỗi exception, stacktrace, tên thư viện | Cả hai | |

### MODULE 12: SAFETY (SHELLY RELAY)

| TC# | Test Case | Nhóm user | Kết quả |
|:---|:---|:---:|:---:|
| TC-SAF-01 | Relay chỉ hiển thị ON sau khi readback xác nhận `output == true` | Lâu năm | |
| TC-SAF-02 | Relay không đóng vật lý → chuyển `readbackMismatch`, KHÔNG báo thành công | Lâu năm | |
| TC-SAF-03 | Restart gateway → relay mặc định OFF, KHÔNG tự bật | Lâu năm | |
| TC-SAF-04 | Cloud timeout → chuyển sang LAN, KHÔNG sinh lệnh kép | Lâu năm | |
| TC-SAF-05 | Nút Manual OFF luôn hoạt động bất kể trạng thái AI hay Cloud | Lâu năm | |

### MODULE 13: ĐIỀU HƯỚNG (NAVIGATION)

| TC# | Test Case | Nhóm user | Kết quả |
|:---|:---|:---:|:---:|
| TC-NAV-01 | Back vật lý ở Tab 1/2/3 → chuyển về Tab 0 (không thoát app) | Cả hai | |
| TC-NAV-02 | Back vật lý ở Tab 0 → hiện dialog thoát app (hoặc thoát thẳng) | Cả hai | |
| TC-NAV-03 | Deep link vào SmartChargingScreen → back về Home đúng | Lâu năm | |
| TC-NAV-04 | Chuyển tab nhanh 5 lần liên tiếp → không bị lag hoặc state reset sai | Cả hai | |

---

## 8. PHỤ LỤC — MAPPING BUGS VÀO FILE CODE

| Bug ID | File code liên quan | Dòng ước tính |
|:---|:---|:---:|
| P0-001 | `app/lib/main.dart` | ~30–50 |
| P1-001 | `app/lib/features/smart_charging/smart_charging_control_screen.dart` | dispose() |
| P1-002 | `app/lib/features/smart_charging/` (SmartChargeEnergySummary) | calculate() |
| P1-003 | `app/lib/core/` (cần tạo mới UserFriendlyErrorMapper) | NEW FILE |
| P2-001 | `app/lib/features/charge/` & `app/lib/features/smart_charging/` | Empty states |
| P2-002 | `app/lib/core/widgets/animated_battery_gauge.dart` | Gauge center |
| P2-003 | `sync_service.dart`, `battery_state_service.dart`, `soc_api_service.dart` | 40+ lines |
| NEW-001 | `app/lib/features/auth/login_screen.dart` | Add TextButton |
| NEW-004 | `app/lib/navigation/app_navigation.dart` | Wrap in PopScope |
| NEW-005 | `app/lib/features/auth/register_screen.dart` | Phone TextField |
| P3-001 | `app/lib/navigation/app_navigation.dart` | `tabTitles` array |
| P3-002 | `app/lib/features/home/home_screen.dart` | ODO card icon |

---

*Báo cáo được tổng hợp bởi Senior QA Lead & UX Researcher — 18/09/2026*
*Tham chiếu: QA_AUDIT_REPORT.md (ba9df98), QA_UIUX_FIRST_RUN_AUDIT_2026-09-17.md (44194aa), UI_UX_DESIGN_REVIEW_2026-09-17.md*
