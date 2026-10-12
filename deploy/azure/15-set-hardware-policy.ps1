param(
    [Parameter(Mandatory)][ValidateSet('Locked', 'Unlocked')][string]$Policy,
    [Parameter(Mandatory)][string]$EvidencePath,
    [ValidatePattern('^[a-zA-Z0-9_-]{1,64}$')][string]$WorkerScope = 'azure-staging-1',
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'staging.json'),
    [switch]$UnlockApproved,
    [switch]$Execute
)
# Env-only change of the API hardware policy. Image, secrets, identity, ingress,
# scale and every other env entry must stay identical. No relay calls.
# Rollback is always: -Policy Locked -Execute (ON blocked at once; OFF/stop still allowed).
. (Join-Path $PSScriptRoot 'common.ps1')
$config = Read-DeploymentConfig $ConfigPath
if ($Policy -eq 'Unlocked' -and $Execute -and -not $UnlockApproved) { throw 'Explicit unlock approval required.' }
$evidence = [IO.Path]::GetFullPath($EvidencePath)
$evidenceRoot = [IO.Path]::GetFullPath((Join-Path $script:RepoRoot 'docs/qa_evidence')) + [IO.Path]::DirectorySeparatorChar
if (-not $evidence.StartsWith($evidenceRoot, [StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $evidence)) {
    throw 'Use a new evidence path inside docs/qa_evidence; never overwrite a previous receipt.'
}
$managed = @('AZURE_STAGING_HARDWARE_DISABLED', 'SMART_CHARGE_WORKER_SCOPE')
function Get-App([string]$name) {
    return (Invoke-Azure @('containerapp', 'show', '-g', $config.resourceGroup, '-n', $name, '-o', 'json') | ConvertFrom-Json)
}
function Get-EnvValue($app, [string]$name) {
    $entry = @($app.properties.template.containers[0].env | Where-Object name -eq $name)
    if ($entry.Count -ne 1) { return $null }
    return [string]$entry[0].value
}
function Get-ProtectedHash($app) {
    # Everything except the two managed env entries, image-independent of revision suffix.
    $template = ($app.properties.template | ConvertTo-Json -Depth 40 -Compress | ConvertFrom-Json)
    $template.PSObject.Properties.Remove('revisionSuffix')
    foreach ($container in $template.containers) {
        $container.env = @($container.env | Where-Object { $managed -notcontains $_.name } | ForEach-Object {
            $reference = $_.PSObject.Properties['secretRef']
            $value = $_.PSObject.Properties['value']
            if ($reference -and $reference.Value -and $value -and ($null -eq $value.Value -or $value.Value -eq '')) {
                $_.PSObject.Properties.Remove('value')
            }
            $_
        })
    }
    $shape = [ordered]@{ template = $template; configuration = $app.properties.configuration; identity = $app.identity; environment = $app.properties.managedEnvironmentId }
    $bytes = [Text.Encoding]::UTF8.GetBytes(($shape | ConvertTo-Json -Depth 50 -Compress))
    $hasher = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($hasher.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $hasher.Dispose() }
}
function Assert-Policy($app, [string]$expected) {
    $flag = Get-EnvValue $app 'AZURE_STAGING_HARDWARE_DISABLED'
    $scope = Get-EnvValue $app 'SMART_CHARGE_WORKER_SCOPE'
    if ((Get-EnvValue $app 'APP_ENV') -notin @('prod', 'production')) { throw 'API must keep production authentication mode.' }
    if ($expected -eq 'Locked' -and $flag -ne '1') { throw 'API is not locked.' }
    if ($expected -eq 'Unlocked' -and ($flag -ne '0' -or $scope -ne $WorkerScope)) { throw 'API unlock not applied as approved.' }
}
$before = Get-App 'vinfast-api'
if ($before.properties.template.containers.Count -ne 1 -or $before.properties.configuration.activeRevisionsMode -ne 'Single') {
    throw 'Unexpected API topology.'
}
$provider = Get-EnvValue $before 'SHELLY_PROVIDER'
if ($provider -and $provider -ne 'vault_cloud') { throw 'API SHELLY_PROVIDER must be vault_cloud (or unset) for server control.' }
if (-not @($before.properties.template.containers[0].env | Where-Object { $_.name -eq 'SHELLY_PROFILE_MASTER_KEY' -and $_.secretRef }).Count) {
    throw 'API vault key secret reference is missing.'
}
if ($Policy -eq 'Unlocked') {
    # The API still refuses ON until this worker's Firestore heartbeat/lease is fresh;
    # this check only prevents unlocking with no matching worker at all.
    $worker = Get-App 'vinfast-worker-control'
    if ((Get-EnvValue $worker 'SMART_CHARGE_WORKER_SCOPE') -ne $WorkerScope -or
        (Get-EnvValue $worker 'SHELLY_PROVIDER') -ne 'vault_cloud' -or
        $worker.properties.runningStatus -ne 'Running' -or
        $worker.properties.latestReadyRevisionName -ne $worker.properties.latestRevisionName) {
        throw 'Control worker with the same scope is not running and ready.'
    }
}
$beforeHash = Get-ProtectedHash $before
$record = [ordered]@{
    policy = $Policy; scope = $WorkerScope; execute = [bool]$Execute
    beforeRevision = $before.properties.latestReadyRevisionName; beforeImage = $before.properties.template.containers[0].image
    beforeFlag = Get-EnvValue $before 'AZURE_STAGING_HARDWARE_DISABLED'; beforeScope = Get-EnvValue $before 'SMART_CHARGE_WORKER_SCOPE'
    protectedHash = $beforeHash; succeeded = $false; noRelayCalls = $true
}
if (-not $Execute) {
    [IO.File]::WriteAllText($evidence, ($record | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
    Write-Host "Hardware policy preflight ($Policy) passed; no Azure mutation."
    return
}
try {
    $flagValue = if ($Policy -eq 'Locked') { '1' } else { '0' }
    $record.stage = 'updateEnv'
    Invoke-Azure @('containerapp', 'update', '-g', $config.resourceGroup, '-n', 'vinfast-api',
        '--set-env-vars', "AZURE_STAGING_HARDWARE_DISABLED=$flagValue", "SMART_CHARGE_WORKER_SCOPE=$WorkerScope",
        '--revision-suffix', ('hw' + $flagValue + '-' + [DateTime]::UtcNow.ToString('MMddHHmmss')), '-o', 'none') | Out-Null
    $record.stage = 'checkConfiguration'
    $after = Get-App 'vinfast-api'
    Assert-Policy $after $Policy
    if ((Get-ProtectedHash $after) -ne $beforeHash -or $after.properties.template.containers[0].image -ne $record.beforeImage) {
        throw 'API configuration outside the two managed env entries changed.'
    }
    $hostName = $after.properties.configuration.ingress.fqdn
    if ($hostName -notmatch '^[a-z0-9.-]+\.azurecontainerapps\.io$') { throw 'Unexpected HTTPS API hostname.' }
    $record.stage = 'httpsHealthReadiness'
    $deadline = [DateTime]::UtcNow.AddSeconds(300)
    $ready = $false
    do {
        try {
            $health = Invoke-WebRequest -UseBasicParsing -Uri "https://$hostName/api/health" -TimeoutSec 15
            $readiness = Invoke-WebRequest -UseBasicParsing -Uri "https://$hostName/api/ready" -TimeoutSec 15
            $ready = $health.StatusCode -eq 200 -and $readiness.StatusCode -eq 200
        } catch { $ready = $false }
        if (-not $ready) { Start-Sleep -Seconds 3 }
    } while (-not $ready -and [DateTime]::UtcNow -lt $deadline)
    if (-not $ready) { throw 'API health/readiness deadline exceeded.' }
    $final = Get-App 'vinfast-api'
    Assert-Policy $final $Policy
    if ($final.properties.latestReadyRevisionName -ne $final.properties.latestRevisionName) { throw 'New revision not ready.' }
    $record.afterRevision = $final.properties.latestReadyRevisionName
    $record.afterFlag = Get-EnvValue $final 'AZURE_STAGING_HARDWARE_DISABLED'
    $record.afterScope = Get-EnvValue $final 'SMART_CHARGE_WORKER_SCOPE'
    $record.healthStatus = 200
    $record.readinessStatus = 200
    $record.stage = 'verified'
    $record.succeeded = $true
    Write-Host "API hardware policy $Policy verified; no relay calls."
} catch {
    throw "Hardware policy change failed at $($record.stage). Rollback: rerun with -Policy Locked -Execute."
} finally {
    [IO.File]::WriteAllText($evidence, ($record | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
}
