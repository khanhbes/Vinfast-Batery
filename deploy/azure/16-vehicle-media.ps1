param(
    [Parameter(Mandatory)][string]$ConfigPath,
    [string]$MediaStorageName = 'vfmediaf1c11a09',
    [switch]$Apply,
    [switch]$ConfigureApi,
    [switch]$ConfigureDispatch,
    [switch]$DisableDispatch
)
# Vehicle catalog media (Task 122). Default: compile + what-if only.
#   -Apply         create/update the public-read media account, container and
#                  the API identity's blob-writer role.
#   -ConfigureApi  set VEHICLE_MEDIA_* / AZURE_CLIENT_ID on vinfast-api
#                  (run only after the API image with azure-storage-blob is live).
#   -ConfigureDispatch  Task 123: move the Shelly Cloud dispatch gate and the
#                  worker lease/health (SHELLY_CONTROL_STATE=table) to the
#                  shellyDispatch table — worker first, API right after (a
#                  mismatch only blocks ON until both match).
#   -DisableDispatch    roll back both apps to the Firestore gate.
. "$PSScriptRoot/common.ps1"
$config = Read-DeploymentConfig $ConfigPath
if ($MediaStorageName -notmatch '^[a-z0-9]{3,24}$') { throw 'Invalid media storage account name.' }
Assert-StudentSubscription | Out-Null
$template = "$PSScriptRoot/vehicle-media.bicep"
$parameters = @("location=$($config.location)", "mediaStorageName=$MediaStorageName")

if (-not $Apply -and -not $ConfigureApi -and -not $ConfigureDispatch -and -not $DisableDispatch) {
    Invoke-Azure @('bicep', 'build', '--file', $template, '--stdout') | Out-Null
    Write-Host 'Template compiled. What-if:'
    Invoke-Azure (@('deployment', 'group', 'what-if', '--resource-group', $config.resourceGroup,
        '--template-file', $template, '--parameters') + $parameters + @('--result-format', 'ResourceIdOnly')) | Write-Host
    return
}

if ($Apply) {
    $outputs = Invoke-Azure (@('deployment', 'group', 'create', '--resource-group', $config.resourceGroup,
        '--name', 'vinfast-vehicle-media', '--template-file', $template, '--parameters') + $parameters +
        @('--query', 'properties.outputs', '-o', 'json')) | ConvertFrom-Json
    # Names and URLs only; no keys (shared-key access is disabled).
    Write-Host ("Media account: {0}" -f $outputs.mediaStorageName.value)
    Write-Host ("Public base URL: {0}" -f $outputs.publicBaseUrl.value)
}

if ($ConfigureApi) {
    $clientId = (Invoke-Azure @('identity', 'show', '-g', $config.resourceGroup, '-n', 'vinfast-image-pull',
        '--query', 'clientId', '-o', 'tsv')).Trim()
    if ($clientId -notmatch '^[0-9a-f-]{36}$') { throw 'Could not read the API identity client id.' }
    Invoke-Azure @('containerapp', 'update', '-g', $config.resourceGroup, '-n', 'vinfast-api',
        '--set-env-vars', "VEHICLE_MEDIA_ACCOUNT=$MediaStorageName", 'VEHICLE_MEDIA_CONTAINER=vehicle-media',
        "AZURE_CLIENT_ID=$clientId", '-o', 'none') | Out-Null
    Write-Host 'vinfast-api now writes catalog media to Azure Blob.'
}

if ($ConfigureDispatch -or $DisableDispatch) {
    if ($ConfigureDispatch -and $DisableDispatch) { throw 'Choose one of -ConfigureDispatch / -DisableDispatch.' }
    $clientId = (Invoke-Azure @('identity', 'show', '-g', $config.resourceGroup, '-n', 'vinfast-image-pull',
        '--query', 'clientId', '-o', 'tsv')).Trim()
    if ($clientId -notmatch '^[0-9a-f-]{36}$') { throw 'Could not read the API identity client id.' }
    foreach ($app in @('vinfast-worker-control', 'vinfast-api')) {
        if ($ConfigureDispatch) {
            Invoke-Azure @('containerapp', 'update', '-g', $config.resourceGroup, '-n', $app,
                '--set-env-vars', "SHELLY_DISPATCH_TABLE_ACCOUNT=$MediaStorageName", 'SHELLY_DISPATCH_TABLE=shellyDispatch',
                'SHELLY_CONTROL_STATE=table', "AZURE_CLIENT_ID=$clientId", '-o', 'none') | Out-Null
        } else {
            Invoke-Azure @('containerapp', 'update', '-g', $config.resourceGroup, '-n', $app,
                '--remove-env-vars', 'SHELLY_DISPATCH_TABLE_ACCOUNT', 'SHELLY_DISPATCH_TABLE', 'SHELLY_CONTROL_STATE', '-o', 'none') | Out-Null
        }
        Write-Host ("{0}: dispatch gate {1}" -f $app, $(if ($ConfigureDispatch) { 'Azure Table' } else { 'Firestore' }))
    }
}
