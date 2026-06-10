---
id: no-secrets
severity: critical
applies_to:
  - "**/*"
enabled: true
---

# No hardcoded secrets

**FAIL** when the diff adds a credential, key, or token as a literal value.

Trip on added lines containing a recognizable secret:

- **Provider key prefixes:** AWS `AKIA…`/`ASIA…`, GitHub
  `ghp_…`/`gho_…`/`ghu_…`/`ghs_…`/`github_pat_…`, OpenAI/Anthropic
  `sk-…`/`sk-ant-…`, Slack `xox[baprs]-…`, Google API `AIza…`, Stripe
  `sk_live_…`/`rk_live_…`, SendGrid `SG.…`, npm `npm_…`.
- **Private keys:** a `-----BEGIN (RSA|EC|OPENSSH|PGP)? ?PRIVATE KEY-----` block.
- **Secret assignments:** an identifier matching
  `password|passwd|secret|api[_-]?key|access[_-]?token|auth[_-]?token|client[_-]?secret`
  assigned a non-empty, non-placeholder string literal (e.g.
  `DB_PASSWORD = "S3cr3t!"`), including a connection string with inline
  credentials (`postgres://user:pass@host`).
- A committed `.env` (not `.env.example`) carrying real values.

**Why:** a leaked credential is unrecoverable — once pushed it must be *rotated*,
not just deleted, because history, forks, and mirrors retain it. The moment
before merge is the only cheap place to catch it.

**Suggestion:** move the value to an environment variable / secrets manager and
reference it by name; commit only a `.env.example` with placeholder values.
Rotate any key that already reached a commit.

**Exemptions:** placeholders and well-known dummies (`your-api-key-here`,
`xxxxxxxx`, `changeme`, `AKIAIOSFODNN7EXAMPLE`); test fixtures clearly using fake
values; lockfiles (`package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`,
`Cargo.lock`, `poetry.lock`) whose long strings are integrity digests, not
secrets. Quote the exact literal as evidence; never quote the full secret if it
is real — cite enough to identify it (prefix + length).
