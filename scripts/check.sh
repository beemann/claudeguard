#!/usr/bin/env bash
# ClaudeGuard — local/CI gate runner (POSIX).
# Runs the claudeguard skill headless against a diff and exits non-zero on FAIL.
#
# Usage:   scripts/check.sh [base-ref]
# Example: scripts/check.sh origin/main
#
# Requires: git, claude (Claude Code CLI) on PATH, ANTHROPIC_API_KEY in env.
set -euo pipefail

BASE_REF="${1:-origin/main}"
REPORT_MD="claudeguard.report.md"

command -v git >/dev/null    || { echo "ClaudeGuard: git not found"; exit 2; }
command -v claude >/dev/null || { echo "ClaudeGuard: claude CLI not found"; exit 2; }

git fetch --quiet origin >/dev/null 2>&1 || true

if git diff --quiet --merge-base "$BASE_REF" -- . 2>/dev/null; then
  echo "ClaudeGuard verdict: PASS (empty diff vs $BASE_REF)"
  exit 0
fi

PROMPT="Run the claudeguard skill. Gate the diff of the current branch against \
base ref '${BASE_REF}'. Follow SKILL.md exactly: resolve rulesets via \
claudeguard.config.json, run the mandatory smoke check, evaluate, and output \
the human report followed by the machine-readable \`\`\`json verdict block. \
Do not edit any files."

# Headless, read-only. The skill never edits; we still scope tools defensively.
claude -p "$PROMPT" \
  --permission-mode plan \
  | tee "$REPORT_MD"

# Extract the last JSON verdict block from the report and read .verdict.
VERDICT="$(
  awk '/```json/{f=1;next} /```/{f=0} f' "$REPORT_MD" \
    | grep -oE '"verdict"[[:space:]]*:[[:space:]]*"[A-Z]+"' \
    | tail -n1 | grep -oE '[A-Z]+$' || true
)"

echo ""
echo "ClaudeGuard parsed verdict: ${VERDICT:-UNKNOWN}"

case "$VERDICT" in
  PASS|WARN) exit 0 ;;
  FAIL)      exit 1 ;;
  *)         echo "ClaudeGuard: could not parse verdict from report"; exit 2 ;;
esac
