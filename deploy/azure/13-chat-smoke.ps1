param([Parameter(Mandatory)][string]$ConfigPath)
. "$PSScriptRoot/common.ps1"
$config = Read-DeploymentConfig $ConfigPath
$null = Assert-StudentSubscription $config.subscriptionName
$flag = Invoke-Azure @('containerapp','show','-g',$config.resourceGroup,'-n','vinfast-api',
    '--query',"properties.template.containers[0].env[?name=='AZURE_STAGING_HARDWARE_DISABLED'].value | [0]",'-o','tsv')
if ($flag.Trim() -ne '1') { throw 'Staging hardware lock could not be verified; QA stopped.' }
$container = Invoke-Azure @('containerapp','show','-g',$config.resourceGroup,'-n','vinfast-api',
    '--query','properties.template.containers[0].name','-o','tsv')
# The encoded payload is checked-in QA code, never a token/configuration.
# Credentials stay in the container environment and are never printed.
$source = [IO.File]::ReadAllText((Join-Path $script:RepoRoot 'tools/api_chat_smoke.py'))
$buffer = New-Object IO.MemoryStream
$gzip = New-Object IO.Compression.GZipStream($buffer, [IO.Compression.CompressionMode]::Compress, $true)
try { $bytes = [Text.Encoding]::UTF8.GetBytes($source); $gzip.Write($bytes,0,$bytes.Length) } finally { $gzip.Dispose() }
try { $encoded = [Convert]::ToBase64String($buffer.ToArray()) } finally { $buffer.Dispose() }
$expression = 'exec(__import__("gzip").decompress(__import__("base64").b64decode("' + $encoded + '")))'
$remote = "python -c '$expression'"
$revision = Invoke-Azure @('containerapp','show','-g',$config.resourceGroup,'-n','vinfast-api','--query','properties.latestReadyRevisionName','-o','tsv')
$replica = Invoke-Azure @('containerapp','replica','list','-g',$config.resourceGroup,'-n','vinfast-api','--revision',$revision.Trim(),'--query','[0].name','-o','tsv')
if ([string]::IsNullOrWhiteSpace($replica)) { throw 'No API replica; call health and retry once.' }
Write-Host 'Running synthetic chatbot QA only; zero relay commands. Read the JSON pass field, not just CLI exit.'
$azureCliPath = (Get-Command $script:AzCommand -ErrorAction Stop).Source
$azurePython = Join-Path (Split-Path (Split-Path $azureCliPath)) 'python.exe'
if (-not (Test-Path -LiteralPath $azurePython)) { throw 'Azure CLI Python missing.' }
# Avoid cmd.exe's 8191-character limit. This is the same interpreter/module
# as Microsoft's az.cmd, with no new authentication or downloaded executable.
& $azurePython -IBm azure.cli containerapp exec -g $config.resourceGroup -n vinfast-api --revision $revision.Trim() --replica $replica.Trim() --container $container.Trim() --command $remote --only-show-errors
if ($LASTEXITCODE -ne 0) { throw 'Container exec failed; chatbot not verified.' }
