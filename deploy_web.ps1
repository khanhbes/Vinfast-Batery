<#
.SYNOPSIS
  Tương thích ngược: chuyển tiếp tới start_server_docker.ps1 (Cách 2 - Docker & Tailscale Funnel)
#>
[CmdletBinding()]
param(
    [ValidateSet('all', 'api', 'ai', 'dashboard')]
    [string]$Service = 'all',
    [string]$PublicUrl = 'https://khanhbes.tailaafca5.ts.net',
    [switch]$NoCache
)

$target = Join-Path $PSScriptRoot "start_server_docker.ps1"
& $target -Service $Service -PublicUrl $PublicUrl -NoCache:$NoCache
