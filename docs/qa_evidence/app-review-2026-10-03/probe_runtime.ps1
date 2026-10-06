#requires -Version 7.0

param(
    [ValidateSet('Status', 'Launch', 'Snapshot', 'Events')]
    [string]$Action = 'Status',
    [string]$Serial = 'emulator-5554',
    [int]$TimeoutSeconds = 25
)

# Read-only QA probe except explicitly opening the installed Activity.
# Never output raw hierarchy, logcat, field values, credentials or response bodies.
$ErrorActionPreference = 'Stop'
$qaAdbPath = 'C:\Users\khanh\AppData\Local\Android\Sdk\platform-tools\adb.exe'

function Invoke-QaAdb([string[]]$Arguments) {
    $qaInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $qaInfo.FileName = $qaAdbPath
    $qaInfo.UseShellExecute = $false
    $qaInfo.CreateNoWindow = $true
    $qaInfo.RedirectStandardOutput = $true
    $qaInfo.RedirectStandardError = $true
    foreach ($qaArgument in (@('-s', $Serial) + $Arguments)) {
        $qaInfo.ArgumentList.Add($qaArgument)
    }
    $qaCall = [System.Diagnostics.Process]::new()
    $qaCall.StartInfo = $qaInfo
    try {
        [void]$qaCall.Start()
        $qaOutTask = $qaCall.StandardOutput.ReadToEndAsync()
        $qaErrTask = $qaCall.StandardError.ReadToEndAsync()
        if (-not $qaCall.WaitForExit($TimeoutSeconds * 1000)) {
            $qaCall.Kill()
            $qaCall.WaitForExit()
            return @{ TimedOut = $true; ExitCode = $null; Output = '' }
        }
        return @{ TimedOut = $false; ExitCode = $qaCall.ExitCode; Output = $qaOutTask.GetAwaiter().GetResult() }
    } finally {
        $qaCall.Dispose()
    }
}

$qaResult = @{ Action = $Action; Serial = $Serial; RawPrivateDataStored = $false }
switch ($Action) {
    'Status' {
        $qaBoot = Invoke-QaAdb @('shell', 'getprop', 'sys.boot_completed')
        $qaResult.BootCompleted = $qaBoot.Output.Trim() -eq '1'
        $qaResult.TimedOut = $qaBoot.TimedOut
        $qaResult.ExitCode = $qaBoot.ExitCode
    }
    'Launch' {
        $qaLaunch = Invoke-QaAdb @('shell', 'am', 'start', '-W', '-n', 'com.bes.vinbatery/com.vinfast.vinfast_battery.MainActivity')
        $qaResult.ExitCode = $qaLaunch.ExitCode
        $qaResult.TimedOut = $qaLaunch.TimedOut
        $qaResult.ActivityStatus = if ($qaLaunch.Output -match 'Status: (\w+)') { $Matches[1] } else { 'unavailable' }
        $qaResult.WaitTimeMs = if ($qaLaunch.Output -match 'WaitTime: (\d+)') { [int]$Matches[1] } else { $null }
    }
    'Snapshot' {
        $qaDump = Invoke-QaAdb @('shell', '-tt', 'uiautomator', 'dump', '/dev/tty')
        $qaStart = $qaDump.Output.IndexOf('<?xml')
        $qaEnd = $qaDump.Output.IndexOf('</hierarchy>')
        $qaResult.TimedOut = $qaDump.TimedOut
        $qaResult.ExitCode = $qaDump.ExitCode
        $qaResult.HierarchyAvailable = $qaStart -ge 0 -and $qaEnd -gt $qaStart
        if ($qaResult.HierarchyAvailable) {
            [xml]$qaXml = $qaDump.Output.Substring($qaStart, $qaEnd - $qaStart + '</hierarchy>'.Length)
            $qaAllowed = @('Close app', 'Wait', 'Tổng quan', 'Sạc pin', 'Lịch sử', 'Thêm', 'Đăng nhập', 'Đăng ký', 'Quên mật khẩu?', 'Email', 'Mật khẩu', 'Thử lại', 'Bỏ qua', 'Tiếp tục', 'Hoàn tất', 'Hướng dẫn', 'Cài đặt', 'Kết nối Shelly', 'Sạc AI', 'Sạc hẹn giờ', 'Xem chi tiết', 'BẬT SẠC', 'TẮT SẠC', 'Quay lại', 'Hủy', 'Đóng', 'Đăng xuất', 'Xe của tôi', 'Hành trình năng lượng', 'Bắt đầu thiết lập', 'Xem hướng dẫn')
            $qaNodes = @($qaXml.SelectNodes('//node'))
            $qaResult.NodeCount = $qaNodes.Count
            $qaResult.AppNodesPresent = @($qaNodes | Where-Object { $_.package -eq 'com.bes.vinbatery' }).Count -gt 0
            $qaResult.SafeControls = @(
                foreach ($qaNode in $qaNodes) {
                    $qaLabel = if ($qaNode.text -match 'VinFast Battery.*respond') { 'Application ANR' }
                    elseif ($qaNode.text -match '(com.android.phone|System UI).*respond') { 'Android service ANR' }
                    elseif ($qaAllowed -contains $qaNode.text) { $qaNode.text }
                    elseif ($qaAllowed -contains $qaNode.'content-desc') { $qaNode.'content-desc' }
                    else { $null }
                    if ($qaLabel) {
                        @{ Label = $qaLabel; Bounds = $qaNode.bounds; Clickable = $qaNode.clickable -eq 'true'; Enabled = $qaNode.enabled -eq 'true' }
                    }
                }
            )
        }
    }
    'Events' {
        $qaEvents = Invoke-QaAdb @('logcat', '-b', 'events', '-d')
        $qaLines = @($qaEvents.Output -split "`n")
        $qaResult.ExitCode = $qaEvents.ExitCode
        $qaResult.TimedOut = $qaEvents.TimedOut
        $qaResult.ObservationAvailable = $qaEvents.ExitCode -eq 0 -and -not $qaEvents.TimedOut
        if ($qaResult.ObservationAvailable) {
            $qaResult.AppAnrCount = @($qaLines | Where-Object { $_ -match 'am_anr' -and $_ -match 'com.bes.vinbatery' }).Count
            $qaResult.OtherAndroidAnrCount = @($qaLines | Where-Object { $_ -match 'am_anr' -and $_ -notmatch 'com.bes.vinbatery' }).Count
            $qaResult.AppCrashCount = @($qaLines | Where-Object { $_ -match 'am_crash' -and $_ -match 'com.bes.vinbatery' }).Count
        } else {
            $qaResult.AppAnrCount = $null
            $qaResult.OtherAndroidAnrCount = $null
            $qaResult.AppCrashCount = $null
        }
    }
}
$qaResult | ConvertTo-Json -Depth 5 -Compress
