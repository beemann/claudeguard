#!/usr/bin/env bash
# ClaudeGuard - deterministic rule self-test (POSIX, no LLM, no API key).
#
# Every rule that declares `detect:` patterns must ship fixtures under
# fixtures/<rule-id>/, and this harness asserts that:
#   - every line in should-fail.txt IS a candidate
#   - no line in should-pass.txt is a candidate
#
# A line is a candidate when it matches no `exempt` pattern and some match of a
# `detect` pattern is not overlapped by an `exempt_match` match. That is the rule
# SKILL.md applies to a diff (step 5), in the same dialect: case-insensitive POSIX
# ERE (`git grep -iE` there, `grep -iE` here).
#
# The two exemption keys answer different questions:
#   exempt        - the LINE is fine in context (wrapped in `docker compose exec`,
#                   a comment). Any match anywhere on the line drops it.
#   exempt_match  - this VALUE is known-harmless (a documented dummy key, an
#                   environment reference). It excuses only the detect matches it
#                   overlaps, so `process.env.KEY || "sk-live-..."` is still a
#                   candidate: the env reference does not excuse the literal.
# Each detect pattern is matched on its own, so a long excused match cannot hide a
# shorter real one; exempt_match matches are collected in one pass.
#
# Portable to bash 3.2 (the macOS default): no mapfile, no associative arrays.
#
# Usage:   scripts/test-rules.sh
# Exit:    0 = all assertions pass, 1 = an assertion failed, 2 = setup error.
set -euo pipefail
# grep -b reports byte offsets, so ${#var} has to count bytes as well.
export LC_ALL=C

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RULES_DIR="$ROOT/rulesets"
FIX_DIR="$ROOT/fixtures"

[ -d "$RULES_DIR" ] || { echo "test-rules: no rulesets/ directory"; exit 2; }
[ -d "$FIX_DIR" ]   || { echo "test-rules: no fixtures/ directory"; exit 2; }

# Print the patterns under a frontmatter list key, one per line.
# The CR is stripped first: a CRLF checkout must not blind the parser.
list_patterns() { # <rule-file> <key>
  awk -v k="$2" '
    { sub(/\r$/, "") }
    $0=="---"{d++; next}
    d!=1{next}
    $0==k":"{inl=1; next}
    inl && /^[[:space:]]+-[[:space:]]/{print; next}
    inl{inl=0}
  ' "$1" | sed -E "s/^[[:space:]]*-[[:space:]]*'//; s/'[[:space:]]*\$//"
}

# Print the frontmatter id of a rule file; nothing if it has none.
rule_id() { # <rule-file>
  awk '
    { sub(/\r$/, "") }
    $0=="---"{d++; next}
    d==1 && /^id:/{sub(/^id:[[:space:]]*/, ""); sub(/[[:space:]]+$/, ""); print; exit}
  ' "$1"
}

# Fill the global array LIST with the patterns under a frontmatter key.
read_list() { # <rule-file> <key>
  LIST=()
  local p
  while IFS= read -r p; do LIST+=("$p"); done < <(list_patterns "$1" "$2")
}

# "<offset> <length>" in bytes for every match on a line. With several -e
# arguments grep reports one leftmost-longest match per position, as git grep does.
spans() { # <line> -e <pattern> [-e <pattern>...]
  local line="$1" m text
  shift
  grep -obiE "$@" <<< "$line" | while IFS= read -r m; do
    text="${m#*:}"
    printf '%s %s\n' "${m%%:*}" "${#text}"
  done || true
}

# True when the line is a candidate under DETECT, EXEMPT and EXEMPT_MATCH.
is_candidate() { # <line>
  local line="$1" ex="" p ds dl es el covered
  local args=()
  if [ "${#EXEMPT[@]}" -gt 0 ]; then
    for p in "${EXEMPT[@]}"; do args+=(-e "$p"); done
    if grep -qiE "${args[@]}" <<< "$line"; then return 1; fi
    args=()
  fi
  if [ "${#EXEMPT_MATCH[@]}" -gt 0 ]; then
    for p in "${EXEMPT_MATCH[@]}"; do args+=(-e "$p"); done
    ex="$(spans "$line" "${args[@]}")"
  fi
  for p in "${DETECT[@]}"; do
    while read -r ds dl; do
      [ -n "$ds" ] || continue
      covered=0
      while read -r es el; do
        [ -n "$es" ] || continue
        if [ "$ds" -lt $((es + el)) ] && [ "$es" -lt $((ds + dl)) ]; then covered=1; break; fi
      done <<EOF
$ex
EOF
      if [ "$covered" -eq 0 ]; then return 0; fi
    done < <(spans "$line" -e "$p")
  done
  return 1
}

fails=0
tested=0
skipped=0
known_ids=" "

while IFS= read -r rf; do
  id="$(rule_id "$rf")"
  [ -n "$id" ] || continue
  known_ids="$known_ids$id "

  read_list "$rf" detect; DETECT=(${LIST[@]+"${LIST[@]}"})
  read_list "$rf" exempt; EXEMPT=(${LIST[@]+"${LIST[@]}"})
  read_list "$rf" exempt_match; EXEMPT_MATCH=(${LIST[@]+"${LIST[@]}"})
  if [ "${#DETECT[@]}" -eq 0 ]; then
    echo "SKIP  $id  (judgment-only rule, no detect patterns)"; skipped=$((skipped+1)); continue
  fi

  rule_fails=0
  assertions=0

  # An invalid pattern must not read as "no match": grep exits 2 on a bad regex.
  for p in "${DETECT[@]}" ${EXEMPT[@]+"${EXEMPT[@]}"} ${EXEMPT_MATCH[@]+"${EXEMPT_MATCH[@]}"}; do
    rc=0; grep -iE -e "$p" </dev/null >/dev/null 2>&1 || rc=$?
    if [ "$rc" -eq 2 ]; then
      echo "  FAIL [$id] invalid ERE: $p"; rule_fails=$((rule_fails+1))
    fi
  done

  dir="$FIX_DIR/$id"
  if [ ! -f "$dir/should-fail.txt" ] && [ ! -f "$dir/should-pass.txt" ]; then
    echo "FAIL  $id  (detect patterns but no fixtures/$id/should-{fail,pass}.txt - untested)"
    fails=$((fails+1)); continue
  fi

  # should-fail: every line must be a candidate.
  if [ -f "$dir/should-fail.txt" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      line="${line%$'\r'}"
      [ -n "$line" ] || continue
      assertions=$((assertions+1))
      if ! is_candidate "$line"; then
        echo "  FAIL [$id] should-fail line is not a candidate: $line"; rule_fails=$((rule_fails+1))
      fi
    done < "$dir/should-fail.txt"
  fi

  # should-pass: no line may be a candidate.
  if [ -f "$dir/should-pass.txt" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      line="${line%$'\r'}"
      [ -n "$line" ] || continue
      assertions=$((assertions+1))
      if is_candidate "$line"; then
        echo "  FAIL [$id] should-pass line is a candidate: $line"; rule_fails=$((rule_fails+1))
      fi
    done < "$dir/should-pass.txt"
  fi

  if [ "$assertions" -eq 0 ]; then
    echo "  FAIL [$id] fixtures hold no lines"; rule_fails=$((rule_fails+1))
  fi

  tested=$((tested+1))
  if [ "$rule_fails" -eq 0 ]; then
    echo "PASS  $id  (${#DETECT[@]} detect, ${#EXEMPT[@]} exempt, ${#EXEMPT_MATCH[@]} exempt_match, $assertions assertions)"
  else
    echo "FAIL  $id  ($rule_fails assertion(s) failed)"; fails=$((fails+rule_fails))
  fi
done < <(find "$RULES_DIR" -type f -name '*.md' | sort)

# Fixtures for an id no rule declares are a renamed or deleted rule whose
# patterns nobody tests any more.
for dir in "$FIX_DIR"/*/; do
  [ -d "$dir" ] || continue
  id="$(basename "$dir")"
  case "$known_ids" in
    *" $id "*) ;;
    *) echo "FAIL  $id  (fixtures/$id/ but no rule with this id)"; fails=$((fails+1)) ;;
  esac
done

echo ""
echo "test-rules: $tested rule(s) tested, $skipped skipped, $fails assertion failure(s)."

# A harness that tested nothing is not a harness that passed.
#
# This is not hypothetical: on a checkout with CRLF line endings, `$0=="---"` never
# matched `---\r`, so no frontmatter was parsed, every rule was classified
# "judgment-only, no detect patterns", and the run reported 0 tested / 3 skipped and
# exited 0 - a clean bill of health from a check that had stopped checking. The
# parser now strips the CR, and reaching the end without having tested a single
# rule stays a failure of the harness, not a pass for the rules.
if [ "$tested" -eq 0 ]; then
  echo "test-rules: FAIL - no rule was tested. Fixtures or frontmatter are not being"
  echo "            parsed. Refusing to report success for a check that ran nothing."
  exit 1
fi

[ "$fails" -eq 0 ]
