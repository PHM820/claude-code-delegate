# codex-detect.ps1 - is Codex usable as the worker engine? Prints ONE json line, exit 0 always.
# ready=true  -> tiers holds the resolved model/effort per tier (fallback model used if the primary is not in the local model cache)
# ready=false -> reason says why; the manager then uses the Claude engine.
# ASCII only on purpose (Windows PowerShell 5.1 reads BOM-less files as ANSI).
$ErrorActionPreference = 'Continue'

function Out-Json($o) { $o | ConvertTo-Json -Compress -Depth 5; exit 0 }

$exe = $null
$cmd = Get-Command codex -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($cmd) { $exe = $cmd.Source }
if (-not $exe -and $env:LOCALAPPDATA) {
  $dir = Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\bin'
  if (Test-Path $dir) {
    $f = Get-ChildItem $dir -Recurse -Filter codex.exe -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($f) { $exe = $f.FullName }
  }
}
if (-not $exe) { Out-Json @{ ready = $false; reason = 'codex not found (PATH, %LOCALAPPDATA%\OpenAI\Codex\bin)' } }

$ver = (cmd /d /c "`"$exe`" --version 2>&1" | Out-String).Trim()
$login = (cmd /d /c "`"$exe`" login status 2>&1" | Out-String).Trim()
if ($login -notmatch 'Logged in') {
  Out-Json @{ ready = $false; reason = 'codex not logged in (run: codex login)'; exe = $exe; version = $ver }
}

# resolve tiers against the model cache (raw text match: PS 5.1 ConvertFrom-Json chokes on this file)
$cachePath = Join-Path $env:USERPROFILE '.codex\models_cache.json'
$cache = ''
if (Test-Path $cachePath) { $cache = [IO.File]::ReadAllText($cachePath, [Text.Encoding]::UTF8) }
function Has-Model($m) { return ($cache -eq '') -or ($cache -match ('"slug":\s*"' + [regex]::Escape($m) + '"')) }

$engine = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'engine.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json
$tiers = [ordered]@{}
foreach ($t in 'light', 'normal', 'hard') {
  $c = $engine.tiers.$t
  $m = $c.model
  if (-not (Has-Model $m)) { $m = $c.fallback }
  if (-not (Has-Model $m)) { Out-Json @{ ready = $false; reason = "no usable model for tier $t (checked $($c.model), $($c.fallback))"; exe = $exe } }
  $tiers[$t] = @{ model = $m; effort = $c.effort; primary = ($m -eq $c.model) }
}

Out-Json @{ ready = $true; exe = $exe; version = $ver; sandbox = $engine.sandbox; timeout_min = $engine.timeout_min; tiers = $tiers }
