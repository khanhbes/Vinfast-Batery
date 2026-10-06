Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$releases = Invoke-RestMethod -Uri 'https://aka.ms/swalocaldeploy' -TimeoutSec 45
$stable = @($releases | Where-Object version -eq 'stable')[0]
if (-not $stable -or $stable.buildId -notmatch '^[a-zA-Z0-9.-]+$') { throw 'Invalid Microsoft deployment client metadata.' }
$windows = $stable.files.'win-x64'
$uri = [uri]$windows.url
if ($uri.Scheme -ne 'https' -or $uri.UserInfo -or
    ($uri.Host -ne 'swalocaldeploy.azureedge.net' -and $uri.Host -notlike 'swalocaldeployv2-*.azurefd.net') -or
    $windows.sha -notmatch '^[a-fA-F0-9]{64}$') { throw 'Unexpected deployment client download origin/hash.' }
$cacheRoot = [IO.Path]::GetFullPath((Join-Path ([Environment]::GetFolderPath('UserProfile')) '.swa/deploy'))
$versionFolder = [IO.Path]::GetFullPath((Join-Path $cacheRoot $stable.buildId))
if (-not $versionFolder.StartsWith($cacheRoot + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe cache target.' }
[IO.Directory]::CreateDirectory($versionFolder) | Out-Null
$binary = Join-Path $versionFolder 'StaticSitesClient.exe'
function Get-ClientHash([string]$Path) {
    $sha = [Security.Cryptography.SHA256]::Create()
    $stream = [IO.File]::OpenRead($Path)
    try { return [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','').ToLowerInvariant() }
    finally { $stream.Dispose(); $sha.Dispose() }
}
if (-not (Test-Path -LiteralPath $binary) -or (Get-ClientHash $binary) -ne $windows.sha) {
    $download = Join-Path $versionFolder ('download-'+[guid]::NewGuid().ToString('N')+'.exe')
    Invoke-WebRequest -UseBasicParsing -Uri $uri.AbsoluteUri -OutFile $download -TimeoutSec 180
    if ((Get-ClientHash $download) -ne $windows.sha) { throw 'Deployment client checksum mismatch; downloaded file retained, not executed.' }
    if (Test-Path -LiteralPath $binary) { Copy-Item -LiteralPath $binary -Destination ($binary+'.before-'+[guid]::NewGuid().ToString('N')) }
    Move-Item -LiteralPath $download -Destination $binary -Force
}
$record = @{metadata=$stable; binary=$binary; checksum=(Get-ClientHash $binary)}
$metadataFile = Join-Path $cacheRoot 'StaticSitesClient.json'
if (Test-Path -LiteralPath $metadataFile) { Copy-Item -LiteralPath $metadataFile -Destination ($metadataFile+'.before-'+[guid]::NewGuid().ToString('N')) }
[IO.File]::WriteAllText($metadataFile,($record | ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
Write-Host "Microsoft deployment client cached; build=$($stable.buildId); SHA256=$($record.checksum). TLS/hash verification kept enabled."
