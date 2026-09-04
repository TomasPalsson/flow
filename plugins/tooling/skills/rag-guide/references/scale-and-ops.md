---
name: scale-and-ops
description: Depth on running retrieval in production — context rot and the effective-context ceiling, stuff-vs-retrieve caching arithmetic, semantic-cache false hits, the indexing/freshness pipeline, cost attribution, degradation, rollout, observability. Load when a working system has to survive traffic, change, and time; skip while still diagnosing wrong answers (use diagnosis.md) or choosing components (retrieval-stack.md).
---

# Scale and Operations

Confidence tiers are marked throughout. The latency table and every dollar figure are **unverified** — the research pass could not reach primary benchmarks for them. Directional relationships (generation dominates, reranking is the swing variable, vector-DB choice barely moves the bill) are corroborated across independent sources; the specific numbers are not.

## Context rot — what was actually measured

[Chroma Research, July 2025](https://research.trychroma.com/context-rot): 18 models (Claude Opus 4 / Sonnet 4 / 3.7 / 3.5 / Haiku 3.5; o3; GPT-4.1 +mini/nano; GPT-4o; GPT-4 Turbo; GPT-3.5 Turbo; Gemini 2.5 Pro/Flash, 2.0 Flash; Qwen3 235B-A22B/32B/8B), **194,480 calls**, 8 input lengths × 11 needle positions. Under *minimal-complexity* conditions — far easier than any real workload — every model degraded non-uniformly, well before its documented limit. The authors' own caveat is the load-bearing one: real applications are harder, so production rot is likely **worse** than what they measured. They claim no mechanistic explanation.

| Experiment | Result | What it changes in your design |
|---|---|---|
| Needle–question similarity | Lower similarity → degradation gets *steeper with length*. Needle **position** showed "no notable variation" in this NIAH setup | The variable is ambiguity × length, not length. For literal-match tasks, position-shuffling fixes aim at the wrong knob. |
| Distractors | "Even a single distractor reduces performance relative to the baseline"; four compound it; effect size depends on *which* distractor, not only how many | Precision at small k beats recall at large k. Near-misses, not random noise, are what cost you. |
| Haystack coherence | Shuffling sentence order (destroying logical coherence) **improved** accuracy, consistently across all 18 models | The most counterintuitive result in the study: coherent prose makes a *more plausible*, therefore better, distractor; incoherent text is obviously irrelevant and easy to ignore. Do not assume a well-organized context is a safer context. |
| LongMemEval | 306 prompts, ~113K-token full inputs vs ~300-token focused versions; focused beat full **universally**, all models | Trimming to what's relevant reliably beats dumping history — including on models marketed for long-context conversational memory. |
| Repeated-words copy | The simplest possible long task degrades with length; some models emit tokens that never appeared in the input | Even the floor is not clean. |

**The model-family split matters for routing:** Claude models had the *lowest* hallucination rates under distractor load — they prefer abstention; GPT models had the highest. A pipeline with a weak sufficiency gate inherits its failure mode from the generator family it runs on.

Anthropic's independent framing matches: recall degrades as tokens grow, attributed to n² attention diluting per-token representational capacity plus a pretraining distribution dominated by short sequences — "a performance gradient rather than a hard cliff" ([effective context engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)).

**Reconciling with Liu et al. 2023.** With a *real* retriever (Contriever/MS-MARCO over NQ-Open), reader accuracy **saturates** rather than declines: 20→50 documents bought ~1.5% (GPT-3.5-Turbo) and ~1% (Claude-1.3) while retriever recall kept climbing. Chroma's distractors were deliberately irrelevant-but-plausible. The two agree once you state the rule properly: **the risk of adding context scales with the plausibility-weighted irrelevance of what you add, not with the count.** Raising k stays safe while document #40 is still topically relevant; it turns actively harmful the moment you exhaust the genuinely relevant documents and start scraping near-misses.

## Advertised vs effective context

NIAH is a **floor test** — fail it and you are in trouble; pass it and you have learned nothing about adequacy. It rewards literal string retrieval from an obviously irrelevant haystack, which is a far easier subtask than semantic retrieval or reasoning.

| Instrument | What it establishes |
|---|---|
| **NoLiMa** (Modarressi et al., ICML 2025, [arXiv:2502.05167](https://arxiv.org/abs/2502.05167)) — minimizes literal overlap, forces associative matching | At **32K tokens, 10 of 13** tested 128K+-context models fell **below 50% of their own <1K baseline**. GPT-4o: 99.3% → 69.7%. |
| **RULER** (NVIDIA, [arXiv:2404.06654](https://arxiv.org/abs/2404.06654)) — multi-task; "effective length" = longest length still scoring ≥85.6% | Roughly **half** the models claiming ≥32K did not clear the bar at 32K; nearly all fell below before their claimed max. Limitation worth stating: 85.6% is Llama-2-7B's 4K baseline — an arbitrary anchor. |
| **HELMET / LongBench v2** | Real-task signal; HELMET includes an explicit RAG subtask. LongBench v2 difficulty calibration: human experts with search tools and 15 min/question scored **53.7%** — "hard long-context task" does not imply "solvable with more context." |

**The circulating "effective context = 50–65% / 60–70% of advertised" percentages are unsourced.** They trace to content-farm pages, not to Chroma, NoLiMa, or RULER's published numbers. Cite the instrument and its measured drop; never quote a percentage-of-advertised figure. Vendor pricing is a useful tell: Anthropic prices the full 1M Opus 5/Sonnet 5 window flat with no >200K tier, while Gemini still bills higher past 200K — an implicit admission that the >200K regime is different.

## Stuff vs retrieve — the arithmetic and its two traps

Break-even falls straight out of the 0.1× cached-read multiplier all three vendors converged on: stuffing and retrieving cost the same when a typical query needs ~10% of the corpus. Run it rather than estimating — `scripts/rag_calc.py stuff` takes corpus size, query rate, and prices and prints the break-even corpus size:

```bash
python scripts/rag_calc.py stuff --corpus-tokens 400000 --queries-per-day 1440 \
  --retrieved-tokens 10000 --price-input 5.0 --price-cached-read 0.50 --price-cache-write 6.25
```

That command (Aug-2026 Opus 5 rates: $5/MTok input, $6.25 5-min write, $0.50 cached read) prints $290.30/day for stuffing a 400K-token corpus with a perpetually warm cache versus $79.20/day for RAG retrieving 10K tokens — ≈$0.20 vs ≈$0.055 per query, **RAG ≈3.7× cheaper**, before counting any accuracy effect. Re-run it with your own prices rather than trusting these; the rates are dated and the ranking can flip on corpus size.

**Trap 1 — the cold cache inverts the result.** TTLs: Anthropic 5 min default (1.25× write) / 1h opt-in (2× write); GPT-5.6+ a flat 30 min, and it now charges a 1.25× write where earlier OpenAI generations charged none. At one query every 20 minutes the cache expires between requests and *every* query pays the write: ≈$2.50/query cached vs $2.00/query **uncached** vs $0.06 for RAG. Caching a large prefix at low query volume is strictly worse than not caching at all.

**Trap 2 — exact-prefix matching.** One changed token near the start of the cached block invalidates it and everything after. A corpus that changes faster than query volume can amortize a fresh write is functionally uncachable; incremental index updates have no such all-or-nothing property. Gemini differs structurally: explicit caching bills *storage* (~$1.00/M tokens/hour Flash-tier, $4.50 Pro-tier), so a long-lived, rarely-hit cache can cost more than no cache.

**CAG** (preload everything, skip retrieval; Chan et al., [arXiv:2412.15605](https://arxiv.org/abs/2412.15605)) is a real published technique, but its own authors scope it to small, static, fully-in-context knowledge bases — both traps above are the authors' stated limitations, not critics'. Prompt-caching mechanics beyond this arithmetic (breakpoint placement, why `cache_read_input_tokens` stays 0, per-model minimums) → **agent-architecture**.

## Latency — orders of magnitude, not SLOs

**Unverified, all rows.** Use this to answer "which order of magnitude is this stage," never to write an SLO. Hardware, batch size, quantization, and network topology move every row by a large factor.

| Stage | Magnitude (unverified) | The non-obvious part |
|---|---|---|
| Query embedding | tens of ms | The surprise is cold model load or a cross-region API hop, not the encode itself. |
| ANN search, warm | single-digit to tens of ms | Retrieval in the *hundreds* of ms is almost always a config bug — unindexed filter, oversized top-k, or an HNSW working set spilling out of RAM (random graph traversal → page churn, ms→seconds). pgvector: tune `effective_cache_size` or the planner misprices disk fetches. |
| Metadata filtering | adds low tens of ms | Reported to cut real QPS **40–60%** vs an unfiltered benchmark — the usual explanation for the gap between vendor headline QPS and yours. |
| Reranking | tens of ms to seconds | **The swing variable, and the widest spread in the table**: ~15ms (FlashRank on CPU) to 2.5s+ (BGE); hosted APIs add a reported 150–400ms network hop. One benchmark attributed **62–84%** of total pipeline latency to reranking alone. |
| Generation | low seconds | 60–85% of end-to-end. The only real levers are model size and output length. |

Make reranking **conditional** (fire on low first-stage confidence) before touching the vector DB — an ~800ms end-to-end budget effectively forces it. A rough starting envelope, also unverified: retrieval+rerank ≤200–300ms, TTFT ≤800ms–1.2s p95.

## Caching layers — the false hit is the headline risk

Three layers, descending safety. Prompt cache (provider-side, safe) → embedding + retrieval-result cache keyed on the *normalized query* (safe, because an exact-match trigger is far stricter than a fuzzy one; ≈30% repeat-query rates are a grounded planning baseline, meaning roughly a third of traffic can be payable-once) → **semantic response cache, which is where correctness goes to die**.

A semantic cache returns a stored answer when the incoming query's embedding sits within threshold (commonly 0.92–0.97) of a cached one. **A miss only costs money; a false hit costs correctness.** That asymmetry makes a hit-rate dashboard with no false-hit denominator an instrument that actively rewards the wrong behavior — hit rate improves monotonically as you loosen the threshold, which is the exact direction that manufactures confident wrong answers.

Concrete false-hit patterns:
- **Polarity/intent flip** — "how do I upgrade my subscription" vs "how do I cancel my subscription": embedding-adjacent, opposite intent.
- **Parameter difference** — "MAU in Q1 2024" vs "Q1 2025" can exceed **0.95 cosine** under common embedding models with completely different correct answers.
- **Lost conversational context** — a follow-up like "change the color to red" matching an *unrelated conversation's* follow-up. One benchmark reported **54 false hits** for naive GPTCache vs **3** for context-chain-aware MeanCache on the same test set.

Mitigation ladder, in leverage order: (1) start at **0.92** for factual/RAG workloads, monitor the false-positive rate for 48h, move in 0.01 increments — below ~0.90 dissimilar queries start matching; (2) require agreement across several independent equivalence checks rather than one cosine score (≈20ms extra per lookup); (3) context-chain verification for multi-turn; (4) hash-invalidate every entry derived from a source document the instant that document changes, and give genuinely time-sensitive facts a short hard TTL instead of similarity caching — content that should change as the world changes is bad semantic-cache material at any threshold.

## The indexing pipeline is the real ops burden

The vector database is rarely the bottleneck; the sync pipeline that keeps it correct is where the engineering time goes. This section covers the *pipeline* — delivery, failure handling, scaling. The correctness *invariants* it depends on (stable IDs, content hashing, orphan deletion on rename, chunking-config versioning) are in [`ingestion.md`](ingestion.md); a pipeline built without them will run efficiently and stay wrong.

- **Push over pull where the source supports it.** A scheduled crawl is simpler but its staleness window *equals* the crawl interval; webhooks/CDC (Confluence, Notion, S3 events, Postgres logical replication) give near-real-time updates and — the underrated part — native **delete signals**. Either way, assume at-least-once delivery and deduplicate downstream; idempotency is mandatory, not defensive.
- **Diff at chunk level, not document level.** Hash per chunk, re-embed only changed chunks, preserve the rest. This is the single biggest lever on ongoing re-index cost because most edits touch a small fraction of a document. One team's own infrastructure data: incremental sync was faster *and* roughly half the cost of full reprocessing.
- **Carry per-chunk metadata** — `doc_id`, `doc_version`, `chunk_id`, `chunk_hash`, `embedding_model`, `chunking_config_version`, `source_modified_time`. Without it, a mixed-version index after a partial reindex is undetectable, shadow rollouts are unsafe, and a stale answer is indistinguishable from a fresh one when you debug a complaint a week later.
- **Deletes are tombstones.** HNSW cannot cheaply remove a node from an immutable segment; a bitset flip hides the ID and background compaction reclaims space and rebuilds later (one practitioner trigger: ~20% tombstoned — a rule of thumb, not a vendor spec). An "update" is delete-plus-insert underneath, not a mutation.
- **Re-embedding on a model upgrade is a migration, not a config change.** Staged: double-write → backfill → dark reads → switch reads → switch writes → decommission after a full business cycle. Backfill is a horizontal-scaling problem, not a per-node tuning one — one documented case embedded ~30M reviews across 406 GPUs at 364.4k tokens/s, turning a 20-hour job into 2.3 hours, $710 → $277 on spot.
- **Dead-letter the poison documents.** Separate transient failures (network, rate limits → retry with backoff) from permanent ones (deserialization, validation → quarantine immediately), side-output with enough context to replay, and alert on **DLQ depth growth** as a first-class signal. Without it, one malformed document either blocks everything queued behind it or is silently dropped.
- **Circuit-break anomalous change volume.** One vendor reroutes to human review when >~45% of a source's pages change in a single sync cycle — the signature of a site redesign or a misconfiguration, not editorial activity (single-vendor practice, reasonable to copy).

## Freshness — silent by construction

Cosine similarity is time-blind. An embedding of a deprecated policy scores exactly as well as its replacement, so while both sit in the index retrieval returns whichever scores higher — *not* deterministically the newer one. Context recall and faithfulness keep looking healthy the whole time, because nothing about retrieval is broken; the corpus is lying about what is current.

Three freshness problems get conflated. Each needs a different fix:

| Shape | Example | Fix |
|---|---|---|
| **Hard expiry** | recalled policy, closed promotion | **Remove or filter it out** before the model sees it. Decay only down-weights — it never removes, so the document still surfaces whenever nothing outranks it. |
| **Time-bound** | active outage notice | Explicit validity window. It is the single most important document while the window is open and completely wrong the moment it closes; no decay curve expresses that. |
| **Versioned/evolving** | a policy revised periodically | The one case where time-decay is the right tool: `score = α·cos(q,d) + (1−α)·0.5^(age_days/h)`, α≈0.7, half-life h≈14d. For explicit "as-of" queries, filter the corpus to what existed as of that date instead of decay-scoring. |

Staleness SLO template (practitioner pattern, not a standard): `staleness = time_since_update / acceptable_refresh_interval_for_this_document_class`, thresholded per class — safety/compliance at zero tolerance, reference ~30d, contextual ~90d. Monitor **nearest-neighbor stability**: run fixed canonical queries on a schedule and compare top-10 IDs to a baseline; 85–95% overlap is healthy, below ~70% is a warning. Verify at ingest by re-retrieving immediately after insert and confirming the indexed version matches, retrying with backoff on mismatch — that catches a reindex that crashed partway and left documents straddling two versions.

**The unsolved case is implicit expiration.** A tutorial for a deprecated API endpoint carries no expiry field. Heuristics catch explicit dates and version numbers; the rest surface only when a user gets a wrong answer. Worse: **an eval set built while a now-outdated document was still current keeps passing indefinitely**, because nothing in the eval process detects that its ground truth rotted underneath it.

## Cost — where it actually is

- Generation is **~95% of marginal per-query cost**. Query embedding is fractions of a cent; one vendor published a single vector read around $0.000016 (point-in-time). **So the vector-DB product choice barely moves the bill** — it is a latency and operability decision, wildly out of proportion to the argument it attracts. The real vector-DB cost is the fixed monthly hosting bill, not the per-query charge.
- **The standing pipeline can dwarf per-query cost.** One audit cited retrieval infrastructure above **$47,000/month** *before* counting three engineers handling embedding drift. Reported marginal per-query costs (≈$0.002–$0.02) exclude build cost and the standing spend to keep the corpus synced and fresh — quoting them as "what RAG costs" understates the bill by the part that actually hurts.
- Highest-leverage optimization is fewer, sharper context tokens (rerank, tighter chunks) plus model routing — reported to cut 60–70%, blog-sourced, not a controlled result.
- Scale tiers circulating in consultancy posts (~$300–1,600/mo small, up to $8,000–35,000/mo enterprise) have undisclosed methodology and mix one-time build with recurring run cost; one source frames cross-architecture variability as a **factor of 1 to 20**. Use for scoping a project, never as a defensible budget.

## Degradation and abstention

- **A reranker failure should degrade quality, not availability.** Explicit fallback chain — local cross-encoder ↔ managed API in either primary/backup order — and on total failure fall back to the first-stage ranking (bi-encoder or BM25) rather than failing the request.
- **Total vector-store outage is genuinely under-sourced.** No solid 2026 source was found for keyword-only fallback paths or cross-region read-replica failover mid-outage; a semantic response cache absorbs a subset of outage traffic at best. Treat this as a gap you must design deliberately, not a pattern you can look up.
- **When nothing crosses threshold, abstain.** Gate on a calibrated combination of retrieved-result count, top similarity, reranker confidence, and a query-complexity penalty — not a single global cosine cutoff. Corrective-RAG generalizes it: classify each retrieved document Correct/Incorrect/Ambiguous, strip irrelevant evidence, and caveat partial matches rather than synthesizing over them.
- **Write the degraded contract — including the user-facing copy — before the outage**, or it gets written badly under pressure. And note the monitoring gap: a weak answer that still returns HTTP 200 with text passes any check that only looks for hard failures. "Completed" is not "useful."

## Rollout

A **shadow index** is mandatory for an embedding-model or chunking change, because vectors from different model versions live in non-comparable spaces and cannot be mixed in one query. Pattern: build the new index fully in parallel → validate against a golden query set → **atomic alias swap** → keep the old index warm through a rollback window. The alias swap is what guarantees no query ever sees a partially-migrated index — the exact failure where a crashed reindex leaves some documents at version N and others at N+1 with the seam invisible at the retrieval layer.

**Offline wins routinely fail to reproduce online**, because production query distributions are messier and more ambiguous than any curated set. One paper's offline A/B — real production queries, generation held constant, blind pairwise judging, and framed by its own authors as a deployment sanity check rather than hypothesis testing — preferred the improved system in only **54.6%** of paired comparisons after excluding ties. That is one data point that the gap is real and can be large; it is *not* a rule that online gains are half of offline. Gate on the golden set, ramp gradually, and measure retrieval and generation as **separable** stages so a regression is attributable rather than a vague "the answers got worse" — a real regression in one layer hides comfortably inside an acceptable blended score.

## Observability

Emit a span tree, not flat logs: query → embedding → retrieval → reranking → context assembly → generation. Per stage: raw and rewritten query plus user ID; top-k similarity scores and retrieved chunk IDs; post-rerank scores **and the actual text of the chunks that survived**; the full assembled prompt, the response, and token counts. That chunk text is the single most valuable artifact when a user reports a bad answer — it separates "reasoned badly over good context" from "reasoned faithfully over the wrong context," which is a retrieval bug wearing a generation costume.

Grain: **chunk-as-attribute, not span-per-chunk.** A span per retrieved chunk explodes trace volume for no debugging benefit unless something chunk-specific happened to it; log per-chunk timing as span events.

**OpenTelemetry GenAI semantic conventions are `Status: Development`** — verified in the spec repo ([`open-telemetry/semantic-conventions-genai`](https://github.com/open-telemetry/semantic-conventions-genai), `docs/gen-ai/gen-ai-spans.md`, Aug 2026), cross-referencing semantic-conventions v1.44.0 / opentelemetry-specification v1.56.0. Every GenAI span and nearly every `gen_ai.*` attribute carries the Development badge; only borrowed general-purpose attributes (`error.type`, `server.address`, `server.port`) are Stable. Six span categories exist (Inference, Embeddings, Retrievals, Fetch response, Memory, Execute tool) and **there is no dedicated RAG or vector-database span type** — retrieval appears only as a generic operation value. Practical consequence: align with the shape (`gen_ai.*` naming, `CLIENT` span kind), pin the spec version, isolate the attribute strings behind a thin mapping layer, and expect to hand-instrument retrieval logic.

Production canaries: sample ~1–2% of traffic plus **100% of thumbs-down**, batch-judge hourly on faithfulness and relevance with a cheap model, and alert on *trend change* rather than an absolute threshold — a "good" faithfulness score is application-specific, so a fixed global bar produces noisy alerts. **Track distributions, not means**: 0.90 average with 10% catastrophically wrong is worse in production than a uniform 0.85, and mean-only alerting will never surface that tail before a user does. Drift signals worth a continuous line: average top-k similarity, nearest-neighbor stability on canonical queries, recall@K/MRR trend — retrieval drift usually moves before answer quality visibly does. Judge construction, sampling, and significance → **agent-evals**.

## Ops NEVER list

- **NEVER rerank every query unconditionally** — WHY: it is the largest controllable latency line after generation (~15ms to 2.5s+ depending on model and hosting), and most queries do not need it; condition it on low first-stage confidence.
- **NEVER report semantic-cache hit rate without a false-hit rate** — WHY: hit rate improves monotonically as you loosen the threshold, so a hit-rate-only dashboard rewards exactly the change that produces confidently wrong answers.
- **NEVER rebuild the full index on a content change** — WHY: cost scales with total corpus size instead of delta size, and the rebuild window is itself a period of index inconsistency.
- **NEVER re-embed in place during a model upgrade** (null out embeddings, resize the column, backfill live) — WHY: old and new vectors are non-comparable, so there is no point in the migration at which queries can safely run; search is broken for every document for the whole window.
- **NEVER let time-decay stand in for hard expiry** — WHY: decay down-weights but never removes, so a recalled or legally-expired document still surfaces whenever nothing else outranks it.
- **NEVER trust a published ANN QPS/recall number without re-testing under your own filter and concurrency profile** — WHY: vendor figures are typically single-threaded and unfiltered on chosen hardware; metadata filtering alone was reported to cut real QPS 40–60%.
- **NEVER let the offline eval be the only gate** — WHY: it is reproducible but not representative, and it silently keeps passing after its ground truth goes stale.
