# `_core` — universal rulesets

This folder holds **provider-agnostic, universal** best-practice rules that any
project can adopt as-is. It ships intentionally minimal.

`rulesets/house/` holds **this team's** opinionated rules (Docker-only,
measurement-first, …). When you fork ClaudeGuard for another project, you keep
`_core`, swap out `house/`, and override anything via `claudeguard.config.json`.

To add a universal rule, drop a `*.md` here with the same frontmatter shape as
the house rules (`id`, `severity`, `applies_to`, optional `enabled`) and a body
that states what a `FAIL` looks like and why. The skill engine picks it up with
no code change.

Keep `_core` rules **uncontroversial** — anything debatable belongs in `house/`.
