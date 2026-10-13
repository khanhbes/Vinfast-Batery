# Shelly Connection Refactor — Implementation Plan

## 1. Current Architecture

### 1.1 Flutter App Layer

| Layer | Key Files | Purpose |
|---|---|---|
| **Data Models** | [`shelly_connection.dart`](file:///c:/Users/khanh/OneDrive/Desktop/Vinfast%20Batery/app/lib/data/models/shelly_connection.dart) | `ShellyConnectionProfile` (cloud host, auth key, device ID, LAN addr, local password), `DiscoveredShellyDevice`, `SmartChargePlan`, `ShellyTransport` enum, `SmartChargerErrorCode` enum |
| | [`shelly_snapshot.dart`](file:///c:/Users/khanh/OneDrive/Desktop/Vinfast%20Batery/app/lib/data/models/shelly_snapshot.dart) | `ShellyDeviceSnapshot`, `ShellyDeviceIdentity`, `ShellySwitchConfig`, `ShellySafetyTestResult` |
| | [`smart_charger_binding.dart`](file:///c:/Users/khanh/OneDrive/Desktop/Vinfast%20Batery/app/lib/data/models/smart_charger_binding.dart) | `SmartChargerBinding` + `SmartChargerConnectionMode` enum (`serverCloud`, `advancedDirect`) |
| | [`smart_charger_capabilities.dart`](file:///c:/Users/khanh/OneDrive/Desktop/Vinfast%20Batery/app/lib/data/models/smart_charger_capabilities.dart) | `SmartChargerCapabilities` — readiness flags for control |
| | [`smart_charger_status.dart`](file:///c:/Users/khanh/OneDrive/Desktop/Vinfast%20Batery/app/lib/data/models/smart_charger_status.dart) | `SmartChargerStatus` — live telemetry model |
| | [`vehicle_charger_binding.dart`](file:///c:/Users/khanh/OneDrive/Desktop/Vinfast%20Batery/app/lib/data/models/vehicle_charger_binding.dart) | `VehicleChargerBinding` — vehicleId ↔ deviceId link |
| **Services** | [`shelly_clients.dart`](file:///c:/Users/khanh/OneDrive/Desktop/Vinfast%20Batery/app/lib/data/services/shelly_clients.dart) | `ShellyCloudClient` (Cloud Control v2 API), `ShellyLanClient` (RPC + Digest Auth), `parseShellySnapshot`, `parseShellyStatus` |
| | [`shelly_discovery_service.dart`](file:///c:/Users/khanh/OneDrive/Desktop/Vinfast%20Batery/app/lib/data/services/shelly_discovery_service.dart) | `ShellyDiscoveryService` — mDNS `_shelly._tcp`, `probeDevice` (HTTP RPC), `discoverAndProbe`, `sweepSubnet` (unicast /24 sweep) |
| | [`shelly_cloud_auth_service.dart`](file:///c:/Users/khanh/OneDrive/Desktop/Vinfast%20Batery/app/lib/data/services/shelly_cloud_auth_service.dart) | `ShellyCloudAuthService` — list devices from Cloud via auth key, `matchDevice` (LAN ↔ Cloud match), `assembleProfile`, `launchShellyCloudPortal` |
| | [`smart_charger_credentials_service.dart`](file:///c:/Users/khanh/OneDrive/Desktop/Vinfast%20Batery/app/lib/data/services/smart_charger_credentials_service.dart) | `SmartChargerCredentialsService` — `FlutterSecureStorage` CRUD for `ShellyConnectionProfile`, draft, verification state; scoped to Firebase UID; `restoreFromCloud` via backend vault |
| | [`smart_charger_service.dart`](file:///c:/Users/khanh/OneDrive/Desktop/Vinfast%20Batery/app/lib/data/services/smart_charger_service.dart) | `SmartChargerService` — orchestrator: `testConnection`, `armSmartCharge`, `getStatus`, `capabilities`, safety enforcement, session management |
| | [`server_smart_charger_service.dart`](file:///c:/Users/khanh/OneDrive/Desktop/Vinfast%20Batery/app/lib/data/services/server_smart_charger_service.dart) | `ServerSmartChargerService` — HTTP client for Flask backend APIs (`/api/shelly/*`, `/api/smart-charging/*`), profile sync, session CRUD |
| | [`shelly_qr_parser.dart`](file:///c:/Users/khanh/OneDrive/Desktop/Vinfast%20Batery/app/lib/data/services/shelly_qr_parser.dart) | QR code parsing — extracts device ID, cloud host, model, LAN address from scanned codes |
| **Repository** | [`smart_charger_repository.dart`](file:///c:/Users/khanh/OneDrive/Desktop/Vinfast%20Batery/app/lib/data/repositories/smart_charger_repository.dart) | `SmartChargerRepository` interface, `DirectSmartChargerRepository`, `ServerSmartChargerRepository`, `SmartChargerRepositoryFactory` with mode persistence |
| **UI Screens** | [`smart_charger_setup_hub_screen.dart`](file:///c:/Users/khanh/OneDrive/Desktop/Vinfast%20Batery/app/lib/features/smart_charging/smart_charger_setup_hub_screen.dart) (3012 lines!) | Main setup wizard — Tabs: Config, Verification, Settings; mDNS scan, subnet sweep, QR scan, manual Cloud/LAN fields, safe boot, no-load test, mode switch |
| | [`shelly_setup_screen.dart`](file:///c:/Users/khanh/OneDrive/Desktop/Vinfast%20Batery/app/lib/features/smart_charging/shelly_setup_screen.dart) | Stepper-based legacy setup with manual Cloud/LAN entry + verification |
| | [`settings_screen.dart`](file:///c:/Users/khanh/OneDrive/Desktop/Vinfast%20Batery/app/lib/features/settings/settings_screen.dart) | App settings — loads Shelly state, shows "Smart Charger" row linking to setup hub |

### 1.2 Backend Layer

| Module | Key Files | Purpose |
|---|---|---|
| **Shelly Module** | [`web/shelly/routes.py`](file:///c:/Users/khanh/OneDrive/Desktop/Vinfast%20Batery/web/shelly/routes.py) | Flask blueprint: consent/start (Integrator OAuth), profiles CRUD, consent callback, device binding, capabilities, select device |
| | [`web/shelly/profile_vault.py`](file:///c:/Users/khanh/OneDrive/Desktop/Vinfast%20Batery/web/shelly/profile_vault.py) | AES-256-GCM encrypted vault for Shelly credentials in Firestore — secrets never stored in plaintext |
| | [`web/shelly/repositories.py`](file:///c:/Users/khanh/OneDrive/Desktop/Vinfast%20Batery/web/shelly/repositories.py) | Firestore persistence — bindings, synced profiles, consent state, sessions |
| | [`web/shelly/service.py`](file:///c:/Users/khanh/OneDrive/Desktop/Vinfast%20Batery/web/shelly/service.py) | Backend smart charge orchestration — session management, safety enforcement |
| | [`web/shelly/providers/`](file:///c:/Users/khanh/OneDrive/Desktop/Vinfast%20Batery/web/shelly/providers/) | `base.py`, `fake.py`, `integrator.py`, `legacy_cloud.py` — Shelly provider abstraction |

### 1.3 Developer Mode — Current Implementation

**Đã tồn tại.** Kích hoạt bằng cách chạm vào phiên bản app 7 lần trong Settings.

- [`settings_screen.dart` L52](file:///c:/Users/khanh/OneDrive/Desktop/Vinfast%20Batery/app/lib/features/settings/settings_screen.dart#L52): `bool _developerUnlocked = false;`
- [`settings_screen.dart` L116](file:///c:/Users/khanh/OneDrive/Desktop/Vinfast%20Batery/app/lib/features/settings/settings_screen.dart#L116): Persisted via `SharedPreferences('developerModeUnlocked')`
- [`settings_screen.dart` L566-L581](file:///c:/Users/khanh/OneDrive/Desktop/Vinfast%20Batery/app/lib/features/settings/settings_screen.dart#L566-L581): Version tap handler — 7 taps to unlock
- [`settings_screen.dart` L445](file:///c:/Users/khanh/OneDrive/Desktop/Vinfast%20Batery/app/lib/features/settings/settings_screen.dart#L445): `if (_developerUnlocked)` — shows Developer Mode section with AI Studio, Diagnostics, Training Data

**Quan trọng:** Developer Mode hiện tại ảnh hưởng settings screen (hiển thị subtitles, developer tools), nhưng **CHƯA** phân tách UI Normal/Developer trong Setup Hub screen. Setup Hub luôn hiện tất cả các trường kỹ thuật (Cloud Host, Auth Key, Device ID, LAN IP, Password).

---

## 2. Current Shelly Implementation — Chi Tiết

### 2.1 Connection Models hiện tại

Có **2 connection modes** đã được triển khai:

1. **`serverCloud`** — Backend giữ credentials, Flutter chỉ gọi API `/api/shelly/*` và `/api/smart-charging/*`
2. **`advancedDirect`** — Flutter giữ credentials trong `FlutterSecureStorage`, gọi trực tiếp Cloud Control v2 API và LAN RPC

Mode được persist tại [`SmartChargerRepositoryFactory`](file:///c:/Users/khanh/OneDrive/Desktop/Vinfast%20Batery/app/lib/data/repositories/smart_charger_repository.dart#L557-L617) (`SharedPreferences: smart_charger.connection_mode.v1.<uid>`).

### 2.2 Discovery hiện có

[`ShellyDiscoveryService`](file:///c:/Users/khanh/OneDrive/Desktop/Vinfast%20Batery/app/lib/data/services/shelly_discovery_service.dart) đã triển khai:
- ✅ mDNS lookup `_shelly._tcp.local` (L36-L37)
- ✅ `probeDevice` via HTTP `Shelly.GetDeviceInfo` + `Shelly.GetStatus` (L90-L181)
- ✅ `discoverAndProbe` — parallel probe (L184-L202)
- ✅ `sweepSubnet` — /24 unicast scan (L230-L327)
- ✅ `detectLocalSubnet` (L205-L226)
- ⚠️ Chỉ lọc `isPlugSGen3` — bỏ qua các Shelly khác có thể đo power (L76)

### 2.3 Cloud Auth hiện có

[`ShellyCloudAuthService`](file:///c:/Users/khanh/OneDrive/Desktop/Vinfast%20Batery/app/lib/data/services/shelly_cloud_auth_service.dart):
- ✅ `listDevices` — thử v2 API rồi fallback legacy endpoints (L71-L231)
- ✅ `matchDevice` — match LAN ↔ Cloud device by ID (L234-L254)
- ✅ `assembleProfile` — kết hợp LAN + Cloud data thành `ShellyConnectionProfile` (L257-L282)
- ⚠️ `launchShellyCloudPortal` — chỉ mở trình duyệt, không có OAuth callback flow (L62-L68)

### 2.4 Backend OAuth (Integrator API)

[`routes.py` consent_start](file:///c:/Users/khanh/OneDrive/Desktop/Vinfast%20Batery/web/shelly/routes.py#L99-L122):
- ✅ Integrator consent URL generation (redirect to `my.shelly.cloud/integrator.html`)
- ✅ Consent callback handler (L198-L227)
- ⚠️ Yêu cầu `SHELLY_INTEGRATOR_TAG` và `SHELLY_CONSENT_CALLBACK_URL` — hiện trả 503 "Easy Connect đang chờ Shelly Integrator license" nếu chưa cấu hình

### 2.5 Secrets Storage

- **Client:** `FlutterSecureStorage` (Android EncryptedSharedPreferences) — [`smart_charger_credentials_service.dart`](file:///c:/Users/khanh/OneDrive/Desktop/Vinfast%20Batery/app/lib/data/services/smart_charger_credentials_service.dart)
- **Server:** AES-256-GCM encrypted Firestore collection via [`ShellyProfileVault`](file:///c:/Users/khanh/OneDrive/Desktop/Vinfast%20Batery/web/shelly/profile_vault.py) — keyed by `SHELLY_PROFILE_MASTER_KEY` env var
- `toRedactedJson()` đã tồn tại cho diagnostic output (L93-L103 in `shelly_connection.dart`)

### 2.6 Android Permissions hiện có

[`AndroidManifest.xml`](file:///c:/Users/khanh/OneDrive/Desktop/Vinfast%20Batery/app/android/app/src/main/AndroidManifest.xml):
- ✅ `ACCESS_WIFI_STATE`, `CHANGE_WIFI_STATE`, `CHANGE_WIFI_MULTICAST_STATE`
- ✅ `NEARBY_WIFI_DEVICES` (with `neverForLocation`)
- ✅ `ACCESS_LOCAL_NETWORK`
- ❌ Chưa có BLE permissions (`BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT`)

### 2.7 iOS Permissions hiện có

❌ **Chưa có** `NSLocalNetworkUsageDescription`, `NSBonjourServices` — mDNS trên iOS sẽ **KHÔNG hoạt động** nếu thiếu khai báo này.

---

## 3. Problems Found

### P1: Setup Hub quá phức tạp — Người dùng bình thường phải nhìn thấy API Key và Device ID
**Current:** [`smart_charger_setup_hub_screen.dart`](file:///c:/Users/khanh/OneDrive/Desktop/Vinfast%20Batery/app/lib/features/smart_charging/smart_charger_setup_hub_screen.dart) (3012 dòng) luôn hiện đầy đủ: Cloud Host, Auth Key, Device ID, LAN IP, Password, verification steps.
**Problem:** Normal user phải hiểu "Authorization Cloud Key", "Device ID", "Server URI" — hoàn toàn không thân thiện.
**Impact:** Giảm khả năng sử dụng, tăng support requests.

### P2: Developer Mode chưa được áp dụng cho Shelly setup
**Current:** Developer Mode chỉ ảnh hưởng `settings_screen.dart` (subtitles, developer tools section). Setup Hub **luôn** ở chế độ advanced.
**Problem:** Không có phân tách Normal vs Developer trong Shelly connection flow.
**Proposed:** Setup Hub screen cần dùng `developerModeUnlocked` flag để ẩn/hiện advanced fields.

### P3: Model hardcode Plug S Gen3 duy nhất
**Current:** [`shelly_connection.dart` L65-L67](file:///c:/Users/khanh/OneDrive/Desktop/Vinfast%20Batery/app/lib/data/models/shelly_connection.dart#L65-L67): `validate()` reject mọi model khác `S3PL-00112EU`. [`DiscoveredShellyDevice.isPlugSGen3`](file:///c:/Users/khanh/OneDrive/Desktop/Vinfast%20Batery/app/lib/data/models/shelly_connection.dart#L144-L148) lọc cứng.
**Problem:** Không hỗ trợ thiết bị Shelly khác có power meter (Shelly Pro PM, Shelly EM, Shelly Plus PM Mini, etc.).
**Proposed:** Thay bằng capability-based detection sau discovery.

### P4: iOS thiếu mDNS permission declarations
**Current:** Không có `NSLocalNetworkUsageDescription` hoặc `NSBonjourServices` trong Info.plist.
**Problem:** mDNS discovery sẽ bị iOS chặn im lặng — app fallback về "không tìm thấy thiết bị" mà không báo lỗi.
**Proposed:** Thêm khai báo đúng vào Info.plist.

### P5: Shelly Cloud OAuth chưa hoàn thiện
**Current:** `launchShellyCloudPortal()` chỉ mở web browser để user tự copy key. Backend consent flow yêu cầu Integrator license chưa có.
**Problem:** User phải tự sao chép Cloud Auth Key — rủi ro lỗi.
**Impact:** Trước khi có Integrator license, vẫn cần manual key input như backup.

### P6: Không tự động tạo profile từ discovery kết quả
**Current:** mDNS scan tìm được device → user phải chạm để điền IP vào form → vẫn phải nhập Cloud Key riêng.
**Problem:** Nếu device trên cùng LAN, app có thể kết nối trực tiếp mà không cần Cloud Key cho monitoring (read-only).

---

## 4. Target User Experience — Chiến Lược 3 Flow Thông Minh

### 4.0 Tổng Quan Chiến Lược Fallback

Khi người dùng nhấn "Kết nối Shelly", app tự động chạy qua **3 Flow theo thứ tự ưu tiên**, tự động chuyển flow khi flow hiện tại thất bại:

```
┌─────────────────────────────────────────────────────────────────┐
│                    FLOW TRANSITION ENGINE                       │
│                                                                 │
│  FLOW 1: LAN Discovery (Auto)                                  │
│  ├── mDNS scan + subnet sweep                                  │
│  ├── Tìm thấy → Chọn thiết bị → Kết nối ✅                    │
│  └── Không tìm thấy ─── AUTO ──→ FLOW 2                       │
│                                                                 │
│  FLOW 2: Shelly Cloud Connect (Guided)                         │
│  ├── Hướng dẫn lấy Cloud Auth Key từ app Shelly               │
│  ├── Nhập key → List devices từ Cloud → Chọn → Kết nối ✅     │
│  └── Thất bại / Bỏ qua ─── AUTO ──→ FLOW 3                   │
│                                                                 │
│  FLOW 3: Hỗ Trợ Thủ Công (Troubleshoot)                       │
│  ├── Checklist kiểm tra kết nối                                │
│  ├── Quét lại (quay về Flow 1)                                 │
│  ├── Nhập IP thủ công (nếu biết)                               │
│  └── Liên hệ hỗ trợ / Hướng dẫn chi tiết                     │
└─────────────────────────────────────────────────────────────────┘
```

> [!IMPORTANT]
> **Nguyên tắc chuyển flow:**
> - Flow 1 → Flow 2: **Tự động** sau khi LAN scan + sweep đều trả về 0 thiết bị. Không cần user action.
> - Flow 2 → Flow 3: **Tự động** nếu Cloud Auth thất bại (key sai, timeout, không tìm thấy thiết bị) **HOẶC** user nhấn "Bỏ qua".
> - Flow 3 → Flow 1: User có thể nhấn "Quét lại" để quay về Flow 1 bất cứ lúc nào.
> - Từ **bất kỳ flow nào**, user có thể nhấn nút quay lại (←) để huỷ toàn bộ.

### 4.1 Normal Mode (Developer OFF)

#### State: Disconnected
```
┌─────────────────────────────────────────────┐
│  ⚡ Smart Charger                           │
│                                             │
│  🔌 Shelly                                 │
│  Theo dõi điện năng sạc bằng thiết bị      │
│  Shelly.                                    │
│                                             │
│  ┌─────────────────────────────────────┐    │
│  │      🔍 Kết nối Shelly              │    │
│  └─────────────────────────────────────┘    │
│                                             │
└─────────────────────────────────────────────┘
```

---

#### 🔵 FLOW 1: LAN Discovery (Tự Động)

##### State: Discovering (Flow 1 — bắt đầu ngay khi tap "Kết nối Shelly")
```
┌─────────────────────────────────────────────┐
│  ← Kết nối Shelly                          │
│                                             │
│  ━━━━━ BƯỚC 1/3 ━━━━━                      │
│                                             │
│     ◉◉◉ Đang tìm kiếm...                  │
│     Quét mạng Wi-Fi hiện tại để tìm        │
│     thiết bị Shelly.                        │
│                                             │
│     ┌───────────────────────────────┐       │
│     │ 📡 mDNS scan...     ████░░   │       │
│     │ 🔍 Subnet sweep...  ░░░░░░   │       │
│     └───────────────────────────────┘       │
│                                             │
│  ⏱️ Thường mất 5-15 giây                   │
│                                             │
└─────────────────────────────────────────────┘
```

##### State: DeviceFound (1 thiết bị tương thích)
```
┌─────────────────────────────────────────────┐
│  ← Kết nối Shelly                          │
│                                             │
│  ✅ Đã tìm thấy thiết bị                   │
│                                             │
│  ┌──────────────────────────────────────┐   │
│  │ 🔌 Shelly Plug S — Garage Charger    │   │
│  │    IP: 192.168.1.50 • FW: 1.4.4     │   │
│  │    ● Online                          │   │
│  └──────────────────────────────────────┘   │
│                                             │
│  ┌─────────────────────────────────────┐    │
│  │        Kết nối thiết bị này          │    │
│  └─────────────────────────────────────┘    │
│                                             │
└─────────────────────────────────────────────┘
```

##### State: MultipleDevicesFound
```
┌─────────────────────────────────────────────┐
│  ← Kết nối Shelly                          │
│                                             │
│  Tìm thấy 3 thiết bị                       │
│  Chọn thiết bị bạn dùng để sạc xe.         │
│                                             │
│  ┌──────────────────────────────────────┐   │
│  │ 🔌 Shelly Plug S — Garage             │  │
│  │    ● Online • 192.168.1.50            │  │
│  ├──────────────────────────────────────┤   │
│  │ 🔌 Shelly Plus 1PM — Phòng khách      │  │
│  │    ● Online • 192.168.1.51            │  │
│  ├──────────────────────────────────────┤   │
│  │ 🔌 Shelly Pro 3EM — Tủ điện           │  │
│  │    ○ Offline                          │  │
│  └──────────────────────────────────────┘   │
│                                             │
└─────────────────────────────────────────────┘
```

---

#### 🟡 FLOW 2: Shelly Cloud Connect (Tự Động Chuyển Khi Flow 1 Thất Bại)

> **Khi nào chuyển:** Ngay sau khi Flow 1 (mDNS + sweep) trả về 0 thiết bị, app **tự động** chuyển sang Flow 2 với animation transition mượt.

##### State: CloudIntro (Flow 2 — giới thiệu + hướng dẫn lấy key)
```
┌─────────────────────────────────────────────┐
│  ← Kết nối Shelly                          │
│                                             │
│  ━━━━━ BƯỚC 2/3 ━━━━━                      │
│                                             │
│  ☁️ Kết nối qua Shelly Cloud               │
│                                             │
│  Không tìm thấy Shelly trên mạng Wi-Fi     │
│  hiện tại. Bạn có thể kết nối từ xa qua    │
│  Shelly Cloud.                              │
│                                             │
│  📋 Cách lấy Cloud Auth Key:               │
│  ┌──────────────────────────────────────┐   │
│  │ 1. Mở app Shelly trên điện thoại     │   │
│  │ 2. Vào User Profile → Cloud Auth Key  │   │
│  │ 3. Sao chép key và dán vào ô bên dưới │   │
│  └──────────────────────────────────────┘   │
│                                             │
│  🔑 Cloud Auth Key:                        │
│  ┌──────────────────────────────────────┐   │
│  │ ••••••••••••••••••••••••              │   │
│  └──────────────────────────────────────┘   │
│  🔒 Key được mã hoá và lưu an toàn        │
│                                             │
│  ┌─────────────────────────────────────┐    │
│  │      ☁️ Kết nối Cloud                │    │
│  └─────────────────────────────────────┘    │
│                                             │
│  ┌─────────────────────────────────────┐    │
│  │  🌐 Mở Shelly Cloud Portal          │    │
│  └─────────────────────────────────────┘    │
│                                             │
│       Bỏ qua → Xem hướng dẫn khác          │
│                                             │
└─────────────────────────────────────────────┘
```

> [!NOTE]
> **UI thân thiện cho Normal Mode:**
> - Chỉ yêu cầu **1 trường duy nhất**: Cloud Auth Key (obscured text).
> - Cloud Host được tự động dò từ `ShellyCloudAuthService.defaultCloudHosts` — user **KHÔNG** cần nhập.
> - Device ID được tự động lấy từ `listDevices()` — user **KHÔNG** cần nhập.
> - Key được mã hoá bằng `FlutterSecureStorage` + sync lên server qua `ShellyProfileVault` (AES-256-GCM).
> - Nút "Mở Shelly Cloud Portal" gọi `ShellyCloudAuthService.launchShellyCloudPortal()` (đã có sẵn).

##### State: CloudAuthenticating (Flow 2 — đang xác thực key)
```
┌─────────────────────────────────────────────┐
│  ← Kết nối Shelly                          │
│                                             │
│     ◉◉◉ Đang xác thực Cloud Key...        │
│     Kiểm tra key và tìm thiết bị trong     │
│     tài khoản Shelly Cloud của bạn.         │
│                                             │
│     ┌───────────────────────────────┐       │
│     │ 🔐 Auth check...    ████░░   │       │
│     │ 📡 Device list...   ░░░░░░   │       │
│     └───────────────────────────────┘       │
│                                             │
└─────────────────────────────────────────────┘
```

##### State: CloudDevicesFound (Flow 2 — chọn thiết bị từ Cloud)
```
┌─────────────────────────────────────────────┐
│  ← Kết nối Shelly                          │
│                                             │
│  ☁️ Thiết bị trên Shelly Cloud              │
│  Chọn thiết bị bạn dùng để sạc xe.         │
│                                             │
│  ┌──────────────────────────────────────┐   │
│  │ ☁️ Shelly Plug S — Garage Charger     │  │
│  │    ● Online (Cloud)                   │  │
│  ├──────────────────────────────────────┤   │
│  │ ☁️ Shelly Plus PM Mini                │  │
│  │    ○ Offline                          │  │
│  └──────────────────────────────────────┘   │
│                                             │
│  ┌─────────────────────────────────────┐    │
│  │        Kết nối thiết bị đã chọn      │    │
│  └─────────────────────────────────────┘    │
│                                             │
└─────────────────────────────────────────────┘
```

##### State: CloudAuthFailed (Flow 2 — key sai hoặc không tìm thấy thiết bị)
```
┌─────────────────────────────────────────────┐
│  ← Kết nối Shelly                          │
│                                             │
│  ⚠️ Không thể kết nối Cloud                │
│                                             │
│  • Cloud key không hợp lệ hoặc hết hạn     │
│  • Không tìm thấy thiết bị tương thích      │
│    trong tài khoản Cloud                    │
│                                             │
│  ┌─────────────────────────────────────┐    │
│  │     🔄 Nhập lại key                  │    │
│  └─────────────────────────────────────┘    │
│  ┌─────────────────────────────────────┐    │
│  │     ➡️ Xem hướng dẫn thêm           │    │
│  └─────────────────────────────────────┘    │
│                                             │
└─────────────────────────────────────────────┘
```

---

#### 🔴 FLOW 3: Hỗ Trợ Thủ Công (Troubleshooting)

> **Khi nào chuyển:** Flow 2 thất bại (key sai, timeout) **HOẶC** user nhấn "Bỏ qua" ở Flow 2 **HOẶC** user nhấn "Xem hướng dẫn thêm".

##### State: Troubleshoot (Flow 3 — hướng dẫn chi tiết + tuỳ chọn thủ công)
```
┌─────────────────────────────────────────────┐
│  ← Kết nối Shelly                          │
│                                             │
│  ━━━━━ BƯỚC 3/3 ━━━━━                      │
│                                             │
│  🔧 Hỗ trợ kết nối                         │
│                                             │
│  📋 Kiểm tra các bước sau:                  │
│  ┌──────────────────────────────────────┐   │
│  │ ☐ Shelly đã cắm điện và đèn LED     │   │
│  │   sáng xanh                          │   │
│  │ ☐ Shelly đã kết nối Wi-Fi (không     │   │
│  │   ở chế độ AP)                       │   │
│  │ ☐ Điện thoại cùng mạng Wi-Fi với    │   │
│  │   Shelly                             │   │
│  │ ☐ Router cho phép mDNS/multicast    │   │
│  └──────────────────────────────────────┘   │
│                                             │
│  ┌─────────────────────────────────────┐    │
│  │     🔍 Quét lại (Flow 1)             │    │
│  └─────────────────────────────────────┘    │
│                                             │
│  ── hoặc nhập thủ công ──                  │
│                                             │
│  Địa chỉ IP Shelly:                        │
│  ┌──────────────────────────────────────┐   │
│  │ 192.168.x.x                          │   │
│  └──────────────────────────────────────┘   │
│                                             │
│  ┌─────────────────────────────────────┐    │
│  │     🔗 Kết nối trực tiếp             │    │
│  └─────────────────────────────────────┘    │
│                                             │
│  ┌─────────────────────────────────────┐    │
│  │     📞 Liên hệ hỗ trợ               │    │
│  └─────────────────────────────────────┘    │
│                                             │
│  💡 Mẹo: Bạn có thể tìm IP Shelly trong   │
│  app Shelly hoặc trên trang quản trị       │
│  router của bạn.                            │
│                                             │
└─────────────────────────────────────────────┘
```

---

#### State: Connected (Chung cho cả 3 Flow)
```
┌─────────────────────────────────────────────┐
│  ⚡ Smart Charger                           │
│                                             │
│  🔌 Shelly Plug S — Garage Charger         │
│     ● Đã kết nối (LAN / Cloud / Thủ công)  │
│                                             │
│  ┌─────────────────────────────────────┐    │
│  │        Ngắt kết nối                  │    │
│  └─────────────────────────────────────┘    │
│                                             │
└─────────────────────────────────────────────┘
```

#### State: Incompatible (Chung)
```
┌─────────────────────────────────────────────┐
│  ← Kết nối Shelly                          │
│                                             │
│  ⚠️ Thiết bị không tương thích              │
│                                             │
│  "Shelly i3" không hỗ trợ đo điện năng     │
│  cần thiết cho chức năng theo dõi sạc.      │
│                                             │
│  Thiết bị cần có power metering: switch     │
│  với đo apower/voltage/current/energy.      │
│                                             │
│  ┌─────────────────────────────────────┐    │
│  │     Quét lại thiết bị khác           │    │
│  └─────────────────────────────────────┘    │
│                                             │
└─────────────────────────────────────────────┘
```

### 4.2 Developer Mode (Developer ON)

Khi Developer Mode bật, Shelly screen bổ sung **tất cả tuỳ chọn** mà không qua flow engine:

```
┌─────────────────────────────────────────────┐
│  🔧 Cấu hình nâng cao                      │
│                                             │
│  Connection Mode:  [Auto ▼]                 │
│   (Auto | Local | Cloud | Manual)           │
│                                             │
│  Device ID:   [shellyplug-xxxx          ]   │
│  Model:       S3PL-00112EU                  │
│  Generation:  3                             │
│  MAC:         AA:BB:CC:DD:EE:FF             │
│  Firmware:    1.4.4-g0xxxxxx                │
│                                             │
│  Local IP:    [192.168.1.50             ]   │
│  Cloud Host:  [shelly-104-eu.shelly.cloud]  │
│  Cloud credential: ✅ Đã cấu hình           │
│  RPC endpoint: http://192.168.1.50/rpc      │
│                                             │
│  [Test Connection] [Rediscover] [Save] [Reset]
│                                             │
└─────────────────────────────────────────────┘
```

> **Bảo mật:** Developer Mode **KHÔNG** hiển thị raw Cloud Auth Key trên UI. Chỉ hiện "Đã cấu hình" / "Chưa cấu hình". Nếu cần nhập key thủ công → form riêng với obscure text + cảnh báo bảo mật (đã có pattern ở [`shelly_setup_screen.dart` L248-L265](file:///c:/Users/khanh/OneDrive/Desktop/Vinfast%20Batery/app/lib/features/smart_charging/shelly_setup_screen.dart#L248-L265)).

---

## 5. Target Architecture

### 5.1 Service Abstraction — Sử dụng kiến trúc có sẵn

Codebase đã có một service architecture tốt. **KHÔNG** tạo class mới nếu không cần. Thay vào đó, **EXTEND** và **REFACTOR**:

```
SmartChargerService (EXISTING — keep as orchestrator)
├── ShellyDiscoveryService (EXISTING — extend capability detection)
├── ShellyCloudClient (EXISTING — keep)
├── ShellyLanClient (EXISTING — keep)
├── ShellyCloudAuthService (EXISTING — extend: auto-probe Cloud hosts)
├── SmartChargerCredentialsService (EXISTING — keep as storage)
├── ShellyConnectionCoordinator (NEW — 3-flow auto-connect state machine)
└── ShellyCapabilityChecker (NEW — power meter capability validation)
```

### 5.2 Luồng Kết Nối 3 Flow — Normal Mode

```
User taps "Kết nối Shelly"
        │
        ▼
┌─────────────────────────────────────────────────────┐
│ ShellyConnectionCoordinator.autoConnect()            │
│ Manages flow transitions automatically               │
└────────┬────────────────────────────────────────────┘
         │
 ╔═══════▼═══════╗
 ║   FLOW 1      ║
 ║   LAN Scan    ║
 ╚═══════╤═══════╝
         │
    ┌────▼────┐
    │ Step 1a │  mDNS discover `_shelly._tcp`
    │ mDNS    │  (ShellyDiscoveryService.discover)
    └────┬────┘
         │
    ┌────▼────┐
    │ Step 1b │  /24 unicast sweep (if mDNS=0)
    │ Sweep   │  (ShellyDiscoveryService.sweepSubnet)
    └────┬────┘
         │
    ┌────▼──────────────────────────────────┐
    │ Filter: hasCompatiblePowerMeter?       │ ← capability check
    └────┬──────────────────────────────────┘
         │
    Devices found?
    ├── 1   → deviceFound → user confirms → connecting
    ├── N   → multipleDevices → user picks → connecting
    └── 0   → ═══ AUTO TRANSITION ════════════╗
                                               ║
         ╔═════════════════════════════════════╝
         ║
 ╔═══════▼═══════╗
 ║   FLOW 2      ║
 ║ Cloud Connect ║
 ╚═══════╤═══════╝
         │
    ┌────▼────────────────────────────────────┐
    │ cloudAuthRequired state                  │
    │ UI: Hướng dẫn lấy Cloud Auth Key        │
    │     + trường nhập key (obscured)         │
    │     + nút "Mở Shelly Cloud Portal"      │
    │     + nút "Bỏ qua" ──→ Flow 3          │
    └────┬────────────────────────────────────┘
         │ (user nhập key + nhấn "Kết nối Cloud")
         ▼
    ┌────────────────────────────────────────┐
    │ cloudAuthenticating state               │
    │ ShellyCloudAuthService.listDevices()    │
    │   → auto-probe ALL defaultCloudHosts    │
    │   → filter compatible devices           │
    └────┬──────────────────────────────────┘
         │
    Devices found?
    ├── 1   → cloudDeviceFound → user confirms → connecting
    ├── N   → cloudMultipleDevices → user picks → connecting
    └── 0   → cloudAuthFailed ════════════════╗
         │ (key sai / timeout)                  ║
         │   → nút "Nhập lại"    ←─── loop     ║
         │   → nút "Xem hướng dẫn" ───────────╝
         │                                      ║
         ╔══════════════════════════════════════╝
         ║
 ╔═══════▼═══════╗
 ║   FLOW 3      ║
 ║ Troubleshoot  ║
 ╚═══════╤═══════╝
         │
    ┌────▼────────────────────────────────────┐
    │ troubleshoot state                       │
    │ UI: Checklist kiểm tra kết nối          │
    │     + "Quét lại" ──→ Flow 1             │
    │     + Nhập IP thủ công                  │
    │       → probeDevice(IP) → connecting    │
    │     + "Liên hệ hỗ trợ"                 │
    └─────────────────────────────────────────┘
         │
         │ (from any flow, after device selected)
         ▼
    ┌─────────────────────────────────────────┐
    │ connecting state                         │
    │ ShellyCapabilityChecker.check()          │
    │   → incompatible? → incompatible state  │
    │   → OK? → save profile + register       │
    └────┬────────────────────────────────────┘
         │
    ┌────▼────┐
    │ Verify  │  testConnection → safeBoot → noLoadTest
    └────┬────┘
         │
    ┌────▼────┐
    │ Done ✅ │  connected state
    └─────────┘
```

### 5.3 Key Architectural Decisions

| Quyết định | Lý do |
|---|---|
| **REUSE** `ShellyDiscoveryService` | Đã hoàn thiện mDNS + subnet sweep + probe |
| **REUSE** `SmartChargerCredentialsService` | Đã có draft/profile/verification lifecycle, UID scoping |
| **REUSE** `SmartChargerService.testConnection` | Safety test logic đã mature |
| **REUSE** `ShellyCloudAuthService.listDevices` | Đã xử lý multi-host probe + multi-endpoint fallback |
| **REUSE** `ShellyCloudAuthService.launchShellyCloudPortal` | Mở browser đến Cloud profile page |
| **REUSE** `ShellyCloudAuthService.assembleProfile` | Kết hợp LAN+Cloud data → `ShellyConnectionProfile` |
| **EXTEND** `DiscoveredShellyDevice` | Thêm capability detection thay vì hardcode isPlugSGen3 |
| **EXTEND** `ShellyDiscoveryService.probeDevice` | Dùng cho Flow 3 nhập IP thủ công |
| **REUSE** Developer Mode mechanism | SharedPreferences `developerModeUnlocked`, 7-tap activation |
| **BLE Provisioning → Phase 2** | Thiếu BLE permissions, chưa có Flutter BLE package, phức tạp hơn giá trị MVP |
| **OAuth Integrator → Phase 2** | License chưa có; Flow 2 dùng manual Cloud Auth Key thay thế — đủ cho MVP |

### 5.4 Flow Selection Logic (Tự động vs Thủ công)

```dart
/// Coordinator tự động quyết định chuyển flow dựa trên kết quả.
class FlowTransitionRules {
  /// Flow 1 → Flow 2: LAN scan trả về 0 thiết bị tương thích
  static bool shouldTransitionToCloud(List<DiscoveredShellyDevice> lanDevices) {
    return lanDevices.where((d) => d.isCompatible).isEmpty;
  }

  /// Flow 2 → Flow 3: Cloud auth thất bại HOẶC user nhấn "Bỏ qua"
  static bool shouldTransitionToTroubleshoot({
    required bool cloudAuthFailed,
    required bool userSkipped,
  }) {
    return cloudAuthFailed || userSkipped;
  }

  /// Flow 3 → Flow 1: User nhấn "Quét lại"
  /// (Không tự động — chỉ theo user action)
}
```

---

## 6. Connection State Machine

```dart
enum ShellyConnectionFlowState {
  // === Shared States ===
  disconnected,         // Initial — no device configured
  connecting,           // Testing connection + saving profile
  verifying,            // Running safety verification chain
  connected,            // Device verified and monitored
  incompatible,         // Device found but lacks power metering
  offline,              // Previously connected device unreachable

  // === Flow 1: LAN Discovery ===
  lanDiscovering,       // mDNS + subnet sweep running
  lanDeviceFound,       // Exactly 1 compatible device found via LAN
  lanMultipleDevices,   // Multiple compatible devices found via LAN

  // === Flow 2: Shelly Cloud Connect ===
  cloudAuthRequired,    // UI: nhập Cloud Auth Key
  cloudAuthenticating,  // Validating key + listing Cloud devices
  cloudDeviceFound,     // Exactly 1 compatible Cloud device
  cloudMultipleDevices, // Multiple Cloud devices — user picks
  cloudAuthFailed,      // Key invalid / no compatible Cloud devices

  // === Flow 3: Troubleshooting ===
  troubleshoot,         // Checklist + manual IP entry + support contact
  manualProbing,        // Probing user-entered IP address
}
```

### State Machine Transitions — Full 3-Flow

```
# === Entry ===
disconnected → (user taps "Kết nối") → lanDiscovering

# === Flow 1: LAN Discovery ===
lanDiscovering → (1 device)  → lanDeviceFound
lanDiscovering → (N devices) → lanMultipleDevices
lanDiscovering → (0 devices) → cloudAuthRequired          # AUTO → Flow 2
lanDeviceFound → (user confirms) → connecting
lanMultipleDevices → (user selects) → connecting

# === Flow 2: Cloud Connect ===
cloudAuthRequired → (user enters key) → cloudAuthenticating
cloudAuthRequired → (user taps "Bỏ qua") → troubleshoot   # → Flow 3
cloudAuthenticating → (1 device)  → cloudDeviceFound
cloudAuthenticating → (N devices) → cloudMultipleDevices
cloudAuthenticating → (0 / error) → cloudAuthFailed
cloudDeviceFound → (user confirms) → connecting
cloudMultipleDevices → (user selects) → connecting
cloudAuthFailed → (user taps "Nhập lại") → cloudAuthRequired
cloudAuthFailed → (user taps "Hướng dẫn") → troubleshoot  # → Flow 3

# === Flow 3: Troubleshooting ===
troubleshoot → (user taps "Quét lại")  → lanDiscovering    # → Flow 1
troubleshoot → (user enters IP)        → manualProbing
manualProbing → (device responds)      → connecting
manualProbing → (timeout/error)        → troubleshoot

# === Shared: Connection + Verification ===
connecting → (capability check fails)  → incompatible
connecting → (connection OK)           → verifying
connecting → (connection fails)        → troubleshoot      # → Flow 3
verifying → (all passed)               → connected
verifying → (verification fails)       → troubleshoot      # → Flow 3
connected → (user taps "Ngắt kết nối") → disconnected
connected → (device offline)           → offline
offline → (device back online)         → connected
incompatible → (user taps "Quét lại") → lanDiscovering     # → Flow 1

# === Any state ===
* → (user taps ←) → disconnected                          # Cancel all
```

> [!TIP]
> **So với plan cũ:** Cloud states (`cloudAuthRequired`, `cloudAuthenticating`) đã được **đưa vào MVP** thay vì defer Phase 2. Normal Mode user giờ có thể nhập Cloud Auth Key khi LAN thất bại — nhưng chỉ với 1 trường duy nhất (key) thay vì form kỹ thuật đầy đủ.
>
> **Flow 3 (Troubleshooting)** là state mới hoàn toàn — cung cấp checklist, nhập IP thủ công, và liên hệ hỗ trợ như lưới an toàn cuối cùng.

---

## 7. Data Model Changes

### 7.1 Extend `DiscoveredShellyDevice` — Capability detection

```
Current: isPlugSGen3 getter hardcoded to S3PL-00112EU + gen 3
Problem: Rejects other Shelly devices with power metering
Proposed: Add `hasPowerMetering` getter based on probed status fields
Files affected: shelly_connection.dart
Reason: Capability-based instead of model-based filtering
```

#### Proposed additions to [`shelly_connection.dart`](file:///c:/Users/khanh/OneDrive/Desktop/Vinfast%20Batery/app/lib/data/models/shelly_connection.dart):

```dart
// Add to DiscoveredShellyDevice:
bool get hasPowerMetering => 
    currentPowerW != null || relayState != null;

// Add alongside isPlugSGen3:
bool get isCompatible => hasPowerMetering || isPlugSGen3;
```

### 7.2 ShellyConnectionProfile.validate() — Relax model restriction + Allow/Deny rules

```
Current: validate() L65-67 rejects anything except S3PL-00112EU
Problem: Blocks other Shelly models with power meter
Proposed: Remove hardcoded model string check; rely on runtime capability probe.
         Add extensible allow/deny rule mechanism for future edge cases.
Files affected: shelly_connection.dart L65-67, NEW shelly_capability_checker.dart
Reason: Validation moves to capability check instead of string match.
        Allow/deny rules provide safety net if specific models have unexpected behavior.
```

#### Allow/Deny Rules Design

```dart
/// Extensible model compatibility rules.
/// Default: allow any model with verified power metering capability.
/// Add deny rules when specific models are found to have edge cases.
class ShellyModelRules {
  /// Models explicitly known to work well (fast path, skip extended checks).
  static const allowlist = {'S3PL-00112EU'}; // Plug S Gen3

  /// Models known to have incompatible power metering or dangerous behavior.
  /// If a model appears here, capability probe is overridden → incompatible.
  static const denylist = <String>{}; // Empty initially

  static ModelCompatibility check(String model, bool hasPowerMetering) {
    if (denylist.contains(model)) return ModelCompatibility.denied;
    if (allowlist.contains(model)) return ModelCompatibility.allowed;
    if (hasPowerMetering) return ModelCompatibility.probePass;
    return ModelCompatibility.incompatible;
  }
}

enum ModelCompatibility { allowed, probePass, incompatible, denied }
```

> [!TIP]
> **Khi phát hiện model có edge case:** Thêm vào `denylist` và release update. Không cần backend change — rules nằm trong client code. Có thể chuyển sang remote config sau nếu cần.

### 7.3 New: ShellyConnectionFlowState (State machine enum)

**File:** NEW [`app/lib/data/models/shelly_connection_state.dart`]

```dart
enum ShellyConnectionFlowState {
  disconnected, discovering, deviceFound, multipleDevices,
  connecting, verifying, connected, connectionFailed,
  incompatible, offline,
  // Phase 2: cloudAuthRequired, cloudAuthenticating,
}
```

### 7.4 Data separation — không cần thay đổi

`ShellyConnectionProfile` (persistent config) và `DiscoveredShellyDevice` (runtime discovery data) đã được phân tách đúng. `SmartChargerVerificationState` (debug/verification data) cũng đã tách riêng. **Không cần refactor data model lớn.**

---

## 8. Backend Changes

### 8.1 Backend routes đã đầy đủ cho MVP

Backend đã có tất cả endpoints cần thiết:

| Endpoint | Có sẵn | Dùng cho |
|---|---|---|
| `POST /api/shelly/consent/start` | ✅ | Integrator OAuth start (Phase 2) |
| `POST /api/shelly/consent/callback` | ✅ | OAuth callback (Phase 2) |
| `GET /api/shelly/devices` | ✅ | List bound devices |
| `GET /api/shelly/device` | ✅ | Get current binding |
| `POST /api/shelly/devices/<id>/select` | ✅ | Associate device with vehicle |
| `PUT /api/shelly/profiles/<id>` | ✅ | Register/sync profile |
| `POST /api/shelly/profiles/<id>/restore` | ✅ | Restore encrypted profile |
| `POST /api/shelly/profiles/resolve` | ✅ | Resolve profile for vehicle |
| `GET /api/shelly/capabilities` | ✅ | Get device capabilities |

**Kết luận: Không cần thay đổi backend cho MVP.** Tất cả API endpoints đã sẵn sàng.

---

## 9. Flutter Changes

### 9.1 New Files

| File | Purpose |
|---|---|
| `app/lib/data/models/shelly_connection_state.dart` | Connection flow state enum |
| `app/lib/data/services/shelly_connection_coordinator.dart` | Auto-connect state machine orchestrator |
| `app/lib/data/services/shelly_capability_checker.dart` | Power meter capability validation |
| `app/lib/features/smart_charging/shelly_connect_screen.dart` | Normal Mode simple connect UI |

### 9.2 Modified Files

| File | Current Purpose | Planned Changes |
|---|---|---|
| [`shelly_connection.dart`](file:///c:/Users/khanh/OneDrive/Desktop/Vinfast%20Batery/app/lib/data/models/shelly_connection.dart) | Connection profile + discovery models | Add `hasPowerMetering`, `isCompatible` to `DiscoveredShellyDevice`; relax `validate()` model check |
| [`shelly_discovery_service.dart`](file:///c:/Users/khanh/OneDrive/Desktop/Vinfast%20Batery/app/lib/data/services/shelly_discovery_service.dart) | mDNS + probe + sweep | Change `isPlugSGen3` filter to `isCompatible` in `discover()` L76; add capability probe to `probeDevice()` |
| [`smart_charger_setup_hub_screen.dart`](file:///c:/Users/khanh/OneDrive/Desktop/Vinfast%20Batery/app/lib/features/smart_charging/smart_charger_setup_hub_screen.dart) | Full setup wizard | Read `developerModeUnlocked` from SharedPreferences; when OFF → show simplified `ShellyConnectScreen`; when ON → show current advanced UI |
| [`settings_screen.dart`](file:///c:/Users/khanh/OneDrive/Desktop/Vinfast%20Batery/app/lib/features/settings/settings_screen.dart) | App settings | Update "Smart Charger" row to reflect new Shelly connection state |
| [`shelly_setup_screen.dart`](file:///c:/Users/khanh/OneDrive/Desktop/Vinfast%20Batery/app/lib/features/smart_charging/shelly_setup_screen.dart) | Legacy stepper setup | Deprecate — redirect to new flow or keep as developer-only |

---

## 10. Security Design

### 10.1 Client-side OK

| Dữ liệu | Lưu ở đâu | Lý do |
|---|---|---|
| Device ID, model, generation | `FlutterSecureStorage` + Firestore metadata | Non-secret device identity |
| Local IP address | `FlutterSecureStorage` | LAN address — public within network |
| Connection state, verification status | `FlutterSecureStorage` | UI state |
| Friendly device name | `FlutterSecureStorage` | Display only |

### 10.2 Server-side only

| Dữ liệu | Lưu ở đâu | Lý do |
|---|---|---|
| Cloud Auth Key | `FlutterSecureStorage` (encrypted) + `ShellyProfileVault` (AES-256-GCM on server) | Full control credential — already properly stored |
| Local password | `FlutterSecureStorage` only | Never sent to Firestore — already implemented correctly |
| OAuth access/refresh tokens | Server-only (future Integrator flow) | Never exposed to client |

### 10.3 Existing security mechanisms — Đã đầy đủ

- ✅ `toRedactedJson()` — omits secrets for diagnostics
- ✅ UID-scoped secure storage keys (`_profileKey.$uid`)
- ✅ Profile vault encryption server-side
- ✅ `FlutterSecureStorage` with `AndroidOptions(encryptedSharedPreferences: true)`

**Không cần thay đổi security model cho MVP.**

---

## 11. Platform Permissions

### 11.1 Android — Đã đầy đủ

Tất cả permissions cần thiết cho mDNS và LAN scanning đã có:
- ✅ `INTERNET`, `ACCESS_WIFI_STATE`, `CHANGE_WIFI_STATE`
- ✅ `CHANGE_WIFI_MULTICAST_STATE` — cần cho mDNS multicast
- ✅ `NEARBY_WIFI_DEVICES` (android:usesPermissionFlags="neverForLocation") — Android 12+
- ✅ `ACCESS_LOCAL_NETWORK`
- ❌ BLE: `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT` — **chỉ cần cho Phase 2 BLE Provisioning**

### 11.2 iOS — Cần thêm

> [!IMPORTANT]
> iOS **BẮT BUỘC** có `NSLocalNetworkUsageDescription` và `NSBonjourServices` để mDNS hoạt động. Hiện tại thiếu hoàn toàn.

**Cần thêm vào** [`app/ios/Runner/Info.plist`](file:///c:/Users/khanh/OneDrive/Desktop/Vinfast%20Batery/app/ios/Runner/Info.plist):

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>Ứng dụng cần truy cập mạng cục bộ để tìm kiếm và kết nối với thiết bị Shelly trong mạng Wi-Fi của bạn.</string>
<key>NSBonjourServices</key>
<array>
  <string>_shelly._tcp</string>
</array>
```

### 11.3 Runtime permission handling

Đã có [`permission_handler`](file:///c:/Users/khanh/OneDrive/Desktop/Vinfast%20Batery/app/pubspec.yaml#L43) package. [`shelly_setup_screen.dart` L87-L94](file:///c:/Users/khanh/OneDrive/Desktop/Vinfast%20Batery/app/lib/features/smart_charging/shelly_setup_screen.dart#L87-L94) đã request `Permission.nearbyWifiDevices`. **Reuse** pattern này.

---

## 12. Migration Strategy

### 12.1 Backward Compatibility Analysis

**Config hiện tại:**
- `FlutterSecureStorage`: `smart_charger.shelly_profile.v1.<uid>` → `ShellyConnectionProfile` JSON
- `FlutterSecureStorage`: `smart_charger.verification.v1.<uid>` → `SmartChargerVerificationState` JSON
- `SharedPreferences`: `smart_charger.connection_mode.v1.<uid>` → `"server_cloud"` | `"advanced_direct"`
- Server: encrypted profile in Firestore via `ShellyProfileVault`

**Migration cần thiết: KHÔNG.**

Tất cả existing profiles vẫn hoạt động nguyên vẹn. Refactor này:
1. Thêm layer UI đơn giản **phía trên** config hiện tại
2. Không thay đổi storage schema
3. Không thay đổi `ShellyConnectionProfile` structure
4. Legacy manual API-key setups vẫn load đúng qua `credentials.readProfile()`

**Developer Mode vẫn hiện tất cả advanced config** → manual override luôn khả dụng.

**Xác nhận:** Không cần data migration. Existing configurations are preserved.

---

## 13. Error Handling

| Scenario | Detection | UI Behavior |
|---|---|---|
| Wi-Fi/LAN unavailable | `SocketException`, `NetworkInterface.list` empty | "Không tìm thấy mạng Wi-Fi. Hãy kiểm tra kết nối Internet." + Retry |
| Local Network permission denied (iOS) | mDNS returns empty + iOS platform check | "Cần cho phép truy cập mạng cục bộ trong Cài đặt iOS." + Open Settings |
| Bluetooth permission denied | `Permission.bluetooth.isPermanentlyDenied` | Phase 2 only |
| mDNS not found (0 devices) | `discover()` returns empty list | Auto fallback to `sweepSubnet()`, then **auto-transition to Flow 2** (Cloud Auth Key) |
| Shelly offline | `SmartChargerErrorCode.deviceOffline` | "Shelly đang offline. Kiểm tra nguồn điện và Wi-Fi của ổ cắm." |
| Different Wi-Fi network | Device discovered but unreachable via RPC | "Thiết bị có thể ở mạng Wi-Fi khác. Hãy kiểm tra cả điện thoại và Shelly cùng mạng." |
| RPC timeout | `TimeoutException` from `ShellyLanClient` | "Shelly không phản hồi. Kiểm tra nguồn điện." + Retry |
| RPC auth required | 401 from `/rpc/Shelly.GetDeviceInfo` → `authEnabled=true` | Hiện form nhập mật khẩu local |
| Incompatible device | Capability check: no `apower`/`voltage`/`current` fields | "Thiết bị này không hỗ trợ đo điện năng." + Suggest compatible models |
| Cloud auth invalid | `SmartChargerErrorCode.cloudAuthInvalid` (401/403) | "Cloud key không hợp lệ hoặc đã bị thu hồi." |
| Cloud rate limited | `SmartChargerErrorCode.cloudRateLimited` (429) | "Shelly Cloud đang giới hạn tần suất. Thử lại sau." + auto-retry with backoff |
| Device removed from Cloud account | `SmartChargerErrorCode.cloudDeviceNotFound` | "Thiết bị đã bị xóa khỏi tài khoản Shelly Cloud." |
| IP changed | RPC to stored IP fails, re-discover finds device at new IP | Auto-update `lanAddress` in profile transparently |
| Duplicate device | Same device ID already bound to another vehicle | "Thiết bị này đã được liên kết với xe khác. Bạn có muốn chuyển?" |
| Backend unavailable | `ServerSmartChargerService` network errors | "Không thể kết nối máy chủ. Cấu hình cục bộ vẫn hoạt động." |
| Firestore failure | Server profile sync fails | Non-blocking — local config remains authoritative (already implemented) |

---

## 14. Testing Strategy

### 14.1 Unit Tests

| Test | Target File | What to Test |
|---|---|---|
| Capability detection | `shelly_capability_checker.dart` | `apower` presence, `voltage`/`current` presence, energy fields, switch config |
| Connection state machine | `shelly_connection_coordinator.dart` | All state transitions, error recovery, timeout handling |
| Profile assembly | `shelly_cloud_auth_service.dart` | `assembleProfile` with various LAN+Cloud combinations |
| Discovery filtering | `shelly_discovery_service.dart` | `isCompatible` instead of `isPlugSGen3` |
| Config validation | `shelly_connection.dart` | Relaxed model validation |

### 14.2 Integration Tests

| Test | Components | What to Test |
|---|---|---|
| Local discovery flow | Discovery → Probe → Capability → Save | Full auto-connect with mock mDNS |
| Cloud auth flow | Auth service → List devices → Select → Profile assembly | Cloud key validation and device listing |
| Profile sync | Credentials → Server → Vault | Save/restore encrypted profile |
| Connection + Verification | SmartChargerService.testConnection | Cloud + LAN + safe boot + no-load |

### 14.3 UI Tests

| Test | Mode | What to Test |
|---|---|---|
| Normal Mode connect | Developer OFF | No API key/device ID visible; auto-discover; device picker; connect/disconnect |
| Normal Mode states | Developer OFF | All connection states render correctly |
| Developer Mode config | Developer ON | All advanced fields visible; manual override; test connection; reset |
| Mode transition | Toggle | Switching developer mode doesn't lose connection |

### 14.4 Manual Device Tests

| Scenario | Test |
|---|---|
| Gen 3 Plug S same LAN | mDNS finds device, auto-fills, connects |
| Gen 3 Plug S different LAN | mDNS fails, sweep fails, Cloud fallback works |
| Shelly offline | Graceful error, retry available |
| Multiple devices | Picker shows all, selection works |
| Auth-protected Shelly | Password prompt appears, Digest auth works |

---

## 15. Implementation Phases

### Phase 1: Core Refactor — Data Model + Capability Detection

**Goal:** Replace hardcoded Plug S Gen3 filtering with capability-based detection.

**Files:**
- MODIFY [`app/lib/data/models/shelly_connection.dart`](file:///c:/Users/khanh/OneDrive/Desktop/Vinfast%20Batery/app/lib/data/models/shelly_connection.dart)
  - Add `hasPowerMetering` and `isCompatible` to `DiscoveredShellyDevice`
  - Relax `validate()` model check to accept any model with power metering
- MODIFY [`app/lib/data/services/shelly_discovery_service.dart`](file:///c:/Users/khanh/OneDrive/Desktop/Vinfast%20Batery/app/lib/data/services/shelly_discovery_service.dart)
  - Change `isPlugSGen3` filter in `discover()` L76 to `isCompatible`
- NEW `app/lib/data/services/shelly_capability_checker.dart`
  - `checkCapability(DiscoveredShellyDevice)` → verifies `switch:0` has `apower`, `voltage`, `current`, `aenergy`
- NEW `app/lib/data/models/shelly_connection_state.dart`
  - `ShellyConnectionFlowState` enum

**Dependencies:** None

**Acceptance criteria:**
- ✅ mDNS scan finds Shelly devices with power meter that aren't Plug S Gen3
- ✅ Plug S Gen3 still works as before
- ✅ Devices without power metering are rejected with clear message
- ✅ All existing tests pass

**Risks:** Relaxing model validation might allow devices with incomplete power meter fields. Mitigated by capability probe.

---

### Phase 2: Connection Coordinator (3-Flow State Machine)

**Goal:** Auto-connect state machine orchestrating 3-flow fallback: LAN → Cloud → Troubleshoot.

**Files:**
- NEW `app/lib/data/services/shelly_connection_coordinator.dart`
  - `ShellyConnectionCoordinator` — emits `ShellyConnectionFlowState` stream
  - `autoConnect()` — full sequence: mDNS → sweep → auto-transition to Cloud flow
  - `submitCloudKey(String key)` — validate key + list Cloud devices
  - `probeManualIp(String ip)` — probe user-entered IP for Flow 3
  - `connectDevice(DiscoveredShellyDevice)` — probe + capability check + save
  - `disconnect()` — clear profile + state
  - `skipToTroubleshoot()` — user-triggered skip from Flow 2 → Flow 3
  - `retryLanScan()` — user-triggered restart from Flow 3 → Flow 1

**Dependencies:** Phase 1

**Acceptance criteria:**
- ✅ Flow 1 → Flow 2: Auto-transitions when LAN scan returns 0 devices
- ✅ Flow 2 → Flow 3: Auto-transitions on Cloud auth failure OR user skip
- ✅ Flow 3 → Flow 1: User taps "Quét lại" to restart LAN scan
- ✅ State stream correctly reflects all flow transitions
- ✅ Single compatible device auto-selected in both LAN and Cloud flows
- ✅ Multiple devices require user selection in both flows
- ✅ Manual IP probe in Flow 3 works correctly
- ✅ Cancel token / lifecycle management prevents orphaned scans

**Risks:** mDNS may be unreliable on some routers — sweep fallback + Cloud flow mitigates this.

---

### Phase 3: Normal Mode UI — 3-Flow Connect Screen

**Goal:** "Kết nối Shelly" screen with 3-flow fallback UX for Normal Mode users.

**Files:**
- NEW `app/lib/features/smart_charging/shelly_connect_screen.dart`
  - Driven by `ShellyConnectionCoordinator` state stream
  - **Flow 1 UI:** discovering animation (mDNS + sweep), device card(s), device picker
  - **Flow 2 UI:** Cloud Auth Key intro + guided instructions + obscured key input + "Mở Shelly Cloud Portal" + "Bỏ qua" button
  - **Flow 3 UI:** Troubleshooting checklist + "Quét lại" button + manual IP input + "Liên hệ hỗ trợ"
  - Step indicator (BƯỚC 1/3, 2/3, 3/3) shows current flow position
  - **NEVER** shows: Device ID, Server URI, MAC, RPC endpoint, Cloud Host
  - Cloud Auth Key shown as **single obscured text field** only — minimal UI
- MODIFY [`smart_charger_setup_hub_screen.dart`](file:///c:/Users/khanh/OneDrive/Desktop/Vinfast%20Batery/app/lib/features/smart_charging/smart_charger_setup_hub_screen.dart)
  - Read `SharedPreferences('developerModeUnlocked')` on load
  - When Developer OFF: navigate to `ShellyConnectScreen` instead of showing advanced tabs
  - When Developer ON: show current full setup UI unchanged

**Dependencies:** Phase 2

**Acceptance criteria:**
- ✅ Normal user sees 3-flow guided experience
- ✅ Flow transitions are smooth with animation
- ✅ Cloud Auth Key entry is simplified (1 field only, obscured)
- ✅ Cloud Host is auto-probed, not user-entered
- ✅ Device ID is auto-fetched from Cloud listDevices, not user-entered
- ✅ Troubleshoot screen shows interactive checklist + manual IP option
- ✅ Developer users see full advanced setup unchanged
- ✅ Both modes share same underlying `SmartChargerCredentialsService` and `ShellyConnectionProfile`

**Risks:** Setup Hub is 3012 lines — routing logic must be added carefully without breaking existing flows.

---

### Phase 4: iOS Permissions + Developer UI Polish

**Goal:** iOS mDNS works; Developer UI cleaned up with proper sectioning.

**Files:**
- MODIFY [`app/ios/Runner/Info.plist`](file:///c:/Users/khanh/OneDrive/Desktop/Vinfast%20Batery/app/ios/Runner/Info.plist)
  - Add `NSLocalNetworkUsageDescription` + `NSBonjourServices` for `_shelly._tcp`
- MODIFY [`settings_screen.dart`](file:///c:/Users/khanh/OneDrive/Desktop/Vinfast%20Batery/app/lib/features/settings/settings_screen.dart)
  - Update "Smart Charger" row to show connection state from coordinator
  - When connected, show device name + "● Đã kết nối"
  - When disconnected, show "Chưa kết nối"

**Dependencies:** Phase 3

**Acceptance criteria:**
- ✅ mDNS discovery works on iOS
- ✅ Local Network permission dialog appears on iOS
- ✅ Settings screen reflects actual Shelly connection state
- ✅ Developer section shows "Cấu hình nâng cao Shelly" link

**Risks:** iOS permission prompt must be shown before first mDNS call — timing matters.

---

### Phase 5: Error Handling + IP Change Recovery

**Goal:** Graceful error handling for all failure scenarios; auto-recover from IP change.

**Files:**
- MODIFY `shelly_connection_coordinator.dart`
  - Add re-discovery on IP change detection
  - Handle all error scenarios from Section 13
- MODIFY `shelly_connect_screen.dart`
  - Error state UIs for each scenario
  - Permission denied dialogs with links to Settings

**Dependencies:** Phase 3

**Acceptance criteria:**
- ✅ Every error in Section 13 has a user-friendly message
- ✅ IP change auto-recovered via re-discovery
- ✅ Permission denied shows clear remediation steps
- ✅ No raw exception messages shown to user

**Risks:** Low — error handling extends existing `SmartChargerException` pattern.

---

### Phase 6: Tests + Cleanup

**Goal:** Comprehensive tests; cleanup deprecated code.

**Files:**
- NEW `app/test/shelly_capability_checker_test.dart`
- NEW `app/test/shelly_connection_coordinator_test.dart`
- MODIFY existing tests as needed

**Dependencies:** All previous phases

**Acceptance criteria:**
- ✅ Unit tests for capability detection
- ✅ Unit tests for connection state machine
- ✅ Integration tests for discovery → connect flow
- ✅ `flutter test` passes
- ✅ `flutter build apk` succeeds

---

### Phase 7 (Future): OAuth Integrator + BLE Provisioning

**NOT in MVP.** Deferred until:
- Shelly Integrator license obtained → OAuth consent flow (replaces manual key entry in Flow 2)
- BLE package evaluated (`flutter_blue_plus` or `flutter_reactive_ble`)
- BLE permissions added to Android/iOS manifests
- BLE provisioning UI designed

> [!NOTE]
> **Cloud Auth Key (manual entry) đã có trong MVP** qua Flow 2. Phase 7 sẽ **thay thế** manual key entry bằng OAuth consent flow tự động — UX tốt hơn nhưng cần Integrator license.

---

## 16. Exact Files To Modify

| File | Current Purpose | Planned Changes |
|---|---|---|
| [`app/lib/data/models/shelly_connection.dart`](file:///c:/Users/khanh/OneDrive/Desktop/Vinfast%20Batery/app/lib/data/models/shelly_connection.dart) | Connection profile + discovery models | Add `hasPowerMetering`, `isCompatible` getters; relax `validate()` |
| [`app/lib/data/services/shelly_discovery_service.dart`](file:///c:/Users/khanh/OneDrive/Desktop/Vinfast%20Batery/app/lib/data/services/shelly_discovery_service.dart) | mDNS + probe + sweep | Change hardcoded `isPlugSGen3` filter to `isCompatible` |
| [`app/lib/features/smart_charging/smart_charger_setup_hub_screen.dart`](file:///c:/Users/khanh/OneDrive/Desktop/Vinfast%20Batery/app/lib/features/smart_charging/smart_charger_setup_hub_screen.dart) | Full advanced setup wizard | Add developer mode gate — route Normal Mode to simple connect screen |
| [`app/lib/features/settings/settings_screen.dart`](file:///c:/Users/khanh/OneDrive/Desktop/Vinfast%20Batery/app/lib/features/settings/settings_screen.dart) | App settings | Update Shelly row to show live connection state |
| [`app/ios/Runner/Info.plist`](file:///c:/Users/khanh/OneDrive/Desktop/Vinfast%20Batery/app/ios/Runner/Info.plist) | iOS app config | Add `NSLocalNetworkUsageDescription`, `NSBonjourServices` |

## 17. New Files To Create

| File | Purpose |
|---|---|
| `app/lib/data/models/shelly_connection_state.dart` | `ShellyConnectionFlowState` enum for state machine |
| `app/lib/data/services/shelly_connection_coordinator.dart` | Auto-connect state machine orchestrator |
| `app/lib/data/services/shelly_capability_checker.dart` | Power meter capability validation |
| `app/lib/features/smart_charging/shelly_connect_screen.dart` | Normal Mode simple connect UI |
| `app/test/shelly_capability_checker_test.dart` | Capability detection tests |
| `app/test/shelly_connection_coordinator_test.dart` | State machine tests |

## 18. Dependencies To Add

| Package | Platform | Why |
|---|---|---|
| *None for MVP* | — | All needed packages already in pubspec: `multicast_dns`, `http`, `permission_handler`, `flutter_secure_storage`, `url_launcher`, `shared_preferences` |

> [!NOTE]
> `multicast_dns: ^0.3.3+1` is already in [`pubspec.yaml` L63](file:///c:/Users/khanh/OneDrive/Desktop/Vinfast%20Batery/app/pubspec.yaml#L63). No new packages needed.

## 19. Risks / Open Technical Questions

> [!WARNING]
> ### R1: iOS mDNS Reliability
> iOS has aggressive Local Network permission requirements. Some users may deny the permission and never see the prompt again. Mitigation: check permission status before discovery, show instructions to enable in Settings.

### ~~R2: Shelly Cloud Auth Key Entry for Cloud-Only Users~~ — ĐÃ CẬP NHẬT
> **Quyết định mới (v1.1.6):** Normal Mode MVP **CHO PHÉP** nhập Cloud Auth Key qua **Flow 2** (tự động chuyển khi LAN thất bại). UI thân thiện: chỉ 1 trường duy nhất (obscured text) + hướng dẫn lấy key từ app Shelly. Cloud Host được auto-probe, Device ID được auto-fetch.
>
> **Lý do cập nhật:** Chiến lược 3-flow đảm bảo user có thể kết nối trong mọi tình huống (LAN / Cloud / Manual IP). Chỉ yêu cầu 1 trường = vẫn thân thiện với người dùng bình thường.

### R3: Relaxed Model Validation Impact
Cho phép Shelly model khác ngoài S3PL-00112EU có thể tạo edge cases chưa được test (different switch channel IDs, different status JSON structure). **Đã giảm thiểu rủi ro** bằng:
1. Capability-based probe kiểm tra field presence thực tế
2. **Allow/deny rules** (Section 7.2) — allowlist cho models đã test, denylist cho models có vấn đề. Mặc định: cho phép nếu có power metering.
3. Có thể chuyển rules sang remote config sau nếu cần block model khẩn cấp.

### R4: Setup Hub Screen Size
`smart_charger_setup_hub_screen.dart` (3012 dòng, 109KB) rất lớn. Refactor cần cẩn thận để không break existing flows. Recommend: add developer gate routing at the entry point rather than deep refactoring.

### R5: Concurrent Discovery
Nếu user bấm "Kết nối" → scan chạy → user navigate back → scan vẫn chạy. Cần cancel token / lifecycle management trong coordinator.

---

## 20. Recommended Implementation Order

```
Phase 1 → Phase 2 → Phase 3 → Phase 4 → Phase 5 → Phase 6
 (Model)   (3-Flow)   (UI)     (iOS)    (Errors)  (Tests)
```

Mỗi phase có thể merge và test độc lập. **Phase 1-3 tạo thành core functional MVP** (3-flow hoạt động). Phase 4-6 bổ sung polish + quality.

---

## 21. Definition of Done

| # | Tiêu chí | Ghi chú |
|---|---|---|
| 1 | Normal user never enters Device ID, Server URL, Cloud Host, or MAC | UI hides all technical fields when Developer OFF |
| 2 | User can just tap "Kết nối Shelly" | Single entry point → 3-flow auto-connect |
| 3 | **Flow 1:** App auto-discovers Shelly on LAN when possible | mDNS + subnet sweep |
| 4 | **Flow 2:** App guides user to enter Cloud Auth Key when LAN fails | 1 field only (obscured), Cloud Host auto-probed, Device ID auto-fetched |
| 5 | **Flow 3:** App provides troubleshooting when Cloud fails | Checklist + manual IP entry + support contact |
| 6 | **Auto-transition:** Flow 1 → 2 automatic, Flow 2 → 3 automatic or user-skip | No dead ends |
| 7 | Developer Mode still exposes/edits advanced config | Existing Setup Hub UI preserved for Developer ON |
| 8 | Cloud secrets are not unnecessarily exposed to Flutter | `FlutterSecureStorage` + `toRedactedJson()` + `ShellyProfileVault` |
| 9 | Legacy manual configuration is supported or safely migrated | No migration needed — existing profiles load transparently |
| 10 | Existing battery-monitoring functionality is not broken | No changes to monitoring/charging logic |
| 11 | Normal Mode and Developer Mode share same underlying connection model | Both use `ShellyConnectionProfile` + `SmartChargerCredentialsService` |
| 12 | Tests exist for connection state and capability detection | Unit tests for coordinator and capability checker |
| 13 | No sensitive credentials are logged | Existing pattern: `toRedactedJson()`, `debugPrint` redacts keys |
| 14 | App handles Shelly IP changes gracefully | Re-discovery on RPC failure |
| 15 | Incompatible devices are detected and clearly reported | Capability-based probe with user-friendly message |
| 16 | Disconnect/reconnect works reliably | Clear profile → state resets to disconnected |

---

## 22. Recommended MVP Scope

### ✅ MVP (Ship Now) — Phases 1-6

| Feature | Effort | UX Impact |
|---|---|---|
| Capability-based device detection | Thấp | Hỗ trợ nhiều Shelly models |
| **3-Flow auto-connect state machine** | Trung bình | **Core logic** — LAN → Cloud → Troubleshoot |
| **Normal Mode 3-flow connect screen** | Cao | **Highest UX impact** — guided fallback experience |
| **Flow 2: Cloud Auth Key entry** | Trung bình | Kết nối từ xa khi LAN thất bại |
| **Flow 3: Troubleshooting** | Thấp | Lưới an toàn cuối — manual IP + checklist |
| iOS mDNS permissions | Thấp | mDNS hoạt động trên iOS |
| Developer Mode gate in Setup Hub | Thấp | Tách Normal vs Advanced UI |
| Error handling + IP change recovery | Trung bình | Robust error UX |
| Tests | Trung bình | Quality assurance |

**Tổng effort ước lượng:** ~5-6 ngày cho 1 developer.

### 📋 Defer (Ship Later)

| Feature | Reason to Defer |
|---|---|
| **OAuth Integrator consent flow** | License chưa có; Flow 2 dùng manual Cloud Auth Key thay thế — đủ cho MVP |
| BLE Provisioning | Cần thêm package + permissions + complex pairing UI — giá trị thấp khi user đã có Shelly trên Wi-Fi |

### Nguyên tắc MVP (Cập nhật v1.1.6)

1. **3-Flow > Single-Flow:** Thay vì chỉ hỗ trợ LAN, MVP bao gồm 3 flow fallback để user luôn có đường kết nối
2. **Guided > Technical:** Flow 2 (Cloud) chỉ yêu cầu 1 trường duy nhất (key), không yêu cầu Cloud Host hay Device ID
3. **Reuse > Rewrite:** Sử dụng tối đa code hiện tại (`ShellyCloudAuthService.listDevices`, `probeDevice`, `assembleProfile`)
4. **Gate > Refactor:** Thêm developer mode gate vào entry point thay vì refactor 3000-line setup hub
5. **Safety net:** Allow/deny rules cho model compatibility + troubleshoot flow cho edge cases

---

## 23. User Decisions Log

| # | Quyết định | Trạng thái | Ghi chú |
|---|---|---|---|
| ~~D1~~ | ~~Cloud fallback: Normal Mode MVP không cho nhập Cloud Auth Key~~ | ❌ Thay thế bởi D5 | ~~LAN-not-found → thông báo hướng dẫn~~ |
| D2 | MVP scope: Phases 1–6 (bao gồm 3-flow) | 🔄 Cập nhật | Mở rộng từ Phases 1–4 sang 1–6 để bao gồm Cloud + Troubleshoot |
| D3 | Model validation: Capability probe + allow/deny rules | ✅ Đã xác nhận | Bỏ hardcode S3PL-00112EU. Allowlist cho models đã test, denylist cho models có vấn đề |
| D4 | iOS permissions: Phải có trong MVP | ✅ Đã xác nhận | `NSLocalNetworkUsageDescription` + `NSBonjourServices` — không có thì LAN discovery trên iOS không hoạt động |
| **D5** | **3-Flow fallback strategy** | **✅ Mới** | **Flow 1 (LAN) → auto → Flow 2 (Cloud Auth Key) → auto → Flow 3 (Troubleshoot)**. User luôn có đường kết nối. Cloud Auth Key được cho phép trong Normal Mode nhưng chỉ 1 trường duy nhất. |
| **D6** | **Flow transition rules** | **✅ Mới** | **Flow 1→2: tự động khi 0 devices. Flow 2→3: tự động khi auth fail HOẶC user skip. Flow 3→1: user action "Quét lại".** |
