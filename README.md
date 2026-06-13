# ClaudeGuard

> A report-only, pre-merge **policy gate** that runs as a [Claude Code](https://claude.com/claude-code) skill.
> It reads a diff, evaluates it against versioned rulesets, and emits a structured **PASS / WARN / FAIL** verdict. It never edits your code.
>
> **Install in one command** — `/plugin marketplace add beemann/claudeguard` then `/plugin install claudeguard@claudeguard`. ([What's new in 0.1.0](#whats-new-in-010))

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

---

## What it is

ClaudeGuard is a **gate, not a fixer**. It answers one question on every change —
*"does this diff violate our policy?"* — and leaves the decision to a human.

It deliberately **reuses the host agent's existing engine** (git, diff reading,
reasoning) instead of rebuilding an LLM client, a diff analyzer, or a patch
applier. The only thing ClaudeGuard owns is **policy as data**: a folder of
plain-Markdown rules, each with a small frontmatter contract and a human-readable
body describing what a failure looks like and why.

That design has three consequences worth stating up front:

- **Separation of concerns.** A component that both *finds* and *fixes*
  violations has an incentive to over-flag to look useful. A pure gate doesn't.
- **No unreviewed merges.** Running on a PR moments before merge, an auto-fixer
  would mutate the very diff a human just reviewed. ClaudeGuard reports; you act.
- **Determinism & auditability.** The output is a verdict table plus a parseable
  JSON block — diffable, reviewable, and mappable to a CI exit code.

## What's new in 0.1.0

ClaudeGuard is now **packaged for one-step adoption** — no more copy-pasting files
into your repo:

- **Claude Code plugin + marketplace.** Install the gate and a `claudeguard-init`
  bootstrap skill with two `/plugin` commands; the engine auto-updates via
  `/plugin update`.
- **`claudeguard-init` skill.** Ask *"set up claudeguard"* and it scaffolds the
  policy template into the current repo for you.
- **Standalone installer** (`scripts/install.{sh,ps1}`) for any repo or CI, with
  no plugin dependency — idempotent, and it never clobbers your house rules or config.
- **Engine / policy split.** Universal `_core` rules ship with the engine; your
  `house` rules and config live in your repo. The gate resolves both and lets the
  project override a shipped rule.

Full notes in the [CHANGELOG](CHANGELOG.md).

## Install

Two ways to adopt ClaudeGuard, sharing one design — a universal **engine**
(the gate skill, `_core` rules, runner scripts) plus per-project **policy**
(`rulesets/house/`, `claudeguard.config.json`, the CI workflow).

### As a Claude Code plugin

```text
/plugin marketplace add beemann/claudeguard
/plugin install claudeguard@claudeguard
```

You immediately get two skills in every project: `claudeguard` (the gate) and
`claudeguard-init` (bootstrap). To scaffold the gate into the current repo, ask:

> *set up claudeguard* · *claudeguard init*

The engine updates with `/plugin update`. When run as a plugin, the gate reads
its `_core` rules from the plugin and your `house` rules from the project.

### Standalone (any repo / CI)

Vendors the engine + a policy template into your repo, self-contained with no
plugin dependency — ideal for CI:

```bash
# POSIX
scripts/install.sh /path/to/your/repo
```
```powershell
# PowerShell
./scripts/install.ps1 -Target C:\path\to\your\repo
```

The installer is idempotent: it refreshes engine files on every run and never
overwrites your policy (`rulesets/house/`, `claudeguard.config.json`, an existing
workflow). See [Forking into your project](#forking-into-your-project) for what
it lays down.

## Why

Static linters catch syntax; they don't catch *policy*. "We run everything
through Docker", "no destructive migration without sign-off", "every new route
declares its auth posture", "no optimization without a measurement" — these are
team contracts that normally live in a `CLAUDE.md` nobody re-reads at review
time. ClaudeGuard turns those contracts into executable rules and enforces them
at the last cheap moment: **before the merge**.

## How it works

The procedure is defined in [`SKILL.md`](SKILL.md) and runs in five steps:

1. **Resolve the diff.** Default base is `origin/main` (merge-base, so only the
   branch's own commits are judged); overridable per project or per run.
2. **Resolve rulesets.** Read every `*.md` from the engine's `_core`
   (`${CLAUDE_PLUGIN_ROOT}/rulesets/_core/` when installed as a plugin) and the
   project's `rulesets/`, dedupe by `id` (the project copy wins so a repo can
   override a shipped rule), honor `claudeguard.config.json` (enable/disable,
   severity overrides), and keep only rules whose `applies_to` globs match at
   least one changed file.
3. **Smoke check (mandatory, anti-falsification).** For each kept rule, state how
   many changed files it *actually* applies to. A rule that matches zero files is
   dropped — the gate never invents violations to justify a rule.
4. **Evaluate.** Judge only added/modified (`+`) lines. Rules that declare `detect`
   patterns get **deterministic candidate detection** (regex finds the hits; the
   model only adjudicates them against the rule's exemptions); rules without
   `detect` are judged by the model directly. Every violation must cite concrete
   evidence: a file, a best-effort line, and the exact offending line.
5. **Verdict.** `FAIL` if any violation is `high`/`critical`; `WARN` for
   `medium`/`low`; `PASS` if clean. The threshold is configurable via `block_on`
   (default `high`).

## Output

ClaudeGuard emits a human-readable table followed by a machine-readable JSON
block:

```
ClaudeGuard verdict: FAIL
Base: origin/main · Files scanned: 7 · Rulesets active: 5

| Severity | Rule        | File            | Line | Why                          |
|----------|-------------|-----------------|------|------------------------------|
| high     | docker-only | scripts/dev.ps1 | 12   | `npm run dev` invoked on host |
| medium   | no-any      | src/api/user.ts | 44   | `: any` on request body       |
```

```json
{
  "verdict": "FAIL",
  "base": "origin/main",
  "files_scanned": 7,
  "rulesets_active": ["docker-only", "no-any", "..."],
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

The CI runner maps the verdict to an exit code: `PASS`/`WARN` → `0`, `FAIL` → `1`.

## Rulesets

Rules ship in two tiers:

| Tier | Folder | Intent |
|------|--------|--------|
| **Core** | `rulesets/_core/` | Universal, provider-agnostic, uncontroversial — adopt as-is. |
| **House** | `rulesets/house/` | Your team's opinionated rules — swap when you fork. |

Bundled rules:

| Rule | Tier | Severity | Trips on |
|------|------|----------|----------|
| `no-secrets` | core | critical | Credential/key/token literals (provider prefixes, PEM blocks, secret assignments). |
| `no-conflict-markers` | core | high | Unresolved git conflict markers committed to a tracked file. |
| `docker-only` | house | high | Project tooling run on the host instead of in-container (shell scripts & task runners). |
| `no-destructive-db` | house | critical | Unguarded `DROP`/`TRUNCATE`/`DELETE … ` without `WHERE`, etc. |
| `security-routes` | house | high | A new route/handler with no visible auth, validation, or injection posture. |
| `no-any` | house | medium | `any`, `as any`, `@ts-ignore` and other TypeScript escape hatches. |
| `measurement-first` | house | medium | A change claiming to *optimize* something with no benchmark/measurement. |

## Usage

### As a Claude Code skill

Place this repo's contents where Claude Code discovers skills (e.g.
`.claude/skills/claudeguard/` in your project), then ask:

> *run claudeguard* · *gate this branch* · *check policy compliance*

### Local runner

```powershell
# PowerShell
./scripts/check.ps1 -BaseRef origin/main
```

```bash
# POSIX
scripts/check.sh origin/main
```

Requires `git`, the `claude` CLI on `PATH`, and `ANTHROPIC_API_KEY` in the
environment. An empty diff is an immediate `PASS`.

### CI (GitHub Actions)

[`.github/workflows/claudeguard.yml`](.github/workflows/claudeguard.yml) gates
pull requests, posts the verdict as a PR comment and job summary, and blocks the
merge on a high/critical violation. Add a repository secret
`ANTHROPIC_API_KEY` to activate it.

> **Security note:** the workflow uses `on: pull_request` (not
> `pull_request_target`). On public repos, GitHub does **not** pass secrets to
> workflows triggered by fork PRs, so an untrusted PR cannot exfiltrate the API
> key — by design.

## Configuration

Copy [`claudeguard.config.example.json`](claudeguard.config.example.json) to
`claudeguard.config.json` and edit per project:

```json
{
  "base": "origin/main",
  "block_on": "high",
  "rules": {
    "no-secrets": { "enabled": true },
    "docker-only": { "enabled": true, "severity": "critical" }
  }
}
```

- `base` — default ref to diff against.
- `block_on` — minimum severity that produces a `FAIL` (`low`|`medium`|`high`|`critical`).
- `rules.<id>.enabled` — toggle a rule off without deleting it.
- `rules.<id>.severity` — override a rule's shipped severity.

## Authoring a rule

Drop a `*.md` into `rulesets/_core/` (universal) or `rulesets/house/`
(team-specific). No code change is required — the procedure picks it up
automatically.

```markdown
---
id: no-todo-without-ticket
severity: low
applies_to:
  - "**/*.ts"
  - "**/*.py"
enabled: true
detect:                       # optional: deterministic candidate detection (ERE)
  - 'TODO|FIXME'
exempt:                       # optional: suppress candidates that cite a ticket
  - '[A-Z]+-[0-9]+|#[0-9]+'
---

# No TODO without a tracking ticket

**FAIL** when the diff adds a `TODO`/`FIXME` with no issue reference.

Trip on added lines matching `TODO`/`FIXME` not followed by a ticket id
(e.g. `JIRA-123`, `#456`).

**Why:** untracked TODOs are debt that never gets scheduled.

**Suggestion:** link a ticket, or do the work now.
```

**Deterministic detection (optional).** A rule may carry `detect` (and `exempt`)
regex lists. Detection then runs *deterministically*: a changed line is a candidate
when it matches a `detect` pattern and no `exempt` pattern, and the model only
*adjudicates* those candidates against the rule body. This makes recall
reproducible — a real hit can't be silently missed — and is the right shape for
pattern rules (`no-secrets`, `no-conflict-markers`, `no-any`). Rules with no
`detect` are judged purely by the model, as before.

**Test your patterns.** Add `fixtures/<rule-id>/should-fail.txt` and
`should-pass.txt`, then run `scripts/test-rules.sh` (or `.ps1`). It asserts every
`detect`/`exempt` pattern against the fixtures with **no LLM and no API key**, so
the deterministic layer is regression-tested for free.

Keep `_core` rules uncontroversial; anything debatable belongs in `house/`.
Every rule body should state, in plain language, **what a `FAIL` looks like**,
**why** it matters, and a **suggestion** — and should rely on evidence visible
in the diff.

## Forking into your project

The fastest path is the [standalone installer](#standalone-any-repo--ci) or the
`claudeguard-init` skill — both lay down exactly what's below. Under the hood it:

1. Copies the engine into your repo: the gate skill →
   `.claude/skills/claudeguard/SKILL.md`, `rulesets/_core/`, `scripts/check.*`,
   and (if absent) the workflow.
2. Seeds `rulesets/house/` and `claudeguard.config.json` only if they don't
   already exist — your policy is never clobbered.

Then make it yours:

3. Replace `rulesets/house/` with your team's rules; keep `rulesets/_core/`.
4. Tune `applies_to` globs and trip patterns to your stack (e.g. Bun vs npm,
   Drizzle vs Prisma, Hono vs Express).
5. Set `base` in `claudeguard.config.json` to your integration branch.

## Design principles & non-goals

- **Never edits, stages, or commits.** A gate, not a fixer.
- **Never invents violations** to make a rule look useful. Inert rule → dropped.
- **Evidence-based.** Every violation cites the exact added line.
- **Precise over zealous.** A false `FAIL` erodes trust faster than a missed `LOW`.
- **Deterministic output** so report diffs stay reviewable.

## License

[MIT](LICENSE) © 2026 Beeman
