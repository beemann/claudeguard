# Changelog

All notable changes to ClaudeGuard are documented here. The version in
[`.claude-plugin/plugin.json`](.claude-plugin/plugin.json) is the cache key for
plugin updates — bump it to ship changes to installed users.

This project adheres to [Semantic Versioning](https://semver.org).

## 0.4.0

Make the deterministic layer do what the documentation says it does, and make the
runners, the CI workflow and the installer agree with the skill. Every defect below
was reproduced before it was changed.

### Changed — affects rule authors
- **`exempt_match`: an exemption that excuses only the match it overlaps.** `exempt`
  drops the whole line, which is right for context (wrapped in `docker compose
  exec`, a comment) and wrong for values: in `no-secrets`, the line
  `process.env.API_KEY || "sk-ant-…"` matched the exemption `process[.]env`, so the
  literal beside it never reached adjudication. `no-secrets` now lists its dummies
  and environment references under `exempt_match`. `exempt` keeps its meaning, so
  existing rules behave as before.
- **The candidate procedure runs as written.** The documented
  `git diff | grep -iE '<detect>'` kept the diff's leading `+` — an anchored pattern
  such as `^<<<<<<< ` could never match — and searched removed and context lines
  too. SKILL.md step 5 now builds candidates with `git grep -n --column -o` on
  `HEAD`, restricted to the added lines of `git diff -U0`, one command per detect
  pattern, and the report lists every candidate it dismissed (`dismissed`).
- **The diff range is `<base>...HEAD`.** `git diff --merge-base <base>` compares with
  the working tree, so uncommitted edits were gated although they are not what
  merges.

### Fixed
- **The runners did not have the tool set SKILL.md described.** 0.3.0 referred to a
  read-only tool whitelist; `check.sh` and `check.ps1` still ran
  `--permission-mode plan`. They now pass `--permission-mode dontAsk` with explicit
  `--allowed-tools` (`Read`, `Grep`, `Glob`, `git diff|grep|log|merge-base|rev-parse`)
  and remove `Edit`, `Write` and `NotebookEdit`.
- **An infrastructure failure read as a policy FAIL.** When the `claude` CLI exited
  non-zero (auth, credit, network), `check.sh` exited 1 — the code for `FAIL`. It
  now exits 2 and says no verdict was produced; the workflow names the difference.
- **`base` in `claudeguard.config.json` was read by nothing**, although the installer
  and the README told users to set it. Both runners now default to it (argument >
  config > `origin/main`) and exit 2 on a base that does not resolve or has no merge
  base with `HEAD`.
- **`no-any` missed conditions its own body lists** — `Map<K, any>`, `<T = any>`,
  `type X = any`, `string | any`, `() => any` and the `no-explicit-any` disable
  comment. Only candidates are adjudicated, so those lines were never looked at.
  Patterns and fixtures added.
- **`no-invisible-characters` probe B saw 2 of 13 invisible classes**, measured with
  ripgrep on byte-generated samples. Its pattern is now the Unicode definition the
  integrity engine uses (`\p{Cc}`, `\p{Cf}`, `\p{Zl}`, `\p{Zp}`,
  `Default_Ignorable_Code_Point`, minus tab, LF, CR, `U+FE0E`, `U+FE0F`): 11 of 13,
  the other two by design (NUL is probe A's; a leading BOM is stripped by ripgrep,
  named in the rule). A hit on a line the change did not add is `info`.
- **The report could republish a secret.** "Quote the exact added line" applied to
  credentials too, and the report is posted as a PR comment. SKILL.md and
  `no-secrets` now require prefix and length instead.
- **Rule harness.** Tolerates CRLF instead of only detecting it; fails when a rule
  with `detect` has no fixtures, when fixtures name no rule, and on an invalid
  pattern (grep's exit 2 used to read as "no match"); runs on bash 3.2, the macOS
  default (`mapfile` is bash 4). `test-rules.ps1` gained the "tested nothing" guard
  `test-rules.sh` got in 0.3.0, and translates POSIX bracket classes such as
  `[[:space:]]`, which .NET regex reads as literal characters.
- **CI workflow.** Actions on Node 24 (`checkout@v7`, `setup-node@v7`,
  `github-script@v9` — the Node 20 versions were deprecated and their runtime left
  the runners on 2026-09-16); Node 24 instead of end-of-life Node 20; Claude Code
  CLI pinned to `2.1.309`; `persist-credentials: false`; `base_ref` passed through
  `env`; the runner invoked through `bash`, because a commit made on Windows does
  not record the executable bit; the PR comment best-effort; and a new `rules` job
  that runs `scripts/test-rules.sh` without an API key.
- **Installer** vendors `scripts/test-rules.*` and fixtures — the README told users
  to run a harness they did not have. House-rule fixtures are seeded only together
  with the house rules they test.
- **`claudeguard-init`** runs the installer through `bash` and
  `powershell -ExecutionPolicy Bypass`: `install.sh` is not executable on `main`
  0.2.0, and the default Windows policy refuses `.ps1` files.
- **`docker-only`** reads git hooks (`.githooks/`, `.husky/`). A hook has no
  extension, so the extension list never saw the file that runs on every push.
- **`claudeguard.config.example.json`**: `$schema` held a sentence, which editors
  try to load as a schema URL; renamed `$comment`.
- **README** brought up to date, including a security model: what the gate is and
  is not robust against.
- **CHANGELOG order** — 0.3.0 had been appended below 0.1.0.

### Upgrading
- Plugin: `/plugin update`. Vendored copy: re-run the installer. It keeps your house
  rules, config and workflow, so compare your workflow with the shipped one (the
  `rules` job, the action versions, `bash scripts/check.sh`) by hand.
- A house rule with `detect` patterns and no `fixtures/<id>/` now fails
  `scripts/test-rules.sh`. Add fixtures.
- If an `exempt` entry of yours excuses a *value* rather than a line, move it to
  `exempt_match`.

## 0.3.0

_Merged to `dev` on 2026-08-02 and never released on `main`; installed users
receive these changes with 0.4.0._

Close the gap a statistical gate leaves open: make "could not check" a state of its
own, and stop a Windows checkout from silently disabling the rule harness.

### Added
- **Probes, and a fourth verdict state.** A rule may declare read-only commands whose
  *output* is the evidence. Some defect classes are invisible in rendered text, and an
  agent reading "carefully" produces a confident wrong answer. When a declared probe
  cannot run, the rule is **`UNEVALUATED`** — never green, never counted toward `PASS`.
  A gate that reports clean because it stopped being able to check is worse than no
  gate: the report looks identical to a real pass.
- **`no-invisible-characters`** (`_core`) — C0 controls incl. NUL, bidi overrides and
  isolates, zero-width, BOM. Ships two probes, because neither sees the whole class:
  ripgrep skips binary files so it cannot see a NUL, and `git diff --numstat` catches
  exactly that case but nothing that keeps a file textual.
- **Fixed marker semantics.** Four states, four colours, and red means a problem and
  nothing else — an inert rule is grey, never a red X. Someone who only glances at the
  icons must come away correct.

### Fixed
- **`.gitattributes`** — without it a Windows checkout produced CRLF shell scripts that
  bash refuses outright (`set: pipefail: invalid option name`). The scripts are the
  gate's entry point, so this read as a broken tool rather than a broken checkout.
- **`scripts/test-rules.sh` now fails when it tested nothing.** Under those same CRLF
  endings the frontmatter parser matched no `---`, every rule was classified
  judgment-only, and the harness reported `0 rule(s) tested` and exited **0**. The
  guard against silent-green now guards itself.
- **The CI workflow no longer `chmod`s before the gate runs.** The executable bit is
  committed (100755) instead. Mutating the tree before the gate reads it makes the
  gate judge a diff that is not the pull request's — it surfaces as a phantom
  mode-only entry for the very file being chmod-ed.

## 0.2.0

Strengthen the core: push determinism down toward the rules.

### Added
- **Deterministic candidate detection (`detect`/`exempt`).** Pattern rules can now
  carry optional `detect` (and `exempt`) regex lists in their frontmatter. Detection
  becomes reproducible — a real hit can't be silently missed — while the LLM's job
  shrinks to *adjudicating* the bounded candidate set (applying the prose exemptions
  a regex can't decide). Shipped for `no-secrets`, `no-conflict-markers`, `no-any`;
  other rules stay judgment-only. Backward compatible (the fields are optional).
- **Testable rules.** `fixtures/<rule-id>/{should-fail,should-pass}.txt` plus
  `scripts/test-rules.{sh,ps1}` assert each rule's `detect`/`exempt` patterns —
  **no LLM, no API key** — so the deterministic layer is regression-tested for free.
- **Machine verdict sentinel.** The skill now ends with a `claudeguard-verdict: …`
  line; the runner reads that instead of scraping the verdict out of prose,
  eliminating the parser-fragility class (the JSON block remains a fallback).

## 0.1.1

### Fixed
- **Headless gate stalling in plan mode.** Under the current Claude Code CLI, a
  `--permission-mode plan` run could pause to request `ExitPlanMode` approval
  instead of emitting the verdict — so CI got no report and failed even on a clean
  diff (the runner parsed `UNKNOWN` → exit 2). The runner prompts (`check.ps1`,
  `check.sh`) and `SKILL.md` now state explicitly that this is a read-only audit:
  do not call `ExitPlanMode` or ask for approval; emit the verdict report
  directly. Surfaced by ClaudeGuard gating its own release PR.

## 0.1.0

Initial packaged release.

### Added
- **Claude Code plugin packaging.** `.claude-plugin/plugin.json` and a
  self-referential `.claude-plugin/marketplace.json` make ClaudeGuard installable
  via `/plugin marketplace add beemann/claudeguard` → `/plugin install claudeguard`.
- **`claudeguard-init` skill.** Bootstraps the gate into the current project by
  running the vendoring installer.
- **Standalone installer.** `scripts/install.ps1` and `scripts/install.sh` vendor
  the engine + a policy template into any repo, self-contained for CI with no
  plugin dependency. Idempotent: refreshes engine files, never clobbers policy.

### Changed
- **Dual-root ruleset resolution.** The gate now resolves `_core` rules from the
  plugin engine root (`${CLAUDE_PLUGIN_ROOT}`) when installed as a plugin, and
  `house` rules from the project, deduping by `id` with the project winning. This
  cleanly separates the shipped engine from per-project policy while keeping the
  vendored and self-test modes working unchanged.

### Fixed
- **`check.sh` verdict parser.** The POSIX runner anchored the verdict extraction
  with `[A-Z]+$`, which never matched because the JSON line ends in `"` — so every
  non-empty diff parsed as `UNKNOWN` and exited 2, failing CI even on a `PASS`.
  Now extracts the quoted value with `sed`. (The PowerShell runner was unaffected.)
  Caught by the first real CI run on a consumer repo.
