<#
  deploy.ps1 — Tự động deploy VinFast Battery lên VPS
  Chạy: .\deploy.ps1
  Chỉ api:       .\deploy.ps1 -Service api
  Chỉ ai:        .\deploy.ps1 -Service ai
  Chỉ dashboard: .\deploy.ps1 -Service dashboard
#>
param(
    [string]$Service = "all",              # api | ai | dashboard | all
    [string]$VpsIp   = "167.71.207.121",
    [string]$VpsUser = "root",
    [string]$VpsPath = "/opt/vinfast",
    [string]$KeyFile = "$env:USERPROFILE\.ssh\id_ed25519"
)

$ErrorActionPreference = "Stop"
$WebSrc = Join-Path $PSScriptRoot "web"
$ZIP    = "$env:TEMP\vinfast_deploy.zip"

# ── Màu sắc ──────────────────────────────────────────────────────
function Info($msg)    { Write-Host $msg -ForegroundColor Cyan }
function Ok($msg)      { Write-Host "  ✅ $msg" -ForegroundColor Green }
function Warn($msg)    { Write-Host "  ⚠ $msg" -ForegroundColor Yellow }
function Step($msg)    { Write-Host "`n▶ $msg" -ForegroundColor White }

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

# ── BƯỚC 0: Khởi động ssh-agent và add key (nhập passphrase 1 lần) ──
Step "Kiểm tra ssh-agent..."

$agentRunning = $false
try {
    $result = ssh-add -l 2>&1
    if ($LASTEXITCODE -eq 0) {
        $agentRunning = $true
        Ok "ssh-agent đã có key sẵn sàng"
    }
} catch {}

if (-not $agentRunning) {
    Info "Khởi động ssh-agent..."
    $agentOutput = ssh-agent -s 2>&1
    foreach ($line in $agentOutput) {
        if ($line -match 'SSH_AUTH_SOCK=([^;]+)') {
            $env:SSH_AUTH_SOCK = $Matches[1]
        }
        if ($line -match 'SSH_AGENT_PID=(\d+)') {
            $env:SSH_AGENT_PID = $Matches[1]
        }
    }
    # Start-Service nếu dùng OpenSSH agent của Windows
    try { Start-Service ssh-agent -ErrorAction SilentlyContinue } catch {}

    Info "Thêm SSH key — bạn sẽ nhập passphrase 1 lần duy nhất:"
    ssh-add $KeyFile
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Không thể add SSH key. Kiểm tra lại passphrase." -ForegroundColor Red
        exit 1
    }
    Ok "Key đã được add vào agent"
}

# ── BƯỚC 1: Nén thư mục web ──────────────────────────────────────
Step "Nén source code web/..."
if (Test-Path $ZIP) { Remove-Item $ZIP -Force }

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zipArchive = [System.IO.Compression.ZipFile]::Open($ZIP, 'Create')
Get-ChildItem -Path $WebSrc -Recurse -File | Where-Object {
    $_.FullName -notmatch '\\.venv\\|\\node_modules\\|\\__pycache__\\|\\.git\\|\\\.mypy_cache\\|\.pyc$|\.log$|\.zip$' -or $_.FullName -match 'dashboard\\dist'
} | ForEach-Object {
    $entry = $_.FullName.Substring($WebSrc.Length + 1).Replace('\', '/')
    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zipArchive, $_.FullName, $entry) | Out-Null
}
$zipArchive.Dispose()
$sizeMB = [math]::Round((Get-Item $ZIP).Length / 1MB, 1)
Ok "Đã nén: $sizeMB MB"

# ── BƯỚC 2: Upload lên VPS ────────────────────────────────────────
Step "Upload lên VPS $VpsIp..."
scp -i $KeyFile -o StrictHostKeyChecking=accept-new `
    $ZIP "${VpsUser}@${VpsIp}:${VpsPath}/vinfast_web.zip"
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Upload thất bại!" -ForegroundColor Red; exit 1
}
Ok "Upload xong"

# ── BƯỚC 3: SSH vào VPS, giải nén + rebuild ──────────────────────
Step "Rebuild service '$Service' trên VPS..."

$plan = Get-DeployPlan $Service
$buildServices = Join-ServiceList $plan.BuildServices
$upServices = Join-ServiceList $plan.UpServices
$healthTargets = Join-ServiceList $plan.HealthTargets

$remoteScript = @"
set -e
cd $VpsPath
echo '--- Giai nen ---'
rm -rf web_tmp && mkdir -p web_tmp
unzip -o vinfast_web.zip -d web_tmp/ 2>&1 | grep -v '^Archive\|^inflating\|^extracting' || true
ls web_tmp/
cp -rf web_tmp/. web/
rm -rf web_tmp
cd web
echo '--- Build ---'
docker compose --env-file .env build $buildServices 2>&1 | tail -10
echo '--- Restart ---'
docker compose --env-file .env up -d $upServices
echo '--- Status ---'
docker compose ps
echo '--- Verify containers ---'
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

echo '--- Verify proxy /api/health ---'
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

ssh -i $KeyFile -o ServerAliveInterval=30 -o ServerAliveCountMax=20 `
    "${VpsUser}@${VpsIp}" $remoteScript

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Deploy thất bại trên VPS!" -ForegroundColor Red; exit 1
}

# ── BƯỚC 4: Health check ─────────────────────────────────────────
Step "Kiểm tra API..."
Start-Sleep -Seconds 5
try {
    $res = Invoke-WebRequest -Uri "http://${VpsIp}/api/health" -TimeoutSec 15 -UseBasicParsing
    $json = $res.Content | ConvertFrom-Json
    Ok "API OK (HTTP $($res.StatusCode)) — version: $($json.version)"
} catch {
    Warn "API chưa phản hồi ngay — container đang khởi động, thử lại sau 30s"
}

# ── Kết quả ──────────────────────────────────────────────────────
Write-Host ""
Info "============================================"
Info "  ✅ Deploy '$Service' hoàn tất!"
Info "  🌐 Dashboard: http://$VpsIp"
Info "  🔌 API:       http://${VpsIp}/api/health"
Info "============================================"
