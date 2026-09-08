---
name: question-bank
description: 8-category question taxonomy for flow-spec's discovery phase, in impact-first order. Includes example phrasings, the quantification probe for vague adjectives, the three-step "I don't know" fallback, and the convergence-based stopping heuristic. Load this entire file before asking the first discovery question.
---

# Spec-Forge Question Bank

The discovery phase of flow-spec is the load-bearing innovation: questions are asked BEFORE drafting, not after. The questions below are ordered by impact-if-missed, grouped into three phases, and calibrated by size tier.

---

## Phase Order — Non-Negotiable

```
PHASE 1 — ANCHOR              → Cat 1 (Purpose, Users, Success)
PHASE 2 — BOUNDARIES          → Cat 2 (Scope), Cat 3 (NFRs)
PHASE 3 — DEPTH (as needed)   → Cat 4 (Failure), Cat 5 (Integration),
                                 Cat 6 (Constraints), Cat 7 (Stakeholders),
                                 Cat 8 (Acceptance)
```

A wrong answer in Phase 1 invalidates everything downstream. If you cannot get clear answers to Cat 1, STOP — produce a problem-framing document, not a spec.

Always ask the negative scope question (Cat 2). It is the highest-leverage underused question — 10 seconds to ask, prevents weeks of rework.

For Medium and Large tiers, always ask "Who maintains this after launch, and what does that person know?" (in Cat 6). It is structurally orphaned in every other tool.

---

## Question Budget by Size Tier

| Tier | Min | Max | Notes |
|---|---|---|---|
| Small | 2 | 4 | Cat 1 only if description is detailed; add Cat 4 + Cat 6 if not. Skip Cat 7 unless multiple stakeholders implied. |
| Medium | 5 | 7 | All Cat 1–4 mandatory; add Cat 5/6/8 if signals present. |
| Large | 7 | 10 | All Cat 1–8 mandatory; multi-pass if needed. |

Beyond these caps, defer remaining gaps to Open Questions in the spec.

---

## Category 1 — Purpose, Users, Success Criteria  (Anchor)

**What it surfaces**: The real problem (vs. the stated solution), who actually uses it, what "done well" looks like measurably.

**Why non-obvious**: Stakeholders describe solutions, not problems. "I need a dashboard" hides "I need to know if my team is behind before standups."

**Question bank** (pick 1–3, ask serially or in a labeled framing burst of ≤3):

- "What problem are we actually trying to solve?" *(always ask before anything else)*
- "What happens today if we do nothing?" *(reveals urgency)*
- "Who is actually going to use this — daily, hands-on?" *(distinguish requester from user)*
- "What does success look like in 6 months?" *(surfaces measurable outcome expectations)*
- "What would make this project a failure even if it ships on time?" *(exposes hidden criteria)*
- *JTBD probe*: "When did you first realize you needed this? What were you doing? What were you using before?"

**Phase 1 framing burst exception**: For a cold context, you may ask three Cat 1 questions in one turn IF labeled as a set: *"To shape this spec, I need to anchor on three things: (1) what problem this solves, (2) who uses it daily, (3) what success looks like in 6 months. Take them in any order."*

---

## Category 2 — Scope Boundaries & Exclusions  (Boundaries)

**What it surfaces**: What the system will NOT do — more clarifying than what it WILL do.

**Why non-obvious**: Scope is almost always defined positively. Negative scope is rare but far more protective.

**Question bank**:

- **"What should this system explicitly NOT do?"** *(MANDATORY — never skip; the highest-leverage underused question)*
- "What related problems are you deliberately leaving for later or for a different system?"
- "If a user tries to do [adjacent thing], what should happen?"
- "Is there anything you're assuming is included that we haven't discussed?"
- "Are there existing tools or systems that handle any part of this — should we integrate, replace, or ignore them?"

---

## Category 3 — Non-Functional Requirements  (Boundaries)

**What it surfaces**: Performance, concurrency, security, accessibility, reliability, compliance.

**Why non-obvious**: Stakeholders think "fast" and "secure". Translating those adjectives into testable numbers is YOUR job — but you have to surface them first.

**Question bank** (pick 1–3 most relevant; never accept a vague adjective):

- "How many users do you expect at peak? How many total?"
- "What response delay would cause a user to give up or call support?" *(performance target)*
- "What's the longest acceptable downtime in a given month?" *(reliability/SLA)*
- "Who has access to this data, and who must be prevented from seeing it?" *(security posture)*
- "Does this need to meet any compliance requirements — GDPR, HIPAA, SOC 2, WCAG?"
- "Should this work for users with disabilities — screen readers, keyboard-only navigation?"
- "What's the maximum amount of data this will need to handle at once?" *(scale)*

**Most commonly missed NFRs** (probe explicitly if not raised):
- **Observability** — logging, metrics, tracing. Almost never mentioned. *"What does your team need to see in logs/metrics to debug this in production?"*
- **Accessibility** — assumed implied. *"What accessibility standard applies — WCAG 2.1 AA, or none formally?"*
- **Data retention/deletion** — *"How long is this data kept? What triggers deletion?"*

---

## The Quantification Probe — MANDATORY

When a stakeholder uses any of these words: **fast, slow, secure, reliable, robust, scalable, user-friendly, intuitive, easy, simple, responsive, modern, clean** — ALWAYS follow with the probe before moving on.

**Probe template**:
> "[Adjective] compared to what? Slower/less than what would be unacceptable? Tied to what business outcome?"

**Concrete examples**:
- *"Fast"* → "Slower than what would cause users to give up? Are we talking sub-100ms or sub-2-second?"
- *"Secure"* → "Secure against what — credential theft, data exposure, denial of service? What's the highest-risk vector?"
- *"Reliable"* → "Reliable enough that what business process would break if it failed? Aiming for two-nines, three-nines, four-nines?"
- *"User-friendly"* → "Friendly to whom — first-time users, power users, accessibility users? What task should they complete without help?"

A vague adjective that survives discovery survives into the spec (AP-01) and survives into the rubric where D1 will dock points heavily.

---

## Category 4 — Failure Modes & Edge Cases  (Depth)

**What it surfaces**: What the system does when things go wrong. Often consumes 60–80% of implementation effort.

**Why non-obvious**: Stakeholders describe the happy path. The high-yield question is about KNOWN failures in the current system, not hypothetical ones.

**Question bank**:

- **"Where does this usually break in the current system or process?"** *(highest-yield failure question)*
- "What should happen if the input is wrong or missing?"
- "What if two users try to do the same thing simultaneously?" *(concurrency)*
- "What happens when a downstream service is unavailable?" *(dependency failure)*
- "What should definitely not happen, ever?" *(hard constraints — security, data corruption, money)*
- "What do users do today when this breaks, and is that still acceptable?"

**5 Whys**: useful for tracing known recurring problems to root cause. Avoid for speculative or multi-causal scenarios — answers become theoretical after ~3 Whys.

---

## Category 5 — Integration Points & External Dependencies  (Depth)

**What it surfaces**: What other systems this connects to, who owns them, what happens on failure.

**Why non-obvious**: Integration is usually stated as "it connects to X" without auth, data volume, latency tolerance, ownership, or failure behavior. Each is independent risk.

**Question bank**:

- "What existing systems must this read from or write to?"
- "Who owns those systems? Who would we call if the integration breaks?"
- "What data formats are in play? Are there existing APIs or will new ones need to be built?"
- "What happens in this system if [external service] goes down for an hour?"
- "Are there any data import/export requirements — CSV, webhooks, third-party sync?"
- "Does this need to authenticate against an existing identity provider, or is auth standalone?"

**Per-dependency probe**: For each integration, capture (a) owner, (b) failure behavior, (c) retry/fallback expectation. These go into Section 4.3 Integration Requirements and Section 5.4 Error Handling.

---

## Category 6 — Constraints & Technical Boundaries  (Depth)

**What it surfaces**: Tech decisions already made, budget/time limits, team capability, explicitly rejected alternatives.

**Why non-obvious**: Constraints are often treated as embarrassing limitations and go unstated. Undisclosed constraints are the most reliable source of rework.

**Question bank**:

- "Is there an existing tech stack this must use or integrate with?"
- "Where will this be deployed — cloud, on-premise, specific vendor?"
- "Are there team skill constraints that affect what we can build?"
- "What approaches have already been ruled out, and why?"
- "Is there a budget ceiling that would change scope if crossed?"
- **"Who will maintain this after launch, and what does that person know?"** *(MANDATORY for Medium and Large)*
- "Does this need to run in a regulated environment that constrains technology choices?"

The maintenance/ownership probe is the most commonly skipped question in the literature. A system maintained by a non-technical user needs a radically different design than one maintained by a DevOps team.

---

## Category 7 — Stakeholders & Decision Authority  (Depth)

**What it surfaces**: Real users vs. requester, veto holders, hidden stakeholders (support, compliance, downstream consumers), competing priorities.

**Why non-obvious**: The requester is rarely the user. Hidden stakeholders often have requirements that contradict the primary requester's wants.

**Question bank** (Medium and Large only, unless solo Small):

- "Who will actually use this system day-to-day? Are they the same as who requested it?"
- "Who else will be affected — even if they don't use it directly?" *(hidden stakeholders)*
- "Who has the authority to say the requirements are correct?" *(DRI)*
- "Are there teams or systems that consume the outputs downstream?"
- "Are there regulatory bodies, auditors, or compliance teams who would care about this?"
- "If two stakeholder groups want different things, who breaks the tie?"

---

## Category 8 — Completion & Acceptance Criteria  (Depth)

**What it surfaces**: What "done" looks like in testable terms, post-launch metrics, rollback triggers.

**Why non-obvious**: This category is LAST because it can only be answered well after the others are addressed. "How will we know it's done?" too early produces "when it works."

**Question bank**:

- "For each major feature, how would you test that it works correctly?"
- "What is the minimum viable version — what is the first thing that has to work?"
- "What metrics will you track in the first 3 months after launch?"
- "What would cause you to roll back or shut this down after deploying?"
- "Can you describe a scenario where this ships, looks like it works, but actually fails your real need?"

If the stakeholder cannot give a specific example of when a feature works correctly, the requirement is not understood yet — re-probe Cat 1 or Cat 4.

---

## When the User Says "I Don't Know" — Three-Step Fallback

Never let "I don't know" terminate a thread. Apply in order:

**Step 1 — Offer a default with reasoning**:
> "If we had to choose now, the safest default is X — because [reason from context]. Is that acceptable, or would it definitely need to be different?"

**Step 2 — Ask for an order-of-magnitude range**:
> "Even a rough order of magnitude helps — are we talking about 10 users, 1,000, or 10 million?"

**Step 3 — Document as a named assumption**:
> "I'll document this as 'A-NNN: assumed X unless corrected, confidence: Low' so the developer knows to validate it. You can update it once you know more."

The named assumption goes into Section 7.2 of the spec with confidence "Low" and a stated validation method.

---

## When to Stop Asking — The Convergence Test

After every answer, ask yourself: *"Would the answer to my next question change what I'd build or how I'd test it?"*

- **Yes** → ask it
- **No** → defer it to planning, or skip; proceed to drafting

This is the single most powerful filter. Most questions that feel important don't actually change architecture, data model, test design, or deployment.

### Six Secondary Stopping Signals — Stop When ALL Are True

1. You can write the happy-path narrative unambiguously — who does what, in what order, with what outcome
2. You can name the three most likely failure modes and state what should happen in each
3. You can state at least two NFRs in testable form (e.g., "<200ms response at p95" or "WCAG 2.1 AA")
4. You have identified who builds it, who uses it, who maintains it, and who approves it
5. You can articulate what is NOT in scope with specific examples
6. The stakeholder's most recent answers are CONFIRMING (yes, that's right) rather than EXPANDING (and also...)

### Anti-Signals — Keep Asking When ANY Are True

- Any NFR is still described with a vague adjective without a number
- You don't know who the real users are vs. who asked for the project
- No one has mentioned failure handling, error states, or exception paths
- The scope boundary is described only positively (what it does) with no negatives
- Integration points are named but their failure modes are unaddressed
- "Who maintains this?" has never been answered (Medium/Large only)

### The Metacognitive Check (before closing)

Before stopping, ask yourself: *"Is there anything I haven't asked because I assumed the answer? Is there a question I'm afraid to ask because the answer might complicate the spec?"* If yes to either: ask it.

---

## Anti-Patterns in Questioning — NEVER Do

1. **Solution-first questions** (*"Should we use REST or GraphQL?"*) — asks the stakeholder to make a technical decision they're not equipped to make. Better: *"What kinds of data does this expose, and how often does it change?"*

2. **Leading questions** (*"This should be mobile-first, right?"*) — encodes your assumption as the default; most stakeholders agree rather than contradict. Better: *"What devices will users primarily access this from?"*

3. **Vague adjective acceptance** — accepting "fast and secure" and moving on. Always run the quantification probe.

4. **The feature-list trap** (*"What features do you want?"*) — produces solutions, not requirements. Better: *"Walk me through how you do this today."*

5. **Excessive 5 Whys** — past 3 Whys, answers become theoretical. Better: *"What were you doing when you first realized you needed this?"*

6. **Batching more than 3 questions in one turn** — triggers list-answering mode (shallow, skip-the-hard-ones). Exception: the Phase 1 framing burst.

7. **Skipping the negative-scope question** — the single most asymmetric question in requirements. Always ask it.

8. **Treating "I don't know" as a dead end** — apply the three-step fallback.

9. **Asking without permission to follow up** — the highest-leverage technique is the follow-up. Stakeholders reveal more in response to their own words than to prepared questions.
