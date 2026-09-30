# codex-run.ps1 - run ONE Codex worker in a worktree and judge it with the 3 signals.
# Exit: 0 = PASS (3 signals ok)  1 = FAIL  4 = LIMIT (usage limit hit; manager must ask the user)
# Output is a short summary only; full logs stay in OutDir (events.jsonl, report.json, stderr.txt) and are NOT to be read by the manager.
# The brief is fed with a raw cmd '<' redirect: piping from PowerShell 5.1 mangles Korean (system code page).
# ASCII only on purpose (Windows PowerShell 5.1 reads BOM-less files as ANSI).
param(
  [Parameter(Mandatory)][string]$Exe,
  [Parameter(Mandatory)][string]$Worktree,   # working dir of the worker (a git worktree, or project root for read-only research)
  [Parameter(Mandatory)][string]$Brief,      # brief file, UTF-8
  [Parameter(Mandatory)][string]$OutDir,
  [Parameter(Mandatory)][string]$Model,
  [Parameter(Mandatory)][string]$Effort,     # low | medium | high | xhigh   (never max/ultra for workers)
  [string]$Resume = '',                      # thread id from a previous run -> continue that session
  [string]$Sandbox = 'workspace-write',      # read-only for research workers
  [int]$TimeoutMin = 25
)
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$schema = Join-Path $PSScriptRoot 'codex-report.schema.json'
$ev = Join-Path $OutDir 'events.jsonl'
$rep = Join-Path $OutDir 'report.json'
$err = Join-Path $OutDir 'stderr.txt'
foreach ($f in $ev, $rep, $err) { if (Test-Path $f) { Remove-Item $f -Force } }

$common = "-m $Model -c model_reasoning_effort=`"$Effort`" --output-schema `"$schema`" -o `"$rep`" --json - < `"$Brief`" > `"$ev`" 2> `"$err`""
if ($Resume) {
  # resume has no -C / -s: cwd + sandbox_mode override instead
  $line = "cd /d `"$Worktree`" && `"$Exe`" exec resume $Resume -c sandbox_mode=`"$Sandbox`" $common"
} else {
  $line = "cd /d `"$Worktree`" && `"$Exe`" exec -C `"$Worktree`" -s $Sandbox $common"
}

$sw = [Diagnostics.Stopwatch]::StartNew()
$p = Start-Process -FilePath cmd.exe -ArgumentList "/d /s /c `"$line`"" -NoNewWindow -PassThru
$null = $p.Handle
$timedOut = $false
if (-not $p.WaitForExit($TimeoutMin * 60 * 1000)) {
  $timedOut = $true
  cmd /d /c "taskkill /PID $($p.Id) /T /F >nul 2>&1"
}
$secs = [int]$sw.Elapsed.TotalSeconds
$code = if ($timedOut) { -1 } else { $p.ExitCode }

function Read-Utf8($path) { if (Test-Path $path) { [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8) } else { '' } }
$evText = Read-Utf8 $ev
$errText = Read-Utf8 $err
$repText = Read-Utf8 $rep

$tid = ''
if ($evText -match '"type":"thread\.started","thread_id":"([^"]+)"') { $tid = $Matches[1] }
elseif ($Resume) { $tid = $Resume }

# 3 signals
$why = @()
if ($timedOut) { $why += "timeout after $TimeoutMin min (killed)" }
elseif ($code -ne 0) { $why += "exit code $code" }
if ($evText -notmatch '"type":"turn\.completed"') { $why += 'no turn.completed event' }
if ($evText -match '"type":"turn\.failed"') { $why += 'turn.failed event' }
$report = $null
if ($repText.Trim() -eq '') { $why += 'report.json missing/empty' }
else { try { $report = $repText | ConvertFrom-Json } catch { $why += 'report.json not valid json' } }

# usage limit? (message wording is not verified yet - broad match on purpose)
$limit = ($why.Count -gt 0) -and (($evText + $errText) -match '(?i)usage limit|rate.?limit|quota|limit reached|too many requests|try again (later|in)')

$changed = @()
$st = git -C $Worktree status --porcelain 2>$null
foreach ($l in $st) { if ($l.Length -gt 3) { $changed += $l.Substring(3).Trim('"') } }

$verdict = if ($limit) { 'LIMIT' } elseif ($why.Count -eq 0) { 'PASS' } else { 'FAIL' }
"CODEX $verdict"
"thread=$tid model=$Model effort=$Effort secs=$secs"
if ($report) {
  $sum = "$($report.summary)"; if ($sum.Length -gt 300) { $sum = $sum.Substring(0, 300) + '...' }
  "report: status=$($report.status) | $sum"
  if ($report.blocker) { "blocker: $($report.blocker)" }
  "worker-verify: $($report.verify)"
}
$shown = ($changed | Select-Object -First 15) -join ', '
if ($changed.Count -gt 15) { $shown += " (+$($changed.Count - 15) more)" }
"changed(git): $shown"
if ($why.Count -gt 0) {
  "why: $($why -join '; ')"
  $m = [regex]::Matches($evText, '"type":"error","message":"((?:[^"\\]|\\.)*)"')
  if ($m.Count -gt 0) { $t = $m[$m.Count - 1].Groups[1].Value; if ($t.Length -gt 300) { $t = $t.Substring(0, 300) }; "last-error: $t" }
  $tail = ($errText -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -Last 4) -join ' / '
  if ($tail) { "stderr-tail: $tail" }
}
if ($verdict -eq 'PASS') { exit 0 } elseif ($verdict -eq 'LIMIT') { exit 4 } else { exit 1 }
