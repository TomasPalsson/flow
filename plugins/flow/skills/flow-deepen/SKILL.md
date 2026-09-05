---
name: flow-deepen
description: "Closing architecture loop of the build flow — runs AFTER a spec's issues are built and PRs merged. Hunts deepening opportunities (Ousterhout deep modules, information leakage, poor locality, layer/abstraction mismatch, tests coupled to internals) and emits BEHAVIOR-PRESERVING, characterization-test-first vertical slices in .specs/<NNN>/issues/ format that flow-feature and flow-swarm consume unchanged. Triggers: /flow-deepen, \"deep modules\", \"reduce coupling\", \"post-merge cleanup\", \"tech debt from the build\", \"the agent keeps editing the wrong place\", \"shallow modules\", behavior-preserving refactor, leakage, pass-through methods, characterization test, after all flow-feature issues shipped. Do NOT use for: whole-codebase debt (→ /audit), current-diff cleanup (→ /simplify), adding new behavior (→ /flow-feature). /audit sweeps the whole repo; /simplify cleans the current diff; /flow-feature adds behavior; flow-deepen scopes to ONE shipped spec and emits slices back into its pipeline."
---

# Flow Deepen

The closing loop of the build flow. After a spec's issues are built and the PRs are merged, the codebase carries debt the feature work exposed — shallow modules, leaked decisions, scattered knowledge, cosmetic layers, tests welded to internals. `flow-deepen` hunts those, scores them, and emits the worthwhile ones as **behavior-preserving** deepening slices that slot straight back into the same `.specs/` pipeline the features came from.

```
flow-spec ──► flow-to-issues ──► flow-handoff ──► flow-feature ──► [PRs merged] ──► [flow-deepen] ──► more slices ──► flow-feature/flow-swarm
```

## The One Idea: deepen, don't rewrite

A **deepening opportunity** is placing useful behavior behind a smaller, more stable interface — *more leverage per unit of interface surface*. Ousterhout's frame: a module's depth = benefit hidden ÷ interface complexity imposed on callers. Deep = tall and narrow (Unix's 5 file syscalls hiding decades of kernel). Shallow = wide and squat (`new ObjectInputStream(new BufferedInputStream(new FileInputStream(path)))` — three classes, an ordering dependency, and buffering semantics dumped on the caller).

The unit of work is a **deepening slice**, not a refactor and not a rewrite. Every slice is behavior-preserving by definition and gated on a characterization test written FIRST. If a slice changes observable behavior, it is feature work — it does not belong here.

## What this is NOT (read this before anything)

| Skill | Scope | Behavior change? | flow-deepen is different because |
|---|---|---|---|
| `/audit` | whole codebase/module, churn-driven | sometimes (fixes bugs) | flow-deepen is scoped to ONE shipped spec, behavior-preserving only |
| `/simplify` | current diff only | no | flow-deepen runs post-merge across the merged work, emits issues not edits |
| `/flow-feature` | one issue, adds behavior | yes (Red→Green) | flow-deepen never adds observable behavior |

**Do NOT run flow-deepen** when: the spec's issues aren't all built yet (it is downstream of execution, never mid-flight); the request is "audit the repo" with no `.specs/` context (→ `/audit`); the request is "clean up this function" (→ `/simplify`); the request is "add X" (→ `/flow-feature`); or the proposed change introduces a new method, return value, or error type visible to callers (that is a feature — split it out).

## MANDATORY: load the detection checklist

Before Phase 2, **read `references/detection-heuristics.md` in full.** It carries the complete greppable detection signal catalogue (the five smell families), the agent-failure guardrails, the AFK/HITL tag decision table, and the three-part behavior-preserving acceptance-criteria pattern. Do not hunt from memory — the catalogue is the skill's expert knowledge and the body below assumes it is loaded.

---

## Phase 1 — Absorb context

Ground the hunt in *intended* boundaries before judging *accidental* structure. Friction that is a documented trade-off is not a smell.

1. **Resolve the spec.** Default to the **highest-numbered** `.specs/<NNN>-*/` dir (the freshest flow-spec output), or the path the user passed. If none exists, stop: *"No `.specs/` context found. flow-deepen deepens a shipped spec's modules — for a whole-repo debt sweep run `/audit` instead."*
2. **Read the intent layer first**: the spec's domain glossary, any ADRs, and `.out-of-scope/`. These tell you which boundaries are deliberate. A pass-through layer an ADR explicitly mandates is not a candidate.
3. **Read the merged diffs.** `git log --oneline --merges` since the spec's first issue, and the diffs of the merged issue branches (`flow/<slug>/issue-*`). The deepening targets are the modules the feature work actually touched and grew.
4. **Mine the repeated-agent-mistake signal.** `git log --follow` on the spec's hot files — if multiple issue branches edited the same file repeatedly, or the agent kept landing changes in the wrong place, that is a first-class structural signal (missing seam / locality failure), more reliable than human code review because agents expose navigability under load. One mistake is noise; *repeated* mistakes at the same location are signal.

## Phase 2 — Hunt opportunities

With `references/detection-heuristics.md` loaded, sweep the touched modules through the five smell families. Run the grep signals; do not eyeball.

1. **Shallow modules** — ratio heuristic, classitis chains, anemic getter/setter classes.
2. **Interface leakage** — comment bleed (`internally`/`buffer`/`cache`/`retry`), config-parameter explosion, the same internal type imported across two modules.
3. **Poor locality** — temporal decomposition (Reader/Validator/Applier sharing a format), pass-through variables threaded through frames that never use them.
4. **Layer / abstraction mismatch** — pass-through methods, same-named method chains (`save→save→save`), the decorator trap, feature-named APIs.
5. **Tests coupled to internals** — structural one-test-class-per-class mirroring, over-mocking, tests importing from `__internal`/`internals/`.

**Apply the guardrails as a HARD FILTER, not advice.** Discard any candidate that: touches a low-churn stable file (`git log --follow` shows churn < 2 in 6 months — frozen debt, refactoring it is negative ROf); has only two duplicate instances (Rule of Three — wait for the third); would add a single-implementation interface, plugin hook, or factory "for the future" (speculative generality); or has no test coverage and no seam to attach one at (characterize first or drop it). These are the dominant ways an "improve architecture" agent makes things worse — see the guardrail section in the reference.

**Before running the speculative-generality and single-implementation filters on a candidate, check the spec dir for `code-design.md` and read its Decisions section first** — a structure recorded there passed the pattern adoption gate with named consuming slices and a spec witness, so it is a deliberate design decision, not an invented abstraction, and is exempt from those two filters. That exemption expires with its premise: if the named consuming slices never materialized or the second implementation never arrived, the structure fails the filter like any other candidate. A structure `code-design.md` never mentions gets the full filter unchanged.

## Phase 3 — Score and recommend

For every surviving candidate, fill the four-dimension frame (vague "this is messy" is banned):

1. **Modules involved** — the named files/types and the seam between them.
2. **Friction today** — the concrete cost, with the detection signal that found it.
3. **Proposed deepening** — the before→after at the call site (e.g. "caller goes from 3 constructor calls to 1 factory call").
4. **Win** — measurable gain in **locality + leverage + testability**, plus a churn note (high-churn = high payoff).

Then **rank them and recommend the top ones** — do not dump every candidate on the user. State a cutoff and the reasoning: *"Mr Claude recommends shipping the top 3 (highest churn × leverage) and parking the rest — confirm or correct?"* The always-recommend-an-answer rule holds for every choice surfaced here.

## Phase 4 — Emit as behavior-preserving slices (draft only)

Draft each recommended deepening as a vertical slice in the flow's exact issue format — **drafted, not written; nothing hits disk before Phase 5.**

- **Location**: the EXISTING spec's `issues/` dir. NN continues from the highest existing issue number. NEVER a new `.specs/` dir.
- **Vertical, not horizontal**: `## What ships` states call-site-observable behavior ("caller creates a user with one method call instead of three"), never a layer ("extract the repository interface").
- **Tag**: AFK by default — behavior-preserving + test-gated. Escalate to HITL only on the four triggers (interface-shape choice, external-contract change, public-symbol deletion, or a characterization test that reveals a possible bug). Label conditional ones `AFK (pending characterization test — may escalate to HITL if current behavior is a bug)`.
- **depends-on**: serialize same-module slices with `#<NN>` — slice N pins the seam, slice N+1 refactors through that pin. A single straight chain across all slices means they are too coupled; split into per-module chains.
- **Acceptance criteria**: the mandatory three-part behavior-preserving pattern (characterization-test-first → byte-for-byte seam observability → measurable interface reduction). No AC may require a NEW test case to pass — that would be feature work.
- **Trace**: include a `## Deepening rationale` section naming the detected anti-pattern + detection signal (deepenings derive from smell detection, not spec FRs — this lets spec-judge grade without false-penalizing an absent spec trace).

Use `references/detection-heuristics.md` for the full slice template and the worked example.

## Phase 5 — Approval gate (HARD)

**Nothing is written until the user approves.** Show one table and stop:

```
#  Deepening slice                                      Tag                       depends-on   Family / signal
05 Caller deserializes with one factory call, not 3     AFK                       —            classitis (3-class chain)
06 UserStore exposes 1 method where 4 forwarded         AFK                       #05          pass-through method chain
07 Collapse Config{Reader,Validator,Applier} to load()  AFK (pending char-test)   —            temporal decomposition
08 Choose options-object vs two-method client shape     HITL                      —            interface-shape decision
...
Top 3 by churn × leverage recommended  •  N AFK / M HITL  •  every slice characterization-test-gated
```

Then ask exactly: *"Write these as local markdown only, or also open GitHub issues with `gh`? Reply 'local', 'github', or edits."* Wait. **Silence is not consent** — even local markdown is filesystem state flow-swarm will act on. Ambiguous replies get the question again.

On approval: write each slice file to `<SPEC-DIR>/issues/<NN>-<slug>.md`, append `### <NN> — <title>` subsections to `plan.md`, and add a row to `issues.md` — all three in sync. For GitHub, create in dependency order and write the URLs back to `issues.md`.

## Phase 6 — Hand off + the characterization-test-first guard

Each slice runs in its OWN fresh session — eight refactors in one context and the agent goes dumb and starts rewriting. The guard that keeps "behavior-preserving" honest: **the characterization test is a commit gate, not advice.** A slice is not done until the pinning-test commit exists in its branch and the full suite is green byte-for-byte. flow-swarm respects the `depends-on` ordering so each seam is pinned before the next slice refactors through it.

**ALWAYS end with the next step (so the user never has to remember the flow):**

> *"Deepening plan ready (N AFK, M HITL), all behavior-preserving and characterization-test-gated. **Next in the flow:** #05 is unblocked (the walking skeleton of the deepening). Mr Claude can run **`/flow-handoff`** to write a per-slice bridge, then **`/flow-feature`** implements it via the characterization-test-first guard — or **`/flow-swarm`** runs the unblocked AFK slices in parallel since they land in the same `issues/` dir. Start with #05? HITL slices need your decision first. (Flow: `flow-spec → flow-to-issues → flow-handoff → flow-feature → [merged] → flow-deepen`.)"*

---

## NEVER

- **NEVER change observable behavior.** A new method, return value, or error type visible to callers is a feature — route it to `/flow-feature`. Consequence: a "refactor" commit that silently breaks an edge case the original author handled, surfacing as a production bug weeks later with a misleading commit message.
- **NEVER emit a slice without the characterization-test-first AC.** Consequence: the refactor has no behavioral oracle; flow-swarm restructures with no proof of preservation, which is exactly the Feathers failure mode — restructuring masquerading as refactoring.
- **NEVER mark a slice AFK when it hides a design decision.** Interface-shape forks, external-contract changes, and public-symbol deletions are HITL with the decision named. Consequence: an agent autonomously picks an interface shape no human signed off on, and the wrong abstraction is now load-bearing.
- **NEVER refactor a low-churn stable file or extract on two instances.** Consequence: risk spent for zero payoff (frozen debt) or a wrong abstraction coupled before the third instance reveals its real shape — both cost more to undo than the original state.
- **NEVER add a single-implementation interface, plugin hook, or factory "for the future."** Consequence: interface complexity equals implementation complexity — a shallow module, the opposite of deepening, and YAGNI accidental complexity every future reader must navigate.
- **NEVER write slices to a new or parallel directory.** They go in the existing spec's `issues/` dir with continuing NN. Consequence: flow-swarm resolves `ISSUE_DIR` once from the spec dir and never recurses — a parallel dir is invisible and the slices never run.
- **NEVER write any file before the approval gate.** Consequence: filesystem state downstream agents act on, created without consent — the house-wide hard-gate rule.
- **NEVER ask a bare question.** Lead every HITL choice with a concrete recommendation and its reasoning, then "confirm or correct?". Consequence: an open question stalls the flow and abdicates the judgment this skill exists to provide.
- **NEVER reimplement the refactor here.** flow-deepen plans and slices; `flow-feature`/`flow-swarm` execute under the characterization-test guard. Consequence: a bloated context that rewrites instead of deepens.

