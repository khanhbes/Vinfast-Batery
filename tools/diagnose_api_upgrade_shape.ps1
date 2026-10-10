# Read-only structural diagnosis. Never print env/secret contents.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../deploy/azure/common.ps1')
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '../deploy/azure/14-update-api-image.ps1'), [ref]$tokens, [ref]$errors)
$fn = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-ShapeHash' }, $false)
. ([ScriptBlock]::Create($fn.Extent.Text))
$app = Invoke-Azure @('containerapp', 'show', '-g', 'rg-vinfast-battery', '-n', 'vinfast-api', '-o', 'json') | ConvertFrom-Json
$expectedHash = '97cc9a831d36d064d2de19b43ea39e60911e70c19f5398205ba990b1509c22f9'
$variants = @()
foreach ($imageMode in @('keep', 'remove', 'null')) {
foreach ($metricsMode in @('keep', 'remove')) {
foreach ($secretValueMode in @('keep', 'remove', 'null')) {
    $candidate = $app | ConvertTo-Json -Depth 50 -Compress | ConvertFrom-Json
    if ($imageMode -eq 'remove') { $candidate.properties.template.containers[0].PSObject.Properties.Remove('imageType') }
    if ($imageMode -eq 'null') { $candidate.properties.template.containers[0].imageType = $null }
    if ($metricsMode -eq 'remove') { $candidate.properties.template.PSObject.Properties.Remove('customMetricsSettings') }
    foreach ($entry in $candidate.properties.template.containers[0].env) {
        $reference = $entry.PSObject.Properties['secretRef']
        $value = $entry.PSObject.Properties['value']
        if ($reference -and $reference.Value -and $value -and ($null -eq $value.Value -or $value.Value -eq '')) {
            if ($secretValueMode -eq 'remove') { $entry.PSObject.Properties.Remove('value') }
            if ($secretValueMode -eq 'null') { $entry.value = $null }
        }
    }
    $hash = Get-ShapeHash $candidate
    $variants += @{ imageType = $imageMode; customMetrics = $metricsMode; secretEmptyValue = $secretValueMode; hash = $hash; matchesOriginal = $hash -eq $expectedHash }
}}}
$old = Invoke-Azure @('containerapp', 'revision', 'show', '-g', 'rg-vinfast-battery', '-n', 'vinfast-api', '--revision', 'vinfast-api--3f2kpvk', '-o', 'json') | ConvertFrom-Json
function Differences($left, $right, [string]$path) {
    if ($null -eq $left -or $null -eq $right) {
        if ($null -ne $left -or $null -ne $right) { $path }
        return
    }
    if ($left -is [pscustomobject] -and $right -is [pscustomobject]) {
        $keys = @($left.PSObject.Properties.Name) + @($right.PSObject.Properties.Name) | Sort-Object -Unique
        foreach ($key in $keys) {
            $lp = $left.PSObject.Properties[$key]
            $rp = $right.PSObject.Properties[$key]
            if (-not $lp -or -not $rp) { "$path.$key" } else { Differences $lp.Value $rp.Value "$path.$key" }
        }
    } elseif ($left -is [array] -and $right -is [array]) {
        if ($left.Count -ne $right.Count) { "$path.length"; return }
        for ($i = 0; $i -lt $left.Count; $i++) { Differences $left[$i] $right[$i] "$path[$i]" }
    } elseif ($left -ne $right) { $path }
}
$result = @{
    variants = $variants
    optionalFieldTypes = @{
        imageType = $app.properties.template.containers[0].imageType
        customMetricsIsNull = $null -eq $app.properties.template.customMetricsSettings
    }
    revisionTemplateDifferentPaths = @(Differences $old.properties.template $app.properties.template 'template')
}
$result | ConvertTo-Json -Depth 8
