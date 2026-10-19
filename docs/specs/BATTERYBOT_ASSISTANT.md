# BatteryBot — Đặc tả hiện hành (v2)

> Gộp ngày 19/10/2026 (QA 131) từ `BATTERYBOT_ASSISTANT.md` (bản thiết kế Qwen/RAG cũ) và `AI_CHATBOT_PERSONALIZATION.md` (Gemini/SSE + ai_server chat, Tasks 93–105). Hai thiết kế cũ đã không còn chạy; mã chatbot cũ trong `web/ai_server` (chat_engine, chat_tools, chat_memory, behavior_analyzer, suggestion_engine, chat_schemas, chat_guardrails, personality_adapter) và các route proxy `/api/chat/*`, `/api/behavior/*` đã gỡ. Lịch sử chi tiết nằm trong git và `PROJECT_STATUS.md` (Tasks 93–105, 124).

## 1. Luồng chính

```text
App (BatteryBot sheet)
  └─ HybridAssistantEngine
       ├─ có mạng + còn lượt → POST /api/assistant/chat  (Flask, web/assistant/)
       │      └─ Gemini (GEMINI_CHAT_MODEL) qua relay APIM Japan East (GEMINI_RELAY_URL, X-Relay-Token)
       └─ mất mạng / hết lượt / lỗi → BatteryBotLocalEngine (FAQ + công cụ trên máy)
```

- Gemini chặn Azure East Asia, nên API gọi qua relay APIM (`deploy/azure/gemini-relay-apim.bicep`); khóa Gemini chỉ nằm trong named value của APIM. `web/gemini_relay/` + `Dockerfile.gemini-relay` là relay dạng container, giữ để dùng khi có subscription khác.
- Gemini 3 bắt buộc gửi lại `thoughtSignature` giữa các lượt.
- Quota: 50 tin/ngày/tài khoản (Azure Table, `web/assistant/quota.py`).

## 2. Mã nguồn

| Phần | File |
| --- | --- |
| Route Flask | `web/assistant/routes.py` (`/api/assistant/chat`, bộ nhớ, cài đặt học) |
| Prompt, công cụ, kiểm tra hành động | `web/assistant/engine.py` (`CLIENT_ACTIONS`, `SERVER_TOOLS`, `validate_action`, `describe_action`) |
| Gemini REST / relay | `web/assistant/gemini.py` |
| Kiến thức app | `web/assistant/knowledge.py` + Firestore `assistantKnowledge` (sửa ở dashboard `/assistant`) |
| Bộ nhớ | `web/assistant/memory.py` → `users/{uid}/assistantMemory`, `assistant/settings.learningEnabled` |
| Lộ trình | `web/assistant/trip_model.py` ↔ `app/lib/data/services/trip_energy_model.dart` (vector chung) |
| App | `app/lib/features/ai/assistant_sheet.dart`, `services/hybrid_assistant_engine.dart`, `services/app_chat_tool_gateway.dart`, `widgets/action_confirmation_card.dart` |

## 3. Công cụ

- **Máy chủ tự chạy (chỉ đọc / ước tính):** `get_charger_status`, `get_charging_history`, `get_charging_habits`, `get_charging_summary`, `search_app_help`, `remember`, `forget`, `estimate_trip` (OSRM/Nominatim thật), `estimate_charge` (mô hình đã học của xe).
- **Hành động trên app:** `navigate` chạy ngay; `prepare_target_charging`, `plan_trip` mở màn đã điền sẵn; pin/ODO/xe/mục tiêu/giá điện/nhắc lịch/`set_app_setting` (chỉ bật/tắt thông báo đẩy) là thẻ một chạm có "hoàn tác".
- **Bật/tắt sạc:** `start_timed_charging`, `stop_charging` luôn đi qua `BatteryBotLocalEngine` + gateway đã xác minh. Bật cần thao tác xác nhận theo Cài đặt → Giao diện (mặc định vuốt; giữ 1 giây hoặc bấm 1 lần nếu chủ xe chọn — `ChargeConfirmControl`). Dừng là nút thường. Máy chủ từ chối (403/404/409) → báo rõ, không gửi lại ON.

## 4. Bộ nhớ và riêng tư

- Chỉ lưu sự thật ngắn người dùng tự nói (không mật khẩu, số tài khoản); không lưu transcript. Màn "BatteryBot đang nhớ gì" cho xem/xóa; tắt học bằng `learningEnabled`.
- Lịch sử chat và hành vi chỉ ở trên máy (`ChatApiService`, `SuggestionService`, `BehaviorSyncService` chạy `localOnly`).

## 5. Giao diện

- Nút BatteryBot nổi ở góc phải, tự thu vào mép sau 6 giây đứng yên, hiện lại khi cuộn lên, có bong bóng hoặc chạm (`AssistantContextCoordinator`). Chỉ chuyển động khi có hoạt động thật.
- Gợi ý chủ động: luật trên máy, tối đa 1 bong bóng/30 phút và 5/ngày, bỏ qua thì ẩn 24 giờ.
- Nút camera trong ô nhập: quét đồng hồ xe (`scanDashboard`) rồi điền "Đồng hồ xe đang báo …" để người dùng kiểm và gửi.
- Thẻ xác nhận: champagne khi chờ, rose khi không thực hiện, emerald khi đã xác minh.

## 6. Kiểm thử

- Backend: `web/tests/test_assistant.py`, `test_gemini_relay.py`, `test_qa129_fixes.py`.
- App: `test/unit/hybrid_assistant_engine_test.dart`, `batterybot_local_engine_test.dart`, `chat_shelly_backend_integration_test.dart`, `chat_reminder_integration_test.dart`.
