---
name: spec-judge
description: "Evaluate software/product spec quality across 8 dimensions, scoring out of 120 (IEEE 29148, INVEST, SMART, Wiegers, EARS). Produces score, letter grade A-F, Buildability ratio B:D:U, and Top 3 Improvements with quoted evidence. Calibrates against Small/Medium/Large tiers. Also runs ISSUE-BREAKDOWN MODE (caller passes MODE: issue-breakdown) scoring a tracer-bullet vertical-slice issue plan out of 100 across 5 dimensions: vertical integrity, AFK/HITL classification accuracy, dependency soundness, spec coverage, and INVEST granularity. Use when: (1) /flow:spec invokes this as a refinement-loop subagent, (2) user runs /spec-judge directly on a path, (3) a PRD, SRS, requirements doc, or user-story spec needs pre-implementation quality audit, (4) user asks \"is this spec ready to build from?\", \"rate/score/judge this spec\", \"review spec\", \"audit requirements\", or \"score the slices\". Do NOT use for design docs, architecture docs, or code reviews — those are not specs."
---

# Spec Judge

Evaluate software specifications against 8 quality dimensions derived from IEEE 29148, INVEST, SMART-NFR, Karl Wiegers' requirements quality framework, and EARS syntax. Be ruthless: a spec that scores high on this rubric is one a developer can build from without interviewing the author.

---

## Core Philosophy

### What a Spec Is — and Is Not

A spec is **NOT**:
- A design document (that describes HOW to build)
- A feature wishlist (that lists what people want)
- A PRD-as-political-artifact (that justifies a roadmap decision)
- A vision statement (that paints the future)

A spec **IS** a **buildability contract**: the minimum information a developer needs to build one specific thing — not many possible things — and the minimum information a QA engineer needs to write a test that passes or fails deterministically.

> **Karl Wiegers' test**: *"If you cannot describe the expected system response, the requirement is not a requirement."*

The art of a good spec: maximize **observable behavior specified** while stripping every **premature implementation choice** the developer should be free to make based on professional judgment.

### The Core Formula

```
Good Spec = Observable Behaviors specified − Implementation Choices embedded
```

- **Observable behavior**: something a QA engineer can write a test for without interviewing the author
- **Implementation choice**: technology names, algorithmic approaches, data structures, UI pixel values, framework selections

Both directions are defects:
- **Under-specification**: the developer makes decisions the spec should have made → wrong system gets built
- **Over-specification**: the developer's professional judgment is removed → brittle, expensive system gets built

The rubric penalizes both.

### The Three Requirement Categories — Apply to Every Requirement

| Category | Definition | Treatment |
|---|---|---|
| **B — Buildable** | A developer reads this and builds one specific thing | Keep — this is the spec's value |
| **D — Debatable** | A developer reads this and could build 2–3 valid things | Fix before shipping to development |
| **U — Unbuildable** | Cannot build from this — too vague, contradictory, or missing | Must fix — blocks implementation |

Quality bands by Buildability ratio:
- **Good**: >70% B, <20% D, <10% U
- **Mediocre**: 40–70% B, high D (decisions deferred to developers)
- **Bad**: <40% B, high U (cannot build without re-interviewing the author)

The First Pass scan applies this classification to every requirement before any dimension is scored.

### Size Calibration

Specs serve different scopes. A 50-line spec for a CLI tool and a 500-line spec for a platform must be judged against different baselines or the rubric is unfair.

| Tier | Effort | Roles | Integrations | Length target | Rubric note |
|---|---|---|---|---|---|
| **Small** | <1wk | 1–2 | 0–1 | 30–80 lines | Relax D4/D5/D6/D7 passing thresholds |
| **Medium** | 1–8wk | 2–4 | 1–3 | 100–250 lines | Apply full rubric — this is the design point |
| **Large** | >8wk | 4+ | 3+ | 300–600 lines | Extend D4 (require 7+ NFR categories); D7 mandatory MoSCoW |

When invoked, the caller should pass the size tier. If not provided, infer from the spec's content (line count, role count, NFR sub-section count) and note your inferred tier in the report.

**Calibration table** — passing thresholds within each dimension by tier:

| Dim | Small passes at | Medium passes at | Large passes at |
|---|---|---|---|
| D1 Clarity (20) | 16 (full) | 16 (full) | 16 (full) |
| D2 Completeness (20) | 16 (full) | 16 (full) | 16 (full) |
| D3 Testability (18) | 14 (full) | 14 (full) | 14 (full) |
| D4 NFR (16) | 8 (≥2 categories) | 12 (≥4) | 13 (≥7) |
| D5 Structural (12) | 8 | 10 (full) | 10 (full) |
| D6 Form (12) | 8 | 10 (full) | 10 (full) |
| D7 Traceability (14) | 8 | 11 (full) | 14 (MoSCoW required) |
| D8 Error/Edge (10) | 8 (full) | 8 (full) | 8 (full) |

---

## Evaluation Dimensions

The rubric totals 120 points across 8 dimensions, weighted by failure-cost evidence from Karl Wiegers and the IEEE 29148 quality attribute literature. **D1 (Clarity & Unambiguity) is THE CORE DIMENSION** — pervasive ambiguity is the root failure mode of specs (35% of all defects per the literature).

---

### D1: Clarity & Unambiguity (20 points) — THE CORE DIMENSION

**Core question**: *Can a developer who has never spoken to the author read this spec and have exactly one valid interpretation of every requirement?*

**Detection techniques**:
- Vague quality adjectives — grep for: fast, slow, secure, robust, scalable, user-friendly, intuitive, easy, simple, modern, clean, responsive
- Passive voice hiding actors ("the data is processed" vs "the API processes the data")
- "and/or" constructs (always a defect)
- Ambiguous pronouns without referents ("it shall persist", "this is required")
- Modal strength confusion — "should" used where "shall" is meant
- Hedge words: "typically", "as appropriate", "where necessary", "when feasible"
- Missing comparison baselines ("faster" — than what?)

**Scoring bands**:

| Score | Criteria | Evidence Pattern |
|---|---|---|
| 19–20 | Zero vague adjectives without measurement; consistent modal usage; every pronoun has a clear referent; no hedge words | Quote 5+ requirements showing precise, unambiguous language |
| 15–18 | 1–2 minor ambiguities (single hedge word in context) but core requirements unambiguous | Quote 1–2 minor issues, confirm core is clean |
| 10–14 | 3–5 ambiguous adjectives or constructs; mixed modal discipline | Quote ≥3 instances of ambiguous language |
| 5–9 | Multiple instances of "fast/secure/easy" without thresholds; passive voice throughout | Show pattern of recurring ambiguity |
| 0–4 | Spec is dominated by vague language; cannot determine intent for most requirements | Show the spec is essentially aspirational prose |

**Zero-score triggers**:
- 3+ instances of "user-friendly", "intuitive", or "easy" without measurement criteria → cap D1 at 8
- All performance NFRs lack numeric thresholds → cap at 6
- Consistent use of "should" where "shall" is clearly meant → cap at 10
- "and/or" appears anywhere → automatic −2

**Worked example — bad → good**:
- ❌ "The system shall be fast and easy to use."
- ✅ "FR-007: The dashboard MUST render the initial KPI panel in <500ms at p95 for the 90% of users on broadband (>10Mbps), measured by the existing RUM beacon (`dashboard.initial_render_ms`)."

---

### D2: Completeness (20 points)

**Core question**: *Does the spec cover all the territory it claims to cover? Are there obvious gaps a reader can identify without domain expertise?*

Three layers of completeness to evaluate:
1. **Functional completeness** — every claimed feature has requirements beneath it
2. **NFR completeness** — does the spec address NFRs at all? (D4 evaluates the quality of those NFRs separately)
3. **Boundary completeness** — is scope explicitly stated, including non-goals?

**Detection techniques**:
- Count TBD / TODO / [NEEDS CLARIFICATION] / placeholder markers
- Symmetry check: login↔logout, create↔delete, enable↔disable, subscribe↔unsubscribe — pair absence is a red flag
- Named-epics-without-requirements scan (epic title appears but no FR-NNN beneath it)
- Coverage of stated user journeys (each journey listed → does it have ACs?)
- Scope section presence (in-scope AND out-of-scope explicit?)

**Scoring bands**:

| Score | Criteria | Evidence Pattern |
|---|---|---|
| 19–20 | Zero TBDs; explicit scope + non-goals; all symmetry pairs present; every named feature has FRs | Confirm scope statement, count FRs per epic, note absence of TBDs |
| 15–18 | 1 TBD or 1 minor symmetry gap; scope present | Quote the gap |
| 10–14 | 2–3 TBDs OR scope stated only positively (no non-goals) OR 1 named feature has no requirements | Quote each gap |
| 5–9 | Many TBDs OR no scope section OR feature list without acceptance criteria | Show pattern of incompleteness |
| 0–4 | Spec is bullet ideas with no requirements; or fewer than 5 concrete verifiable requirements for non-trivial system | Confirm stub status |

**Zero-score triggers**:
- Bullet list of feature ideas without acceptance criteria → cap at 4
- Named feature with zero requirements in body → cap at 8
- For Medium/Large: no Non-Goals section → cap at 12
- `[NEEDS CLARIFICATION]` or `TBD` count > 3 → cap at 10

---

### D3: Testability & Verifiability (18 points)

**Core question**: *Can a QA engineer write a test case for every requirement directly from the spec text, without interviewing the author?*

**The Wiegers test**: For each requirement, attempt to write a test. If you cannot describe the expected system response, the requirement is not testable. Sample 5 requirements.

**Testability hierarchy** (IEEE 29148): test (executable check) → demonstration (behavioral observation) → analysis (calculation) → inspection (manual review). Higher = better.

**Detection techniques**:
- Acceptance criteria presence per user story (count stories with vs. without ACs)
- AC quality scan: does it describe **observable behavior** or **intent/feeling**?
- NFR threshold presence (numeric or qualitative?)
- Sample 5 requirements and run the write-a-test exercise mentally

**Scoring bands**:

| Score | Criteria | Evidence Pattern |
|---|---|---|
| 17–18 | Every requirement directly testable; ACs in Given/When/Then or equivalent; all NFRs quantitative | Run write-a-test on 3 requirements, all pass |
| 13–16 | >80% testable; minor untestable requirements (could be reformulated) | Quote 1–2 untestable items |
| 9–12 | 50–80% testable; multiple untestable NFRs | Quote pattern of non-testable items |
| 5–8 | <50% testable; ACs describe intent ("user feels confident") not observable behavior | Show the gap is structural |
| 0–4 | No acceptance criteria anywhere, all NFRs qualitative | Confirm spec is intent-only |

**Zero-score triggers**:
- No acceptance criteria anywhere in spec → cap at 4
- All NFRs are qualitative adjectives → cap at 6
- "Shall never fail" or equivalent absolutes → −2 each (untestable)

---

### D4: NFR Coverage & Quality (16 points)

**Core question**: *Does the spec address non-functional qualities, and do those requirements meet the SMART standard?*

**Why separate from D2**: a spec with no NFRs can still be internally consistent (high D2, D5). NFR absence is a distinct, high-cost failure mode (60–80% of software rework cost per CMU SEI).

**SMART test per NFR**:
- **S**pecific (names component and user class)
- **M**easurable (numeric threshold)
- **A**chievable (consistent with known tech)
- **R**elevant (real stakeholder concern, not boilerplate)
- **T**ime-bound (load condition or environment specified)

**Minimum coverage set** (Medium tier):
1. Performance (latency, throughput targets)
2. Security (auth + authorization)
3. Reliability/availability (uptime or fault tolerance)
4. Error handling (system behavior on failure)

**Extended set** (Large tier): add observability, accessibility, data retention, browser/platform support, compliance.

**Scoring bands** (by category count + SMART quality):

| Score | Criteria | Evidence Pattern |
|---|---|---|
| 15–16 | All minimum categories present; ≥80% pass SMART; for Large, 7+ categories | Quote NFRs from each category showing SMART compliance |
| 12–14 | All minimum categories present; some lack 1–2 SMART attributes | Quote weak NFRs |
| 8–11 | 2–3 categories present; mixed SMART quality | Note missing categories |
| 4–7 | 1 category present OR all NFRs qualitative | Note critical gaps |
| 0–3 | No NFR section OR purely functional spec with zero NFRs | Confirm absence |

**Zero-score triggers**:
- Purely functional spec, no NFRs anywhere → cap at 2
- System handles user data or auth but no security NFR → cap at 6
- All performance targets are adjectives ("fast") → cap at 8
- For Large tier: fewer than 4 NFR categories → cap at 10

**Domain calibration**: "2 seconds" is excellent for a reporting dashboard, unacceptable for a trading system. Infer domain from spec content; if no signal, calibrate against general consumer-web baseline and note the assumption in the report.

---

### D5: Structural Integrity (12 points)

**Core question**: *Are requirements atomic, non-contradictory, non-redundant, and organized so changes can be made cleanly?*

**Sub-criteria**:
- **Atomicity**: requirements describe ONE behavior, not "X and Y" compounded
- **Internal consistency**: no contradictions; no terminology drift (same concept = same name)
- **Non-redundancy**: behaviors aren't restated under different IDs
- **Organization**: requirements have unique IDs; logical grouping
- **Implementation freedom**: no premature technology lock-in

**Detection techniques**:
- Compound "and" scan in requirement bodies (FR-007: "MUST authenticate AND log the event AND notify admin" → split needed)
- Contradiction scan: requirement X says A; requirement Y says NOT A
- Technology-name scan: PostgreSQL, React, Redis, Lambda, S3 in requirement bodies
- ID presence: every requirement has FR-NNN, AC-NNN, NFR-NNN, or equivalent
- Terminology consistency: "user", "customer", "account" used distinctly or interchangeably?

**Implementation-leak test**: *"If we used different technology to achieve this, would the requirement still be satisfied?"*
- ✅ "The system shall use TLS 1.3 for all API communications" — security CONSTRAINT, acceptable
- ❌ "The system shall use PostgreSQL for user storage" — implementation LEAK

**Scoring bands**:

| Score | Criteria | Evidence Pattern |
|---|---|---|
| 11–12 | Atomic; no contradictions; all IDs present; consistent terms; zero implementation leaks | Quote 3 well-formed requirements |
| 9–10 | 1–2 compound requirements OR 1 minor terminology drift | Quote the issues |
| 6–8 | Multiple compound requirements OR 1 contradiction OR ≥2 terminology issues | Show pattern |
| 3–5 | Frequent compound requirements; terminology chaos; some implementation leaks | Show structural breakdown |
| 0–2 | Directly contradictory unresolved requirements; no IDs; spec is unstructured prose | Confirm unbuildable |

**Zero-score triggers**:
- Directly contradictory requirements (unresolved) → cap at 4
- No unique identifiers of any kind → cap at 6
- Technology name in 3+ requirements → −3 (implementation leakage pattern)

---

### D6: Story / Requirement Form (12 points)

**Core question**: *Do requirements follow a recognized well-formed structure that makes intent unambiguous and scope clear?*

**EARS patterns** (Easy Approach to Requirements Syntax):
1. **Ubiquitous**: "The system shall <action>"
2. **State-driven**: "While <state>, the system shall <action>"
3. **Event-driven**: "When <trigger>, the system shall <action>"
4. **Optional feature**: "Where <feature is included>, the system shall <action>"
5. **Unwanted behavior**: "If <undesired event>, then the system shall <response>" *(positive indicator for D8 too)*

**INVEST for user stories** (text-evaluable parts):
- **V**aluable — clear user benefit stated (the "so that" clause)
- **S**mall — implementable in one sprint
- **T**estable — has acceptance criteria

I (Independent) and E (Estimable) require team context — exclude from text-only evaluation.

**As-a-I-want-So-that completeness**: actor / goal / rationale. The "so that" clause is most frequently omitted.

**Modal verb discipline**:
- shall = mandatory (defect if absent)
- should = strong preference
- may = optional
- will = describes future state, doesn't obligate

**Scoring bands**:

| Score | Criteria | Evidence Pattern |
|---|---|---|
| 11–12 | Consistent EARS or user-story format; clear actor in every requirement; correct modal usage; "so that" present in stories | Quote 3 well-formed examples |
| 9–10 | Consistent format; 1–2 modal slips OR missing "so that" in some stories | Quote slips |
| 6–8 | Mixed format; multiple actor omissions; modal soup (shall/will/should used interchangeably) | Show pattern |
| 3–5 | No consistent form; many requirements as bare statements without actor | Show structural failure |
| 0–2 | Spec is paragraph prose with no extractable distinct requirements | Confirm unbuildable |

**Zero-score triggers**:
- Spec is entirely prose with no requirement format → cap at 4
- No actors named anywhere → cap at 6
- Modal verbs used inconsistently throughout (will/shall/should mixed without policy) → −2

**Hybrid-format note**: A spec that consistently mixes user stories with "The system shall…" requirements is treated as equivalent to a consistently applied pure format. The defect is INCONSISTENT mixing, not the mix itself.

---

### D7: Traceability & Prioritization (14 points)

**Core question**: *Can every requirement be tracked to a source/objective and ranked by importance?*

**Traceability in spec context**: backward linkage to the spec's own stated goals — does the spec list its objectives such that a reader can verify requirements address them?

**Priority signals**:
- MoSCoW (Must/Should/Could/Won't)
- P1/P2/P3
- MUST/SHOULD/MAY in requirement bodies
- Explicit ordering with rationale
- MVP cut line (TL;DR statement)

**Detection techniques**:
- Unique IDs present per requirement
- Priority markers per requirement
- "Stated goals" vs "requirements" linkage
- For Large tier: MoSCoW or equivalent MANDATORY

**Scoring bands**:

| Score | Criteria | Evidence Pattern |
|---|---|---|
| 13–14 | Unique IDs; explicit priorities per requirement; MVP cut line present; goals→requirements traceable; Large: MoSCoW present | Quote priority + ID examples; show MVP boundary |
| 10–12 | IDs present; priorities present but inconsistent; MVP boundary inferable | Note inconsistencies |
| 7–9 | IDs present but no priority markers OR priorities present without IDs | Note the gap |
| 4–6 | No priority structure; no MVP boundary; goals not explicit | Show pattern of missing structure |
| 0–3 | No IDs, no priorities, no goals — flat list of features | Confirm wishlist status |

**Zero-score triggers**:
- No requirement IDs of any kind → cap at 4
- For Large tier: no MoSCoW or equivalent → cap at 8
- Bullet list of features with no priorities → cap at 6 (the AP-03 Wishlist signature)

**Note**: This dimension cannot evaluate whether the RIGHT goals were chosen — only whether requirements link to STATED goals.

---

### D8: Error & Edge Case Coverage (10 points)

**Core question**: *Does the spec tell implementers what the system should do when things go wrong?*

**Why separate from D2**: D2 (Completeness) measures coverage of named features. D8 measures coverage of the space OUTSIDE normal operation.

**Six error/edge categories to look for**:
1. Invalid input handling
2. Service / external dependency failure
3. Resource exhaustion (rate limits, quotas, storage)
4. Security / authorization failures (unauthorized, expired token)
5. Boundary conditions (empty list, max length, zero, negative)
6. Concurrent access conflicts (race conditions, conflicting writes)

**EARS unwanted-behavior pattern as positive indicator**: presence of "If <undesired event>, then the system shall <response>" requirements signals D8 awareness.

**Happy-path:error-path ratio heuristic**:
- 2:1 to 3:1 → good
- >5:1 → suspect
- >10:1 → systematic omission

**Scoring bands**:

| Score | Criteria | Evidence Pattern |
|---|---|---|
| 9–10 | All 6 categories present where applicable; ratio ≤3:1; explicit "what user sees" per error | Quote error paths from each journey |
| 7–8 | 4–5 categories present; ratio 3:1 to 5:1 | Note missing categories |
| 4–6 | 2–3 categories; ratio 5:1 to 10:1; happy-path-dominated | Show the gap |
| 1–3 | 0–1 error category; "shall never fail" type absolutes | Show absence |
| 0 | Zero error/edge requirements; happy path only | Confirm AP-04 |

**Zero-score triggers**:
- System handles user auth but contains zero auth-failure handling → cap at 4
- API integration but no failure / timeout / retry specification → cap at 4
- Happy-path:error ratio > 10:1 → cap at 4

---

## NEVER Do When Evaluating

- **NEVER** give high D1 scores because "shall" is used consistently — form without measurable thresholds is still ambiguous
- **NEVER** penalize a short spec for apparent incompleteness when its stated scope is genuinely small — calibrate against claimed scope and size tier, not absolute requirement count
- **NEVER** ignore missing NFRs because "that's covered in the architecture doc" — the spec must stand alone
- **NEVER** forgive "and/or" with "the intent is clear from context" — it is always a defect
- **NEVER** treat passive voice as merely a stylistic choice — it hides missing actors that will generate rework
- **NEVER** credit acceptance criteria that describe intent ("user feels confident") as if they describe observable behavior
- **NEVER** accept TBD sections as "work in progress" — they are acknowledged incompleteness gaps that block a real score
- **NEVER** let a well-structured spec fool you into assuming its requirements are testable — run the write-a-test check on a sample
- **NEVER** penalize API specs for including HTTP methods, response schemas, or error codes — for the API domain that IS specification, not implementation leakage

---

## Evaluation Protocol — 5 Steps

### Step 1: First Pass — Buildability Scan

Read the spec completely. For each requirement (FR-NNN, AC-NNN, NFR-NNN, or equivalent), categorize:

- **[B] Buildable** — one developer, no author access, builds one specific thing
- **[D] Debatable** — multiple valid implementations; developer must make a decision the spec should have made
- **[U] Unbuildable** — too vague, contradictory, or absent; cannot build without re-interviewing the author

Compute the ratio. Note during the scan:
- TBD / TODO / [NEEDS CLARIFICATION] count
- Vague-adjective count (fast, user-friendly, robust, intuitive, etc.)
- Passive-voice instances
- Acceptance-criteria presence per user story
- Approximate happy-path:error-path ratio

### Step 2: Structure Analysis

Mechanical checklist:

```
[ ] Executive summary or TL;DR present
[ ] Total approximate requirement count
[ ] TBD / TODO / placeholder marker count
[ ] Spec format identified (story-based / IEEE-style / hybrid / stub)
[ ] User roles defined (table or named list)
[ ] NFR section present + sub-section count
[ ] Priority markers present (MoSCoW, P1/P2/P3, MUST/SHOULD/MAY)
[ ] Scope / non-goals section present
[ ] Requirement IDs present
[ ] Approximate happy-path : error-path ratio
[ ] Modal verb consistency (shall vs should vs will vs may)
```

### Step 3: Score Each Dimension

For D1 through D8:
1. Find specific evidence — **quote or cite the requirement(s) that justify the score**
2. Assign the score with one-line justification
3. Note specific improvements if score is below 80% of the dimension's max

### Step 4: Calculate Total & Grade

```
Total = D1 + D2 + D3 + D4 + D5 + D6 + D7 + D8
Max = 120 points
```

**Grade Scale**:

| Grade | Score | Meaning |
|---|---|---|
| A | 108–120 (90%+) | Production-ready spec — build from this |
| B | 96–107 (80–89%) | Good spec — minor gaps, low implementation risk |
| C | 84–95 (70–79%) | Adequate spec — known gaps, medium risk |
| D | 72–83 (60–69%) | Below average — significant ambiguity or missing coverage |
| F | <72 (<60%) | Cannot be built from — stub or fundamentally broken |

### Step 5: Generate Report (template below)

---

## Report Template

This is the standardized output format. Both invocation modes produce this format identically.

```markdown
# Spec Evaluation Report: [Spec Name / File Path]

## Summary
- **Total Score**: X/120 (X%)
- **Grade**: [A/B/C/D/F]
- **Size Tier**: [Small / Medium / Large] (passed / inferred)
- **Spec Format**: [Story-based / IEEE-format / Hybrid / Stub]
- **Buildability Ratio**: B:D:U = X:Y:Z
- **TBD Count**: X (unresolved)
- **Happy-Path:Error Ratio**: ~X:1
- **Verdict**: [One sentence. Brutally honest. E.g.: "Functional requirements are buildable but NFRs are absent and error handling is missing — this will generate constant rework during development."]

## Dimension Scores

| Dimension | Score | Max | Notes |
|-----------|-------|-----|-------|
| D1: Clarity & Unambiguity | X | 20 | |
| D2: Completeness | X | 20 | |
| D3: Testability & Verifiability | X | 18 | |
| D4: NFR Coverage & Quality | X | 16 | |
| D5: Structural Integrity | X | 12 | |
| D6: Story/Requirement Form | X | 12 | |
| D7: Traceability & Prioritization | X | 14 | |
| D8: Error & Edge Case Coverage | X | 10 | |
| **Total** | **X** | **120** | |

## Critical Issues
[Must-fix problems. Only items that materially block implementation or testing. No softening, no "consider".]

## Top 3 Improvements
1. [Highest-impact improvement with specific, actionable guidance — tell them exactly what to fix and how. Quote the offending requirement.]
2. [Second priority]
3. [Third priority]

## Detected Anti-Patterns
[List any of the 9 Common Failure Patterns detected, with severity (Critical/High/Medium) and the requirement that triggered detection.]

## Detailed Analysis
[Only include dimensions that scored below 80% of their max. For each:
- What evidence led to the score
- Specific quoted/cited requirements that are the problem
- Concrete suggestion for fixing the specific evidence cited]
```

---

## Common Failure Patterns

Nine named patterns drawn from the practitioner anti-pattern catalog. Detect during the First Pass and report in the Detected Anti-Patterns section.

### Pattern 1: The Fog of Adjectives (AP-01) — Critical
- **Symptom**: "fast", "user-friendly", "robust", "secure" used repeatedly without measurement criteria
- **Root cause**: stakeholder language ("we want it to be fast") survives discovery and lands in the spec untranslated
- **Fix**: Replace each adjective with a SMART NFR. *"Fast"* → *"<200ms p95 response time at 1000 concurrent users measured by APM tool X"*

### Pattern 2: The Happy Path Spec (AP-04) — Critical
- **Symptom**: every journey describes the success case; error states, empty states, timeouts unmentioned. Happy:error ratio > 10:1.
- **Root cause**: stakeholders naturally describe success; analysts assume error handling is "obvious"
- **Fix**: For every primary action, specify what happens on invalid input, dependency failure, auth failure, and resource exhaustion. EARS unwanted-behavior pattern: *"If <X fails>, then the system shall <Y>."*

### Pattern 3: The NFR Graveyard (AP-06) — Critical
- **Symptom**: spec is purely functional; NFR section absent or contains 1 vague item
- **Root cause**: NFRs aren't part of stakeholder language; teams assume they're implied; structural prompt absent
- **Fix**: Mandatory NFR section with sub-sections for performance, security, reliability, error handling at minimum. Each must be SMART. "Not applicable" must be an explicit decision, not an omission.

### Pattern 4: The Untestable Criterion (AP-09) — High
- **Symptom**: acceptance criteria describe intent ("user feels confident", "the system is reliable") not observable behavior
- **Root cause**: ACs written before testability check; "would I be able to write a passing/failing test?" was never asked
- **Fix**: Rewrite each AC as Given/When/Then with a specific observable outcome. *"User feels confident"* → *"Given login completes, when user lands on dashboard, then a 'Welcome back' banner is visible for 3 seconds and `auth.success` event is emitted."*

### Pattern 5: The Missing Actor (AP-05) — High
- **Symptom**: passive voice throughout — "the data is processed", "the request shall be validated"
- **Root cause**: writer focuses on system behavior without attributing it; passive voice masks the omission
- **Fix**: Every requirement must name an actor (user role from Section 1.2 OR "the System" explicitly). Rewrite passive into active: *"The Validation Service MUST reject requests where field X is missing."*

### Pattern 6: The Wishlist (AP-03) — High
- **Symptom**: 30+ unprioritized features listed as bullets; no MVP boundary; everything is "important"
- **Root cause**: scope discipline absent; stakeholder requests accumulated without prioritization
- **Fix**: Apply MoSCoW (Must/Should/Could/Won't) to every requirement. State the MVP cut line explicitly. Move "Should/Could" to a backlog section.

### Pattern 7: The Implementation Leak (AP-02) — Medium
- **Symptom**: technology names in requirement bodies — PostgreSQL, React, Redis, S3 — when the WHAT is what's needed
- **Root cause**: writer encodes the assumed implementation as a constraint; locks in choices the developer should make
- **Fix**: Apply the implementation-leak test: *"If we used different technology to achieve this, would the requirement still be satisfied?"* If yes, remove the technology name. Move legitimate constraints (TLS 1.3, must use existing auth service) to Section 7.1 with rationale.

### Pattern 8: The Tense Soup (AP-15) — Medium
- **Symptom**: "shall", "should", "will", "must", "may" used interchangeably without a glossary stating their meaning
- **Root cause**: modal-verb policy absent; each writer uses preferred phrasing
- **Fix**: Establish modal verb policy in the Glossary: shall=mandatory, should=desired, may=optional, will=describes future state. Apply consistently. Use MUST/SHOULD/MAY explicitly in tables.

### Pattern 9: The Scope Creep Incubator (AP-13) — High
- **Symptom**: scope stated only positively; no Non-Goals section; ambiguous edges between this feature and adjacent ones
- **Root cause**: negative scope feels rude or premature; positive scope is easier to write
- **Fix**: Mandatory Non-Goals section with binding statement. List 3+ specific things the feature does NOT do. Place it before the requirements section (high in document, not buried).

---

## Quick Reference Checklist

```
┌─────────────────────────────────────────────────────────────────────────┐
│  SPEC EVALUATION QUICK CHECK                                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  CLARITY (D1 — most important):                                         │
│    [ ] No vague quality adjectives without measurement thresholds       │
│    [ ] No "and/or" constructs                                           │
│    [ ] All actors named (no passive voice hiding who does what)         │
│    [ ] "shall" vs "should" vs "may" used with consistent meaning        │
│    [ ] No hedge phrases (as appropriate, where necessary, typically)    │
│                                                                         │
│  COMPLETENESS (D2):                                                     │
│    [ ] Zero TBD / TODO / [NEEDS CLARIFICATION] markers                  │
│    [ ] All named epics/features have requirements beneath them          │
│    [ ] Natural symmetry pairs accounted for (create/delete, login/out)  │
│    [ ] Explicit scope/non-goals section present                         │
│                                                                         │
│  TESTABILITY (D3):                                                      │
│    [ ] Every user story has acceptance criteria                         │
│    [ ] Acceptance criteria describe observable outcomes, not intent     │
│    [ ] "Write a test" check passes for sampled requirements             │
│                                                                         │
│  NFRs (D4):                                                             │
│    [ ] Performance: latency target with numeric threshold + load cond.  │
│    [ ] Security: auth mechanism and authorization model named           │
│    [ ] Reliability: uptime target or fault tolerance approach           │
│    [ ] Error handling: system behavior on failure named                 │
│                                                                         │
│  STRUCTURE (D5):                                                        │
│    [ ] Requirements are atomic (no compound "and" linking behaviors)    │
│    [ ] No contradictions between requirements                           │
│    [ ] Consistent terminology (no synonym drift)                        │
│    [ ] No unjustified implementation choices in requirements            │
│                                                                         │
│  FORM (D6):                                                             │
│    [ ] Consistent requirement format throughout                         │
│    [ ] "As a... so that..." includes the "so that" clause               │
│    [ ] Conditional requirements have explicit trigger conditions        │
│                                                                         │
│  TRACEABILITY (D7):                                                     │
│    [ ] Requirements have unique IDs                                     │
│    [ ] Priority markers present (MoSCoW or equivalent)                  │
│    [ ] Stated goals exist; requirements link to them                    │
│    [ ] MVP cut line stated (Large tier: MoSCoW mandatory)               │
│                                                                         │
│  ERROR COVERAGE (D8):                                                   │
│    [ ] Invalid input handling specified                                 │
│    [ ] Service/dependency failure handling present                      │
│    [ ] Happy-path : error-path ratio below 5:1                          │
│    [ ] Auth failure handling if system uses authentication              │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Issue-Breakdown Mode (Tracer-Bullet + AFK)

When invoked on an **issue breakdown** (a task list such as a `TASKS.md`, or a legacy `plan.md` / `issues/*.md` set) instead of a raw spec, switch to this rubric. The caller will say `MODE: issue-breakdown`. Score out of 100 across 5 dimensions. Be just as ruthless: a breakdown that scores high is one where an agent can pick up any AFK issue and ship it end-to-end without a human.

### What a tracer-bullet vertical slice IS

A tracer bullet is the **thinnest possible cut through every layer** that produces observable end-to-end behavior. "User can create the simplest possible record and see it persist" touches UI + API + storage in one issue. The next slice adds *one* field, or *one* validation, end-to-end. Each issue, when merged, leaves the system **demoable and one capability richer**.

### The horizontal-masquerade detector — THE CORE CHECK

The #1 failure is a horizontal breakdown wearing vertical clothing. Catch it:

| Smell | Verdict |
|---|---|
| Issue titles name **layers/artifacts**: "Create database schema", "Build the API endpoints", "Add the UI", "Write the tests" | HORIZONTAL — fail D-Slice hard |
| An issue, merged alone, produces **no behavior a user/QA can observe** (it only "enables" later issues) | HORIZONTAL — that's a layer, not a slice |
| Dependency chain is one straight line where each issue is a different tech layer of the *same* feature | HORIZONTAL |
| Issue titles name **user capabilities**: "User can submit an empty form and see a validation error" | VERTICAL — good |
| Each issue has acceptance criteria phrased as observable behavior, traceable to a spec journey | VERTICAL — good |

Litmus test for every issue: *"If we merged ONLY this issue and stopped, could a QA engineer run a test that passes?"* No → it's horizontal; dock D-Slice and name the offending issues verbatim.

### What makes AFK classification GOOD

- **AFK** (agent-friendly, no human): requirements are fully specified, acceptance criteria are deterministic, no new product/UX/architecture decision is required, no ambiguous trade-off. The agent has everything it needs in the spec + issue.
- **HITL** (human-in-the-loop): the issue hides an unmade decision — visual/UX design, an architectural fork, an external-credential or policy call, an irreversible/destructive action, or a `[NEEDS CLARIFICATION]` the spec never resolved.
- A breakdown that tags everything AFK is **lying** — flag any issue that requires judgment but is marked AFK. A breakdown that tags everything HITL is **useless** — the point is to maximize safe autonomy. Good breakdowns justify each HITL with the *specific* decision the human must make.

### The 5 dimensions (100 pts)

| Dim | Points | Core question |
|---|---|---|
| **D-Slice — Vertical Integrity** | 35 | Is every issue an end-to-end tracer bullet, or are any horizontal layers? (Apply the detector above. This is the core dimension — a horizontal breakdown caps total at 50.) |
| **D-AFK — Classification Accuracy** | 20 | Is each AFK/HITL tag correct, with each HITL naming its specific blocking decision? |
| **D-Dep — Dependency Soundness** | 15 | Does every `depends-on` resolve to a real issue? Is the order acyclic and shippable incrementally? |
| **D-Trace — Spec Coverage** | 20 | Does every spec journey/requirement map to ≥1 issue, and every issue's ACs trace back to the spec? No orphans either direction. |
| **D-Gran — Granularity (INVEST)** | 10 | Is each issue Independent, Negotiable, Valuable, Estimable, Small, Testable? Flag mega-issues (>~7 ACs) and trivial fragments. |

Report format mirrors the spec report: total `X/100`, per-dimension scores with **quoted offending issue titles**, and **Top 3 Improvements** (verbatim, actionable). Name every horizontal issue explicitly — the caller will re-slice them.

---

## Minimum-Spec Refusal

If the spec contains fewer than 5 distinct verifiable requirements, do NOT score. Instead return:

> **Stub — insufficient requirements to evaluate.** Minimum 5 verifiable requirements needed for meaningful scoring. Spec contains only [N] items, most of which are [feature ideas / aspirational statements / TBDs]. Recommend completing discovery (use the flow-spec skill) before re-submitting for evaluation.

---

## The Meta-Question

When uncertain about a score, return to this:

> **"Could a developer who has never spoken to the spec author**
> **build the same system as a developer who attended every stakeholder meeting?"**

If yes → the spec has done its job.
If no → it contains decisions that belong in the spec but aren't there.

The best specs are **buildability contracts** — they transfer the full intent of the author's mental model to the builder's, with zero dependency on the author being present.

---

## Self-Evaluation

This skill should pass its own rubric:

- **D1 Clarity**: frontmatter description has exactly one interpretation of when to invoke; modal verbs (MUST/NEVER) used consistently
- **D2 Completeness**: covers both invocation paths (subagent and direct), all 8 dimensions, the grade scale, the report format, and the minimum-spec refusal case
- **D3 Testability**: report template produces machine-parseable output (score is a number, grade is a letter, ratio is computable — all verifiable)
- **D4 NFR**: not directly applicable to a Skill, but the skill states its own scope boundaries (refuses to score stubs, calibrates by tier)
- **D5 Structural**: dimensions are atomic (each evaluates one quality), non-contradictory, IDs present (D1–D8)
- **D6 Form**: consistent imperative-voice section structure throughout
- **D7 Traceability**: invocation triggers explicit; rubric dimensions linked to detection techniques and worked examples
- **D8 Error/Edge**: NEVER rules cover the failure modes that would corrupt the evaluation; minimum-spec refusal handles the unscoreable case

Calibration exercise: evaluate this Skill against the 8 dimensions to test the rubric is internally consistent before applying to user specs.
