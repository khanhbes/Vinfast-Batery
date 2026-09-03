<#
  deploy.ps1 — Deploy VinFast Battery trên laptop qua Docker + Tailscale Funnel.

  Chạy toàn bộ:          .\deploy.ps1
  Chỉ API:                .\deploy.ps1 -Service api
  Chỉ AI:                 .\deploy.ps1 -Service ai
  Chỉ Dashboard:          .\deploy.ps1 -Service dashboard
  Không build image:      .\deploy.ps1 -SkipBuild
  Không thay Funnel:      .\deploy.ps1 -SkipFunnel

  Không dùng SSH, VPS hay DigitalOcean. Public HTTPS được cung cấp bởi
  Tailscale Funnel, còn Docker chỉ lắng nghe 127.0.0.1:8080.
#>
[CmdletBinding()]
param(
    [ValidateSet('api', 'ai', 'dashboard', 'all')]
    [string]$Service = 'all',
    [string]$PublicUrl = 'https://khanhbes.tailaafca5.ts.net',
    [switch]$SkipBuild,
    [switch]$SkipFunnel
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$rootDir = $PSScriptRoot
$webDir = Join-Path $rootDir 'web'
$envFile = Join-Path $webDir '.env.laptop'
$composeArgs = @('--env-file', '.env.laptop', '-f', 'docker-compose.yml', '-f', 'docker-compose.laptop.yml')

function Write-Step([string]$Message) {
    Write-Host "`n▶ $Message" -ForegroundColor Cyan
}

function Write-Ok([string]$Message) {
    Write-Host "  OK  $Message" -ForegroundColor Green
}

function Invoke-Compose([string[]]$Arguments) {
    & docker compose @composeArgs @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Docker Compose that bai: $($Arguments -join ' ')"
    }
}

function Test-Health([string]$Url, [int]$Attempts = 15) {
    $lastError = $null
    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        try {
            $result = Invoke-RestMethod -Uri $Url -Method GET -TimeoutSec 15 -ErrorAction Stop
            if ($result.status -eq 'ok') { return $result }
            $lastError = "status=$($result.status)"
        } catch {
            $lastError = $_.Exception.Message
        }
        if ($attempt -lt $Attempts) { Start-Sleep -Seconds 2 }
    }
    throw "Health check that bai: $Url — $lastError"
}

if (-not (Test-Path -LiteralPath $webDir)) {
    throw "Khong tim thay thu muc web: $webDir"
}
if (-not (Test-Path -LiteralPath $envFile)) {
    throw "Khong tim thay web/.env.laptop. Tao file nay theo web/.env.laptop.example truoc."
}

Write-Step 'Kiem tra Docker Desktop'
& docker info *> $null
if ($LASTEXITCODE -ne 0) {
    throw 'Docker Desktop chua chay. Hay mo Docker Desktop va cho trang thai Engine running.'
}
Write-Ok 'Docker Engine dang san sang'

Push-Location $webDir
try {
    $buildServices = switch ($Service) {
        'api' { @('api') }
        'ai' { @('ai') }
        'dashboard' { @('dashboard') }
        default { @('ai', 'api', 'dashboard') }
    }

    if (-not $SkipBuild) {
        # Build sequentially: laptop has limited Docker memory and concurrent
        # pip/npm builds can make BuildKit terminate unexpectedly.
        foreach ($buildService in $buildServices) {
            Write-Step "Build image $buildService"
            Invoke-Compose @('build', $buildService)
        }
    } else {
        Write-Host "`n[SKIP] Bo qua build image theo -SkipBuild" -ForegroundColor DarkGray
    }

    $upServices = switch ($Service) {
        'api' { @('api', 'dashboard', 'laptop_gateway') }
        'ai' { @('ai', 'api', 'dashboard', 'laptop_gateway') }
        'dashboard' { @('dashboard', 'laptop_gateway') }
        default { @('ai', 'api', 'dashboard', 'laptop_gateway') }
    }

    Write-Step "Khoi dong $($upServices -join ', ')"
    Invoke-Compose (@('up', '-d', '--force-recreate') + $upServices)

    Write-Step 'Kiem tra API local'
    $localHealth = Test-Health 'http://127.0.0.1:8080/api/health'
    Write-Ok "API local OK — Firebase: $($localHealth.firebaseConnected)"

    if (-not $SkipFunnel) {
        Write-Step 'Dam bao Tailscale Funnel dang bat'
        & tailscale funnel --bg 8080
        if ($LASTEXITCODE -ne 0) {
            throw 'Khong the bat Tailscale Funnel. Mo PowerShell Run as Administrator, sau do chay: tailscale funnel --bg 8080'
        }
        Write-Ok 'Tailscale Funnel dang proxy 127.0.0.1:8080'
    }

    Write-Step 'Kiem tra API public HTTPS'
    $publicHealth = Test-Health "$($PublicUrl.TrimEnd('/'))/api/health"
    Write-Ok "API public OK — version: $($publicHealth.version), Firebase: $($publicHealth.firebaseConnected)"

    Write-Step 'Trang thai containers'
    Invoke-Compose @('ps')

    Write-Host "`n============================================" -ForegroundColor Green
    Write-Host '  Deploy laptop hoan tat' -ForegroundColor Green
    Write-Host "  Dashboard: $PublicUrl" -ForegroundColor Green
    Write-Host "  API:       $($PublicUrl.TrimEnd('/'))/api/health" -ForegroundColor Green
    Write-Host '============================================' -ForegroundColor Green
} finally {
    Pop-Location
}
