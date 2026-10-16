param([Parameter(Mandatory)][string]$ParameterPath)
. "$PSScriptRoot/common.ps1"
$config = Read-DeploymentConfig "$PSScriptRoot/staging.json"
$privatePath = [IO.Path]::GetFullPath($ParameterPath)
if ($privatePath.StartsWith($script:RepoRoot, [StringComparison]::OrdinalIgnoreCase) -or $privatePath -match '(?i)[\\/]OneDrive[^\\/]*[\\/]') {
    throw 'Contact parameters must be private, outside Git and OneDrive.'
}
$parameters = Get-Content -LiteralPath $privatePath -Raw | ConvertFrom-Json
try {
    $email = [Net.Mail.MailAddress]::new($parameters.parameters.contactEmail.value)
    if ($email.Address -ne $parameters.parameters.contactEmail.value) { throw 'Invalid contact' }
    Invoke-Azure @('deployment','group','validate','-g',$config.resourceGroup,'--name','vinfast-worker-pilot-budget-105',
        '--template-file',"$PSScriptRoot/worker-pilot-budget.bicep",'--parameters',"@$privatePath",'-o','none') | Out-Null
    Invoke-Azure @('deployment','group','create','-g',$config.resourceGroup,'--name','vinfast-worker-pilot-budget-105',
        '--template-file',"$PSScriptRoot/worker-pilot-budget.bicep",'--parameters',"@$privatePath",'-o','none') | Out-Null
    $rgId = Invoke-Azure @('group','show','-n',$config.resourceGroup,'--query','id','-o','tsv')
    $state = Invoke-Azure @('rest','--method','get','--url',
        "https://management.azure.com$rgId/providers/Microsoft.Consumption/budgets/vinfast-worker-pilot-monthly?api-version=2024-08-01",'-o','json') | ConvertFrom-Json
    $rules = @($state.properties.notifications.PSObject.Properties)
    if ($state.properties.amount -ne 20 -or $state.properties.timeGrain -ne 'Monthly' -or
        $state.properties.filter.dimensions -or $rules.Count -ne 3) { throw 'Budget verification failed' }
    foreach ($rule in $rules) {
        if (-not $rule.Value.enabled -or $rule.Value.contactEmails.Count -ne 1 -or $rule.Value.contactEmails[0] -ne $email.Address) { throw 'Notification verification failed' }
    }
    [pscustomobject]@{ budgetName=$state.name; amount=20; timeGrain='Monthly'; workerOnly=$false;
        notificationCount=3; recipientVerified=$true; hardSpendCap=$false; scope='resourceGroup' } | ConvertTo-Json
} catch {
    throw 'Pilot budget operation failed. No email or private diagnostics printed; check Cost Management permissions/offer in Portal.'
}
