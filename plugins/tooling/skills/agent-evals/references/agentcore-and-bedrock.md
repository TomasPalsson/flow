---
name: agentcore-and-bedrock
description: Evaluating agents on AWS — Amazon Bedrock AgentCore Evaluations (13 built-in evaluators, ground truth, online vs on-demand, OTEL/CloudWatch) and Amazon Bedrock Evaluations (model + RAG, 11 metrics, judge models, pricing). Load when the system runs on AWS or the user mentions AgentCore, Bedrock, CloudWatch, or managed evaluation.
---

# Evaluating Agents on AWS

## First, don't conflate three things

- **AgentCore Observability** = the *data substrate*. OTEL traces/spans with GenAI semantic conventions (prompts, completions, tool calls, model params) + built-in metrics (session count, latency, duration, token usage, error rate), stored in CloudWatch. This is telemetry, **not** evaluation.
- **AgentCore Evaluations** = the managed *scoring layer* on top of those traces.
- **AgentCore Policy** = real-time guardrails (Cedar / natural-language) that *block* tool calls before execution. Evals *measure* quality after the fact; Policy *prevents* actions. Different tool.

## AgentCore Evaluations (GA 2026-03-31)

Managed agent evaluation that reads OTEL traces and scores them. Works with any OTEL+OpenInference-instrumented agent (Strands, LangGraph, etc.) — not Bedrock-locked. Results land in the CloudWatch AgentCore Observability dashboard with **judge reasoning shown alongside each score**, and you can set CloudWatch alarms on eval scores.

### The 13 built-in evaluators, by altitude

**Session (1):** `GoalSuccessRate` — were *all* user goals met in the conversation (consumes `assertions` ground truth).

**Trace (11):** `Helpfulness`, `Correctness` (consumes `expected_response`), `Coherence`, `Conciseness`, `Faithfulness`, `Harmfulness`, `InstructionFollowing`, `ResponseRelevance`, `ContextRelevance`, `Refusal`, `Stereotyping`.

**Tool/span (2):** `ToolSelectionAccuracy`, `ToolParameterAccuracy`.

Built-ins use fixed configs (standardization). Cross-region inference preserves data residency.

### Three evaluator types (maps to the universal hierarchy)

1. **LLM-as-a-judge** — most trace-level built-ins; structured rubric per criterion.
2. **Ground truth** — reference comparison (below).
3. **Custom code** — **AWS Lambda** for deterministic scoring (exact values, format, business rules). This is AgentCore's deterministic-eval hook.

### Ground truth — three optional, independent inputs

| Input | Consumed by | Measures |
|-------|-------------|----------|
| `expected_response` | `Builtin.Correctness` | similarity to known-correct answer |
| `expected_trajectory` | `TrajectoryExactOrderMatch` / `TrajectoryInOrderMatch` / `TrajectoryAnyOrderMatch` | did it call the expected tools (exact order / in-order subseq / any order) |
| `assertions` | `Builtin.GoalSuccessRate` | natural-language session-outcome statements |

**The trajectory matchers are the strictness dial** from the main skill's Decision 2. Default to **AnyOrder** (the tools were used) unless order genuinely matters; reserve **ExactOrder** for true compliance sequences. Over-constraining fails valid alternate paths.

### Online vs on-demand

| Mode | Use | Limits |
|------|-----|--------|
| **Online** | continuous prod monitoring of live traces | configurable % sampling; ≤10 evaluators/config |
| **On-demand** | dev, **CI/CD regression**, interactive debug | real-time API, 10 evals/call |

Both use identical evaluators → dev↔prod comparability. Python SDK `bedrock-agentcore`: `EvaluationClient` (score existing CloudWatch sessions), `OnDemandEvaluationRunner` (dataset eval for CI/CD), `CreateOnlineEvaluationConfig`. Custom evaluators: pick model + params + judging prompt + scale (binary 0/1 or ordinal 1–5); AWS recommends **MECE** criteria and **low temperature** for deterministic scoring.

### Setup

1. Deploy on AgentCore Runtime with OTEL (or self-host w/ ADOT). **Enable CloudWatch Transaction Search once per account** — spans (and thus Evaluations) don't appear until you do, and it takes ~10 min to propagate.
2. Create an evaluation config (console/API).
3. Select evaluators (≤10/online config).
4. Set sampling + data source (endpoint or CloudWatch logs).
5. Monitor in the dashboard; set alarms.

### AgentCore pitfalls

- **Observability ≠ Evaluation** — dashboards of traces aren't scores; you must add Evaluations (or your own harness).
- **Forgot Transaction Search** → silent empty results.
- **Over-sampling online eval** → LLM-judge cost per trace × high traffic = surprise bill. Start at 1–5%, alarm, tune. AWS throttling advice: lower sampling, fewer evaluators, or quota increase.
- **`Correctness` without `expected_response`** degrades to a weaker reference-free judge — supply ground truth on a golden set.
- **Wrong trajectory strictness** (see above).
- **PII in spans** — GenAI spans capture prompts/completions verbatim; filter sensitive data from span attributes.

## Bedrock Evaluations (managed, separate, GA 2025-03)

For evaluating *models* and *RAG pipelines* (not agent traces). Two tracks: **Model Evaluation** (any LLM) and **Knowledge Base / RAG Evaluation**.

- **Methods:** automatic algorithmic (F1, BERTScore, exact match); **LLM-as-judge** (needs a generator model + a separate judge model); human ($0.21/task).
- **11 model metrics (0–1):** Correctness, Completeness, Faithfulness, Helpfulness, Coherence, Relevance, FollowingInstructions, ProfessionalStyleAndTone, Harmfulness, Stereotyping, Refusal. (For Harmfulness/Stereotyping, **higher = worse**.)
- **RAG metrics add:** Context Relevance, Context Coverage (retrieval), and **Citation Precision + Citation Coverage** — AWS: always use the citation pair together (coverage ≈ recall).
- **Judge models:** Claude (3 Haiku → Opus 4.5), Amazon Nova, Llama 3.1 70B, Mistral Large; cross-region profiles ok.
- **Generator:** any Bedrock model, fine-tuned/imported, prompt routers, **or bring-your-own-inference** (upload JSONL of pre-fetched completions to S3 → evaluate models hosted anywhere).
- **Input:** JSONL with `prompt` (required), `referenceResponse` (optional ground truth), `category` (optional slicing). Output to S3 + console histograms/spider charts.
- **Pricing:** automatic = free; LLM-judge = standard judge-model token rates, **no per-job fee**; human = $0.21/task.

## What AWS managed eval does NOT do (add locally)

- No native **pass@k / pass^k** aggregation — run multiple jobs, aggregate externally.
- Bedrock Evaluations has **no agent-trajectory / tool-sequence** eval — that's what **AgentCore** Evaluations adds; for non-AWS stacks use Braintrust / LangSmith / Phoenix.
- No built-in **user-simulator** for multi-turn conversational agents — simulate externally.

## Recommended AWS pattern

Design *what* to measure with the eval philosophy in the main skill (error analysis → balanced golden set → deterministic-first → validated judge). Then: AgentCore **on-demand** as a CI/CD regression gate + **online** sampled eval with CloudWatch alarms as a production guardrail; Bedrock Evaluations for model-selection bake-offs and RAG/Knowledge-Base pipelines. Use built-in evaluators for the universal dimensions; add Lambda/custom evaluators only for business rules the built-ins can't express.
