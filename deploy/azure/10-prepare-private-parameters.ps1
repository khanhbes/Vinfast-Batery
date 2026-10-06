param(
    [Parameter(Mandatory)][string]$PrivateEnvPath,
    [string]$AiUrl = '',
    [Parameter(Mandatory)][string]$DashboardUrl
)
. "$PSScriptRoot/common.ps1"
$aiUri = if ($AiUrl) { [uri]$AiUrl } else { $null }
$adminUri = [uri]$DashboardUrl
if (($aiUri -and ($aiUri.Scheme -ne 'https' -or $aiUri.Host -notlike '*.azurecontainerapps.io' -or
    $aiUri.Query -or $aiUri.UserInfo -or $aiUri.AbsolutePath -ne '/')) -or
    $adminUri.Scheme -ne 'https' -or $adminUri.Host -notlike '*.azurestaticapps.net' -or
    $adminUri.Query -or $adminUri.UserInfo -or $adminUri.AbsolutePath -ne '/') {
    throw 'Use the generated HTTPS staging AI/Admin origins only.'
}
$needed = @('FIREBASE_CREDENTIALS_JSON','SHELLY_PROFILE_MASTER_KEY','GEMINI_API_KEY','GEMINI_CHAT_MODEL','ADMIN_EMAILS')
$values = @{}
foreach ($line in (Get-Content -LiteralPath $PrivateEnvPath -Encoding UTF8)) {
    if ($line -match '^\s*([A-Z][A-Z0-9_]*)\s*=(.*)$' -and $Matches[1] -in $needed) {
        $value = $Matches[2].Trim()
        if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        $values[$Matches[1]] = $value
    }
}
foreach ($key in $needed) {
    if (-not $values.ContainsKey($key) -or [string]::IsNullOrWhiteSpace($values[$key]) -or $values[$key] -match '^<|changeme|your[_-]|\$\{') {
        throw "Missing/unresolved required variable: $key. Values are not printed."
    }
}
try {
    # Existing server supports raw JSON and base64. Normalize privately for ARM.
    $credentialJson = if ($values.FIREBASE_CREDENTIALS_JSON.TrimStart().StartsWith('{')) {
        $values.FIREBASE_CREDENTIALS_JSON
    } else {
        [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($values.FIREBASE_CREDENTIALS_JSON))
    }
    $credential = $credentialJson | ConvertFrom-Json
    if ($credential.project_id -ne 'vinfast-873db' -or $credential.type -ne 'service_account' -or -not $credential.private_key) {
        throw 'Unexpected Firebase credential.'
    }
    $values.FIREBASE_CREDENTIALS_JSON = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($credentialJson))
} catch { throw 'Firebase credential validation failed; no content printed.' }
$rng = [Security.Cryptography.RandomNumberGenerator]::Create()
try {
    $tokenBytes = New-Object byte[] 32
    $adminBytes = New-Object byte[] 32
    $rng.GetBytes($tokenBytes)
    $rng.GetBytes($adminBytes)
    $token = [Convert]::ToBase64String($tokenBytes)
    $adminToken = [Convert]::ToBase64String($adminBytes)
} finally { $rng.Dispose() }
$api = Get-Content -LiteralPath "$PSScriptRoot/api.parameters.example.json" -Raw -Encoding UTF8 | ConvertFrom-Json
$ai = Get-Content -LiteralPath "$PSScriptRoot/ai.parameters.example.json" -Raw -Encoding UTF8 | ConvertFrom-Json
$apiSecrets = @{ firebase = $values.FIREBASE_CREDENTIALS_JSON; 'ai-token' = $token; 'admin-key' = $adminToken; 'vault-key' = $values.SHELLY_PROFILE_MASTER_KEY }
foreach ($secret in $api.parameters.secrets.value.entries) { $secret.value = $apiSecrets[$secret.name] }
$api.parameters.variables.value.ADMIN_EMAILS.value = $values.ADMIN_EMAILS
$api.parameters.variables.value.AI_SERVER_URL.value = if ($AiUrl) { $AiUrl.TrimEnd('/') } else { 'https://<internal-ai-fqdn>' }
$api.parameters.variables.value.DASHBOARD_URL.value = $DashboardUrl.TrimEnd('/')
$api.parameters.variables.value.CORS_ORIGINS.value = $DashboardUrl.TrimEnd('/')
foreach ($secret in $ai.parameters.secrets.value.entries) {
    $secret.value = if ($secret.name -eq 'ai-token') { $token } else { $values.GEMINI_API_KEY }
}
$ai.parameters.variables.value.GEMINI_CHAT_MODEL.value = $values.GEMINI_CHAT_MODEL
$privateDir = Join-Path ([IO.Path]::GetTempPath()) "vinfast-azure-$([Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $privateDir -ErrorAction Stop | Out-Null
# No whole-env copying. Only allowlisted secrets; new internal/admin tokens.
Write-RestrictedJson -Path (Join-Path $privateDir 'api.private.json') -Data $api
Write-RestrictedJson -Path (Join-Path $privateDir 'ai.private.json') -Data $ai
Write-Host "Private parameters prepared with restricted ACL outside Git/OneDrive: $privateDir"
Write-Host 'No cloud operation performed. Retain until deployment succeeds, then securely manage/remove these exact files.'
if (-not $AiUrl) { Write-Host 'Deploy AI first. API deploy discovers and verifies its actual internal FQDN, preserving the same private AI token.' }
