---
name: claudeguard-init
description: Scaffold ClaudeGuard into the current project. Vendors the engine (gate skill, core rules, runner scripts) and a policy template (house rules, config, CI workflow) so the gate runs self-contained. Use when the user asks to "set up claudeguard", "add claudeguard to this repo", "claudeguard init", or "install the policy gate".
---

# ClaudeGuard — project bootstrap

This skill installs ClaudeGuard into the **current project** by running the
vendoring installer. It is a thin, DRY wrapper: all copy logic lives in
`scripts/install.ps1` / `scripts/install.sh` (the same scripts a user can run by
hand), so there is one source of truth for what gets scaffolded.

It writes files but **only into the target project**, and never overwrites
existing policy (house rules, config, an existing workflow). It does not touch
the ClaudeGuard engine itself.

## Procedure

### 1. Locate the installer

The engine root is `${CLAUDE_PLUGIN_ROOT}` when ClaudeGuard is installed as a
plugin. The installer scripts live at `${CLAUDE_PLUGIN_ROOT}/scripts/`. If
`${CLAUDE_PLUGIN_ROOT}` is unset (you are inside a cloned engine repo), use
`scripts/` relative to that repo root.

### 2. Run the installer against the current project

Pick the script by OS and run it with the project directory as the target
(default: the current working directory). Pass the engine root through so the
script copies from the right place.

- **Windows / PowerShell:**
  ```powershell
  & "${env:CLAUDE_PLUGIN_ROOT}\scripts\install.ps1" -Target "."
  ```
- **macOS / Linux:**
  ```bash
  CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}" "${CLAUDE_PLUGIN_ROOT}/scripts/install.sh" .
  ```

The installer is idempotent: it refreshes engine files (`.claude/skills/claudeguard/SKILL.md`,
`rulesets/_core/`, `scripts/check.*`) and leaves policy files untouched if they
already exist (`rulesets/house/`, `claudeguard.config.json`, an existing
`.github/workflows/claudeguard.yml`).

### 3. Report what was scaffolded

Relay the installer's output, then state the two manual steps it cannot do for
the user:

1. **Set the base branch** — edit `claudeguard.config.json` and set `base` to the
   project's integration branch (e.g. `origin/dev`, `origin/main`, `origin/master`).
2. **Enable CI** — add the repository secret `ANTHROPIC_API_KEY` so the GitHub
   Actions workflow can run the gate.

Optionally suggest tuning `rulesets/house/` to the project's stack (e.g. Bun vs
npm, Drizzle vs Prisma, Hono vs Express), and offer to run the gate locally with
`scripts/check.sh origin/<base>` (or `scripts/check.ps1 -BaseRef origin/<base>`).

## Hard constraints

- **Only scaffold into the target project.** Never edit the engine.
- **Never overwrite policy.** House rules, config, and an existing workflow are
  the team's; the installer skips them when present. Do not force-copy them.
- **Do not run the gate as part of init** unless the user asks — bootstrapping
  and gating are separate actions.
