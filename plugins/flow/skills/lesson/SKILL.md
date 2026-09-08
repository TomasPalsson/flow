---
name: lesson
description: "Turn one observed mistake into a guardrail that makes it impossible, not discouraged. Use WHENEVER the user corrects Claude ('don't do that', 'you did X again', 'that was wrong', 'stop doing X', 'why did you delete…') or when the user types /lesson. Pins the mistake in three lines, runs `flow lesson propose` — which DECIDES the rung (rule, test, script or note) and DRAFTS the guardrail — asks exactly one lock-it-in question, then `flow lesson lock` writes it. Do NOT use for: fixing the bug itself (/fix), logging a note without acting (/aside), general skill polish (/skill-improver), or a one-off preference that only applies to this conversation."
argument-hint: "[what went wrong]"
---

# /lesson — never the same mistake twice

A sentence in CLAUDE.md is a request; a rule, test or script is enforcement. When the user corrects a mistake, run this now — do not ask whether to, do not wait for agreement first. Finish the interrupted step first if one is mid-flight; once started, carry it through to the one-line receipt before resuming.

## Step 1 — Pin the mistake

Three lines, from the conversation:
- **Did:** the exact action (command, edit, claim) — quote it.
- **Should have:** the correct behaviour, one sentence.
- **Input:** the concrete thing that reproduces it — a command string, a file path, a diff.

If `$ARGUMENTS` is empty, read the last ~30 messages and list at most 4 candidate mistakes, newest first, each with its own Did/Should have/Input. Pick the newest unless the user named one.

## Step 2 — Propose

```
flow lesson propose --did "<did>" --should "<should have>" --input "<input>" --json
```
Decides the rung and drafts the guardrail. Nothing is proposed that isn't already drafted; do not second-guess the rung.

## Step 3 — Ask exactly one question

Via `AskUserQuestion` when interactive; when not interactive, take the default and say so.
The first option's label is the propose JSON's `block` field **verbatim** — it names what
`--choice block` writes here (a rule, a red test, or a note). Never paraphrase it into enforcement:
```
Lock this in?
▸ Block it      <the "block" field, verbatim>          (default)
  Just note it  one line in CLAUDE.md — or .claude/rules/<area>.md when the input names a path
  Not a lesson  discard
```
"Just note it" always writes the note, never a rule — say where it lands, not what it enforces.

## Step 4 — Lock it

```
flow lesson lock <draft-id> --choice block|note|discard
```

## Step 5 — Report

Print the command's own line, verbatim — nothing added:
```
flow: lesson locked — <what> (<file>, <n> tests). Undo: flow lesson undo <slug>
```
Then resume the interrupted task.

## Worked example

```
user> don't do that again
flow> Reverted. I hand-edited src/generated/api.ts, which is generated.
      Locking that out — one question:
      Lock this in?
      ▸ Block it      Edit and Write under src/generated/ are blocked — the rule
                      .claude/flow.rules/never-hand-edit-files-under-generated.md   (default)
        Just note it  one line in generated.md
        Not a lesson  discard
user> [enter]
flow: lesson locked — never hand-edit files under generated/
(.claude/flow.rules/never-hand-edit-files-under-generated.md, 0 tests).
Undo: flow lesson undo never-hand-edit-files-under-generated
```

One user turn, one keypress — the bookkeeping is `flow lesson`'s, not yours.
