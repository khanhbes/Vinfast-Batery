param(
    [Parameter(Mandatory)][string]$ConfigPath,
    [Parameter(Mandatory)][ValidateSet('vinfast-api','vinfast-ai')][string]$AppName,
    [Parameter(Mandatory)][string]$ImageTag,
    [Parameter(Mandatory)][string]$ParameterPath,
    [switch]$LocalGatePassed,
    [switch]$Apply
)
. "$PSScriptRoot/common.ps1"
$config = Read-DeploymentConfig $ConfigPath
if ($ImageTag -notmatch '^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,127}$' -or $ImageTag -eq 'latest') { throw 'Use an explicit source/manifest-tagged image.' }
if (-not $LocalGatePassed -and $Apply) { throw 'Complete clean-image build, isolated local boot and dashboard build first.' }
# The private file must use ARM deploymentParameters schema; secure values
# never appear in CLI arguments. Create it with Write-RestrictedJson outside Git.
$parameters = Get-Content -LiteralPath $ParameterPath -Raw -Encoding UTF8 | ConvertFrom-Json
$resolvedPrivatePath = [IO.Path]::GetFullPath($ParameterPath)
if ($resolvedPrivatePath.StartsWith($script:RepoRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or
    $resolvedPrivatePath -match '(?i)[\\/]OneDrive[^\\/]*[\\/]') {
    throw 'Store real deployment secrets outside the repository and OneDrive.'
}
foreach ($secret in $parameters.parameters.secrets.value.entries) {
    if ([string]::IsNullOrWhiteSpace($secret.value) -or $secret.value -match '[<>]') {
        throw 'Private parameter file still contains empty/placeholders. No deployment started.'
    }
}
$isApi = $AppName -eq 'vinfast-api'
$environmentId = Invoke-Azure @('containerapp', 'env', 'show', '-g', $config.resourceGroup, '-n', $config.environmentName, '--query', 'id', '-o', 'tsv')
$identityId = Invoke-Azure @('identity', 'show', '-g', $config.resourceGroup, '-n', 'vinfast-image-pull', '--query', 'id', '-o', 'tsv')
$variables = $parameters.parameters.variables.value
if ($isApi) {
    # AI is deployed first. Discover its real internal URL without regenerating
    # tokens or requiring a guessed FQDN in the private parameter file.
    $aiState = Invoke-Azure @('containerapp', 'show', '-g', $config.resourceGroup, '-n', 'vinfast-ai',
        '--query', '{environmentId:properties.managedEnvironmentId,ingress:properties.configuration.ingress}', '-o', 'json') | ConvertFrom-Json
    if ($aiState.environmentId -ne $environmentId -or $aiState.ingress.external -ne $false -or
        $aiState.ingress.fqdn -notlike '*.azurecontainerapps.io') {
        throw 'AI must have internal ingress in the same staging environment.'
    }
    $variables.AI_SERVER_URL.value = "https://$($aiState.ingress.fqdn)"
}
foreach ($variable in $variables.PSObject.Properties) {
    if ($variable.Value.value -match '[<>]') { throw 'Replace variable placeholders privately before deployment.' }
}
if ($isApi -and ($variables.AZURE_STAGING_HARDWARE_DISABLED.value -ne '1' -or $variables.APP_ENV.value -ne 'production')) {
    throw 'Azure staging must run production authentication and disable hardware mutations.'
}
if ($isApi -and ($variables.ADMIN_EMAILS.value -match '\*' -or $variables.CORS_ORIGINS.value -match '\*')) { throw 'Wildcard admin/CORS forbidden.' }
if ($isApi) {
    $firebaseSecret = $parameters.parameters.secrets.value.entries | Where-Object name -eq $variables.FIREBASE_CREDENTIALS_JSON.value
    try { $firebase = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($firebaseSecret.value)) | ConvertFrom-Json }
    catch { throw 'Firebase credential must be valid base64 JSON; value not printed.' }
    if ($firebase.project_id -ne 'vinfast-873db') { throw 'Firebase project identity differs from the existing project. Deployment stopped.' }
}
$temporary = Join-Path ([IO.Path]::GetTempPath()) ("vinfast-azure-$([guid]::NewGuid().ToString('N')).json")
try {
    foreach ($entry in @{
        appName=$AppName; location=$config.location; environmentId=$environmentId;
        registryServer="$($config.registryName).azurecr.io"; pullIdentityId=$identityId;
        image="$($config.registryName).azurecr.io/$AppName`:$ImageTag"
    }.GetEnumerator()) {
        $parameters.parameters | Add-Member -NotePropertyName $entry.Key -NotePropertyValue @{value=$entry.Value} -Force
    }
    Write-RestrictedJson $temporary $parameters
    $verb = if ($Apply) { 'create' } else { 'validate' }
    $url = Invoke-Azure @('deployment', 'group', $verb, '-g', $config.resourceGroup,
        '--name', "$AppName-staging", '--template-file', "$PSScriptRoot/container-app.bicep",
        '--parameters', "@$temporary", '-o', 'none')
    if ($Apply) {
        Write-Host (Invoke-Azure @('containerapp', 'show', '-g', $config.resourceGroup, '-n', $AppName,
            '--query', 'properties.configuration.ingress.fqdn', '-o', 'tsv'))
    }
} finally {
    # Exact file created by this process, never an existing directory/user file.
    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary }
}
