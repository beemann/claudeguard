# ClaudeGuard - vendoring installer (PowerShell).
# Copies the ClaudeGuard engine + a policy template into a target project so the
# gate runs self-contained (local and in CI) with no plugin dependency.
#
# Usage:   ./scripts/install.ps1 [-Target <path>]
# Default target is the current directory.
#
# Engine source is resolved as (in order):
#   1. $env:CLAUDE_PLUGIN_ROOT   (set when run via the claudeguard-init skill)
#   2. the parent of this script's directory (a cloned/checked-out repo)
#
# Idempotent: engine files (skill, _core rules and their fixtures, runner and
# rule-test scripts) are refreshed on every run; policy files (house rules, config,
# an existing workflow) are never overwritten. House-rule fixtures are seeded only
# together with the house rules they test, so a kept policy never meets fixtures
# written for a different version of it.
[CmdletBinding()]
param(
  [string]$Target = (Get-Location).Path
)

$ErrorActionPreference = "Stop"

# --- resolve engine source --------------------------------------------------
$EngineRoot = $env:CLAUDE_PLUGIN_ROOT
if ([string]::IsNullOrWhiteSpace($EngineRoot)) {
  $EngineRoot = Split-Path -Parent $PSScriptRoot
}
if (-not (Test-Path (Join-Path $EngineRoot "SKILL.md"))) {
  Write-Host "ClaudeGuard: engine source not found (no SKILL.md at $EngineRoot)."
  exit 2
}

$Target = (Resolve-Path $Target).Path
Write-Host "ClaudeGuard: installing engine from"
Write-Host "  $EngineRoot"
Write-Host "into project"
Write-Host "  $Target"
Write-Host ""

# --- helpers ----------------------------------------------------------------
function New-Dir([string]$path) {
  if (-not (Test-Path $path)) { New-Item -ItemType Directory -Force -Path $path | Out-Null }
}

# Always refresh an engine file.
function Copy-Engine([string]$rel, [string]$destRel) {
  $src = Join-Path $EngineRoot $rel
  $dst = Join-Path $Target $destRel
  New-Dir (Split-Path -Parent $dst)
  Copy-Item -Path $src -Destination $dst -Force
  Write-Host "  engine  $destRel"
}

# Copy a directory's files matching a filter.
function Copy-EngineDir([string]$relDir, [string]$destRelDir, [string]$filter, [string]$label) {
  $src = Join-Path $EngineRoot $relDir
  $dst = Join-Path $Target $destRelDir
  New-Dir $dst
  Get-ChildItem -Path $src -Filter $filter -File | ForEach-Object {
    Copy-Item -Path $_.FullName -Destination (Join-Path $dst $_.Name) -Force
    Write-Host "  $label  $destRelDir/$($_.Name)"
  }
}

# Copy only if the destination does not already exist (policy / user-owned).
function Copy-IfAbsent([string]$rel, [string]$destRel) {
  $src = Join-Path $EngineRoot $rel
  $dst = Join-Path $Target $destRel
  if (Test-Path $dst) {
    Write-Host "  keep    $destRel (already present)"
    return
  }
  New-Dir (Split-Path -Parent $dst)
  Copy-Item -Path $src -Destination $dst -Force
  Write-Host "  policy  $destRel"
}

# Is <id> the id of a shipped _core rule?
function Test-CoreRule([string]$id) {
  $pattern = "^id:\s*$([regex]::Escape($id))\s*$"
  foreach ($f in (Get-ChildItem -Path (Join-Path $EngineRoot "rulesets/_core") -Filter *.md -File)) {
    if ((Get-Content -LiteralPath $f.FullName) -match $pattern) { return $true }
  }
  return $false
}

$fixtureDirs = @()
$fixtureRoot = Join-Path $EngineRoot "fixtures"
if (Test-Path $fixtureRoot) { $fixtureDirs = @(Get-ChildItem -Path $fixtureRoot -Directory) }

# --- engine (refreshed) -----------------------------------------------------
Copy-Engine "SKILL.md" ".claude/skills/claudeguard/SKILL.md"
Copy-EngineDir "rulesets/_core" "rulesets/_core" "*.md" "engine"
Copy-Engine "scripts/check.ps1"      "scripts/check.ps1"
Copy-Engine "scripts/check.sh"       "scripts/check.sh"
Copy-Engine "scripts/test-rules.ps1" "scripts/test-rules.ps1"
Copy-Engine "scripts/test-rules.sh"  "scripts/test-rules.sh"
foreach ($d in $fixtureDirs) {
  if (Test-CoreRule $d.Name) { Copy-EngineDir "fixtures/$($d.Name)" "fixtures/$($d.Name)" "*.txt" "engine" }
}

# --- policy (never clobbered) -----------------------------------------------
if (Test-Path (Join-Path $Target "rulesets/house")) {
  Write-Host "  keep    rulesets/house/ (already present)"
} else {
  Copy-EngineDir "rulesets/house" "rulesets/house" "*.md" "policy"
  foreach ($d in $fixtureDirs) {
    if (-not (Test-CoreRule $d.Name)) { Copy-EngineDir "fixtures/$($d.Name)" "fixtures/$($d.Name)" "*.txt" "policy" }
  }
}
Copy-IfAbsent ".github/workflows/claudeguard.yml" ".github/workflows/claudeguard.yml"
Copy-IfAbsent "claudeguard.config.example.json" "claudeguard.config.json"

# --- next steps -------------------------------------------------------------
Write-Host ""
Write-Host "ClaudeGuard installed. Next steps:"
Write-Host "  1. Set 'base' in claudeguard.config.json to your integration branch (the"
Write-Host "     runners default to it), and list that branch under on.pull_request.branches"
Write-Host "     in .github/workflows/claudeguard.yml."
Write-Host "  2. Tune rulesets/house/ to your stack. Every rule with 'detect' patterns needs"
Write-Host "     fixtures/<id>/should-fail.txt and should-pass.txt; check them with"
Write-Host "     ./scripts/test-rules.ps1. Commit your policy."
Write-Host "  3. For CI: add the repo secret ANTHROPIC_API_KEY."
Write-Host "  4. Run the gate locally: ./scripts/check.ps1"
Write-Host ""
Write-Host "  Windows: add '*.sh text eol=lf' to .gitattributes, or a checkout with"
Write-Host "  core.autocrlf=true writes the scripts with CRLF and bash refuses them. The"
Write-Host "  bundled CI workflow runs them through bash, so the executable bit (not"
Write-Host "  recorded with core.fileMode=false) does not matter there."
