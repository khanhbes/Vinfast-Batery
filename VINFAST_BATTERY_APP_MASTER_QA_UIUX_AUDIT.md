# VINFAST BATTERY APP — MASTER QA / BUG HUNT / LOGIC / SECURITY / UIUX AUDIT

**Repository:** `https://github.com/khanhbes/Vinfast-Batery`  
**Primary scope:** `app/`  
**Target:** Flutter Android application  
**Audit mode:** Code-first, test-first, production-safety-first  
**Version:** Consolidated QA + UI/UX Edition  
**Date:** 2026-09-07

---

## 0. ROLE

Bạn là một nhóm kỹ thuật cấp Senior gồm:

- Senior Flutter Engineer
- Senior Mobile QA/SDET
- Senior UI/UX Designer
- Senior Product Designer
- Accessibility Specialist
- Mobile Security Engineer
- Firebase/Firestore Engineer
- API Contract Reviewer
- IoT/Shelly Integration Engineer
- ML/AI Integration Engineer
- Android Performance Engineer

Nhiệm vụ KHÔNG phải chỉ chạy app và xác nhận rằng giao diện mở được.

Nhiệm vụ là:

> đọc toàn bộ `app/` → hiểu architecture → lập state machine → lập data/API contract → audit logic → audit security → audit UI/UX → cố tình phá các giả định của ứng dụng → tái hiện bug → viết regression test → đưa ra release recommendation.

Không được xem `flutter analyze` hoặc `flutter test` PASS là bằng chứng rằng sản phẩm đã đúng.

---

# 1. PHẠM VI BẮT BUỘC

Đọc recursive toàn bộ:

```text
app/
  lib/
  test/
  android/
  assets/
  pubspec.yaml
  analysis_options.yaml
  l10n.yaml
  build_apk.ps1
  google-services.json
```

Ưu tiên đặc biệt các vùng hiện có trong source:

```text
lib/core/theme/
  app_colors.dart
  app_theme.dart
  app_motion.dart

lib/core/widgets/
  animated_battery_gauge.dart
  empty_state.dart
  error_state.dart
  loading_skeleton.dart
  quick_action_menu.dart
  vehicle_detail_sheet.dart
  ...

lib/features/auth/
  login_screen.dart
  register_screen.dart
  auth_gate.dart

lib/features/home/
lib/features/dashboard/
lib/features/battery_monitor/
lib/features/charge_log/
lib/features/ai/
lib/features/maintenance/
lib/features/notifications/
lib/features/settings/
lib/features/statistics/
lib/features/trip_planner/

lib/navigation/
lib/data/services/
lib/data/repositories/
lib/core/services/
```

Các màn quan trọng phải được kiểm tra độc lập:

- Login
- Register
- Auth Gate
- Home
- Dashboard
- Battery Monitor
- Charge Log
- Add Charge Log
- Add Manual Trip
- Smart Charging ETA / Smart Charging controls
- AI Charging Predictor
- AI Models
- Trip Planner
- Trip Live Map
- Statistics
- Maintenance
- Notification Center
- Settings
- Appearance Settings
- Profile
- Vehicle Garage
- Vehicle Specification Detail
- AI Functions / AI settings
- Guide / Help
- App Update flow

---

# 2. MỤC TIÊU CUỐI CÙNG

Phải trả lời được tối thiểu các câu hỏi sau:

## Logic / Data

- SOC có bao giờ < 0 hoặc > 100 không?
- Battery capacity có nhất quán theo vehicle model không?
- Charge session có thể start hai lần không?
- Stop session có thể ghi log hai lần không?
- Trip tracking có duplicate session không?
- App restart có phục hồi đúng trạng thái không?
- Offline sync có ghi trùng dữ liệu không?
- Firestore malformed document có crash màn hình không?
- User A có bao giờ đọc/ghi dữ liệu User B không?
- App có tin `ownerUid`/UID do client tự cung cấp không?
- Model AI lỗi có làm app crash không?
- AI fallback có bị hiển thị như model thật không?
- Prediction có NaN/Infinity/âm/>100 không?
- Smart Charger có giữ đúng fail-safe/manual-OFF priority không?
- Cloud/LAN fallback có gây double command không?
- App đóng/restart có vô tình auto-ON relay không?
- Update APK/version có compare đúng semantic version không?

## UI/UX

- Có màn nào đẹp ở 412dp nhưng vỡ ở 320/360dp không?
- Có chữ bị cắt khi text scale 1.3x/1.5x/2.0x không?
- Có nút nào khó bấm hoặc nhỏ hơn touch target hợp lý không?
- Loading/error/empty/offline/stale state có được thiết kế đầy đủ không?
- Có thao tác nguy hiểm nào thiếu confirm hoặc feedback không?
- Khi nhấn ON/OFF sạc, UI có phản ánh đúng trạng thái “đang gửi lệnh / chờ readback / thành công / thất bại” không?
- Animation có gây jank, che mất dữ liệu hoặc khiến người dùng tưởng lệnh đã thành công khi thực tế chưa readback không?
- Dark/light theme có tương phản đủ và nhất quán không?
- Vietnamese/English có gây overflow không?
- Screen reader có hiểu đúng ý nghĩa pin, SOC, nút sạc, biểu đồ, trạng thái offline không?
- App có giữ focus/scroll/selection hợp lý khi quay lại màn?
- Navigation có tạo duplicate route hoặc mất state không?
- Error copy có giúp người dùng biết phải làm gì tiếp theo không?
- UI có phân biệt “estimated”, “measured”, “AI prediction”, “fallback”, “stale” rõ ràng không?

---

# 3. NGUYÊN TẮC AUDIT

## 3.1 Không sửa trước khi hiểu

Vòng đầu:

1. Inventory
2. Architecture
3. State machines
4. Baseline
5. Reproduction
6. Report
7. Regression test
8. Fix proposal

Không refactor lớn trước khi xác nhận bug.

## 3.2 Không thử nghiệm nguy hiểm trên production

Không:

- bật/tắt relay production liên tục;
- fuzz API production;
- xóa dữ liệu thật;
- dùng tài khoản thật của người khác;
- gửi GPS giả vào production;
- brute-force auth;
- load model độc hại.

Dùng test account, mock, emulator, local gateway và fixture.

## 3.3 Phân loại bằng bằng chứng

Dùng:

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

# 4. INVENTORY & ARCHITECTURE

Tạo:

`app/QA_ARCHITECTURE_INVENTORY.md`

Phải ghi:

- entry point;
- state management;
- navigation;
- auth lifecycle;
- Firebase collections;
- API clients;
- local storage;
- secure storage;
- notification services;
- background services;
- GPS/location;
- trip lifecycle;
- charge lifecycle;
- AI services;
- model sync;
- Smart Charger service;
- update service;
- theme system;
- motion system;
- localization;
- reusable widgets;
- screen list;
- dependency graph.

Tạo state machine cho tối thiểu:

### Authentication

```text
unknown -> signedOut -> signingIn -> signedIn
                         |             |
                         v             v
                       error         signOut
```

### Charge session

```text
idle -> starting -> charging -> stopping -> completed
              \        |          |
               \       v          v
                -> error/recovery <-
```

### Smart Charger relay

```text
unknown
  -> offline
  -> off
  -> commandOnPending
  -> on
  -> commandOffPending
  -> off
  -> error/readbackMismatch
```

### Trip

```text
idle -> starting -> tracking -> stopping -> completed
```

### Sync

```text
clean -> dirty -> queued -> syncing -> synced
                         \-> failed -> retry
```

---

# 5. BASELINE

Chạy và ghi output:

```bash
git status --short --branch
git remote -v
git fetch --all --prune
git rev-parse HEAD
flutter --version
dart --version
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

Nếu release build khả dụng:

```bash
flutter build apk --release
```

Không che lỗi existing.

Ghi:

- commit SHA;
- branch;
- dirty worktree;
- Flutter/Dart version;
- Android SDK;
- emulator/device;
- failed tests;
- warnings;
- deprecations.

---

# 6. AUTHENTICATION / SESSION

Test:

- email/password hợp lệ;
- email sai format;
- password sai;
- user không tồn tại;
- disabled user;
- network offline;
- Firebase timeout;
- multiple rapid tap Login;
- app background trong khi login;
- app killed trong khi login;
- token expiry;
- sign out;
- sign out rồi Back;
- multi-session nếu supported.

Không được:

- duplicate login request;
- spinner vô hạn;
- stale authenticated screen sau logout;
- token xuất hiện trong log;
- login error raw Firebase exception hiển thị trực tiếp cho user.

---

# 7. USER ISOLATION / FIRESTORE OWNERSHIP

Tạo:

- User A
- User B
- Vehicle A
- Vehicle B
- Charge A/B
- Trip A/B
- Notification A/B

Kiểm tra toàn bộ repository/service.

User A không được:

- đọc Vehicle B;
- update Vehicle B;
- đọc Charge B;
- đọc Trip B;
- ghi maintenance B;
- đọc notification B;
- link model vào vehicle B.

Identity phải derive từ authenticated UID.

Không tin UID do UI gửi nếu có thể derive từ auth state.

---

# 8. MALFORMED FIRESTORE DATA

Tạo fixture:

- missing field;
- null;
- wrong type;
- int thay double;
- string thay number;
- invalid timestamp;
- negative distance;
- SOC 101;
- SOC -1;
- NaN/Infinity nếu serialization layer cho phép;
- deleted record;
- unknown enum.

Một document xấu không được crash toàn màn.

Phải:

- normalize;
- skip;
- fallback;
- hoặc hiển thị error state rõ ràng.

---

# 9. BATTERY LOGIC

Test boundary:

```text
SOC: -1, 0, 1, 20, 50, 99, 100, 101
Capacity: 0, negative, missing, huge
Voltage/current/power: finite, zero, negative, extreme
```

Invariants:

- SOC finite;
- SOC 0..100;
- capacity > 0;
- estimated range >= 0;
- predicted time >= 0;
- percent formatting thống nhất;
- không divide by zero;
- không hiện NaN/Infinity.

Kiểm tra consistency giữa:

- Home;
- Dashboard;
- Battery Monitor;
- Statistics;
- Smart Charging;
- AI Predictor.

---

# 10. CHARGE SESSION

Test:

- start từ idle;
- start khi đã charging;
- stop khi idle;
- double start;
- double stop;
- rapid tap;
- app killed;
- app background;
- network loss;
- clock/timezone change;
- Firestore write fail;
- retry;
- stale session recovery.

Một charge vật lý không được sinh hai log do retry.

Session ID phải ổn định theo business operation.

---

# 11. SMART CHARGER SAFETY

Ưu tiên an toàn hơn UI convenience.

Test:

- ON cần confirm nếu design yêu cầu;
- OFF phải nhanh và dễ;
- OFF không bị block bởi AI/network;
- command pending phải hiển thị rõ;
- ON chỉ coi là thành công sau readback phù hợp;
- readback mismatch;
- Cloud fail -> LAN fallback;
- Cloud/LAN race;
- duplicate command;
- gateway restart;
- app restart;
- timeout;
- Shelly offline;
- Shelly reports stale;
- relay physically OFF nhưng UI cached ON;
- device timer expired;
- safety cutoff;
- maximum charging duration;
- manual OFF priority;
- no auto-ON after restart;
- recovery không bật relay ngoài ý muốn.

UI không được đổi sang trạng thái ON chỉ vì request gửi thành công nếu readback chưa xác nhận.

---

# 12. AI PREDICTION

Test input:

- missing;
- null;
- wrong type;
- SOC 0/100;
- target < current;
- target > 100;
- extreme temperature;
- zero power;
- invalid model;
- AI API unavailable;
- timeout;
- malformed response.

Output invariants:

- finite;
- SOC 0..100;
- duration >= 0;
- confidence hợp lý;
- model source/version đúng;
- fallback được đánh dấu.

Không hiển thị heuristic/fallback như model chính thức.

---

# 13. TRIP / GPS / BACKGROUND

Test Android permissions:

- allow;
- deny;
- deny permanently;
- approximate location;
- precise location;
- permission revoked while running.

Test:

- no GPS;
- weak GPS;
- stale fix;
- jump/outlier;
- zero speed;
- background;
- Doze;
- battery saver;
- app killed;
- device reboot nếu scope hỗ trợ.

Không tạo distance âm hoặc route vô lý.

Trip Live Map phải xử lý:

- no points;
- one point;
- duplicate point;
- out-of-order timestamps;
- GPS jump;
- offline tiles/network.

---

# 14. NOTIFICATIONS

Test:

- permission granted/denied;
- Android notification permission;
- foreground;
- background;
- app killed;
- duplicate notification;
- tap notification;
- deep-link destination;
- stale notification;
- deleted object target.

Notification không được đưa user vào màn unauthorized hoặc object đã xóa mà crash.

---

# 15. SETTINGS / PERSISTENCE

Test:

- theme;
- language;
- AI settings;
- notification settings;
- profile;
- vehicle selection;
- preferred vehicle;
- Smart Charger settings.

Scenario:

1. change setting;
2. kill app;
3. reopen;
4. sign out;
5. sign in;
6. compare expected persistence boundary.

Không để setting của User A leak sang User B nếu setting thuộc user scope.

---

# 16. UPDATE FLOW

Test semantic versions:

```text
1.0.9
1.0.10
1.1.0
2.0.0
```

Không compare bằng string lexical.

Test:

- no update;
- optional update;
- forced update nếu supported;
- bad metadata;
- bad download URL;
- interrupted download;
- checksum mismatch nếu supported;
- no storage;
- install permission issue;
- old APK cached.

Không mở file update không đáng tin mà không có trust mechanism phù hợp.

---

# 17. OFFLINE / RETRY / SYNC

Test:

- launch offline;
- go offline giữa request;
- reconnect;
- flaky network;
- timeout;
- DNS fail;
- backend 500/503;
- Firebase unavailable.

UX phải phân biệt:

- offline;
- loading;
- stale cached data;
- hard error.

Không được nói “Đã lưu” nếu write chỉ mới nằm local nhưng UI không giải thích.

Retry không được tạo duplicate.

---

# 18. CONCURRENCY / RACE CONDITIONS

Test đồng thời:

- double Save;
- double Start Trip;
- double Start Charge;
- ON và OFF liên tiếp;
- app sync + realtime listener;
- refresh + navigation;
- selected vehicle changed while request in-flight;
- AI request A/B out-of-order;
- logout while request pending.

Response stale không được overwrite state mới.

---

# 19. SECURITY / PRIVACY

Audit:

- secure storage;
- SharedPreferences;
- logs;
- Firebase config;
- API URLs;
- bearer tokens;
- Shelly credentials;
- local Wi-Fi credentials nếu có;
- cloud keys;
- screenshot exposure;
- clipboard;
- exported Android components;
- deep links;
- intent filters;
- network security config.

Không log:

- password;
- bearer token;
- private key;
- admin key;
- Shelly secret.

Firebase browser/mobile API key không tự động được coi là secret.

---

# 20. UI/UX AUDIT — DESIGN SYSTEM

Đây là phần BẮT BUỘC, không phải optional polish.

Audit:

```text
app_colors.dart
app_theme.dart
app_motion.dart
shared widgets
```

Lập bảng token:

- primary;
- secondary;
- background;
- surface;
- text primary/secondary;
- success;
- warning;
- danger;
- disabled;
- border;
- radius;
- elevation;
- spacing;
- typography;
- icon sizing;
- animation duration/easing.

Tìm:

- hard-coded màu ngoài design system;
- radius không nhất quán;
- padding 12/14/15/16 lộn xộn vô lý;
- font size tự phát;
- component giống nhau nhưng style khác;
- dark/light mapping thiếu.

---

# 21. UI/UX — VISUAL HIERARCHY

Trên từng screen, trả lời:

1. Người dùng nhìn thấy thông tin quan trọng nhất trong < 2 giây không?
2. Primary CTA có rõ không?
3. Có quá nhiều card competing attention không?
4. Có màu cảnh báo bị dùng như màu trang trí không?
5. Information density có quá cao không?
6. Giá trị quan trọng như SOC/range/status có hierarchy rõ không?
7. Đơn vị có rõ không?
8. Estimated data có được phân biệt với measured data không?

Đặc biệt Home/Dashboard:

- không để quá nhiều AI card tranh nhau;
- không lặp cùng một metric ở nhiều card không cần thiết;
- ưu tiên battery status, range, charger/trip state.

---

# 22. UI/UX — SCREEN STATE MATRIX

Mỗi màn phải có matrix:

| State | UI expected |
|---|---|
| Initial | không flash dữ liệu sai |
| Loading | skeleton/progress hợp lý |
| Success | dữ liệu đầy đủ |
| Empty | empty state có hướng dẫn |
| Error | error message + retry |
| Offline | offline indicator |
| Stale | timestamp/stale badge nếu cần |
| Partial | phần còn dùng được vẫn hiển thị |
| Permission denied | hướng dẫn rõ |
| Unauthorized | quay về auth hợp lý |

Không chấp nhận spinner vô hạn.

---

# 23. UI/UX — INTERACTION STATES

Mọi interactive control phải kiểm tra:

- default;
- hover nếu platform hỗ trợ;
- pressed;
- focused;
- disabled;
- loading;
- success;
- error.

Đặc biệt:

- Start/Stop Trip
- Start/Stop Charge
- Smart Charger ON/OFF
- Save
- Add log
- Delete
- Retry
- Select vehicle
- Target SOC
- Time selector

Không dùng cùng một icon/màu cho hai trạng thái đối nghịch.

---

# 24. UI/UX — TOUCH TARGET

Kiểm tra target thực tế, không chỉ icon visual.

Ưu tiên ít nhất khoảng 44–48 logical pixels cho control chính.

Test:

- icon trong AppBar;
- quick actions;
- tiny chevron;
- radio/chip;
- target selector;
- close dialog;
- map controls.

Hai nút nguy hiểm không đặt quá sát nhau.

---

# 25. UI/UX — NAVIGATION

Kiểm tra:

- back button;
- Android system Back;
- nested route;
- modal -> back;
- bottom sheet -> back;
- notification deep link;
- auth redirect;
- logout;
- tab state;
- scroll restoration;
- selected vehicle preservation.

Không:

- duplicate screen stack;
- mở cùng modal 2 lần;
- mất state không chủ ý;
- quay Back vào protected screen sau logout.

---

# 26. UI/UX — FORMS & KEYBOARD

Test Login/Register/Profile/Add Charge/Add Trip/Settings.

- keyboard không che field/button;
- scroll tới focused field;
- Next/Done action;
- validation timing;
- inline error;
- server error;
- preserving entered values;
- password show/hide;
- autofill;
- copy/paste;
- Vietnamese diacritics;
- long text.

Không hiển thị error trước khi user có cơ hội nhập hợp lý trừ validation tức thời rõ ràng.

---

# 27. UI/UX — RESPONSIVE DEVICE MATRIX

Bắt buộc test tối thiểu:

```text
320 x 568
360 x 640
375 x 812
412 x 915
tablet portrait
tablet landscape
```

Và:

- landscape phone;
- split-screen nếu supported;
- notch/cutout;
- gesture navigation;
- 3-button navigation.

Không được có:

- overflow stripe;
- clipped text;
- modal vượt màn;
- CTA nằm dưới navigation bar;
- chart mất legend;
- horizontal scroll bất ngờ.

---

# 28. UI/UX — TEXT SCALE

Test:

```text
1.0x
1.15x
1.3x
1.5x
2.0x
```

Kiểm tra:

- button;
- chip;
- list tile;
- statistic card;
- bottom sheet;
- dialog;
- AppBar;
- battery gauge label;
- chart legend;
- tab.

Không khóa text scale để né overflow.

---

# 29. UI/UX — LOCALIZATION

Test cả:

- Vietnamese
- English

Kiểm tra:

- missing key;
- hard-coded mixed language;
- overflow vì tiếng Việt dài hơn;
- plural;
- date;
- decimal;
- units;
- 12h/24h nếu relevant.

Không để một màn tiếng Việt, dialog tiếng Anh trừ thuật ngữ kỹ thuật bắt buộc.

---

# 30. UI/UX — DARK / LIGHT THEME

Test mọi screen/state ở cả hai theme.

Kiểm tra:

- contrast;
- icons;
- card border;
- disabled state;
- chart grid;
- modal background;
- map overlay;
- snackbar/toast;
- success/warning/error;
- skeleton.

Không dùng màu text cố định khiến dark mode unreadable.

---

# 31. ACCESSIBILITY

Test bằng TalkBack nếu có thiết bị/emulator.

Mọi control quan trọng phải có semantic label.

Ví dụ:

Không chỉ:

> “82”

Mà nên convey:

> “Mức pin 82 phần trăm”.

Smart Charger:

- “Bật sạc”
- “Tắt sạc”
- “Đang gửi lệnh”
- “Thiết bị ngoại tuyến”

Biểu đồ phải có text summary thay thế cho thông tin thiết yếu.

Kiểm tra:

- traversal order;
- focus;
- semantics;
- modal focus;
- button labels;
- icon-only controls;
- color-only status.

Không dùng màu là dấu hiệu duy nhất cho warning/error.

---

# 32. REDUCED MOTION

Nếu OS/user preference yêu cầu giảm chuyển động:

- giảm/bỏ animation trang trí;
- không bỏ feedback trạng thái quan trọng;
- không dùng scale/bounce mạnh.

Audit `app_motion.dart`.

Mọi animation phải có mục đích.

---

# 33. MOTION / ANIMATION QA

Test:

- page transition;
- card press;
- gauge update;
- SOC change;
- progress;
- bottom sheet;
- quick action;
- success feedback;
- charger relay state;
- countdown;
- energy/power update.

Không:

- animation làm state giả;
- delayed UI khiến user double tap;
- animation > operation feedback;
- jank khi realtime update 5s;
- animate entire screen mỗi polling tick.

---

# 34. UI PERFORMANCE / JANK

Profile bằng Flutter DevTools/Profile mode.

Scenario:

- Dashboard scroll;
- Home scroll;
- Statistics chart;
- AI Models list;
- Maintenance list;
- Live Map;
- Smart Charging realtime polling;
- animated battery gauge.

Ghi:

- slow frame;
- rebuild storm;
- large image;
- expensive chart;
- excessive provider invalidation.

Không tối ưu dựa đoán; đo trước.

---

# 35. UI/UX — LOADING

Không dùng một spinner toàn màn cho mọi thứ nếu dữ liệu cũ vẫn hữu ích.

Ưu tiên:

- skeleton cho initial content;
- inline progress cho button;
- stale data + refresh indicator cho polling;
- optimistic UI chỉ khi operation an toàn.

Smart Charger ON không được optimistic “ON” trước readback.

---

# 36. UI/UX — ERROR COPY

Mỗi lỗi phải trả lời:

1. Chuyện gì xảy ra?
2. Dữ liệu có mất không?
3. Người dùng làm gì tiếp theo?

Tránh:

- “Something went wrong”
- raw exception
- HTTP 500
- Firebase code kỹ thuật

nếu có thể chuyển thành copy hữu ích.

---

# 37. UI/UX — EMPTY STATE

Empty state phải khác error state.

Ví dụ:

Charge Log rỗng:

> “Chưa có phiên sạc.”

Có CTA hợp lý:

> “Thêm phiên sạc”

Không dùng warning đỏ cho dữ liệu rỗng bình thường.

---

# 38. UI/UX — OFFLINE / STALE DATA

Nếu hiển thị cache:

phải có khả năng biết:

- dữ liệu cập nhật lúc nào;
- hiện offline hay backend lỗi;
- thao tác nào vẫn dùng được.

Không silently hiển thị SOC cũ như live SOC.

---

# 39. UI/UX — SAFETY-CRITICAL SMART CHARGER

Đây là release gate riêng.

UI phải phân biệt rõ:

```text
OFF
TURNING ON
ON
TURNING OFF
OFFLINE
ERROR
READBACK MISMATCH
SAFETY STOP
```

Màu/icon/text phải nhất quán.

OFF action phải luôn dễ tìm.

Không để AI recommendation che nút manual OFF.

Target SOC phải cho thấy:

- current SOC;
- target SOC;
- estimated completion;
- model/fallback source nếu relevant;
- limitation nếu SOC là estimated.

Khi target không khả thi:

không chỉ disable nút; giải thích lý do.

---

# 40. UI/UX — AI EXPLAINABILITY

Prediction card cần tránh “AI said so”.

Hiển thị khi phù hợp:

- predicted value;
- confidence;
- model source/version;
- fallback indicator;
- last updated;
- assumptions.

Không làm confidence 0.52 trông như certainty 100%.

---

# 41. UI/UX — CHARTS / STATISTICS

Test:

- no data;
- one data point;
- 1000 points;
- extreme values;
- negative invalid fixture;
- out-of-order timestamp.

Chart cần:

- readable axis;
- unit;
- legend;
- tooltip;
- empty state;
- screen-reader summary cho thông tin thiết yếu.

Không truncate số khiến hiểu sai.

---

# 42. UI/UX — MAP

Trip Live Map / Planner:

- loading;
- location denied;
- GPS unavailable;
- route missing;
- network missing;
- one-point trip;
- route outlier.

Controls không che map content quan trọng.

Bottom sheet không chiếm toàn screen vô lý.

---

# 43. UI/UX — MODAL / BOTTOM SHEET

Test tất cả:

- open;
- close;
- swipe;
- back;
- outside tap;
- keyboard;
- landscape;
- text scale;
- double open.

Destructive action không dismiss ngẫu nhiên làm user tưởng đã thực thi.

---

# 44. UI/UX — CONFIRMATION & DESTRUCTIVE ACTION

Confirm cho:

- logout nếu cần;
- delete vehicle/log/task;
- reset;
- dangerous Smart Charger ON nếu design yêu cầu.

OFF an toàn không nên bị thêm friction không cần thiết.

Button labels cụ thể:

- “Xóa xe”
- “Dừng sạc”

thay vì “OK”.

---

# 45. VISUAL REGRESSION

Thiết lập golden/screenshot test cho màn ổn định.

Tối thiểu:

- Login
- Home
- Dashboard
- Battery Monitor
- Charge Log
- Smart Charging
- AI Predictor
- Statistics
- Settings

Variant:

- light;
- dark;
- Vietnamese;
- English;
- empty;
- loaded;
- error nếu ổn định.

Không dùng screenshot test thay functional test.

---

# 46. UI TEST AUTOMATION

Ưu tiên:

```text
flutter_test
integration_test
golden tests
SemanticsTester / accessibility-oriented widget tests
```

Test:

- no overflow;
- navigation;
- loading/error/empty;
- button disabled/loading;
- duplicate tap guard;
- theme;
- text scaling;
- localization;
- semantics labels.

---

# 47. HIGH-RISK HYPOTHESES — APP

Bắt buộc kiểm chứng, không mặc định là bug:

### APP-H1
Charge Start rapid double tap tạo hai session/log?

### APP-H2
Stop/retry tạo duplicate ChargeLog?

### APP-H3
Trip tracking restart tạo duplicate trip?

### APP-H4
User switch nhưng provider/cache còn dữ liệu user cũ?

### APP-H5
Vehicle switch khi request AI đang pending khiến response vehicle A overwrite vehicle B?

### APP-H6
SOC malformed >100 hoặc NaN làm gauge/chart crash?

### APP-H7
AI fallback được hiển thị như model thật?

### APP-H8
Offline cached SOC bị hiển thị như live data?

### APP-H9
Smart Charger UI đổi ON trước readback?

### APP-H10
Cloud timeout + LAN fallback gửi double ON/OFF?

### APP-H11
App/gateway restart có auto-ON ngoài ý muốn?

### APP-H12
Manual OFF bị delay bởi AI/session logic?

### APP-H13
Token/credential xuất hiện trong logs/storage không an toàn?

### APP-H14
Version `1.0.10` bị coi nhỏ hơn `1.0.9`?

### APP-H15
Text scale 1.5x/2.0x gây overflow ở dashboard/modal?

### APP-UX-H16
320dp làm CTA hoặc card bị clipped?

### APP-UX-H17
Dark mode có warning/error contrast kém?

### APP-UX-H18
TalkBack không đọc được battery gauge/charger control?

### APP-UX-H19
Reduced Motion không được tôn trọng?

### APP-UX-H20
Polling 5s animate/rebuild toàn màn gây jank?

### APP-UX-H21
Loading state che mất nút OFF an toàn?

### APP-UX-H22
Error copy không phân biệt offline với server failure?

### APP-UX-H23
Vietnamese copy dài gây overflow trong chip/button?

### APP-UX-H24
Back navigation sau logout vào lại protected screen?

### APP-UX-H25
Modal/bottom sheet bị keyboard che CTA?

---

# 48. DEVICE / OS MATRIX

Tối thiểu:

- Android 12
- Android 13
- Android 14
- Android 15 nếu SDK/emulator có

Thiết bị:

- small phone;
- common mid-size;
- large phone;
- tablet nếu app hỗ trợ.

Test:

- dark/light;
- gesture nav;
- 3-button nav;
- battery saver;
- font scale;
- display size;
- notification permission;
- location permission.

---

# 49. PERFORMANCE / MEMORY

Đo:

- cold start;
- warm start;
- Home first meaningful content;
- Dashboard load;
- chart render;
- map load;
- AI request;
- Smart Charger polling.

Kiểm tra:

- timer dispose;
- stream subscription dispose;
- animation controller dispose;
- provider lifetime;
- background service;
- map controller;
- repeated navigation.

Không để memory tăng liên tục sau 20–50 lần navigation.

---

# 50. PROPERTY / FUZZ TEST

Với pure logic:

Dùng randomized/property testing nếu phù hợp.

Invariants:

```text
0 <= SOC <= 100
duration >= 0
range >= 0
distance >= 0
finite(value) == true
```

Fuzz local:

- model parser;
- Firestore model parser;
- API response parser;
- calculation service.

Client data lỗi không nên gây app crash.

---

# 51. BUG FORMAT

```markdown
### APP-BUG-XXX — Title

Status:
Severity:
Confidence:

Screen/Subsystem:
File:
Function/Region:
Device/OS:

Preconditions:

Steps to reproduce:
1.
2.
3.

Expected:

Actual:

Evidence:

Root cause:

Data impact:
Safety impact:
Security impact:
UX impact:
Accessibility impact:

Regression test:

Suggested fix:

Verification:
```

---

# 52. UI/UX DEFECT FORMAT

```markdown
### APP-UX-XXX — Title

Severity:
Screen:
State:
Viewport/device:
Theme:
Language:
Text scale:

User goal:

Observed behavior:

Expected behavior:

Why this matters:

Accessibility impact:

Screenshot/video evidence:

Design-system cause:

Suggested design/code fix:

Regression coverage:
```

---

# 53. SEVERITY

## P0 — Critical

- unsafe charger control;
- unauthorized cross-user write/delete;
- credential compromise;
- severe privacy leak;
- update mechanism compromise;
- app can auto-ON charger unexpectedly.

## P1 — High

- data loss/duplicate;
- manual OFF unavailable/delayed;
- cross-user read;
- broken authentication;
- core flow unusable;
- severe accessibility blocker on primary flow;
- screen broken on common device size.

## P2 — Medium

- wrong statistics;
- stale state;
- confusing AI/source;
- significant responsive issue;
- important loading/error UX failure;
- navigation defect with workaround.

## P3 — Low

- cosmetic inconsistency;
- minor spacing;
- non-critical microcopy issue.

---

# 54. RELEASE GATES — FUNCTIONAL

Không `READY FOR RELEASE` nếu còn:

- P0;
- P1 data integrity;
- P1 auth/ownership;
- charger safety violation;
- auto-ON after restart;
- duplicate session/log;
- severe AI output invariant violation;
- release build failure;
- Flutter test/analyze failure nghiêm trọng.

---

# 55. RELEASE GATES — UI/UX

Không `READY FOR RELEASE` nếu:

- primary CTA bị inaccessible ở 320/360dp;
- common screen overflow;
- text scale 1.3x làm core flow unusable;
- Smart Charger OFF bị che/khó bấm;
- UI báo ON khi chưa readback;
- loading/error che mất safety control;
- TalkBack không thao tác được core flow;
- dark/light khiến trạng thái nguy hiểm không đọc được;
- Vietnamese/English làm vỡ core layout;
- animation gây repeated severe jank ở core screens;
- protected screen quay lại được sau logout;
- empty/error/offline state thiếu ở core screen.

---

# 56. OUTPUT CUỐI CÙNG

Tạo:

`app/QA_AUDIT_REPORT.md`

và nên có:

```text
app/qa-evidence/
  screenshots/
  videos/
  logs/
  golden-diffs/
```

Report phải gồm:

1. Executive Summary
2. Commit SHA / Environment
3. Architecture Inventory
4. State Machines
5. Baseline Results
6. Functional Findings
7. Authentication / Ownership
8. Data Integrity
9. Charge / Smart Charger Safety
10. Trip / GPS
11. AI Findings
12. Offline / Sync / Retry
13. Security / Privacy
14. UI/UX Design System Audit
15. Screen-by-Screen UX Matrix
16. Responsive Results
17. Accessibility Results
18. Localization Results
19. Theme Results
20. Motion / Jank Results
21. Visual Regression Results
22. Performance / Memory
23. Confirmed Bugs
24. Regression Tests Added
25. Blocked Checks
26. Remaining Risks
27. Fix Plan
28. Release Recommendation

Release recommendation:

- `BLOCK RELEASE`
- `RELEASE WITH CONDITIONS`
- `READY FOR RELEASE`

---

# 57. EXECUTION PHASES

Không hỏi xác nhận sau từng phase.

### Phase 1 — Inventory & architecture
### Phase 2 — Baseline
### Phase 3 — Auth / ownership / malformed data
### Phase 4 — Battery / charge / trip state machines
### Phase 5 — Smart Charger safety
### Phase 6 — AI / prediction / fallback
### Phase 7 — Offline / sync / race / restart
### Phase 8 — UI/UX design-system audit
### Phase 9 — Screen-by-screen UI/UX QA
### Phase 10 — Responsive / localization / theme
### Phase 11 — Accessibility / reduced motion
### Phase 12 — Performance / memory / jank
### Phase 13 — Visual regression / integration tests
### Phase 14 — Regression test-first fixes proposal
### Phase 15 — Final report / release gate

Nếu bị block vì device/Firebase/test account/gateway:

ghi `BLOCKED`, lý do chính xác, rồi tiếp tục phần còn lại.

---

# 58. DEFINITION OF DONE

Audit APP chỉ hoàn tất khi:

- recursive inventory xong;
- commit SHA ghi lại;
- `flutter analyze` chạy;
- `flutter test` chạy;
- APK debug build chạy;
- auth/session test;
- User A/B isolation test;
- malformed Firestore test;
- battery invariants test;
- charge/trip state-machine test;
- retry/idempotency test;
- restart recovery test;
- Smart Charger safety/readback test;
- manual OFF priority test;
- AI invalid input/output/fallback test;
- offline UX test;
- every primary screen có state matrix;
- 320/360/375/412dp test;
- landscape test;
- light/dark test;
- VI/EN test;
- text scale test;
- keyboard test;
- TalkBack/semantics test;
- reduced motion audit;
- animation/jank profile;
- golden/screenshot regression cho core screens;
- protected navigation sau logout test;
- mọi P0/P1 có reproduction;
- confirmed bug có regression test nếu technically feasible;
- final report hoàn thành.

---

# 59. MỤC TIÊU THỰC SỰ

Không phải chứng minh app “chạy được”.

Phải tìm ra nơi mà:

- dữ liệu sai nhưng UI vẫn trông hợp lệ;
- thao tác retry tạo duplicate;
- state cũ overwrite state mới;
- AI fallback bị hiểu nhầm là AI chính thức;
- người dùng không thể OFF sạc đủ nhanh;
- UI báo thành công trước readback;
- offline data bị hiểu là live;
- accessibility user không thao tác được;
- layout chỉ đẹp trên một máy;
- animation làm app trông mượt nhưng logic sai;
- error/loading state khiến user không biết điều gì thực sự xảy ra.

**Chỉ được gọi APP READY khi cả logic, safety, security và UI/UX cùng đạt release gate.**
