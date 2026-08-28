# Local Smart Charger Gateway (legacy / diagnostic)

> Ứng dụng Android không còn phụ thuộc gateway này khi chạy. Luồng Sạc thông
> minh dùng Shelly Cloud trực tiếp và fallback qua LAN. Dịch vụ Python được giữ
> lại để chẩn đoán và thử nghiệm tương thích cũ.

FastAPI gateway giữa ứng dụng Flutter và Shelly Plug S Gen3. Gateway là nguồn
sự thật cho trạng thái relay và phiên sạc; ứng dụng không dùng timer nền để tự
ngắt điện.

## Cấu hình

```powershell
cd smart_charger_gateway
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
Copy-Item .env.example .env
```

Nạp các biến môi trường trong `.env` bằng process manager hoặc thiết lập trực
tiếp trước khi chạy:

- `SHELLY_IP`: IP tĩnh/DHCP reservation của Shelly trong LAN.
- `SMART_CHARGER_API_TOKEN`: token dài, ngẫu nhiên; bắt buộc cho status/control.
- `SMART_CHARGER_DB_PATH`: đường dẫn SQLite bền vững, cần backup định kỳ.
- `SMART_CHARGER_MAX_SESSION_MINUTES`: giới hạn an toàn tuyệt đối. Không có giá
  trị mặc định; chỉ điền sau khi xác nhận phần cứng và quy trình vận hành.
- `ENABLE_SMART_CHARGING=true`: bật API tạo phiên.
- `ENABLE_AUTOMATIC_CUTOFF=false`: mặc định không cho scheduler tự OFF.
- `SMART_CHARGER_SHADOW_MODE=true`: chỉ ghi `would_have_turned_off_at`, không tự
  OFF. Nút OFF thủ công vẫn hoạt động.

Chạy gateway:

```powershell
.\.venv\Scripts\python.exe -m uvicorn main:app --host 0.0.0.0 --port 8000
```

Thiết bị chạy gateway phải luôn bật, không sleep, dùng UTC chính xác và cùng
trusted LAN với Shelly. Không forward cổng 8000 hoặc Shelly ra Internet.

App không cần `SMART_CHARGER_API_BASE_URL`. Hồ sơ Cloud/LAN được nhập trong
wizard **Kết nối Shelly** và lưu bằng secure storage.

## Safety rollout

Production giữ `SMART_CHARGER_SHADOW_MODE=true` và
`ENABLE_AUTOMATIC_CUTOFF=false` cho đến khi hoàn tất shadow run, test mất mạng,
restart, relay readback, charging curve và kiểm chứng giới hạn phần cứng trên xe
thật. SOC là giá trị ước tính (`~`), không phải dữ liệu BMS và không được dùng
đơn độc để cắt relay.

## API

Legacy Step 8 vẫn được giữ: `GET /api/charger/status`, `POST /api/charger/on`,
`POST /api/charger/off`, `POST /api/charging/session` (monitor-only), và
`GET /api/charging/session/current`.

Step 9 bổ sung:

- `POST /api/charging/session/start` (`Idempotency-Key` bắt buộc)
- `GET/PATCH /api/charging/session/{id}`
- `POST /api/charging/session/{id}/stop`
- `GET /api/charging/sessions?limit=20`

Mọi endpoint charger/session yêu cầu `Authorization: Bearer <token>`. Lỗi có
schema ổn định `{ "error": { "code", "message", "retryable", "session_id" } }`.

## Kiểm thử

```powershell
python -m pytest tests -q
```
