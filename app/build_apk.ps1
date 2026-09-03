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
    [switch]$NoDeploy,  # Không publish APK lên laptop server sau build
    [switch]$Offline,   # Dùng pub cache/lock hiện có, không gọi pub.dev
    [switch]$SkipChecks, # Chỉ dùng khi toolchain Flutter bị kẹt; không dùng cho deploy
    [string]$ApiUrl    = 'https://khanhbes.tailaafca5.ts.net',
    [string]$AdminKey  = $env:VINFAST_ADMIN_KEY, # Nếu trống, đọc DEV_ADMIN_KEY từ web/.env.laptop
    [string]$ReleaseNotes = '',         # Ghi chú phiên bản, có thể truyền khi chạy
    [switch]$ForceUpdate,                # Đánh dấu bản này là bắt buộc cập nhật
    [int]$MinSupportedBuild = 0          # 0 = giữ policy hiện tại; >0 = cập nhật build tối thiểu
) 

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $projectDir
$laptopWebDir = Join-Path (Split-Path -Parent $projectDir) 'web'

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
$oldPubspecContent = $pubspec
$oldConstContent = $null
$script:versionChanged = $false

# Resolve the SDK itself instead of a PATH/WindowsApps shim. On some Windows
# installations `Get-Command flutter` resolves to an inaccessible alias and
# fails before Flutter can print a diagnostic. Calling flutter_tools.snapshot
# through the SDK's dart.exe is the same tool entry point without that shim.
$flutterRoots = @()
if (-not [string]::IsNullOrWhiteSpace($env:FLUTTER_ROOT)) {
    $flutterRoots += $env:FLUTTER_ROOT
}
$flutterRoots += 'C:\flutter'
if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
    $flutterRoots += Join-Path $env:LOCALAPPDATA 'flutter'
}

$flutterDart = $null
$flutterSnapshot = $null
foreach ($root in $flutterRoots) {
    if ([string]::IsNullOrWhiteSpace($root)) { continue }
    $dartCandidate = Join-Path $root 'bin\cache\dart-sdk\bin\dart.exe'
    $snapshotCandidate = Join-Path $root 'bin\cache\flutter_tools.snapshot'
    if ((Test-Path $dartCandidate) -and (Test-Path $snapshotCandidate)) {
        $flutterDart = (Get-Item $dartCandidate).FullName
        $flutterSnapshot = (Get-Item $snapshotCandidate).FullName
        $env:FLUTTER_ROOT = (Get-Item $root).FullName
        $env:Path = "$(Join-Path $env:FLUTTER_ROOT 'bin');$env:Path"
        Write-Host "  Su dung Flutter SDK: $env:FLUTTER_ROOT" -ForegroundColor DarkGray
        break
    }
}
if ($null -eq $flutterDart -or $null -eq $flutterSnapshot) {
    throw 'Khong tim thay Flutter SDK day du. Dat FLUTTER_ROOT hoac cai Flutter tai C:\flutter.'
}

$env:CI = 'true'
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
function Invoke-Flutter {
    & $flutterDart $flutterSnapshot @args
    if ($LASTEXITCODE -ne 0) { throw "Flutter command that bai (exit $LASTEXITCODE): $($args -join ' ')" }
}

# Ctrl-C/terminating errors can arrive while Gradle is running. Keep version
# metadata transactional so an interrupted build never leaves a phantom
# release advertised to the updater.
function Restore-VersionMetadata {
    if (-not $script:versionChanged) { return }
    Set-Content 'pubspec.yaml' -Value $oldPubspecContent -NoNewline
    if ($null -ne $oldConstContent -and (Test-Path $constFile)) {
        Set-Content $constFile -Value $oldConstContent -NoNewline
    }
    $script:versionChanged = $false
    Write-Host "Da rollback version do build bi ngat/that bai." -ForegroundColor Yellow
}

trap {
    Write-Host "BUILD ERROR: $_" -ForegroundColor Red
    Restore-VersionMetadata
    exit 1
}

# ── 2. Preflight trước khi chạm vào version ──
# Một build lỗi không được quảng bá version mới. Analyze và tests luôn chạy
# trước bước bump để metadata auto-update chỉ trỏ tới artifact đã kiểm chứng.
if ($ApiUrl -notmatch '^https://') {
    throw 'Release API bat buoc dung HTTPS. Hay truyen -ApiUrl https://...'
}
if ($NoDeploy) {
    Write-Host "[CHECK] Bo qua release health (-NoDeploy); van chay analyze/test/build." -ForegroundColor DarkGray
} else {
  $healthOk = $false
  $healthError = $null
  for ($attempt = 1; $attempt -le 3 -and -not $healthOk; $attempt++) {
    try {
        # Invoke-RestMethod avoids the retired IE parser in Windows PowerShell
        # 5.1 and is retried because the production endpoint can briefly flap
        # during deploy/instance wake-up.
        $health = Invoke-RestMethod -Uri "$ApiUrl/api/health" -Method GET -TimeoutSec 15 -ErrorAction Stop
        if ($null -eq $health -or $health.status -ne 'ok') {
            throw "API health khong tra status=ok"
        }
        $healthOk = $true
    } catch {
        $healthError = $_
        if ($attempt -lt 3) { Start-Sleep -Seconds 2 }
    }
  }
  if (-not $healthOk) {
    # On some Windows installations powershell.exe 5.1 has a different TLS/
    # proxy stack than the installed pwsh 7 used by the developer toolchain.
    # Use it as a compatibility probe before failing the release gate.
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($null -ne $pwsh) {
        $safeHealthUrl = ("$ApiUrl/api/health").Replace("'", "''")
        & $pwsh.Source -NoProfile -NonInteractive -Command `
            "try { `$r=Invoke-RestMethod -Uri '$safeHealthUrl' -TimeoutSec 15 -ErrorAction Stop; if (`$null -eq `$r -or `$r.status -ne 'ok') { exit 2 } } catch { exit 1 }"
        if ($LASTEXITCODE -eq 0) { $healthOk = $true }
    }
  }
  if (-not $healthOk) {
    throw "Release API HTTPS chua san sang: $ApiUrl/api/health — $healthError"
  }
}

Write-Host "`n[CHECK] Dong bo dependencies..." -ForegroundColor Cyan
$LASTEXITCODE = 0
if ($NoDeploy -and (Test-Path '.dart_tool\package_config.json')) {
    Write-Host "  Pub da resolve; dung package_config local (-NoDeploy)" -ForegroundColor DarkGray
} elseif ($Offline -or $NoDeploy) {
    Write-Host "  Pub offline (cache/lock local)" -ForegroundColor DarkGray
    Invoke-Flutter pub get --offline
} else {
    Invoke-Flutter pub get
}
if ($LASTEXITCODE -ne 0) { throw 'flutter pub get that bai.' }

if ($SkipChecks) {
    if (-not $NoDeploy) { throw '-SkipChecks chi duoc phep khi dung -NoDeploy.' }
    Write-Host "[CHECK] Bo qua analyze/test theo yeu cau (-SkipChecks)." -ForegroundColor Yellow
} else {
    Write-Host "[CHECK] Flutter analyze..." -ForegroundColor Cyan
    Invoke-Flutter analyze --no-pub --no-fatal-warnings --no-fatal-infos
    if ($LASTEXITCODE -ne 0) { throw 'flutter analyze that bai; version chua bi thay doi.' }

    Write-Host "[CHECK] Flutter tests..." -ForegroundColor Cyan
    Invoke-Flutter test --no-pub
    if ($LASTEXITCODE -ne 0) { throw 'flutter test that bai; version chua bi thay doi.' }
}

# Fail fast with an actionable message instead of letting Gradle hang or
# silently leave a bumped version when Java is unavailable. Android Studio's
# bundled JBR is a valid JDK 17 for Flutter builds, so discover it first.
$javaCommand = Get-Command java -ErrorAction SilentlyContinue
# Prefer a real JDK installation over a PATH shim (Android Studio's
# javapath entry can be present even when it is not executable). Resolve
# JAVA_HOME first whenever the caller did not explicitly provide one.
if ([string]::IsNullOrWhiteSpace($env:JAVA_HOME)) {
    $javaCandidates = @(
        (Join-Path ${env:ProgramFiles} 'Android\Android Studio\jbr'),
        (Join-Path ${env:ProgramFiles} 'Java\jdk-17'),
        (Join-Path ${env:ProgramFiles} 'Eclipse Adoptium\jdk-17*')
    )
    foreach ($candidate in $javaCandidates) {
        $resolved = Get-Item $candidate -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $resolved -and (Test-Path (Join-Path $resolved.FullName 'bin\java.exe'))) {
            $env:JAVA_HOME = $resolved.FullName
            $env:Path = "$(Join-Path $env:JAVA_HOME 'bin');$env:Path"
            $javaCommand = Get-Command java -ErrorAction SilentlyContinue
            Write-Host "  Su dung JDK tu: $env:JAVA_HOME" -ForegroundColor DarkGray
            break
        }
    }
}
if ($null -eq $javaCommand -and [string]::IsNullOrWhiteSpace($env:JAVA_HOME)) {
    throw 'Khong tim thay Java/JAVA_HOME. Cai JDK 17 va dat JAVA_HOME truoc khi build APK.'
}
if (-not [string]::IsNullOrWhiteSpace($env:JAVA_HOME) -and
    -not (Test-Path (Join-Path $env:JAVA_HOME 'bin\java.exe'))) {
    throw "JAVA_HOME khong hop le: $env:JAVA_HOME. Can JDK 17 co bin\java.exe."
}
$javaExePath = if (-not [string]::IsNullOrWhiteSpace($env:JAVA_HOME)) {
    Join-Path $env:JAVA_HOME 'bin\java.exe'
} elseif ($null -ne $javaCommand) {
    $javaCommand.Source
} else {
    $null
}
if ($javaExePath) {
    $javaReady = $false
    try {
        # Use Start-Process so PowerShell's native stderr/exit-code handling
        # cannot mistake the JBR `-version` diagnostic output for failure.
        # The resolved absolute path also avoids stale javapath shims.
        $javaProbe = Start-Process -FilePath $javaExePath -ArgumentList '-version' `
            -WindowStyle Hidden -Wait -PassThru -RedirectStandardError "$env:TEMP\vinfast-java-probe.err"
        $javaReady = ($javaProbe.ExitCode -eq 0)
        Remove-Item -LiteralPath "$env:TEMP\vinfast-java-probe.err" -Force -ErrorAction SilentlyContinue
    } catch {
        $javaReady = $false
    }
    if (-not $javaReady) {
        throw "Java khong the chay duoc tu JAVA_HOME; cai lai JDK 17 truoc khi build APK."
    }
}

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
    $oldConstContent = $constContent
    $constContent = $constContent -replace "appVersion\s*=\s*'[^']+'", "appVersion = '$newSemver'"
    Set-Content $constFile -Value $constContent -NoNewline
}
$script:versionChanged = $true
Write-Host "Da cap nhat pubspec.yaml va app_constants.dart" -ForegroundColor Green

# ── 6. Flutter clean (CHỈ khi -Clean được truyền) ──
if ($Clean) {
    Write-Host "`n[CLEAN] Dang chay flutter clean..." -ForegroundColor Yellow
    Invoke-Flutter clean
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
    Invoke-Flutter build apk --release --no-pub --dart-define=APP_API_BASE_URL=$ApiUrl
} elseif ($AllAbi) {
    Write-Host "`nDang build APK split 3 ABI (release)..." -ForegroundColor Cyan
    Invoke-Flutter build apk --release --split-per-abi --no-pub --dart-define=APP_API_BASE_URL=$ApiUrl
} else {
    Write-Host "`nDang build APK arm64-v8a only (release)..." -ForegroundColor Cyan
    Invoke-Flutter build apk --release --split-per-abi --target-platform android-arm64 --no-pub --dart-define=APP_API_BASE_URL=$ApiUrl
}

if ($LASTEXITCODE -ne 0) {
    Write-Host "`nBuild THAT BAI!" -ForegroundColor Red
    Set-Content 'pubspec.yaml' -Value $oldPubspecContent -NoNewline
    if ($null -ne $oldConstContent) { Set-Content $constFile -Value $oldConstContent -NoNewline }
    Write-Host "Da rollback version vi build that bai." -ForegroundColor Yellow
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
    Set-Content 'pubspec.yaml' -Value $oldPubspecContent -NoNewline
    if ($null -ne $oldConstContent) { Set-Content $constFile -Value $oldConstContent -NoNewline }
    Write-Host "Da rollback version vi khong co artifact." -ForegroundColor Yellow
    exit 1
}
$script:versionChanged = $false

# ── 9. Thời gian build ──
$elapsed = [math]::Round(((Get-Date) - $buildStart).TotalMinutes, 1)
Write-Host "`n=== BUILD THANH CONG — v$newVersion (${elapsed} phut) ===" -ForegroundColor Cyan
Write-Host "APK nam tai: $releaseDir`n" -ForegroundColor Yellow
Write-Host "[HUONG DAN] Cai dat len thiet bi:" -ForegroundColor DarkGray
Write-Host "  adb install releases\VinFastBattery_v$newSemver.apk" -ForegroundColor DarkGray

# ── 10. Publish APK through the local laptop server + update app_config ──
if (-not $NoDeploy) {
    Write-Host "`n--- Auto-publish APK len laptop server ---" -ForegroundColor Cyan

    # Tìm APK vừa build (ưu tiên arm64)
    $apkToDeploy = $null
    $arm64Apk = Join-Path $releaseDir "VinFastBattery_v$newSemver.apk"
    if (Test-Path $arm64Apk) { $apkToDeploy = $arm64Apk }

    if ($apkToDeploy) {
        $remoteApkName = "VinFastBattery_latest.apk"

        try {
            # apk_data is a bind volume to web/apk on this laptop. Copying here
            # lets the running API publish /api/app/download without SSH/VPS.
            $localApkDir = Join-Path $laptopWebDir 'apk'
            if (-not (Test-Path $localApkDir)) {
                New-Item -ItemType Directory -Path $localApkDir -Force | Out-Null
            }
            $publishedApk = Join-Path $localApkDir $remoteApkName
            Write-Host "  Publish APK locally ($([math]::Round((Get-Item $apkToDeploy).Length/1MB,1)) MB)..." -ForegroundColor Gray
            Copy-Item -LiteralPath $apkToDeploy -Destination $publishedApk -Force

            # Read the local API admin key from the ignored laptop environment
            # only when the caller has not supplied VINFAST_ADMIN_KEY.
            if ([string]::IsNullOrWhiteSpace($AdminKey)) {
                $laptopEnvFile = Join-Path $laptopWebDir '.env.laptop'
                if (Test-Path $laptopEnvFile) {
                    $devAdminLine = Get-Content -LiteralPath $laptopEnvFile |
                        Where-Object { $_ -match '^DEV_ADMIN_KEY=' } |
                        Select-Object -First 1
                    if ($devAdminLine) {
                        $AdminKey = ($devAdminLine -replace '^DEV_ADMIN_KEY=', '').Trim()
                    }
                }
            }
            if ([string]::IsNullOrWhiteSpace($AdminKey)) {
                throw 'Khong tim thay VINFAST_ADMIN_KEY hay DEV_ADMIN_KEY trong web/.env.laptop.'
            }

            # Update the public metadata through the running local API.
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
    Write-Host "`n[SKIP] Bo qua publish APK (-NoDeploy)" -ForegroundColor DarkGray
}
