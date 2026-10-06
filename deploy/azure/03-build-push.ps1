param([Parameter(Mandatory)][string]$ConfigPath, [switch]$Push, [switch]$UseDockerDesktopProxy)
. "$PSScriptRoot/common.ps1"
$config = Read-DeploymentConfig $ConfigPath
$sha = (& git -C $script:RepoRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Cannot record source SHA.' }
$tag = "$($sha.Substring(0, 10))-qa-$([DateTime]::UtcNow.ToString('yyyyMMddHHmmss'))"
$registry = "$($config.registryName).azurecr.io"
foreach ($service in @('api', 'ai')) {
    $buildArguments = @('build', '--platform', 'linux/amd64')
    if ($UseDockerDesktopProxy) {
        # Predefined Docker proxy ARGs: not ENV, not redeclared in Dockerfile.
        # Opt-in for this Windows host only; never apply to Azure runtime.
        $buildArguments += @('--build-arg', 'HTTP_PROXY=http://http.docker.internal:3128',
            '--build-arg', 'HTTPS_PROXY=http://http.docker.internal:3128',
            '--build-arg', 'NO_PROXY=localhost,127.0.0.1')
    }
    if ($service -eq 'ai') {
        $buildArguments += @('--build-arg', 'AI_REQUIREMENTS=requirements-ai.azure.txt',
            '--build-arg', 'AI_PIP_TIMEOUT=120', '--build-arg', 'AI_PIP_RETRIES=2')
    }
    $buildArguments += @('-f', "$script:RepoRoot/web/Dockerfile.$service", '-t', "$registry/vinfast-${service}:$tag", "$script:RepoRoot/web")
    & docker @buildArguments
    if ($LASTEXITCODE -ne 0) { throw "Clean $service build failed. Nothing deployed." }
}
if ($Push) {
    Invoke-Azure @('acr', 'login', '--name', $config.registryName) | Out-Null
    foreach ($service in @('api', 'ai')) {
        & docker push "$registry/vinfast-${service}:$tag"
        if ($LASTEXITCODE -ne 0) { throw "Push $service failed. Nothing deployed." }
    }
}
Write-Host "Source SHA: $sha; image tag: $tag (includes uncommitted work; not an immutable Git-only build)."
Write-Host 'Record Docker image digests, source manifest and local boot results before container deployment.'
