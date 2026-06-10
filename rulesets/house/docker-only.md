---
id: docker-only
severity: high
applies_to:
  - "**/*.ps1"
  - "**/*.sh"
  - "**/package.json"
  - "**/Makefile"
  - "**/*.yml"
  - "**/*.yaml"
  - "**/*.md"
enabled: true
---

# 100% Docker policy

**FAIL** when the diff introduces a command meant to run on the host instead of
inside the container.

Trip on added lines that invoke project tooling directly:

- `npm run …`, `npm install`, `pnpm …`, `yarn …`
- `npx prisma …`, `prisma migrate`, `prisma generate`
- `next dev`, `next build`, `node server.js`
- `python manage.py …`, `pytest`, `uvicorn …`

…**unless** the command is wrapped in `docker compose exec app …`,
`docker compose run …`, or appears inside a `Dockerfile` / a `docker compose`
service definition (those run in-container by design).

**Why:** the project runs exclusively through Docker. Host-level commands drift
from the container environment, hide "works on my machine" bugs, and break the
reproducibility guarantee.

**Suggestion:** prefix with `docker compose exec app `, e.g.
`docker compose exec app npm run build`.

**Exemptions:** CI workflow steps that set up Docker itself, and documentation
explicitly labelled as host-side bootstrap.
