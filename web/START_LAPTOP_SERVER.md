# Chạy VinFast Battery Server trên laptop Windows với Tailscale Funnel

Tài liệu này chạy Dashboard, Flask API, AI runtime và vault Shelly trên laptop.
Tailscale Funnel công bố HTTPS từ laptop ra Internet mà không cần VPS, IP tĩnh,
Cloudflare hay mở port modem. Timer Shelly sau khi được arm vẫn nằm trên thiết bị.

## Điều kiện

- Docker Desktop đang chạy và dùng Linux containers.
- Tailscale đã đăng nhập trên laptop, MagicDNS và HTTPS certificates đã bật.
- Funnel được cấp quyền cho tailnet.
- Laptop có Internet, không sleep trong lúc cần web/API/AI.
- Firebase service account của đúng Firebase project.

Public URL có dạng `https://<ten-may>.<tailnet>.ts.net`. Tailscale Funnel không
hỗ trợ custom domain, do đó app phải được build với URL Tailscale thay vì
`api.evbattery.live`.

## 1. Tạo file secret local

Mở PowerShell tại thư mục `web`:

```powershell
Copy-Item .env.laptop.example .env.laptop
```

Tạo một khóa cho `SHELLY_PROFILE_MASTER_KEY`:

```powershell
$b = New-Object byte[] 32
$r = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$r.GetBytes($b)
$r.Dispose()
[Convert]::ToBase64String($b)
```

Điền kết quả vào `.env.laptop`. Tạo thêm hai giá trị Base64 độc lập cho
`AI_SERVER_INTERNAL_TOKEN` và `DEV_ADMIN_KEY`.

Tải Firebase service account JSON từ Firebase Console > Project settings >
Service accounts > Generate new private key. Minify JSON thành một dòng và đặt
vào `FIREBASE_CREDENTIALS_JSON`. File JSON này và `.env.laptop` là bí mật.

## 2. Chạy full stack local

```powershell
docker compose --env-file .env.laptop -f docker-compose.yml -f docker-compose.laptop.yml up -d --build ai api dashboard laptop_gateway
```

Kiểm tra gateway local:

```powershell
Invoke-WebRequest http://127.0.0.1:8080/api/health -UseBasicParsing
docker compose --env-file .env.laptop -f docker-compose.yml -f docker-compose.laptop.yml ps
```

`laptop_gateway` phục vụ Dashboard ở `/` và proxy mọi `/api/*` sang Flask.
Không mở cổng Docker ra mạng LAN/Internet.

## 3. Bật Tailscale Funnel

Mở PowerShell **Run as Administrator**:

```powershell
tailscale funnel --bg 8080
tailscale funnel status
```

Lệnh đầu có thể mở trình duyệt để bạn xác nhận quyền Funnel. Sau khi thành
công, Tailscale in public URL, ví dụ:

```text
https://khanhbes.tailaafca5.ts.net
```

Kiểm tra URL này trong trình duyệt và kiểm tra API:

```powershell
Invoke-WebRequest https://khanhbes.tailaafca5.ts.net/api/health -UseBasicParsing
```

## 4. Vận hành hằng ngày

Docker containers tự restart khi Docker Desktop chạy. Funnel chạy nền với
`--bg` và tự phục hồi sau reboot/Tailscale restart. Dừng server:

```powershell
docker compose --env-file .env.laptop -f docker-compose.yml -f docker-compose.laptop.yml stop ai api dashboard laptop_gateway
```

Laptop tắt, sleep, mất mạng hoặc Docker Desktop dừng thì web/API/AI/server-sync
không dùng được. Smart Charge đã xác minh timer Shelly vẫn tự tắt đúng hẹn.

## Khôi phục và an toàn

- Sao lưu `.env.laptop` trong password manager/USB mã hóa. Mất
  `SHELLY_PROFILE_MASTER_KEY` sẽ không giải mã được profile Shelly đã lưu.
- Không commit `.env.laptop` hoặc Firebase JSON.
- Không đặt Cloud key Shelly trong Firestore. Vault local chỉ trả secret sau
  khi API xác minh Firebase UID.
- Khi đổi laptop, chuyển `.env.laptop` bằng kênh mã hóa rồi khởi động cùng
  source/Docker; hoặc nhập lại profile Shelly trên điện thoại.

## Sự cố nhanh

- Funnel không public: chạy `tailscale funnel status`; kiểm tra MagicDNS, HTTPS
  certificates và quyền Funnel.
- Health local lỗi: xem `logs api`, `logs ai`, `logs dashboard` và
  `logs laptop_gateway`; AI phải healthy trước API.
- App báo unauthorized: kiểm tra service account JSON là của Firebase project
  đang dùng bởi app.
