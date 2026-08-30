<#
  build_apk.ps1 — Auto tăng version + build APK arm64-v8a (tối ưu tốc độ)
  Mặc định:         .\build_apk.ps1              → arm64-v8a only (nhanh nhất)
  Có clean:         .\build_apk.ps1 -Clean        → xóa cache rồi build
  Không tăng ver:   .\build_apk.ps1 -NoBump       → giữ nguyên version
  Tất cả ABI:       .\build_apk.ps1 -AllAbi       → arm64 + armv7 + x86_64
  Fat APK:          .\build_apk.ps1 -Fat          → 1 file cho mọi thiết bị
#>
param(
    [switch]$Clean,     # Xóa cache trước khi build (dùng khi có lỗi lạ)
    [switch]$Fat,       # Build fat APK (tất cả ABI trong 1 file)
    [switch]$AllAbi,    # Build split cho cả 3 ABI: arm64-v8a, armeabi-v7a, x86_64
    [switch]$NoBump,    # Không tăng version (build lại cùng version)
    [switch]$NoDeploy,  # Không upload APK lên VPS sau build
    [string]$ApiUrl    = 'https://api.evbattery.live',
    [string]$VpsIp     = '167.71.207.121',
    [string]$VpsUser   = 'root',
    [string]$VpsPath   = '/opt/vinfast/web',
    [string]$KeyFile   = "$env:USERPROFILE\.ssh\id_ed25519",
    [string]$AdminKey  = $env:VINFAST_ADMIN_KEY, # Nếu trống, cập nhật config an toàn qua SSH
    [string]$ReleaseNotes = '',         # Ghi chú phiên bản, có thể truyền khi chạy
    [switch]$ForceUpdate,                # Đánh dấu bản này là bắt buộc cập nhật
    [int]$MinSupportedBuild = 0          # 0 = giữ policy hiện tại; >0 = cập nhật build tối thiểu
) 

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $projectDir

Write-Host "`n=== VinFast Battery — Build APK ===" -ForegroundColor Cyan
$buildStart = Get-Date

# ── 1. Đọc version hiện tại từ pubspec.yaml ──
$pubspec = Get-Content 'pubspec.yaml' -Raw
if ($pubspec -match 'version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)') {
    $major = [int]$Matches[1]
    $minor = [int]$Matches[2]
    $patch = [int]$Matches[3]
    $build = [int]$Matches[4]
} else {
    Write-Host "Khong tim thay version trong pubspec.yaml" -ForegroundColor Red
    exit 1
}

$oldVersion = "$major.$minor.$patch+$build"
Write-Host "Version hien tai: $oldVersion" -ForegroundColor Yellow

# ── 2. Preflight trước khi chạm vào version ──
# Một build lỗi không được quảng bá version mới. Analyze và tests luôn chạy
# trước bước bump để metadata auto-update chỉ trỏ tới artifact đã kiểm chứng.
if ($ApiUrl -notmatch '^https://') {
    throw 'Release API bat buoc dung HTTPS. Hay truyen -ApiUrl https://...'
}
try {
    # Windows PowerShell 5.1 may invoke the retired IE HTML parser and throw a
    # misleading NullReferenceException even when the HTTPS response is 200.
    $health = Invoke-WebRequest -UseBasicParsing -Uri "$ApiUrl/api/health" -Method GET -TimeoutSec 15 -ErrorAction Stop
    if ([int]$health.StatusCode -lt 200 -or [int]$health.StatusCode -ge 400) {
        throw "API health tra HTTP $($health.StatusCode)"
    }
} catch {
    throw "Release API HTTPS chua san sang: $ApiUrl/api/health — $_"
}

Write-Host "`n[CHECK] Dong bo dependencies..." -ForegroundColor Cyan
flutter pub get
if ($LASTEXITCODE -ne 0) { throw 'flutter pub get that bai.' }

Write-Host "[CHECK] Flutter analyze..." -ForegroundColor Cyan
flutter analyze --no-pub --no-fatal-warnings --no-fatal-infos
if ($LASTEXITCODE -ne 0) { throw 'flutter analyze that bai; version chua bi thay doi.' }

Write-Host "[CHECK] Flutter tests..." -ForegroundColor Cyan
flutter test --no-pub
if ($LASTEXITCODE -ne 0) { throw 'flutter test that bai; version chua bi thay doi.' }

# ── 3. Tăng patch + build number (nếu không có -NoBump) ──
if (-not $NoBump) {
    $patch++
    $build++
}
$newVersion = "$major.$minor.$patch+$build"
$newSemver  = "$major.$minor.$patch"
Write-Host "Version moi:      $newVersion" -ForegroundColor Green

# ── 4. Cập nhật pubspec.yaml ──
$pubspec = $pubspec -replace "version:\s*\d+\.\d+\.\d+\+\d+", "version: $newVersion"
Set-Content 'pubspec.yaml' -Value $pubspec -NoNewline

# ── 5. Cập nhật app_constants.dart ──
$constFile = 'lib\core\constants\app_constants.dart'
if (Test-Path $constFile) {
    $constContent = Get-Content $constFile -Raw
    $constContent = $constContent -replace "appVersion\s*=\s*'[^']+'", "appVersion = '$newSemver'"
    Set-Content $constFile -Value $constContent -NoNewline
}
Write-Host "Da cap nhat pubspec.yaml va app_constants.dart" -ForegroundColor Green

# ── 6. Flutter clean (CHỈ khi -Clean được truyền) ──
if ($Clean) {
    Write-Host "`n[CLEAN] Dang chay flutter clean..." -ForegroundColor Yellow
    flutter clean
    Write-Host "[CLEAN] Xong." -ForegroundColor Yellow
} else {
    Write-Host "`n[TIP] Bo qua flutter clean de dung cache (dung -Clean neu build loi)" -ForegroundColor DarkGray
}

# Dependencies đã được resolve trong preflight. Version app không thay đổi
# dependency graph nên không cần chạy pub get lần hai.
Write-Host "`n[SKIP] Dependencies da duoc kiem tra trong preflight." -ForegroundColor DarkGray

# ── 7. Build APK ──
if ($Fat) {
    Write-Host "`nDang build fat APK (release)..." -ForegroundColor Cyan
    flutter build apk --release --no-pub --dart-define=APP_API_BASE_URL=$ApiUrl
} elseif ($AllAbi) {
    Write-Host "`nDang build APK split 3 ABI (release)..." -ForegroundColor Cyan
    flutter build apk --release --split-per-abi --no-pub --dart-define=APP_API_BASE_URL=$ApiUrl
} else {
    Write-Host "`nDang build APK arm64-v8a only (release)..." -ForegroundColor Cyan
    flutter build apk --release --split-per-abi --target-platform android-arm64 --no-pub --dart-define=APP_API_BASE_URL=$ApiUrl
}

if ($LASTEXITCODE -ne 0) {
    Write-Host "`nBuild THAT BAI!" -ForegroundColor Red
    exit 1
}

# ── 8. Copy APK ra thư mục releases ──
$releaseDir = Join-Path $projectDir 'releases'
if (!(Test-Path $releaseDir)) {
    New-Item -ItemType Directory -Path $releaseDir | Out-Null
}

$apkSource = 'build\app\outputs\flutter-apk'
$copied = 0

if ($Fat) {
    $apkFile = "$apkSource\app-release.apk"
    if (Test-Path $apkFile) {
        $dest = Join-Path $releaseDir "VinFastBattery_v$newSemver.apk"
        Copy-Item $apkFile $dest -Force
        $sizeMB = [math]::Round((Get-Item $apkFile).Length / 1MB, 1)
        Write-Host "  -> $dest ($sizeMB MB)" -ForegroundColor Green
        $copied++
    }
} elseif ($AllAbi) {
    $abis = @('arm64-v8a', 'armeabi-v7a', 'x86_64')
    foreach ($abi in $abis) {
        $apkFile = "$apkSource\app-$abi-release.apk"
        if (Test-Path $apkFile) {
            $dest = Join-Path $releaseDir "VinFastBattery_v$newSemver`_$abi.apk"
            Copy-Item $apkFile $dest -Force
            $sizeMB = [math]::Round((Get-Item $apkFile).Length / 1MB, 1)
            Write-Host "  -> $dest ($sizeMB MB)" -ForegroundColor Green
            $copied++
        }
    }
} else {
    # Default: chỉ arm64-v8a
    $apkFile = "$apkSource\app-arm64-v8a-release.apk"
    if (Test-Path $apkFile) {
        $dest = Join-Path $releaseDir "VinFastBattery_v$newSemver.apk"
        Copy-Item $apkFile $dest -Force
        $sizeMB = [math]::Round((Get-Item $apkFile).Length / 1MB, 1)
        Write-Host "  -> $dest ($sizeMB MB)" -ForegroundColor Green
        $copied++
    }
}

if ($copied -eq 0) {
    Write-Host "Khong tim thay file APK nao!" -ForegroundColor Red
    exit 1
}

# ── 9. Thời gian build ──
$elapsed = [math]::Round(((Get-Date) - $buildStart).TotalMinutes, 1)
Write-Host "`n=== BUILD THANH CONG — v$newVersion (${elapsed} phut) ===" -ForegroundColor Cyan
Write-Host "APK nam tai: $releaseDir`n" -ForegroundColor Yellow
Write-Host "[HUONG DAN] Cai dat len thiet bi:" -ForegroundColor DarkGray
Write-Host "  adb install releases\VinFastBattery_v$newSemver.apk" -ForegroundColor DarkGray

# ── 10. Upload APK lên VPS + cập nhật app_config.json ──
if (-not $NoDeploy) {
    Write-Host "`n--- Auto-deploy APK len VPS ---" -ForegroundColor Cyan

    # Tìm APK vừa build (ưu tiên arm64)
    $apkToDeploy = $null
    $arm64Apk = Join-Path $releaseDir "VinFastBattery_v$newSemver.apk"
    if (Test-Path $arm64Apk) { $apkToDeploy = $arm64Apk }

    if ($apkToDeploy) {
        $remoteApkDir  = "$VpsPath/apk"
        $remoteApkName = "VinFastBattery_latest.apk"
        $remoteApkPath = "$remoteApkDir/$remoteApkName"

        try {
            # Tạo thư mục trên VPS nếu chưa có
            ssh -i $KeyFile -o BatchMode=yes -o StrictHostKeyChecking=accept-new `
                "${VpsUser}@${VpsIp}" "mkdir -p $remoteApkDir" 2>$null

            # Upload APK
            Write-Host "  Upload APK ($([math]::Round((Get-Item $apkToDeploy).Length/1MB,1)) MB)..." -ForegroundColor Gray
            scp -i $KeyFile -q $apkToDeploy "${VpsUser}@${VpsIp}:${remoteApkPath}"

            # Cập nhật app_config.json. Ưu tiên Admin API; nếu máy build chưa
            # cấu hình VINFAST_ADMIN_KEY thì dùng chính SSH đã upload APK.
            $apkRelUrl = "/apk/$remoteApkName"
            $notes = if ($ReleaseNotes) { $ReleaseNotes } else { "Build $build — $([datetime]::Now.ToString('dd/MM/yyyy HH:mm'))" }
            $config = @{}
            try {
                $currentConfigResp = Invoke-RestMethod `
                    -Uri "$ApiUrl/api/app/config" `
                    -Method GET `
                    -TimeoutSec 15 `
                    -ErrorAction Stop
                if ($currentConfigResp.success -and $currentConfigResp.data) {
                    $currentConfigResp.data.psobject.Properties | ForEach-Object {
                        $config[$_.Name] = $_.Value
                    }
                }
            } catch {
                $localConfigFile = Join-Path (Split-Path $projectDir -Parent) 'web\app_config.json'
                if (Test-Path $localConfigFile) {
                    $localConfig = Get-Content $localConfigFile -Raw | ConvertFrom-Json
                    $localConfig.psobject.Properties | ForEach-Object {
                        $config[$_.Name] = $_.Value
                    }
                }
            }

            $config['latestVersion'] = $newSemver
            $config['latestBuild'] = [int]$build
            if ($MinSupportedBuild -gt 0) {
                $config['minSupportedBuild'] = [int]$MinSupportedBuild
            } elseif (-not $config.ContainsKey('minSupportedBuild')) {
                $config['minSupportedBuild'] = 1
            }
            $config['apkUrl'] = $apkRelUrl
            $config['releaseNotes'] = $notes
            $config['forceUpdate'] = [bool]$ForceUpdate
            if (-not $config.ContainsKey('releaseChannel')) { $config['releaseChannel'] = 'apk' }
            if (-not $config.ContainsKey('remindLaterHours')) { $config['remindLaterHours'] = 6 }
            if (-not $config.ContainsKey('features')) { $config['features'] = @{} }
            $configBody = $config | ConvertTo-Json -Depth 10 -Compress

            if (-not [string]::IsNullOrWhiteSpace($AdminKey)) {
                $configResp = Invoke-RestMethod `
                    -Uri "$ApiUrl/api/app/config" `
                    -Method POST `
                    -Headers @{ 'Content-Type' = 'application/json'; 'X-Admin-Key' = $AdminKey } `
                    -Body $configBody `
                    -TimeoutSec 15 `
                    -ErrorAction Stop
                if (-not $configResp.success) {
                    throw "Admin API khong cap nhat duoc app config: $($configResp.error)"
                }
            } else {
                $tempConfigFile = Join-Path $projectDir '.app_config.deploy.json'
                $remoteTempConfig = "$remoteApkDir/app_config.json.tmp-$build"
                try {
                    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
                    [System.IO.File]::WriteAllText(
                        $tempConfigFile,
                        ($config | ConvertTo-Json -Depth 10),
                        $utf8NoBom
                    )
                    scp -i $KeyFile -q $tempConfigFile "${VpsUser}@${VpsIp}:${remoteTempConfig}"
                    ssh -i $KeyFile -o BatchMode=yes `
                        "${VpsUser}@${VpsIp}" "mv $remoteTempConfig $remoteApkDir/app_config.json"
                } finally {
                    if (Test-Path $tempConfigFile) {
                        Remove-Item -LiteralPath $tempConfigFile -Force
                    }
                }
            }

            # Xác nhận public endpoint đã quảng bá đúng build vừa upload.
            $verifyResp = Invoke-RestMethod `
                -Uri "$ApiUrl/api/app/config" `
                -Method GET `
                -TimeoutSec 15 `
                -ErrorAction Stop
            if (-not $verifyResp.success -or
                [int]$verifyResp.data.latestBuild -ne [int]$build -or
                [string]$verifyResp.data.latestVersion -ne $newSemver) {
                throw "Server chua xac nhan app config v$newSemver+$build"
            }
            $downloadProbe = Invoke-WebRequest `
                -UseBasicParsing `
                -Uri "$ApiUrl/api/app/download" `
                -Method HEAD `
                -TimeoutSec 15 `
                -ErrorAction Stop
            if ([int]$downloadProbe.StatusCode -lt 200 -or [int]$downloadProbe.StatusCode -ge 400) {
                throw "APK download endpoint tra HTTP $($downloadProbe.StatusCode)"
            }

            # Giữ metadata trong repo đồng bộ với bản đang phát hành.
            $localConfigFile = Join-Path (Split-Path $projectDir -Parent) 'web\app_config.json'
            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllText(
                $localConfigFile,
                ($config | ConvertTo-Json -Depth 10),
                $utf8NoBom
            )

            $forceLabel = if ($ForceUpdate) { ' [FORCE]' } else { '' }
            $effectiveMinBuild = [int]$config['minSupportedBuild']
            Write-Host "  OK app_config.json → v$newSemver (build $build, min=$effectiveMinBuild)$forceLabel" -ForegroundColor Green
            Write-Host "  Download: $ApiUrl/api/app/download" -ForegroundColor DarkGray
        } catch {
            Write-Host "  ERROR: Auto-update deploy that bai: $_" -ForegroundColor Red
            Write-Host "  APK local van nam tai $releaseDir" -ForegroundColor DarkGray
            throw
        }
    } else {
        throw "Khong tim thay APK de auto-deploy."
    }
} else {
    Write-Host "`n[SKIP] Bo qua deploy VPS (-NoDeploy)" -ForegroundColor DarkGray
}
