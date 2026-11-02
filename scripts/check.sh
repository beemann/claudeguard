#!/usr/bin/env bash
# ClaudeGuard — local/CI gate runner (POSIX).
# Runs the claudeguard skill headless against a diff and exits non-zero on FAIL.
#
# Usage:   scripts/check.sh [base-ref]
# Example: scripts/check.sh origin/main
#
# The base ref is the argument, else `base` in claudeguard.config.json, else
# origin/main. The gate judges the commits the branch adds: <base>...HEAD.
#
# Exit:    0 = PASS or WARN
#          1 = FAIL (a policy verdict)
#          2 = no verdict: setup error, the claude CLI failed (auth, credit,
#              network), or the report carried no readable verdict
#
# Requires: git, claude (Claude Code CLI) on PATH, ANTHROPIC_API_KEY in env.
set -euo pipefail

REPORT_MD="claudeguard.report.md"
CONFIG="claudeguard.config.json"

command -v git >/dev/null    || { echo "ClaudeGuard: git not found"; exit 2; }
command -v claude >/dev/null || { echo "ClaudeGuard: claude CLI not found"; exit 2; }

# Operate from the repository root, so the policy paths resolve the same way
# wherever the gate is invoked from.
TOP="$(git rev-parse --show-toplevel 2>/dev/null)" \
  || { echo "ClaudeGuard: not inside a git repository"; exit 2; }
cd "$TOP"

# The policy lives at the repository root. Without it there is nothing to judge,
# and a model sent to look for it elsewhere guesses; stop here instead.
[ -d rulesets ] || { echo "ClaudeGuard: rulesets/ not found at the repository root"; exit 2; }

BASE_REF="${1:-}"
if [ -z "$BASE_REF" ] && [ -f "$CONFIG" ]; then
  # `base` is a flat string key; read it without requiring jq.
  BASE_REF="$(sed -nE 's/.*"base"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' "$CONFIG" | head -n1)"
fi
BASE_REF="${BASE_REF:-origin/main}"

git fetch --quiet origin >/dev/null 2>&1 || true

git rev-parse --verify --quiet "${BASE_REF}^{commit}" >/dev/null \
  || { echo "ClaudeGuard: base ref '$BASE_REF' does not resolve to a commit"; exit 2; }
git merge-base "$BASE_REF" HEAD >/dev/null \
  || { echo "ClaudeGuard: no merge base between '$BASE_REF' and HEAD (shallow clone? fetch full history)"; exit 2; }

if git diff --quiet "${BASE_REF}...HEAD" --; then
  printf 'ClaudeGuard verdict: PASS (empty diff vs %s)\n\nclaudeguard-verdict: PASS\n' "$BASE_REF" \
    | tee "$REPORT_MD"
  exit 0
fi

PROMPT="Run the claudeguard skill. Gate the commits of the current branch against \
base ref '${BASE_REF}' (diff range ${BASE_REF}...HEAD). The policy is at the \
repository root: ./claudeguard.config.json (optional) and the *.md rules under \
./rulesets/. Follow SKILL.md exactly: resolve rulesets, run the mandatory smoke \
check and every declared probe, build the detect candidates as step 5 prescribes, \
evaluate, and output the human report followed by the machine-readable \`\`\`json \
block. Do not edit any files. This is a headless, read-only audit: the report is \
the deliverable and there is nothing to plan or approve. End with a final line \
exactly: claudeguard-verdict: <PASS|WARN|FAIL>."

# Headless, with an explicit tool set.
#
# `dontAsk` denies every call that would need approval instead of prompting.
# --allowed-tools names what SKILL.md uses: the file tools (rules, probe B) and the
# read-only git commands of the procedure. --disallowed-tools removes the editing
# tools from the session outright.
#
# Not `--permission-mode plan`: headless plan mode once gated the very `git diff`
# the skill starts with, so the gate died without a verdict on clean PRs.
#
# Defense in depth, not a boundary: `--output` makes git diff/log/show write a
# file, and Claude Code classifies read-only git by subcommand, so that flag is
# denied explicitly. Other write- or exec-capable git flags are not enumerated - a
# denylist of spellings is not a boundary. The boundary for an untrusted branch is
# where the gate runs: an ephemeral CI runner or a container, never a workstation
# holding credentials. See "Security model" in the README.
set +e
claude -p "$PROMPT" \
  --permission-mode dontAsk \
  --allowed-tools Read Grep Glob \
    "Bash(git diff:*)" "Bash(git grep:*)" "Bash(git log:*)" \
    "Bash(git merge-base:*)" "Bash(git rev-parse:*)" \
  --disallowed-tools Edit Write NotebookEdit "Bash(git *--output*)" \
  | tee "$REPORT_MD"
CLAUDE_STATUS="${PIPESTATUS[0]}"
set -e

if [ "$CLAUDE_STATUS" -ne 0 ]; then
  echo ""
  echo "ClaudeGuard: the claude CLI exited $CLAUDE_STATUS - no verdict was produced."
  echo "             That is an infrastructure error (auth, credit, network), not a policy FAIL."
  exit 2
fi

# Read the verdict. Prefer the machine sentinel line; fall back to the JSON block.
VERDICT="$(
  grep -iE '^[[:space:]]*claudeguard-verdict:[[:space:]]*[A-Za-z]+' "$REPORT_MD" \
    | tail -n1 | sed -E 's/.*:[[:space:]]*([A-Za-z]+).*/\1/' \
    | tr '[:lower:]' '[:upper:]' || true
)"
if [ -z "$VERDICT" ]; then
  VERDICT="$(
    awk '/```json/{f=1;next} /```/{f=0} f' "$REPORT_MD" \
      | grep -oE '"verdict"[[:space:]]*:[[:space:]]*"[A-Z]+"' \
      | tail -n1 | sed -E 's/.*"([A-Z]+)".*/\1/' || true
  )"
fi

echo ""
echo "ClaudeGuard parsed verdict: ${VERDICT:-UNKNOWN}"

case "$VERDICT" in
  PASS|WARN) exit 0 ;;
  FAIL)      exit 1 ;;
  *)         echo "ClaudeGuard: could not parse verdict from report"; exit 2 ;;
esac
