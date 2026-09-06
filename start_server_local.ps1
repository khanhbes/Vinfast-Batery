<#
.SYNOPSIS
  Khởi động server cục bộ (Cách 1 - Local Dev / Không Docker):
  - AI Server (FastAPI) trên cổng 8001
  - Unified API (Flask) trên cổng 5000
  - Admin Portal (React/Vite) trên cổng 3000

.EXAMPLE
  .\start_server_local.ps1
#>
[CmdletBinding()]
param()

$target = Join-Path $PSScriptRoot "web\start_server_local.ps1"
if (Test-Path $target) {
    & $target @args
} else {
    throw "Không tìm thấy file: $target"
}
