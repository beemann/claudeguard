# ClaudeGuard - local/CI gate runner (PowerShell).
# Runs the claudeguard skill headless against a diff and exits non-zero on FAIL.
#
# Usage:   ./scripts/check.ps1 [-BaseRef origin/main]
#
# The base ref is -BaseRef, else `base` in claudeguard.config.json, else
# origin/main. The gate judges the commits the branch adds: <base>...HEAD.
#
# Exit:    0 = PASS or WARN
#          1 = FAIL (a policy verdict)
#          2 = no verdict: setup error, the claude CLI failed (auth, credit,
#              network), or the report carried no readable verdict
#
# Requires: git, claude (Claude Code CLI) on PATH, ANTHROPIC_API_KEY in env.
# Runs on Windows PowerShell 5.1 and PowerShell 7. Native commands are checked
# through $LASTEXITCODE and their stderr is never redirected: under
# $ErrorActionPreference = "Stop", Windows PowerShell turns a redirected native
# stderr line into a terminating error.
[CmdletBinding()]
param(
  [string]$BaseRef = ""
)

$ErrorActionPreference = "Stop"
$ReportMd = "claudeguard.report.md"
$Config   = "claudeguard.config.json"

if (-not (Get-Command git -ErrorAction SilentlyContinue))    { Write-Host "ClaudeGuard: git not found"; exit 2 }
if (-not (Get-Command claude -ErrorAction SilentlyContinue)) { Write-Host "ClaudeGuard: claude CLI not found"; exit 2 }

# Operate from the repository root, so the policy paths resolve the same way
# wherever the gate is invoked from.
$top = git rev-parse --show-toplevel
if ($LASTEXITCODE -ne 0 -or -not $top) { Write-Host "ClaudeGuard: not inside a git repository"; exit 2 }
Set-Location $top

# The policy lives at the repository root. Without it there is nothing to judge,
# and a model sent to look for it elsewhere guesses; stop here instead.
if (-not (Test-Path "rulesets" -PathType Container)) {
  Write-Host "ClaudeGuard: rulesets/ not found at the repository root"; exit 2
}

if (-not $BaseRef -and (Test-Path $Config)) {
  try { $cfg = Get-Content $Config -Raw | ConvertFrom-Json }
  catch { Write-Host "ClaudeGuard: $Config is not valid JSON ($($_.Exception.Message))"; exit 2 }
  if ($cfg.base) { $BaseRef = [string]$cfg.base }
}
if (-not $BaseRef) { $BaseRef = "origin/main" }

try { git fetch --quiet origin | Out-Null } catch { }

git rev-parse --verify --quiet "$BaseRef^{commit}" | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Host "ClaudeGuard: base ref '$BaseRef' does not resolve to a commit"; exit 2 }
git merge-base $BaseRef HEAD | Out-Null
if ($LASTEXITCODE -ne 0) {
  Write-Host "ClaudeGuard: no merge base between '$BaseRef' and HEAD (shallow clone? fetch full history)"; exit 2
}

# No `--` here: Windows PowerShell does not pass it through to native commands.
git diff --quiet "$BaseRef...HEAD"
if ($LASTEXITCODE -eq 0) {
  "ClaudeGuard verdict: PASS (empty diff vs $BaseRef)`n`nclaudeguard-verdict: PASS" | Tee-Object -FilePath $ReportMd
  exit 0
}

# Single-quoted: no interpolation, and the backticks of ```json stay literal.
$prompt = @'
Run the claudeguard skill. Gate the commits of the current branch against base ref
'{BASE}' (diff range {BASE}...HEAD). The policy is at the repository root:
./claudeguard.config.json (optional) and the *.md rules under ./rulesets/. Follow
SKILL.md exactly: resolve rulesets, run the mandatory smoke check and every declared
probe, build the detect candidates as step 5 prescribes, evaluate, and output the
human report followed by the machine-readable ```json block. Do not edit any files.
This is a headless, read-only audit: the report is the deliverable and there is
nothing to plan or approve. End with a final line exactly:
claudeguard-verdict: <PASS|WARN|FAIL>.
'@
$prompt = $prompt.Replace('{BASE}', $BaseRef)

# Headless, with an explicit tool set - the same as scripts/check.sh, which
# explains each choice (dontAsk, the allow-list, why not plan mode, and why the
# --output deny is defense in depth rather than a boundary).
$allowed = @("Read", "Grep", "Glob",
             "Bash(git diff:*)", "Bash(git grep:*)", "Bash(git log:*)",
             "Bash(git merge-base:*)", "Bash(git rev-parse:*)")
$denied  = @("Edit", "Write", "NotebookEdit", "Bash(git *--output*)")

# The report carries Unicode status markers; decode the CLI's UTF-8 output as such.
$prevEncoding = $null
try { $prevEncoding = [Console]::OutputEncoding; [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
try {
  claude -p $prompt --permission-mode dontAsk --allowed-tools $allowed --disallowed-tools $denied |
    Tee-Object -FilePath $ReportMd
  $claudeStatus = $LASTEXITCODE
} finally {
  if ($prevEncoding) { try { [Console]::OutputEncoding = $prevEncoding } catch { } }
}

if ($claudeStatus -ne 0) {
  Write-Host ""
  Write-Host "ClaudeGuard: the claude CLI exited $claudeStatus - no verdict was produced."
  Write-Host "             That is an infrastructure error (auth, credit, network), not a policy FAIL."
  exit 2
}

# Read the verdict. Prefer the machine sentinel line; fall back to the JSON block.
$report = Get-Content $ReportMd -Raw
$verdict = "UNKNOWN"
$sentinel = [regex]::Matches($report, '(?im)^\s*claudeguard-verdict:\s*([A-Za-z]+)\s*$')
if ($sentinel.Count -gt 0) {
  $verdict = $sentinel[$sentinel.Count - 1].Groups[1].Value.ToUpper()
} else {
  $json = [regex]::Matches($report, '"verdict"\s*:\s*"([A-Z]+)"')
  if ($json.Count -gt 0) { $verdict = $json[$json.Count - 1].Groups[1].Value }
}

Write-Host ""
Write-Host "ClaudeGuard parsed verdict: $verdict"

switch ($verdict) {
  "PASS" { exit 0 }
  "WARN" { exit 0 }
  "FAIL" { exit 1 }
  default { Write-Host "ClaudeGuard: could not parse verdict from report"; exit 2 }
}
