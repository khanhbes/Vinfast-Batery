# Battery telemetry schema v1

Mọi telemetry mới được ghi theo `schemaVersion: "battery-telemetry/v1"`. Dữ liệu cũ
vẫn được giữ nguyên các trường gốc; cấu trúc mới nằm trong `measurements`.

```json
{
  "schemaVersion": "battery-telemetry/v1",
  "vehicleId": "VF-001",
  "chargerId": "shelly-plus-1pm-01",
  "chargingSessionId": "session-20260905-001",
  "recordedAt": "2026-09-04T10:30:00Z",
  "measurements": {
    "soc": {
      "value": 68.5,
      "unit": "%",
      "source": "ai_estimate",
      "confidence": 0.82,
      "measuredAt": "2026-09-04T10:30:00Z",
      "modelVersion": "soc-v3"
    },
    "power": {
      "value": 2300,
      "unit": "W",
      "source": "shelly_meter",
      "confidence": 0.98,
      "measuredAt": "2026-09-04T10:30:00Z"
    }
  }
}
```

## Quy ước

- Chỉ số hỗ trợ: `soc`, `soh` (`%`); `voltage` (`V`); `power` (`W`); `energy` (`Wh`).
- `source`: `manual_entry`, `shelly_meter`, `bms`, hoặc `ai_estimate`.
- `confidence` luôn thuộc `[0, 1]`; mặc định là `1.0` nhập tay/BMS, `0.98` Shelly,
  `0.7` AI. AI luôn nhận thêm `modelVersion` (`unknown` nếu hệ thống không cung cấp).
- API tự đổi `kW` → `W` và `kWh` → `Wh`; các đơn vị khác bị từ chối.
- `measuredAt` bắt buộc là ISO-8601 có timezone. Tất cả được lưu UTC dạng `Z`.
- `vehicleId` là bắt buộc. `chargerId` và `chargingSessionId` là tùy chọn nhưng nên có
  khi dữ liệu thuộc một phiên sạc.

## Ghi dữ liệu

`POST /api/telemetry` yêu cầu Firebase Bearer token (hoặc khóa admin trong môi trường
phát triển), lưu vào `TelemetryPoints`. Endpoint tương thích cũ
`POST /api/web/sync/battery-state` vẫn ghi `battery_states`, nhưng tự thêm envelope v1.

Ví dụ Shelly có thể gửi trực tiếp `powerW` và `energyWh`. Payload cũ dùng `kW`/`kWh`
vẫn được chấp nhận và tự chuyển đổi sang đơn vị chuẩn.

## Đồng bộ Flutter và dashboard

Flutter gửi battery state/trip data qua API; API chuẩn hóa telemetry rồi ghi Firestore,
dashboard đọc cùng nguồn dữ liệu. Không dùng `localhost` từ điện thoại: bản phát hành
phải dùng URL Tailscale Funnel `https://khanhbes.tailaafca5.ts.net`.
