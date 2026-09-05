<#
.SYNOPSIS
  build_app.ps1 — Script duy nhat de build VinFast Battery Android APK.

.DESCRIPTION
  Tu dong xu ly signing, toi uu kich thuoc, ho tro build Release va Debug,
  tu dong sao chep file APK sang thu muc releases va web/apk de phan phoi OTA.

.EXAMPLE
  .\build_app.ps1                              # Build release APK (mac dinh)
  .\build_app.ps1 -SplitAbi                    # Build release chia nho theo chip (arm64-v8a)
  .\build_app.ps1 -Mode debug                  # Build debug APK
  .\build_app.ps1 -Clean                       # Xoa cache build sach se truoc khi build
  .\build_app.ps1 -ApiUrl https://my-server    # Chi dinh dia chi API backend
#>
[CmdletBinding()]
param(
    [ValidateSet('release', 'debug')]
    [string]$Mode = 'release',

    [switch]$SplitAbi,

    [switch]$Clean,

    [string]$ApiUrl = 'https://khanhbes.tailaafca5.ts.net'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$rootDir = $PSScriptRoot
if (-not $rootDir) { $rootDir = (Get-Location).Path }
$appDir = Join-Path $rootDir 'app'
$androidDir = Join-Path $appDir 'android'
$keyPropsFile = Join-Path $androidDir 'key.properties'

function Write-Step([string]$msg) {
    Write-Host "`n[>] $msg" -ForegroundColor Cyan
}

function Write-Ok([string]$msg) {
    Write-Host "  [OK] $msg" -ForegroundColor Green
}

function Write-Warn([string]$msg) {
    Write-Host "  [!] $msg" -ForegroundColor Yellow
}

if (-not (Test-Path $appDir)) {
    throw "Khong tim thay thu muc app: $appDir"
}

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  VinFast Battery - Build Android APK" -ForegroundColor Cyan
Write-Host "  Mode: $Mode | API: $ApiUrl" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

# 1. Kiem tra Flutter SDK
Write-Step "Kiem tra moi truong Flutter"
$flutterCmd = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutterCmd) {
    throw "Khong tim thay lenh 'flutter'. Vui long cai dat Flutter SDK va them vao PATH."
}
Write-Ok "Flutter SDK san sang"

# 2. Xu ly Signing
$env:ALLOW_DEBUG_SIGNING = "true"
if (Test-Path $keyPropsFile) {
    Write-Ok "Phat hien cau hinh release signing tai: app/android/key.properties"
} else {
    Write-Warn "Chua co app/android/key.properties -> Tu dong dung debug keystore de build."
}

Push-Location $appDir
try {
    # 3. Clean neu duoc yeu cau
    if ($Clean) {
        Write-Step "Don dep cache (flutter clean)"
        & flutter clean
        Write-Ok "Da clean xong"
    }

    # 4. Cai dat dependencies
    Write-Step "Tai dependencies (flutter pub get)"
    & flutter pub get
    if ($LASTEXITCODE -ne 0) {
        throw "flutter pub get that bai."
    }
    Write-Ok "Dependencies da san sang"

    # 5. Build APK
    Write-Step "Dang bien dich APK ($Mode)..."
    $buildArgs = @('build', 'apk', "--$Mode")
    $buildArgs += "--dart-define=APP_API_BASE_URL=$ApiUrl"

    if ($SplitAbi -and $Mode -eq 'release') {
        $buildArgs += '--split-per-abi'
    }

    Write-Host "  Lenh: flutter $($buildArgs -join ' ')" -ForegroundColor DarkGray
    & flutter @buildArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Build APK that bai voi exit code $LASTEXITCODE"
    }

    # 6. Thu thap file ket qua
    $outputDir = Join-Path $appDir "build\app\outputs\flutter-apk"
    $apkFiles = Get-ChildItem -Path $outputDir -Filter "*.apk" | Where-Object { $_.Name -notmatch 'preview' }

    if (-not $apkFiles) {
        throw "Khong tim thay file APK trong: $outputDir"
    }

    # Tao thu muc releases va web/apk de luu tru
    $appReleasesDir = Join-Path $appDir "releases"
    $webApkDir = Join-Path $rootDir "web\apk"
    if (-not (Test-Path $appReleasesDir)) { New-Item -ItemType Directory -Path $appReleasesDir -Force | Out-Null }
    if (-not (Test-Path $webApkDir)) { New-Item -ItemType Directory -Path $webApkDir -Force | Out-Null }

    Write-Step "Tong ket file APK da tao:"
    foreach ($apk in $apkFiles) {
        $sizeMB = [math]::Round($apk.Length / 1MB, 2)
        Write-Host "  [APK] $($apk.Name) ($sizeMB MB)" -ForegroundColor Green
        Write-Host "        Duong dan: $($apk.FullName)" -ForegroundColor DarkGray

        # Copy ra releases
        Copy-Item -Path $apk.FullName -Destination (Join-Path $appReleasesDir $apk.Name) -Force

        # Neu la ban release chinh, cap nhat vao web/apk/VinFastBattery_latest.apk
        if ($apk.Name -match 'app-release.apk' -or $apk.Name -match 'app-arm64-v8a-release.apk') {
            $latestTarget = Join-Path $webApkDir "VinFastBattery_latest.apk"
            Copy-Item -Path $apk.FullName -Destination $latestTarget -Force
            Write-Ok "Da sao chep vao web server: $latestTarget"
        }
    }

    Write-Host "`n============================================" -ForegroundColor Green
    Write-Host "  BUILD APK THANH CONG!" -ForegroundColor Green
    Write-Host "  File APK da duoc tao va san sang de cai dat." -ForegroundColor Green
    Write-Host "============================================" -ForegroundColor Green
} finally {
    Pop-Location
}
