---
id: no-destructive-db
severity: critical
applies_to:
  - "**/migrations/**"
  - "**/*.sql"
  - "**/prisma/**"
  - "**/seeds/**"
  - "**/*.migration.ts"
enabled: true
---

# No unguarded destructive DB operations

**FAIL** when the diff introduces a destructive database operation without an
explicit, visible safeguard.

Trip on added lines containing irreversible data/schema loss:

- `DROP TABLE`, `DROP COLUMN`, `DROP DATABASE`, `DROP SCHEMA`
- `TRUNCATE`
- `DELETE FROM …` without a `WHERE` clause
- `UPDATE …` without a `WHERE` clause
- Prisma: `migrate reset`, `--force-reset`, `db push --accept-data-loss`

**Why:** production data loss is unrecoverable. The project rule is: no
destructive DB operations without explicit human sign-off, and prefer soft
delete.

A change passes only if the destructive operation is clearly guarded:

- Soft delete (`deleted_at` / status flag) used instead of hard `DELETE`.
- A reversible, reviewed migration with an explicit approval marker in the diff
  (e.g. a comment `-- APPROVED-DESTRUCTIVE: <reason/ticket>`).
- The statement is scoped to ephemeral/test data only and labelled as such.

**Suggestion:** prefer soft delete; if a destructive migration is truly
required, scope it with `WHERE`, make it reversible, and add the explicit
approval marker so the gate records that a human signed off.
