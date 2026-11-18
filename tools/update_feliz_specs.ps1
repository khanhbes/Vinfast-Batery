<#
QA 166 (2): the Feliz 2025 catalog keeps only what VinFast publishes (400 W
charger, about 6 h 30 min from 0 to 100 %; no voltage or Ah), the estimate's
wall power goes 600 -> 450 W, and Feliz 2025 vehicles (yours by -VehicleId)
get chargerRatedW 400. See web/scripts/qa166_feliz_specs.py.

DRY RUN by default: it only reads and prints what would change. Run it once,
read the report, then run again with -Apply to write. The Firebase key never
leaves the container.

Run with PowerShell 7 (pwsh), signed in to az:
    pwsh tools/update_feliz_specs.ps1
    pwsh tools/update_feliz_specs.ps1 -Apply

Uses 2 to 4 `az containerapp exec` calls (the service allows about 6 in a
few minutes; on a 429 wait 10 minutes and run it again).
#>
param(
    [string]$VehicleId = 'tINp0QiXwEfrGg07iL78',
    [switch]$Apply,
    [string]$App = 'vinfast-api',
    [string]$ResourceGroup = 'rg-vinfast-battery'
)
$ErrorActionPreference = 'Stop'
$script = Join-Path $PSScriptRoot '..\web\scripts\qa166_feliz_specs.py'
if ($VehicleId -notmatch '^[A-Za-z0-9_-]{6,64}$') { throw 'VehicleId looks wrong.' }
$applyFlag = if ($Apply) { '1' } else { '0' }

# The command travels in a URL and is split on spaces: send the script
# zlib + base64, in chunks, with no space anywhere in the Python.
$encode = @'
import base64, sys, zlib
src = open(sys.argv[1], encoding="utf-8").read().replace("__VEHICLE__", sys.argv[2]).replace("__APPLY__", sys.argv[3])
print(base64.b64encode(zlib.compress(src.encode(), 9)).decode())
'@
$payload = ($encode | python -I - $script $VehicleId $applyFlag).Trim()
if (-not $payload) { throw 'Could not encode the script (is python on PATH?).' }

function Invoke-InContainer([string]$python) {
    if ($python -match '\s') { throw 'The container command must not contain spaces.' }
    $command = "env PYTHONIOENCODING=ascii:backslashreplace PYTHONWARNINGS=ignore python3 -c $python"
    $job = Start-Job -ScriptBlock {
        param($a, $g, $c)
        az containerapp exec -n $a -g $g --command $c 2>&1 | Out-String
    } -ArgumentList $App, $ResourceGroup, $command
    if (-not (Wait-Job $job -Timeout 240)) { Stop-Job $job; throw 'az containerapp exec timed out.' }
    $text = Receive-Job $job
    Remove-Job $job
    if ($text -match '429|Too Many Requests') { throw 'Rate limited by Azure. Wait 10 minutes and run again.' }
    return $text
}

$tmp = "/tmp/qa166s_$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$size = 1200
for ($i = 0; $i -lt $payload.Length; $i += $size) {
    $chunk = $payload.Substring($i, [Math]::Min($size, $payload.Length - $i))
    Write-Host "Sending part $([int]($i / $size) + 1)..."
    Invoke-InContainer "open('$tmp','a').write('$chunk')" | Out-Null
}
Write-Host $(if ($Apply) { 'Writing the changes...' } else { 'Reading (dry run, nothing is written)...' })
$run = "s=open('$tmp').read();assert(len(s)==$($payload.Length));b=__import__('base64');z=__import__('zlib');__import__('os').remove('$tmp');exec(z.decompress(b.b64decode(s)))"
$text = Invoke-InContainer $run

$match = [regex]::Match(($text -replace '\s', ''), '<<<([A-Za-z0-9+/=]+)>>>')
if (-not $match.Success) {
    Write-Host $text
    throw 'No result came back (see the output above).'
}
$decode = @'
import base64, sys, zlib, json
print(json.dumps(json.loads(zlib.decompress(base64.b64decode(sys.argv[1]))), ensure_ascii=False, indent=2))
'@
$decode | python -I - $match.Groups[1].Value
if (-not $Apply) { Write-Host 'Dry run only. Run again with -Apply to write these changes.' }
