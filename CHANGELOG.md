# Changelog

All notable changes to ClaudeGuard are documented here. The version in
[`.claude-plugin/plugin.json`](.claude-plugin/plugin.json) is the cache key for
plugin updates — bump it to ship changes to installed users.

This project adheres to [Semantic Versioning](https://semver.org).

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
