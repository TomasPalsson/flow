---
name: flow-handoff
description: Split work into fresh, focused sessions by writing a small disposable handoff doc that bridges one session to the next. Use WHENEVER the user says /flow-handoff, "hand this off", "spin this into its own session", "start a fresh session for X", "I'm getting context bloat", or when a long session is going dumb and the remaining work is separable. Also the connective tissue of the build flow — flow-to-issues and flow-feature use it to implement each issue in its own clean session. Writes a purpose-driven markdown bridge (to a temp dir) that REFERENCES existing artifacts instead of duplicating them, redacts secrets, and tells the next session which skill to run. Triggers also on - handoff, hand off, fresh session, new session for, context bloat, smart zone, split this work, sub-agent prototype, parallel session.
---

# Flow Handoff

Move work into a new, focused session without losing the thread — and without dragging a bloated context along.

## Why this exists — the smart zone

Claude's window is huge (1M tokens) but its *quality* lives in roughly the first **~120k tokens** — the "smart zone". Past that, reasoning degrades: it forgets earlier decisions, repeats itself, misses things. There are two tools for this and they are NOT the same:

- **`/compact`** summarizes the *current* thread so you can keep going on the *same* task. It rescues intelligence within one line of work.
- **`/flow-handoff`** extracts just the slice of context a *different* concern needs and starts it in a *fresh* session. It preserves intelligence across *parallel* lines of work by never letting one context accumulate everything.

Rule of thumb: same task, too long → `/compact`. Different task hiding inside this one, or a clean unit of work to run alone → `flow-handoff`.

## When to use it

1. **Per-issue implementation (the main flow use).** Implementing 8 issues in one session means by issue #4 the agent is reasoning in a 200k-token swamp. Instead, write one handoff per issue and let each `flow-feature` run start fresh and sharp. flow-to-issues / flow-feature call this automatically.
2. **Out-of-scope tangent.** Mid-task you spot a bug or refactor that isn't this task. Don't dilute the current session and don't abandon it — hand the tangent off and keep going.
3. **DIY sub-agent / prototype.** Burn 100k+ tokens in a throwaway session exploring an approach, then hand the *distilled* learnings (not the exploration) back to the parent.
4. **HITL → AFK resume.** A human made the decision an issue was blocked on; hand off to an agent session to implement it now that it's unblocked.
5. **Tool diversity / adversarial review.** The doc is portable markdown — hand off to Codex/Copilot/another model for a second opinion.

## What a good handoff doc contains

Four parts, and no more — this is a *disposable bridge*, not documentation:

1. **Purpose** — one or two sentences: what the next session is for, and what "done" looks like. The single most important field; a vague purpose produces a vague session.
2. **References, not copies** — point to the artifacts (`@.specs/003-x/spec.md`, `@.specs/003-x/issues/02-*.md`, `@.specs/003-x/code-design.md` if `/flow-spec` produced one, a GitHub issue #, file:line). Do NOT paste their contents — duplication rots the moment the source changes. One exception: if code-design.md exists, paste its per-slice contract block for this issue in full alongside the path — a fresh cheap agent won't read a long design doc end to end, so the contract has to travel as content, not just a pointer.
3. **Skill to run** — tell the next session how to start: "run `/flow-feature` on the referenced issue", "run `/grill-me`", "diagnose then fix". This sets the session's flavor immediately.
4. **State + gotchas** — only what's NOT recoverable from the references: decisions already made, dead ends already ruled out, the deep-module seam to test at, anything surprising. Keep it tight.

## Phase 1 — Capture purpose

If the user invoked `/flow-handoff` with a purpose, use it. If not, ask ONE question: *"What is the next session for, in one sentence?"* Do not generate a generic handoff — the purpose is the whole point.

## Phase 2 — Gather references (not content)

Collect pointers to the relevant artifacts: spec path, issue file, plan.md, PR/issue numbers, key `file:line` anchors. Resolve them to real paths so the next session can open them. NEVER inline their text.

## Phase 3 — Redact

Scan what you're about to write for secrets — API keys, tokens, passwords, connection strings, PII. Strip them. A handoff doc lands on disk and may be shared or fed to another tool; treat it as if it will be.

## Phase 4 — Write the bridge

Write to a temp path (ephemeral, not tracked): `${TMPDIR:-/tmp}/flow-handoff-<slug>-<n>.md`. Use the template below. Tell the user the exact path and the exact command to start the next session, e.g.:

> Handoff written to `/tmp/flow-handoff-issue-02.md`. Start a fresh session and paste: *"Read /tmp/flow-handoff-issue-02.md and proceed."*

Do NOT write handoffs into the repo or `.specs/` — those hold durable artifacts; handoffs are throwaway. If the purpose turns out to be durable (a decision worth keeping), record it as an ADR in `.out-of-scope/` or the spec, and reference THAT from the handoff.

## Phase 5 — (Optional) reverse handoff

When a spun-off session finishes, it can write a handoff *back*: the distilled result (what changed, what was learned, what the parent should do next) — again references over copies. This is how a prototype session returns value without dumping its 100k-token exploration into the parent.

---

## Handoff doc template

```markdown
# Handoff: <short title>

## Purpose
<1–2 sentences: what this session is for + what "done" looks like.>

## Start here
Run: `/flow-feature` on the issue below   ← (or /grill-me, /fix, /diagnose, …)

## References (open these — do not expect them pasted)
- Spec: @.specs/003-foo/spec.md
- Issue: @.specs/003-foo/issues/02-add-title.md  (GitHub #14)
- Relevant code: src/foo/store.ts:40

## State you can't recover from the refs
- Decisions made: <…>
- Dead ends (don't retry): <…>
- Deep-module seam to test at: "entry persistence"

## Out of scope for this session
- <what NOT to touch — keeps the session focused>
```

---

## NEVER

- **NEVER duplicate content that already lives in a file or issue.** Reference it. A handoff that pastes the spec is stale the moment the spec changes — and it bloats the very context you're trying to keep lean. The one carve-out is the per-slice `## Contract for this slice` block: it is short, scoped to the single issue this session builds, and dies with it, so it cannot go stale the way a pasted spec does — and a cheap fresh agent demonstrably does not read a long design document end to end, which is the whole reason the block exists.
- **NEVER write a handoff without an explicit purpose.** A purposeless bridge produces an unfocused session, which is the exact problem this skill exists to prevent.
- **NEVER leave secrets in the doc.** It hits disk and may cross tools. Redact keys, tokens, PII.
- **NEVER store handoffs in the repo or `.specs/`.** They are disposable; durable knowledge goes in an ADR or the spec, and the handoff references that.
- **NEVER use handoff when `/compact` is the right tool.** Same task, too long → compact. Handoff is for separable concerns, not for rescuing the current thread.
