---
name: agent-evals
description: "MUST use for evaluating LLM and agent systems — design, build, and operate trustworthy, cost-controlled evals. Use when: evaluating/benchmarking an LLM, agent, RAG, or chatbot; building an eval suite, golden dataset, or LLM-as-a-judge; choosing deterministic vs model-graded evals; judging whether a score change is real vs noise or picking sample sizes; setting up evals in CI/CD or cutting eval cost; grading agent trajectories vs outcomes or tool-call accuracy; evaluating on AWS AgentCore or Bedrock. Keywords: LLM-as-a-judge, golden dataset, pass@k, pass^k, eval harness, RAG triad, hallucination/faithfulness eval, agent trajectory eval, tool-call accuracy, eval flaky/noisy, is my eval significant, AgentCore Evaluations, Bedrock Evaluations, are my evals good, how do I eval my agent."
---

# Agent & LLM Evaluation

Evals are the highest-leverage investment in any LLM product — teams without them stay stuck in whack-a-mole, teams with them swap models in days. But most evals lie: they measure generic qualities that don't track the product, move on noise, or trust an unvalidated judge. This skill encodes what practitioners learned the hard way.

## Scenario router — load the ONE reference that matches the task

Read the matching reference **fully** before acting; load **only** the ones a row points to, and do **not** load the others until their decision point is actually reached (each is 130–150 lines — loading all four wastes context).

| The task in front of you | Load (entire file) |
|--------------------------|--------------------|
| Find where the agent/system fails; pick metrics; build a dataset | [`references/metrics-and-datasets.md`](references/metrics-and-datasets.md) |
| Build, validate, or debug an LLM-as-a-judge / model-graded eval | [`references/llm-as-judge.md`](references/llm-as-judge.md) |
| Decide significance/sample size; design the pipeline, CI cadence, or cut cost | [`references/statistics-and-cost.md`](references/statistics-and-cost.md) |
| Anything on AWS — AgentCore, Bedrock, CloudWatch, managed eval | [`references/agentcore-and-bedrock.md`](references/agentcore-and-bedrock.md) |
| Just deciding code-graded vs judge vs human, or outcome vs trajectory | none — stay in this file (Decisions 1 & 2) |

If unsure, start with `metrics-and-datasets.md` (error analysis comes before everything). The decision sections below are self-contained — only load a reference when its row matches.

## The Prime Directive: look at your data first

**Before building any evaluator, read traces.** The most common and most expensive mistake is building infrastructure (judges, dashboards) before understanding failure modes — you automate ignorance. The correct order is non-negotiable:

```
1. ERROR ANALYSIS   read 50–100 real traces → open-code failures freely →
                    axial-code into a taxonomy → count frequency
2. BUILD            write evals ONLY for high-frequency, recurring failure modes
3. TIER & SCHEDULE  cheap deterministic on every commit; judge on a curated set; human/canary pre-release
4. FLYWHEEL         every confirmed prod failure becomes a golden-set case before the fix ships
```

60–80% of eval effort should be error analysis, not tooling. A one-off bug gets a targeted fix, not a new judge. Only build an expensive evaluator for a failure mode that **recurs across versions**.

**MANDATORY — READ ENTIRE FILE** before doing error analysis or choosing metrics/datasets: load [`references/metrics-and-datasets.md`](references/metrics-and-datasets.md). It has the open/axial coding loop, dataset sizing, the metrics reference, and the RAG triad. **Do NOT** load the judge, statistics, or AWS references for this step.

## Decision 1 — Deterministic vs model-graded vs human

**Before writing any eval code, ask yourself:** (1) Have I read ≥50 real traces, or am I guessing at failure modes? (2) Is this failure *checkable in code* (an answer, a schema, a tool call, a budget)? (3) Will this failure *recur across versions*, or is it a one-off I should just fix? Build an evaluator only when the answers are yes/structured/recurring — otherwise read more traces or fix the bug directly.

Grade with the **fastest reliable method**, in this order (Anthropic's explicit hierarchy):

| Method | Use when | Cost | Reliability |
|--------|----------|------|-------------|
| **Code-based (deterministic)** | answer/structure/tool-call/latency/cost is checkable | ~$0, <1ms | perfect, reproducible |
| **LLM-as-a-judge (model-graded)** | quality, tone, reasoning, faithfulness, open-ended — and code can't express it | $0.01–0.20/call | only after validation |
| **Human** | calibrating the judge; novel/high-stakes ground truth | very high | gold standard, unscalable |

Deterministic checks catch 30–60% of failures for free — **always run them first** and let the judge fire only on what survives. "Often all that lies between you and an automatable eval is clever design" (Anthropic). Reserve human grading for calibration only ("avoid if possible").

**Making model-graded evals reproducible** (they have two variance sources — the system under test AND the judge): pin a dated judge version (never `gpt-4o-latest`); temperature 0 (reduces but does NOT eliminate variance — GPU batching); binary/structured-JSON output; majority vote over 3–5 judge runs for gates; cache verdicts by `hash(judge_version, prompt, input)`; version the judge contract as `(model_id, rubric_version, prompt_hash)`.

## Decision 2 — Outcome vs trajectory vs component (the agent question)

Agents add three altitudes. **Default to outcome; drill down only on failure or requirement.**

```
Outcome / end-state   "Did the task actually get done?"   ← default & primary signal
  └ Trajectory        "Did it take a sensible path?"      ← only if path is a requirement
      └ Component     "Did this tool call / route work?"  ← to localize a found failure
```

- **Grade outcomes, not paths** — verify the *end state changed* (tests pass, ticket resolved, form actually submitted), not the agent's *claim* of success, and not a single reference path. Frontier agents find valid alternate routes; rigid step-matching fails correct work.
- **Grade the trajectory only when the process itself is the requirement**: safety/compliance steps, efficiency budgets (unnecessary tool calls), or to diagnose *where* a failed outcome broke. Even then, prefer order-flexible matching (any-order / in-order subsequence) over exact-order.
- **Always log full traces** (every tool call, args, retrieval) — you cannot diagnose multi-step failures without them.

## Decision 3 — Is this score change real, or noise?

Non-determinism means a single run is never enough. Two traps: reading a 2-point move as signal, and reporting point estimates with no interval.

- **100 examples only detects a ~15-point delta.** Smaller deltas need far more: ~165 (12pt), ~480 (7pt), ~1,580 (4pt). Below n≈few-hundred, scores are bimodal — **use bootstrap CIs, not the CLT**.
- **Paired design is ~10× more efficient:** run both variants on identical inputs, test discordant pairs with **McNemar** — detects a 5% edge in ~290 examples, not thousands.
- **pass@k vs pass^k:** `pass@k` = ≥1 of k succeeds (capability); `pass^k` = ALL k succeed (reliability). `0.75^3 ≈ 42%`. **Production needs pass^k.**
- Multiple comparisons (testing N prompts) inflate false positives — apply Bonferroni/FDR.

Use the bundled calculator instead of guessing:
```bash
python scripts/eval_stats.py power --baseline 0.80 --delta 0.04        # examples needed
python scripts/eval_stats.py compare --a results_a.json --b results_b.json  # McNemar + bootstrap CI: real or noise?
python scripts/eval_stats.py kappa  --judge judge.json --human human.json   # validate a judge: κ, TPR, TNR
```
Each file is a JSON array of pass/fail (or scores). `compare` and `kappa` require the two arrays **aligned element-for-element** (same eval items, same order) — they run a *paired* test; independent, unaligned runs can't be compared this way.

## Building an LLM-as-a-judge

A judge is a measurement instrument — **calibrate before trusting it.** An unvalidated judge gives false confidence (judges catch only 30–60% of real defects).

**MANDATORY — READ ENTIRE FILE** before building, validating, or debugging any model-graded eval: load [`references/llm-as-judge.md`](references/llm-as-judge.md). It has the modes, the full bias→mitigation table, the validation loop, rubric design, and a judge prompt template. **Do NOT** load the metrics, statistics, or AWS references unless you separately hit their rows above.

The non-negotiables (full detail in the reference): binary pass/fail over Likert; one criterion per prompt; chain-of-thought *before* the verdict (then discard it); cross-family judge (never grade a model with itself); validate against human labels until Cohen's κ ≥ 0.6 (≥0.85 high-stakes), reporting **TPR and TNR separately** — accuracy alone hides a judge that passes everything.

## Tiering, scheduling, and cost

Running a frontier judge on 500 examples per change is how teams end up abandoning evals. **Tier them:**

```
   △  Tier 3  human / canary / A-B      pre-release   hours   $$$
  ◢◣  Tier 2  LLM-judge on golden set   per-PR/nightly minutes $$
 ◢——◣ Tier 1  deterministic + classifiers every commit  seconds ¢
```

Most teams build only Tier 3 and never run it. Build Tier 1 first. **MANDATORY — READ ENTIRE FILE** when designing the eval pipeline, arguing significance, choosing sample sizes, scheduling CI, or cutting cost: load [`references/statistics-and-cost.md`](references/statistics-and-cost.md). **Do NOT** load the metrics, judge, or AWS references for this step.

## Evaluating on AWS (AgentCore / Bedrock)

**MANDATORY — READ ENTIRE FILE** if the system runs on AWS, or the user mentions AgentCore, Bedrock, CloudWatch, or managed eval: load [`references/agentcore-and-bedrock.md`](references/agentcore-and-bedrock.md). **Do NOT** load the metrics, judge, or statistics references for this step, and **do NOT** load this file at all for non-AWS work — it's vendor-specific.

One-paragraph orientation: **AgentCore Observability** emits OTEL traces (GenAI semantic conventions) to CloudWatch — that's the *data*, not eval. **AgentCore Evaluations** (GA 2026-03-31) is the managed *scoring* layer: 13 built-in evaluators at session/trace/tool levels, ground-truth via `expected_response`/`expected_trajectory`/`assertions`, **online** (sampled prod) vs **on-demand** (CI/CD) modes, custom code evaluators as Lambda. **Bedrock Evaluations** (managed, separate) does model + RAG eval with 11 metrics and judge models. Don't confuse Observability (data) with Evaluations (scoring), or Evaluations (measures quality) with Policy (blocks actions).

## NEVER do these (the landmines)

- **NEVER build a judge or dashboard before reading traces.** Error analysis first; you cannot enumerate LLM failure modes from first principles.
- **NEVER trust an LLM judge you haven't validated against human labels.** Report TPR+TNR, not accuracy — a judge that passes everything scores 99% accurate and catches zero failures.
- **NEVER use a holistic 1–10 score** where binary pass/fail (or pass/partial/fail) works — middle values absorb disagreement and need bigger samples.
- **NEVER grade a model with a judge from its own family** — self-preference inflates scores 10–25%.
- **NEVER ship on a 2-point eval move from ~100 examples** — it's inside the noise. Get a CI; use the calculator.
- **NEVER tune prompts on the same set you report scores on** — that's train/test contamination; the optimizer overfits to the set and production degrades. Hold out a test set.
- **NEVER leave the judge model or temperature unpinned** — silent provider updates shift scores 3–8 points; you'll chase phantom regressions.
- **NEVER rigidly match a single reference trajectory** for agents — frontier agents find valid alternate paths; grade the end state.
- **NEVER accept the agent's *claim* of completion** — verify the environment actually changed (tests pass, record written).
- **NEVER test only happy paths** — your worst-experience users already left the dataset; construct adversarial, edge, multi-turn, and tool-failure cases.
- **NEVER chase 100% pass rate** — it means the eval is too easy. 70% on hard, adversarial cases is more informative.
- **NEVER treat the eval score as the goal** (Goodhart). When the score and user signals diverge, trust the users and fix the eval.
- **NEVER let the golden set rot, and NEVER leak prod data into it without decontamination** — refresh ~20%/quarter and feed every confirmed prod failure back in, but if those prod traces ever fed a training/fine-tuning run the model has already seen them, so they inflate scores while measuring nothing (contamination audits find 1–45% leakage in public benchmarks).
- **NEVER use an LLM judge to verify math or arithmetic** — judges trust a provided answer instead of re-solving it (~70% error rate); use a code/deterministic check.
- **NEVER reach for BLEU/ROUGE/BERTScore for modern LLM/agent quality** — built for 2002-era MT; near-zero correlation with what your product needs.

## The five-second cheat sheet

The order is the method: **data → method → tier → math → flywheel.**
1. Read traces and do error analysis *before* building anything.
2. Grade with the cheapest reliable method (code → validated judge → human).
3. For agents, grade the **outcome** unless the path is the requirement.
4. Never declare a win without a CI — run `scripts/eval_stats.py compare`.
5. Feed every confirmed prod failure back into the golden set.

(Reference routing is the table at the top of this file; the two grading/altitude calls are Decisions 1 & 2 above — both self-contained, no reference needed.)
