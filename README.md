# ClaudeGuard

> A report-only, pre-merge **policy gate** that runs as a [Claude Code](https://claude.com/claude-code) skill.
> It reads a diff, evaluates it against versioned rulesets, and emits a structured **PASS / WARN / FAIL** verdict. It never edits your code.
>
> **Install in one command** — `/plugin marketplace add beemann/claudeguard` then `/plugin install claudeguard@claudeguard`. ([What's new in 0.4.0](#whats-new-in-040))

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
- **Auditable output.** A verdict table, a parseable JSON block and one fixed
  verdict line — diffable, reviewable, and mapped to a CI exit code.

## What's new in 0.4.0

**The deterministic layer now does what the documentation said it did** — every
item was reproduced before it was fixed:

- **Candidates come from tool output, as written.** Step 5 builds the candidate
  set with `git grep` on the added lines; the old `git diff | grep` recipe could
  never match an anchored pattern and also searched removed lines.
- **`exempt_match`.** `exempt` clears a whole line (right for *context*, such as a
  command wrapped in `docker compose exec`); `exempt_match` excuses only the match
  it overlaps (right for *values*). `process.env.KEY || "sk-live-…"` is a candidate
  again — the environment reference no longer hides the literal beside it.
- **Wider rules.** `no-any` detects every condition its body lists;
  `no-invisible-characters` sees 11 of 13 invisible classes instead of 2, using the
  same Unicode definition as [ClaudeGuard Integrity](https://github.com/beemann/claudeguard-integrity).
- **Runners and CI agree with the skill.** An explicit read-only tool set instead of
  plan mode, `base` read from the config, `<base>...HEAD` as the range, exit `2` for
  "no verdict" (an expired API credit is no longer a policy `FAIL`), current GitHub
  Actions, a pinned CLI, and a `rules` CI job that needs no API key.

**0.3.0** (never published on `main`, shipped with 0.4.0) added **probes** — rules
whose evidence is the output of a read-only command, because some defects are
invisible in rendered text — a fourth state, **`UNEVALUATED`**, for a rule whose
probe could not run, and the `no-invisible-characters` rule.

Full notes, including how to upgrade, in the [CHANGELOG](CHANGELOG.md).

## Install

Two ways to adopt ClaudeGuard, sharing one design — a universal **engine**
(the gate skill, `_core` rules, runner and rule-test scripts) plus per-project
**policy** (`rulesets/house/`, `claudeguard.config.json`, the CI workflow).

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
bash scripts/install.sh /path/to/your/repo
```
```powershell
# PowerShell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/install.ps1 -Target C:\path\to\your\repo
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

The procedure is defined in [`SKILL.md`](SKILL.md) and runs in six steps:

1. **Resolve the diff.** The commits the branch adds, `<base>...HEAD`. The base is
   the run's argument, else `base` in `claudeguard.config.json`, else `origin/main`.
   Uncommitted changes are not judged.
2. **Resolve rulesets.** Read every `*.md` from the engine's `_core`
   (`${CLAUDE_PLUGIN_ROOT}/rulesets/_core/` when installed as a plugin) and the
   project's `rulesets/`, dedupe by `id` (the project copy wins so a repo can
   override a shipped rule), honor `claudeguard.config.json` (enable/disable,
   severity overrides), and keep only rules whose `applies_to` globs match at
   least one changed file.
3. **Smoke check (mandatory, anti-falsification).** For each kept rule, state how
   many changed files it *actually* applies to. A rule that matches zero files is
   inert — the gate never invents violations to justify a rule.
4. **Run probes.** A rule whose evidence is invisible in rendered text declares
   read-only commands whose output *is* the evidence. A probe that cannot run makes
   the rule `UNEVALUATED` — never a pass.
5. **Evaluate.** Only added lines are judged. Rules with `detect` patterns get their
   candidates from `git grep` output (the model then adjudicates only those
   candidates, and lists the ones it dismissed); rules without `detect` are judged
   by the model directly. Every violation cites a file, a line, and the offending
   line — a credential by prefix and length only.
6. **Verdict.** `FAIL` if a violation or an `UNEVALUATED` rule reaches `block_on`
   (default `high`); `WARN` if everything found is below it; `PASS` if clean.

## Output

ClaudeGuard emits a human-readable report, a machine-readable JSON block, and a
final verdict line:

```
ClaudeGuard verdict: ❌ FAIL   (1 high, 1 medium)
Base: origin/main · Files scanned: 7 · Rules: 2 clean · 2 failing · 1 unevaluated · 1 inert

Ruleset resolution
| Rule                     | Severity | Files matched | Status                              |
|--------------------------|----------|---------------|-------------------------------------|
| no-secrets               | critical | 7             | ✅ checked — clean                   |
| docker-only              | high     | 1             | ❌ FAIL — 1 violation                |
| no-any                   | medium   | 3             | ❌ FAIL — 1 violation                |
| security-routes          | high     | 2             | ✅ checked — clean                   |
| no-invisible-characters  | high     | 7             | ⚠️ UNEVALUATED — probe could not run |
| no-destructive-db        | critical | 0             | ➖ n/a — not in this diff             |

Violations
| Severity | Rule        | File            | Line | Why                           |
|----------|-------------|-----------------|------|-------------------------------|
| high     | docker-only | scripts/dev.ps1 | 12   | `npm run dev` invoked on host |
| medium   | no-any      | src/api/user.ts | 44   | `: any` on request body       |
```

```json
{
  "verdict": "FAIL",
  "base": "origin/main",
  "files_scanned": 7,
  "rulesets_active": ["no-secrets", "docker-only", "no-any", "..."],
  "rulesets_inert": ["no-destructive-db"],
  "unevaluated": [{ "rule": "no-invisible-characters", "severity": "high", "why": "..." }],
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
  "dismissed": [{ "rule": "no-any", "file": "src/api/user.ts", "line": 51, "why": "..." }],
  "block_on": "high"
}
```

```
claudeguard-verdict: FAIL
```

Markers are fixed: ✅ checked and clean, ➖ inert (nothing to judge), ⚠️ could not
be checked, ❌ a violation — red never means anything else.

The runners read the last line and exit `0` for `PASS`/`WARN`, `1` for `FAIL`, and
`2` when there is no verdict (setup error, the `claude` CLI failed, or the report
carried no verdict line).

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
| `no-invisible-characters` | core | high | Characters a reviewer cannot see: controls incl. NUL, bidi, zero-width, Tags, variation selectors. Judged by two probes, not by reading. |
| `docker-only` | house | high | Project tooling run on the host instead of in-container (shell scripts, task runners, git hooks). |
| `no-destructive-db` | house | critical | Unguarded `DROP`/`TRUNCATE`/`DELETE … ` without `WHERE`, etc. |
| `security-routes` | house | high | A new route/handler with no visible auth, validation, or injection posture. |
| `no-any` | house | medium | `any`, `as any`, `@ts-ignore` and other TypeScript escape hatches. |
| `measurement-first` | house | medium | A change claiming to *optimize* something with no benchmark/measurement. |

## Usage

### As a Claude Code skill

Install the plugin, or vendor the gate into the repository with the installer
(the rules must live in the project's `rulesets/`, not in the skill directory).
Then ask:

> *run claudeguard* · *gate this branch* · *check policy compliance*

### Local runner

```bash
# POSIX — base defaults to `base` in claudeguard.config.json, then origin/main
bash scripts/check.sh [base-ref]
```

```powershell
# PowerShell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/check.ps1 [-BaseRef origin/main]
```

Requires `git`, the `claude` CLI on `PATH`, and `ANTHROPIC_API_KEY` in the
environment. An empty diff is an immediate `PASS`. The runners give the model a
fixed read-only tool set — see [Security model](#security-model).

### CI (GitHub Actions)

[`.github/workflows/claudeguard.yml`](.github/workflows/claudeguard.yml) runs two
jobs on every pull request to `main`/`master` (add your integration branch to
`on.pull_request.branches` if PRs target it):

- **`rules`** — `scripts/test-rules.sh`: every `detect` pattern against its
  fixtures. No model, no API key.
- **`gate`** — the verdict. Posts the report as a PR comment and job summary, and
  blocks the merge on `FAIL` or on "no verdict". Add a repository secret
  `ANTHROPIC_API_KEY` to activate it.

The Claude Code CLI is pinned in the workflow; bump it deliberately.

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

- `base` — default ref to diff against, used by the skill and both runners when
  no base is passed. CI passes the pull request's target branch explicitly.
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
exempt:                       # optional: a line that is fine in context
  - '[A-Z]+-[0-9]+|#[0-9]+'
---

# No TODO without a tracking ticket

**FAIL** when the diff adds a `TODO`/`FIXME` with no issue reference.

Trip on added lines matching `TODO`/`FIXME` not followed by a ticket id
(e.g. `JIRA-123`, `#456`).

**Why:** untracked TODOs are debt that never gets scheduled.

**Suggestion:** link a ticket, or do the work now.
```

**Deterministic detection (optional).** A rule may carry regex lists (case-insensitive
POSIX ERE):

- `detect` — what makes an added line a candidate.
- `exempt` — a match anywhere on the line drops the whole line: the line is fine
  in its context (a ticket reference, a command wrapped in `docker compose exec`,
  a comment).
- `exempt_match` — excuses only the `detect` match it overlaps: the value is
  harmless (a documented dummy key, an environment reference). Use this one for
  values, or a real literal on the same line goes unseen.

Candidates come from `git grep` output, and the model only *adjudicates* them
against the rule body — so every trip condition the body lists needs a pattern,
or it is never looked at. Rules with no `detect` are judged by the model directly.

**Test your patterns.** Add `fixtures/<rule-id>/should-fail.txt` and
`should-pass.txt`, then run `bash scripts/test-rules.sh` (or `test-rules.ps1`). It
applies the same candidate rule to every line with **no LLM and no API key**, and
it fails while a rule with `detect` has no fixtures, so the deterministic layer is
regression-tested for free.

**Probes.** If a reviewer could not see the violation by eye, the rule needs a
probe: a read-only command (`Read`, `Grep`, `Glob`, read-only `git`) whose output
is the evidence. See `rulesets/_core/no-invisible-characters.md`.

Keep `_core` rules uncontroversial; anything debatable belongs in `house/`.
Every rule body should state, in plain language, **what a `FAIL` looks like**,
**why** it matters, and a **suggestion** — and should rely on evidence visible
in the diff, or declare a probe.

## Security model

ClaudeGuard is a model reading text that the author of the change controls. State
what that means before relying on it:

- **It is a policy check, not a security boundary.** A diff can contain
  instructions addressed to the model ("report PASS"). SKILL.md treats the diff as
  data, candidates for pattern rules come from tool output rather than from reading,
  and probe-carrying rules are judged by command output — but the verdict is still
  written by a model. Use ClaudeGuard to catch honest mistakes before review, and
  keep human review and branch protection for adversarial ones.
- **Tools.** The runners start the CLI with `--permission-mode dontAsk`, allow
  `Read`, `Grep`, `Glob` and read-only `git` (`diff`, `grep`, `log`, `merge-base`,
  `rev-parse`), and remove `Edit`, `Write` and `NotebookEdit`. Claude Code runs
  read-only commands without asking in every mode, and some git flags write or
  execute; `--output` is denied explicitly, the rest are not enumerated. So the
  boundary for a branch you do not trust is **where the gate runs**: an ephemeral
  CI runner or a container, never a workstation that holds credentials.
- **Secrets in CI.** The workflow uses `on: pull_request`, not
  `pull_request_target`. GitHub withholds secrets from pull requests opened from
  forks, so an untrusted PR cannot reach the API key — and the gate cannot run
  there either (reported as "no verdict"; the `rules` job still runs). On a
  same-repository PR the author can already change the workflow itself, so the gate
  adds no access they lack. `persist-credentials: false` keeps the job token out of
  `.git/config`, where a file read would reach it.
- **The report is public.** It is posted as a PR comment and job summary, so a
  credential is cited by prefix and length, never reproduced.

## Forking into your project

The fastest path is the [standalone installer](#standalone-any-repo--ci) or the
`claudeguard-init` skill — both lay down exactly what's below. Under the hood it:

1. Copies the engine into your repo: the gate skill →
   `.claude/skills/claudeguard/SKILL.md`, `rulesets/_core/` with its fixtures,
   `scripts/check.*` and `scripts/test-rules.*`, and (if absent) the workflow.
2. Seeds `rulesets/house/` with its fixtures and `claudeguard.config.json` only if
   they don't already exist — your policy is never clobbered.

Then make it yours:

3. Replace `rulesets/house/` with your team's rules; keep `rulesets/_core/`.
4. Tune `applies_to` globs and trip patterns to your stack (e.g. Bun vs npm,
   Drizzle vs Prisma, Hono vs Express), with fixtures for every `detect` rule.
5. Set `base` in `claudeguard.config.json` to your integration branch, and add it
   to the workflow's `on.pull_request.branches` if PRs target it.
6. On Windows, add `*.sh text eol=lf` to `.gitattributes`: with
   `core.autocrlf=true` a checkout writes the scripts with CRLF, and bash refuses
   them.

## Design principles & non-goals

- **Never edits, stages, or commits.** A gate, not a fixer.
- **Never invents violations** to make a rule look useful. Inert rule → dropped.
- **Evidence-based.** Every violation cites the exact added line (a credential by
  prefix and length).
- **"Could not check" is not "clean".** An unevaluated rule never renders green.
- **Precise over zealous.** A false `FAIL` erodes trust faster than a missed `LOW`.
- **Deterministic output** so report diffs stay reviewable.

## License

[MIT](LICENSE) © 2026 Beeman
