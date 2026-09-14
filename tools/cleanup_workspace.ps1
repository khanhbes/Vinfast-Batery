<#
.SYNOPSIS
  Remove reproducible local build, dependency and test-cache artifacts.

.DESCRIPTION
  Dry-run by default. Use -Apply to remove only the allow-listed generated
  directories. Credentials, runtime databases, APK archives and model files
  are intentionally outside the allow-list.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

$relativeTargets = @(
    'app/build',
    'app/.dart_tool',
    'app/android/.gradle',
    'web/.venv',
    'web/dashboard/node_modules',
    'web/dashboard/dist',
    'web/dashboard/.playwright-cli',
    'web/.pytest-temp',
    'web/.pytest_cache',
    'web/dashboard/.pytest_cache',
    'web/__pycache__',
    '.pytest_cache'
)

$relativeTargets += @(Get-ChildItem -LiteralPath (Join-Path $root 'web') -Force -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like '.pytest-run-*' } |
    ForEach-Object { $_.FullName.Substring($root.Length + 1) })

foreach ($relative in $relativeTargets | Sort-Object -Unique) {
    $target = [IO.Path]::GetFullPath((Join-Path $root $relative))
    if (-not ($target.StartsWith($root + [IO.Path]::DirectorySeparatorChar))) {
        throw "Refusing target outside repository: $target"
    }

    if (-not (Test-Path -LiteralPath $target)) { continue }
    $files = @(Get-ChildItem -LiteralPath $target -Recurse -Force -File -ErrorAction SilentlyContinue)
    $bytes = [long](($files | Measure-Object Length -Sum).Sum)
    $size = '{0:N2} MB' -f ($bytes / 1MB)
    if ($Apply) {
        if ($PSCmdlet.ShouldProcess($target, 'Remove generated workspace artifact')) {
            Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "Removed $relative ($($files.Count) files, $size)" -ForegroundColor Green
        }
    } else {
        Write-Host "Would remove $relative ($($files.Count) files, $size)" -ForegroundColor Yellow
    }
}

if (-not $Apply) {
    Write-Host 'Dry-run only. Re-run with -Apply to remove the listed artifacts.' -ForegroundColor Cyan
}
