# Chạy VinFast Battery Server trên laptop Windows

Tài liệu này chạy API Flask, AI runtime và vault Shelly ngay trên laptop. Nó
không thay đổi timer của Shelly: timer sau khi được arm vẫn nằm trên thiết bị.

## Điều kiện

- Docker Desktop đang chạy và dùng Linux containers.
- Laptop có Internet, không sleep trong lúc cần AI/sync.
- Bạn sở hữu domain `evbattery.live` và có thể đưa DNS của domain vào Cloudflare.
- Firebase service account của đúng Firebase project.

Cloudflare Tunnel là kết nối đi ra ngoài, vì vậy không mở port modem, không
forward port 5000 và không dùng IP công khai của laptop.

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

## 2. Tạo Cloudflare Tunnel

1. Đăng nhập Cloudflare, thêm zone `evbattery.live` và đổi nameserver tại nơi
   bạn mua domain sang hai nameserver Cloudflare cung cấp.
2. Mở **Zero Trust** > **Networks** > **Tunnels** > **Create a tunnel**.
3. Đặt tên `vinfast-laptop`, chọn Docker, sao chép tunnel token vào
   `CLOUDFLARE_TUNNEL_TOKEN` trong `.env.laptop`.
4. Trong tunnel vừa tạo, thêm Public Hostname:
   - Hostname: `api.evbattery.live`
   - Service type: `HTTP`
   - URL: `http://api:5000`

Tên `api` là tên service Docker nội bộ, không phải `localhost`. Không bật
Cloudflare Access cho hostname API vì app Android dùng Firebase Bearer token;
Access sẽ chặn app trước khi API có thể xác thực token.

## 3. Chạy server

Từ thư mục `web`:

```powershell
docker compose --env-file .env.laptop -f docker-compose.yml -f docker-compose.laptop.yml up -d --build ai api cloudflared
```

Kiểm tra local:

```powershell
Invoke-WebRequest http://127.0.0.1:5000/api/health -UseBasicParsing
docker compose --env-file .env.laptop -f docker-compose.yml -f docker-compose.laptop.yml ps
docker compose --env-file .env.laptop -f docker-compose.yml -f docker-compose.laptop.yml logs --tail=100 cloudflared
```

Khi tunnel báo `Connected`, kiểm tra public:

```powershell
Invoke-WebRequest https://api.evbattery.live/api/health -UseBasicParsing
```

Sau đó app giữ base URL `https://api.evbattery.live`; không cần build APK lại
chỉ để đổi IP server.

## Vận hành hằng ngày

Khởi động Docker Desktop rồi chạy lại lệnh `up` ở trên. Dừng server:

```powershell
docker compose --env-file .env.laptop -f docker-compose.yml -f docker-compose.laptop.yml stop ai api cloudflared
```

Laptop tắt, sleep, mất mạng hoặc Docker Desktop dừng thì API/AI/server-sync sẽ
không dùng được. Smart Charge đã xác minh timer Shelly vẫn tự tắt đúng hẹn.

## Khôi phục và an toàn

- Sao lưu `.env.laptop` trong password manager/USB mã hóa. Mất
  `SHELLY_PROFILE_MASTER_KEY` sẽ không giải mã được profile Shelly đã lưu.
- Không commit `.env.laptop`, Firebase JSON hoặc tunnel token.
- Không đặt Cloud key Shelly trong Firestore. Vault local chỉ trả secret sau
  khi API xác minh Firebase UID.
- Nếu cần đổi laptop, chuyển `.env.laptop` một cách mã hóa rồi khởi động cùng
  source/Docker; hoặc nhập lại profile Shelly trên điện thoại.

## Sự cố nhanh

- `cloudflared` không connected: kiểm tra Internet outbound TCP 443 và UDP/TCP
  7844, token tunnel và Public Hostname.
- Health local lỗi: xem `logs api` và `logs ai`; AI phải healthy trước API.
- Health public 1016/502: tunnel chưa connected hoặc service trong Cloudflare
  không phải `http://api:5000`.
- App báo unauthorized: kiểm tra service account JSON là của Firebase project
  đang dùng bởi app.
