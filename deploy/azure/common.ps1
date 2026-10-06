Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:RepoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$script:AzCommand = 'az'
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    $candidate = 'C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd'
    if (-not (Test-Path $candidate)) { throw 'Azure CLI missing. Install Microsoft.AzureCLI and sign in.' }
    $script:AzCommand = $candidate
}

function Invoke-Azure {
    param([string[]]$Arguments)
    # Capture diagnostics: never echo secret-bearing CLI arguments or responses.
    # Windows PowerShell treats native stderr as ErrorRecords. With Stop it
    # throws before we can sanitize diagnostics (including secure deployments).
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $result = & $script:AzCommand @Arguments --only-show-errors 2>&1
        $commandExit = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    if ($commandExit -ne 0) { throw "Azure command failed (exit $commandExit). Inspect the operation in Portal; no secret diagnostics printed." }
    return ($result -join "`n")
}

function Assert-StudentSubscription {
    param([string]$ExpectedName = 'Azure for Students')
    $account = Invoke-Azure @('account', 'show', '-o', 'json') | ConvertFrom-Json
    if ($account.name -ne $ExpectedName -or $account.name -ne 'Azure for Students' -or $account.state -ne 'Enabled') {
        throw 'Active subscription is not the intended Enabled Azure for Students subscription.'
    }
    return $account
}

function Read-DeploymentConfig {
    param([string]$Path)
    $config = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($config.location -ne 'eastasia' -or $config.resourceGroup -ne 'rg-vinfast-battery') {
        throw 'Unexpected staging location/resource group. Review configuration before deploying.'
    }
    Assert-StudentSubscription $config.subscriptionName | Out-Null
    return $config
}

function Write-RestrictedJson {
    param([string]$Path, [object]$Data)
    # A secret deployment parameter file is outside Git and readable only by
    # the current user. Never put the resulting file in OneDrive or the repo.
    $current = [Security.Principal.WindowsIdentity]::GetCurrent().User
    [IO.File]::WriteAllText($Path, '', [Text.UTF8Encoding]::new($false))
    # Use the Windows .NET ACL API directly: module autoload/type-data conflicts
    # must not prevent secure deployment or lead to a permissions bypass.
    $fileInfo = [IO.FileInfo]::new($Path)
    $acl = $fileInfo.GetAccessControl()
    $acl.SetAccessRuleProtection($true, $false)
    $acl.SetAccessRule([Security.AccessControl.FileSystemAccessRule]::new($current, 'FullControl', 'Allow'))
    $fileInfo.SetAccessControl($acl)
    [IO.File]::WriteAllText($Path, ($Data | ConvertTo-Json -Depth 30), [Text.UTF8Encoding]::new($false))
}
