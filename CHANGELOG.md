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
