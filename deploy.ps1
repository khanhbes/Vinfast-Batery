<#
  deploy.ps1 — Tự động deploy VinFast Battery lên VPS
  Chạy: .\deploy.ps1
  Chỉ api:       .\deploy.ps1 -Service api
  Chỉ ai:        .\deploy.ps1 -Service ai
  Chỉ dashboard: .\deploy.ps1 -Service dashboard
#>
param(
    [string]$Service = "api",              # api | ai | dashboard | all
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

if ($Service -eq "all") {
    $buildCmd  = "docker compose --env-file .env build 2>&1 | tail -10"
    $upCmd     = "docker compose --env-file .env up -d"
} else {
    $buildCmd  = "docker compose --env-file .env build $Service 2>&1 | tail -10"
    # PLAN1: Nếu deploy api, cũng restart dashboard để pick up file mới
    if ($Service -eq "api") {
        $upCmd = "docker compose --env-file .env up -d --no-deps $Service && docker compose --env-file .env restart dashboard"
    } else {
        $upCmd = "docker compose --env-file .env up -d --no-deps $Service"
    }
}

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
$buildCmd
echo '--- Restart ---'
$upCmd
echo '--- Status ---'
docker compose ps
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
    $res = Invoke-WebRequest -Uri "http://${VpsIp}:5000/api/health" -TimeoutSec 15 -UseBasicParsing
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
Info "  🔌 API:       http://${VpsIp}:5000/api/health"
Info "============================================"
