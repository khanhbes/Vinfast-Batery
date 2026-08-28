<#
  deploy_update.ps1 - Cập nhật VinFast Battery lên VPS
  Chạy: .\deploy_update.ps1
  Chỉ rebuild dashboard: .\deploy_update.ps1 -Service dashboard
  Chỉ rebuild api:       .\deploy_update.ps1 -Service api
#>
param(
    [string]$Service = "all",   # all | dashboard | api | ai
    [string]$VpsIp   = "167.71.207.121",
    [string]$VpsUser = "root",
    [string]$VpsPath = "/opt/vinfast",
    [switch]$NoCache             # Force rebuild without Docker cache
)

$ErrorActionPreference = "Stop"
$SRC  = if ($PSScriptRoot) { $PSScriptRoot } else { "." }
$ZIP  = "$env:TEMP\vinfast_web_update.zip"
$DEST = "${VpsUser}@${VpsIp}:${VpsPath}/"

function Join-ServiceList([string[]]$Services) {
    return ($Services | Where-Object { $_ } | Select-Object -Unique) -join ' '
}

function Get-DeployPlan([string]$RequestedService) {
    switch ($RequestedService) {
        'all' {
            return @{
                BuildServices = @('ai', 'api', 'dashboard')
                UpServices    = @('ai', 'api', 'dashboard', 'caddy')
                HealthTargets = @('vinfast_ai', 'vinfast_api', 'vinfast_caddy')
            }
        }
        'ai' {
            return @{
                BuildServices = @('ai', 'api')
                UpServices    = @('ai', 'api', 'dashboard', 'caddy')
                HealthTargets = @('vinfast_ai', 'vinfast_api', 'vinfast_caddy')
            }
        }
        'api' {
            return @{
                BuildServices = @('api')
                UpServices    = @('api', 'dashboard', 'caddy')
                HealthTargets = @('vinfast_api', 'vinfast_caddy')
            }
        }
        'dashboard' {
            return @{
                BuildServices = @('dashboard')
                UpServices    = @('api', 'dashboard', 'caddy')
                HealthTargets = @('vinfast_api', 'vinfast_caddy')
            }
        }
        default {
            throw "Service '$RequestedService' không hợp lệ. Dùng: api | ai | dashboard | all"
        }
    }
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  VinFast Battery - Deploy Update" -ForegroundColor Cyan
Write-Host "  VPS: $VpsIp | Service: $Service" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# ── BƯỚC 1: Tạo ZIP (loại trừ .venv, node_modules, __pycache__) ──
Write-Host "📦 Đang nén source code..." -ForegroundColor Yellow
if (Test-Path $ZIP) { Remove-Item $ZIP -Force }

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zipArchive = [System.IO.Compression.ZipFile]::Open($ZIP, 'Create')
Get-ChildItem -Path $SRC -Recurse -File | Where-Object {
    $_.FullName -notmatch '\\.venv\\|\\node_modules\\|\\__pycache__\\|\\.git\\|\\dist\\|\\.pyc$|\\.log$|\\.zip$'
} | ForEach-Object {
    # Use forward slashes so Linux `unzip` extracts into proper subdirectories
    # (Windows backslashes cause "appears to use backslashes as path separators"
    # warning and files land with wrong names, breaking Docker builds)
    $entry = $_.FullName.Substring($SRC.Length + 1).Replace('\', '/')
    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zipArchive, $_.FullName, $entry) | Out-Null
}
$zipArchive.Dispose()
$sizeMB = [math]::Round((Get-Item $ZIP).Length / 1MB, 1)
Write-Host "   ✅ Xong: $sizeMB MB" -ForegroundColor Green

# ── BƯỚC 2: Upload ZIP lên VPS ────────────────────────────────
Write-Host ""
Write-Host "📤 Đang upload lên VPS ($VpsIp)..." -ForegroundColor Yellow
scp $ZIP "${VpsUser}@${VpsIp}:${VpsPath}/vinfast_web.zip"
Write-Host "   ✅ Upload xong" -ForegroundColor Green

# ── BƯỚC 3: Giải nén + Rebuild + Restart trên VPS ─────────────
Write-Host ""
Write-Host "🔨 Đang rebuild và restart trên VPS..." -ForegroundColor Yellow

$plan = Get-DeployPlan $Service
$buildServices = Join-ServiceList $plan.BuildServices
$upServices = Join-ServiceList $plan.UpServices
$healthTargets = Join-ServiceList $plan.HealthTargets
$buildFlags = if ($NoCache) { "--no-cache" } else { "" }

Write-Host "📤 Đang upload bash script..." -ForegroundColor Yellow
scp "$SRC\deploy_cmd.sh" "${VpsUser}@${VpsIp}:${VpsPath}/deploy_cmd.sh"

Write-Host "   (SSH có thể mất 3-5 phút, vui lòng chờ...)" -ForegroundColor Gray
ssh -o ServerAliveInterval=30 -o ServerAliveCountMax=10 "${VpsUser}@${VpsIp}" "dos2unix ${VpsPath}/deploy_cmd.sh 2>/dev/null || true; bash ${VpsPath}/deploy_cmd.sh '$buildFlags' '$buildServices' '$upServices' '$healthTargets'"

# ── BƯỚC 4: Kiểm tra ──────────────────────────────────────────
Write-Host ""
Write-Host "🔍 Kiểm tra API..." -ForegroundColor Yellow
Start-Sleep -Seconds 3
try {
    $res = Invoke-WebRequest -Uri "https://api.evbattery.live/api/health" -TimeoutSec 15 -UseBasicParsing
    Write-Host "   ✅ API OK: $($res.StatusCode)" -ForegroundColor Green
} catch {
    Write-Host "   ⚠ API chưa phản hồi (có thể đang khởi động)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  ✅ Deploy xong!" -ForegroundColor Green
Write-Host "  🌐 Dashboard: https://api.evbattery.live" -ForegroundColor Green
Write-Host "  🔌 API:       https://api.evbattery.live/api/health" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
