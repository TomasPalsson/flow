---
name: rag-guide
description: "Building, debugging, and scaling retrieval systems — RAG, vector search, agentic retrieval, and whether to retrieve at all. Use when: building or fixing a RAG pipeline; answers are wrong, hallucinated, or missing though the document exists; choosing embeddings, vector store, chunking, reranking, or hybrid search; deciding RAG vs long-context vs fine-tuning vs GraphRAG vs SQL; securing a corpus (prompt injection via documents, ACL-aware retrieval, multi-tenancy, PII, erasure); measuring retrieval quality; retrieval over a codebase; or on a managed platform, especially AWS Bedrock Knowledge Bases. Keywords: RAG, vector database, embeddings, chunking, hybrid search, BM25, reranker, knowledge base, citations, context rot, GraphRAG, agentic search, pgvector, recall@k, Bedrock Knowledge Base, RetrieveAndGenerate, OpenSearch Serverless, 'why is my RAG bad'. Do NOT use for: LLM/agent eval methodology (use agent-evals) or agent architecture and caching economics (use agent-architecture)."
---

# Retrieval-Augmented Generation

Most RAG advice is a list of fixes for *specific* failures, handed out without diagnosing which failure you have. Applied blind, much of it makes things worse: hybrid search **hurts** a strong dense retriever, semantic chunking **loses** to plain recursive splitting on answer accuracy, and retrieving more context **lowers** F1 past a small k. This skill is organized around diagnosis first, because that is what separates people who fix RAG systems from people who rebuild them.

Figures are dated to **August 2026** and tiered: **stated as fact** = traced to a primary source (paper abstract, vendor doc, release API); **"reported"/"≈"** = one credible source, not reproduced; **"unverified"** = named as such. A final section lists widely-circulated numbers that are **wrong** — you will meet them elsewhere.

## Scenario router — load the ONE reference that matches

Read the matching reference **fully**; load **only** what a row points to. Each is ~100–150 dense lines — loading all of them wastes the context you are trying to protect.

| The task in front of you | Load (entire file) |
|---|---|
| Parsing, tables, chunking, contextual retrieval, sync/re-ingest | [`references/ingestion.md`](references/ingestion.md) |
| Embedding choice, hybrid/fusion, rerankers, vector store, filtered search, migration | [`references/retrieval-stack.md`](references/retrieval-stack.md) |
| "It gives bad answers" — isolating and measuring the failure | [`references/diagnosis.md`](references/diagnosis.md) |
| Prompt shape, abstention, citations, conflicting docs, multi-turn | [`references/generation.md`](references/generation.md) |
| Prompt injection, ACLs, multi-tenancy, PII, erasure, poisoning | [`references/security.md`](references/security.md) |
| Latency, cost, caching, indexing pipeline, freshness, rollout | [`references/scale-and-ops.md`](references/scale-and-ops.md) |
| Aggregation/SQL questions, GraphRAG, code retrieval, agentic routing | [`references/beyond-vector.md`](references/beyond-vector.md) |
| **AWS Bedrock Knowledge Bases**, Vertex, Azure, or any managed RAG platform; build-vs-buy | [`references/managed-platforms.md`](references/managed-platforms.md) |
| Deciding *whether* to retrieve, or triaging a failure | none — stay here (Decisions 0 and 1) |

**Defer, don't duplicate:** eval methodology (judges, sample sizes, significance) → **`agent-evals`**. Token economics, prompt-caching mechanics, agent architecture → **`agent-architecture`**.

## Decision 0 — Does this need retrieval at all?

Walk down. Stop at the first rung that passes your evals. Most teams start at rung 3 and never revisit.

```
1. No retrieval        Model already knows it, or the answer is not in any document.
                       A "don't retrieve" branch is the most-skipped routing decision.
       ↓ corpus is small and static?
2. Put it in the prompt   Anthropic's own guidance: under ~200K tokens, skip retrieval
                          entirely. Infrastructure you don't build, you don't operate.
       ↓ corpus too big, or changes often?
3. Retrieve            Single-pass: retrieve → rerank → generate. Correct for the
                       bulk of production traffic, which is simple lookup. (The
                       "60-70%" figure you'll see quoted has no traceable
                       methodology — measure your own mix.)
       ↓ query needs exploration, not lookup?
4. Agentic retrieval   Model calls search as a tool, reads, refines. 2-8x tokens.
```

**The stuff-vs-retrieve line is corpus size, not query volume.** With cached reads ~10x cheaper than uncached input, stuffing stays cheaper while the corpus is under **~10x your per-query retrieved context**. The same arithmetic read from the other end: stuffing wins once a typical query needs more than ~10% of the corpus anyway. (Note this is a *cost* boundary and is distinct from Anthropic's ~200K-token guidance above, which is an architectural one — they only coincide when your retrieved context is ~20K tokens.) Run it rather than guessing:

```bash
python scripts/rag_calc.py stuff --corpus-tokens 180000 --queries-per-day 500
```

Two traps this catches. **Cold cache**: if queries arrive slower than the cache TTL, every query pays the write premium and never collects the read discount — caching *costs* you money. **Context rot**: cheaper-to-stuff does not mean better answers. Quality degrades well before the advertised window, non-uniformly (see Decision 3).

## Decision 1 — Where is the failure? (the prime directive)

**Read the actual retrieved chunks for ten failing queries before changing anything.** A CHI 2026 study of RAG debugging found practitioners overwhelmingly work retriever-first, and one put the reason plainly: you can iterate on a prompt all you want — it cannot recover evidence that was never retrieved.

**MANDATORY when a system is already broken — open and fill in [`scripts/triage.md`](scripts/triage.md)** before changing chunking, embeddings, fusion, or adding a graph. It forces the tally that decides which fix is even applicable, and it has two gates that catch expensive mistakes: *the document isn't in the index* and *retrieval is scoring worse than no retrieval at all*.

Then put a number on it with the **oracle-context test**: hand the generator the known-correct passage and measure the ceiling.

```bash
python scripts/rag_calc.py ceiling --oracle 0.81 --live 0.44   # retrieval-bound or generation-bound?
python scripts/rag_calc.py recall  --file run.jsonl            # recall@k curve + where k saturates
```

- **Oracle low (<~0.75)** → generation-bound. Retrieval work is capped; fix prompt shape, model, or accept the question is unanswerable from this corpus.
- **Oracle high, live far below** → retrieval-bound. Spend upstream, in the leverage order below.
- Bracket it with a **closed-book floor** (no context) too. In a combustion-science RAG study ([arXiv:2603.04452](https://arxiv.org/pdf/2603.04452)) a *noisy* configuration scored **worse than zero-shot** (21.1% vs 23.35%, against an 87.3% oracle ceiling) — retrieval can be net-negative, and only the floor reveals it.

**MANDATORY — READ ENTIRE FILE** before designing metrics, building an eval set, or interpreting retrieval scores: load [`references/diagnosis.md`](references/diagnosis.md). It has the seven isolation experiments, the metric traps, and the synthetic-golden-set circularity problem. **Do NOT** load the ingestion, security, or ops references for this step.

### The leverage ladder — what actually moves the needle

Ordered by measured payoff per unit of effort. Working out of order is the most common way teams waste a quarter.

| Rank | Lever | Why it sits here |
|---|---|---|
| 1 | **Parsing quality** | Unbounded and irreversible. A dropped table or scrambled reading order cannot be recovered by any downstream stage. |
| 2 | **Is the answer even in the corpus?** | Free to check, and frequently the real answer. This is a documentation problem wearing a retrieval costume. |
| 3 | **Contextual retrieval** | Best-evidenced single technique: retrieval-failure rate 5.7% → 3.7% (contextual embeddings) → 2.9% (+ contextual BM25) → 1.9% (+ reranking). |
| 4 | **Reranking** | Cheap precision at the top. Retrieve wide (50–100), rerank hard, pass few. |
| 5 | **Query contextualization** (multi-turn) | Rewrite follow-ups into self-contained queries — *only when needed*. Rewriting every turn adds noise. |
| 6 | **Chunking strategy** | **Bounded**: ~8–9 recall points separate the best and worst strategy on a matched corpus. Real, but not where 10x lives. |
| 7 | **Embedding model swap** | Forces a full re-index and invalidates every tuned threshold. High cost, usually modest gain. |

**On a managed platform, rungs 1, 3, and 6 may not be yours to pull.** Bedrock Knowledge Bases, Vertex, and Azure each fix some of parsing, chunking, and contextualization behind their own defaults — so the ladder above can bottom out at a wall rather than a fix. The escape hatch is almost always the same shape: keep managed *ingestion* but take back the parts you need, by pre-chunking upstream and calling the retrieve-only API with your own reranking and generation. Load [`references/managed-platforms.md`](references/managed-platforms.md) before concluding a managed platform "can't do" something — the constraint is often a KB-type choice made at creation time, not a platform limit.

## Decision 2 — Is this a retrieval question at all?

A large share of "RAG doesn't work" is a **routing** failure, not a retrieval failure.

| Query shape | Right tool | Why retrieval cannot do it |
|---|---|---|
| "How many…", "top 5 by…", "trend since…" | **SQL / semantic layer** | The answer is a computed aggregate that exists in no passage. Better embeddings cannot help. |
| "What does the contract say about X" | Vector + rerank | Single-hop passage lookup — the default case. |
| "How are A and B connected", "main themes across the corpus" | Graph *only if* you can name 5–10 real such queries from logs | GraphRAG indexing reportedly ran **$33,000 for one 5GB corpus** (one credible source, breakdown paywalled); entity resolution, not graph construction, is the hard part. |
| Exact identifiers, symbols, error strings | Lexical/grep | Exact match beats semantic neighbors. |

**Semantic layer vs raw text-to-SQL is a failure-mode choice, not an accuracy choice**: text-to-SQL fails as a *plausible but wrong number*; a semantic layer fails as an *error message*. For anything reaching a dashboard or an auditor, that difference dominates.

## Decision 3 — Pipeline or agentic retrieval?

The "RAG is dead" claim traces to Claude Code dropping embeddings for agentic grep. Two things are worth knowing before repeating it. First, the widely-quoted admission that the evaluation was "internal vibes, with some internal benchmarks" is **secondary-sourced and could not be traced to a primary record** — treat it as reported, not quoted. Second, the one independent factorial study on the question ([arXiv:2605.15184](https://arxiv.org/abs/2605.15184), May 2026) is **not about code at all** — it runs on conversational memory, and its authors explicitly decline to claim grep beats vector in general, naming code semantics as a domain where it may differ.

What that study *does* establish transfers better than the anecdote: **how results are delivered to the agent matters as much as which retriever produced them.** Grep won all 10 harness-model pairs when results were inlined, but file-based delivery flipped it — vector won 5 of 10, and one pair collapsed 93.1%→55.2% under programmatic grep. Same backbone, same retriever, different flow: 93.1% vs 76.7%. Before swapping retrievers, check how the results reach the model.

Route per query rather than picking a side. The one design rule that transfers everywhere: **return handles first, hydrate on demand** — a search tool should return IDs, titles, and snippets, with a separate call to fetch full text. In Anthropic's Tool Search Tool benchmark, deferring tool definitions this way cut tokens ~85% (77K→8.7K) *and raised task accuracy from 49% to 74%* on Opus 4 ([advanced tool use](https://www.anthropic.com/engineering/advanced-tool-use), Nov 2025 — vendor-published, on tool schemas rather than retrieved documents, so read it as directional for retrieval). The mechanism is the point: dumping full results into context is not merely expensive, it degrades judgment.

**Context rot is the mechanism.** Across 18 models and ~194K calls, accuracy degrades with input length well before any limit — a gradient, not a cliff. A *single* distractor measurably hurts. Counterintuitively, shuffling the surrounding text *improved* results: coherent context makes a **better** distractor. And the harmful chunks are the near-misses a similarity reranker promotes — random irrelevant documents are comparatively harmless.

## Security — one decision dominates the rest

Map the **lethal trifecta** onto RAG: the corpus is the private data, retrieved chunks are the untrusted content. A read-only Q&A assistant is missing the third leg. **The moment you add a tool that can email, post, ticket, or call an API, the trifecta closes and your corpus becomes the injection vector.** Treat "does this system have an outbound tool" as a higher-leverage decision than any prompt-level defense — no measured defense reaches zero attack success.

**MANDATORY — READ ENTIRE FILE** before shipping anything multi-tenant, permissioned, PII-bearing, or ingesting untrusted content: load [`references/security.md`](references/security.md).

## Symptom → cause → fix

| Symptom | Cause + the non-obvious *why* | First move |
|---|---|---|
| Confident answers citing the wrong thing | Citation APIs guarantee a valid *pointer*, not that the span *entails* the claim | Post-hoc entailment check on cited spans |
| Right doc exists, never retrieved | Vocabulary gap, or a filter silently excluding it | Grep the corpus first; then swap embedding model as an ablation |
| Retrieval fine, answers still wrong | Near-miss distractors; or query placed before the documents | Put documents first, query last (Anthropic reports "up to 30%" in unpublished internal tests — an upper bound, not a typical gain); tighten the relevance floor |
| Good demo, bad in production | Near-duplicate chunks, and eval built from 20 hand-picked queries | Dedup the index; mine real query logs |
| Highly-filtered queries return junk | HNSW graph disconnection below ~5% selectivity — **silent**, not an error | Pre-filter, or an engine with adaptive filtered search |
| Was right last month, wrong now | Staleness is silent by design — metrics look fine while the corpus is wrong | Freshness SLO; recency/authority tiebreak; delete orphaned chunks |
| Got slow and expensive | Generation dominates both latency and marginal cost; the reranker is the swing variable (magnitudes only — the underlying figures are unverified, see `scale-and-ops.md`) | Measure your own stages, then make reranking conditional before touching the vector DB |
| Cache made it *wrong* | Semantic-cache **false hit** — "upgrade" vs "cancel" sit close in embedding space | Raise threshold, add non-similarity verification; never share a cache across tenants |
| Fine turn 1, broken turn 3 | Retriever is embedding "what about the second one?" literally | Query contextualization step before retrieval |

## NEVER — the landmines

- **NEVER change anything before reading the retrieved chunks for real failing queries.** Every other item here is downstream of this one.
- **NEVER add hybrid search reflexively.** Fusing BM25 into an already-strong dense retriever reportedly *lowered* nDCG@10 (23.3→21.3, 24.1→21.2 — medium confidence, exact paper unconfirmed); it *raised* it for weaker models. Do add it for lexical/identifier recall, and because it blunts corpus poisoning cheaply — but read that defense narrowly: the headline co-retrieval 38%→0% is one corpus against an attacker who *wasn't adapting*, and joint sparse+dense optimization still lands 20–44% (`security.md`). Decide on measurement, not folklore.
- **NEVER post-filter for access control.** Leakage happens *before* the filter runs — via metadata, reranker features, and trace logs — and under-filling k creates pressure to loosen the filter. Filter during the ANN query; re-check the survivors late.
- **NEVER share a semantic cache across tenants, roles, or system prompts.** A cache hit skips the LLM call, and therefore skips that call's authorization context and safety checks.
- **NEVER treat embeddings as non-sensitive.** Inversion recovers ~92% of **32-token passages** exactly, and 89% of full names from clinical embeddings. If the vector store leaks, the documents leak.
- **NEVER treat a soft delete as erasure.** Tombstoned vectors can remain reconstructable on disk; GDPR needs hard delete plus compaction, and the sweep must also reach caches, traces, and backups.
- **NEVER mix embedding models between indexing and query,** and never carry a tuned similarity threshold across a model swap — scores are not comparable across models, corpora, or even queries. A global cosine cutoff is close to a category error.
- **NEVER add retrieved chunks because "more context is safer."** Recall@k and answer quality peak at *different* k — one reported 2026 analysis had Hit@k still climbing (0.726→0.834, k=2→5) while F1 peaked at **k=3** and fell after (primary source not pinned down — treat the *shape* as the finding, not the decimals). The mechanism is solid regardless: past the point where genuinely relevant documents run out, you are adding near-miss distractors.
- **NEVER forget instruction prefixes** (`query:` / `passage:`) on models that require them — there is no error, just quietly worse rankings.
- **NEVER build an eval set by asking an LLM to write questions from your chunks and stopping there.** The query is generated from the very chunk you then score as correct; recall inflates and the eval endorses whatever chunking you already chose.
- **NEVER ship GraphRAG on a demo.** Price the extraction pass first — it is multiple LLM calls per chunk plus summarization and community reports, and `beyond-vector.md` works the arithmetic for a realistic corpus. Budget entity resolution as its own project with its own eval; it, not graph construction, is where the effort actually goes.
- **NEVER let a system answer when retrieval found nothing.** A pipeline that cannot abstain converts every retrieval miss into a confident fabrication. Note the honest caveat: for capable models an abstention *instruction* mostly changes the wording, not the behavior — this needs a sufficiency gate, not a politer prompt.

## Numbers that circulate and are wrong

You will meet these in blog posts, in older versions of this guidance, and in other models' output. They do not survive contact with the primary source.

| Circulating claim | Reality |
|---|---|
| "Spotlighting cuts injection 73% → 3%" | The paper's headline is **">50% to below 2%"**, and **73% appears nowhere in it**. The "3" is a mangling of a real sub-result (datamarking, 3.10% on GPT-3.5 document QA) — so the pair is a fabricated baseline welded to a cherry-picked endpoint. Cite the headline or the specific model/task row, never the pair. |
| "Embedding inversion recovers 92% of tokens" | 92% **exact recovery of 32-token passages**, by an attacker who trained an inverter for that model. |
| "100% cross-tenant leakage in undefended systems" | Untraceable. Nearest artifact is an unsourced "95%" in a blog *title*, never defined in the body. |
| "Reasoning models hallucinate more — never use them for RAG (14.3% vs 3.9%)" | Current figures are **11.3% vs 6.1%**, and the category rule fails: reasoning-capable Gemini 2.5 Pro (7.0%) and Qwen3-thinking (9.3%) beat the median, while o3-pro (23.3%) is near the bottom. **Check the model, not the category.** |
| "87% of RAG failures are retrieval quality" (and its frequency table) | No traceable primary methodology. Directionally believable, quantitatively invented. |
| "BM42 replaces BM25" | Retracted — the vendor admitted a benchmark bug; independent reproduction showed it losing to BM25. |
| "RRF k=60 is optimal" | A flat optimum from a 2009 pilot study; k=30 beat it on a 2025 benchmark. Sweep it. |
| "LazyGraphRAG gives GraphRAG quality at 0.1% of the cost" | Announced Nov 2024, **still not in the OSS repo 19+ months later** — it ships only inside the vendor's own products. |
| "Prompt caching saves 50–75%" | ~**90% cached-read discount**, now consistent across Anthropic, OpenAI, and Gemini. |

## The five-second version

1. Read the failing queries' retrieved chunks. Run `ceiling` to learn whether you are retrieval-bound or generation-bound.
2. Ask whether the question is a lookup, an aggregate, or a traversal — and route accordingly.
3. Fix upstream first: parsing, then corpus coverage, then contextual retrieval, then reranking. Chunking is a bounded lever.
4. Retrieve wide, rerank hard, pass few — the near-misses hurt more than random noise.
5. If it can email, it can be exfiltrated. Filter ACLs *during* retrieval, never after.
