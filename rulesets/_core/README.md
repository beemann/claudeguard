# `_core` — universal rulesets

This folder holds **provider-agnostic, universal** best-practice rules that any
project can adopt as-is. It ships intentionally minimal.

`rulesets/house/` holds **this team's** opinionated rules (Docker-only,
measurement-first, …). When you fork ClaudeGuard for another project, you keep
`_core`, swap out `house/`, and override anything via `claudeguard.config.json`.

To add a universal rule, drop a `*.md` here with the same frontmatter shape as
the house rules (`id`, `severity`, `applies_to`, optional `enabled`, optional
`detect` / `exempt` / `exempt_match`) and a body that states what a `FAIL` looks
like and why. The skill engine picks it up with no code change. A rule with
`detect` patterns also needs `fixtures/<id>/should-fail.txt` and
`should-pass.txt`; `scripts/test-rules.sh` fails while they are missing.

**Rules that carry a probe.** Most rules are judged by reading the diff. Some
cannot be: if the evidence is invisible in rendered text, an agent reading
"carefully" produces a confident wrong answer. Such a rule must declare **probes**
— exact read-only commands whose output is the evidence — and SKILL.md then
requires them to be run rather than judged. `no-invisible-characters` is the
worked example, and the reason the mechanism exists: the defect that motivated it
passed this gate by being unreadable.

Two constraints on a probe: it must stay inside the gate's read-only tool set
(`Read`, `Grep`, `Glob`, read-only `git`), or it cannot run headless in CI; and a
probe that does not run makes the rule `UNEVALUATED`, which is **not** a pass.

Keep `_core` rules **uncontroversial** — anything debatable belongs in `house/`.
