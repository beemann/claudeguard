# ClaudeGuard - local/CI gate runner (PowerShell).
# Runs the claudeguard skill headless against a diff and exits non-zero on FAIL.
#
# Usage:   ./scripts/check.ps1 [-BaseRef origin/main]
# Requires: git, claude (Claude Code CLI) on PATH, ANTHROPIC_API_KEY in env.
[CmdletBinding()]
param(
  [string]$BaseRef = "origin/main"
)

$ErrorActionPreference = "Stop"
$ReportMd = "claudeguard.report.md"

if (-not (Get-Command git -ErrorAction SilentlyContinue))    { Write-Host "ClaudeGuard: git not found"; exit 2 }
if (-not (Get-Command claude -ErrorAction SilentlyContinue)) { Write-Host "ClaudeGuard: claude CLI not found"; exit 2 }

try { git fetch --quiet origin | Out-Null } catch { }

# Empty diff -> immediate PASS.
git diff --quiet --merge-base $BaseRef -- .
if ($LASTEXITCODE -eq 0) {
  Write-Host "ClaudeGuard verdict: PASS (empty diff vs $BaseRef)"
  exit 0
}

$prompt = @"
Run the claudeguard skill. Gate the diff of the current branch against base ref
'$BaseRef'. Follow SKILL.md exactly: resolve rulesets via claudeguard.config.json,
run the mandatory smoke check, evaluate, and output the human report followed by
the machine-readable ``````json verdict block. Do not edit any files.

This is a read-only audit running headless. Do NOT call ExitPlanMode and do NOT
ask for approval or present a plan — the verdict report IS your deliverable.
Emit the human table and the ``````json block directly as your reply, and end with
a final line exactly: claudeguard-verdict: <PASS|WARN|FAIL>.
"@

# Headless, read-only.
claude -p $prompt --permission-mode plan | Tee-Object -FilePath $ReportMd

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
