---
id: no-conflict-markers
severity: high
applies_to:
  - "**/*"
enabled: true
---

# No leftover merge conflict markers

**FAIL** when the diff adds an unresolved git conflict marker.

Trip on added lines that begin with a 7-character conflict marker:

- `<<<<<<< ` followed by a ref/branch name (start of "ours").
- `>>>>>>> ` followed by a ref/branch name (end of "theirs").
- `||||||| ` — the merge base, in `diff3` conflict style.
- `=======` **only** when it sits between a `<<<<<<<` and a `>>>>>>>` in the
  same hunk. A bare `=======` is a legitimate Markdown/reST heading underline or
  a decorative separator and must **not** be flagged on its own.

**Why:** conflict markers are never valid source — they mean a merge was left
half-resolved. Merging them breaks the build, or silently ships both sides of a
change. This is trivially caught before merge and never a false alarm.

**Suggestion:** finish resolving the conflict — keep the intended side, delete
the markers, and re-run the build/tests before committing.

**Exemptions:** documentation that *quotes* conflict markers to explain them
(inside a code block / clearly illustrative). Judge by context: prose teaching
about markers is not an unresolved conflict in shipped code.
