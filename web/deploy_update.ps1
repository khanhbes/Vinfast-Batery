<#
  deploy_update.ps1 — Cập nhật VinFast Battery lên VPS
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
$SRC  = "$PSScriptRoot"
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
                UpServices    = @('ai', 'api', 'dashboard')
                HealthTargets = @('vinfast_ai', 'vinfast_api')
            }
        }
        'ai' {
            return @{
                BuildServices = @('ai', 'api')
                UpServices    = @('ai', 'api', 'dashboard')
                HealthTargets = @('vinfast_ai', 'vinfast_api')
            }
        }
        'api' {
            return @{
                BuildServices = @('api')
                UpServices    = @('api', 'dashboard')
                HealthTargets = @('vinfast_api')
            }
        }
        'dashboard' {
            return @{
                BuildServices = @('dashboard')
                UpServices    = @('api', 'dashboard')
                HealthTargets = @('vinfast_api')
            }
        }
        default {
            throw "Service '$RequestedService' không hợp lệ. Dùng: api | ai | dashboard | all"
        }
    }
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  VinFast Battery — Deploy Update" -ForegroundColor Cyan
Write-Host "  VPS: $VpsIp | Service: $Service" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# ── BƯỚC 1: Tạo ZIP (loại trừ .venv, node_modules, __pycache__) ──
Write-Host "📦 Đang nén source code..." -ForegroundColor Yellow
if (Test-Path $ZIP) { Remove-Item $ZIP -Force }

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zipArchive = [System.IO.Compression.ZipFile]::Open($ZIP, 'Create')
Get-ChildItem -Path $SRC -Recurse -File | Where-Object {
    $_.FullName -notmatch '\\\.venv\\|\\node_modules\\|\\__pycache__\\|\\.git\\|\\dist\\|\.pyc$|\.log$|\.zip$'
} | ForEach-Object {
    $entry = $_.FullName.Substring($SRC.Length + 1)
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

$remoteCmd = @"
set -e
cd $VpsPath
unzip -o vinfast_web.zip -d web/ > /dev/null
cd web
docker compose --env-file .env build $buildFlags $buildServices 2>&1 | tail -10
docker compose --env-file .env up -d $upServices
docker compose ps

for name in $healthTargets; do
  status=""
  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    status=`$(docker inspect --format '{{.State.Status}}|{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "`$name" 2>/dev/null || true)
    if echo "`$status" | grep -Eq '^running\|(healthy|none)$'; then
      break
    fi
    sleep 3
  done
  echo "`$name => `$status"
  if ! echo "`$status" | grep -Eq '^running\|(healthy|none)$'; then
    echo "Deployment check failed for `$name"
    exit 1
  fi
done

dashboard_status=`$(docker inspect --format '{{.State.Status}}' vinfast_dashboard 2>/dev/null || true)
echo "vinfast_dashboard => `$dashboard_status"
if [ "`$dashboard_status" != "running" ]; then
  echo "Deployment check failed for vinfast_dashboard"
  exit 1
fi

for attempt in 1 2 3 4 5 6 7 8 9 10; do
  if curl -fsS http://127.0.0.1/api/health > /tmp/vinfast_api_health.json; then
    cat /tmp/vinfast_api_health.json
    break
  fi
  sleep 3
done
if [ ! -s /tmp/vinfast_api_health.json ]; then
  echo 'Deployment check failed: /api/health is not reachable through dashboard nginx'
  exit 1
fi
"@

Write-Host "   (SSH có thể mất 3-5 phút, vui lòng chờ...)" -ForegroundColor Gray
ssh -o ServerAliveInterval=30 -o ServerAliveCountMax=10 "${VpsUser}@${VpsIp}" $remoteCmd

# ── BƯỚC 4: Kiểm tra ──────────────────────────────────────────
Write-Host ""
Write-Host "🔍 Kiểm tra API..." -ForegroundColor Yellow
Start-Sleep -Seconds 3
try {
    $res = Invoke-WebRequest -Uri "http://${VpsIp}/api/health" -TimeoutSec 10 -UseBasicParsing
    Write-Host "   ✅ API OK: $($res.StatusCode)" -ForegroundColor Green
} catch {
    Write-Host "   ⚠ API chưa phản hồi (có thể đang khởi động)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  ✅ Deploy xong!" -ForegroundColor Green
Write-Host "  🌐 Dashboard: http://$VpsIp" -ForegroundColor Green
Write-Host "  🔌 API:       http://$VpsIp/api/health" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
