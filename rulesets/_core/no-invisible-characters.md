---
id: no-invisible-characters
severity: high
applies_to:
  - "**/*"
enabled: true
---

# No invisible characters in source

**FAIL** when the diff adds a character that a reviewer cannot see but a machine
acts on:

- **C0 control characters** including **NUL** (`U+0000`–`U+001F` except tab, LF and
  CR, plus `U+007F`).
- **Bidi overrides and isolates** (`U+202A`–`U+202E`, `U+2066`–`U+2069`).
- **Zero-width characters and the BOM** (`U+200B`–`U+200D`, `U+FEFF`).

## Judge this one with the probe, not by reading

**You cannot see these characters in the diff, and neither can the model reading
it.** That is the entire defect class, and it is why this rule ships with
deterministic probes instead of a judgement. Run them; report exactly what they
print. Reading the diff and concluding "looks clean" is not evaluating this rule.

Two probes are required, because **neither one alone can see the whole class**.
Both stay inside this gate's read-only tool whitelist, so they also run headless
in CI.

**Probe A — the binary tell (catches NUL and other C0 controls).** `git` marks a
file holding one as binary, so its numstat row carries `-` `-` instead of line
counts:

```bash
git diff --merge-base <base> --numstat
```

Every row whose added and deleted columns are both `-` is a candidate. One
caveat that is not a violation: if the file is binary on the **old** side only
and the change removes the byte, that row is the fix landing, not the defect —
confirm with probe B, which will be silent.

**Probe B — the textual class (catches bidi overrides, zero-width, BOM).** Use the
`Grep` tool (ripgrep) over the changed files with this pattern:

```
[\x{0000}-\x{0008}\x{000B}\x{000C}\x{000E}-\x{001F}\x{007F}\x{202A}-\x{202E}\x{2066}-\x{2069}\x{200B}-\x{200D}\x{FEFF}]
```

**Why both, measured rather than assumed:** ripgrep *skips binary files*, so probe
B cannot see a NUL — the very byte that makes a file binary. Probe A sees exactly
that case and nothing else, because bidi and zero-width characters keep a file
textual. Each covers the other's blind spot; running only one is a silent gap.

Each hit is one violation: cite the file and line, and name the code point
(`U+0000`, `U+202E`, …) rather than pasting the character.

If neither probe can run, this rule is **`UNEVALUATED`**, not clean — say so.

**Why:** a single NUL byte makes `git` classify the whole file as binary — no
reviewable diff, no `git blame` — so every later change to that file ships
unreviewed. Bidi overrides are the Trojan Source class (CVE-2021-42574): the code a
reviewer reads is not the code that compiles. Both defeat review itself, which is
what makes them worse than an ordinary bug: nothing downstream will catch what
review stopped being able to see.

This is not hypothetical. The defect that produced this rule was a raw NUL inside a
template literal, and it reached a merged commit after passing lint, the formatter,
the type-checker, a full test suite **and this gate** — every one of which reads the
file as text, where a NUL is legal text.

**Suggestion:** write the character as its escape sequence instead (the six ASCII
characters that spell a zero-width space, never the character itself). The runtime
string is identical and the source becomes reviewable. Test fixtures for concealment
detectors are not an exception; they are the *most* important place to use escapes,
because a reviewer there cannot otherwise tell what is being tested.

**Exemptions:** none in source, docs, or config. Genuinely binary assets (images,
fonts, `.wasm`, compiled artefacts) are out of scope — they are not reviewed as
text and are excluded by extension, not waived case by case.

**Related:** this rule catches the defect in a *diff*. Its deterministic whole-tree
twin is the `source-encoding` check in
[ClaudeGuard Integrity](https://github.com/beemann/claudeguard-integrity), which
re-scans everything on every run and so catches what predates the diff.
