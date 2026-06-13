# ClaudeGuard - deterministic rule self-test (PowerShell, no LLM, no API key).
#
# For every rule that declares `detect:` patterns in its frontmatter and ships
# fixtures under fixtures/<rule-id>/, assert that:
#   - each line in should-fail.txt  MATCHES a detect pattern AND is NOT exempt
#   - each line in should-pass.txt  does NOT match detect  OR  is exempt
# Matching is case-insensitive regex, the same engine the gate uses.
#
# Usage:   ./scripts/test-rules.ps1
# Exit:    0 = all assertions pass, 1 = a fixture failed, 2 = setup error.
[CmdletBinding()]
param()
$ErrorActionPreference = "Stop"

$Root     = Split-Path -Parent $PSScriptRoot
$RulesDir = Join-Path $Root "rulesets"
$FixDir   = Join-Path $Root "fixtures"

if (-not (Test-Path $FixDir)) { Write-Host "test-rules: no fixtures/ directory"; exit 2 }

# Patterns under a frontmatter list key (detect|exempt), in the first --- block.
function Get-ListPatterns([string]$file, [string]$key) {
  $lines = Get-Content -LiteralPath $file
  $dash = 0; $inList = $false; $out = @()
  foreach ($line in $lines) {
    if ($line -eq "---") { $dash++; continue }
    if ($dash -ne 1) { continue }
    if ($line -eq "${key}:") { $inList = $true; continue }
    if ($inList) {
      if ($line -match '^\s+-\s') {
        $p = $line -replace '^\s*-\s*', ''
        $p = $p -replace "^'", '' -replace "'\s*$", ''
        $out += $p
      } else { $inList = $false }
    }
  }
  return $out
}

function Find-RuleFile([string]$id) {
  Get-ChildItem -Path $RulesDir -Recurse -Filter *.md |
    Where-Object { (Get-Content -LiteralPath $_.FullName) -match "^id:\s*$([regex]::Escape($id))\s*$" } |
    Select-Object -First 1 -ExpandProperty FullName
}

function Match-Any([string]$line, [string[]]$patterns) {
  foreach ($p in $patterns) {
    if ([string]::IsNullOrEmpty($p)) { continue }
    if ([regex]::IsMatch($line, $p, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) { return $true }
  }
  return $false
}

$fails = 0; $tested = 0; $skipped = 0

foreach ($dir in Get-ChildItem -Path $FixDir -Directory) {
  $id = $dir.Name
  $rf = Find-RuleFile $id
  if (-not $rf) { Write-Host "SKIP  $id  (no rule with this id)"; $skipped++; continue }

  $detect = @(Get-ListPatterns $rf "detect")
  $exempt = @(Get-ListPatterns $rf "exempt")
  if ($detect.Count -eq 0) { Write-Host "SKIP  $id  (judgment-only rule, no detect patterns)"; $skipped++; continue }

  $ruleFails = 0

  $sf = Join-Path $dir.FullName "should-fail.txt"
  if (Test-Path $sf) {
    foreach ($line in Get-Content -LiteralPath $sf) {
      if ([string]::IsNullOrWhiteSpace($line)) { continue }
      if (-not (Match-Any $line $detect)) {
        Write-Host "  FAIL [$id] should-fail line not detected: $line"; $ruleFails++
      } elseif (Match-Any $line $exempt) {
        Write-Host "  FAIL [$id] should-fail line wrongly exempted: $line"; $ruleFails++
      }
    }
  }

  $sp = Join-Path $dir.FullName "should-pass.txt"
  if (Test-Path $sp) {
    foreach ($line in Get-Content -LiteralPath $sp) {
      if ([string]::IsNullOrWhiteSpace($line)) { continue }
      if ((Match-Any $line $detect) -and -not (Match-Any $line $exempt)) {
        Write-Host "  FAIL [$id] should-pass line wrongly flagged: $line"; $ruleFails++
      }
    }
  }

  $tested++
  if ($ruleFails -eq 0) {
    Write-Host "PASS  $id  ($($detect.Count) detect, $($exempt.Count) exempt)"
  } else {
    Write-Host "FAIL  $id  ($ruleFails assertion(s) failed)"; $fails += $ruleFails
  }
}

Write-Host ""
Write-Host "test-rules: $tested rule(s) tested, $skipped skipped, $fails assertion failure(s)."
if ($fails -eq 0) { exit 0 } else { exit 1 }
