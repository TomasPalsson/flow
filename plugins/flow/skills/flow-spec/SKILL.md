---
name: flow-spec
description: "Forge a judge-scored specification from a brief description: size classification, serial Anchor→Boundaries→Depth discovery, an anti-pattern-proof spec, code-design.md when slices share a seam, spec-judge scoring to ≥96/120. Triggers: /flow-spec, /spec, \"write a spec for\", create a spec, PRD, requirements doc, design doc, SRS, RFC, acceptance criteria, \"how should this be structured\". Not for building it (use /flow)."---
---

# Spec Forge

Produce a buildability contract — a spec a developer who has never spoken to the author can implement and a QA engineer can write tests from — by running discovery before drafting, then scoring the draft.

---

## Core Philosophy

### What this skill is for

A spec is not a document about what to build — it is a **contract between discovery (what was learned) and implementation (what gets built)**. The skill's job is to shrink the gap between the author's mental model and the builder's mental model to zero, then prove it with a numeric score.

### The Three-Category Buildability Lens

Every requirement you write must fall into category B. The skill exists to maximize B and eliminate U.

| Category | Definition |
|---|---|
| **B — Buildable** | One developer, no author access, builds one specific thing |
| **D — Debatable** | Multiple valid implementations; developer must make a decision the spec should have made |
| **U — Unbuildable** | Too vague, contradictory, or absent — cannot build without interviewing the author |

Target: **>70% B, <20% D, <10% U** in the final spec. spec-judge measures this directly.

---

## The Process — 6 Phases

The skill body assumes activation already happened — the description handled routing. The phases below describe execution.

### Phase 1 — Classify Size

**Pre-classification gate (AP-14 guard)**: If `<description>` is empty (`/spec` alone), prompt: *"Describe the project, feature, or system in 1–3 sentences and I'll forge a spec for it."* If the description is unspeccable (no problem, no users, no domain signal), do NOT classify — apply the guard: *"This description doesn't have enough signal to spec yet. Before we write requirements, tell me: (1) what problem this solves, (2) for whom, (3) what they do today instead."* Resume Phase 1 only after these are answered. The reason: classifying size from a feature-shaped description that lacks problem-shape produces wrong-tier specs that AP-14 (Discovery Bypass) cannot recover from.

Classify the project as **Small**, **Medium**, or **Large** using the heuristic table. Display your classification and let the user override with one short message before proceeding.

| Signal | Small | Medium | Large |
|---|---|---|---|
| Estimated effort | < 1 week | 1–8 weeks | > 8 weeks |
| User roles | 1–2 | 2–4 | 4+ |
| External integrations | 0–1 | 1–3 | 3+ |
| Teams affected | 1 | 1–2 | 3+ |
| Distinct user journeys | 1–3 | 3–6 | 6+ |
| Example | CLI script, single endpoint | Web feature, mobile screen | Multi-service platform |

Output: `Detected size: **Medium** — feature with ~3 journeys touching 1 external system. Reply 'small' or 'large' to override, or anything else to continue.`

**If the user overrides the size**, recalculate the question budget for the new tier BEFORE entering Phase 2 — a Small→Large override that keeps the Small budget (2–4 questions) produces a Large spec with Small-tier discovery depth that no amount of Phase 5 refinement can fix. Use the new tier's budget from the table below.

Size determines:
- **Question budget**: S = 2–4, M = 5–7, L = 7–10
- **Spec length target**: S = 30–80 lines, M = 100–250, L = 300–600
- **Template variant**: S omits Prior Art / Data / Integration / Scalability / Observability / Accessibility / Browser / Compliance / Revision; M omits Integration & Compliance; L includes everything

### Phase 2 — Discovery (Serial Questioning)

**PREP.md gate (check before everything else).** If a `.specs/NNN-*/PREP.md` exists with `Status: ready for spec` and no `spec.md` beside it, that directory is the spec directory and the interview is already done — do NOT load `references/question-bank.md` at all. Consolidate from the file: every `D-NN` under `## Decisions` is copied verbatim into the spec and never re-asked (if the spec must contradict one, write `[NEEDS CLARIFICATION: conflicts with D-NN]` rather than asking); `## Not this` becomes Section 2.2 Non-Goals verbatim; `## Discretion` items are decided silently by the spec writer and never asked; `## Assumptions` land in the Assumptions table with their confidence; `## Verify` seeds the launch criteria / acceptance; `## Open` items become Open Questions (they already count toward the cap of 3). Gap questions are allowed ONLY for a category PREP.md left genuinely empty. The two consolidate-mode guards below become conditional: ask the negative-scope question only if `## Not this` is empty; run the quantification probe only on adjectives PREP.md did not already quantify. A PREP.md with `Status: interviewing` means prep is unfinished — tell the user to finish `/flow:prep` first and stop.

**MANDATORY — READ ENTIRE FILE (unless the PREP.md gate above fired)**: Load [`references/question-bank.md`](references/question-bank.md) before asking your first question. It contains the 8-category taxonomy, the recommended phrasings, the quantification probes, and the three-step "I don't know" fallback.

**Consolidate-mode gate (check FIRST).** If the spec request arrives with rich context already resolved — a long prior design conversation in this session, or an existing codebase you've explored — do NOT re-interview from scratch. Instead: (a) synthesize a draft answer to each of the 8 categories from the context you already have, (b) show the user a compact "here's what I already know" summary, (c) ask gap-filling questions ONLY for categories the context left genuinely unresolved. This is borrowed from the to-prd philosophy: consolidate resolved understanding rather than re-gathering it. Two guards are non-negotiable even in consolidate mode — you MUST still ask the negative-scope question (rule 5) and MUST still quantify every surviving adjective (rule 4); silent context rarely contains either. If context is thin or absent, skip this gate and run the full serial interview below.

**Rules of engagement** (all non-negotiable):

1. **Serial only.** Ask ONE question per turn. Wait for the answer. Optionally probe with one follow-up before moving on. Never present a numbered list of 4+ questions.
2. **Phase order is fixed.** Anchor (Cat 1: Purpose/Users/Success) → Boundaries (Cat 2 Scope, Cat 3 NFRs) → Depth (Cat 4 Failure, Cat 5 Integration, Cat 6 Constraints, Cat 7 Stakeholders, Cat 8 Acceptance). Asking out of order anchors the conversation to the wrong frame.
3. **ALWAYS recommend an answer with visible reasoning — every question, no exceptions.** Never ask a bare question. Lead with your best-guess answer and the *why* it's drawn from (the description, the domain, common practice), so the user can confirm with one word or correct it: *"For auth, Mr Claude recommends **email + password with magic-link fallback** — it fits a solo-founder MVP with no enterprise SSO need yet. Good, or do you need SSO/social login?"* Format every turn as **Recommendation → reasoning → "confirm or correct?"**. If you genuinely cannot form a recommendation, say so explicitly and offer 2–3 concrete options rather than an open question — a blank "what do you want for X?" is a banned form. Transparent recommendations are help; hidden assumptions are leading questions (still banned — show the why).
4. **Quantify every adjective.** If the user says "fast", "secure", "robust", "scalable", "user-friendly" — ALWAYS follow with the quantification probe from question-bank.md before moving on. Vague adjectives that survive discovery survive into the spec (AP-01).
5. **Always ask the negative scope question.** "What should this explicitly NOT do?" is the highest-leverage underused question. Never skip it (AP-13).
6. **For Medium and Large only**: always ask "Who maintains this after launch, and what does that person know?" (AP-12 guard, structurally orphaned in every other tool).
7. **The "I don't know" fallback (3 steps)**: (a) Offer a default with reasoning, (b) Ask for an order-of-magnitude range, (c) Document as a named assumption with confidence level. Never let "I don't know" terminate a thread.

**The convergence test — when to stop asking**: After every answer, ask yourself: *"Would the answer to my next question change what I'd build or how I'd test it?"* If no, stop questioning and proceed to Phase 3. The stopping signal is convergence, not exhaustion of the budget.

**Hard stop conditions** (force exit from discovery):
- 8 questions asked in M tier or 10 in L tier — proceed even if gaps remain (document gaps as Open Questions in spec)
- User says "just write it" or equivalent — proceed with assumptions flagged
- The 6 secondary stopping signals are all met (see question-bank.md "Enough Heuristic")

### Phase 3 — Draft the Spec

**MANDATORY — READ ENTIRE FILE**: Load [`references/spec-template.md`](references/spec-template.md). This is the canonical output template with all section markers, placeholder syntax, and `<!-- SIZE: X only -->` conditionals. The `<!-- SIZE: X only -->` markers wrap sections that should be INCLUDED only when the matching size variant is being generated — strip the section entirely (markers and content) for any other variant. Fill placeholders from the discovery answers; do not leave any placeholder unfilled in a section that the size variant includes.

**Do NOT load `references/question-bank.md` in this phase** — it was loaded in Phase 2 and re-loading it duplicates ~10K tokens of context that won't be referenced again.

**Where to write the spec**:
- If the PREP.md gate fired, write `spec.md` beside that `PREP.md` in the same `.specs/NNN-<slug>/` directory — never allocate a new number.
- Default: write to `.specs/<NNN>-<feature-slug>/spec.md`, where `<NNN>` is a zero-padded 3-digit sequence (`001`, `002`, …). Compute `<NNN>` by scanning `.specs/` for existing `NNN-*` directories and taking `max + 1` (or `001` if none / the dir doesn't exist yet). Create `.specs/` if absent.
- If the project already uses a `specs/` or `.specify/` directory, follow that existing convention instead: `specs/<NNN>-<feature-slug>/spec.md`
- Always tell the user the path before writing

**Anti-pattern defense — STRUCTURAL not advisory**:

| Anti-pattern | Defended by |
|---|---|
| AP-01 Fog of Adjectives | Quantification probe in Phase 2; rubric will dock D1 if any survive |
| AP-02 Implementation Leak | Template's "no technology names" guard in Section 4.1 — excluded content is routed to code-design.md (Phase 3.5), not discarded |
| AP-03 Wishlist | TL;DR MVP cut line + MoSCoW priorities in FR table |
| AP-04 Happy Path Only | Three-path journey structure (happy + error + edge per journey) |
| AP-05 Missing Actors | User Roles table in 1.2 + every requirement names an actor from it |
| AP-06 NFR Graveyard | Section 5 with 4 (S) / 7 (M) / 9 (L) mandatory NFR sub-sections |
| AP-07 Spec Rot | Last-updated header + Revision History (M/L) |
| AP-08 Wall of Text | TL;DR block delivers everything in first scroll |
| AP-09 Untestable ACs | Given/When/Then table per journey |
| AP-11 Anchored Spec | Assumptions table with validation method column |
| AP-10 Design by Committee | 1.2 Hidden Stakeholders + DRI named in Roles table for Large tier |
| AP-13 Vague Scope | Section 2.2 Non-Goals as binding first-class section |
| AP-15 Tense Chaos | MUST/SHOULD/MAY discipline; Glossary in Appendix A |
| AP-16 Micromanagement | Logical-only Data Requirements (4.2); no algorithmic detail in FRs — the excluded structural detail lands in code-design.md (Phase 3.5), not discarded |

**Open Questions cap**: Maximum 3 unresolved `[NEEDS CLARIFICATION]` markers in the final spec. If the spec has more than 3 unresolved items, tell the user: *"This spec has N open questions, which is above the cap of 3. Either we resolve N−3 of them now, or the spec is premature for planning."* The reason for the cap: a spec with more than 3 unknowns is not a buildability contract — it is a wishlist with placeholders, and refinement can't fix what discovery left out.

### Phase 3.5 — Design

**Test the trigger first.** This phase runs only when two or more of the provisional slices derived below share a name, id type, error shape, module boundary, or resource; **skip it entirely** when the build has one slice, or when no such seam is shared by two or more slices — small builds usually skip because they rarely have 2+ slices sharing a seam, not because of their size tier. The trigger is cross-agent surface, never file count and never the size tier. Determine this from the spec's journeys before loading anything else.

**If the phase is not skipped, MANDATORY — READ ENTIRE FILE**: Load [`references/code-design-doctrine.md`](references/code-design-doctrine.md) and, in the same pass, [`references/pattern-forces.md`](references/pattern-forces.md). Both are orchestrator-only — read once, here, and **never pasted into a subagent prompt**: a slice agent in flow's Phase 4 only ever receives the per-slice contract block this pass cuts, never the doctrine or the force catalogue itself.

**Output**: `.specs/<NNN>-<feature-slug>/code-design.md`, beside `spec.md`, in the same `<NNN>-<feature-slug>` directory Phase 3 just wrote to; this same pass also cuts the per-slice "Contract for this slice" blocks, because the doctrine and the provisional slice list both exist at this moment.

There is no build plan yet at this point in flow-spec — slicing happens later, in `flow-to-issues`. So this pass derives a **provisional slice list** from the spec's journeys (the journey structure `flow/planning.md`'s slicing step already calls the natural slices), counts consuming slices against that list, and records every count as provisional; because the slice list here is provisional, the per-slice contract blocks this pass cuts are provisional too, and once the real slices are known, `flow-to-issues` (or `flow`'s own Phase 3) takes over: it revalidates each provisional count, drops any structure whose consuming-slice count falls below two, and cuts the real per-slice contract blocks from the provisional ones this pass produced.

`code-design.md` is **not a spec** and is never sent to spec-judge (`spec-judge/SKILL.md:3` excludes design docs from scoring); the spec written in Phase 3 is unchanged by this phase — the technology name that would cost the spec D5 points as an implementation leak is **relocated** here, never relaxed there.

This phase makes REST-vs-GraphQL-class decisions on its own judgment and **surfaces** them at the plan-approval gate — it never asks them, because `question-bank.md:262` bans solution-first questions for the stakeholder's sake, not because the decision does not need making.

### Phase 4 — Score with spec-judge

**Do NOT re-load `references/spec-template.md` or `references/question-bank.md` in this phase or in Phase 5.** Both were loaded earlier; re-loading wastes ~25K tokens per iteration and compresses refinement quality across the (max 2) refinement session.

After writing the spec, invoke spec-judge as a subagent.

**Pre-flight check** — verify the spec has no unfilled placeholders (`[SQUARE BRACKETS]` in any section the size variant includes). Running spec-judge on a spec with placeholders produces artificially low D2/D3 scores and wastes a refinement iteration. If placeholders remain, re-enter Phase 3 to fill them as Open Questions or named assumptions before scoring.

**If spec-judge is not installed** at `${CLAUDE_PLUGIN_ROOT}/skills/spec-judge/SKILL.md`: do not fail silently. Tell the user *"spec-judge skill is not installed; skipping automated scoring. The spec is at <path>. Install spec-judge to enable iterative refinement."* Then exit the loop. Do not attempt to self-score against the rubric — that defeats the independent-judge property.

**Spawn a Task agent** (`subagent_type: general-purpose`, `model: sonnet`, `mode: bypassPermissions` — required because spec-judge reads files outside the project directory). Before spawning, perform these substitutions in the prompt below:

- Replace `<ABSOLUTE-SPEC-PATH>` with the absolute path of the spec file written in Phase 3
- Replace `<TIER>` with the size classification from Phase 1 (literal `Small`, `Medium`, or `Large`)
- Replace `<N>` with the current iteration number (1 for first pass, 2+ for refinements)
- Replace `<SPEC-DIR>` with the directory containing the spec file

```
You are evaluating a spec for quality.

FIRST: Read the spec-judge skill at:
${CLAUDE_PLUGIN_ROOT}/skills/spec-judge/SKILL.md

THEN: Read and evaluate the spec at:
<ABSOLUTE-SPEC-PATH>

Follow the spec-judge evaluation protocol EXACTLY:
1. First Pass — Buildability Scan (categorize each requirement B/D/U)
2. Structure Analysis (the 11-item checklist)
3. Score all 8 dimensions with quoted evidence
4. Calculate total and grade
5. Generate the report

Apply the size-tier calibration: this is a <TIER> spec.
Refer to spec-judge's size-calibration table for relaxed thresholds.

Write the complete evaluation report to:
<SPEC-DIR>/spec-judge-iteration-<N>.md

Be ruthless. Top 3 Improvements must be specific and actionable, not generic advice.
Do NOT mention any prior iteration scores — score this spec cold.
```

Parse the resulting report. Extract:
- Total score (X/120) and letter grade
- Per-dimension scores
- Top 3 Improvements (verbatim)
- Critical Issues
- Buildability ratio

**If the report file does not exist or cannot be parsed** (subagent crashed, missing fields, malformed score): show the user *"spec-judge returned a malformed report — see <path>. Spec is at <path>. Recommend either re-running spec-judge manually or accepting the spec as-is."* and exit the loop. Do not invent a score; do not retry without telling the user.

### Phase 5 — Refinement Loop

Apply the judge's feedback and re-score. Loop until ONE of:

| Condition | Action |
|---|---|
| Score ≥ 96/120 (B+ or A) | **Ship it.** Show the trajectory and final report. |
| Score delta < 3 between iterations | **Diminishing returns.** Show the trajectory; offer to ship OR iterate on the **single lowest absolute-score dimension** (not the lowest delta). A dimension at 7/15 has more available headroom than one at 13/15 — picking by absolute score wins more points per iteration. |
| 2 iterations completed | **Hard cap.** Ship with caveats explicitly stated. |

**Diagnose before refining** — different low dimensions need different responses:

| Low dimension | Likely cause | Fix |
|---|---|---|
| D1 Clarity | Vague adjectives survived discovery | Re-quantify them with the probe; rewrite the offending requirements |
| D2 Completeness | Missing sections or symmetry pairs | Check the size-variant section list; add what's missing |
| D3 Testability | ACs describe intent not behavior | Rewrite as Given/When/Then with observable outcomes |
| D4 NFR Coverage | Sub-sections marked N/A without justification | Re-ask Cat 3 questions; convert each adjective to a number |
| D5 Structural | Compound requirements or tech leakage | Split "and" requirements; remove technology names |
| D6 Form | Inconsistent modal verbs or missing actors | Apply MUST/SHOULD/MAY discipline; name an actor per requirement |
| D7 Traceability | No MVP cut line or priorities | Add MoSCoW labels; write the cut line statement |
| D8 Error/Edge | Happy-path:error ratio > 5:1 | Add error path to each journey; expand Section 5.4 |

**Score regression rule**: If iteration N+1 scores LOWER than iteration N, the refinement broke something. Diff the two specs, restore what was working, apply changes more surgically.

**Track the trajectory**:
```
.specs/
└── <NNN>-<feature-slug>/
    ├── spec.md                              ← the latest spec
    ├── spec-judge-iteration-1.md
    ├── spec-judge-iteration-2.md
    └── spec-judge-iteration-3.md
```

---

## Output to the User

After convergence, present:

1. **Path to the final spec** (clickable file link)
2. **Score trajectory**: `Iteration 1: 73 → 2: 88 → 3: 97 (A)` 
3. **Final grade and verdict** (one sentence from the judge's Summary)
4. **What changed across iterations** (1-line diff per iteration)
5. **Remaining gaps** (if score < 108): name them and offer to address now or accept

If the user's last reply was just "ship it" or equivalent, suppress the trajectory and just show the path + grade.

**Then ALWAYS end with the next step (so the user doesn't have to remember the flow):**

> **Next in the flow:** the spec is ready. Phase 3.5 already ran alongside it — if the build had 2+ slices sharing a seam, `code-design.md` is sitting beside the spec so each slice subagent inherits those structural decisions instead of inventing its own; otherwise Phase 3.5 skipped itself and there's nothing to inherit. Run **`/flow-to-issues`** to slice the spec into tracer-bullet, AFK/HITL-tagged build issues. (Flow: `flow-spec → code-design.md → flow-to-issues → flow-feature`, with `flow-handoff` giving each issue its own fresh session.) Want Mr Claude to run `/flow-to-issues` now?

---

## NEVER Do

Each rule states the prohibition AND the non-obvious failure mode it prevents. The WHY is what makes the rule load-bearing instead of stylistic.

- **NEVER** write the spec before discovery completes — even one missing answer in Phase 1 (Anchor) invalidates everything downstream because Phase 2/3 questions assume the anchor is set; missing it means you're asking about scope of an undefined system.

- **NEVER** batch more than 3 questions per turn (exception: the Phase 1 framing burst) — batching triggers list-answering mode where stakeholders answer the easy questions and silently skip the hard ones. The skipped questions are always the ones that would change the spec the most.

- **NEVER** accept a vague adjective without the quantification probe — a vague adjective that survives discovery survives into the spec, where spec-judge's D1 will dock points and force another iteration. The cost compounds, not adds: each surviving adjective creates one ambiguity AND one iteration of rework.

- **NEVER** skip the negative-scope question ("what should this NOT do?") — it is the single most asymmetric question in requirements: 10 seconds to ask, prevents weeks of scope-creep arguments. Skipping it is the AP-13 (Vague Scope Incubator) signature.

- **NEVER** skip "who maintains this?" for Medium or Large specs — the answer determines architecture: a system maintained by a non-technical owner needs radically different design than one owned by a DevOps team. The question is structurally orphaned in every other tool, which is exactly why missing it leads to undocumented constraints.

- **NEVER** leave a placeholder unfilled in a section the size variant includes — running spec-judge with `[BRACKET]` placeholders left in produces artificially low D2/D3 scores that waste a refinement iteration on a phantom problem. Fill from discovery, mark as named assumption with confidence "Low", or list as Open Question.

- **NEVER** present the spec to the user without running spec-judge at least once — the score is the contract that distinguishes "I wrote a spec" from "I forged a spec". An unscored spec hides whether discovery succeeded or failed.

- **NEVER** continue the refinement loop past 2 iterations — after 2 iterations, residual gaps almost always trace back to discovery failures (missing stakeholder, untranslated adjective, unspoken constraint) that no amount of drafting can fix. The correct action at the cap is to restart Phase 2 on the failing dimension, not to keep refining text.

- **NEVER** continue past a score regression (iteration N+1 < iteration N) — regression means your refinement broke something that was working. Diff the two specs, restore what was working, apply the next change more surgically. Mechanical re-application of judge feedback is how you regress.

- **NEVER** invent a number for an NFR the user couldn't quantify — invented numbers feel authoritative to the implementer and bypass validation. Document as named assumption with confidence "Low" and a stated validation method so the developer knows to test it.

- **NEVER** ask the Cat 8 acceptance-criteria questions before Cat 1–4 are answered — early acceptance questions produce vague answers ("when it works") because the system isn't defined yet. Cat 8 is last in the question taxonomy by design; asking out of order produces stub ACs that survive into the spec.

- **NEVER** copy a stack, architecture, or constraint set from a prior project without re-asking — inherited assumptions are the AP-11 (Anchored Spec) trap. The new project's stakeholders may have different needs that the old constraints silently violate.

- **NEVER** treat spec-judge's score as ground truth without sanity check — if the judge scores D3 (Testability) low but discovery produced legitimate ACs, the spec may need restructuring (move the ACs into the journey table) rather than content addition. Blind compliance with the judge can degrade quality.

- **NEVER** rewrite the entire spec in response to judge feedback — wholesale rewrites fix the dimension the judge flagged while silently erasing coverage in dimensions that were already passing. The result is sideways motion or regression. Apply changes to the smallest scope that addresses the cited evidence: edit a single requirement, replace a single adjective, add a single missing section. Diff your edit against what was working before committing it.

- **NEVER** re-ask a decision recorded as a `D-NN` in PREP.md — the user already made it; re-asking teaches them the file is decorative and the interview was wasted, and a second answer that differs silently forks the record. Contradict it only via a `[NEEDS CLARIFICATION: conflicts with D-NN]` marker.
