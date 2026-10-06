param([Parameter(Mandatory)][string]$ApiUrl)
$ErrorActionPreference = 'Stop'
$uri = [uri]$ApiUrl
if ($uri.Scheme -ne 'https' -or $uri.Host -notlike '*.azurecontainerapps.io' -or $uri.UserInfo -or $uri.Query) { throw 'Use the generated staging HTTPS origin.' }
foreach ($path in @('/api/health','/api/ready')) {
    $response = Invoke-WebRequest -Uri "$($ApiUrl.TrimEnd('/'))$path" -TimeoutSec 120 -UseBasicParsing
    if ($response.StatusCode -ne 200 -or -not $response.Headers['X-Request-Id']) { throw "$path failed readiness/request-ID contract." }
    Write-Host "$path : HTTP 200; request-ID present"
}
Write-Host 'Only liveness/readiness checked. Auth, private AI, persistence and Android still require separate acceptance.'
