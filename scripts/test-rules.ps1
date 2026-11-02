# ClaudeGuard - deterministic rule self-test (PowerShell, no LLM, no API key).
#
# Every rule that declares `detect:` patterns must ship fixtures under
# fixtures/<rule-id>/, and this harness asserts that:
#   - every line in should-fail.txt IS a candidate
#   - no line in should-pass.txt is a candidate
#
# A line is a candidate when it matches no `exempt` pattern and some match of a
# `detect` pattern is not overlapped by an `exempt_match` match - the rule SKILL.md
# applies to a diff (step 5). `exempt` clears the whole line (context: wrapped in
# `docker compose exec`, a comment); `exempt_match` excuses only the detect matches
# it overlaps (a documented dummy key, an environment reference), so
# `process.env.KEY || "sk-live-..."` stays a candidate. Each detect pattern is
# matched on its own, so a long excused match cannot hide a shorter real one.
#
# Dialect. The gate and scripts/test-rules.sh use POSIX ERE; this script uses .NET
# regex. POSIX bracket classes (`[[:space:]]`, `[^[:alnum:]_-]`) are translated, so
# a rule using them is tested here too. Two differences are not emulated: .NET picks
# the leftmost-FIRST alternative where POSIX picks the leftmost-longest, and
# exempt_match matches are collected per pattern rather than in one pass.
# scripts/test-rules.sh is the reference run (it is what CI executes); this one is a
# convenience.
#
# Usage:   ./scripts/test-rules.ps1
# Exit:    0 = all assertions pass, 1 = an assertion failed, 2 = setup error.
[CmdletBinding()]
param()
$ErrorActionPreference = "Stop"

$Root     = Split-Path -Parent $PSScriptRoot
$RulesDir = Join-Path $Root "rulesets"
$FixDir   = Join-Path $Root "fixtures"
$Options  = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase

if (-not (Test-Path $RulesDir)) { Write-Host "test-rules: no rulesets/ directory"; exit 2 }
if (-not (Test-Path $FixDir))   { Write-Host "test-rules: no fixtures/ directory"; exit 2 }

# POSIX bracket classes -> .NET. Each token sits inside a bracket expression, so
# `[[:space:]]` becomes `[\s]` and `[^[:alnum:]_-]` becomes `[^a-zA-Z0-9_-]`.
# Single-quoted on purpose: the backtick in [:punct:] is PowerShell's escape
# character inside double quotes.
$PosixClasses = [ordered]@{
  '[:alnum:]'  = 'a-zA-Z0-9'
  '[:alpha:]'  = 'a-zA-Z'
  '[:blank:]'  = ' \t'
  '[:cntrl:]'  = '\x00-\x1F\x7F'
  '[:digit:]'  = '0-9'
  '[:lower:]'  = 'a-z'
  '[:punct:]'  = '!-/:-@\[-`{-~'
  '[:space:]'  = '\s'
  '[:upper:]'  = 'A-Z'
  '[:xdigit:]' = '0-9A-Fa-f'
}
function ConvertTo-DotNetPattern([string]$pattern) {
  $out = $pattern
  foreach ($k in $PosixClasses.Keys) { $out = $out.Replace($k, $PosixClasses[$k]) }
  return $out
}

# Patterns under a frontmatter list key, in the first --- block.
# Get-Content drops CR and LF alike, so a CRLF checkout parses the same.
function Get-ListPatterns([string]$file, [string]$key) {
  $dash = 0; $inList = $false; $out = @()
  foreach ($line in Get-Content -LiteralPath $file) {
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

function Get-RuleId([string]$file) {
  $dash = 0
  foreach ($line in Get-Content -LiteralPath $file) {
    if ($line -eq "---") { $dash++; continue }
    if ($dash -ne 1) { continue }
    if ($line -match '^id:\s*(\S+)\s*$') { return $Matches[1] }
  }
  return ""
}

# @(start, length) for every match of every pattern on a line.
function Get-Spans([string]$line, [string[]]$patterns) {
  $spans = @()
  foreach ($p in $patterns) {
    if ([string]::IsNullOrEmpty($p)) { continue }
    foreach ($m in [regex]::Matches($line, (ConvertTo-DotNetPattern $p), $Options)) {
      if ($m.Length -gt 0) { $spans += , @($m.Index, $m.Length) }
    }
  }
  return , $spans
}

function Test-Candidate([string]$line, [string[]]$detect, [string[]]$exempt, [string[]]$exemptMatch) {
  if ((Get-Spans $line $exempt).Count -gt 0) { return $false }
  $exemptSpans = Get-Spans $line $exemptMatch
  foreach ($p in $detect) {
    foreach ($d in (Get-Spans $line @($p))) {
      $covered = $false
      foreach ($e in $exemptSpans) {
        if ($d[0] -lt ($e[0] + $e[1]) -and $e[0] -lt ($d[0] + $d[1])) { $covered = $true; break }
      }
      if (-not $covered) { return $true }
    }
  }
  return $false
}

$fails = 0; $tested = 0; $skipped = 0
$knownIds = @{}

foreach ($rf in (Get-ChildItem -Path $RulesDir -Recurse -Filter *.md -File | Sort-Object FullName)) {
  $id = Get-RuleId $rf.FullName
  if (-not $id) { continue }
  $knownIds[$id] = $true

  $detect = @(Get-ListPatterns $rf.FullName "detect")
  $exempt = @(Get-ListPatterns $rf.FullName "exempt")
  $exemptMatch = @(Get-ListPatterns $rf.FullName "exempt_match")
  if ($detect.Count -eq 0) { Write-Host "SKIP  $id  (judgment-only rule, no detect patterns)"; $skipped++; continue }

  $ruleFails = 0; $assertions = 0

  # An invalid pattern must not read as "no match".
  foreach ($p in ($detect + $exempt + $exemptMatch)) {
    try { [void][regex]::new((ConvertTo-DotNetPattern $p), $Options) }
    catch { Write-Host "  FAIL [$id] invalid pattern: $p"; $ruleFails++ }
  }

  $sf = Join-Path (Join-Path $FixDir $id) "should-fail.txt"
  $sp = Join-Path (Join-Path $FixDir $id) "should-pass.txt"
  if (-not (Test-Path $sf) -and -not (Test-Path $sp)) {
    Write-Host "FAIL  $id  (detect patterns but no fixtures/$id/should-{fail,pass}.txt - untested)"
    $fails++; continue
  }

  if (Test-Path $sf) {
    foreach ($line in Get-Content -LiteralPath $sf) {
      if ([string]::IsNullOrEmpty($line)) { continue }
      $assertions++
      if (-not (Test-Candidate $line $detect $exempt $exemptMatch)) {
        Write-Host "  FAIL [$id] should-fail line is not a candidate: $line"; $ruleFails++
      }
    }
  }

  if (Test-Path $sp) {
    foreach ($line in Get-Content -LiteralPath $sp) {
      if ([string]::IsNullOrEmpty($line)) { continue }
      $assertions++
      if (Test-Candidate $line $detect $exempt $exemptMatch) {
        Write-Host "  FAIL [$id] should-pass line is a candidate: $line"; $ruleFails++
      }
    }
  }

  if ($assertions -eq 0) { Write-Host "  FAIL [$id] fixtures hold no lines"; $ruleFails++ }

  $tested++
  if ($ruleFails -eq 0) {
    Write-Host "PASS  $id  ($($detect.Count) detect, $($exempt.Count) exempt, $($exemptMatch.Count) exempt_match, $assertions assertions)"
  } else {
    Write-Host "FAIL  $id  ($ruleFails assertion(s) failed)"; $fails += $ruleFails
  }
}

# Fixtures for an id no rule declares are a renamed or deleted rule whose patterns
# nobody tests any more.
foreach ($dir in (Get-ChildItem -Path $FixDir -Directory)) {
  if (-not $knownIds.ContainsKey($dir.Name)) {
    Write-Host "FAIL  $($dir.Name)  (fixtures/$($dir.Name)/ but no rule with this id)"; $fails++
  }
}

Write-Host ""
Write-Host "test-rules: $tested rule(s) tested, $skipped skipped, $fails assertion failure(s)."

# A harness that tested nothing is not a harness that passed.
if ($tested -eq 0) {
  Write-Host "test-rules: FAIL - no rule was tested. Fixtures or frontmatter are not being"
  Write-Host "            parsed. Refusing to report success for a check that ran nothing."
  exit 1
}
if ($fails -eq 0) { exit 0 } else { exit 1 }
