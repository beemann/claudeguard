---
id: no-any
severity: medium
applies_to:
  - "**/*.ts"
  - "**/*.tsx"
enabled: true
---

# No `any`, no silent escape hatches

**FAIL** when the diff adds an explicit `any` type or a type-safety escape
hatch in TypeScript.

Trip on added lines containing:

- `: any`, `as any`, `<any>`
- `any[]`, `Array<any>`, `Record<string, any>`
- `// @ts-ignore` and `// @ts-nocheck`
- `@typescript-eslint/no-explicit-any` disable comments

**Why:** `any` disables the type checker exactly where bugs hide — at
boundaries and on untrusted input. "Explicit is King": prefer `unknown` plus a
narrowing guard, a real interface, or a generic.

**Suggestion:** replace `any` with `unknown` + a type guard, a precise
interface, or a generic parameter. For genuinely dynamic shapes use `unknown`
and validate (e.g. Zod) before use.

**Exemptions:** `*.d.ts` ambient declarations wrapping untyped third-party code,
and generated files. A `// @ts-expect-error` with an adjacent explanation is
acceptable where a fix is genuinely out of scope.
