# AI Chatbot Cá Nhân Hóa — Đặc Tả Kỹ Thuật & Kế Hoạch Triển Khai

> **Phiên bản**: v1.0.0 — 02/10/2026
> **Mục tiêu**: Nâng cấp BatteryBot từ FAQ cứng thành AI Chatbot thông minh, cá nhân hóa dựa trên hành vi người dùng, sử dụng Google Gemini API, tích hợp function calling, streaming response (SSE), feedback loop và lưu trữ hybrid (local + Firestore).

> **Đối chiếu triển khai 06/10/2026:** Các dấu `[x]` bên dưới là ghi nhận lịch sử, không chứng nhận nghiệm thu runtime. Xem Task 66 trong `PROJECT_STATUS.md` cho kết quả hiện hành. Đã sửa auth/UID isolation, SSE/error handling, dữ liệu giả và xác nhận lệnh giả; chưa nghiệm thu Gemini thật, dữ liệu lịch sử đa máy, retention/TTL thực tế hoặc adapter điều khiển sạc. Lưu chat local hiện dùng Secure Storage theo UID, chưa phải Hive/Isar. Văn bản Gemini được đệm để kiểm duyệt trước khi phát, chưa đạt streaming từng token như thiết kế. Nhập giọng nói chưa có recognizer thật và được vô hiệu hóa; chatbot không gửi lệnh relay.

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
