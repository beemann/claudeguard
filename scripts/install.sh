#!/usr/bin/env bash
# ClaudeGuard - vendoring installer (POSIX).
# Copies the ClaudeGuard engine + a policy template into a target project so the
# gate runs self-contained (local and in CI) with no plugin dependency.
#
# Usage:   scripts/install.sh [target-dir]
# Default target is the current directory.
#
# Engine source is resolved as (in order):
#   1. $CLAUDE_PLUGIN_ROOT   (set when run via the claudeguard-init skill)
#   2. the parent of this script's directory (a cloned/checked-out repo)
#
# Idempotent: engine files (skill, _core rules and their fixtures, runner and
# rule-test scripts) are refreshed on every run; policy files (house rules, config,
# an existing workflow) are never overwritten. House-rule fixtures are seeded only
# together with the house rules they test, so a kept policy never meets fixtures
# written for a different version of it.
set -euo pipefail

# --- resolve engine source --------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENGINE_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$SCRIPT_DIR")}"

if [ ! -f "$ENGINE_ROOT/SKILL.md" ]; then
  echo "ClaudeGuard: engine source not found (no SKILL.md at $ENGINE_ROOT)."
  exit 2
fi

TARGET="${1:-$(pwd)}"
mkdir -p "$TARGET"
TARGET="$(cd "$TARGET" && pwd)"

echo "ClaudeGuard: installing engine from"
echo "  $ENGINE_ROOT"
echo "into project"
echo "  $TARGET"
echo ""

# --- helpers ----------------------------------------------------------------
copy_engine() {  # <relsrc> <reldst>
  local src="$ENGINE_ROOT/$1" dst="$TARGET/$2"
  mkdir -p "$(dirname "$dst")"
  cp -f "$src" "$dst"
  echo "  engine  $2"
}

copy_engine_dir() {  # <reldir> <reldstdir> <glob> <label>
  local src="$ENGINE_ROOT/$1" dst="$TARGET/$2" f
  mkdir -p "$dst"
  for f in "$src"/$3; do
    [ -e "$f" ] || continue
    cp -f "$f" "$dst/$(basename "$f")"
    echo "  $4  $2/$(basename "$f")"
  done
}

copy_if_absent() {  # <relsrc> <reldst>
  local dst="$TARGET/$2"
  if [ -e "$dst" ]; then
    echo "  keep    $2 (already present)"
    return
  fi
  mkdir -p "$(dirname "$dst")"
  cp -f "$ENGINE_ROOT/$1" "$dst"
  echo "  policy  $2"
}

# Is <id> the id of a shipped _core rule?
is_core_rule() {  # <id>
  grep -qlE "^id:[[:space:]]*$1[[:space:]]*\$" "$ENGINE_ROOT"/rulesets/_core/*.md 2>/dev/null
}

# --- engine (refreshed) -----------------------------------------------------
copy_engine "SKILL.md" ".claude/skills/claudeguard/SKILL.md"
copy_engine_dir "rulesets/_core" "rulesets/_core" "*.md" "engine"
copy_engine "scripts/check.ps1"      "scripts/check.ps1"
copy_engine "scripts/check.sh"       "scripts/check.sh"
copy_engine "scripts/test-rules.ps1" "scripts/test-rules.ps1"
copy_engine "scripts/test-rules.sh"  "scripts/test-rules.sh"
chmod +x "$TARGET/scripts/check.sh" "$TARGET/scripts/test-rules.sh"
for d in "$ENGINE_ROOT"/fixtures/*/; do
  [ -d "$d" ] || continue
  id="$(basename "$d")"
  if is_core_rule "$id"; then copy_engine_dir "fixtures/$id" "fixtures/$id" "*.txt" "engine"; fi
done

# --- policy (never clobbered) -----------------------------------------------
if [ -e "$TARGET/rulesets/house" ]; then
  echo "  keep    rulesets/house/ (already present)"
else
  copy_engine_dir "rulesets/house" "rulesets/house" "*.md" "policy"
  for d in "$ENGINE_ROOT"/fixtures/*/; do
    [ -d "$d" ] || continue
    id="$(basename "$d")"
    if ! is_core_rule "$id"; then copy_engine_dir "fixtures/$id" "fixtures/$id" "*.txt" "policy"; fi
  done
fi
copy_if_absent ".github/workflows/claudeguard.yml" ".github/workflows/claudeguard.yml"
copy_if_absent "claudeguard.config.example.json" "claudeguard.config.json"

# --- next steps -------------------------------------------------------------
echo ""
echo "ClaudeGuard installed. Next steps:"
echo "  1. Set 'base' in claudeguard.config.json to your integration branch (the"
echo "     runners default to it), and list that branch under on.pull_request.branches"
echo "     in .github/workflows/claudeguard.yml."
echo "  2. Tune rulesets/house/ to your stack. Every rule with 'detect' patterns needs"
echo "     fixtures/<id>/should-fail.txt and should-pass.txt; check them with"
echo "     scripts/test-rules.sh. Commit your policy."
echo "  3. For CI: add the repo secret ANTHROPIC_API_KEY."
echo "  4. Run the gate locally: scripts/check.sh"
