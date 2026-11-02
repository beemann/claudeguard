---
id: no-invisible-characters
severity: high
applies_to:
  - "**/*"
enabled: true
---

# No invisible characters in source

**FAIL** when the diff adds a character that a reviewer cannot see but a machine
acts on. The class is defined by Unicode, not by a hand-written list:

- **Controls** — C0 and C1 (`\p{Cc}`), including **NUL**; tab, LF and CR excepted.
- **Format characters** (`\p{Cf}`) — bidi overrides, isolates and marks
  (`U+202A`–`U+202E`, `U+2066`–`U+2069`, `U+200E`/`U+200F`, `U+061C`), zero-width
  characters, the word joiner and invisible operators (`U+2060`–`U+2064`), the BOM,
  the soft hyphen, and the Tags block (`U+E0000`–`U+E007F`).
- **Line and paragraph separators** (`U+2028`, `U+2029`) — a line break for the
  parser, not for the diff.
- **Default-ignorable code points** — what the categories miss: variation
  selectors, Hangul fillers, the unassigned tails of the Tags and selector planes.
  `U+FE0E`/`U+FE0F` (text/emoji presentation) are excepted; the other selectors are
  a documented smuggling alphabet.

This is the Unicode definition the `source-encoding` check of
[ClaudeGuard Integrity](https://github.com/beemann/claudeguard-integrity) starts
from (before any per-extension allowance a project configures there), so the diff
gate and the whole-tree gate agree on what counts.

## Judge this one with the probes, not by reading

**You cannot see these characters in the diff, and neither can the model reading
it.** That is the entire defect class, and it is why this rule ships with
deterministic probes instead of a judgement. Run them; report exactly what they
print. Reading the diff and concluding "looks clean" is not evaluating this rule.

Two probes are required, because **neither one alone can see the whole class**.
Both stay inside this gate's read-only tool set, so they also run headless in CI.

**Probe A — the binary tell (catches NUL and other controls git treats as
binary).** `git` marks a file holding one as binary, so its numstat row carries
`-` `-` instead of line counts:

```bash
git diff <base>...HEAD --numstat
```

Every row whose added and deleted columns are both `-` is a candidate. One
caveat that is not a violation: if the file is binary on the **old** side only
and the change removes the byte, that row is the fix landing, not the defect —
confirm with probe B, which will be silent.

**Probe B — the textual class.** Use the `Grep` tool (ripgrep) over each changed
file, with line numbers, and this pattern:

```
[\p{Cc}\p{Cf}\p{Zl}\p{Zp}\p{Default_Ignorable_Code_Point}&&[^\t\n\r\x{FE0E}\x{FE0F}]]
```

**Why both, measured rather than assumed:** ripgrep *skips binary files*, so probe
B cannot see a NUL — the very byte that makes a file binary. Probe A sees exactly
that case and nothing else, because bidi and zero-width characters keep a file
textual. Each covers the other's blind spot; running only one is a silent gap.
Measured against probe B: the pattern above reports 11 of 13 invisible classes
(C1, LRM, RLO, ALM, ZWSP, word joiner, soft hyphen, line separator, Tag character,
variation selector, Hangul filler) and none of Czech diacritics, a non-breaking
space, an em dash, an emoji or an emoji with `U+FE0F`; the hand-written range list
this rule used before 0.4.0 reported 2 of the 13.

**Residual, named rather than solved:** ripgrep strips a UTF-8 BOM at byte 0
before matching, so a **leading** BOM is invisible to probe B (a BOM anywhere else
is reported). The whole-tree `source-encoding` check reads bytes and catches it.

Each hit on a line the diff **adds** is one violation: cite the file and line, and
name the code point (`U+0000`, `U+202E`, …) rather than pasting the character. A
hit on a line the diff did not add is pre-existing — report it as `info`, not as a
violation of this change.

If neither probe can run, this rule is **`UNEVALUATED`**, not clean — say so.

**Why:** a single NUL byte makes `git` classify the whole file as binary — no
reviewable diff, no `git blame` — so every later change to that file ships
unreviewed. Bidi overrides are the Trojan Source class (CVE-2021-42574): the code a
reviewer reads is not the code that compiles. Tag characters and variation
selectors carry whole instructions to a model while rendering as nothing. All of
them defeat review itself, which is what makes them worse than an ordinary bug:
nothing downstream will catch what review stopped being able to see.

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
