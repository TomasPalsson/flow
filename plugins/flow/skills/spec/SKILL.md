---
name: spec
description: "The only door into a flow build: compute the route (bounded | oneshot | dispatch) from intent gaps, irreversibles and footprint, run ONE batched discovery turn of pre-answered assumptions, write only the artifacts that route needs (nothing, TASKS.md, or spec.md + TASKS.md + design.md), point .specs/.current at it and lint it. Triggers: /flow:spec, \"spec this\", \"write a spec for\", \"build me X\", PRD, requirements doc, design doc, acceptance criteria, \"how should this be structured\". Flags: --amend \"<change>\", --interview, --unattended, --stealth. Not for building it (that is /flow:next), not for a bug (/flow:fix)."
---

# /flow:spec — the only door

One turn of discovery, one route decision, the smallest set of files that route needs, and a `Next:` line that hands the build to `/flow:next`. You never negotiate the route with the user and you never ask a question you could answer and let them correct.

## 0. Empty input, and the speccability guard

`/flow:spec` with no description: *"Describe it in 1–3 sentences and I'll route it."* A description with no problem, no user and no domain signal is not a small spec, it is an unspeccable one: ask for (1) the problem, (2) whose, (3) what they do today instead — and stop until they answer. This guard holds under `--unattended` too; nothing can invent a problem statement.

**An issue reference satisfies this guard.** `/flow:spec 143`, `#143`, `I-003` or "do issue 143" — resolve it per [`${CLAUDE_PLUGIN_ROOT}/skills/shared/issue-refs.md`](../shared/issue-refs.md), read in full before doing anything else. Its Problem / Whose / Today become the description and its `Verify` seeds §6, so you ask only what the issue left empty.

## 1. PREP.md gate — check this before everything else

If a `.specs/NNN-*/PREP.md` exists with `Status: ready for spec` and no `spec.md` beside it, that directory is the spec directory, the interview already happened, and you **do NOT load `references/question-bank.md` at all**. Consolidate instead:

- every `D-NN` under `## Decisions` is copied verbatim and **never re-asked**; if the spec must contradict one, write `[NEEDS CLARIFICATION: conflicts with D-NN]` rather than asking again
- `## Not this` becomes §2.2 Non-goals verbatim · `## Discretion` items you decide silently · `## Assumptions` land in §7 with their confidence · `## Verify` seeds §6 launch criteria · `## Open` items become Open Questions and already count toward the cap of 3
- PREP.md's own route line is an input to §2, not a verdict — recompute and say so if you differ

Ask only about a category PREP.md left genuinely empty. `Status: interviewing` means prep is unfinished: tell the user to finish `/flow:prep` and stop.

## 2. Route — computed, then stated as a fact

Three facts, counted before anything is written:

| Fact | How you count it |
|---|---|
| **intent gaps** | decisions the description leaves open that change what ships |
| **irreversibles** | migrations, public contracts, deletions, anything with a blast radius past this branch |
| **footprint** | files this touches, and whether the flow already exists in this repo |

| Route | Predicate | Artifacts | Execution |
|---|---|---|---|
| `bounded` | 0 gaps, 0 irreversibles, exactly 1 task, ≤2 files, the flow already exists here | **nothing under `.specs/NNN-slug/`** — the plan is three lines in chat, and one `LEDGER.md` line after it lands | inline, main session |
| `oneshot` | 0 gaps, 0 irreversibles, 2-5 tasks | `TASKS.md` only | inline per task |
| `dispatch` | anything else | `spec.md` + `TASKS.md` (+ `design.md` on the seam trigger) | one fresh subagent per task |


**State the route; do not ask it.** One line, facts first:

> `Route: dispatch — 3 intent gaps, 1 irreversible, 9 files. Reply 'oneshot' to downgrade.`

The ratchet is one-way. `/flow:next --escalate` upgrades at any time; a downgrade needs `--force` and writes a `Ruling:` line into `NOTES.md`. **Reaching for a lighter label because you are unsure is the doubt.** And the approval gate never scales down — `bounded` still costs exactly one "go?". Only the artifact scales.

## 3. Discovery — ONE turn

**MANDATORY — READ ENTIRE FILE** (unless the PREP.md gate above fired): [`references/question-bank.md`](references/question-bank.md). It defines the one batched turn: a numbered list of positions you have already taken, each with its reasoning, closing with *"reply with the numbers you want to change, or 'all good'"*. Silence is acceptance of a stated position, not a skipped question.

Two items are never dropped: the negative-scope position (what this will NOT do) and a number for every adjective in play. `--interview` restores the serial one-question-per-turn form for a user who wants it. `--unattended` proceeds on the stated positions after one offer, recording each as an Assumption with its confidence.

## 4. Write only what the route needs

**`bounded`** — no directory, no spec file. Print the plan in chat (what changes, the test that proves it, the one risk), ask **"Go?"**, and stop. After it lands, append one line to `.specs/LEDGER.md`: `<date> bounded — <title> — <sha>`.

**`oneshot` and `dispatch`** — allocate the directory with `${CLAUDE_PLUGIN_ROOT}/scripts/new-spec "<Title>" --dir .specs --current` — after §4a's `flow stealth` when `--stealth` was passed or its position was accepted — (add `--reuse .specs/NNN-<slug>` when the PREP.md gate fired; never allocate a second number for a prepped feature). Then:

- `dispatch` only: write `spec.md` from [`${CLAUDE_PLUGIN_ROOT}/flow-templates/spec.md`](../../flow-templates/spec.md) — ~110 lines, every placeholder filled from the discovery turn or recorded as an Assumption. When the PREP.md gate fired, **write `spec.md` beside** that `PREP.md`, in its directory. No technology names in §4; those belong in `design.md`.
- `dispatch` only, and only when the seam trigger fires — two or more tasks share a name, an id type, an error shape, a module boundary or a resource — read [`references/design.md`](references/design.md) in full and write `design.md`. One task, or no shared seam: skip it and write `Design: none` in the header. Never paste any of `design.md` into a task agent but its own `## Contract` block.
- both routes: write `TASKS.md` from [`${CLAUDE_PLUGIN_ROOT}/flow-templates/TASKS.md`](../../flow-templates/TASKS.md). The header carries `Spec: · Design: · Base: <sha> · Route: · Test: <cmd>`, plus `Issue: #143` when this run came from an issue reference; every task line carries `files:` (a comma list, no globs) and `verify:` (a runnable command, or `human: <observable>` for a `CHK###`). `after:` is what computes the waves; two `[P]` tasks in one wave may not share a file. Do **not** write `Approved:` — that line is the user's, and only `/flow:next` records it.

## 4a. Stealth — specs this repo must never see

- `--stealth`: before `new-spec`, run `flow stealth` (idempotent, once per clone). It moves any untracked `.specs/` into a private store repo outside the target, links it back, hides it in `.git/info/exclude`, and installs a `post-checkout` hook (re-links in new worktrees) and a `commit-msg` hook (blocks spec vocabulary). Nothing else in the skill changes; `flow next` detects stealth from disk, so the flag is never needed again.
- Suggesting it: on `oneshot`/`dispatch`, when no `.specs/` exists yet, run `flow stealth --check --json`. When `suggest` is true, the discovery turn carries a stated position: `N. Stealth: this repo looks public (<reasons>) — the specs will live in a private store outside it. Reply N to keep them in-tree.` Silence accepts → run `flow stealth` before `new-spec`. `flow next`'s no-project `Why:` names the same hint.
- `bounded` writes no directory, so there is nothing to hide — only the no-leak rule applies.
- When stealth is active (`flow next --json` → `stealth.active`): never write `.specs/` paths, `T###`/`CHK###`/`G###` ids, spec numbers or `Ruling:` labels into anything the target repo keeps.

## 5. Judge — dispatch only, one pass

On `dispatch`, spawn one spec-judge subagent (`general-purpose`, `sonnet`) against the spec, **capped at one iteration**. Apply its ship-blockers, carry the rest as Assumptions, and report the score once. `oneshot` and `bounded` never invoke it. If spec-judge is not installed at `${CLAUDE_PLUGIN_ROOT}/skills/spec-judge/SKILL.md`, say so in one line and continue — never self-score, that defeats the independent judge.

## 6. Hand off

In this order, every run that wrote a directory:

1. `flow use <NNN-slug>` — points `.specs/.current` at it
2. `flow lint` — fix every ERROR it prints before you stop; each one carries its own `fix:` string
3. print the truthful gate manifest: **"This run will stop for you N times"** — count them for real (the approval gate, every `CHK###`, the verification gate, and the PR), and name where
4. **issue runs only** — post the "picked up" comment per `shared/issue-refs.md` §4 moment 1, after checking the marker so a re-run or an `--amend` updates it instead of posting twice. A `gh` failure here is one clause of output, never a stop.
5. end with the router's own line: run `flow next` and print its `Next:` verbatim, e.g. `Next: read .specs/003-entry-tagging/TASKS.md, reply "approved"`

## 7. `--amend "<change>"`

Never a silent rewrite. Append `## Amendment <YYYY-MM-DD>` to `spec.md` recording what changed and why, then re-plan **append-only**:

- new IDs are appended; an existing `[x]` is never renumbered, reordered or deleted
- an unchecked task the amendment obsoletes becomes `- [~] <ID> … — dropped: <reason>`
- `Approved:` is **cleared** — a scope change may not ride on a stale approval
- when nothing actually changed, the files are **byte-for-byte identical**; say "no-op" and stop

Then `flow lint` and the `Next:` line as in §6.

## NEVER

- **NEVER** ask the user to pick the route. Compute it, state it, and let them downgrade in one word.
- **NEVER** ask more than one discovery turn (`--interview` is the user's own opt-in, not yours). Batching is the whole design: a numbered list of positions gets corrected, a list of open questions gets the easy half answered.
- **NEVER** accept a vague adjective. "Fast" with no number is a decision you have handed to whoever builds it, alone, at 2am.
- **NEVER** skip the negative-scope item. Ten seconds to state; it is the only thing that ends a scope argument.
- **NEVER** write a `spec.md` on `bounded` or `oneshot`. The escape from ceremony is a route, not a missing feature — and the artifact is the only thing that scales.
- **NEVER** write `Approved:` yourself, on any route or under `--unattended`. That line means a human read the plan.
- **NEVER** re-ask a decision recorded as a `D-NN` in PREP.md — the user already made it, a second answer silently forks the record, and re-asking teaches them the file is decorative.
- **NEVER** hand off to GitHub issues. Work items live in `TASKS.md`; `flow publish` mirrors them only when someone asks.
- **NEVER** end without the router's `Next:` line. A spec whose next step lives only in this transcript does not survive `/clear`.
- **NEVER** commit, link or name a spec in a repo where `stealth.active` is true (the hook catches the commit message; code comments, test names and PR text are on you).
