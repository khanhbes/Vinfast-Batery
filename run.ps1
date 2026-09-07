<#
.SYNOPSIS
  run.ps1 - Trung tam dieu khien, khoi chay server va build app VinFast Battery.

.DESCRIPTION
  File script duy nhat tich hop toan bo tac vu cua du an:
  - Option 1: Chay Server Cuc bo (Local Dev: FastAPI 8001 + Flask 5000 + React 3000)
  - Option 2: Chay Server Docker va Tailscale Funnel (Public Internet)
  - Option 3: Build Android APK Release (Toi uu, ky so, copy OTA)
  - Option 4: Build Android APK Debug (Test nhanh tren may that)
  - Option 5: Don cache va Build sach APK (flutter clean + pub get + build)
  - Option 6: Don dep va Giai phong cac cong mang (5000, 8001, 3000)

.EXAMPLE
  .\run.ps1                 # Mo menu tuong tac chon option
  .\run.ps1 1               # Chay Server Local Dev
  .\run.ps1 2               # Chay Server Docker
  .\run.ps1 3               # Build APK Release
  .\run.ps1 4               # Build APK Debug
  .\run.ps1 -Option 1       # Chay theo tham so
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('1', '2', '3', '4', '5', '6', '0', 'local', 'docker', 'build-release', 'build-debug', 'build-clean', 'stop')]
    [string]$Option
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$rootDir = $PSScriptRoot
if (-not $rootDir) { $rootDir = (Get-Location).Path }
$webDir = Join-Path $rootDir 'web'
$appDir = Join-Path $rootDir 'app'

# =============================================================================
# Helper Functions
# =============================================================================
function Write-Header([string]$title) {
    Write-Host ""
    Write-Host "=====================================================================" -ForegroundColor Cyan
    Write-Host "  $title" -ForegroundColor Cyan
    Write-Host "=====================================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Step([string]$msg) {
    Write-Host "`n[>] $msg" -ForegroundColor Cyan
}

function Write-Ok([string]$msg) {
    Write-Host "  [OK] $msg" -ForegroundColor Green
}

function Write-Warn([string]$msg) {
    Write-Host "  [!] $msg" -ForegroundColor Yellow
}

function Write-ErrorMsg([string]$msg) {
    Write-Host "  [X] $msg" -ForegroundColor Red
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
                    Write-Host "  Giai phong cong $Port (PID $ownerPid)" -ForegroundColor DarkYellow
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

# =============================================================================
# OPTION 1: Server Local Dev (Python venv + Flask + AI + Vite)
# =============================================================================
function Start-ServerLocal {
    Write-Header "KHOI CHAY SERVER CUC BO (LOCAL DEV)"

    $pythonExe = Join-Path $webDir ".venv\Scripts\python.exe"
    if (-not (Test-Path $pythonExe)) {
        $pythonExe = "python"
        Write-Warn "Khong tim thay web\.venv\Scripts\python.exe, dung python tu PATH he thong."
    } else {
        Write-Ok "Python venv: $pythonExe"
    }

    Write-Step "Kiem tra va giai phong cac cong 5000, 3000, 8001..."
    try {
        Stop-PortProcess -Port 5000
        Stop-PortProcess -Port 3000
        Stop-PortProcess -Port 8001
        Write-Ok "Cac cong da san sang."
    } catch {
        Write-Warn "Bo qua don cong do han che quyen."
    }

    $serviceAccountCandidates = @(
        (Join-Path $rootDir "vinfast-873db-firebase-adminsdk-fbsvc-e584000635.json"),
        (Join-Path $webDir "serviceAccountKey.json"),
        (Join-Path $webDir "service-account-key.json"),
        (Join-Path $webDir "firebase-adminsdk.json"),
        (Join-Path $webDir "firebase-service-account.json"),
        (Join-Path $webDir "secrets\serviceAccountKey.json")
    )
    $serviceAccountPath = $null
    foreach ($c in $serviceAccountCandidates) {
        if (Test-Path $c) {
            $serviceAccountPath = $c
            break
        }
    }
    if (-not $serviceAccountPath) {
        $patternCandidates = @(
            (Get-ChildItem -Path $rootDir -File -Filter "*firebase-adminsdk*.json" -ErrorAction SilentlyContinue),
            (Get-ChildItem -Path $webDir -File -Filter "*firebase-adminsdk*.json" -ErrorAction SilentlyContinue),
            (Get-ChildItem -Path $webDir -File -Filter "*service*account*.json" -ErrorAction SilentlyContinue)
        )
        foreach ($group in $patternCandidates) {
            if ($group -and $group.Count -gt 0) {
                $serviceAccountPath = $group[0].FullName
                break
            }
        }
    }

    $aiToken = $env:AI_SERVER_INTERNAL_TOKEN
    if ([string]::IsNullOrWhiteSpace($aiToken)) {
        $bytes = New-Object byte[] 32
        $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        $rng.GetBytes($bytes)
        $rng.Dispose()
        $aiToken = [Convert]::ToBase64String($bytes)
        Write-Warn "AI_SERVER_INTERNAL_TOKEN chua set -> da tao token tam cho phien nay."
    }
    $devAdminKey = $env:DEV_ADMIN_KEY
    if ([string]::IsNullOrWhiteSpace($devAdminKey)) {
        $bytes = New-Object byte[] 32
        $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        $rng.GetBytes($bytes)
        $rng.Dispose()
        $devAdminKey = [Convert]::ToBase64String($bytes)
        Write-Warn "DEV_ADMIN_KEY chua set -> da tao key tam cho phien nay."
    }

    Write-Step "Khoi dong AI Server (FastAPI port 8001)..."
    $aiCmd = "cd /d `"$webDir`" && set `"PYTHONIOENCODING=utf-8`" && set `"AI_SERVER_INTERNAL_TOKEN=$aiToken`" && `"$pythonExe`" -m uvicorn ai_server.main:app --host 127.0.0.1 --port 8001"
    $aiProc = Start-Process cmd -ArgumentList "/k", $aiCmd -PassThru
    Write-Ok "AI Server        -> http://127.0.0.1:8001 (PID $($aiProc.Id))"

    Write-Step "Khoi dong Unified API (Flask port 5000)..."
    $apiCmd = "cd /d `"$webDir`" && set `"PYTHONIOENCODING=utf-8`" && set `"AI_SERVER_URL=http://127.0.0.1:8001`" && set `"AI_SERVER_INTERNAL_TOKEN=$aiToken`" && set `"CORS_ORIGINS=http://localhost:3000`" && "
    $adminEmails = $env:ADMIN_EMAILS
    if ([string]::IsNullOrWhiteSpace($adminEmails)) {
        $adminEmails = "khanhnhim21102004@gmail.com"
        Write-Warn "ADMIN_EMAILS chua cau hinh -> bootstrap owner admin: $adminEmails"
    } else {
        Write-Ok "ADMIN_EMAILS = $adminEmails"
    }
    $apiCmd += "set `"ADMIN_EMAILS=$adminEmails`" && set `"DEV_ADMIN_KEY=$devAdminKey`" && set `"APP_ENV=development`" && "

    if ($serviceAccountPath) {
        $apiCmd += "set `"GOOGLE_APPLICATION_CREDENTIALS=$serviceAccountPath`" && "
        Write-Ok "Firebase Credential: $serviceAccountPath"
    } else {
        Write-Warn "Khong tim thay service account key. API se chay in-memory fallback."
    }
    $apiCmd += "set `"FLASK_USE_RELOADER=0`" && `"$pythonExe`" server.py"

    $api = Start-Process cmd -ArgumentList "/k", $apiCmd -PassThru
    Write-Ok "Unified API      -> http://localhost:5000 (PID $($api.Id))"

    Write-Step "Khoi dong Admin Portal (React / Vite port 3000)..."
    $dashDir = Join-Path $webDir "dashboard"
    $npmCmd = Join-Path ${env:ProgramFiles} "nodejs\npm.cmd"
    if (-not (Test-Path $npmCmd)) { $npmCmd = "npm.cmd" }

    if (-not (Test-Path (Join-Path $dashDir "node_modules"))) {
        Write-Host "  Dang cai dat node_modules cho dashboard..." -ForegroundColor DarkGray
        & $npmCmd install --prefix $dashDir
    }

    $dash = Start-Process -FilePath $npmCmd -WorkingDirectory $dashDir -ArgumentList "run","dev","--","--host","127.0.0.1","--port","3000","--strictPort" -PassThru
    Write-Ok "Admin Portal     -> http://localhost:3000 (PID $($dash.Id))"

    Write-Step "Kiem tra trang thai khoi dong cac dich vu..."
    $aiReady = Wait-ForPort -Port 8001 -TimeoutSec 45
    $apiReady = Wait-ForPort -Port 5000 -TimeoutSec 45
    $dashReady = Wait-ForPort -Port 3000 -TimeoutSec 60

    Write-Host ""
    if ($apiReady -and $dashReady) {
        Write-Host "=====================================================================" -ForegroundColor Green
        Write-Host "  TAT CA DICH VU DA SAN SANG HOAT DONG!" -ForegroundColor Green
        Write-Host "  - Admin Portal:  http://localhost:3000" -ForegroundColor Cyan
        Write-Host "  - Backend API:   http://localhost:5000" -ForegroundColor Cyan
        Write-Host "  - AI Engine:     http://localhost:8001" -ForegroundColor Cyan
        Write-Host "  - Public server: https://khanhbes.tailaafca5.ts.net/" -ForegroundColor Cyan
        Write-Host "=====================================================================" -ForegroundColor Green
    } else {
        Write-Warn "Mot so dich vu can them vai giay de san sang. Kiem tra cac cua so CMD."
    }
    Write-Host "`nDe dung server: Chay .\run.ps1 chon [6] hoac dong 3 cua so CMD." -ForegroundColor DarkGray
}

# =============================================================================
# OPTION 2: Server Docker va Tailscale Funnel (Cach 2)
# =============================================================================
function Start-ServerDocker {
    Write-Header "KHOI CHAY SERVER DOCKER VA TAILSCALE FUNNEL"

    $envLaptop = Join-Path $webDir '.env.laptop'
    if (-not (Test-Path $envLaptop)) {
        throw "Khong tim thay web/.env.laptop. Vui long tao web/.env.laptop truoc."
    }

    Write-Step "Kiem tra Docker Desktop..."
    & docker info *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "Docker Desktop chua chay! Hay mo Docker Desktop truoc khi chay option nay."
    }
    Write-Ok "Docker Desktop dang hoat dong."

    $compose = @('--env-file', '.env.laptop', '-f', 'docker-compose.yml', '-f', 'docker-compose.laptop.yml')
    $buildServices = @('ai', 'api', 'dashboard')
    $upServices = @('ai', 'api', 'dashboard', 'laptop_gateway')

    Push-Location $webDir
    try {
        foreach ($item in $buildServices) {
            Write-Step "Build Docker image: $item"
            & docker compose @compose build $item
            if ($LASTEXITCODE -ne 0) { throw "Build Docker image $item that bai." }
        }

        Write-Step "Khoi dong containers: $($upServices -join ', ')"
        & docker compose @compose up -d --force-recreate @upServices
        if ($LASTEXITCODE -ne 0) { throw "Khoi dong Docker containers that bai." }
        Write-Ok "Containers da chay ngam."

        Write-Step "Kich hoat Tailscale Funnel cong 8080..."
        & tailscale funnel --bg 8080
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "Khong the bat Tailscale Funnel. Can chay PowerShell voi quyen Administrator hoac kiem tra Tailscale."
        } else {
            Write-Ok "Tailscale Funnel da kich hoat tren cong 8080."
        }

        $publicUrl = "https://khanhbes.tailaafca5.ts.net"
        $healthUrl = "$publicUrl/api/health"
        Write-Step "Kiem tra ket noi: $healthUrl"
        try {
            Invoke-RestMethod -Uri $healthUrl -TimeoutSec 20 -ErrorAction Stop | Out-Null
            Write-Ok "API Public da phan hoi tot qua Tailscale Funnel!"
        } catch {
            Write-Warn "Chua nhan phan hoi tu $healthUrl. Co the server dang khoi dong container."
        }

        Write-Host "`nDOCKER VA TAILSCALE DA SAN SANG:" -ForegroundColor Green
        Write-Host "  - Public Dashboard: $publicUrl" -ForegroundColor Cyan
        Write-Host "  - Public Health API: $healthUrl" -ForegroundColor Cyan
    } finally {
        Pop-Location
    }
}

# =============================================================================
# OPTION 3, 4, 5: Build Android APK
# =============================================================================
function Build-AndroidApp {
    param(
        [string]$BuildMode = 'release',
        [switch]$Clean,
        [switch]$SplitAbi,
        [string]$ApiUrl = 'https://khanhbes.tailaafca5.ts.net'
    )

    Write-Header "BUILD ANDROID APK ($($BuildMode.ToUpper()))"

    if (-not (Test-Path $appDir)) {
        throw "Khong tim thay thu muc app: $appDir"
    }

    Write-Step "Kiem tra moi truong Flutter SDK..."
    $flutterCmd = Get-Command flutter -ErrorAction SilentlyContinue
    if (-not $flutterCmd) {
        throw "Khong tim thay lenh 'flutter'. Vui long cai Flutter SDK va them vao PATH."
    }
    Write-Ok "Flutter SDK san sang."

    $androidDir = Join-Path $appDir 'android'
    $keyPropsFile = Join-Path $androidDir 'key.properties'
    $env:ALLOW_DEBUG_SIGNING = "true"
    if (Test-Path $keyPropsFile) {
        Write-Ok "Phat hien key.properties -> Dung release keystore."
    } else {
        Write-Warn "Chua co key.properties -> Tu dong dung debug keystore de build."
    }

    Push-Location $appDir
    try {
        if ($Clean) {
            Write-Step "Don dep cache sach (flutter clean)..."
            & flutter clean
            Write-Ok "Da clean xong."
        }

        Write-Step "Cap nhat dependencies (flutter pub get)..."
        & flutter pub get
        if ($LASTEXITCODE -ne 0) { throw "flutter pub get that bai." }
        Write-Ok "Dependencies san sang."

        Write-Step "Dang bien dich APK ($BuildMode)..."
        $buildArgs = @('build', 'apk', "--$BuildMode")
        $buildArgs += "--dart-define=APP_API_BASE_URL=$ApiUrl"
        if ($SplitAbi -and $BuildMode -eq 'release') {
            $buildArgs += '--split-per-abi'
        }

        Write-Host "  Lenh: flutter $($buildArgs -join ' ')" -ForegroundColor DarkGray
        & flutter @buildArgs
        if ($LASTEXITCODE -ne 0) {
            throw "Build APK that bai voi exit code $LASTEXITCODE"
        }

        $outputDir = Join-Path $appDir "build\app\outputs\flutter-apk"
        $apkFiles = Get-ChildItem -Path $outputDir -Filter "*.apk" | Where-Object { $_.Name -notmatch 'preview' }
        if (-not $apkFiles) {
            throw "Khong tim thay file APK nao trong $outputDir"
        }

        $appReleasesDir = Join-Path $appDir "releases"
        $webApkDir = Join-Path $webDir "apk"
        if (-not (Test-Path $appReleasesDir)) { New-Item -ItemType Directory -Path $appReleasesDir -Force | Out-Null }
        if (-not (Test-Path $webApkDir)) { New-Item -ItemType Directory -Path $webApkDir -Force | Out-Null }

        Write-Step "Tong ket file APK da tao:"
        foreach ($apk in $apkFiles) {
            $sizeMB = [math]::Round($apk.Length / 1MB, 2)
            Write-Host "  [APK] $($apk.Name) ($sizeMB MB)" -ForegroundColor Green
            Write-Host "        Duong dan: $($apk.FullName)" -ForegroundColor DarkGray

            Copy-Item -Path $apk.FullName -Destination (Join-Path $appReleasesDir $apk.Name) -Force

            if ($apk.Name -match 'app-release.apk' -or $apk.Name -match 'app-arm64-v8a-release.apk') {
                $latestTarget = Join-Path $webApkDir "VinFastBattery_latest.apk"
                Copy-Item -Path $apk.FullName -Destination $latestTarget -Force
                Write-Ok "Da cap nhat OTA web server: $latestTarget"
            }
        }

        Write-Host ""
        Write-Host "=====================================================================" -ForegroundColor Green
        Write-Host "  BUILD APK THANH CONG!" -ForegroundColor Green
        Write-Host "  File APK da san sang de cai dat hoac phan phoi OTA." -ForegroundColor Green
        Write-Host "=====================================================================" -ForegroundColor Green
    } finally {
        Pop-Location
    }
}

# =============================================================================
# OPTION 6: Tat server va giai phong cong
# =============================================================================
function Stop-AllServers {
    Write-Header "DON DEP VA GIAI PHONG CAC CONG MANG"

    Write-Step "Dang dong cac tien trinh tren cong 5000, 8001, 3000..."
    Stop-PortProcess -Port 5000
    Stop-PortProcess -Port 8001
    Stop-PortProcess -Port 3000
    Write-Ok "Da giai phong cac cong."

    Write-Step "Kiem tra Docker containers..."
    $dockerCmd = Get-Command docker -ErrorAction SilentlyContinue
    if ($dockerCmd) {
        try {
            Push-Location $webDir
            & docker compose -f docker-compose.yml -f docker-compose.laptop.yml down --remove-orphans 2>$null
            Write-Ok "Da dung Docker containers (neu co)."
        } catch {} finally {
            Pop-Location
        }
    }

    Write-Host "`nHe thong da duoc don dep sach se!" -ForegroundColor Green
}

# =============================================================================
# Menu tuong tac
# =============================================================================
function Show-Menu {
    Clear-Host
    Write-Host ""
    Write-Host "=====================================================================" -ForegroundColor Cyan
    Write-Host "          VINFAST BATTERY - TRUNG TAM DIEU KHIEN VA BUILD" -ForegroundColor Cyan
    Write-Host "=====================================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  [1] Khoi chay Server Cuc bo (Local Dev - Khong Docker)" -ForegroundColor White
    Write-Host "      -> AI FastAPI (8001) + Flask API (5000) + Admin Portal (3000)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  [2] Khoi chay Server Docker va Tailscale Funnel" -ForegroundColor White
    Write-Host "      -> Chay containers va mo ket noi Internet: khanhbes.tailaafca5.ts.net" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  [3] Build ung dung Android APK (Ban Release chuan - Toi uu, Ky so)" -ForegroundColor White
    Write-Host "      -> Tao APK release va tu dong copy vao thu muc OTA web" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  [4] Build ung dung Android APK (Ban Debug - Test nhanh tren may that)" -ForegroundColor White
    Write-Host "      -> Bien dich nhanh khong can cau hinh keystore" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  [5] Don dep cache va Build sach APK (flutter clean + build release)" -ForegroundColor White
    Write-Host "      -> Dung khi gap loi cache hoac thu vien bien dich" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  [6] Tat server va Giai phong toan bo cong (5000, 8001, 3000)" -ForegroundColor White
    Write-Host "      -> Giai quyet loi Port already in use / xung dot tien trinh" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  [0] Thoat" -ForegroundColor Red
    Write-Host ""
    Write-Host "=====================================================================" -ForegroundColor Cyan
    $choice = Read-Host "Nhap lua chon cua ban [0-6] (mac dinh: 1)"
    if ([string]::IsNullOrWhiteSpace($choice)) { $choice = '1' }
    return $choice
}

# =============================================================================
# Router
# =============================================================================
$selected = $Option
if ([string]::IsNullOrWhiteSpace($selected)) {
    $selected = Show-Menu
}

switch ($selected) {
    { $_ -in '1', 'local' } {
        Start-ServerLocal
    }
    { $_ -in '2', 'docker' } {
        Start-ServerDocker
    }
    { $_ -in '3', 'build-release' } {
        Build-AndroidApp -BuildMode 'release' -SplitAbi
    }
    { $_ -in '4', 'build-debug' } {
        Build-AndroidApp -BuildMode 'debug'
    }
    { $_ -in '5', 'build-clean' } {
        Build-AndroidApp -BuildMode 'release' -Clean -SplitAbi
    }
    { $_ -in '6', 'stop' } {
        Stop-AllServers
    }
    { $_ -in '0', 'exit', 'q' } {
        Write-Host "Da thoat." -ForegroundColor Yellow
        exit 0
    }
    default {
        Write-ErrorMsg "Lua chon khong hop le: $selected"
        exit 1
    }
}
