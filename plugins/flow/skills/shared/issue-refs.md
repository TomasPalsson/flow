---
name: issue-refs
description: The issue contract shared by /flow:issue, /flow:prep, /flow:spec, /flow:fix and /flow:next — how an issue reference is resolved into a build input, and the exactly-two moments flow is allowed to write back to it. Read this whenever an invocation carries an issue reference.
---

# Issue references — resolve in, write back twice

One grammar, one resolution order, two write moments. Five skills read this
file so they cannot drift from each other.

## 1. The grammar

An argument is an issue reference when it matches any of:

| Form | Means |
|---|---|
| `I-003` | an entry in `.specs/ISSUES.md` |
| `#143`, `143`, `gh-143` | GitHub issue 143 in this repo |
| `do issue 143`, `issue 143`, `fix #143`, `work on 143` | GitHub issue 143 |
| a full `https://github.com/<o>/<r>/issues/143` URL | GitHub issue 143 |

A bare integer is only an issue reference when the invocation has no other
description. `/flow:spec 143` is issue 143; `/flow:spec add a 143ms timeout`
is prose. When genuinely ambiguous, say which reading you took in one clause
and continue — never stop to ask.

## 2. Resolution

**`I-NNN`** — read that entry from `.specs/ISSUES.md`. Absent → say so and
treat the raw argument as prose.

**GitHub** — `gh issue view <n> --json number,title,body,state,author,comments`.
Use the body **and every comment** as discovery input; a correction three
comments deep is exactly the context that stops you re-deciding something the
team already settled.

Then map onto the specable five: **Problem · Whose · Today · Evidence ·
Verify**. Whatever the issue leaves empty is what you ask about — everything
it answers is never re-asked, the same rule `PREP.md` gets.

`gh issue view <n>` also resolves **pull requests** — `gh issue view 4` on this
repo returns PR #4, `MERGED`. A reference that resolves to a PR is a typo, not
a build input: say which it was and stop, rather than speccing a merged PR.
`gh pr view <n> --json number` succeeding is the tell.

**Degrade, never block.** `gh` missing, unauthenticated, offline, or the issue
not found → say which check failed in one clause, use the raw text as the
description, and carry on. An unreachable issue tracker never stops a build.
This is the router's own rule at `bin/lib/router.js:275`.

## 3. Recording the link

The link lives on disk, because disk is the state:

- spec directories: `Issue: #143` (or `I-003`) in the `TASKS.md` header, beside
  `Spec:` and `Base:`
- `.specs/ISSUES.md` entries: `Status: speccing → NNN-slug`, then
  `closed — <sha>`

`flow next` never reads an issue to decide state. GitHub is a mirror, never a
routing predicate — `TASKS.md` stays THE state, so the two can never disagree
about what to do next.

## 4. The two write moments

Exactly two comments per issue, ever. Both carry a marker so a re-run, an
`--amend` or a resumed session updates the existing comment instead of posting
a second one. **Check the marker before every post:**

```
gh issue view <n> --json comments -q '.comments[].body' | grep -q 'flow:<slug>'
```

**Moment 1 — picked up.** After `/flow:spec` (or `/flow:fix`) writes the
directory. Tells a teammate to stop duplicating the work:

```
🔨 Picked up → `.specs/007-token-refresh/`
branch: `flow/007-token-refresh` · 5 tasks · route: dispatch
Verify: `bun test auth/refresh`
<!-- flow:007-token-refresh -->
```

**Moment 2 — shipped.** At `/flow:next`'s archive step, when the feature is
merged. Then `gh issue close <n>`:

```
✅ Shipped in #212 (`a1b2c3d`)
Verify: `bun test auth/refresh` — 4 pass
<!-- flow:007-token-refresh:done -->
```

Nothing else comments. Not a wave, not a gate, not a `PASS-<sha>`, not a
`Discovered:` line — those are turns, and a turn is not news to a human
reading an issue thread.

## 5. Improving the issue body — ownership decides

| Who wrote the issue | What you may do |
|---|---|
| flow did (`I-NNN`, or a `gh` issue this skill filed) | rewrite the body in place with the specable five, once, at moment 1 |
| a human did | **never touch the body** — put what you learned in the moment-1 comment |

Rewriting a colleague's words to be more specable is the kind of tidy that
reads as someone overwriting your report. The comment says the same thing and
costs nobody their text.

## NEVER

- **Never make an issue a routing predicate.** `flow next` reads disk. An
  issue that says "done" while `TASKS.md` has unchecked tasks is a mirror that
  went stale, not a state change.
- **Never comment per state change.** Eight comments on one issue is how a
  thread stops being read at all.
- **Never post without checking the marker first** — a resumed session that
  double-posts makes the whole mechanism untrustworthy.
- **Never let a `gh` failure block a build.** Degrade to the raw text, say so,
  continue.
- **Never close an issue the build did not actually ship.** Closing is the one
  write a human has to undo by hand.
