param(
    [Parameter(Mandatory)][string]$ConfigPath,
    [Parameter(Mandatory)][string]$ApiUrl,
    [Parameter(Mandatory)][string]$FirebaseConfigPath,
    [string]$DashboardPath,
    [switch]$Deploy
)
. "$PSScriptRoot/common.ps1"
$config = Read-DeploymentConfig $ConfigPath
if ([string]::IsNullOrWhiteSpace($DashboardPath)) { $DashboardPath = Join-Path $script:RepoRoot 'web/dashboard' }
$DashboardPath = (Resolve-Path -LiteralPath $DashboardPath).Path
$package = Get-Content -LiteralPath (Join-Path $DashboardPath 'package.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($package.name -ne 'vinfast-battery-admin') { throw 'Unexpected admin workspace.' }
$nodeCommand = (Get-Command node -ErrorAction Stop).Source
$npmEntry = Join-Path (Split-Path (Get-Command npm.cmd -ErrorAction Stop).Source) 'node_modules/npm/bin/npm-cli.js'
if (-not (Test-Path -LiteralPath $npmEntry)) { throw 'npm CLI entrypoint missing.' }
function Invoke-AdminNpm {
    # npm.cmd/ps1 on Windows can select its adjacent Node instead of the one
    # pinned by PATH. Invoke the CLI explicitly with the selected toolchain.
    & $nodeCommand $npmEntry @args
    $script:LASTEXITCODE = $LASTEXITCODE
}
$uri = [uri]$ApiUrl
if ($uri.Scheme -ne 'https' -or $uri.Host -notlike '*.azurecontainerapps.io' -or $uri.Query -or $uri.UserInfo) { throw 'Use the generated staging API HTTPS origin.' }
$allowed = @('VITE_FIREBASE_API_KEY','VITE_FIREBASE_AUTH_DOMAIN','VITE_FIREBASE_PROJECT_ID',
    'VITE_FIREBASE_STORAGE_BUCKET','VITE_FIREBASE_MESSAGING_SENDER_ID','VITE_FIREBASE_APP_ID')
if ([IO.Path]::GetExtension($FirebaseConfigPath) -eq '.json') {
    $firebase = Get-Content -LiteralPath $FirebaseConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
} else {
    # Read only public Firebase Web SDK fields from the existing dashboard env.
    # No whole-env copy and no server secrets enter the frontend config.
    $firebase = @{}
    foreach ($line in (Get-Content -LiteralPath $FirebaseConfigPath -Encoding UTF8)) {
        if ($line -match '^\s*([A-Z][A-Z0-9_]*)\s*=(.*)$' -and $Matches[1] -in $allowed) {
            $value = $Matches[2].Trim()
            if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
                $value = $value.Substring(1, $value.Length - 2)
            }
            $firebase[$Matches[1]] = $value
        }
    }
}
if ($firebase.VITE_FIREBASE_PROJECT_ID -ne 'vinfast-873db') { throw 'Unexpected Firebase project; review the staging data boundary before deploying.' }
$saved = @{}
foreach ($key in @($allowed + @('VITE_API_BASE_URL','VITE_AI_API_BASE_URL','SWA_CLI_DEPLOYMENT_TOKEN'))) {
    $saved[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
}
try {
    foreach ($key in $allowed) {
        $value = $firebase.$key
        if ([string]::IsNullOrWhiteSpace($value) -or $value -match '[<>]') { throw 'Firebase WEB configuration is incomplete. Never use an Admin private key here.' }
        [Environment]::SetEnvironmentVariable($key, $value, 'Process')
    }
    $env:VITE_API_BASE_URL = $ApiUrl.TrimEnd('/')
    $env:VITE_AI_API_BASE_URL = $env:VITE_API_BASE_URL
    Push-Location $DashboardPath
    try {
        Invoke-AdminNpm ci
        if ($LASTEXITCODE -ne 0) { throw 'npm ci failed.' }
        $auditPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $auditText = Invoke-AdminNpm audit --json 2>&1
            $auditExit = $LASTEXITCODE
        } finally { $ErrorActionPreference = $auditPreference }
        if ($auditExit -notin @(0,1)) { throw 'Production dependency audit unavailable; publishing blocked.' }
        try { $audit = ($auditText -join "`n") | ConvertFrom-Json }
        catch { throw 'Production dependency audit malformed; publishing blocked.' }
        if (-not $audit.metadata -or -not $audit.metadata.vulnerabilities) { throw 'Missing dependency audit summary; publishing blocked.' }
        $vulnerabilities = $audit.metadata.vulnerabilities
        Write-Host "Full dependency audit: high=$($vulnerabilities.high), critical=$($vulnerabilities.critical)."
        if ($vulnerabilities.high -gt 0 -or $vulnerabilities.critical -gt 0) {
            throw 'Unresolved high/critical production dependencies; publishing blocked. Do not use audit fix --force blindly.'
        }
        Invoke-AdminNpm run lint
        if ($LASTEXITCODE -ne 0) { throw 'Dashboard lint failed.' }
        Invoke-AdminNpm run test
        if ($LASTEXITCODE -ne 0) { throw 'Dashboard tests failed.' }
        Invoke-AdminNpm run build
        if ($LASTEXITCODE -ne 0) { throw 'Dashboard build failed.' }
        # Firebase Web configuration is public; server credentials are not.
        # Compare known local server secrets in memory only, never print them.
        $privateValues = @()
        $serverEnv = Join-Path $script:RepoRoot 'web/.env.laptop'
        if (Test-Path -LiteralPath $serverEnv) {
            foreach ($line in (Get-Content -LiteralPath $serverEnv -Encoding UTF8)) {
                if ($line -match '^\s*(GEMINI_API_KEY|SHELLY_PROFILE_MASTER_KEY|AI_SERVER_INTERNAL_TOKEN|ADMIN_API_KEY)\s*=(.*)$') {
                    $value = $Matches[2].Trim().Trim('"').Trim("'")
                    if ($value.Length -ge 12) { $privateValues += $value }
                }
            }
        }
        foreach ($file in (Get-ChildItem -LiteralPath './dist' -File -Recurse)) {
            if ($file.Extension -notin @('.js','.css','.json','.html','.map')) { continue }
            $content = [IO.File]::ReadAllText($file.FullName)
            if ($content -match '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----') {
                throw 'Private key signature found in frontend artifact; publish blocked.'
            }
            foreach ($value in $privateValues) {
                if ($content.Contains($value)) { throw 'Server secret found in frontend artifact; publish blocked.' }
            }
        }
        Write-Host 'Frontend artifact scan passed (private-key signatures and allowlisted local server secrets only).'
        if ($Deploy) {
            $tier = Invoke-Azure @('staticwebapp', 'show', '-g', $config.resourceGroup, '-n', $config.adminName, '--query', 'sku.name', '-o', 'tsv')
            if ($tier -ne 'Free') { throw 'Only Static Web Apps Free is authorized.' }
            $env:SWA_CLI_DEPLOYMENT_TOKEN = Invoke-Azure @('staticwebapp', 'secrets', 'list', '-g', $config.resourceGroup, '-n', $config.adminName, '--query', 'properties.apiKey', '-o', 'tsv')
            # Token is inherited by the process, never placed in command arguments.
            $deployPreference = $ErrorActionPreference
            try {
                $ErrorActionPreference = 'Continue'
                $result = Invoke-AdminNpm exec --yes --package=@azure/static-web-apps-cli@2.0.10 -- swa deploy ./dist --env production 2>&1
                $deployExit = $LASTEXITCODE
            } finally { $ErrorActionPreference = $deployPreference }
            if ($deployExit -ne 0) { throw 'SWA deployment failed; diagnostics suppressed to protect token.' }
            Write-Host 'Frontend deployed to the staging Static Web App. Firebase authorized domain still needs verification.'
        }
    } finally { Pop-Location }
} finally {
    foreach ($key in $saved.Keys) { [Environment]::SetEnvironmentVariable($key, $saved[$key], 'Process') }
}
