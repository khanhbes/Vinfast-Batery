# BatteryBot AI Copilot — Technical Specification

> **Đặc tả Kỹ thuật Hệ thống Trợ lý Ảo Thông minh BatteryBot**: Mô tả kiến trúc UI/UX, cơ chế ngữ cảnh proactive, mô hình hybrid AI và quy chuẩn an toàn khi thực thi tác vụ trên hệ sinh thái VinFast Battery.

---

## 1. Tổng Quan & Kiến Trúc Hybrid Brain

BatteryBot được thiết kế theo mô hình **Hybrid Brain (Trí tuệ Lai)** nhằm cân bằng tối ưu giữa tốc độ phản xạ tức thì trên thiết bị và chiều sâu tri thức của mô hình ngôn ngữ lớn:

```text
                                       ┌──────────────────────────────────────────────┐
                                       │              CLIENT LAYER (Flutter)          │
                                       │  - Floating BatteryBot Mascot (Draggable)    │
                                       │  - Context Engine (SoC, ODO, Screen, Time)   │
                                       │  - Proactive Speech Bubble Manager           │
                                       │  - Glassmorphic Interactive Sheet (~60% UI)  │
                                       └──────────────────────┬───────────────────────┘
                                                              │
                                            HTTPS / SSE Stream│ (Bearer Auth Token)
                                                              ▼
                                       ┌──────────────────────────────────────────────┐
                                       │            BACKEND COPILOT SERVICE           │
                                       │         (web/ai_server/chat_copilot.py)      │
                                       │  - Open LLM (Qwen 2.5-7B / Llama 3.1-8B)     │
                                       │  - RAG Engine (Specs, Shelly Hardware, FAQs) │
                                       │  - Tool / Function Calling Engine            │
                                       └──────────────────────┬───────────────────────┘
                                                              │
                                            Internal RPC / API│
                                                              ▼
                                       ┌──────────────────────────────────────────────┐
                                       │       SAFETY GUARD & ACTION DISPATCHER       │
                                       │  - Smart Charger Gateway (Port 8002)         │
                                       │  - Human-in-the-Loop Action Confirmation     │
                                       │  - Watchdog Giám sát 12A / 2500W             │
                                       └──────────────────────────────────────────────┘
```

---

## 2. Đặc Tả Giao Diện & Tương Tác (UI/UX)

### 2.1. Floating Mascot & Bong Bóng Ngữ Cảnh (Proactive Bubble)
- **Vị trí & Neo (Anchor)**:
  - Nằm ở góc dưới bên phải màn hình (cách mép phải 16dp, mép dưới 96dp — nằm ngay trên Bottom Navigation Bar).
  - **Draggable**: Cho phép người dùng kéo nhẹ sang góc đối diện nếu bị che nội dung, tự động hít vào mép màn hình gần nhất.
- **Tự ẩn thông minh (Smart Hide)**:
  - Khi cuộn nhanh xuống dưới (`ScrollDirection.reverse`) -> mascot tự động trượt thu nhỏ vào mép.
  - Khi bàn phím ảo mở (`MediaQuery.viewInsets.bottom > 0`) -> tự ẩn để không che khuất form nhập liệu.
- **Bong bóng thoại chủ động (Proactive Speech Bubble)**:
  - Tự động xuất hiện kèm hiệu ứng nảy nhẹ khi Context Engine phát hiện sự kiện đáng chú ý.
  - Tự động mờ dần và biến mất sau **6 giây** nếu người dùng không chạm vào.
  - Tần suất giới hạn: Tối đa 1 thông điệp chủ động trong mỗi chu kỳ **30 phút** để tránh làm phiền.

### 2.2. Interactive Assistant Sheet (Glassmorphic Drawer)
- Chạm vào Mascot hoặc bóng bóng thoại sẽ mở một **Modal Bottom Sheet**:
  - Chiều cao ban đầu: **60% chiều cao màn hình** (người dùng vừa tương tác với Bot, vừa quan sát được bối cảnh app phía trên).
  - Có thể vuốt lên để mở rộng toàn màn hình (**95%**).
- **Thành phần bên trong Sheet**:
  - **Header**: Mascot cử động mini, tên xe đang kích hoạt và chỉ số SoC/SoH rút gọn.
  - **Quick Action Chips**: Danh sách 3-4 phím tắt ngữ cảnh gợi ý theo trạng thái xe hiện tại.
  - **Chat Message Stream**: Bong bóng tin nhắn người dùng và Bot, hỗ trợ Markdown và các Thẻ trực quan (Rich Action Cards).
  - **Input Bar**: Ô nhập văn bản hỗ trợ micro nhận diện giọng nói và nút gửi.

---

## 3. Context Engine: Ma Trận Đoán Ý Ngữ Cảnh

Context Engine chạy liên tục trên client thông qua Riverpod state listeners (`vehicleProvider`, `batteryMonitorProvider`, `currentTabProvider`):

| Sự kiện / Ngữ cảnh | Điều kiện kích hoạt | Biểu cảm Mascot | Lời thoại bong bóng | Hành động đề xuất (Action Chips) |
|---|---|---|---|---|
| **Chào buổi sáng** | Mở app từ 06:00 đến 08:30 | `greeting` | *"Chào buổi sáng! Pin xe đang ở mức %d%%, sẵn sàng cho ngày mới rồi nhé!"* | `[Lộ trình hôm nay]` `[Kiểm tra trạm sạc]` |
| **Cảnh báo pin thấp** | SoC xe < 20% khi mở app | `thinking` | *"Pin xe chỉ còn %d%% (~%d km). Bạn có muốn hẹn lịch sạc tối ưu không?"* | `[Bật sạc ngay]` `[Hẹn giờ đêm]` |
| **Tại tab Smart Charger** | Đã kết nối Shelly nhưng relay đang OFF | `charging` | *"Bộ sạc thông minh đã sẵn sàng. Bạn muốn sạc đến mốc nào (khuyến nghị 80%)?"* | `[Sạc an toàn 80%]` `[Sạc đầy 100%]` |
| **Sau chuyến đi dài** | Vừa kết thúc chuyến đi GPS > 20 km | `happy` | *"Chuyến đi vừa qua tiêu thụ %.1f Wh/km. Bạn có muốn lưu vào lịch sử học AI không?"* | `[Xem tiêu thụ Wh/km]` `[Bỏ qua]` |
| **Nhắc bảo dưỡng** | ODO sắp chạm mốc 5.000 / 10.000 km | `idle` | *"Xe của bạn sắp tới kỳ bảo dưỡng xích và phanh (%d km). Cần đặt lịch nhắc không?"* | `[Xem danh mục bảo dưỡng]` `[Nhắc sau]` |
| **Cảnh báo sự cố sạc** | Quá dòng (>12A) hoặc mất kết nối | `thinking` | *"Cảnh báo: Bộ sạc tự ngắt an toàn do dòng điện vượt ngưỡng. Chạm để xem chi tiết!"* | `[Chẩn đoán lỗi]` `[Cẩm nang an toàn]` |

---

## 4. Công Nghệ Trí Tuệ Nhân Tạo (Open LLM & RAG)

### 4.1. Lựa chọn Mô hình LLM Mở
- **Model đề xuất**: **Qwen 2.5 (7B/14B Instruct)** hoặc **Llama 3.1 (8B Instruct)**.
- **Tối ưu hóa**: Lượng tử hóa 4-bit (AWQ / GGUF) triển khai qua `vLLM` hoặc `Ollama` trên AI Service (`web/ai_server/`).
- **Tốc độ phản hồi**: Thời gian sinh token đầu tiên (TTFT) < 600ms; truyền dữ liệu qua Server-Sent Events (SSE).

### 4.2. RAG (Retrieval-Augmented Generation) & Knowledge Base
Cơ sở tri thức nạp vào Vector Database (ChromaDB / FAISS) bao gồm:
1. **Catalog xe VinFast**: Thông số kỹ thuật pin, dung lượng danh định Wh, dòng sạc khuyến nghị (từ `web/vehicle_catalog.py`).
2. **Cẩm nang phần cứng sạc thông minh**: Hướng dẫn đấu nối Shelly Plug S Gen3, an toàn điện gia dụng 12A/2500W, cơ chế phục hồi IP (từ `SMART_CHARGE_SETUP_GUIDE.md` và `docs/specs/`).
3. **Quy chuẩn Telemetry & Chẩn đoán**: Schema dữ liệu pin v1, mã lỗi phần cứng và cách khắc phục.

---

## 5. Quy Chuẩn An Toàn: Human-in-the-Loop Action Execution

Tuyệt đối tuân thủ tiêu chuẩn an toàn IoT: **Mô hình AI không bao giờ được phép trực tiếp gửi lệnh đóng relay sạc mà không có sự đồng ý của con người.**

```text
LLM đề xuất hành động ──► Tạo Action Confirmation Card trên Chat ──► Người dùng bấm "XÁC NHẬN"
                                                                            │
                                                                            ▼
                                                            Backend thẩm định Lease & Safety
                                                                            │
                                                                            ▼
                                                            Gửi lệnh bật sạc kèm Timer Watchdog
```

1. **Thẻ xác nhận hành động (Action Confirmation Card)**:
   - Hiển thị rõ: Tên tác vụ (*"Bật sạc đến 80%"*), Công suất giới hạn (*12A / 2500W*), Thời gian tự ngắt dự kiến.
   - Có 2 nút bấm vật lý: **`[ HỦY ]`** và **`[ XÁC NHẬN BẬT SẠC ]`**.
2. **Xác thực Backend**:
   - Khi người dùng bấm Xác nhận, request gửi lên endpoint `/api/smart-charging/execute` kèm chữ ký hành động và kiểm tra tính hợp lệ của phiên sạc trước khi đóng relay.
