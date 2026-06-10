---
name: claudeguard
description: Pre-merge policy gate. Checks a git diff against versioned house rulesets and returns a structured PASS/FAIL verdict. Use before merging to main/master, when reviewing a branch or PR for policy violations, or when the user asks to "run claudeguard", "gate this branch", or "check policy compliance". Report-only — never edits files.
---

# ClaudeGuard — policy gate

ClaudeGuard is a **report-only gate**. It does not edit code, apply patches, or
fix anything. It reads a diff, evaluates it against the active rulesets, and
emits a structured verdict. A human decides what to do with `FAIL`.

It deliberately reuses the host agent's existing engine (git, diff reading,
reasoning) instead of rebuilding an LLM client, diff analyzer, or patch
applier. The only thing ClaudeGuard owns is **policy as data**.

## When to run

- Before merging a feature/`dev` branch into `main`/`master`.
- On a pull request (via `.github/workflows/claudeguard.yml`).
- On demand: "run claudeguard", "gate this branch", "check policy".

## Inputs

1. **The diff under review.** Default range is `origin/main...HEAD` (the merge
   base, so only commits unique to this branch are judged). The user may
   override the base (e.g. `dev`, `master`, an explicit SHA).
2. **The active rulesets.** Every `*.md` under `rulesets/` whose `id` is not
   disabled by `claudeguard.config.json`. See *Resolving rulesets* below.

## Procedure

Follow these steps exactly. Do not skip the smoke check.

### 1. Resolve the diff

Determine the base ref (default `origin/main`, or the user's override). Get:

```
git fetch --quiet origin            # best-effort; ignore failure offline
git diff --merge-base <base> -- .   # full unified diff of the changeset
git diff --merge-base <base> --name-only
```

If the diff is empty, emit a `PASS` verdict with `files_scanned: 0` and stop.

### 2. Resolve rulesets

Read `claudeguard.config.json` if present (fall back to
`claudeguard.config.example.json` semantics: everything enabled). For each
ruleset file under `rulesets/`:

- Parse its frontmatter (`id`, `severity`, `applies_to`, optional `enabled`).
- Skip it if the config sets `rules.<id>.enabled: false`.
- Apply a `severity` override from the config if present.
- Keep it only if at least one changed file path matches one of its
  `applies_to` globs. (A rule that matches nothing is inert — do not invent
  violations to justify it.)

### 3. Smoke check (mandatory, anti-falsification)

Before judging, for each kept ruleset state in one line **how many changed
files it actually applies to**. If a rule applies to zero files, drop it. This
prevents reporting violations for code paths the change never touches — the
same measurement-first discipline the rulesets themselves enforce.

### 4. Evaluate

For each kept ruleset, read its body (the human-readable contract) and judge
the diff against it. A violation requires concrete evidence in the diff: a
`file`, a `line` (best effort), and the **exact added line(s)** that trip the
rule. No evidence → no violation. Judge only **added/modified** lines (`+`),
not pre-existing context, unless the rule explicitly targets removals.

Be precise, not zealous. A false `FAIL` erodes trust in the gate faster than a
missed `LOW`. When genuinely uncertain, record it as `severity: info` with a
note rather than forcing a `FAIL`.

### 5. Verdict

The overall verdict is:

- `FAIL` if any violation has effective severity `high` or `critical`.
- `WARN` if the worst violation is `medium` or `low` (merge allowed, attention
  advised).
- `PASS` if there are no violations.

(`block_on` in the config may raise/lower this threshold — default `high`.)

## Output format

Emit **both** a human-readable table and a machine-readable JSON block, in this
order.

### Human report

```
ClaudeGuard verdict: FAIL
Base: origin/main · Files scanned: 7 · Rulesets active: 5

| Severity | Rule              | File             | Line | Why                                  |
|----------|-------------------|------------------|------|--------------------------------------|
| high     | docker-only       | scripts/dev.ps1  | 12   | `npm run dev` invoked on host        |
| medium   | no-any            | src/api/user.ts  | 44   | `: any` on request body              |

2 violations (1 high, 1 medium). Merge blocked by `block_on: high`.
```

### Machine block

Wrap in a fenced ```json block so CI can parse it:

```json
{
  "verdict": "FAIL",
  "base": "origin/main",
  "files_scanned": 7,
  "rulesets_active": ["docker-only", "measurement-first", "no-any", "security-routes", "no-destructive-db"],
  "violations": [
    {
      "rule": "docker-only",
      "severity": "high",
      "file": "scripts/dev.ps1",
      "line": 12,
      "evidence": "+ npm run dev",
      "why": "Command invoked on host instead of `docker compose exec app …`.",
      "suggestion": "docker compose exec app npm run dev"
    }
  ],
  "block_on": "high"
}
```

When run by CI, the wrapper script maps `verdict` to an exit code:
`PASS`/`WARN` → 0, `FAIL` → 1.

## Hard constraints

- **Never edit, stage, or commit files.** This skill is a gate, not a fixer.
- **Never invent violations** to make a ruleset look useful. Inert rule → drop.
- **Cite evidence** for every violation (exact added line). No quote, no claim.
- Keep the report deterministic in structure so diffs of reports are reviewable.

## Adding a rule

Drop a new `*.md` into `rulesets/_core/` (universal) or `rulesets/house/`
(this team's). Give it `id`, `severity`, `applies_to` frontmatter and a body
that states, in plain language, what a `FAIL` looks like and why. No engine
change required — the procedure above picks it up automatically.
