<#
.SYNOPSIS
  Remove reproducible local build and test-cache artifacts.

.DESCRIPTION
  Dry-run by default. Use -Apply to remove the safe build/test targets.
  Dependencies are intentionally preserved by default so an IDE keeps its
  package graph. Use -Dependencies for a deep dependency cleanup and add
  -RestoreDependencies to rebuild Flutter, Node and Python environments.
  Credentials, runtime databases, APK archives and model files are always
  outside the allow-list.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Apply,
    [switch]$Dependencies,
    [switch]$RestoreDependencies
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

$relativeTargets = @(
    'app/build',
    'web/dashboard/dist',
    'web/dashboard/.playwright-cli',
    'web/.pytest-temp',
    'web/.pytest_cache',
    'web/dashboard/.pytest_cache',
    'web/__pycache__',
    '.pytest_cache'
)

# Dependency folders are opt-in. Removing these while the IDE is open causes
# thousands of false Dart/TypeScript diagnostics until the graph is restored.
if ($Dependencies -or $RestoreDependencies) {
    $relativeTargets += @(
        'app/.dart_tool',
        'app/android/.gradle',
        'web/.venv',
        'web/dashboard/node_modules'
    )
}

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
    if ($Dependencies -or $RestoreDependencies) {
        Write-Warning 'Dependency cleanup is enabled. The IDE will lose package graphs until dependencies are restored.'
    }
    if ($RestoreDependencies) {
        Write-Host 'RestoreDependencies is planned but not run during dry-run.' -ForegroundColor Cyan
    }
    exit 0
}

if ($RestoreDependencies) {
    $restoreFailures = [System.Collections.Generic.List[string]]::new()

    function Invoke-RestoreStep {
        param(
            [Parameter(Mandatory = $true)][string]$Name,
            [Parameter(Mandatory = $true)][string]$WorkingDirectory,
            [Parameter(Mandatory = $true)][scriptblock]$Command
        )
        Write-Host "Restoring $Name..." -ForegroundColor Cyan
        Push-Location $WorkingDirectory
        try {
            & $Command
            if ($LASTEXITCODE -ne 0) {
                throw "exit code $LASTEXITCODE"
            }
            Write-Host "Restored $Name" -ForegroundColor Green
        } catch {
            $script:restoreFailures.Add("${Name}: $($_.Exception.Message)")
            Write-Warning "Could not restore ${Name}: $($_.Exception.Message)"
        } finally {
            Pop-Location
        }
    }

    $appPath = Join-Path $root 'app'
    if (Get-Command flutter -ErrorAction SilentlyContinue) {
        Invoke-RestoreStep -Name 'Flutter packages (offline first)' -WorkingDirectory $appPath -Command {
            flutter pub get --offline
            if ($LASTEXITCODE -ne 0) { flutter pub get }
        }
    } else {
        $restoreFailures.Add('Flutter: flutter executable was not found on PATH')
    }

    $dashboardPath = Join-Path $root 'web/dashboard'
    $npm = Get-Command npm.cmd -ErrorAction SilentlyContinue
    if (-not $npm) { $npm = Get-Command npm -ErrorAction SilentlyContinue }
    if ($npm) {
        Invoke-RestoreStep -Name 'dashboard Node packages' -WorkingDirectory $dashboardPath -Command {
            & $npm.Source ci --prefer-offline --no-audit --fund=false
        }
    } else {
        $restoreFailures.Add('Dashboard: npm executable was not found on PATH')
    }

    $python = Get-Command python -ErrorAction SilentlyContinue
    $requirements = Join-Path $root 'web/requirements.txt'
    if ($python -and (Test-Path -LiteralPath $requirements)) {
        Invoke-RestoreStep -Name 'Python environment' -WorkingDirectory $root -Command {
            python -m venv web/.venv
            $venvPython = Join-Path $root 'web/.venv/Scripts/python.exe'
            if (-not (Test-Path -LiteralPath $venvPython)) {
                $venvPython = Join-Path $root 'web/.venv/bin/python'
            }
            & $venvPython -m pip install -r web/requirements.txt
        }
    } elseif (-not $python) {
        $restoreFailures.Add('Python: python executable was not found on PATH')
    }

    if ($restoreFailures.Count -gt 0) {
        Write-Error ('Dependency restore incomplete: ' + ($restoreFailures -join '; '))
        exit 1
    }

    Write-Host 'Dependency restore completed. Restart the IDE/analyzer if it was open during cleanup.' -ForegroundColor Green
}
