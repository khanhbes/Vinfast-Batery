param(
    [string]$ConfigPath = "$PSScriptRoot/staging.json",
    [Parameter(Mandatory)][string]$ImageDigest,
    [Parameter(Mandatory)][string]$UnitResultPath,
    [Parameter(Mandatory)][string]$SmokeResultPath,
    [switch]$PilotApproved,
    [switch]$Apply
)
. "$PSScriptRoot/common.ps1"
$config = Read-DeploymentConfig $ConfigPath
if ($ImageDigest -notmatch '^sha256:[a-f0-9]{64}$') { throw 'Use a pinned registry digest.' }
if ($Apply -and -not $PilotApproved) { throw 'Pilot resource/cost approval required; ON/rearm remains locked.' }
$unit = Get-Content -LiteralPath $UnitResultPath -Raw | ConvertFrom-Json
$smoke = Get-Content -LiteralPath $SmokeResultPath -Raw | ConvertFrom-Json
if ($unit.exitCode -ne 0 -or $unit.timedOut -or $smoke.passed -ne $true -or $smoke.hardwareCommands -ne 0) {
    throw 'Pilot local gates have not passed.'
}
if ($smoke.imageId -ne $ImageDigest) { throw 'Registry digest does not match the locally tested image.' }
foreach ($entry in $smoke.sourceHashes.PSObject.Properties) {
    $path = [IO.Path]::GetFullPath((Join-Path $script:RepoRoot $entry.Name))
    if (-not $path.StartsWith($script:RepoRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Manifest path escapes repository.'
    }
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $entry.Value) {
        throw 'Pilot source changed after smoke test. Rerun gates.'
    }
}
# No existing app is ever updated, restarted or replaced by this script.
$apps = @(Invoke-Azure @('containerapp', 'list', '-g', $config.resourceGroup, '--query', '[].name', '-o', 'json') | ConvertFrom-Json)
if ($apps -contains 'vinfast-worker-pilot') { throw 'Pilot already exists; review before any update.' }
$policy = Invoke-Azure @('containerapp', 'show', '-g', $config.resourceGroup, '-n', 'vinfast-api',
    '--query', "properties.template.containers[0].env[?name=='AZURE_STAGING_HARDWARE_DISABLED'].value | [0]", '-o', 'tsv')
if ($policy.Trim() -ne '1') { throw 'API staging hardware-disabled policy is not confirmed.' }
$baseline = @{}
foreach ($name in @('vinfast-api','vinfast-ai')) {
    $baseline[$name] = Invoke-Azure @('containerapp', 'show', '-g', $config.resourceGroup, '-n', $name,
        '--query', 'properties.latestRevisionName', '-o', 'tsv')
}
$environmentId = Invoke-Azure @('containerapp', 'env', 'show', '-g', $config.resourceGroup, '-n', $config.environmentName, '--query', 'id', '-o', 'tsv')
$identityId = Invoke-Azure @('identity', 'show', '-g', $config.resourceGroup, '-n', 'vinfast-image-pull', '--query', 'id', '-o', 'tsv')
$registryImage = "vinfast-worker-pilot@$ImageDigest"
$knownDigest = Invoke-Azure @('acr', 'repository', 'show', '-n', $config.registryName, '--image', $registryImage, '--query', 'digest', '-o', 'tsv')
if ($knownDigest.Trim() -ne $ImageDigest) { throw 'Image digest is not in the intended registry.' }
$temporary = Join-Path ([IO.Path]::GetTempPath()) ("vinfast-pilot-$([guid]::NewGuid().ToString('N')).json")
$phase = 'secret_mapping'
try {
    # Only the two existing runtime secrets, captured privately; never print them.
    # No new service-account key, admin token, Cloud key or AI key is generated.
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
            firebase = @{ value = $firebase[0].value }
            vaultKey = @{ value = $vault[0].value }
        }
    }
    $phase = 'private_parameter_file'
    Write-RestrictedJson $temporary $parameters
    $verb = if ($Apply) { 'create' } else { 'validate' }
    $phase = "arm_$verb"
    Invoke-Azure @('deployment', 'group', $verb, '-g', $config.resourceGroup, '--name', 'vinfast-worker-pilot-105',
        '--template-file', "$PSScriptRoot/worker-pilot.bicep", '--parameters', "@$temporary", '-o', 'none') | Out-Null
    if ($Apply) {
        $phase = 'resource_verification'
        $state = Invoke-Azure @('containerapp', 'show', '-g', $config.resourceGroup, '-n', 'vinfast-worker-pilot',
            '--query', '{ingress:properties.configuration.ingress,scale:properties.template.scale,resources:properties.template.containers[0].resources,image:properties.template.containers[0].image,revision:properties.latestRevisionName}', '-o', 'json') | ConvertFrom-Json
        if ($null -ne $state.ingress -or $state.scale.minReplicas -ne 1 -or $state.scale.maxReplicas -ne 1 -or
            $state.resources.cpu -ne 0.25 -or $state.resources.memory -ne '0.5Gi') {
            throw 'Pilot resource shape does not match approval. Inspect and stop this pilot only.'
        }
        foreach ($name in @('vinfast-api','vinfast-ai')) {
            $current = Invoke-Azure @('containerapp', 'show', '-g', $config.resourceGroup, '-n', $name,
                '--query', 'properties.latestRevisionName', '-o', 'tsv')
            if ($current -ne $baseline[$name]) { throw 'Existing app revision changed; investigate before proceeding.' }
        }
        [pscustomobject]@{ appName='vinfast-worker-pilot'; image=$state.image; revision=$state.revision;
            minReplicas=1; maxReplicas=1; ingress=$false; hardwareDisabled=$true; controlReady=$false } | ConvertTo-Json
    } else { Write-Host 'Pilot template validation passed; no worker created.' }
} catch {
    # Do not echo Azure diagnostics or parameters. No broad rollback/deletion.
    $safeType = $_.Exception.GetType().Name
    throw "Pilot failed at $phase ($safeType). No secret diagnostics printed. Inspect only the pilot; existing API/AI were not modified by this script."
} finally {
    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary }
    $parameters = $null
    $secretList = $null
    $firebase = $null
    $vault = $null
}
