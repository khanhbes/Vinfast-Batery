# ═══════════════════════════════════════════════════════════════
# VinFast Battery — Start All Services
# Admin Portal (React) → http://localhost:3000
# Unified API  (Flask)  → http://localhost:5000
# AI Server    (FastAPI)→ http://localhost:8001 (internal)
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
    $out = netstat -ano 2>$null | Select-String "LISTENING" | Select-String ":$Port "
    return [bool]$out
}

function Stop-PortProcess {
    param([int]$Port)
    try {
        $lines = netstat -ano 2>$null | Select-String "LISTENING" | Select-String ":$Port "
        if (-not $lines) { return }
        foreach ($line in $lines) {
            $parts = ($line -replace '\s+', ' ').ToString().Trim().Split(' ')
            $ownerPid = [int]$parts[-1]
            if ($ownerPid -and $ownerPid -ne 0 -and $ownerPid -ne $PID) {
                try {
                    Stop-Process -Id $ownerPid -Force -ErrorAction SilentlyContinue
                    Write-Host "`n  Freed port $Port (killed PID $ownerPid)" -ForegroundColor DarkYellow
                } catch {}
            }
        }
    } catch {}
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

# Auto cleanup ports để tránh lỗi web/api không chạy do cổng bận
Write-Host "🧹 Checking ports..." -ForegroundColor DarkGray -NoNewline
try {
    Stop-PortProcess -Port 5000
    Stop-PortProcess -Port 3000
    Stop-PortProcess -Port 8001
    Write-Host " done." -ForegroundColor DarkGray
} catch {
    Write-Host " skipped (permission issue)." -ForegroundColor Yellow
}

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

# 0) AI Server FastAPI (port 8001) — hot-swappable SOC pipeline
$aiToken = $env:AI_SERVER_INTERNAL_TOKEN
if ([string]::IsNullOrWhiteSpace($aiToken)) { $aiToken = "dev-local-token" }

$aiCmd = "cd /d `"$root`" && set `"AI_SERVER_INTERNAL_TOKEN=$aiToken`" && `"$pythonExe`" -m uvicorn ai_server.main:app --host 127.0.0.1 --port 8001"
$aiProc = Start-Process cmd -ArgumentList "/k", $aiCmd -PassThru
Write-Host "🧠 AI Server        → http://127.0.0.1:8001  (PID $($aiProc.Id))" -ForegroundColor Cyan

# 1) Unified API (port 5000) — replaces app.py + ai_api.py
$apiCmd = "cd /d `"$root`" && set `"AI_SERVER_URL=http://127.0.0.1:8001`" && set `"AI_SERVER_INTERNAL_TOKEN=$aiToken`" && "

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

# 2) Admin Portal React (port 3000)
$dashDir = Join-Path $root "dashboard"
$npmCmd = Join-Path ${env:ProgramFiles} "nodejs\npm.cmd"
if (-not (Test-Path $npmCmd)) {
    $npmCmd = "npm.cmd"
}

if (-not (Test-Path (Join-Path $dashDir "node_modules"))) {
    Write-Host "📦 Đang cài node_modules cho dashboard..." -ForegroundColor DarkGray
    & $npmCmd install --prefix $dashDir
}

$dash = Start-Process -FilePath $npmCmd -WorkingDirectory $dashDir -ArgumentList "run","dev","--","--host","127.0.0.1","--port","3000","--strictPort" -PassThru
Write-Host "📊 Admin Portal     → http://localhost:3000  (PID $($dash.Id))" -ForegroundColor Cyan

# Wait for services to be ready (Firebase init can take 30-60s)
$aiReady = Wait-ForPort -Port 8001 -TimeoutSec 90
$apiReady = Wait-ForPort -Port 5000 -TimeoutSec 90
$dashReady = Wait-ForPort -Port 3000 -TimeoutSec 120

if (-not $aiReady) {
    Write-Host "⚠ AI server chưa mở cổng 8001 — Flask sẽ trả lỗi 502 khi gọi /api/soc/*" -ForegroundColor Yellow
}

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
Write-Host "   Or run: Stop-Process -Id $($aiProc.Id),$($api.Id),$($dash.Id)" -ForegroundColor DarkGray
Write-Host "   Note: No need to run python server.py again after start_all.ps1." -ForegroundColor DarkGray
Write-Host ""
