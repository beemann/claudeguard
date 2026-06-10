---
id: docker-only
severity: high
applies_to:
  - "**/*.sh"
  - "**/*.ps1"
  - "**/Makefile"
  - "**/makefile"
  - "**/*.mk"
  - "**/justfile"
  - "**/Taskfile.yml"
  - "**/Taskfile.yaml"
enabled: true
---

# 100% Docker policy

**FAIL** when the diff adds, to a host-executed automation surface (shell
scripts and task runners — see `applies_to`), a command that runs project
tooling directly instead of inside the container.

Trip on added lines that invoke project tooling directly:

- `npm run …`, `npm install`, `pnpm …`, `yarn …`
- `npx prisma …`, `prisma migrate`, `prisma generate`
- `next dev`, `next build`, `node server.js`
- `python manage.py …`, `pytest`, `uvicorn …`

…**unless** the command is wrapped in `docker compose exec app …` or
`docker compose run …` (those run in-container by design). The `docker …`
commands themselves are never a violation — they are how you reach the
container.

**Why:** the project runs exclusively through Docker. Host-level commands drift
from the container environment, hide "works on my machine" bugs, and break the
reproducibility guarantee.

**Scope note:** this rule deliberately targets only files whose lines *are*
host executions — `*.sh`, `*.ps1`, `Makefile`, `*.mk`, `justfile`, `Taskfile`.
It does **not** scan `package.json` scripts (those run in-container when invoked
via `docker compose exec app npm run …`), CI workflows (the runner legitimately
sets up the host), or documentation/prose. Flagging those produces noise, and a
false `FAIL` erodes the gate faster than a missed `LOW`.

**Suggestion:** prefix with `docker compose exec app `, e.g.
`docker compose exec app npm run build`.

**Exemptions:** host/Docker bootstrap lines — installing Docker itself or the
orchestration commands (`docker compose up`, `docker compose build`) — and any
line explicitly commented as intentional host-side setup.
