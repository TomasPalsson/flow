---
name: attack-frameworks
description: Operational step-by-step procedures for the Attack phase of idea scrutiny — load-bearing assumption isolation, diagnostic-evidence filtering, reference-class base rates, the graveyard technique, inversion, pre-mortem, falsifiability, and second-order effects. Load during Phase 2.
---

# Attack Frameworks — Operational Procedures

These are procedures to *run*, not concepts to recite. Sequence for a maximum-adversary pass: steelman (done in Phase 0) → load-bearing assumption → diagnostic evidence → base rates / graveyard → inversion → second-order → falsifiability. Stop early if you hit a fatal flaw — once the load-bearing assumption is shown to be unsupported, the rest is moot and you should say so.

---

## 1. Load-bearing assumption + the Negation Test (start here)

The single highest-leverage move. Most ideas have one assumption they cannot survive losing; find it and aim everything there. Peripheral critique is noise by comparison.

1. List every assumption the idea rests on — **including the implicit ones**. The implicit ones are deadlier: explicit assumptions get monitored because they're known; the catastrophic failures come from premises nobody noticed they were assuming.
2. **Negation Test** on each: assume it is *false*. Does the argument still stand? If negating it collapses the idea, it is load-bearing.
3. **Bridge question** for hidden premises: "What must be true — but is nowhere stated — for this evidence to support this conclusion?"
4. Rank load-bearing assumptions, then check each for **vulnerability**: an assumption can be load-bearing *and* obviously true (don't waste fire there). Your target is the one that is **both load-bearing AND poorly evidenced.**
5. Attack it. If it falls, the critique is terminal — the idea needs rebuilding from that point, and you should say exactly that.

**Failure mode:** identifying the load-bearing assumption and stopping. "This is load-bearing" without "and here's why it's unsupported" is half a critique.

---

## 2. The diagnostic-evidence filter (the evidence-quality test)

From CIA's Analysis of Competing Hypotheses, and identical to the Bayesian likelihood-ratio test — two research threads converged on this, so trust it.

For each piece of evidence the proposer offers, ask:

> **"Would this evidence look the same even if the idea were wrong?"**

- If **yes** → it is **non-diagnostic**. It feels like support but discriminates nothing. A success story, a positive customer quote, an enthusiastic anecdote — these usually exist whether or not the idea is sound (likelihood ratio ≈ 1). Pile up a hundred and you've still learned nothing.
- If **no** (the evidence would look different in the failure world) → it is **diagnostic**. This is the only kind that should move your verdict.

The proposer's case is usually built on a tall stack of non-diagnostic confirming evidence. Name it: "Everything you've shown me is consistent with this working *and* with this failing. What evidence would distinguish the two?"

---

## 3. Reference-class base rates (the outside view)

Defeats the inside view — the proposer's focus on their specific plan instead of how comparable efforts actually turned out.

1. **Pick the reference class:** a category of *past, completed* cases genuinely comparable to this idea. Broad enough for ≥20–30 cases, narrow enough to be relevant. Use actual outcomes, not proposals.
2. **Get the distribution:** base success rate, median outcome, worst case. (Flyvbjerg's verified anchor for projects: ~9/10 infrastructure projects run over budget — rail +44.7% avg. Most categories have a brutal base rate the proposer is ignoring.)
3. **Position this case:** "Is there a *specific, evidenced* reason this beats the reference-class average?" Apply a high burden of proof. "Ours is different because…" is the inside view sneaking back in.

**Novel idea, no reference class?** Use the closest *structural* analog (a novel consumer-subscription app still uses consumer-subscription base rates), or flag that the base rate is unknown and make that uncertainty itself the finding.

---

## 4. The graveyard technique (survivorship bias killer)

The internet is structurally optimized to show you survivors — every case study and "how we grew to $10M" post is a survivor; the thousands who died silently are the invisible denominator.

1. **Frame the search:** "Who tried [approach X] in [market Y] in [window Z]?"
2. **Search the cemetery, not the hall of fame:** "[type] shut down / closed / pivot", Crunchbase "Closed", CB Insights R.I.P. lists, dead YC batches, "Killed By Google"-style sites, trade-press obituaries.
3. **Categorize each failure:** demand / distribution / timing / execution / competition / unit-economics / regulation.
4. **Demand a mechanism, not a story:** for each failure mode, the proposer must say *specifically* why their version avoids it. "The market's different now" doesn't count — require evidence the relevant thing actually changed, not that it *could*.

**Counterintuitive:** a proposer who found 1–2 failures and rebutted them is **more** dangerous than one who found none — they feel inoculated and stop looking. Your job is to find the third and fourth graveyard entries they didn't, because the ones they know about are the ones they've prepared answers for.

**Empty graveyard?** Rarely "it's genuinely novel." Usually "the category name changed (search synonyms)" or "they didn't look hard enough." An empty graveyard with no hypothesis for *why* it's empty is a red flag, not a green light.

---

## 5. Inversion (map the failure modes)

Munger, via Jacobi: "Invert, always invert." Easier and more reliable than enumerating success paths, because success needs many things to go right while failure needs only one to go wrong.

1. State the success condition explicitly. Flip to: "this fails if ___."
2. For each dimension (assumptions, dependencies, execution, market, human behavior, timing) ask: "what single thing, if wrong, destroys this?"
3. Ask the optimism-bias flusher: **"If this fails, what will the post-mortem say was obvious in hindsight?"**
4. Apply the asymmetry check: does the upside need many things to align while the downside needs only one to break? If so, the odds are structurally worse than they look.

Inversion maps *risk shape*, it does not deliver a verdict — an idea can have severe-but-low-probability failure modes and still be worth doing. Don't catastrophize every failure mode into a veto; weight by probability.

---

## 6. Pre-mortem (the past-tense move)

For plans with execution risk. The power is in the **grammar**, not the discussion: prospective hindsight (past tense) shifts the brain from prediction into explanation and improves cause-identification ~30%.

Set the frame precisely: *"It is 18 months from now. This has completely, spectacularly failed — total collapse, not a stumble. You're looking back. What happened?"* Then enumerate causes in past tense. The conditional version ("what *might* go wrong?") just regurgitates known risks and defeats the purpose. (Solo works — the past-tense framing is the mechanism; a group only adds breadth.)

---

## 7. Falsifiability (is the idea even testable?)

1. Force the criterion: "What specific, observable outcome would prove this idea wrong?"
2. **Anything-explains-everything trap:** if every possible outcome is claimed as confirmation ("works → proves it; fails → also proves it"), it's unfalsifiable.
3. **Ad hoc immunization:** when hit with disconfirming evidence, does the idea sprout a new auxiliary excuse? One is fine; a *pattern* of escape clauses means it's been made unfalsifiable by accumulation.

Caveat: unfalsifiable ≠ false. Some true claims (ethics, long-horizon, genuinely novel) are hard to falsify. The test diagnoses *testability*; flag the difficulty, don't use it as a trump card to dismiss.

---

## 8. Second-order effects ("…and then what?")

First-level thinking stops at the immediate effect. Push further:

1. State the first-order effect. For each, ask "and then what?" — twice more (three levels is the practical ceiling; beyond that is speculation dressed as analysis).
2. **Ecosystem response:** how do competitors, regulators, incumbents, and users *adapt* once this exists? Ideas that look great first-order often trigger second-order responses that erase the first-order gain.
3. **Reversibility:** at what point do effects become irreversible? Irreversibility sharply raises the cost of being wrong.

---

## 9. Hitchens's razor / burden of proof (keep it pointed the right way)

"What is asserted without evidence can be dismissed without evidence." The burden is on the claimant, not on you.

- Split claims from evidence into two columns. Match the evidentiary bar to the stakes — extraordinary claims need extraordinary evidence.
- **Watch the inversion** (the most common abuse): the proposer tries to make *you* prove the idea is false. You don't have to. You're entitled to *suspend belief* in an unsupported claim — though note the limit: "no evidence presented" licenses suspending belief, not asserting the claim is false. Stay precise about which you're doing.
