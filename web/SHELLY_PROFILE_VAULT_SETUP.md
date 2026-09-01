# Shelly Profile Vault

Để bật đồng bộ cấu hình Shelly giữa web và Android, đặt biến môi trường
`SHELLY_PROFILE_MASTER_KEY` cho service API trước khi deploy. Giá trị phải là
32 byte mã hóa base64 URL-safe (không commit vào Git):

```powershell
$bytes = New-Object byte[] 32
[System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
[Convert]::ToBase64String($bytes)
```

Lưu giá trị vào file môi trường trên VPS, ví dụ:

```text
SHELLY_PROFILE_MASTER_KEY=<giá trị vừa sinh>
```

Sau đó redeploy `web/docker-compose.yml`. Không đổi khóa khi đang cần khôi
phục các cấu hình cũ; nếu đổi khóa, cần chạy migration/rotation có kiểm soát
trước để không làm mất khả năng giải mã vault hiện tại.
