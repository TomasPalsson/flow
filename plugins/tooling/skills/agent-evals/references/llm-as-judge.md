---
name: llm-as-judge
description: How to build, validate, and operate an LLM-as-a-judge — modes, the full bias-to-mitigation table, the meta-evaluation/validation loop, rubric and prompt design, and a judge prompt template. Load before building, validating, or debugging any model-graded eval.
---

# LLM-as-a-Judge

A judge is a measurement instrument that approximates human review at ~500–5,000× lower cost. Built well and validated, it hits ~80–85% agreement with experts. Built and trusted blind, it produces **false confidence** — the single worst outcome in evals. **An unvalidated judge is worse than no eval.**

## Modes

| Mode | What it does | Best for | Watch out |
|------|--------------|----------|-----------|
| **Pointwise / direct** | score one output on a rubric | objective checks, prod monitoring w/o reference | score instability; leniency clustering |
| **Binary pass/fail** | pointwise special case → pass/fail (or pass/partial/fail) | gates, guardrails, regression tests | coarse by design (that's the point) |
| **Pairwise** | pick better of two | A/B of prompts/models, subjective qualities | quadratic cost; position bias; *more* gameable via distractor features |
| **Reference-guided** | score with gold answer/context provided | RAG faithfulness, factual QA | needs references; can degrade to fuzzy matching |
| **Rubric decomposition (G-Eval)** | split into binary assertions, score each, aggregate | auditable holistic quality | more calls; needs domain criteria |
| **Panel (PoLL)** | majority vote of 3+ diverse-family judges | high-stakes; bias reduction | 3–8× cost (but can beat one GPT-4 judge cheaper) |

**Prefer binary over 1–10 Likert.** The 3-vs-4 boundary has no natural meaning, annotators drift, middle values absorb uncertainty, binary needs smaller samples, and "fail" is actionable where "6.3" is not. Use 3-way (pass/partial/fail) when you truly need a middle.

**Pairwise is more reliable than absolute scoring** for subjective qualities (it only needs to distinguish A from B) **but is *more* susceptible to distractor-feature gaming** — a generator can exploit spurious attributes the judge prefers. Pointwise is more robust to manipulation but has score-instability. Choose deliberately.

## Biases and mitigations

| Bias | Mechanism | Magnitude | Mitigation |
|------|-----------|-----------|------------|
| **Position/order** | first-seen response gains salience | up to 76% verdict flip on swap (Claude-v1, Zheng '23) | run both orders, win only if both agree; randomize; order-dependent → tie |
| **Verbosity/length** | prefers longer even if info-identical | +15–30 pt; judges score +0.46 over humans | "ignore length" in rubric; length-normalize; concise few-shot anchors |
| **Self-preference** | favors own family's style | +10–25% | **cross-family judge — mandatory, not optional** |
| **Sycophancy** | agrees with confident framing | task-dependent | CoT first; "evaluate correctness, not confidence" |
| **Formatting** | rewards bullets/headers matching rubric | 5–15 pt | format-neutrality instruction; test same content multiple formats |
| **Leniency/clustering** | scores pile at top of range | discriminability loss | binary/categorical; hard negatives in calibration; "passing everything" = redesign |
| **Math/reasoning blindness** | trusts provided answer, doesn't re-solve | 70% fail on math; →15% with ref-CoT | force independent solve first; don't use judges for math verification |
| **Prompt-wording sensitivity** | equivalent prompts → different verdicts | large | stability test (rephrase, check correlation); lock prompt version |
| **Calibration drift** | judge model silently updates | 3–8 pt mean shift per version bump | pin `(model_id, rubric_version, prompt_hash)`; never `*-latest`; recalibrate on swap |

## Meta-evaluation: validate the judge before trusting it

The catch-22 (EvalGen, Shankar et al.): you need criteria to grade, but you need to grade to discover the criteria. So:

1. **Sample 50–100 real outputs** (from error analysis).
2. **Domain expert labels** each binary pass/fail **with a written critique** — Hamel's "critique shadowing." Critiques must be detailed enough to reuse as few-shot examples.
3. **One benevolent dictator** owns "good" — don't average annotators.
4. **Build judge v1** using expert critiques as few-shot; binary output.
5. **Measure alignment on a held-out set:** report **TPR (recall — catches real failures)** and **TNR (specificity — doesn't false-alarm)** *separately*, plus **Cohen's κ**. Accuracy alone is a trap — a judge that passes everything is 99% "accurate" on 99%-pass data and catches zero failures.
6. **Read every disagreement**, fix the prompt, repeat until κ ≥ 0.6 (≥0.85 high-stakes) or ~75–90% agreement. Honeycomb case: 3 iterations.
7. **Re-validate after any material change** (prompt, judge model, new use case).

Calibration-set sizing: **50 stratified traces** suffice for balanced binary criteria; **200+** when any class is <~10% frequency. Composition beats size — 30 examples covering all failure modes beat 300 of the common case. Validate against **domain experts**, not crowd workers (judges correlate better with non-experts, which inflates reported agreement).

Use the bundled tool: `python scripts/eval_stats.py kappa --judge judge.json --human human.json` → κ, TPR, TNR, precision.

## Rubric & prompt design

**Decompose → assert → aggregate.** Never ask for a holistic score. One specific binary criterion per prompt ("Did the response cite at least one source from the provided context?" not "Is it well-grounded?"). Aggregate: any assertion fails → overall fail.

- **CoT before verdict, then discard the reasoning** — prevents the model contradicting facts it just stated; cut math errors 70%→15%.
- **2–4 few-shot examples with full critiques**, not bare labels.
- **Structured JSON output** so the verdict isn't buried in prose.
- **Explicit scope:** "evaluate only using the information provided; do not use background knowledge."
- **Explicit neutrality:** "ignore response length and formatting."
- **Concrete, observable language**; include negative examples.

### Template

```
You are evaluating whether an assistant response satisfies ONE criterion.
Criterion: {single specific criterion}
Ignore response length and formatting. Use only the information below.

Context given to the assistant: {context}
Instruction: {instruction}
Response: {response}

Think step by step in <thinking>...</thinking> (this will be discarded).
Then output exactly: <verdict>pass</verdict> or <verdict>fail</verdict>
Then: <reason>1-2 sentences quoting specific evidence</reason>
```

## Cost & when a judge is overkill

Run **deterministic checks before the judge** (filters 30–60% at $0). Use the cheapest judge that validates (GPT-4o-mini / Haiku often correlate well; a 3-small-model panel can beat one GPT-4 at 7–8× less). Sample 5–10% of prod traffic for real-time; full batch in CI. **Don't** use a judge for: structurally checkable properties, sub-ms guardrails, specialized factual verification (med/legal — judges share blind spots with generators), or when a simple classifier already solves it.

## Downsides (state these honestly)

- **Circularity** — judge trained on similar data to generator; mitigate with cross-family.
- **Drift** — your trend may reflect judge version change, not system change; you're measuring (generator + judge) jointly.
- **Gameability** — confident-wrong explanations and verbosity inflate scores; monitor for score gains without human-confirmed improvement.
- **Domain blindness** — the judge only catches what it was told to look for; 30–60% recall on real defects. High pass rate ≠ "it works."
- **Finetuned specialist judges may be classifiers in disguise** — they pattern-match in-domain and collapse off-domain.
