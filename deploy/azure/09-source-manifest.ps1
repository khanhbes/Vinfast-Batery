param([Parameter(Mandatory)][string]$OutputPath)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$gitSafePath = $repo.Replace('\', '/')
$target = [IO.Path]::GetFullPath($OutputPath)
if (-not $target.StartsWith((Join-Path $repo 'docs/qa_evidence/') , [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Manifest output must be inside docs/qa_evidence.'
}
if (Test-Path -LiteralPath $target) { throw 'Manifest already exists. Do not overwrite previous evidence.' }
$sha = & git -c "safe.directory=$gitSafePath" -C $repo rev-parse HEAD
if ($LASTEXITCODE -ne 0) { throw 'Git SHA lookup failed.' }
$sha = $sha.Trim()
$branch = & git -c "safe.directory=$gitSafePath" -C $repo branch --show-current
if ($LASTEXITCODE -ne 0) { throw 'Git branch lookup failed.' }
$branch = $branch.Trim()
$files = & git -c "safe.directory=$gitSafePath" -C $repo ls-files --cached --others --exclude-standard -- web deploy/azure
if ($LASTEXITCODE -ne 0) { throw 'Git inventory failed.' }
$entries = foreach ($file in ($files | Sort-Object -Unique)) {
    # Hash source only. Never read env, credentials, model/APK binaries or old evidence.
    if ($file -notmatch '^(web/|deploy/azure/)' -or
        $file -match '(^|/)(\.env[^/]*|node_modules|venv|\.venv|dist|data|models|apk|__pycache__|\.pytest[^/]*|tests_tmp)(/|$)' -or
        $file -match '(?i)(service.?account|firebase-adminsdk|private|rendered)' -or
        $file -notmatch '\.(py|ps1|bicep|json|toml|txt|ts|tsx|js|css|html|yml|yaml)$|(^|/)Dockerfile[^/]*$|\.dockerignore$') { continue }
    $absolute = Join-Path $repo $file
    if (Test-Path -LiteralPath $absolute -PathType Leaf) {
        @{ path = $file; sha256 = (Get-FileHash -LiteralPath $absolute -Algorithm SHA256).Hash }
    }
}
$manifest = @{ sourceSha = $sha; branch = $branch; capturedAt = [DateTime]::UtcNow.ToString('o'); scope = 'Staging source hashes; excludes secrets, models, artifacts and evidence'; files = @($entries) }
[IO.File]::WriteAllText($target, ($manifest | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
Write-Host "Source manifest recorded; files=$($entries.Count); no secret values collected."
