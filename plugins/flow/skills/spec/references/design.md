---
name: design-reference
description: The conditional design pass for /flow:spec — when a seam exists, what design.md contains, the pattern adoption gate, the Complexity Tracking table that makes over-engineering cost a written justification, and the per-task Contract block task-brief cuts. Orchestrator-only; no task agent ever reads this file. Load it in full only when the seam trigger fires.
---

# design.md — the cross-task structure layer

**Trigger, tested before anything is loaded**: two or more tasks share a name, an id type, an error shape, a module boundary, or a resource. One task, or no shared seam → **skip this pass entirely** and write `Design: none` in the TASKS.md header. The trigger is cross-agent surface, never file count and never the size of the feature.

The spec says WHAT; `design.md` says only what two agents must agree on to avoid building two incompatible halves. It is **not a spec** and never goes to spec-judge. The technology name that would cost the spec points as an implementation leak is **relocated** here, never relaxed there. It may cite an NFR ("§5's 300 ms p95 is why this seam exists") but never host one.

> The test for every line: *if a fresh agent building task T007 never opened this file, which of its decisions would still come out right?* Everything else is decoration — cut it.

## What carries, and what evaporates

| Carrier | Sticks | Looks like |
|---|---|---|
| **Structural** | ~88% | a compile error, a shared type, a file location, a lint rule |
| **Literal** | high, only inside the prompt | a value the agent copies verbatim from its brief |
| **Prohibition** | ~67% — budget the 33% leak | a NEVER that fires at a decision point; **max 5 per task brief** |

Anything that could be a compile error, a shared type, a file location or a lint rule **must not be prose**.

## Sections — emit only the ones that carry a real seam

Cap: **≤90 lines** plus the contract file. Signatures yes, bodies no.

| # | Section | Emit exactly |
|---|---------|--------------|
| 1 | **Contract file + language** | the path to a *runtime-importable* contract file (`contracts.ts` / `contracts.py` / `types.rs`) that tasks `import` — never a declarations-only stub — plus a ≤15-row table `canonical · identifier · plural · defined in · banned synonyms`, the branded-id / money-as-minor-units / UTC-instant declarations, and the async-vs-sync convention. Typecheck it before handoff: a table is a request, an import is a constraint. |
| 2 | **Trust boundaries** | `boundary · untrusted input shape · parse fn · failure granularity`, including the non-obvious ones (DB rows, queue messages, env vars, third-party and tool output). Agents treat "our own database" as trusted; the schema is older than the code. |
| 3 | **Error taxonomy** | one closed literal type **in the contract file**, plus the single mapping from variant to transport (status + body shape, or exit code). Otherwise T002 returns 422 `{"error":…}` and T009 returns 400 `{"detail":…}`. Adding a variant is an escalation. |
| 4 | **Module boundaries** | one line per module: `layer N · may import: <closed list> · exports: <closed list>` + "anything not listed is a bug". Ship the enforcement config, not the prose. State sibling independence as a pattern, never pairwise. |
| 5 | **Shared resources** | `resource · constructed by · passed how · received by` for the DB handle, HTTP client, config, cache, clock and logger, plus the config-key namespace and who owns migration numbering. An agent told nothing constructs its own. |
| 6 | **Deliberately duplicated** | bullets naming the prohibited consolidation *and what to do instead* — retry/backoff, date formatting, validation helpers, `utils/`. If genuinely none, write `none — because <reason>`: an empty section and a complete one are otherwise indistinguishable. |
| 7 | **Decisions** | ≤6 lines: *"In the context of `<component>`, facing `<force, as a checkable fact>`, we chose `<mechanism + signature>` and rejected `<option>`, to achieve `<benefit>`, accepting `<named cost>`."* Plus one `Makes hard:` line per decision naming the files a reversal touches. |

## Pattern adoption gate

Run this before ANY structure enters the file. Every field filled, or do not adopt.

```
1. HIDDEN DECISION   This structure hides the decision "____" — one sentence, in domain language.
2. TASK CONSUMERS    Tasks ____ and ____ must know it to write correct code. (Fewer than two → reject.)
3. PRODUCTION COUNT  ____ implementations reachable in production TODAY. Mocks, fakes and
                     in-memory stores count as ZERO.
4. SPEC WITNESS      The two concrete cases are at spec §____ and §____ (spec, never TASKS.md).
5. MECHANISM         <the exact declaration every agent will read, in this project's language>
6. REJECTED          ____, rejected because ____ (cite the force from field 1 or 4).
7. CONFIRMATION      A violation is caught by ____ (lint rule, import-boundary test, type error).
8. COST              This makes ____ harder — it would touch ____.
```

Adopt a structure when it removes a decision from six prompts. Reject it when the payoff is an extension point for a seventh task that does not exist. **Patterns are top of mind for you and structurally invisible to the builder**: `design.md` may not contain a GoF pattern name anywhere. "Use Strategy" reliably yields an ABC, two concretes, a factory and a registry; `HANDLERS: dict[EventType, Callable[[Event], Result]]` yields a dict.

## Complexity Tracking

Every structure that survived the gate but violates the simplest thing that could work gets a row here. No row, no violation — the table is the price of over-engineering, paid in writing.

| Violation | Why needed | Simpler alternative rejected because |
|-----------|-----------|--------------------------------------|
| [4th layer / registry / extra module] | [the concrete force] | [what breaks if you do the obvious thing] |

An empty table is the expected outcome on most features. A table with four rows is a design that should be re-cut, not a design that documented itself well.

## The per-task Contract block

Cut one block per task, here, in this same pass. `${CLAUDE_PLUGIN_ROOT}/scripts/task-brief TASKS.md T007 --design design.md` appends the block whose heading names the task — so the heading must contain the task ID verbatim. ≤25 lines each.

```
## Contract for T007 — <title>
CONTRACT   <path> — import from it. A type you need that is not there is an escalation, never a local declaration.
NAMES      <the naming-table rows this task touches, verbatim, banned synonyms included>
MODULE     <path> · layer N · may import: <closed list> · exports: <closed list>
CALLS      <the exact signatures this task implements or calls>
DUPLICATE  <the section-6 bullets that touch this task — do not consolidate these>
THE FIVE   (1) NEVER invent an error type, field name or result shape that already exists in the
           contract — copy the literal declaration. (2) NEVER type a boundary function's parameter
           as the narrow type; the narrow type is only ever the RETURN of a fallible function.
           (3) NEVER add a mode, flag or extra required parameter to a shared abstraction the design
           handed you — duplicate it inside your task and say so. (4) NEVER refactor or rename
           outside the task's `files:` list — a change to an unlisted file is a defect.
           (5) NEVER abbreviate inside an identifier. Spell the word.
```

THE FIVE is the whole prose budget and the set is closed — do not substitute into it. The block fixes NAME, LOCATION and SIGNATURE, never COMPLETENESS; acceptance criteria come verbatim from the spec and the task's own `verify:`.

## NEVER

- **NEVER** paste this file, or any part of it but a `## Contract` block, into a task agent's prompt. Naming the pattern behind a decision moves output away from a correct implementation, not toward it.
- **NEVER** let a task agent edit the contract file. It has exactly one owner: the orchestrator.
- **NEVER** write a section whose seam is consumed by fewer than two tasks. Delete the section instead.
