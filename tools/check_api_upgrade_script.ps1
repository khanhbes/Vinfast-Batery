# Execute only pure validation functions, never the rollout entrypoint/CLI.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$path = Join-Path $PSScriptRoot '../deploy/azure/14-update-api-image.ps1'
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Rollout script has syntax errors.' }
foreach ($name in @('Get-ShapeHash', 'Assert-ApiGuard', 'Assert-PeersUnchanged', 'Get-VerifiedGateRole')) {
    $definition = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $false)
    if (-not $definition) { throw 'Required pure validator is absent.' }
    . ([ScriptBlock]::Create($definition.Extent.Text))
}
function New-Fixture {
    return (@{
        identity = @{ type = 'UserAssigned'; userAssignedIdentities = @{ fixture = @{} } }
        properties = @{
            managedEnvironmentId = 'fixture-environment'
            configuration = @{ activeRevisionsMode = 'Single'; ingress = @{ external = $true }; secrets = @(@{ name = 'fixture-secret' }) }
            template = @{
                revisionSuffix = 'before'
                containers = @(@{ image = 'fixture:old'; name = 'api'; env = @(@{ name = 'AZURE_STAGING_HARDWARE_DISABLED'; value = '1' }, @{ name = 'FIREBASE_CREDENTIALS_JSON'; secretRef = 'fixture-secret' }, @{ name = 'APP_ENV'; value = 'production' }); resources = @{ cpu = 0.25; memory = '0.5Gi' } })
                scale = @{ minReplicas = 0; maxReplicas = 1 }
                volumes = @(@{ name = 'fixture-volume'; storageType = 'AzureFile' })
            }
        }
    } | ConvertTo-Json -Depth 20 | ConvertFrom-Json)
}
$assertions = 0
function Check([bool]$condition, [string]$label) {
    if (-not $condition) { throw "Validation failed: $label" }
    $script:assertions++
}
function Must-Deny([scriptblock]$action) {
    $denied = $false
    try { & $action } catch { $denied = $true }
    Check $denied 'unsafe input must be rejected'
}
$before = New-Fixture
Assert-ApiGuard $before
Check ((Get-ShapeHash $before) -eq (Get-ShapeHash (New-Fixture))) 'stable hashing'
$imageOnly = New-Fixture
$imageOnly.properties.template.containers[0].image = 'fixture:new'
$imageOnly.properties.template.revisionSuffix = 'after'
Check ((Get-ShapeHash $before) -eq (Get-ShapeHash $imageOnly)) 'only image/suffix may differ'
$emptySecretValue = New-Fixture
$emptySecretValue.properties.template.containers[0].env[1] | Add-Member -NotePropertyName value -NotePropertyValue ''
Check ((Get-ShapeHash $before) -eq (Get-ShapeHash $emptySecretValue)) 'Azure empty secretRef metadata is equivalent'
$emptySecretValue.properties.template.containers[0].env[1].value = $null
Check ((Get-ShapeHash $before) -eq (Get-ShapeHash $emptySecretValue)) 'null secretRef metadata is equivalent'
$emptySecretValue.properties.template.containers[0].env[1].value = 'fixture-nonempty'
Check ((Get-ShapeHash $before) -ne (Get-ShapeHash $emptySecretValue)) 'nonempty secret value cannot be ignored'
foreach ($field in @('policy', 'secretRef', 'scale', 'volume', 'identity', 'ingress', 'memory')) {
    $changed = New-Fixture
    switch ($field) {
        'policy' { $changed.properties.template.containers[0].env[0].value = '0' }
        'secretRef' { $changed.properties.template.containers[0].env[1].secretRef = 'different' }
        'scale' { $changed.properties.template.scale.maxReplicas = 2 }
        'volume' { $changed.properties.template.volumes[0].name = 'different' }
        'identity' { $changed.identity.type = 'SystemAssigned' }
        'ingress' { $changed.properties.configuration.ingress.external = $false }
        'memory' { $changed.properties.template.containers[0].resources.memory = '1Gi' }
    }
    Check ((Get-ShapeHash $before) -ne (Get-ShapeHash $changed)) "detect $field changes"
}
$unsafe = New-Fixture
$unsafe.properties.template.containers[0].env[0].value = '0'
Must-Deny { Assert-ApiGuard $unsafe }
$unsafe = New-Fixture
$unsafe.properties.configuration.activeRevisionsMode = 'Multiple'
Must-Deny { Assert-ApiGuard $unsafe }
$unsafe = New-Fixture
$unsafe.properties.template.containers[0].env[2].value = 'testing'
Must-Deny { Assert-ApiGuard $unsafe }
$unsafe = New-Fixture
$unsafe.properties.template.containers += $unsafe.properties.template.containers[0]
Must-Deny { Assert-ApiGuard $unsafe }
# Unlocked is opt-in only: flag 0 plus an explicit worker scope.
$unlocked = New-Fixture
$unlocked.properties.template.containers[0].env[0].value = '0'
Must-Deny { Assert-ApiGuard $unlocked 'Unlocked' }
$unlocked.properties.template.containers[0].env += [pscustomobject]@{ name = 'SMART_CHARGE_WORKER_SCOPE'; value = 'azure-staging-1' }
Assert-ApiGuard $unlocked 'Unlocked'
Must-Deny { Assert-ApiGuard $unlocked }
Must-Deny { Assert-ApiGuard (New-Fixture) 'Unlocked' }
$unlocked.properties.template.containers[0].env[3].value = 'bad scope!'
Must-Deny { Assert-ApiGuard $unlocked 'Unlocked' }
$peers = @(@{ name = 'ai'; revision = 'old'; image = 'fixture:ai'; shapeHash = 'same' })
Assert-PeersUnchanged $peers $peers
Must-Deny { Assert-PeersUnchanged $peers @(@{ name = 'ai'; revision = 'new'; image = 'fixture:ai'; shapeHash = 'same' }) }
Must-Deny { Assert-PeersUnchanged $peers @($peers[0], $peers[0]) }
function Gate($command) { return [pscustomobject]@{ command = $command; exitCode = 0; timedOut = $false; cleanupError = $null } }
Check ((Get-VerifiedGateRole (Gate @('docker', 'build', '-f', 'web/Dockerfile.api'))) -eq 'build') 'production API build receipt'
Check ((Get-VerifiedGateRole (Gate @('powershell', '-File', 'deploy/azure/08-local-boot-smoke.ps1', '-Services', 'api'))) -eq 'boot') 'API-only boot receipt'
Check ((Get-VerifiedGateRole (Gate @('docker', 'run', '--network', 'none', 'qa', 'python', '-m', 'pytest', 'tests'))) -eq 'backend') 'isolated full backend receipt'
Check ((Get-VerifiedGateRole (Gate @('docker', 'build', '-f', 'web/Dockerfile.api-tests'))) -eq 'other') 'QA build cannot substitute for API build'
Check ((Get-VerifiedGateRole (Gate @('docker', 'run', '--network', 'none', 'qa', 'pytest', 'tests/test_one.py'))) -eq 'other') 'targeted tests cannot substitute for full backend'
$bad = Gate @('docker', 'build', '-f', 'web/Dockerfile.api')
$bad.timedOut = $true
Must-Deny { Get-VerifiedGateRole $bad }
$bad = Gate @('docker', 'build', '-f', 'web/Dockerfile.api')
$bad.exitCode = 1
Must-Deny { Get-VerifiedGateRole $bad }
Write-Host "API rollout validators: $assertions assertions Pass; no CLI/network/secrets/relay calls."
