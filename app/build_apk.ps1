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
    [string]$ApiUrl    = 'http://167.71.207.121',
    [string]$VpsIp     = '167.71.207.121',
    [string]$VpsUser   = 'root',
    [string]$VpsPath   = '/opt/vinfast/web',
    [string]$KeyFile   = "$env:USERPROFILE\.ssh\id_ed25519",
    [string]$AdminKey  = 'vinfast-admin-2024',
    [string]$ReleaseNotes = ''  # Ghi chú phiên bản, có thể truyền khi chạy
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

# ── 2. Tăng patch + build number (nếu không có -NoBump) ──
if (-not $NoBump) {
    $patch++
    $build++
}
$newVersion = "$major.$minor.$patch+$build"
$newSemver  = "$major.$minor.$patch"
Write-Host "Version moi:      $newVersion" -ForegroundColor Green

# ── 3. Cập nhật pubspec.yaml ──
$pubspec = $pubspec -replace "version:\s*\d+\.\d+\.\d+\+\d+", "version: $newVersion"
Set-Content 'pubspec.yaml' -Value $pubspec -NoNewline

# ── 4. Cập nhật app_constants.dart ──
$constFile = 'lib\core\constants\app_constants.dart'
if (Test-Path $constFile) {
    $constContent = Get-Content $constFile -Raw
    $constContent = $constContent -replace "appVersion\s*=\s*'[^']+'", "appVersion = '$newSemver'"
    Set-Content $constFile -Value $constContent -NoNewline
}
Write-Host "Da cap nhat pubspec.yaml va app_constants.dart" -ForegroundColor Green

# ── 5. Flutter clean (CHỈ khi -Clean được truyền) ──
if ($Clean) {
    Write-Host "`n[CLEAN] Dang chay flutter clean..." -ForegroundColor Yellow
    flutter clean
    Write-Host "[CLEAN] Xong." -ForegroundColor Yellow
} else {
    Write-Host "`n[TIP] Bo qua flutter clean de dung cache (dung -Clean neu build loi)" -ForegroundColor DarkGray
}

# ── 6. Flutter pub get (chỉ khi pubspec.lock chưa sync) ──
$lockFile   = 'pubspec.lock'
$pubspecAge = (Get-Item 'pubspec.yaml').LastWriteTime
$lockAge    = if (Test-Path $lockFile) { (Get-Item $lockFile).LastWriteTime } else { [datetime]::MinValue }

if ($pubspecAge -gt $lockAge) {
    Write-Host "`nDang chay flutter pub get..." -ForegroundColor Cyan
    flutter pub get
} else {
    Write-Host "`n[SKIP] flutter pub get — pubspec.lock da moi hon pubspec.yaml" -ForegroundColor DarkGray
    flutter pub get --no-precompile 2>$null
}

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
Write-Host "  adb install releases\VinFastBattery_v$newSemver`_arm64-v8a.apk" -ForegroundColor DarkGray

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

            # Cập nhật app_config.json qua API
            $apkRelUrl = "/apk/$remoteApkName"
            $notes = if ($ReleaseNotes) { $ReleaseNotes } else { "Build $build — $([datetime]::Now.ToString('dd/MM/yyyy HH:mm'))" }
            $configBody = @{
                latestVersion    = $newSemver
                latestBuild      = [int]$build
                minSupportedBuild = 1
                apkUrl           = $apkRelUrl
                releaseNotes     = $notes
                forceUpdate      = $false
            } | ConvertTo-Json -Compress

            $configResp = Invoke-RestMethod `
                -Uri "$ApiUrl/api/app/config" `
                -Method POST `
                -Headers @{ 'Content-Type' = 'application/json'; 'X-Admin-Key' = $AdminKey } `
                -Body $configBody `
                -TimeoutSec 15 `
                -ErrorAction Stop

            if ($configResp.success) {
                Write-Host "  OK app_config.json → v$newSemver (build $build)" -ForegroundColor Green
                Write-Host "  Download: $ApiUrl/api/app/download" -ForegroundColor DarkGray
            } else {
                Write-Host "  WARN: API tra loi that bai: $($configResp.error)" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "  WARN: Khong the upload APK len VPS: $_" -ForegroundColor Yellow
            Write-Host "  (Bo qua, APK van nam tai $releaseDir)" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "  Khong tim thay APK de upload." -ForegroundColor DarkGray
    }
} else {
    Write-Host "`n[SKIP] Bo qua deploy VPS (-NoDeploy)" -ForegroundColor DarkGray
}
