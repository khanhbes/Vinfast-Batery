param([Parameter(Mandatory)][string]$ConfigPath, [switch]$EntitlementsConfirmed, [switch]$LocalGatePassed, [switch]$Apply)
. "$PSScriptRoot/common.ps1"
$config = Read-DeploymentConfig $ConfigPath
foreach ($name in @($config.registryName, $config.storageName)) {
    if ($name -notmatch '^[a-z0-9]{5,24}$') { throw 'Choose explicit unique lowercase registry/storage names first.' }
}
if (-not $Apply) {
    Invoke-Azure @('bicep', 'build', '--file', "$PSScriptRoot/infrastructure.bicep", '--stdout') | Out-Null
    Write-Host 'Template compiled only. Standard ACR, Standard_LRS Files and Free SWA require actual entitlement review.'
    return
}
if (-not $EntitlementsConfirmed) { throw 'Confirm current credit/free entitlements before creating resources. This stack is not guaranteed free.' }
if (-not $LocalGatePassed) { throw 'Clean API/AI builds, isolated boots and dashboard build must pass before creating cloud resources.' }
$groupExists = Invoke-Azure @('group', 'exists', '--name', $config.resourceGroup, '-o', 'tsv')
if ($groupExists.Trim() -eq 'false') {
    Invoke-Azure @('group', 'create', '--name', $config.resourceGroup, '--location', $config.location, '-o', 'none') | Out-Null
} elseif ($groupExists.Trim() -ne 'true') {
    throw 'Cannot establish resource group existence.'
}
# Existing resource-group metadata location is immutable. Resources use the
# explicit deployment location and need not match the group's metadata region.
$arguments = @('deployment', 'group', 'create', '--resource-group', $config.resourceGroup,
    '--name', 'vinfast-staging-infrastructure', '--template-file', "$PSScriptRoot/infrastructure.bicep",
    '--parameters', "location=$($config.location)", "environmentName=$($config.environmentName)",
    "registryName=$($config.registryName)", "storageName=$($config.storageName)", "adminName=$($config.adminName)",
    '--query', 'properties.outputs', '-o', 'json')
$outputs = Invoke-Azure $arguments
Write-Host $outputs # Outputs contain resource names/URLs only; no storage key.
