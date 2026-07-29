# Changelog

All notable changes to ClaudeGuard are documented here. The version in
[`.claude-plugin/plugin.json`](.claude-plugin/plugin.json) is the cache key for
plugin updates — bump it to ship changes to installed users.

This project adheres to [Semantic Versioning](https://semver.org).

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

## 0.3.0

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
