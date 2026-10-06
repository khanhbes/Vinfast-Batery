param([string]$ConfigPath, [string]$ImageTag, [string]$ParameterPath, [switch]$LocalGatePassed, [switch]$Apply)
& "$PSScriptRoot/deploy-container.ps1" -ConfigPath $ConfigPath -ImageTag $ImageTag -ParameterPath $ParameterPath -AppName vinfast-api -LocalGatePassed:$LocalGatePassed -Apply:$Apply
