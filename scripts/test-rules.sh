#!/usr/bin/env bash
# ClaudeGuard - deterministic rule self-test (POSIX, no LLM, no API key).
#
# For every rule that declares `detect:` patterns in its frontmatter and ships
# fixtures under fixtures/<rule-id>/, assert that:
#   - each line in should-fail.txt  MATCHES a detect pattern AND is NOT exempt
#   - each line in should-pass.txt  does NOT match detect  OR  is exempt
# Matching is case-insensitive ERE (grep -iE), the same engine the gate uses.
#
# Usage:   scripts/test-rules.sh
# Exit:    0 = all assertions pass, 1 = a fixture failed, 2 = setup error.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RULES_DIR="$ROOT/rulesets"
FIX_DIR="$ROOT/fixtures"

[ -d "$FIX_DIR" ] || { echo "test-rules: no fixtures/ directory"; exit 2; }

# Print the patterns under a frontmatter list key (detect|exempt), one per line.
list_patterns() { # <rule-file> <key>
  awk -v k="$2" '
    $0=="---"{d++; next}
    d!=1{next}
    $0==k":"{inl=1; next}
    inl && /^[[:space:]]+-[[:space:]]/{print; next}
    inl{inl=0}
  ' "$1" | sed -E "s/^[[:space:]]*-[[:space:]]*'//; s/'[[:space:]]*\$//"
}

# Locate the rule file whose frontmatter id == $1.
rule_file_for_id() { # <id>
  grep -rlE "^id:[[:space:]]*$1[[:space:]]*\$" "$RULES_DIR" 2>/dev/null | head -n1
}

# Does $line match ANY pattern in the array passed by name?
matches_any() { # <line> <pattern...>
  local line="$1"; shift
  local p
  for p in "$@"; do
    [ -z "$p" ] && continue
    if printf '%s\n' "$line" | grep -qiE -e "$p"; then return 0; fi
  done
  return 1
}

fails=0
tested=0
skipped=0

for dir in "$FIX_DIR"/*/; do
  [ -d "$dir" ] || continue
  id="$(basename "$dir")"
  rf="$(rule_file_for_id "$id")"
  if [ -z "$rf" ]; then
    echo "SKIP  $id  (no rule with this id)"; skipped=$((skipped+1)); continue
  fi

  mapfile -t DETECT < <(list_patterns "$rf" detect)
  mapfile -t EXEMPT < <(list_patterns "$rf" exempt)
  if [ "${#DETECT[@]}" -eq 0 ]; then
    echo "SKIP  $id  (judgment-only rule, no detect patterns)"; skipped=$((skipped+1)); continue
  fi

  rule_fails=0

  # should-fail: must be detected and not exempt.
  if [ -f "$dir/should-fail.txt" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      [ -z "$line" ] && continue
      if ! matches_any "$line" "${DETECT[@]}"; then
        echo "  FAIL [$id] should-fail line not detected: $line"; rule_fails=$((rule_fails+1))
      elif matches_any "$line" "${EXEMPT[@]}"; then
        echo "  FAIL [$id] should-fail line wrongly exempted: $line"; rule_fails=$((rule_fails+1))
      fi
    done < "$dir/should-fail.txt"
  fi

  # should-pass: must be undetected or exempt.
  if [ -f "$dir/should-pass.txt" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      [ -z "$line" ] && continue
      if matches_any "$line" "${DETECT[@]}" && ! matches_any "$line" "${EXEMPT[@]}"; then
        echo "  FAIL [$id] should-pass line wrongly flagged: $line"; rule_fails=$((rule_fails+1))
      fi
    done < "$dir/should-pass.txt"
  fi

  tested=$((tested+1))
  if [ "$rule_fails" -eq 0 ]; then
    echo "PASS  $id  (${#DETECT[@]} detect, ${#EXEMPT[@]} exempt)"
  else
    echo "FAIL  $id  ($rule_fails assertion(s) failed)"; fails=$((fails+rule_fails))
  fi
done

echo ""
echo "test-rules: $tested rule(s) tested, $skipped skipped, $fails assertion failure(s)."
[ "$fails" -eq 0 ]
