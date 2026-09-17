# Báo cáo Đánh giá UI/UX & Motion Toàn diện — VinFast Battery App

- **Tiêu chuẩn thiết kế:** Premium Automotive Dark UI (tham chiếu: Mercedes Me, BMW My, Porsche Connect, Apple CarPlay, Linear)
- **Đối tượng mục tiêu:** Người dùng trẻ, am hiểu công nghệ (tech-savvy), yêu thích giao diện hiện đại, tinh tế và tốc độ
- **Nền tảng kiểm thử:** Android 16 (Flutter 3.29+), độ phân giải 1080×2424 (mật độ ~420dpi)
- **Phiên bản ứng dụng:** 1.1.3 (Build 4)
- **Tác giả:** Senior Principal UI/UX & Motion Designer

---

## 1. Tóm tắt Đánh giá Điều hành (Executive Summary)

Ứng dụng **VinFast Battery** sở hữu nền tảng ý tưởng tốt về quản lý năng lượng xe điện với linh vật BatteryBot, thẻ trạng thái Cockpit và tích hợp sạc thông minh Shelly. Tuy nhiên, khi đối chiếu với chuẩn mực **Premium Automotive** (sang trọng, tối giản, công nghệ cao, độ hoàn thiện tinh xảo), app hiện bộc lộ 3 nhược điểm cốt lõi:

1. **Trải nghiệm thiếu chiều sâu (Flat Black vs Layered Depth):** App lạm dụng màu đen tuyệt đối `#000000` làm nền phẳng kết hợp với các mảng xanh lá rực kiểu crypto/tiện ích tiêu dùng, thiếu đi hệ thống phân tầng vật liệu (surface levels, subtle radial dark gradients, border ánh kim mờ 1px) vốn là "ADN" của các app xe sang.
2. **Khoảng trống vô định (Unbalanced Whitespace & Empty States):** Các màn hình Onboarding và 2 tab cốt lõi (Sạc pin, Lịch sử) để thừa tới 40–75% diện tích màn hình là khoảng đen trống không, trong khi các trạng thái rỗng (Empty States) không hề có hình ảnh minh họa hay nút kêu gọi hành động (CTA).
3. **Trải nghiệm bàn phím & Tương tác lỗi thời:** Nút Submit bị bàn phím che khuất, trường nhập số điện thoại không mở bàn phím số, lỗi crash khi hiển thị popup, và các nhãn ngôn ngữ bị pha trộn tùy tiện giữa tiếng Anh và tiếng Việt.

---

## 2. Đánh giá Chi tiết theo 5 Nhóm Tiêu chí

---

### Nhóm 1: Bố cục & Phân cấp Thị giác (Layout & Visual Hierarchy)

#### 1.1. Màn hình Đăng nhập (Login Screen)
- **Vị trí:** Màn hình chính khi chưa đăng nhập.
- **Vấn đề:** 
  - Nền `#000000` thuần phẳng khiến khối nội dung trôi nổi không trọng tâm.
  - Quả cầu phát sáng (Glowing Orb) nằm lơ lửng, phía dưới có một đường kẻ ngang gradient xanh mảnh và một đường tương tự ở cuối trang gây cảm giác vụn vặt.
  - Thẻ thông báo offline "Mất kết nối Internet" chèn ngay trên đầu quả cầu tạo sự chật chội cục bộ ở nửa trên màn hình.
- **Vì sao chưa ổn:** Thiết kế xe hơi cao cấp cần sự đĩnh đạc, vững chãi (grounded). Hai đường kẻ gradient mảnh tách biệt tạo cảm giác "template web thập niên trước", làm loãng thị giác.
- **Đề xuất cải thiện:**
  - Nâng nền chính lên `#0B0E14` kết hợp một `RadialGradient` tinh tế phát ra từ tâm quả cầu: `colors: [Color(0x1A00E676), Colors.transparent], radius: 0.8`.
  - Bỏ hai đường kẻ ngang mảnh. Thay bằng khối card kính mờ (`BackdropFilter` với blur 16dp, bo góc 20dp, viền `Colors.white.withOpacity(0.08)`).
  - Nút "Quên mật khẩu?": Tăng touch target lên tối thiểu 48×48dp, chuyển màu sang bạc xám `#94A3B8` hover sáng xanh để đảm bảo độ tương phản WCAG AA.

#### 1.2. Onboarding Bước 1–8: Tỷ lệ bố cục & Linh vật BatteryBot
- **Vị trí:** Luồng thiết lập hồ sơ ban đầu.
- **Vấn đề:**
  - **Khoảng trống chết (Dead Space):** Từ bước 3 đến bước 7, khoảng cách giữa BatteryBot (ở 30% trên) và khung nhập liệu (ở 65% dưới) là một khoảng trống đen chiếm gần 40% chiều cao màn hình.
  - **Linh vật BatteryBot:** Thiết kế dạng robot hoạt hình phẳng với mắt ngôi sao mang phong cách game/app học tập (Duolingo), chưa toát lên vẻ công nghệ ô tô tinh vi (Sophisticated Telemetry AI).
  - **Hộp thoại (Speech bubble):** Là một hình chữ nhật bo góc đơn thuần, thiếu đuôi mũi tên (bubble tail) chỉ vào BatteryBot nên trông như một banner quảng cáo trôi nổi.
- **Vì sao chưa ổn:** Đối tượng tech-savvy cần cảm giác đang làm việc với một "AI Co-pilot" thông minh hơn là một nhân vật hoạt hình trẻ con. Khoảng trống quá lớn tạo cảm giác app chưa hoàn thiện nội dung.
- **Đề xuất cải thiện:**
  - **Bố cục:** Chuyển sang bố cục gắn kết: BatteryBot và Hộp thoại nằm trong một Hero Section liên hoàn, khung nhập liệu đẩy lên cách bot 24dp.
  - **Linh vật:** Nâng cấp visual của BatteryBot theo hướng Holographic HUD: viền phát sáng mỏng, có các vòng radar quét tròn mờ (scanning rings) xung quanh, mắt chuyển động dạng quét LED matrix thanh lịch.
  - **Hộp thoại:** Thêm tam giác pointer 8dp hướng xuống đầu robot; nền hộp thoại dùng `Color(0xFF131B26)` với border phát quang nhẹ `Color(0xFF00E676).withOpacity(0.3)`.

#### 1.3. Onboarding Bước 2: Danh sách chọn Xe
- **Vị trí:** Bước chọn dòng xe VinFast.
- **Vấn đề:**
  - Mỗi thẻ xe có một hình tròn đen to với duy nhất một chữ cái thô sơ: **E** (Evo), **F** (Feliz), **K** (Klara).
  - Hàng xe dưới cùng bị nút CTA "Tiếp tục" che mất một nửa mà không có hiệu ứng mờ (fade gradient) gợi ý cuộn.
- **Vì sao chưa ổn:** Người dùng xe điện rất tự hào về kiểu dáng chiếc xe của họ. Một chữ cái "E" hay "F" đặt trong vòng tròn xám trông giống như placeholder chưa tải xong ảnh hoặc lỗi đồ họa.
- **Đề xuất cải thiện:**
  - Thay chữ cái thô sơ bằng **Silhouette vector tối giản (bóng chiếu xe)** của từng dòng xe VinFast (Evo200, Feliz S, Klara S) màu trắng bạc với góc nghiêng 3/4 thể thao.
  - Khi một xe được chọn: Thẻ phóng to nhẹ (`scale: 1.02`), viền chuyển sang xanh Neon Emerald `#00E676`, nền có ánh sáng hắt từ dưới chân xe (underglow effect).
  - Bổ sung `ShaderMask` tạo gradient fade-out ở 32dp cuối danh sách cuộn trước khi chạm thanh nút bấm.

#### 1.4. Thiết kế Input "Hộp trong hộp" (Double-container clutter)
- **Vị trí:** Bước 3 (Biệt danh, ODO), Bước 4 (Ngày sinh).
- **Vấn đề:** Mỗi dòng nhập liệu gồm một khung bo góc lớn bọc ngoài, bên trái là một ô vuông bo góc chứa icon, bên phải là một ô bo góc con chứa `TextField`.
- **Vì sao chưa ổn:** Việc lồng 3 lớp hình chữ nhật bo góc (Card cha → Row container → Icon box + Textfield box) tạo ra quá nhiều đường kẻ thị giác (visual noise), làm giao diện nặng nề, bí bách.
- **Đề xuất cải thiện:**
  - Loại bỏ khung lồng bên trong. Áp dụng chuẩn Modern Input: 1 khung duy nhất bo góc 14dp, chiều cao 56dp. Icon nằm chìm trực tiếp bên trong làm `prefixIcon` (màu `#64748B`), text field chiếm trọn diện tích còn lại.

---

### Nhóm 2: Tương tác khi Bàn phím Xuất hiện (Keyboard Interaction)

#### 2.1. Mất dấu Nút Hành động Chính (Submit CTA Obscured)
- **Vị trí:** Màn hình Đăng ký (`RegisterScreen`) và các bước Onboarding có nhập liệu text.
- **Vấn đề:** Khi chạm vào trường nhập mật khẩu hoặc số điện thoại, bàn phím Android bung lên chiếm 48% màn hình. Toàn bộ nút "Đăng ký" và link "Đã có tài khoản? Đăng nhập" bị đẩy hoàn toàn xuống dưới mép bàn phím. Người dùng không biết đã điền đủ hay chưa và không có cách nào gửi form ngoài việc bấm phím Back để ẩn bàn phím.
- **Vì sao chưa ổn:** Vi phạm nguyên tắc công thái học di động (Mobile Usability Heuristic). Hành trình tạo tài khoản phải thông suốt, nút CTA cần luôn trong tầm mắt hoặc gắn liền với bàn phím.
- **Đề xuất cải thiện:**
  - Sử dụng bố cục `CustomScrollView` với `SliverFillRemaining(hasScrollBody: false)`.
  - Nút CTA gắn ở bottom sheet với cơ chế nổi trên bàn phím (`padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 16)`).
  - Đặt thuộc tính `textInputAction: TextInputAction.next` cho các trường trên và `TextInputAction.done` cho trường cuối cùng, tự động kích hoạt validate khi bấm Enter trên bàn phím.

#### 2.2. Sai loại Bàn phím trên trường Số điện thoại
- **Vị trí:** `RegisterScreen` và Onboarding Bước 4.
- **Vấn đề:** Trường "Số điện thoại" mở ra bàn phím chữ QWERTY đầy đủ, cho phép gõ cả ký tự chữ cái (ảnh bằng chứng hiển thị nhập được `"09QaT"`).
- **Vì sao chưa ổn:** Gây ức chế cho người dùng khi phải bấm nút đổi sang bàn phím số thủ công, tăng 80% nguy cơ gõ sai số điện thoại.
- **Đề xuất cải thiện:**
  - Cấu hình bắt buộc: `keyboardType: TextInputType.phone`.
  - Thêm `inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(11)]`.
  - Bổ sung auto-formatting hiển thị số điện thoại theo cụm: `0912 345 678` để người dùng dễ đối chiếu.

---

### Nhóm 3: Hiệu ứng 2D, Chuyển động & Trạng thái Phản hồi (Animation & Motion)

#### 3.1. Thiếu Easing Curve và Phản hồi Tương tác (Press States)
- **Vị trí:** Toàn bộ nút bấm chính (`ElevatedButton`) và các thẻ chọn xe.
- **Vấn đề:** Khi người dùng chạm ngón tay vào, nút chỉ có hiệu ứng ripple mặc định của Material mờ nhạt, không có phản hồi cơ học (tactile scale/press depth).
- **Vì sao chưa ổn:** App phong cách xe hơi thể thao cần mang lại cảm giác điều khiển chắc chắn, phản hồi nhanh nhạy như việc bấm nút vật lý trên bảng điều khiển xe.
- **Đề xuất cải thiện:**
  - Bọc các CTA và thẻ chính trong widget tương tác có hiệu ứng nhún nhẹ: khi nhấn giữ (`onTapDown`), scale co lại `0.97` trong `120ms` với `curve: Curves.easeOutCubic`; khi thả (`onTapUp`/`onTapCancel`), nảy lại `1.0` trong `180ms` với `Curves.elasticOut`.
  - Tích hợp rung haptic siêu nhẹ (`HapticFeedback.lightImpact()`) mỗi khi người dùng chọn một dòng xe, chọn mức pin slider hoặc bấm nút chuyển bước.

#### 3.2. Hiệu ứng Mực lỏng Năng lượng trên Dashboard
- **Vị trí:** Hero Card "VinFast EV" ở Tab 0.
- **Vấn đề:** Biểu tượng pin bên phải có hình trụ mực xanh lá dâng lên với các đường sóng lượn ngang. Dù có nỗ lực làm chuyển động, hiệu ứng sóng nước này tạo cảm giác giống bình chứa nước/bình lọc hơn là một khối pin lithium-ion thể rắn hiện đại.
- **Vì sao chưa ổn:** Pin xe điện là công nghệ điện hóa cao cấp, không chứa chất lỏng sóng sánh. Hiệu ứng này làm giảm tính chuyên nghiệp của giao diện cockpit xe điện.
- **Đề xuất cải thiện:**
  - Thay thế bằng **Vòng cung năng lượng Cybernetic (Circular HUD Arc)** hoặc **Mô hình Cell Pin 3D Isometric** với các vạch LED phân khúc (segmented LEDs) chạy ánh sáng xung mạch (pulse glow) khi đang sạc và sáng tĩnh sắc nét khi không sạc.

---

### Nhóm 4: Tính Nhất quán & Thẩm mỹ Tổng thể (Design System & Consistency)

#### 4.1. Không nhất quán Ngôn ngữ (Language Mixing)
- **Vị trí:** Xuất hiện xuyên suốt từ Onboarding đến Cockpit.
- **Bằng chứng cụ thể:**
  - Bước 1 Onboarding: Tag tiếng Anh `⚡ CELL PROTECTION`, `🧠 AI PREDICTION`, `🔌 SMART CHARGER` nhưng tiêu đề và mô tả bên dưới là tiếng Việt thuần túy.
  - Tab 0 Cockpit: Nút hành động ghi `Trip Planner`, `Service`, `Sync Now`, các thẻ đo lường ghi `CHARGE`, `RANGE KM`, `ODO KM`, trong khi tiêu đề tab là `Tổng quan`, banner thông báo là tiếng Việt.
  - Tab 3: Mục đầu tiên ghi `AI & Tính năng`, mục hai ghi `Trip Planner`, mục ba ghi `Bảo dưỡng`, mục bốn ghi `Cài đặt`.
- **Vì sao chưa ổn:** Việc trộn lẫn Anh - Việt không theo một quy chuẩn nào khiến app trông như một bản dịch dang dở, thiếu đi sự chỉn chu của một sản phẩm thương mại cao cấp.
- **Đề xuất cải thiện:**
  - Chuẩn hóa 100% tiếng Việt cho giao diện người dùng phổ thông (hoặc cung cấp nút chuyển ngôn ngữ Anh/Việt hoàn chỉnh trong Cài đặt).
  - Bảng quy đổi thuật ngữ nhất quán:
    - `Trip Planner` → **Lộ trình sạc**
    - `Service` → **Bảo dưỡng xe**
    - `Sync Now` → **Đồng bộ ngay**
    - `CHARGE` → **Mức pin** (kèm đơn vị %)
    - `RANGE KM` → **Quãng đường** (kèm km)
    - `ODO KM` → **Tổng ODO** (kèm km)

#### 4.2. Sai lệch Semantics của Icon đo lường
- **Vị trí:** Thẻ `ODO KM` ở hàng dưới Tab 0.
- **Vấn đề:** Thẻ Odometer (tổng quãng đường xe đã chạy) đang sử dụng icon chiếc đồng hồ tròn (`Icons.access_time` hoặc `schedule`).
- **Vì sao chưa ổn:** Đồng hồ đại diện cho thời gian (giờ/phút), trong khi ODO đo lường độ dài quãng đường (km). Biểu tượng này đánh lừa trực giác người dùng xe.
- **Đề xuất cải thiện:**
  - Đổi sang icon đồng hồ tốc độ xe (`Icons.speed_rounded`) hoặc biểu tượng làn đường / công-tơ-mét (`Icons.alt_route_rounded` / custom odometer icon).

#### 4.3. Bảng màu Nền và Độ tương phản (Dark Palette Levels)
- **Vị trí:** Toàn app.
- **Vấn đề:** Đang tồn tại sự nhảy màu nền thiếu kiểm soát:
  - Nền app: `#000000` (đen kịt).
  - Thẻ Cockpit: `#0A1B16` (xanh lục đen).
  - Thẻ Shelly: `#111A22` (xanh navy đen).
  - Thẻ Quick actions: `#15181E` (xám đen trung tính).
  - Nút bấm chính: `#00E676` hoặc `#10B981` (xanh neon chói).
- **Vì sao chưa ổn:** Việc sử dụng quá nhiều tone màu nền phụ (xanh lục, xanh dương, xám) trên cùng một màn hình khiến giao diện bị "chắp vá", không có một phong cách màu chủ đạo (brand identity).
- **Đề xuất bảng màu chuẩn Premium Automotive:**
  - **Base Background:** `#0A0C10` (Deep Obsidian — đen ánh kim sâu thẳm).
  - **Card Surface Level 1:** `#12161F` (Dark Steel).
  - **Card Surface Level 2 (Elevated/Hover):** `#1A202C`.
  - **Subtle Border:** `rgba(255, 255, 255, 0.07)` (viền sáng mảnh 1px phân tách các khối).
  - **Brand Accent:** `#00E599` (Electric Emerald — chỉ dùng điểm xuyết cho trạng thái pin, nút chính và giá trị quan trọng).
  - **Text Primary:** `#F8FAFC` (Trắng sáng).
  - **Text Secondary:** `#94A3B8` (Bạc ghi).
  - **Text Muted:** `#475569` (Xám tối).

---

### Nhóm 5: Trạng thái Đặc biệt, Trạng thái Rỗng & Vấn đề Kỹ thuật UI (Bugs & Empty States)

#### 5.1. Thảm họa Trạng thái Rỗng (Empty States) ở Tab 1 & Tab 2 [NGHIÊM TRỌNG]
- **Vị trí:** Tab 1 (Sạc pin) và Tab 2 (Lịch sử sạc).
- **Vấn đề:**
  - Tại Tab 1: Thanh AppBar trên cùng bị biến mất tiêu đề hoàn toàn (chỉ có chiếc chuông thông báo trơ trọi). Thân màn hình là một mảng đen trống rỗng 100% với một dòng chữ xám bé tí xíu: *"Hãy chọn xe để sử dụng Smart Charge"*.
  - Tại Tab 2: Tương tự, chỉ có dòng chữ: *"Hãy chọn xe để xem lịch sử sạc"*.
  - Người dùng không có bất kỳ nút nào để chọn xe, không có hướng dẫn cần làm gì tiếp theo, biến màn hình thành "ngõ cụt" (dead-end).
- **Vì sao chưa ổn:** Đây là lỗi trải nghiệm người dùng rất nặng. Nếu người dùng vừa cài app hoặc bị mất phiên kết nối xe, họ sẽ tưởng app bị treo hoặc hỏng dữ liệu.
- **Đề xuất cải thiện:**
  - Giữ nguyên tiêu đề rõ ràng trên AppBar: `"Sạc thông minh"` và `"Lịch sử sạc"`.
  - Xây dựng **Premium Empty State Component** bao gồm:
    1. Hình minh họa vector/lottie tinh xảo: Trụ sạc xe điện với đường phát quang mờ.
    2. Tiêu đề lớn: `"Chưa có xe nào được kích hoạt"`.
    3. Mô tả phụ: `"Kết nối xe VinFast của bạn để bật tính năng tự ngắt 80% và theo dõi lịch sử nạp năng lượng."`
    4. Nút bấm nổi bật (Primary Action Button): `[ + Chọn xe ngay ]` hoặc `[ Thêm xe mới ]`, khi bấm sẽ mở bottom sheet chọn xe lập tức.

#### 5.2. Lộ Chuỗi Exception Kỹ thuật ra Giao diện Người dùng [NGHIÊM TRỌNG]
- **Vị trí:** Banner đỏ trên cùng của Tab 0 khi không có mạng.
- **Vấn đề:** Ứng dụng in nguyên văn mã lỗi Dart/Firestore vào mặt người dùng:
  > *"TimeoutException after 0:00:08.000000: Không kết nối được Firestore (8s). Kiểm tra mạng hoặc thử lại."*
- **Vì sao chưa ổn:** Sản phẩm cao cấp tuyệt đối không bao giờ hiển thị biến số kỹ thuật, số micro giây hoặc tên thư viện backend (Firestore) cho khách hàng. Điều này làm mất niềm tin về độ bảo mật và tính chỉn chu của ứng dụng.
- **Đề xuất cải thiện:**
  - Lọc bỏ chuỗi exception gốc.
  - Hiển thị thông báo người dùng thân thiện:
    - **Tiêu đề:** `"Chế độ ngoại tuyến"`
    - **Mô tả:** `"Đang hiển thị dữ liệu đã lưu gần nhất. Một số tính năng điều khiển từ xa có thể bị gián đoạn."`
    - Có nút `"Thử kết nối lại"` với vòng quay spinner mượt mà.

#### 5.3. Màn hình Cài đặt / Khác quá sơ sài (Tab 3)
- **Vị trí:** Tab Cài đặt (Tab 3).
- **Vấn đề:** Màn hình chỉ có vỏn vẹn 4 dòng danh sách, 75% chiều cao còn lại bỏ trống. Không có thẻ thông tin tài khoản người dùng, không có avatar, không có số hiệu phiên bản ứng dụng, không có nút Đăng xuất.
- **Vì sao chưa ổn:** Màn hình cài đặt của app xe sang luôn là trung tâm cá nhân hóa (Personal Driver Hub), thể hiện đẳng cấp chủ xe.
- **Đề xuất cải thiện:**
  - Thêm **Profile Header Card** ở trên cùng: Avatar người dùng (hoặc chữ cái đầu cách điệu), Tên chủ xe, Số điện thoại, Huy hiệu hạng thành viên (VD: `VinFast Pioneer Member`).
  - Gom các mục cài đặt thành các nhóm Inset Grouped Cards (kiểu Apple iOS / Material 3) có bo góc 16dp:
    - Nhóm 1: Quản lý Phương tiện & Trạm sạc (Xe của tôi, Kết nối Shelly, Lịch sạc tự động).
    - Nhóm 2: Hệ thống & AI (Thông báo pin, AI dự báo, Tùy chỉnh Dashboard).
    - Nhóm 3: Hỗ trợ & Thông tin (Hướng dẫn sử dụng, Liên hệ cứu hộ pin 24/7, Phiên bản 1.1.3).
  - Nút "Đăng xuất" đặt ở cuối cùng với màu đỏ cảnh báo tinh tế.

---

## 3. Bảng Tổng hợp Vấn đề & Kế hoạch Ưu tiên Khắc phục

| Mã | Màn hình | Vấn đề phát hiện | Mức độ | Đề xuất hành động kỹ thuật cụ thể |
| :--- | :--- | :--- | :---: | :--- |
| **ISSUE-01** | Tab 1 & Tab 2 | Màn hình đen ngõ cụt khi chưa chọn xe, thiếu AppBar title ở Tab 1 | 🔴 **Nghiêm trọng** | Tạo `AppEmptyState` widget có illustration, tiêu đề, mô tả và nút CTA `[Chọn xe ngay]`. Khôi phục tiêu đề AppBar Tab 1 thành `"Sạc pin"`. |
| **ISSUE-02** | Tab 0 | Lộ chuỗi lỗi kỹ thuật `TimeoutException... Firestore (8s)` | 🔴 **Nghiêm trọng** | Viết hàm `UserFriendlyErrorMapper.map(error)` để làm sạch lỗi, chỉ hiển thị thông điệp thân thiện. |
| **ISSUE-03** | Register & Form | Nút Đăng ký / Submit bị bàn phím che khuất 100% | 🔴 **Nghiêm trọng** | Bọc layout trong `CustomScrollView` + `SliverFillRemaining`, ghim nút CTA nổi trên bàn phím bằng `viewInsets.bottom`. |
| **ISSUE-04** | Form nhập liệu | Trường Số điện thoại mở bàn phím chữ QWERTY, cho phép gõ chữ | 🟡 **Trung bình** | Thêm `keyboardType: TextInputType.phone` và `FilteringTextInputFormatter.digitsOnly`. |
| **ISSUE-05** | Onboarding 2 | Thẻ chọn dòng xe hiển thị chữ cái "E", "F", "K" thô sơ | 🟡 **Trung bình** | Thay thế bằng Silhouette vector bóng xe VinFast tối giản với góc chiếu 3/4 thể thao. |
| **ISSUE-06** | Toàn bộ app | Trộn lẫn tiếng Anh và tiếng Việt tùy tiện (`Trip Planner`, `Service`, `CHARGE`...) | 🟡 **Trung bình** | Chuẩn hóa toàn bộ nhãn sang tiếng Việt đồng bộ với hệ thống bản địa hóa `AppLocalizations`. |
| **ISSUE-07** | Onboarding 3–7 | Khoảng trống chết (Dead Space) chiếm 40% chiều cao màn hình | 🟡 **Trung bình** | Tái cấu trúc layout: nâng cụm nhập liệu lên gần mascot, thu hẹp padding dọc thừa. |
| **ISSUE-08** | Tab 0 | Thẻ ODO dùng nhầm icon đồng hồ thời gian (`Icons.access_time`) | 🟢 **Nhỏ** | Đổi sang `Icons.speed_rounded` hoặc `Icons.route_rounded`. |
| **ISSUE-09** | Tab 3 | Màn hình Cài đặt trống trải 75%, thiếu User Profile Card | 🟢 **Nhỏ** | Bổ sung thẻ Profile chủ xe ở đầu trang và gom danh mục theo Inset Grouped Cards. |
| **ISSUE-10** | Toàn bộ app | Nền đen tuyệt đối `#000000` thiếu chiều sâu vật liệu xe sang | 🟢 **Nhỏ** | Nâng nền lên `#0A0C10`, thêm viền mờ `1px rgba(255,255,255,0.07)` và hiệu ứng phát quang subtle glow. |

---

## 4. Lộ trình Triển khai Đề xuất (Next Steps)

Để nâng tầm giao diện ứng dụng đạt chuẩn **Premium Automotive**, quy trình cải tiến nên được chia thành 3 đợt:

- **Đợt 1 (Quick Wins & Nghiêm trọng - Khắc phục ngay):**
  1. Thay thế toàn bộ Empty States ở Tab 1 và Tab 2 bằng component đồ họa tương tác chuyên nghiệp.
  2. Bổ sung bộ lọc lỗi `UserFriendlyErrorMapper` cho toàn bộ các banner lỗi và popup.
  3. Sửa bàn phím số điện thoại và đảm bảo nút CTA luôn hiển thị khi mở bàn phím ảo.
  4. Chuẩn hóa 100% thuật ngữ Anh - Việt.
- **Đợt 2 (Cấu trúc & Hoàn thiện Thẩm mỹ):**
  1. Nâng cấp Onboarding: Tái cấu trúc khoảng cách màn hình, thay thế chữ cái "E/F/K" bằng Silhouette xe thể thao.
  2. Nâng cấp Tab 3 (Cài đặt): Thiết kế lại theo dạng Driver Profile Hub với thẻ thông tin tài khoản và danh mục nhóm tinh tế.
- **Đợt 3 (Motion Design & Premium Polish):**
  1. Bổ sung hiệu ứng nhún cơ học (Tactile Press Feedback) và rung haptic cho toàn bộ các nút bấm chính.
  2. Tinh chỉnh bảng màu nền Deep Obsidian `#0A0C10` với hệ thống viền ánh kim mờ sang trọng.
