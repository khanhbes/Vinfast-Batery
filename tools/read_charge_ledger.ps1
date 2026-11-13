<#
QA 157: read the learned charge profile of ONE vehicle from production.
READ ONLY: nothing is written to Firestore. The Firebase key never leaves
the container; only the profile comes back, saved to -OutFile.

Run with PowerShell 7 (pwsh), signed in to az:
    pwsh tools/read_charge_ledger.ps1

Uses 2 to 4 `az containerapp exec` calls (the service allows about 6 in a
few minutes; on a 429 wait 10 minutes and run it again).
#>
param(
    [string]$VehicleId = 'tINp0QiXwEfrGg07iL78',
    [string]$App = 'vinfast-api',
    [string]$ResourceGroup = 'rg-vinfast-battery',
    [string]$OutFile = (Join-Path $PSScriptRoot '..\charge-ledger.local.json')
)
$ErrorActionPreference = 'Stop'
$script = Join-Path $PSScriptRoot '..\web\scripts\qa157_read_charge_ledger.py'
if ($VehicleId -notmatch '^[A-Za-z0-9_-]{6,64}$') { throw 'VehicleId looks wrong.' }

# The command travels in a URL and is split on spaces: send the script
# zlib + base64, in chunks, with no space anywhere in the Python.
$encode = @'
import base64, sys, zlib
src = open(sys.argv[1], encoding="utf-8").read().replace("__VEHICLE__", sys.argv[2])
print(base64.b64encode(zlib.compress(src.encode(), 9)).decode())
'@
$payload = ($encode | python -I - $script $VehicleId).Trim()
if (-not $payload) { throw 'Could not encode the script (is python on PATH?).' }

function Invoke-InContainer([string]$python) {
    if ($python -match '\s') { throw 'The container command must not contain spaces.' }
    $command = "env PYTHONIOENCODING=ascii:backslashreplace PYTHONWARNINGS=ignore python3 -c $python"
    $job = Start-Job -ScriptBlock {
        param($a, $g, $c)
        az containerapp exec -n $a -g $g --command $c 2>&1 | Out-String
    } -ArgumentList $App, $ResourceGroup, $command
    if (-not (Wait-Job $job -Timeout 180)) { Stop-Job $job; throw 'az containerapp exec timed out.' }
    $text = Receive-Job $job
    Remove-Job $job
    if ($text -match '429|Too Many Requests') { throw 'Rate limited by Azure. Wait 10 minutes and run again.' }
    return $text
}

$tmp = "/tmp/qa157_$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$size = 1200
for ($i = 0; $i -lt $payload.Length; $i += $size) {
    $chunk = $payload.Substring($i, [Math]::Min($size, $payload.Length - $i))
    Write-Host "Sending part $([int]($i / $size) + 1)..."
    Invoke-InContainer "open('$tmp','a').write('$chunk')" | Out-Null
}
Write-Host 'Reading the profile...'
$run = "s=open('$tmp').read();assert(len(s)==$($payload.Length));b=__import__('base64');z=__import__('zlib');__import__('os').remove('$tmp');exec(z.decompress(b.b64decode(s)))"
$text = Invoke-InContainer $run

$match = [regex]::Match(($text -replace '\s', ''), '<<<([A-Za-z0-9+/=]+)>>>')
if (-not $match.Success) {
    Write-Host $text
    throw 'No result came back (see the output above).'
}
$decode = @'
import base64, sys, zlib, json
data = json.loads(zlib.decompress(base64.b64decode(sys.argv[1])))
json.dump(data, open(sys.argv[2], "w", encoding="utf-8"), ensure_ascii=False, indent=1)
learned = data.get("learned") or {}
print("found:", data.get("found"), "| samples:", len(learned.get("samples") or []),
      "| ledger:", len(learned.get("ledger") or []))
'@
$decode | python -I - $match.Groups[1].Value $OutFile
Write-Host "Saved to $((Resolve-Path $OutFile).Path)"
