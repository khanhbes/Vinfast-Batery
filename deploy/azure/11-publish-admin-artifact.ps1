param(
    [Parameter(Mandatory)][string]$ConfigPath,
    [Parameter(Mandatory)][string]$ArtifactPath,
    [Parameter(Mandatory)][ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$ExpectedIndexSha256,
    [Parameter(Mandatory)][string]$VerifiedBuildLog,
    [switch]$UseNativeClient
)
. "$PSScriptRoot/common.ps1"
$config = Read-DeploymentConfig $ConfigPath
$artifact = (Resolve-Path -LiteralPath $ArtifactPath).Path
$index = Join-Path $artifact 'index.html'
function Get-ArtifactIndexHash {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($index))).Replace('-','') }
    finally { $sha.Dispose() }
}
if ((Get-ArtifactIndexHash) -ne $ExpectedIndexSha256) {
    throw 'Artifact changed after verification; publishing blocked.'
}
# This is a recovery publisher for an already verified build, not a substitute
# for the quality pipeline. Keep the original failed/timeout deployment result.
$evidence = Get-Content -LiteralPath $VerifiedBuildLog -Raw -Encoding UTF8
foreach ($marker in @('Full dependency audit: high=0, critical=0.', '# fail 0', 'built in', 'Frontend artifact scan passed')) {
    if (-not $evidence.Contains($marker)) { throw 'Incomplete quality evidence; run 07-build-admin first.' }
}
if (-not (Test-Path -LiteralPath (Join-Path $artifact 'staticwebapp.config.json'))) { throw 'SPA configuration missing.' }
$tier = Invoke-Azure @('staticwebapp','show','-g',$config.resourceGroup,'-n',$config.adminName,'--query','sku.name','-o','tsv')
if ($tier -ne 'Free') { throw 'Only the authorized Static Web Apps Free resource may be published.' }
$nodeCommand = (Get-Command node -ErrorAction Stop).Source
$npmEntry = Join-Path (Split-Path (Get-Command npm.cmd -ErrorAction Stop).Source) 'node_modules/npm/bin/npm-cli.js'
$savedToken = [Environment]::GetEnvironmentVariable('SWA_CLI_DEPLOYMENT_TOKEN','Process')
$nativeSaved = @{}
try {
    $env:SWA_CLI_DEPLOYMENT_TOKEN = Invoke-Azure @('staticwebapp','secrets','list','-g',$config.resourceGroup,'-n',$config.adminName,'--query','properties.apiKey','-o','tsv')
    $savedPreference = $ErrorActionPreference
    # Microsoft's uploader forbids cwd inside the artifact. The parent QA
    # workspace avoids both that constraint and scanning the OneDrive repo.
    $publishWorkspace = Split-Path -Parent $artifact
    Push-Location -LiteralPath $publishWorkspace
    try {
        $ErrorActionPreference = 'Continue'
        if ($UseNativeClient) {
            $cacheRecordPath = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.swa/deploy/StaticSitesClient.json'
            $client = Get-Content -LiteralPath $cacheRecordPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $clientHashEngine = [Security.Cryptography.SHA256]::Create()
            $clientStream = [IO.File]::OpenRead($client.binary)
            try { $clientHash = [BitConverter]::ToString($clientHashEngine.ComputeHash($clientStream)).Replace('-','').ToLowerInvariant() }
            finally { $clientStream.Dispose(); $clientHashEngine.Dispose() }
            if ($clientHash -ne $client.checksum -or $clientHash -ne $client.metadata.files.'win-x64'.sha) { throw 'Deployment client checksum mismatch.' }
            $nativeEnv = @{
                DEPLOYMENT_ACTION='upload'; DEPLOYMENT_PROVIDER='SwaCli'; REPOSITORY_BASE=$publishWorkspace
                SKIP_APP_BUILD='true'; SKIP_API_BUILD='true'; APP_LOCATION=$artifact
                API_LOCATION=''; DATA_API_LOCATION=''; CONFIG_FILE_LOCATION=$artifact
                DEPLOYMENT_ENVIRONMENT=''; VERBOSE='false'; DEPLOYMENT_TOKEN=$env:SWA_CLI_DEPLOYMENT_TOKEN
            }
            foreach ($key in $nativeEnv.Keys) {
                $nativeSaved[$key] = [Environment]::GetEnvironmentVariable($key,'Process')
                [Environment]::SetEnvironmentVariable($key,$nativeEnv[$key],'Process')
            }
            $diagnostics = & $client.binary 2>&1
        } else {
            $diagnostics = & $nodeCommand $npmEntry exec --yes --package=@azure/static-web-apps-cli@2.0.10 -- swa deploy $artifact --env production 2>&1
        }
        $publishExit = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $savedPreference
        Pop-Location
    }
    if ($publishExit -ne 0) {
        $diagnosticText = (@($diagnostics | ForEach-Object {
            if ($_ -is [Management.Automation.ErrorRecord]) { $_.Exception.Message } else { $_.ToString() }
        }) -join "`n")
        # Print only fixed classification labels, never provider messages.
        $categories = @{
            'CLI_MODULE_ERROR' = 'ERR_REQUIRE_ESM|Cannot find module'
            'NODE_NATIVE_CRASH' = 'UV_HANDLE_CLOSING|Assertion failed'
            'TLS_FAILURE' = 'CERT_|certificate|TLS|SSL'
            'NETWORK_FAILURE' = 'ETIMEDOUT|ECONNRESET|ENOTFOUND|ECONNREFUSED|fetch failed'
            'AUTH_REJECTED' = 'Unauthorized|Forbidden|authentication failed|invalid token'
            'DEPLOY_CLIENT_FAILURE' = 'StaticSitesClient|deployment client|deploy client'
            'CLI_ARGUMENT_ERROR' = 'unknown option|unknown command|invalid argument'
        }
        $matched = @($categories.Keys | Where-Object { $diagnosticText -match $categories[$_] } | Sort-Object)
        if (-not $matched.Count) { $matched = @('UNCLASSIFIED') }
        $safeText = $diagnosticText.Replace($env:SWA_CLI_DEPLOYMENT_TOKEN,'[redacted-token]')
        $safeText = $safeText -replace '(?i)https?://[^\s]+','[redacted-url]'
        $safeText = $safeText -replace '(?i)[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}','[redacted-email]'
        $safeText = $safeText -replace '[A-Za-z0-9_+/=.-]{16,}','[redacted-value]'
        $safeLines = @($safeText -split "`r?`n" | Where-Object { $_ -match '(?i)error|failed|failure|cannot|could not|not found|requires|exception' } | Select-Object -Last 4)
        $summary = ($safeLines -join ' ').Trim()
        if ($summary.Length -gt 500) { $summary = $summary.Substring(0,500) }
        throw "Artifact publish failed (exit $publishExit; classes=$($matched -join ','); safe summary=$summary)."
    }
    if ((Get-ArtifactIndexHash) -ne $ExpectedIndexSha256) { throw 'Artifact changed during publish.' }
    Write-Host "Verified admin artifact published; index SHA-256=$ExpectedIndexSha256. Live hash/UI verification still required."
} finally {
    foreach ($key in $nativeSaved.Keys) { [Environment]::SetEnvironmentVariable($key,$nativeSaved[$key],'Process') }
    [Environment]::SetEnvironmentVariable('SWA_CLI_DEPLOYMENT_TOKEN',$savedToken,'Process')
}
