param([switch]$RegisterProviders)
. "$PSScriptRoot/common.ps1"
$account = Assert-StudentSubscription
Write-Host "Subscription: $($account.name); state: $($account.state)"
foreach ($namespace in @('Microsoft.App', 'Microsoft.ContainerRegistry', 'Microsoft.Storage', 'Microsoft.Web', 'Microsoft.ManagedIdentity')) {
    if ($RegisterProviders) { Invoke-Azure @('provider', 'register', '--namespace', $namespace, '--wait', '-o', 'none') | Out-Null }
    $state = Invoke-Azure @('provider', 'show', '--namespace', $namespace, '--query', 'registrationState', '-o', 'tsv')
    Write-Host "$namespace : $state"
}
Write-Host 'Verify remaining credit/free entitlements in Portal. No cost-bearing resources created.'
