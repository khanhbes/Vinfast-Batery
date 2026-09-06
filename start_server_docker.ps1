<#
.SYNOPSIS
  Build and deploy the local VinFast Battery stack through Tailscale Funnel.

.EXAMPLE
  .\deploy_web.ps1
  .\deploy_web.ps1 -Service api
  .\deploy_web.ps1 -NoCache
#>
[CmdletBinding()]
param(
    [ValidateSet('all', 'api', 'ai', 'dashboard')]
    [string]$Service = 'all',
    [string]$PublicUrl = 'https://khanhbes.tailaafca5.ts.net',
    [switch]$NoCache
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$rootDir = $PSScriptRoot
$webDir = Join-Path $rootDir 'web'
if (-not (Test-Path (Join-Path $webDir '.env.laptop'))) {
    throw "Không tìm thấy web/.env.laptop. Sao chép web/.env.laptop.example và điền secret local trước."
}

function Write-Step([string]$message) { Write-Host "`n▶ $message" -ForegroundColor Cyan }
function Write-Ok([string]$message) { Write-Host "  ✅ $message" -ForegroundColor Green }

Write-Host '============================================' -ForegroundColor Cyan
Write-Host ' VinFast Battery — Deploy Laptop / Tailscale' -ForegroundColor Cyan
Write-Host " Service: $Service" -ForegroundColor Cyan
Write-Host '============================================' -ForegroundColor Cyan

& docker info *> $null
if ($LASTEXITCODE -ne 0) { throw 'Docker Desktop chưa chạy.' }

$compose = @('--env-file', '.env.laptop', '-f', 'docker-compose.yml', '-f', 'docker-compose.laptop.yml')
$buildServices = switch ($Service) {
    'api' { @('api') }
    'ai' { @('ai') }
    'dashboard' { @('dashboard') }
    default { @('ai', 'api', 'dashboard') }
}
$upServices = switch ($Service) {
    'api' { @('api', 'dashboard', 'laptop_gateway') }
    'dashboard' { @('api', 'dashboard', 'laptop_gateway') }
    default { @('ai', 'api', 'dashboard', 'laptop_gateway') }
}

Push-Location $webDir
try {
    foreach ($item in $buildServices) {
        Write-Step "Build image $item"
        $buildArgs = @('build')
        if ($NoCache) { $buildArgs += '--no-cache' }
        $buildArgs += $item
        & docker compose @compose @buildArgs
        if ($LASTEXITCODE -ne 0) { throw "Build $item thất bại." }
    }

    Write-Step "Khởi động: $($upServices -join ', ')"
    & docker compose @compose up -d --force-recreate @upServices
    if ($LASTEXITCODE -ne 0) { throw 'Khởi động Docker services thất bại.' }

    Write-Step 'Kích hoạt Tailscale Funnel cổng 8080'
    & tailscale funnel --bg 8080
    if ($LASTEXITCODE -ne 0) { throw 'Không thể bật Tailscale Funnel. Chạy PowerShell với quyền Administrator và kiểm tra Tailscale.' }

    $healthUrl = "$($PublicUrl.TrimEnd('/'))/api/health"
    Write-Step "Kiểm tra $healthUrl"
    Invoke-RestMethod -Uri $healthUrl -TimeoutSec 20 -ErrorAction Stop | Out-Null
    Write-Ok 'API public hoạt động qua Tailscale Funnel'
} finally {
    Pop-Location
}

Write-Host "`nDashboard: $PublicUrl" -ForegroundColor Green
Write-Host "API:       $($PublicUrl.TrimEnd('/'))/api/health" -ForegroundColor Green
