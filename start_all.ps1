# ═══════════════════════════════════════════════════════════════
# VinFast Battery — Start All Services
# Admin Portal (React) → http://localhost:3000
# Unified API          → http://localhost:5000
# ═══════════════════════════════════════════════════════════════

$root = $PSScriptRoot
if (-not $root) { $root = Get-Location }

# Python executable (ưu tiên venv, fallback python global)
$pythonExe = Join-Path $root ".venv\Scripts\python.exe"
if (-not (Test-Path $pythonExe)) {
    $pythonExe = "python"
    Write-Host "⚠ Không tìm thấy .venv\\Scripts\\python.exe, dùng python từ PATH." -ForegroundColor Yellow
}

function Test-PortListening {
    param([int]$Port)
    return [bool](Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
}

function Wait-ForPort {
    param(
        [int]$Port,
        [int]$TimeoutSec = 60
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        if (Test-PortListening -Port $Port) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return $false
}

Write-Host ""
Write-Host "⚡ VinFast Battery — Starting all services..." -ForegroundColor Green
Write-Host ""

# Detect Firebase service account key (optional but recommended)
$serviceAccountCandidates = @(
    (Join-Path $root "serviceAccountKey.json"),
    (Join-Path $root "service-account-key.json"),
    (Join-Path $root "firebase-adminsdk.json"),
    (Join-Path $root "firebase-service-account.json"),
    (Join-Path $root "secrets\serviceAccountKey.json")
)
$serviceAccountPath = $null
foreach ($c in $serviceAccountCandidates) {
    if (Test-Path $c) {
        $serviceAccountPath = $c
        break
    }
}

# Fallback: auto-detect file theo pattern Firebase Admin SDK
if (-not $serviceAccountPath) {
    $patternCandidates = @(
        (Get-ChildItem -Path $root -File -Filter "*firebase-adminsdk*.json" -ErrorAction SilentlyContinue),
        (Get-ChildItem -Path $root -File -Filter "*service*account*.json" -ErrorAction SilentlyContinue),
        (Get-ChildItem -Path (Join-Path $root "secrets") -File -Filter "*firebase-adminsdk*.json" -ErrorAction SilentlyContinue),
        (Get-ChildItem -Path (Join-Path $root "secrets") -File -Filter "*service*account*.json" -ErrorAction SilentlyContinue)
    )
    foreach ($group in $patternCandidates) {
        if ($group -and $group.Count -gt 0) {
            $serviceAccountPath = $group[0].FullName
            break
        }
    }
}

# 1) Unified API (port 5000) — replaces app.py + ai_api.py
$apiCmd = "cd /d `"$root`" && "

# Admin bootstrap for local dev:
# - Nếu chưa set ADMIN_EMAILS thì mặc định "*" (mọi user đăng nhập đều là admin)
# - Muốn siết quyền: set biến môi trường ADMIN_EMAILS="email1,email2"
$adminEmails = $env:ADMIN_EMAILS
if ([string]::IsNullOrWhiteSpace($adminEmails)) {
    $adminEmails = "*"
    Write-Host "🛡 ADMIN_EMAILS chưa cấu hình -> dùng local bootstrap ADMIN_EMAILS=* (mọi tài khoản đăng nhập là admin)." -ForegroundColor Yellow
} else {
    Write-Host "🛡 ADMIN_EMAILS=$adminEmails" -ForegroundColor DarkGreen
}
$apiCmd += "set `"ADMIN_EMAILS=$adminEmails`" && "

if ($serviceAccountPath) {
    $apiCmd += "set `"GOOGLE_APPLICATION_CREDENTIALS=$serviceAccountPath`" && "
    Write-Host "🔐 Firebase credential → $serviceAccountPath" -ForegroundColor DarkGreen
} else {
    Write-Host "⚠ Không tìm thấy service account key. API sẽ chạy in-memory fallback." -ForegroundColor Yellow
}
$apiCmd += "set `"FLASK_USE_RELOADER=0`" && `"$pythonExe`" server.py"

$api = Start-Process cmd -ArgumentList "/k", $apiCmd -PassThru
Write-Host "🌐 Unified API      → http://localhost:5000  (PID $($api.Id))" -ForegroundColor Cyan

# 2) Admin Portal React (port 3000) — use cmd.exe to bypass PowerShell execution policy
$dashCmd = "cd /d `"$root\dashboard`" && if not exist node_modules (npm install || exit /b 1) && npm run dev -- --host 127.0.0.1 --port 3000 --strictPort"
$dash = Start-Process cmd -ArgumentList "/k", $dashCmd -PassThru
Write-Host "📊 Admin Portal     → http://localhost:3000  (PID $($dash.Id))" -ForegroundColor Cyan

# Wait for services to be ready
$apiReady = Wait-ForPort -Port 5000 -TimeoutSec 25
$dashReady = Wait-ForPort -Port 3000 -TimeoutSec 120

Write-Host ""
if ($apiReady -and $dashReady) {
    Write-Host "✅ All services started and ready." -ForegroundColor Green
} elseif ($apiReady -and -not $dashReady) {
    Write-Host "⚠ API đã sẵn sàng nhưng Dashboard chưa mở cổng 3000." -ForegroundColor Yellow
    Write-Host "   Kiểm tra cửa sổ 'Admin Portal' để xem lỗi npm/vite." -ForegroundColor Yellow
} elseif (-not $apiReady -and $dashReady) {
    Write-Host "⚠ Dashboard đã sẵn sàng nhưng API chưa mở cổng 5000." -ForegroundColor Yellow
    Write-Host "   Kiểm tra cửa sổ 'Unified API' để xem lỗi Python/Flask." -ForegroundColor Yellow
} else {
    Write-Host "⚠ Cả API và Dashboard chưa sẵn sàng trong thời gian chờ." -ForegroundColor Yellow
    Write-Host "   Kiểm tra 2 cửa sổ process để xem lỗi chi tiết." -ForegroundColor Yellow
}
Write-Host "   Or run: Stop-Process -Id $($api.Id),$($dash.Id)" -ForegroundColor DarkGray
Write-Host "   Lưu ý: Không cần chạy python server.py thêm lần nữa sau khi start_all.ps1." -ForegroundColor DarkGray
Write-Host ""
