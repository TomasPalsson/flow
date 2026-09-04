---
name: metrics-and-datasets
description: Error-analysis loop, dataset construction and sizing, the metrics reference (general + agent-specific + RAG triad), and what makes an eval good. Load before doing error analysis, building a golden dataset, or choosing metrics.
---

# Metrics, Datasets & Error Analysis

## The error-analysis loop (do this first, always)

This is the most important activity in evals — and the most skipped. Run it *before* building any automated evaluator.

1. **Collect traces** — ≥100 real (production or realistic) traces. Refresh every 2–4 weeks.
2. **Open coding** — a domain expert reads each trace and writes free-form notes on what went wrong. Don't force categories yet. **Focus on the *first* failure in each trace** — upstream errors cascade and downstream notes are noise.
3. **Axial coding** — group open notes into a failure taxonomy; count occurrences. LLMs can assist the grouping; one human "benevolent dictator" makes the final quality calls (averaging annotators creates paralysis).
4. **Theoretical saturation** — stop when ~20 consecutive traces add no new category.
5. **Prioritize by frequency** — build evaluators only for persistent, high-frequency modes you'll iterate on repeatedly. One-offs get a direct fix.

Real case (Hamel Husain): a client was *sure* their leasing agent worked from casual testing; systematic trace analysis exposed appointment-setting and date-handling failures that "looked fine" had never surfaced.

## What makes an eval *good*

| Property | Test | Failure smell |
|----------|------|---------------|
| **Validity** | does it measure what matters for *this* product? | generic "helpfulness" that doesn't move with real quality |
| **Reliability** | same input → same verdict? | unpinned judge, non-zero temp |
| **Discriminative power** | separates good from bad? | every output scores 0.7–0.8 |
| **Sensitivity** | a known improvement moves it? | BLEU/ROUGE don't budge for paraphrase |
| **Coverage** | spans real input distribution incl. edges? | happy-path only |
| **Correlation w/ outcomes** | improving it improves users/business? | green dashboard, angry users |
| **Actionability** | a failure points to what to fix? | "scored 6.3" tells you nothing |

**The two-experts test (Anthropic):** a task is well-specified if two independent domain experts reach the *same* pass/fail verdict. If they can't, the rubric isn't specific enough.

**Capability vs regression evals:** capability evals start low (~20–40%, "hills to climb") during development; once they saturate (~100%) they graduate into regression suites where any drop is a signal. A 100% pass rate on a capability eval means it's too easy, not that you're done.

## Dataset construction

**Sources (in order of value):** (1) convert your existing manual pre-release checks into cases; (2) mine bug trackers / support queues — real failures; (3) production traces (most representative, needs annotation); (4) synthetic — fast to bootstrap but **fails at domain complexity, low-resource languages, high-stakes edges, underrepresented groups**. Don't ship on synthetic alone.

**Sizing:**

| Use case | Minimum | Recommended | Note |
|----------|---------|-------------|------|
| Error analysis | 100 traces | 100+ | stop at 20-trace saturation |
| Judge calibration | 100 labeled | 500–1000 | split validation + holdout |
| Golden/regression set | 20–50 tasks | 200+ | start small, grow with capability |
| Production sampling | 10–20 | 50–100 | between major analysis cycles |

**Quality requirements:** balance happy-path / edge / adversarial / off-topic; include a reference solution proving each task is solvable; keep ground truth inaccessible to the agent at eval time; freeze external resources (sites/APIs/state) so the eval is reproducible.

**Coverage beats volume.** 50 diverse cases across distinct failure categories beat 500 near-identical ones. Expand volume only after coverage is established.

**Criteria drift (Shankar et al.):** you often *cannot* fully define eval criteria before seeing outputs — criteria emerge from grading. Budget the first ~30 grades as criteria-discovery, expect to revise your first rubric, and version your rubrics.

## Metrics reference

### General

| Metric | Definition | Good for | Avoid when |
|--------|-----------|----------|-----------|
| Exact match | output == expected | structured output, tool names | any open-ended text |
| F1 | harmonic mean precision/recall | tool-call sets, classification | reporting accuracy alone on imbalanced data |
| PR-AUC | area under precision-recall | imbalanced data (most evals) | balanced classes (ROC-AUC ok) |
| pass@k | ≥1 of k succeeds | capability ("can it at all?") | production reliability |
| pass^k | all k succeed | production reliability | research capability |

**BLEU / ROUGE / BERTScore: effectively obsolete for modern LLM/agent quality.** Built for 2002-era MT/summarization; penalize valid paraphrase; near-zero correlation with human judgment. For translation specifically, COMET / COMETKiwi are the current strong metrics — but for product evals, prefer task-specific code checks or a validated judge.

### Agent-specific

| Metric | Definition | Altitude |
|--------|-----------|----------|
| Task Success Rate | % tasks fully completed (verify end state) | outcome |
| Progress Rate | % sub-goals completed (partial credit) | outcome/trajectory |
| Tool-F1 | F1 of tool-name prediction vs reference | component |
| argname-F1 | F1 of argument names per tool | component |
| Node F1 | F1 of tool selection in task graph | trajectory |
| Edge F1 | F1 of tool invocation *ordering* | trajectory |
| Step Efficiency | % unnecessary tool calls / total | trajectory |

Watch for **eval-bypass exploits**: τ-bench gave a trivial do-nothing agent 38% "success" on *unsolvable* tasks; SWE-Lancer let agents hit 100% by replacing test files. Verify tasks are genuinely solvable and that "success" can't be faked.

### RAG triad

| Metric | Question | Method |
|--------|----------|--------|
| Faithfulness / Groundedness | claims supported by retrieved context? | decompose into claims, check each (NLI/LLM) |
| Context Relevance / Precision | retrieved context relevant to query? | score each chunk |
| Context Recall | context covers all needed info? | compare to ground-truth requirements |
| Answer Relevance | response actually answers the query? | LLM check; penalize tangential |

RAGAS provides production-ready implementations. On Bedrock the managed equivalents add **Citation Precision + Citation Coverage** (always use the pair — see the AgentCore/Bedrock reference).

## Multi-turn & long-horizon

Single-turn evals miss conversation failures: error cascades, context-retention loss, cross-turn contradiction, persona drift. Test conversational agents with a **user-simulator** (a second LLM playing personas) to scale multi-turn coverage. Standard evals cover <10 turns; real enterprise agents run hundreds — very few benchmarks cover this (LoCoMo: 600+ turns) and there's no cheap production answer yet.
