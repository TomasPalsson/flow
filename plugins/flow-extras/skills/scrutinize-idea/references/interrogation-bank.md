---
name: interrogation-bank
description: The question arsenal for the Interrogate phase — bias tells mapped to the question that exposes each, plus verbatim killer questions from YC, Sequoia, Amazon, and CIA red teams. Load during Phase 1.
---

# Interrogation Bank

Pick the 3–5 sharpest questions for *this* idea — don't fire all of them. Lead with whatever targets the load-bearing assumption. **Every question demands a factual answer — a number, a name, a specific.** Accepting "good point, we'll look into it" is a failure; note the dodge and re-ask.

---

## Part A — Bias tells → the question that exposes each

Watch *how* the idea is described. The linguistic tell tells you which bias is live; the question makes the bias load-bearing instead of deniable. Ordered by lethality.

| Bias | Tell in how it's described | Exposing question |
|------|---------------------------|-------------------|
| **Survivorship** (most lethal) | Validation = only successful companies ("Uber did it, so…"); failures invisible | "Name five who tried a version of this and died. For each: the specific failure mode, and why it doesn't apply to you." |
| **Planning fallacy** | Best-case timeline units ("3 months to MVP"), no buffers, scope treated as fixed | "Your last three comparable projects — what was actual-time ÷ estimated-time? Apply that ratio here." |
| **Optimism bias** | "Conservative estimate", "even if we only get 1%…" (where 1% is still huge); downside absent | "Give me the *median* outcome for this type of venture — a number, not a description." |
| **Confirmation bias** | Cited evidence all supports; contradicting data absent or strawmanned; uniformly positive customer quotes | "Show me the three strongest pieces of evidence *against* this. What did you do with each?" |
| **Sunk cost** | "We've already built / spent…" offered as a reason to continue | "Starting today from zero, would you choose this exact approach? If not, what would you do instead?" |
| **Narrative fallacy** | Suspiciously smooth origin story; causation asserted from correlation; story beats data | "Strip the story out. State the evidence as bullets: what signal, from whom, what sample size, collected how?" |
| **Availability** | Problem feels big because *they* felt it; market sized from personal circle | "How many people *outside your network* confirmed this problem, and how did you reach them?" |
| **Anchoring** | First number (market size, valuation) dominates; never stress-tested | "Where did that number come from? What happens to the model if it's 3× lower? 10×?" |
| **Endowment / IKEA effect** | Over-attachment to a specific implementation an outsider would call generic ("the algorithm is the secret sauce") | "If a well-funded team cloned exactly what you have today, which part could they NOT replicate — and why?" |
| **Dunning–Kruger (domain)** | Deep/regulated domain described as "surprisingly simple once you get it" | "Who's the most skeptical *expert* in this domain you've talked to? What did they say? Can we talk to them?" |
| **Base-rate neglect** | No reference to category success rates, typical CAC/LTV, sales-cycle norms | "What's the base rate of success for this market + stage + team profile, and where's that number from?" |

---

## Part B — The institutional killer questions

These are verbatim from the people whose job is killing weak ideas. The cross-cutting logic of all of them: **force the burden of proof onto the idea.**

### Timing — "Why now?" (Sequoia)
- "What specific, *dated* enabler exists today that didn't two years ago?" (A macro-trend like "AI is big" is a fail. Name a regulation, a price drop, a capability threshold.)
- "Why hasn't someone already done this?" — and if they have, the graveyard question.
- An idea buildable three years ago with no new tailwind fails this test.

### The bear case (Amazon PR-FAQ — the single most diagnostic question)
- **"What are the top three reasons this will NOT succeed?"** Make them build the bear case in their own words, in writing.
- "What solutions exist today, and why would anyone switch?"
- "How many people have this problem *and* will pay to solve it?"
- "What's the per-unit economics, and when does it turn profitable?"

### Assumptions (CIA Key Assumptions Check)
- "What has to be true for this to work?" → then attack the weakest of those.
- "Which single assumption, if wrong, most changes the conclusion?"
- "Why are you confident that assumption holds?"

### Evidence quality (CIA Analysis of Competing Hypotheses)
- "What evidence here would look *different* if the idea were wrong?" (diagnostic vs non-diagnostic)
- "If a competitor planted evidence to make this look good, would you be able to tell?"
- "What are you *not* looking for, and why not?"

### Moat & competition (VC / YC)
- "What stops a well-funded competitor from copying this in 12 months?" ("Great UX" is not a moat.)
- "Which competitor — current or future — do you fear most?"
- "Salesforce/Google/[incumbent] could build this in six months. Why won't they, or why won't it matter if they do?"

### Founder / proposer fit (YC)
- "Why are you uniquely qualified to solve this — not just to *care* about it?" ("5 years in the space" is not an answer.)
- "What did you ship last week?" (velocity, not plans)
- "What experiments have you already killed?" (real flexibility vs. "we're open to pivoting")
- "What do you know about this market that others don't?" (If the answer could appear in an industry report, there's no insight.)

### Verdict-forcing close
- "What would change your mind about this? What evidence would make you abandon it?" (If nothing would, it's a belief, not a plan — and that's the finding.)

---

## How to run the interrogation

1. Diagnose which 2–3 biases are live from the tells, and pull their exposing questions.
2. Add the 1–2 institutional questions that hit the load-bearing assumption (usually "why now", the bear case, or the graveyard).
3. Fire them. Hold each open until answered with specifics.
4. Their *non-answers* are data: a dodged graveyard question, a "why now" with no dated enabler, an inability to name what would change their mind — each is itself a finding to carry into the verdict.
