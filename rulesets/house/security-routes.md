---
id: security-routes
severity: high
applies_to:
  - "**/routes/**"
  - "**/api/**"
  - "**/controllers/**"
  - "**/pages/api/**"
  - "**/app/api/**"
  - "**/*.route.ts"
  - "**/*.controller.ts"
enabled: true
---

# Security check on every new route

**FAIL** when the diff adds a new HTTP route / endpoint / handler that lacks an
explicit security posture.

A new endpoint must visibly address, in the diff:

- **Auth / authorization** — an auth guard, middleware, session/role check, or
  an explicit, commented decision that the route is intentionally public.
- **Input validation** — request body / params / query validated (Zod,
  class-validator, schema) before use.
- **Injection safety** — no string-concatenated SQL/shell; parameterized
  queries or an ORM.
- **Output safety** — no unescaped user input reflected into HTML (XSS); state-
  changing routes consider CSRF.

Trip when a new route handler is added (e.g. `router.post(`, `app.get(`,
`@Post(`, `export async function POST(`) and none of the above is present in
the same change for that handler.

**Why:** every new path is new attack surface. Auth, validation, and injection
defenses are cheapest to add at creation time.

**Suggestion:** add the auth guard and input schema in the same commit; if the
route is intentionally public/unauthenticated, say so in a comment so the gate
(and future readers) can see it was a decision, not an omission.

Record residual risks in `security_warnings.md`.
