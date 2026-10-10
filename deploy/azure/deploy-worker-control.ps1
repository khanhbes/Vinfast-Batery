param(
    [string]$ConfigPath = "$PSScriptRoot/staging.json",
    [Parameter(Mandatory)][string]$ImageDigest,
    [Parameter(Mandatory)][string]$SmokeResultPath,
    [ValidatePattern('^[a-zA-Z0-9_-]{1,64}$')][string]$WorkerScope = 'azure-staging-1',
    [switch]$ControlApproved,
    [switch]$Apply
)
# Creates the reconciliation worker only. It does not change the API hardware
# policy (see 15-set-hardware-policy.ps1) and never sends a relay command.
. "$PSScriptRoot/common.ps1"
$config = Read-DeploymentConfig $ConfigPath
if ($ImageDigest -notmatch '^sha256:[a-f0-9]{64}$') { throw 'Use a pinned registry digest.' }
if ($Apply -and -not $ControlApproved) { throw 'Control worker resource/cost approval required.' }
$smoke = Get-Content -LiteralPath $SmokeResultPath -Raw | ConvertFrom-Json
if ($smoke.passed -ne $true -or $smoke.hardwareCommands -ne 0 -or $smoke.relayCommands -ne 0 -or
    $smoke.startupBlockedWithoutScope -ne $true) {
    throw 'Control worker local smoke has not passed.'
}
$registryRepo = "$($config.registryName).azurecr.io/vinfast-worker"
if (@($smoke.repoDigests) -notcontains "$registryRepo@$ImageDigest") {
    throw 'Registry digest does not match the locally smoke-tested image.'
}
# No existing app is ever updated, restarted or replaced by this script.
$apps = @(Invoke-Azure @('containerapp', 'list', '-g', $config.resourceGroup, '--query', '[].name', '-o', 'json') | ConvertFrom-Json)
if ($apps -contains 'vinfast-worker-control') { throw 'Control worker already exists; review before any update.' }
$baseline = @{}
foreach ($name in @('vinfast-api', 'vinfast-ai')) {
    $baseline[$name] = Invoke-Azure @('containerapp', 'show', '-g', $config.resourceGroup, '-n', $name,
        '--query', 'properties.latestRevisionName', '-o', 'tsv')
}
$environmentId = Invoke-Azure @('containerapp', 'env', 'show', '-g', $config.resourceGroup, '-n', $config.environmentName, '--query', 'id', '-o', 'tsv')
$identityId = Invoke-Azure @('identity', 'show', '-g', $config.resourceGroup, '-n', 'vinfast-image-pull', '--query', 'id', '-o', 'tsv')
$registryImage = "vinfast-worker@$ImageDigest"
$knownDigest = Invoke-Azure @('acr', 'repository', 'show', '-n', $config.registryName, '--image', $registryImage, '--query', 'digest', '-o', 'tsv')
if ($knownDigest.Trim() -ne $ImageDigest) { throw 'Image digest is not in the intended registry.' }
$temporary = Join-Path ([IO.Path]::GetTempPath()) ("vinfast-control-$([guid]::NewGuid().ToString('N')).json")
$phase = 'secret_mapping'
try {
    # Reuse the API's existing runtime secrets so API and worker share one vault key.
    $secretList = @(Invoke-Azure @('containerapp', 'secret', 'list', '-g', $config.resourceGroup, '-n', 'vinfast-api',
        '--show-values', '--query', "[?name=='firebase' || name=='vault-key']", '-o', 'json') | ConvertFrom-Json)
    $firebase = @($secretList | Where-Object name -eq 'firebase')
    $vault = @($secretList | Where-Object name -eq 'vault-key')
    if ($firebase.Count -ne 1 -or $vault.Count -ne 1 -or
        [string]::IsNullOrWhiteSpace($firebase[0].value) -or [string]::IsNullOrWhiteSpace($vault[0].value)) {
        throw 'Required secret mapping unavailable.'
    }
    $parameters = @{
        '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
        contentVersion = '1.0.0.0'
        parameters = @{
            location = @{ value = $config.location }
            environmentId = @{ value = $environmentId }
            registryServer = @{ value = "$($config.registryName).azurecr.io" }
            pullIdentityId = @{ value = $identityId }
            image = @{ value = "$($config.registryName).azurecr.io/$registryImage" }
            workerScope = @{ value = $WorkerScope }
            firebase = @{ value = $firebase[0].value }
            vaultKey = @{ value = $vault[0].value }
        }
    }
    $phase = 'private_parameter_file'
    Write-RestrictedJson $temporary $parameters
    $verb = if ($Apply) { 'create' } else { 'validate' }
    $phase = "arm_$verb"
    Invoke-Azure @('deployment', 'group', $verb, '-g', $config.resourceGroup, '--name', 'vinfast-worker-control-108',
        '--template-file', "$PSScriptRoot/worker-control.bicep", '--parameters', "@$temporary", '-o', 'none') | Out-Null
    if ($Apply) {
        $phase = 'resource_verification'
        $state = Invoke-Azure @('containerapp', 'show', '-g', $config.resourceGroup, '-n', 'vinfast-worker-control',
            '--query', '{ingress:properties.configuration.ingress,scale:properties.template.scale,resources:properties.template.containers[0].resources,image:properties.template.containers[0].image,revision:properties.latestRevisionName,running:properties.runningStatus}', '-o', 'json') | ConvertFrom-Json
        if ($null -ne $state.ingress -or $state.scale.minReplicas -ne 1 -or $state.scale.maxReplicas -ne 1 -or
            $state.resources.cpu -ne 0.25 -or $state.resources.memory -ne '0.5Gi') {
            throw 'Control worker shape does not match approval. Inspect and stop this worker only.'
        }
        foreach ($name in @('vinfast-api', 'vinfast-ai')) {
            $current = Invoke-Azure @('containerapp', 'show', '-g', $config.resourceGroup, '-n', $name,
                '--query', 'properties.latestRevisionName', '-o', 'tsv')
            if ($current -ne $baseline[$name]) { throw 'Existing app revision changed; investigate before proceeding.' }
        }
        [pscustomobject]@{ appName = 'vinfast-worker-control'; image = $state.image; revision = $state.revision;
            runningStatus = $state.running; scope = $WorkerScope; minReplicas = 1; maxReplicas = 1; ingress = $false;
            apiPolicyChanged = $false; relayCommands = 0 } | ConvertTo-Json
    } else { Write-Host 'Control worker template validation passed; no worker created.' }
} catch {
    # Do not echo Azure diagnostics or parameters. No broad rollback/deletion.
    $safeType = $_.Exception.GetType().Name
    throw "Control worker failed at $phase ($safeType). No secret diagnostics printed. Existing API/AI were not modified by this script."
} finally {
    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary }
    $parameters = $null
    $secretList = $null
    $firebase = $null
    $vault = $null
}
