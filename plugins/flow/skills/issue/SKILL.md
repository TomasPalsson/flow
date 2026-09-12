---
name: issue
description: "Park an out-of-scope problem as a specable issue instead of fixing it inline or losing it. Files it as a GitHub issue when gh is available (asks first), otherwise appends to .specs/ISSUES.md — either way with the five fields /flow:spec's speccability guard demands, so the issue can become a spec later without a re-investigation. Triggers: /flow:issue, \"file that as an issue\", \"park that\", \"not in scope, record it\", \"open an issue for that\", and any time you flag a real defect while building something else. Not for a bug you are fixing now (that is /flow:fix) and not for a decision inside the current feature (that is a NOTES.md Ruling)."
argument-hint: "<the problem, or nothing to use the one just flagged>"
---

# /flow:issue — park it, don't fix it, don't lose it

The problem this solves: a real defect spotted mid-build has exactly three
fates today — fixed inline (scope creep), mentioned in chat (gone at the next
`/clear`), or a `Discovered: … — defer` line in a feature's `NOTES.md` that
gets archived with the feature. This skill gives it a fourth: a record that
outlives the feature and is complete enough to spec from cold.

**You never fix the problem in this skill.** One record, one `Next:` line,
back to what was in flight.

## 1. What goes in — the specable five

An issue is specable exactly when `/flow:spec`'s guard can't reject it. That
guard wants a problem, whose it is, and what they do today. Two more fields
make it buildable months later:

| Field | Rule |
|---|---|
| **Problem** | one sentence, the wrong behaviour — not the fix you have in mind |
| **Whose** | who hits this. `internal: the build` is a real answer; "users" alone is not |
| **Today** | the workaround, or `nothing — it just breaks` |
| **Evidence** | `path:line` you actually opened this session. No evidence → say so and stop |
| **Verify** | the one check that would prove it fixed. `human: <observable>` when no command can |

Plus a title, the date, `severity: critical｜major｜minor`, and `found during
<NNN-slug>` when a feature is open.

Take these from the session. Ask at most **one** batched round for whatever
the session genuinely can't answer, with your own guess beside each so a
one-word reply closes it. `/flow:issue` with no argument means the problem you
just flagged — restate it in one line and file it; never ask "which one?" when
there is only one.

## 2. Where it lands — ask, gh first

The reference grammar, the `gh` degrade rule and the two write moments live in
[`${CLAUDE_PLUGIN_ROOT}/skills/shared/issue-refs.md`](../shared/issue-refs.md) —
one contract, shared with `/flow:prep`, `/flow:spec`, `/flow:fix` and `/flow:next`.
This skill only files; it never posts a moment-1 or moment-2 comment.

```
gh auth status >/dev/null 2>&1 && gh repo view >/dev/null 2>&1
```

- **Succeeds** → ask once, one line: *"gh is available. GitHub issue, or
  `.specs/ISSUES.md`?"* Wait. GitHub is the default on a bare reply.
- **Fails** → `.specs/ISSUES.md`, and say which check failed in one clause so
  the fallback is never silent.

**GitHub** — `gh issue create --title "<title>" --body "<the five fields>"`.
Add `--label flow-issue` only if that label already exists (`gh label list`);
never create labels. Print the URL it returns.

**`.specs/ISSUES.md`** — append-only, sibling of `LEDGER.md`. Create it with
the `# Issues` heading if absent (create `.specs/` too). `I-NNN` = highest
existing `I-` + 1, `001` if none. Entry:

```
## I-003 — token refresh races on parallel requests
Found: 2026-09-09 · during 004-flow-v2 · severity: major
Evidence: src/auth/refresh.ts:88
Problem: two in-flight 401s each start their own refresh; the second overwrites the first token
Whose: any user with two or more tabs open
Today: they log in again
Verify: test asserts one refresh call for two concurrent 401s
Status: open
```

`Status:` is `open`, `speccing → NNN-slug` once a spec exists, or
`closed — <sha|reason>`. Nothing else edits this file.

## 3. Dedupe before writing

Check for the same problem already recorded — `grep` the open entries in
`.specs/ISSUES.md`, or `gh issue list --search "<3-4 distinctive words>"`.
A match means **append one line to the existing record** (`Also: <new
evidence> — <date>`, or a GitHub comment) and print that ref. Two issues for
one problem is the failure mode that makes the list untrustworthy.

## 4. Cross-reference, then get out of the way

When a feature is open (`.specs/.current` exists), append exactly one line to
its `NOTES.md`:

```
Discovered: <what> — defer → I-003
```

That keeps the existing `Discovered:` convention as the in-feature trail and
makes the issue its destination, so archiving the feature never buries the
problem.

End with two lines and nothing else:

- `Filed: I-003 — <title>` (or the GitHub URL)
- `Next: <the thing that was in flight>` — verbatim what you were doing.
  When nothing was in flight: `Next: /flow:spec I-003` when it should be
  built now, otherwise `Next: nothing — I-003 is parked.`

## NEVER

- **Never fix the problem here.** Filing and fixing in one turn is the scope
  creep this skill exists to prevent — the whole point is that the current
  work is not the place for it.
- **Never file without evidence you opened this run.** An issue whose
  `path:line` was inferred sends the next reader on a hunt; say "no evidence
  yet" and offer `/flow:fix` to reproduce instead.
- **Never file a fix as a problem.** "Add a mutex to refresh.ts" is a
  proposal; the record has to survive being wrong about the fix.
- **Never widen the current spec to absorb it.** Folding it in is an
  `--amend` on the user's call, never a side effect of noticing.
- **Never file more than one issue per invocation.** Three problems means
  three records, one at a time, each with its own evidence.
- **Never comment on the issue you just filed.** Filing is not a moment;
  `shared/issue-refs.md` §4 owns the only two that are.
- **Never silently pick a home.** `gh` available and unasked is the one thing
  the user asked this skill to ask about.
