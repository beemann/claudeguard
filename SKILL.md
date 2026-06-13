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

**Engine vs. policy.** The universal `_core` rules ship with the engine; the
team's `house` rules and config live in the project. When ClaudeGuard runs as an
installed Claude Code plugin, `${CLAUDE_PLUGIN_ROOT}` is the engine root (where
the bundled `rulesets/_core/` lives). When it runs from a repo that vendored the
files (via the installer or `claudeguard-init`), everything lives under the
project root. The ruleset-resolution step below handles both transparently.

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

Read `claudeguard.config.json` from the **project root** if present (fall back to
`claudeguard.config.example.json` semantics: everything enabled).

Gather ruleset `*.md` files from **two roots**, then merge:

1. **Engine `_core`** — if the `${CLAUDE_PLUGIN_ROOT}` environment variable is set
   (ClaudeGuard is running as an installed plugin), include
   `${CLAUDE_PLUGIN_ROOT}/rulesets/_core/*.md`.
2. **Project policy** — always include every `*.md` under the project's
   `rulesets/` directory (`rulesets/house/`, plus any vendored or overriding
   `rulesets/_core/`).

**Dedupe by `id`.** If the same rule `id` appears in both roots, the **project
copy wins** — a repo can override a shipped core rule by committing its own file
with that `id`. (If `${CLAUDE_PLUGIN_ROOT}` is unset, only the project root is
read, which is the vendored / self-test case.)

For each resulting ruleset file:

- Parse its frontmatter (`id`, `severity`, `applies_to`, optional `enabled`, and
  optional `detect`/`exempt` regex lists — see step 4).
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

Judge only **added/modified** lines (`+`), never pre-existing context, unless a
rule explicitly targets removals. Strip the leading `+` before matching.

**Rules with `detect` patterns — hybrid (deterministic detection).** First build
the candidate set *deterministically*: an added line is a candidate when it
matches any `detect` regex (case-insensitive ERE) and does **not** match any
`exempt` regex. Apply the patterns literally — e.g.
`git diff --merge-base <base> | grep -iE -e '<detect>'` — so detection is
reproducible and a real hit cannot be silently missed. Then adjudicate **only the
candidates** against the rule body, applying the remaining prose exemptions the
regex cannot decide (e.g. test fixtures, doc examples, the `=======`-between-markers
nuance). A candidate the body does not exempt is a violation. These `detect`/
`exempt` patterns are validated offline by `scripts/test-rules.{sh,ps1}` against
`fixtures/`, so the deterministic layer is regression-tested.

**Rules without `detect` — judgment.** Read the body (the human-readable contract)
and judge the diff against it directly.

Every violation requires concrete evidence: a `file`, a `line` (best effort), and
the **exact added line** that trips the rule. No evidence → no violation.

**A rule never flags its own test data.** Lines under `fixtures/<rule-id>/` are
that rule's intentional fixtures (and a rule body's own quoted examples are
illustrative) — they are crafted to match and must **not** be reported as
violations.

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

The verdict report **is** the deliverable. When invoked headless (e.g. by the CI
runner in plan mode), do **not** call `ExitPlanMode`, do not present a plan, and
do not pause for approval — this is a read-only audit with no implementation step
to approve. Produce the report directly as your reply so the runner can parse it.

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

### Verdict line (machine sentinel)

After the JSON block, emit **one final line**, exactly:

```
claudeguard-verdict: FAIL
```

(`PASS` | `WARN` | `FAIL`.) This single line is what the runner reads to decide
the exit code — it does not scrape the verdict out of prose. The JSON block stays
for humans and CI artifacts. When run by CI, the wrapper script maps the verdict
to an exit code: `PASS`/`WARN` → 0, `FAIL` → 1.

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
