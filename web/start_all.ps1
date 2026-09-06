<#
.SYNOPSIS
  Tương thích ngược: chuyển tiếp tới web/start_server_local.ps1 (Cách 1 - Local Dev)
#>
[CmdletBinding()]
param()

$target = Join-Path $PSScriptRoot "start_server_local.ps1"
& $target @args
