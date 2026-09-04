---
name: diagnosis
description: How to localize a retrieval failure to a pipeline stage and measure it without lying to yourself — seven isolation experiments, per-stage failure signatures, the bounded oracle test, the metric traps (any-hit recall, the reranker paradox, RAGAS's own broken example), golden-set circularity, and the Aug 2026 tooling landscape. Load when answers are bad and you need to know WHERE; skip for generic eval theory (agent-evals) and for fixing a stage you have already localized.
---

# Diagnosing Retrieval Failure

Generic eval machinery — judge design, bias table, κ validation, sample sizing, significance — belongs to **`agent-evals`**; load it there and do not re-derive it here. This file is only about the part that is RAG-specific: cutting a pipeline into stages, bounding each one, and knowing which metrics quietly lie about which stage.

## The seven isolation experiments

Run in this order. The first three are cheap enough that skipping them is never justified.

| # | Experiment | Setup | What a result means |
|---|---|---|---|
| 1 | **Closed-book floor** | Same questions, no context at all | The hallucination floor. If live ≈ closed-book, retrieval is contributing nothing. If live < closed-book, retrieval is **net-negative** — noisy context is actively displacing correct parametric knowledge. |
| 2 | **Oracle-context ceiling** | Hand-label gold passages for 30–100 queries, inject directly | Splits retrieval-bound from generation-bound. `python scripts/rag_calc.py ceiling --oracle 0.87 --live 0.58` |
| 3 | **"Is it even in the index?"** | grep + embed-search the corpus for the answer string, bypassing the retriever | A miss here is an **ingestion or documentation** problem. Tuning retrieval for a document that does not exist is the single most common wasted quarter. |
| 4 | **Embedding-model swap ablation** | Same chunks, same queries, second embedding model, nothing else changed | Substantial ranking divergence localizes the failure to embedding space. No divergence exonerates it — look upstream at parsing/chunking. |
| 5 | **Reranker on/off with rank-delta logging** | Log each gold doc's rank *before* and *after* rerank, per query | Aggregate deltas hide the failure; see the reranker paradox below. You want the per-query demotion list, not the mean. |
| 6 | **Chunk-boundary spot check** | For each known failure, pull chunk *n−1* and *n+1* alongside the retrieved chunk | Catches the rule-split-from-its-exception failure, which is invisible to every aggregate metric. |
| 7 | **Interactive what-if** | Swap retriever (keyword vs. embedding), change chunk size, re-run **one** failing query at low latency | The `raggy` system (CHI 2026, [arXiv:2504.13587](https://arxiv.org/pdf/2504.13587)) exists specifically for this loop. Re-running a full eval suite per config change is too slow to sustain a debugging session. |

## Stage-by-stage failure signatures

| Stage | Signature | The distinguishing diagnostic |
|---|---|---|
| **Parsing** | Failure looks like an embedding problem — right doc, low score, no obvious reason | Diff parsed text against the source PDF/HTML for structural loss: merged table columns, lost reading order, dropped headers. Almost never checked; frequently the root cause. |
| **Chunking** | Two-sided. Oversized → several ideas averaged into one vector, so no idea wins a similarity contest. Undersized → precise but stranded (a sentence without its paragraph is uninterpretable) | Experiment 6. The canonical case: a rule and its qualifying exception split at a paragraph boundary; the retriever returns the rule, the answer is confidently wrong. |
| **Embedding** | Doc is in the corpus, scores low; jargon, acronyms, numeric codes involved | Experiment 4. Ranking flips under a different model ⇒ embedding space. |
| **Indexing / retrieval** | Doc is in the corpus but structurally unreachable | Query with the filter removed; query by ID directly. Wrong metadata filter, stale index, or ANN recall ceiling. |
| **Reranking** | First-stage retrieval was correct; the reranker demoted the gold doc below the cut | Experiment 5. Never judge a reranker on aggregate Recall@10 or MRR alone. |
| **Generation** | Gold chunks present in context, answer still wrong or ungrounded | Last stage to check, not first. Split further with per-claim attribution (below), not a holistic score. |

## The bounded oracle test

Oracle alone is half a measurement. The standard 2025–26 design is **closed-book floor + oracle ceiling + live**, and the *shape* of the three numbers is the diagnosis: floor tells you how much of the score is parametric knowledge you were about to credit to retrieval; ceiling tells you how much headroom retrieval work can possibly buy.

Documented gaps, useful as calibration for how much headroom is normal:

| Domain | Ceiling | Live / best real | Read |
|---|---|---|---|
| Multimodal/multilingual QA (CVQA) | 94–99% | 64–74% | Reported 20–30 pt gap that **widens with model size** — bigger models exploit perfect context better but degrade relatively more on imperfect retrieval. |
| Scientific domain (combustion) | 87.3% | "Optimal RAG" 58.24% | ≈29 pts of headroom left on the table by retrieval alone. |
| Long-form summarization (CRUX) | coverage 64.6/61.8 | below every empirical retriever tested | Oracle beat all methods; the gap is the whole opportunity. |
| HotpotQA reproduction (passage- vs sentence-level oracle) | both cluster just above 0.70 F1 across k | — | Sentence-level ("only the exact sentences") ≈ passage-level ⇒ the ceiling is **LLM capacity**, not evidence granularity. Tightening evidence granularity will not help you. |

**Oracle is not a strict ceiling.** FreshStack found a fusion+rerank baseline **outperforming** the oracle setting on some topics ([arXiv:2504.13128](https://arxiv.org/pdf/2504.13128)) — extra non-gold context sometimes helps. Treat oracle as a strong reference point; if live > oracle, your gold labels are incomplete, not your pipeline miraculous (`rag_calc.py ceiling` warns on this).

Thresholds `rag_calc.py ceiling` applies: oracle < 0.75 ⇒ generation-bound (retrieval work is capped); gap > 0.15 ⇒ retrieval-bound; otherwise balanced, and further gains need both sides or a reframing of the question type.

## The variance floor — read this before believing any A/B

Before you interpret *any* retrieval A/B, establish the noise floor, because it is far higher than teams assume. **Reversing the order of the retrieved documents — same documents, same query, same model — flips 11.4–25.2% of predictions** across six open-weight LLMs ([arXiv:2605.14115](https://arxiv.org/abs/2605.14115), BioNLP 2026). That is a lower bound on run-to-run variance from a change that carries no information at all.

The consequence is blunt: **an A/B whose effect size sits under that band has not been demonstrated**, no matter how clean the point estimates look. Shuffle-order replicates are the cheapest way to measure your own floor — run the same eval N times with permuted context order and take the spread. Sample sizes, paired designs, and significance testing → **agent-evals**; this section only establishes that the floor exists and is large.

## Metric traps

**Recall@k with one gold chunk is an "any-hit" metric.** It is satisfied the moment *one* relevant chunk lands in top-k — exactly the wrong criterion for multi-hop or diffuse-evidence answers that need several sub-facts assembled. This design flaw explains most of the gap between benchmark numbers and production reality. On MultiHop-RAG, best Hits@10 with reranking was 0.7467, falling to 0.6625 at Hits@4 ([arXiv:2401.15391](https://arxiv.org/abs/2401.15391)) — and the headline still overstates it.

**Accuracy@K is the strict fix**: the fraction of questions where *all* gold documents land in top-K. Under it, multi-hop collapses. On a cross-newspaper multi-hop task, single-hop Recall@3 was 67.8 while multi-hop Recall@3 fell to **14.3** ([StratRAG, arXiv:2604.22757](https://arxiv.org/pdf/2604.22757)). Always stratify by hop count; a blended number is a blend of two different systems.

**The reranker paradox.** Reranking can *raise* Recall@10 and MRR@10 while *lowering* Accuracy@3 — the reranker sharpens the single best hit and crowds out the *other* gold documents a multi-hop answer needed. A net-positive aggregate can be net-negative precisely on the queries that need complete evidence. This is why experiment 5 logs per-query rank deltas rather than means.

**Gold labels are a lower bound, not ground truth.** When several documents could validly support an answer, or annotators only labeled the obvious ones, Recall@k under-credits a retriever that found a genuinely relevant but unlabeled document. Read absolute recall as conservative; read *deltas between configs* as the real signal.

**Multi-round / agentic retrieval breaks recall outright** — with several retrieval rounds, "recall@k" is not well-defined (k of what, at which round?). SePer proposes measuring utility as semantic-perplexity reduction (ΔSePer) instead of any recall variant. If your system loops, stop reporting recall and report end-task utility.

**Companion metrics worth adding**: Answerable@K (is there enough evidence in top-K to actually answer, not merely touch the topic), evidence coverage (fraction of necessary sub-facts retrieved), Contradiction@K (RAG failures are often *misleading* evidence, not absent evidence).

`python scripts/rag_calc.py recall --file run.jsonl` prints the recall@k curve, MRR, and where marginal gain drops below threshold — the k past which you are buying distractors, not answers. Note that the k maximizing recall is **not** the k maximizing answer quality; tune retrieval k and generation k separately, against different metrics.

## RAGAS: known reliability problems

Widely used for fast prototype scoring; treat its numbers as **relative, within a pinned judge**, never as absolute quality thresholds.

- **Faithfulness swings from 0% to over 80% on identical retrievals and responses depending solely on which model judges** (Llama 3 vs. Claude 3 Sonnet in one controlled comparison; single-source, reported). Reported harmonic-mean correlation with human judgment ≈0.55.
- **`LLMContextRecall` scores 1.0 on a context that never mentions the entity** — this is in [RAGAS's own docs](https://docs.ragas.io/en/stable/concepts/metrics/available_metrics/context_recall/): the question concerns the Eiffel Tower, the retrieved context only states Paris is France's capital, the reference claim happens to be trivially entailed, score 1.0. Not a third-party critique; the framework's own worked example.
- **The docs also concede the substitution**: using `reference` (an answer) in place of `reference_contexts` (actual gold passages) is a convenience proxy because annotating contexts "can be very time-consuming." What you are measuring is claim-attributability, not retrieval of the intended passage.
- **Context precision is order-sensitive by design and it looks like a bug**: relevant chunk first, irrelevant second ⇒ ≈1.0; flip the order, same two chunks ⇒ ≈0.5 ([docs](https://docs.ragas.io/en/stable/concepts/metrics/available_metrics/context_precision/)). It measures rank, not "was the right content retrieved." Also check which variant you enabled — `ContextPrecision` (vs. reference answer), `ContextUtilization` (vs. generated response, no ground truth needed), and `IDBasedContextPrecision` (pure ID overlap, **blind to content**) have materially different semantics under one family name.
- **Judge parse/serialization failures silently become 0 or NaN** and sink into the aggregate (documented, Llama-3-as-judge most often). Audit the parse-failure rate explicitly or you will debug a JSON bug as a retrieval regression.

## Golden-set circularity

**Mechanism**, two compounding effects: (1) *lexical leakage* — the generated question copies the chunk's exact wording, so retrieval looks strong on term overlap rather than semantic matching; (2) *self-preference / overlap bias* — models perform better on text they or a same-family model generated, biasing which pipeline "wins."

**It has been measured, and the second-order effect is the dangerous one.** Chroma ran generated vs real production queries over the same corpus: generated queries scored *higher* (text-embedding-3-small Recall@10 **0.530 generated vs 0.439 real**) — an inflated absolute number, which is the obvious problem. The non-obvious one: a real **0.072** Recall@10 gap between two embedding models **collapsed to 0.002** on generated queries ([generative benchmarking](https://trychroma.com/research/generative-benchmarking), Apr 2025). The eval did not merely flatter the system, it lost the power to tell two systems apart — so it will report "no difference" for a change that actually matters.

**The structural fix is to stop letting your chunker define the ground truth.** Generate questions from *raw corpus text*, label gold as verbatim **token spans**, and apply chunking only afterward at retrieval time — then no chunking strategy is privileged by construction. This generalizes: chunk-level metrics **cannot** measure chunking, because the unit of measurement moves with the thing being measured. Label granularity is also where the signal lives — document-level recall correlated with human answer ratings at only **r=0.05**, while word/span-level recall reached **r=0.35** against an inter-human ceiling of 0.85 ([arXiv:2607.07302](https://arxiv.org/abs/2607.07302) — n=96, single system, wide CIs; directional).

Mitigations, ranked by how directly they attack the mechanism:

1. **Separate the generator model from the judge model** — never one model (or family) both writing the test data and grading it.
2. **Adversarial generation with confounder chunks** — show the generator the target chunk *plus* near-duplicate distractors and demand a question uniquely answered by the target. This attacks the shortcut directly rather than hoping paraphrasing dilutes it.
3. **Rotate generator models** across the set so one model's stylistic bias does not dominate.
4. **Break parametric leakage too, not just lexical** — SeedRG ([arXiv:2605.08838](https://arxiv.org/html/2605.08838v1)) substitutes entities *outside* the model's parametric knowledge while preserving reasoning structure; systems that looked tied on a leaky benchmark separate cleanly on the leakage-free one.
5. **Human spot-check 5–10%**, plus an LLM-judge pass dropping malformed/unrealistic questions.
6. **Anchor with real production queries** to catch distribution drift synthetic generation cannot see. (The artifact behind this file flags dedicated log-mining methodology — clustering, dedup, anonymization, refresh cadence — as **unverified / not researched**. Do not invent a procedure and present it as standard.)

**The nuance that matters**: controlled testing found only *limited* self-preference at the "does a generator's own dataset flatter it" level. The real limit is the **validity envelope**: synthetic sets rank systems differing in **retriever configuration** (chunking, embeddings, top-k, reranking) in alignment with human-labeled baselines, but do **not** reliably rank systems differing in **generator architecture** — varied output styles make rankings sensitive to question phrasing, especially on open-ended questions ([arXiv:2508.11758](https://arxiv.org/html/2508.11758v2)). So: **use a synthetic golden set to tune retrieval; never to pick a generator model.** For that comparison, human-labeled or production-derived data only.

## Framework landscape, Aug 2026

Two categories that get conflated: **trace-first observability** (Langfuse, LangSmith, Braintrust, Arize/Phoenix, Opik) attaches scores to live nested spans; **scoring libraries** (RAGAS, DeepEval, TruLens, RAGChecker, ARES) score outputs offline or in CI. The 2026 pattern is pairing one of each, not picking one — with **OpenTelemetry GenAI semantic conventions** as the portability hedge, which matters given consolidation (Langfuse acquired by ClickHouse, Jan 2026).

Maintenance status pulled from the GitHub release API on 2026-08-13, not from vendor comparison blogs: RAGAS v0.4.3 (2026-01-13, ~monthly cadence); DeepEval v4.1.7 (2026-07-29); Langfuse v4.10.0 (2026-08-12, multiple releases/day). **Correction to circulating commentary: TruLens is not stalled** — trulens 2.12.0 (2026-08-06), 2.11.0, 2.10.0, 2.9.0 all shipped within ~3 weeks of that date. Blog claims of a slowing cadence post-TruEra-acquisition are contradicted by release data. What those releases *contain* (product features vs. enterprise plumbing) was not verified — "is it maintained" is settled, "what it ships" is open.

**RAGChecker** (`amazon-science/RAGChecker`, pip-installable, metrics verified from README 2026-08-13) is the one worth knowing because it decomposes by module at the *claim* level via entailment rather than string overlap: retriever `claim_recall` / `context_precision`; generator `context_utilization`, `noise_sensitivity_in_relevant` / `_in_irrelevant`, `hallucination`, `self_knowledge`, `faithfulness`. Its README example — `context_precision: 87.5` alongside `claim_recall: 61.4`, `hallucination: 4.2`, `self_knowledge: 25.0` — is the entire argument against blended scores: precise retrieval, incomplete evidence, and a quarter of the correct claims coming from parametric knowledge rather than the corpus. **`self_knowledge` high is a bad sign for a system meant to be grounded** — the generator is getting away with it, and will stop getting away with it on the next question. ARES uses fine-tuned DeBERTa-class judges instead of an LLM (academic, not productized). Amazon Bedrock's managed RAG eval offers retrieve-only and retrieve-and-generate job types with judges up to Claude Opus 4.5 / Sonnet 4.0 (verified live 2026-08-13); its **built-in metric names are unverified** — pull the page rather than guessing them. Vertex AI's equivalent feature set is **unverified**; do not cite specifics.

## Faithfulness and citation eval

Claim-level decomposition (extract atomic claims → check entailment against context) is the default shape everywhere; the choice is only what does the checking.

- **NLI models** (DeBERTa-MNLI class, Vectara HHEM, PatronusAI Lynx, MiniCheck/FactCC/TRUE): fast, cheap, deterministic, local. Catch obvious unsupported claims, miss subtle ones. **LLM judges**: better on hard cases at ≈5× cost and ≈5× latency (single practitioner comparison), and multi-second latency rules them out as inline guardrails.
- **Do not substitute embedding or cross-encoder similarity for entailment.** On HaluEval/RAGTruth/WikiBio, embedding- and cross-encoder-based hallucination detectors showed false-positive rates of **100%, 88%, and 50%** vs. **7%** for GPT-4-as-judge ([arXiv:2512.15068](https://arxiv.org/pdf/2512.15068)). Plausible hallucinations preserve surface similarity while introducing real errors — the exact case similarity is blind to.
- **Tiered, not binary**: cheap NLI inline on 100% of traffic; LLM judge async on a sample, nightly on the full set, or only on borderline cases the cheap check flags. Calibrate per dimension — one study found LLM/NLI agreement high enough on a single faithfulness dimension to adopt the NLI model for that dimension only.
- **Citations fail independently of groundedness**, hence three separate rubrics: **structural** (well-formed `source_id` + `quoted_span` emitted at all — free, sub-ms, every call; necessary, never sufficient); **resolvability** (does `source_id` actually appear in the upstream retriever span? plus URL/DOI resolution for external sources — cheap, inline); **semantic** (does the cited passage *entail* the claim? atomic-claim + entailment judge per pair — sampled, expensive). A system can score 0.93 groundedness while citing a document it never retrieved. **The retrieval-log join is the cheapest catch of the three and the one most stacks skip.**
- **Span-level ground truth is genuinely ambiguous** — a sentence may be jointly or partially supported by several passages, and annotators picking "the" supporting passage disagree at rates that make inter-annotator agreement a real methodological problem, not a rounding error. Do not build a span-level gold set without measuring your own annotator agreement first.
- **Faithfulness is not truth.** A correct answer drawn from parametric knowledge scores badly; a confidently wrong answer consistent with bad retrieved context scores well. Two different failure surfaces — conflating them misdirects every subsequent fix.

## Nugget-based eval (the genuinely new 2025–26 technique)

For long-form or diffuse answers where string match is brittle and embedding similarity is vague, nugget scoring is the current answer. TREC's **AutoNuggetizer** ([arXiv:2411.09607](https://arxiv.org/abs/2411.09607)) refactored the 2003 TREC QA nugget method for the LLM era: (1) *creation* — distill passages into atomic facts, each labeled **vital** or **okay**; (2) *assignment* — label each nugget **support / partial_support / not_support** against the system answer. Calibration across 301 topics gave run-level Kendall's τ ≈ **0.78–0.90** against human judgment, with **per-topic agreement noticeably lower** — so it ranks systems well and grades individual answers less well. Load-bearing calibration finding: **LLMs apply stricter assignment labels than human assessors**, so an automated pipeline under-credits answers unless you recalibrate.

TREC 2025 moved nugget generation to a multi-LLM ensemble (Gemini 2.5 Pro, GPT-4.1, Qwen3 Thinking 32B, GPT-OSS 120B, merged by GPT-4.1), assignment to **listwise** (one model judges the whole answer against all nuggets at once), and added **sub-narrative mapping** — a sub-narrative counts as covered only if at least one mapped nugget is fully supported, which catches answers that are accurate but only address part of a complex query. 150+ submissions. TREC RAG 2026 is live (topics July 6 2026, deadline Aug 8 2026, results pending); its corpus changed from MS MARCO v2.1 to **ClimbMix-400b** — pin corpus version before comparing your numbers to any published TREC baseline.

Related: BEIR/MTEB are saturated and partly contaminated — 400+ models cluster within noise, and training pipelines routinely ingest BEIR-derived data. MTEB's response is **RTEB**, a retrieval section with private held-out sets where a large public/private gap is itself the cheating signal. Never pick an embedding model off a headline leaderboard without a held-out slice of your own corpus.

## Production signals worth alerting on

Offline evals go stale; these are the online counterparts. **No primary source establishes threshold values** — the alerting rule is on *your* baseline's drift, not on any published constant.

| Signal | Why it is the early warning |
|---|---|
| **Abstention rate** | Moves before quality metrics do. A rise means the corpus went stale, an index shard is missing, or query distribution shifted. A *fall* is worse: the system stopped abstaining and started fabricating. |
| **No-answer / zero-results rate** at the retriever | Distinguishes "retrieved nothing" from "retrieved junk." Zero-results spikes are usually filter or index bugs, not embedding drift. |
| **Judge parse-failure rate** | Silent 0/NaN scores masquerade as quality regressions (documented RAGAS failure mode). Alert on it separately from the score itself. |
| **`self_knowledge`-style parametric-answer rate** | Grounded system answering from parametric memory ⇒ retrieval is failing but is masked by model competence. Will break on the next unfamiliar question. |
| **Retrieval-log citation join failures** | Citations to documents that were never retrieved. Free to compute, catches fabricated citations that groundedness scores miss entirely. |
| **Score-by-span, not just end-to-end** | A trace where retrieval scored low but the final answer scored high is a **distinct, detectable hallucination signature** — an end-to-end number erases it. |

## NEVER

- **NEVER report any-hit Recall@k on a workload with multi-hop or diffuse-evidence queries** — WHY: one lucky chunk satisfies it while the generator is missing 3 of the 4 facts it needs. Report Accuracy@K alongside, stratified by hop count.
- **NEVER judge a reranker on aggregate Recall@10 or MRR** — WHY: the reranker paradox raises both while lowering Accuracy@3. Log per-query rank deltas.
- **NEVER compare RAGAS scores across judge models or versions** — WHY: identical retrievals scored 0% to 80%+ depending only on the judge. Pin `(judge model, version, metric variant)` and read deltas only.
- **NEVER use the generator model as its own faithfulness judge** — WHY: self-enhancement bias, compounded by the general LLM-judge preference for verbose confident answers over well-calibrated hedging.
- **NEVER use a synthetic golden set to rank generator models** — WHY: it is valid for retriever-configuration comparisons and demonstrably not for generator-architecture comparisons; question phrasing interacts with output style.
- **NEVER optimize before running the closed-book and oracle controls** — WHY: without both bounds, "score is 0.58" cannot distinguish "retrieval is bad" from "even perfect retrieval tops out at 0.60."
- **NEVER score only the final answer** — WHY: an end-to-end number cannot attribute a failure to retriever, reranker, or generator, and it destroys the low-retrieval-score/high-answer-score hallucination signature.
