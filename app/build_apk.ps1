<#
  build_apk.ps1 — Auto tăng version + build APK split-per-abi
  Chạy: .\build_apk.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $projectDir

Write-Host "`n=== VinFast Battery — Build APK ===" -ForegroundColor Cyan

# ── 1. Đọc version hiện tại từ pubspec.yaml ──
$pubspec = Get-Content 'pubspec.yaml' -Raw
if ($pubspec -match 'version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)') {
    $major   = [int]$Matches[1]
    $minor   = [int]$Matches[2]
    $patch   = [int]$Matches[3]
    $build   = [int]$Matches[4]
} else {
    Write-Host "Khong tim thay version trong pubspec.yaml" -ForegroundColor Red
    exit 1
}

$oldVersion = "$major.$minor.$patch+$build"
Write-Host "Version hien tai: $oldVersion" -ForegroundColor Yellow

# ── 2. Tăng patch + build number ──
$patch++
$build++
$newVersion = "$major.$minor.$patch+$build"
$newSemver  = "$major.$minor.$patch"

Write-Host "Version moi:      $newVersion" -ForegroundColor Green

# ── 3. Cập nhật pubspec.yaml ──
$pubspec = $pubspec -replace "version:\s*\d+\.\d+\.\d+\+\d+", "version: $newVersion"
Set-Content 'pubspec.yaml' -Value $pubspec -NoNewline

# ── 4. Cập nhật app_constants.dart ──
$constFile = 'lib\core\constants\app_constants.dart'
$constContent = Get-Content $constFile -Raw
$constContent = $constContent -replace "appVersion\s*=\s*'[^']+'", "appVersion = '$newSemver'"
Set-Content $constFile -Value $constContent -NoNewline

Write-Host "Da cap nhat pubspec.yaml va app_constants.dart" -ForegroundColor Green

# ── 5. Flutter clean + build ──
Write-Host "`nDang chay flutter clean..." -ForegroundColor Cyan
flutter clean

Write-Host "`nDang chay flutter pub get..." -ForegroundColor Cyan
flutter pub get

Write-Host "`nDang build APK (split-per-abi, release)..." -ForegroundColor Cyan
flutter build apk --split-per-abi --release

if ($LASTEXITCODE -ne 0) {
    Write-Host "`nBuild THAT BAI!" -ForegroundColor Red
    exit 1
}

# ── 6. Copy APK ra thư mục releases với tên có version ──
$releaseDir = Join-Path $projectDir 'releases'
if (!(Test-Path $releaseDir)) {
    New-Item -ItemType Directory -Path $releaseDir | Out-Null
}

$apkSource = 'build\app\outputs\flutter-apk'
$timestamp = Get-Date -Format 'yyyyMMdd_HHmm'

$apkFiles = Get-ChildItem "$apkSource\*.apk" -ErrorAction SilentlyContinue
foreach ($apk in $apkFiles) {
    $newName = $apk.BaseName -replace 'app', "VinFastBattery_v$newSemver"
    $dest = Join-Path $releaseDir "$newName`_$timestamp.apk"
    Copy-Item $apk.FullName $dest
    Write-Host "  -> $dest" -ForegroundColor Green
}

Write-Host "`n=== BUILD THANH CONG — v$newVersion ===" -ForegroundColor Cyan
Write-Host "APK nam tai: $releaseDir`n" -ForegroundColor Yellow
