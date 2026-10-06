#requires -Version 7.0
param([int]$MonitorSeconds = 300)

$ErrorActionPreference = 'Stop'
$qaWorkspace = 'C:\Users\khanh\OneDrive\Desktop\Vinfast Batery'
$qaSdk = 'C:\Users\khanh\AppData\Local\Android\Sdk'
$qaArtifact = Join-Path $qaWorkspace 'app\build\app\outputs\flutter-apk\VinFastBattery_1.1.9+126_debug.apk'
$qaExpectedHash = '5A0EF61FD5F143AE9685B1DB4481FCDBF2DB7E280011F88608B1EABF5F660639'
if ((Get-FileHash -LiteralPath $qaArtifact -Algorithm SHA256).Hash -ne $qaExpectedHash) {
    throw 'QA artifact hash mismatch; no emulator started.'
}
if (@(Get-Process -Name emulator,qemu-system-x86_64 -ErrorAction SilentlyContinue).Count) {
    throw 'Another emulator is running; no second emulator started.'
}
$env:ANDROID_AVD_HOME = Join-Path $qaWorkspace 'app\build\qa-avd-20261005'
$qaStamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')
$qaOut = Join-Path $qaWorkspace "app\build\qa-software-$qaStamp-out.log"
$qaErr = Join-Path $qaWorkspace "app\build\qa-software-$qaStamp-err.log"
$qaArgs = @('-avd','VinFast_QA_API36_20261005','-port','5556',
    '-memory','1536','-cores','2','-skin','720x1600','-gpu','software',
    '-feature','-Vulkan','-no-snapshot','-no-boot-anim','-no-audio')
# The visible window is intentional: the user must approve ADB and enter QA login.
$qaLauncher = Start-Process -FilePath (Join-Path $qaSdk 'emulator\emulator.exe') `
    -ArgumentList $qaArgs -WindowStyle Normal -RedirectStandardOutput $qaOut `
    -RedirectStandardError $qaErr -PassThru
$qaResult = [ordered]@{
    StartedUtc = [DateTime]::UtcNow.ToString('o')
    Gpu = 'software'
    GuestRamMB = 1536
    CpuCores = 2
    ArtifactSha256 = $qaExpectedHash
    LauncherPid = $qaLauncher.Id
    QemuPid = $null
    StdoutLog = $qaOut
    StderrLog = $qaErr
    MonitorSeconds = $MonitorSeconds
    LauncherExitCode = $null
    QemuExitCode = $null
    ProcessExitObserved = $false
    AppOrHardwareCommandsSent = 0
    WipeData = $false
    RawCredentialsOrMemoryDumpStored = $false
}
$qaResult | ConvertTo-Json -Compress
$qaWatch = [System.Diagnostics.Stopwatch]::StartNew()
$qaQemu = $null
$qaNextOutput = 0
while ($qaWatch.Elapsed.TotalSeconds -lt $MonitorSeconds) {
    if (-not $qaQemu) {
        $qaChild = Get-CimInstance Win32_Process -Filter "Name='qemu-system-x86_64.exe'" |
            Where-Object { $_.ParentProcessId -eq $qaLauncher.Id } |
            Select-Object -First 1
        if ($qaChild) {
            $qaQemu = [System.Diagnostics.Process]::GetProcessById($qaChild.ProcessId)
            # Open the process handle now so its eventual exit code remains observable.
            $null = $qaQemu.Handle
            $qaResult.QemuPid = $qaQemu.Id
        }
    }
    if ($qaLauncher.HasExited -or ($qaQemu -and $qaQemu.HasExited)) {
        $qaResult.ProcessExitObserved = $true
        if ($qaLauncher.HasExited) { $qaResult.LauncherExitCode = $qaLauncher.ExitCode }
        if ($qaQemu -and $qaQemu.HasExited) { $qaResult.QemuExitCode = $qaQemu.ExitCode }
        break
    }
    if ($qaWatch.Elapsed.TotalSeconds -ge $qaNextOutput) {
        [ordered]@{ ElapsedSeconds = [int]$qaWatch.Elapsed.TotalSeconds;
            LauncherAlive = -not $qaLauncher.HasExited;
            QemuPid = $qaResult.QemuPid;
            QemuAlive = if ($qaQemu) { -not $qaQemu.HasExited } else { $null } } |
            ConvertTo-Json -Compress
        $qaNextOutput += 20
    }
    Start-Sleep -Seconds 2
}
$qaResult.EndedUtc = [DateTime]::UtcNow.ToString('o')
$qaResult.ElapsedSeconds = [int]$qaWatch.Elapsed.TotalSeconds
$qaResult | ConvertTo-Json -Compress
# Only a generated, secret-free diagnostic result is written; no app data is changed.
$qaResult | ConvertTo-Json -Depth 4 | Out-File -LiteralPath `
    (Join-Path $qaWorkspace "docs\qa_evidence\app-review-2026-10-05\software-$qaStamp-result.json") -Encoding utf8
# Do not kill or restart the emulator here. A boot failure requires an explicit decision.
