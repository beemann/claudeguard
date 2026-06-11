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
# Idempotent: engine files (skill, _core, runner scripts) are refreshed on every
# run; policy files (house rules, config, an existing workflow) are never
# overwritten.
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

# Copy a directory's *.md, refreshing engine rules.
function Copy-EngineDir([string]$relDir, [string]$destRelDir) {
  $src = Join-Path $EngineRoot $relDir
  $dst = Join-Path $Target $destRelDir
  New-Dir $dst
  Get-ChildItem -Path $src -Filter *.md -File | ForEach-Object {
    Copy-Item -Path $_.FullName -Destination (Join-Path $dst $_.Name) -Force
    Write-Host "  engine  $destRelDir/$($_.Name)"
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

# Copy a directory's *.md only if the destination directory is absent.
function Copy-DirIfAbsent([string]$relDir, [string]$destRelDir) {
  $dst = Join-Path $Target $destRelDir
  if (Test-Path $dst) {
    Write-Host "  keep    $destRelDir/ (already present)"
    return
  }
  Copy-EngineDir $relDir $destRelDir
}

# --- engine (refreshed) -----------------------------------------------------
Copy-Engine "SKILL.md" ".claude/skills/claudeguard/SKILL.md"
Copy-EngineDir "rulesets/_core" "rulesets/_core"
Copy-Engine "scripts/check.ps1" "scripts/check.ps1"
Copy-Engine "scripts/check.sh"  "scripts/check.sh"

# --- policy (never clobbered) -----------------------------------------------
Copy-DirIfAbsent "rulesets/house" "rulesets/house"
Copy-IfAbsent ".github/workflows/claudeguard.yml" ".github/workflows/claudeguard.yml"
Copy-IfAbsent "claudeguard.config.example.json" "claudeguard.config.json"

# --- next steps -------------------------------------------------------------
Write-Host ""
Write-Host "ClaudeGuard installed. Next steps:"
Write-Host "  1. Edit claudeguard.config.json -> set 'base' to your integration branch."
Write-Host "  2. Tune rulesets/house/ to your stack; commit your policy."
Write-Host "  3. For CI: add the repo secret ANTHROPIC_API_KEY."
Write-Host "  4. Run the gate locally: ./scripts/check.ps1 -BaseRef origin/main"
