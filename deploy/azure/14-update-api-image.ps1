param(
    [Parameter(Mandatory)][string]$Image,
    [Parameter(Mandatory)][string]$EvidencePath,
    [Parameter(Mandatory)][string[]]$GateResultPaths,
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'staging.json'),
    [string]$VerifyBaselinePath,
    [ValidateSet('Locked', 'Unlocked')][string]$HardwarePolicy = 'Locked',
    [switch]$Execute
)
# Image-only staging rollout. No credential fetch, worker update or relay calls.
. (Join-Path $PSScriptRoot 'common.ps1')
if ($Execute -and $VerifyBaselinePath) { throw 'Verification-only mode must not execute an update.' }
$config = Read-DeploymentConfig $ConfigPath
$registry = "$($config.registryName).azurecr.io"
if ($Image -notmatch "^$([regex]::Escape($registry))/vinfast-api@sha256:[0-9a-f]{64}$") {
    throw 'Only an immutable API digest in the existing registry is permitted.'
}
$evidence = [IO.Path]::GetFullPath($EvidencePath)
$evidenceRoot = [IO.Path]::GetFullPath((Join-Path $script:RepoRoot 'docs/qa_evidence')) + [IO.Path]::DirectorySeparatorChar
if (-not $evidence.StartsWith($evidenceRoot, [StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $evidence)) {
    throw 'Use a new evidence path inside docs/qa_evidence; never overwrite a previous rollout.'
}
function Get-VerifiedGateRole($gate) {
    if ($gate.exitCode -ne 0 -or $gate.timedOut -or $gate.cleanupError) {
        throw 'A required gate failed or timed out. No Azure mutation performed.'
    }
    $arguments = @($gate.command)
    if ($arguments -contains 'build' -and @($arguments | Where-Object { $_ -match '(^|[/\\])Dockerfile\.api$' }).Count -gt 0) { return 'build' }
    if (@($arguments | Where-Object { $_ -match '(^|[/\\])08-local-boot-smoke\.ps1$' }).Count -gt 0 -and $arguments -contains 'api' -and $arguments -notcontains 'ai') { return 'boot' }
    if ($arguments -contains 'run' -and $arguments -contains '--network' -and $arguments -contains 'none' -and $arguments -contains 'pytest' -and $arguments -contains 'tests') { return 'backend' }
    return 'other'
}
$roles = @()
foreach ($gatePath in $GateResultPaths) {
    $gate = Get-Content -LiteralPath $gatePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $roles += Get-VerifiedGateRole $gate
}
foreach ($requiredRole in @('build', 'boot', 'backend')) {
    if ($roles -notcontains $requiredRole) { throw 'Missing API build, isolated boot or full-backend receipt; unrelated green gates cannot substitute.' }
}
function Get-App([string]$name) {
    return (Invoke-Azure @('containerapp', 'show', '-g', $config.resourceGroup, '-n', $name, '-o', 'json') | ConvertFrom-Json)
}
function Get-ShapeHash($app) {
    # Hash in memory only; never persist env values or secret metadata.
    $template = ($app.properties.template | ConvertTo-Json -Depth 40 -Compress | ConvertFrom-Json)
    $template.PSObject.Properties.Remove('revisionSuffix')
    foreach ($container in $template.containers) {
        $container.PSObject.Properties.Remove('image')
        foreach ($entry in $container.env) {
            $reference = $entry.PSObject.Properties['secretRef']
            $value = $entry.PSObject.Properties['value']
            # Azure CLI adds empty value metadata to existing secret references.
            # Normalize ONLY null/empty values with a nonempty secretRef. Never
            # ignore plain env values, changed secret names or nonempty values.
            if ($reference -and $reference.Value -and $value -and ($null -eq $value.Value -or $value.Value -eq '')) {
                $entry.PSObject.Properties.Remove('value')
            }
        }
    }
    $shape = @{ template = $template; configuration = $app.properties.configuration; identity = $app.identity; environment = $app.properties.managedEnvironmentId }
    $bytes = [Text.Encoding]::UTF8.GetBytes(($shape | ConvertTo-Json -Depth 50 -Compress))
    $hasher = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($hasher.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $hasher.Dispose() }
}
function Assert-ApiGuard($app, [string]$expectedPolicy = 'Locked') {
    if ($app.properties.template.containers.Count -ne 1 -or $app.properties.configuration.activeRevisionsMode -ne 'Single') {
        throw 'Unexpected API topology; image-only rollout stopped.'
    }
    $policy = @($app.properties.template.containers[0].env | Where-Object name -eq 'AZURE_STAGING_HARDWARE_DISABLED')
    if ($expectedPolicy -eq 'Unlocked') {
        # Unlocked is only valid with an explicit worker scope; the API then
        # still refuses ON until that worker's heartbeat/lease is fresh.
        $scope = @($app.properties.template.containers[0].env | Where-Object name -eq 'SMART_CHARGE_WORKER_SCOPE')
        if ($policy.Count -ne 1 -or $policy[0].value -ne '0' -or $scope.Count -ne 1 -or
            [string]$scope[0].value -notmatch '^[a-zA-Z0-9_-]{1,64}$') {
            throw 'Unlocked hardware policy requires flag 0 and an explicit worker scope.'
        }
    } elseif ($policy.Count -ne 1 -or $policy[0].value -ne '1') { throw 'Hardware policy must remain explicitly disabled.' }
    $runtime = @($app.properties.template.containers[0].env | Where-Object name -eq 'APP_ENV')
    if ($runtime.Count -ne 1 -or $runtime[0].value -notin @('prod', 'production')) {
        throw 'API must keep production authentication mode.'
    }
}
function Get-PeerSnapshot {
    $existing = @(Invoke-Azure @('containerapp', 'list', '-g', $config.resourceGroup, '--query', '[].name', '-o', 'json') | ConvertFrom-Json)
    return @('vinfast-ai', 'vinfast-worker-pilot', 'vinfast-worker-control' | Where-Object { $existing -contains $_ } | ForEach-Object {
        $peer = Get-App $_
        @{ name = $_; revision = $peer.properties.latestRevisionName; image = $peer.properties.template.containers[0].image; shapeHash = Get-ShapeHash $peer }
    })
}
function Assert-PeersUnchanged($before, $after) {
    if ($before.Count -ne $after.Count) { throw 'AI/pilot inventory changed.' }
    for ($i = 0; $i -lt $before.Count; $i++) {
        foreach ($field in @('name', 'revision', 'image', 'shapeHash')) {
            if ($before[$i].$field -ne $after[$i].$field) {
                throw 'AI/pilot baseline changed. Stop and investigate; do not modify peers.'
            }
        }
    }
}
$before = Get-App 'vinfast-api'
Assert-ApiGuard $before $HardwarePolicy
$beforeHash = Get-ShapeHash $before
$oldImage = $before.properties.template.containers[0].image
$peers = Get-PeerSnapshot
if ($VerifyBaselinePath) {
    $original = Get-Content -LiteralPath $VerifyBaselinePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($original.proposedImage -ne $Image -or $before.properties.template.containers[0].image -ne $Image -or $beforeHash -ne $original.beforeShapeHash) {
        throw 'Current image/configuration does not match the original approved baseline.'
    }
    Assert-PeersUnchanged $original.peers $peers
    $oldImage = $original.beforeImage
}
$record = @{ sourceSha = (& git -c "safe.directory=$($script:RepoRoot.Replace('\','/'))" -C $script:RepoRoot rev-parse HEAD).Trim(); beforeImage = $oldImage; beforeRevision = $before.properties.latestReadyRevisionName; beforeShapeHash = $beforeHash; proposedImage = $Image; hardwareDisabled = ($HardwarePolicy -eq 'Locked'); peers = $peers; execute = [bool]$Execute; succeeded = $false; rolledBack = $false; noRelayCalls = $true }
if ($VerifyBaselinePath) {
    $record.beforeRevision = $original.beforeRevision
    $record.verificationOnly = $true
    $record.originalReceipt = [IO.Path]::GetFileName($VerifyBaselinePath)
}
if (-not $Execute -and -not $VerifyBaselinePath) {
    [IO.File]::WriteAllText($evidence, ($record | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
    Write-Host 'Image-only preflight passed; no Azure mutation.'
    return
}
$updateAttempted = $false
try {
    if ($Execute) {
        $record.stage = 'updateImage'
        $updateAttempted = $true
        Invoke-Azure @('containerapp', 'update', '-g', $config.resourceGroup, '-n', 'vinfast-api', '--image', $Image, '--revision-suffix', ('api106-' + [DateTime]::UtcNow.ToString('MMddHHmmss')), '-o', 'none') | Out-Null
    }
    $record.stage = 'checkConfiguration'
    $after = Get-App 'vinfast-api'
    Assert-ApiGuard $after $HardwarePolicy
    if ((Get-ShapeHash $after) -ne $beforeHash -or $after.properties.template.containers[0].image -ne $Image) {
        throw 'Image or immutable API configuration differs from approved rollout.'
    }
    Assert-PeersUnchanged $peers (Get-PeerSnapshot)
    $hostName = $after.properties.configuration.ingress.fqdn
    if ($hostName -notmatch '^[a-z0-9.-]+\.azurecontainerapps\.io$') { throw 'Unexpected HTTPS API hostname.' }
    # New image digests can take several minutes to pull and activate.
    $deadline = [DateTime]::UtcNow.AddSeconds(600)
    $record.stage = 'httpsHealthReadiness'
    $ready = $false
    do {
        try {
            $health = Invoke-WebRequest -UseBasicParsing -Uri "https://$hostName/api/health" -TimeoutSec 15
            $readiness = Invoke-WebRequest -UseBasicParsing -Uri "https://$hostName/api/ready" -TimeoutSec 15
            $healthBody = $health.Content | ConvertFrom-Json
            $readyBody = $readiness.Content | ConvertFrom-Json
            $ready = $health.StatusCode -eq 200 -and $readiness.StatusCode -eq 200 -and $healthBody.success -eq $true -and $readyBody.success -eq $true -and $readyBody.data.firebase -eq 'ready' -and [bool]$healthBody.requestId -and [bool]$readyBody.requestId
            $record.lastProbe = "health=$($health.StatusCode) ready=$($readiness.StatusCode) fb=$($readyBody.data.firebase)"
        } catch {
            $ready = $false # Never persist raw error/response bodies.
            $record.lastProbe = "error=$($_.Exception.GetType().Name)"
        }
        if (-not $ready) { Start-Sleep -Seconds 3 }
    } while (-not $ready -and [DateTime]::UtcNow -lt $deadline)
    if (-not $ready) { throw 'API health/readiness deadline exceeded.' }
    # HTTPS can answer from the new revision before ARM marks it latestReady.
    $record.stage = 'revisionReady'
    do {
        $final = Get-App 'vinfast-api'
        $revisionReady = $final.properties.latestReadyRevisionName -eq $final.properties.latestRevisionName
        if (-not $revisionReady) { Start-Sleep -Seconds 5 }
    } while (-not $revisionReady -and [DateTime]::UtcNow -lt $deadline)
    if (-not $revisionReady) { throw 'New API revision did not become latestReady.' }
    $record.stage = 'finalConfiguration'
    Assert-ApiGuard $final $HardwarePolicy
    if ((Get-ShapeHash $final) -ne $beforeHash) {
        throw 'Preserved API configuration not verified.'
    }
    $record.stage = 'finalPeers'
    Assert-PeersUnchanged $peers (Get-PeerSnapshot)
    $record.afterRevision = $final.properties.latestReadyRevisionName
    $record.afterShapeHash = Get-ShapeHash $final
    $record.healthStatus = 200
    $record.readinessStatus = 200
    $record.requestIdsPresent = $true
    $record.firebaseReady = $true
    $record.stage = 'verified'
    $record.succeeded = $true
    Write-Host "API image rollout verified; hardware policy $HardwarePolicy, peers unchanged, no relay calls."
} catch {
    if ($updateAttempted) {
        # Roll back only our API image, and only if its protected shape remains unchanged.
        $current = Get-App 'vinfast-api'
        Assert-ApiGuard $current $HardwarePolicy
        if ((Get-ShapeHash $current) -eq $beforeHash) {
            Invoke-Azure @('containerapp', 'update', '-g', $config.resourceGroup, '-n', 'vinfast-api', '--image', $oldImage, '-o', 'none') | Out-Null
            $rollback = Get-App 'vinfast-api'
            Assert-ApiGuard $rollback $HardwarePolicy
            $record.rolledBack = $rollback.properties.template.containers[0].image -eq $oldImage
        }
    }
    throw 'API rollout failed; inspect sanitized evidence/Portal. No peer or hardware mutation performed.'
} finally {
    [IO.File]::WriteAllText($evidence, ($record | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
}
