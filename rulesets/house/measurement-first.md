---
id: measurement-first
severity: medium
applies_to:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "**/*.py"
  - "**/*.rs"
  - "**/*.go"
enabled: true
---

# Measurement-first discipline (anti-falsification)

**FAIL** when a change *claims* to improve a measurable property — performance,
latency, memory, accuracy, bundle size — but the diff adds **no measurement**
to prove it and no measurement already covers the touched code.

Triggers (look at commit messages, PR title, code comments, and identifiers in
the diff): words like *optimize, speed up, faster, reduce, improve, cache,
parallelize, batch, lower latency*.

A change passes this rule if **any** of these is true:

- It adds or updates a benchmark / profiling harness covering the change.
- It adds a test asserting the new bound (e.g. timing, allocation count).
- An existing benchmark/test in the diff's scope already measures it.
- The change is an **exempt** plain bug fix (compile error, crash, wrong output
  for a specific input) — those are validated by reproduction, not metrics.

**Why:** optimizations shipped without a falsification instrument routinely
regress and get reverted. The cost of measuring first is minutes; the cost of a
silent regression is hours.

**Suggestion:** before the implementation, add the smallest benchmark/test that
would reveal a regression, capture the baseline, then change the code.

When flagging, quote the claim (the word/comment that triggered it) and note
that no corresponding measurement appears in the diff.
