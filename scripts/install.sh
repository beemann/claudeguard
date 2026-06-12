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
# Idempotent: engine files (skill, _core, runner scripts) are refreshed on every
# run; policy files (house rules, config, an existing workflow) are never
# overwritten.
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

copy_engine_dir() {  # <reldir> <reldstdir>
  local src="$ENGINE_ROOT/$1" dst="$TARGET/$2" f
  mkdir -p "$dst"
  for f in "$src"/*.md; do
    [ -e "$f" ] || continue
    cp -f "$f" "$dst/$(basename "$f")"
    echo "  engine  $2/$(basename "$f")"
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

copy_dir_if_absent() {  # <reldir> <reldstdir>
  local dst="$TARGET/$2"
  if [ -e "$dst" ]; then
    echo "  keep    $2/ (already present)"
    return
  fi
  copy_engine_dir "$1" "$2"
}

# --- engine (refreshed) -----------------------------------------------------
copy_engine "SKILL.md" ".claude/skills/claudeguard/SKILL.md"
copy_engine_dir "rulesets/_core" "rulesets/_core"
copy_engine "scripts/check.ps1" "scripts/check.ps1"
copy_engine "scripts/check.sh"  "scripts/check.sh"

# --- policy (never clobbered) -----------------------------------------------
copy_dir_if_absent "rulesets/house" "rulesets/house"
copy_if_absent ".github/workflows/claudeguard.yml" ".github/workflows/claudeguard.yml"
copy_if_absent "claudeguard.config.example.json" "claudeguard.config.json"

# --- next steps -------------------------------------------------------------
echo ""
echo "ClaudeGuard installed. Next steps:"
echo "  1. Edit claudeguard.config.json -> set 'base' to your integration branch."
echo "  2. Tune rulesets/house/ to your stack; commit your policy."
echo "  3. For CI: add the repo secret ANTHROPIC_API_KEY."
echo "  4. Run the gate locally: scripts/check.sh origin/main"
