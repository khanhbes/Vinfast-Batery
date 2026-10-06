param(
    [string]$ApiImage = 'vinfast-api:azure-staging-20261006',
    [string]$AiImage = 'vinfast-ai:azure-staging-20261006',
    [int]$TimeoutSeconds = 180,
    [ValidateSet('api', 'ai')][string[]]$Services = @('api', 'ai')
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($TimeoutSeconds -lt 30 -or $TimeoutSeconds -gt 600) { throw 'Invalid boot timeout.' }
$runId = [Guid]::NewGuid().ToString('N')
$token = [Guid]::NewGuid().ToString('N')
# Isolated import/HTTP/RAM gate, NOT a Firebase readiness or Gemini test.
# No network, mounts, host ports, credentials or existing container changes.
foreach ($service in $Services) {
    $name = "vinfast-azure-boot-$service-$runId"
    $image = if ($service -eq 'api') { $ApiImage } else { $AiImage }
    $memory = if ($service -eq 'api') { '512m' } else { '2g' }
    $cpu = if ($service -eq 'api') { '0.25' } else { '1' }
    $runtime = if ($service -eq 'api') { 'testing' } else { 'production' }
    $port = if ($service -eq 'api') { 5000 } else { 8001 }
    $health = if ($service -eq 'api') { '/api/health' } else { '/healthz' }
    $createdId = $null
    try {
        $createdId = & docker run -d --name $name --label "vinfast.azure.qa=$runId" --network none `
            --memory $memory --cpus $cpu -e "APP_ENV=$runtime" `
            -e AZURE_STAGING_HARDWARE_DISABLED=1 -e "AI_SERVER_INTERNAL_TOKEN=$token" $image
        if ($LASTEXITCODE -ne 0) { throw "$service isolated container creation failed." }
        $started = [DateTime]::UtcNow
        $ready = $false
        do {
            $stateText = & docker inspect --format '{{json .State}}' $createdId
            if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect QA container.' }
            $state = $stateText | ConvertFrom-Json
            if (-not $state.Running) {
                throw "$service boot exited: exit=$($state.ExitCode), OOMKilled=$($state.OOMKilled)."
            }
            $probe = & docker exec $createdId curl --silent --max-time 2 --output /dev/null --write-out '%{http_code}' "http://127.0.0.1:$port$health" 2>$null
            $ready = $LASTEXITCODE -eq 0 -and $probe -eq '200'
            if (-not $ready) { Start-Sleep -Seconds 2 }
        } while (-not $ready -and ([DateTime]::UtcNow - $started).TotalSeconds -lt $TimeoutSeconds)
        if (-not $ready) { throw "$service boot timeout; not Pass." }
        if ($service -eq 'api') {
            $readiness = & docker exec $createdId curl --silent --output /dev/null --write-out '%{http_code}' 'http://127.0.0.1:5000/api/ready'
            if ($LASTEXITCODE -ne 0 -or $readiness -ne '503') { throw 'Isolated API must report Firebase unavailable.' }
            $blocked = & docker exec $createdId curl --silent --output /dev/null --write-out '%{http_code}' -X POST 'http://127.0.0.1:5000/api/smart-charging/start'
            if ($LASTEXITCODE -ne 0 -or $blocked -ne '503') { throw 'Hardware deny guard missing from built image.' }
        } else {
            $denied = & docker exec $createdId curl --silent --output /dev/null --write-out '%{http_code}' 'http://127.0.0.1:8001/v1/types'
            if ($LASTEXITCODE -ne 0 -or $denied -ne '401') { throw 'AI internal token protection failed.' }
            & docker exec $createdId python -c "import tensorflow,onnxruntime,xgboost,sklearn; assert not xgboost.build_info().get('USE_CUDA', True)"
            if ($LASTEXITCODE -ne 0) { throw 'CPU-only ML imports failed under the AI memory limit.' }
        }
        & docker stats --no-stream --format '{{.Name}} RAM={{.MemUsage}} CPU={{.CPUPerc}}' $createdId
        if ($LASTEXITCODE -ne 0) { throw 'Cannot measure container RAM.' }
        Write-Host "$service isolated boot Pass; seconds=$([Math]::Round(([DateTime]::UtcNow - $started).TotalSeconds, 2)); no real dependency calls."
    } finally {
        if ($createdId) {
            # Only the exact container created here, after checking our unique label.
            $containerInfo = & docker inspect $createdId 2>$null
            $inspectExit = $LASTEXITCODE
            $label = if ($inspectExit -eq 0) { ($containerInfo | ConvertFrom-Json)[0].Config.Labels.'vinfast.azure.qa' } else { $null }
            if ($inspectExit -eq 0 -and $label -eq $runId) {
                & docker rm -f $createdId | Out-Null
                if ($LASTEXITCODE -ne 0) { Write-Warning 'QA container cleanup failed; inspect the run-specific container.' }
            }
        }
    }
}
