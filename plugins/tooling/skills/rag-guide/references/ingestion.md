---
name: ingestion
description: Depth layer for getting documents into the index — parser selection and its benchmark caveats, VLM-as-parser economics and silent table hallucination, table serialization and row chunking, what the chunking evidence actually supports, contextualization (Contextual Retrieval vs late chunking), near-duplicate decay, incremental re-ingest, and non-prose formats. Load when building or repairing an ingestion pipeline; skip for retrieval tuning, reranking, or eval design.
---

# Ingestion

Parsing is the only stage whose failures are **unbounded and irreversible**: a dropped table, a scrambled two-column reading order, or a hallucinated cell cannot be recovered by any embedding, reranker, or prompt downstream, and it produces a confidently wrong answer with a *valid-looking citation*. Chunking is **bounded**: the total recall spread between the best and worst chunking strategy on a matched corpus/retriever is ≈8–9 percentage points ([Chroma, July 2024](https://trychroma.com/research/evaluating-chunking); a 2025 Weaviate guide converges on the same figure independently). That asymmetry — not a preference for parsing tooling — is why parsing outranks chunking. The circulating "73%/87% of RAG failures are retrieval" figures are **untraceable to a primary methodology**; the direction is practitioner consensus, the number is invented. Do not quote it.

## Parser selection — Aug 2026

Route by document type, not by leaderboard rank. **Every head-to-head number below is one degree or less removed from a party with an interest in it** (Datalab's olmOCR-bench comparison table includes Datalab's own Marker 2); none were independently reproduced by a neutral third party in this research.

| Tool | Reported number (source) | Pick it when |
|---|---|---|
| **Native text extraction** (pdfplumber/PyMuPDF) | — | The PDF has a real text layer and single-column layout. Free, deterministic, ~0 latency. Always the first branch of a router; most corpora are majority-clean. |
| **MinerU2.5** (1.2B VLM backend) | Leads OmniDocBench as of its March 2026 update; ≈0.54 pg/s pipeline backend (Datalab harness) | Best open-source accuracy-per-parameter; self-hosted, quality over throughput. |
| **Marker 2** (Datalab, Jul 2026) | 76.0% olmOCR-bench, 2.9 pg/s on one B200 — ≈5× MinerU throughput (**Datalab's own run**) | High-volume self-hosted pipelines where throughput is the constraint. |
| **Docling** (IBM/LF AI, MIT) | 50.3% olmOCR-bench (Datalab harness); **no OmniDocBench entry — accuracy story is essentially self-reported** | Format breadth (PDF/DOCX/PPTX/XLSX/HTML/EPUB/email/audio/XBRL in one pipeline), air-gapped, permissive license. Recommend it on *coverage and licensing*, not accuracy. |
| **olmOCR 2 / Chandra 2 / dots.ocr 1.5** (VLM tier) | 82.4 / 85.8 / 83.9 olmOCR-bench (Datalab, Jul 2026); olmOCR 2 Apache-2.0, FP8 weights ≈10K pages for <$2 on one H100 | Degraded scans, handwriting, dense multi-column. olmOCR 2's own report attributes its largest RL-driven gains specifically to tables. |
| **Hosted APIs** (Mistral OCR, LlamaParse, Reducto, Azure DI, Unstructured) | Mistral ≈$2/1K pages standard, flat per page regardless of table complexity; LlamaParse ≈$0.003/pg; Reducto $0.005–0.015/pg; Azure DI $1.50/1K basic but $15–50/1K for custom table/neural models, 2–4 s/pg (fastest observed) | You want no GPU fleet. **None of these have an independent accuracy figure** — their published comparisons are vendor pages. Azure DI is the only hyperscaler with an on-prem container. |

**Benchmark caveats that change decisions.** OmniDocBench (1,651–1,655 pages, edit distance + TEDS) is **saturated** — top scores sit at 94–96% (PaddleOCR-VL-1.6 at 96.33%; GLM-OCR 94.6% on v1.5, above Gemini 3 Pro and GPT-5.2 on that set) and further movement is edge-case fixing, not capability. Prefer **olmOCR-bench** (1,403 pages: arXiv math, multi-column, degraded scans, tiny text): it is unsaturated and scores by *executable unit test* — can a downstream parser actually reconstruct the table — which is harder to game than edit distance. olmOCR 2 was trained with RLVR on binary unit-test rewards precisely because edit distance rewards formatting fidelity (bold-per-cell vs bold-per-row) over correct structure. Chunkr did not appear in any 2026 comparison surfaced; **treat as unverified** rather than recommending it.

## VLM-as-parser: the break-even is per-document *questions*

The 2026 shift is not "always VLM," it is hybrid routing: native text for clean PDFs → small specialist OCR-VLM for scans/complex layout → frontier VLM only for the genuinely hard subset. Small specialists closed most of the gap — dots.ocr (1.7B) and DeepSeek-OCR (3B) post OmniDocBench accuracy competitive with models 20× larger, and DeepSeek-OCR is reported at 200,000+ pages/day on a single A100.

**Break-even rule (reported, one source — a 2026 microservice-architecture paper):** cost parity between VLM-direct and staged parse-once-query-many sits at **≈4–6 questions per document**. Below that, VLM-direct is competitive; above it, staged OCR wins decisively because parsing is amortized. The variable is questions per document, **not** corpus size — this is a sharper decision rule than "use VLMs for hard docs," and it explains why a one-shot invoice extractor and a permanent knowledge base want opposite architectures.

**The failure mode that matters is silent hallucination, not misrecognition.** A VLM will not leave a cell blank when it cannot read it — it emits something plausible and well-formed. A hallucinated number passes chunking, embedding, retrieval, and generation with no signal anywhere. Documented case: an OCR layer misreads an invoice total, subtotal + tax no longer reconcile, and a downstream agent approves the wrong amount because it treated the parser as ground truth.

**Mitigation, cheap and recurring across sources:** run **arithmetic cross-checks at ingestion** — do row sums, column sums, and percentage columns reconcile against any stated total? Quarantine tables that fail rather than indexing them. Where the parser emits bounding boxes, keep them: grounding text to the visual region it claims to come from *reduces* (does not eliminate) hallucination and makes post-hoc audit possible. VLMs read handwriting and layout far better than legacy OCR but **cannot report calibrated confidence** — there is no threshold to gate on. Handwriting-specific 2026 benchmarks are a genuine gap; do not claim a number.

## Tables

**Markdown vs HTML is a real trade-off, not a formatting preference.** Markdown has no rowspan/colspan — complex tables lose merged-cell structure *silently*. HTML preserves it, but one study built a fully HTML-native RAG pipeline and found it performed **worse than plain-text RAG on nearly every benchmark**: retrieval-side quality was comparable, and the markup tags overwhelmed the reader model. Synthesis: markdown by default; HTML only where merged cells are structurally load-bearing, and check the generator's behavior when you switch.

Row-chunking strategies, ascending sophistication:
1. **Whole table as one chunk** if it fits the budget. Best when it works; stop here.
2. **Row-split with the header row repeated in every sub-chunk.** The standard mitigation, and its absence is among the most-cited table bugs — a chunk of bare numbers with no column labels is near-useless to both the embedding (no column semantics) and the reader (cannot say what the numbers mean).
3. **Size-adaptive cascade** (Ragie's documented approach): whole table → pack full rows per chunk → relax the cap up to the embedding model's max for wide single rows → split a row only as a last resort.
4. **Fact-per-line / header-ancestry flattening** — each cell becomes a self-contained fact carrying its full header path: `Revenue | 2024 > Q2: 155` instead of a bare `155` at a grid position. Best embedding-query alignment because it sits close to how the query is phrased ("Q2 2024 revenue"). Structurally the same serialization the [TAG paper](https://arxiv.org/abs/2408.14717) uses for its Text2SQL baseline.

**Table summarization:** pairing the raw markdown with an LLM-generated prose description (or generated question/summary pairs) at index time improves retrievability of tables whose subject is implicit ("quarterly headcount by department" appears nowhere in the cells). Costs one LLM call per table.

**Route to Text2SQL instead when the queries are aggregations.** If the dominant query shape is totals/filters/joins over a stable schema, row-level retrieval is the wrong tool — no set of retrieved fragments contains a computed aggregate. If the dominant shape is "find the passage that mentions X," row-level RAG wins. The TAG framing generalizes this beyond SQL.

## Chunking: what the evidence supports

**Retrieval recall and end-to-end accuracy point in opposite directions here.** This is the load-bearing methodological fact of the 2026 chunking literature, and it invalidates most vendor blog claims. Semantic chunking wins recall (Chroma: 91–92% vs 85–90%; LLMSemanticChunker took the study's top recall at 91.9%, at materially worse efficiency) and **loses end-to-end accuracy** to plain recursive splitting — reported 69% recursive vs 54–58% semantic in the most-cited 2026 comparison (Vecta/FloTorch, Feb 2026). The mechanism: semantic chunking produced fragments averaging **43 tokens** — correctly retrieved but too small to give the generator anything to work with. A NAACL 2025 Findings paper independently concluded semantic chunking's compute is unjustified, with fixed 200-word chunks matching or beating it on both retrieval and generation.

Confidence note: the Vecta/FloTorch figure is **reported inconsistently across two write-ups (54% vs 58%)** — cite the spread, never a single decimal. **Any chunking benchmark reporting only recall@k/nDCG without an end-to-end accuracy number is telling you half the story, and it is the half that flatters semantic chunking.**

- **256–512 tokens persists on evidence, not legacy.** It is not a BERT-512 artifact — Jina v2/v3 and Nomic Embed handle 8K, E5-mistral-7B and NV-Embed 32K, so size is no longer a retriever constraint. It persists because controlled comparisons keep landing there (Chroma's best results cluster at 200–400 tokens; Vecta's winner was recursive @512), and because generation degrades with input length well before any window limit. A Jan 2026 arXiv analysis reports a "context cliff" around **≈2,500 tokens** past which response quality measurably dropped — single source, treat as directional. **Match size to query type**: 128–256 for precise fact lookup, 1,024+ for legal/technical narrative that needs surrounding clauses.
- **Overlap is no longer a safe default.** A January 2026 systematic study (SPLADE retrieval, 8B Mistral, Natural Questions) varying size/overlap/boundary found overlap gave **no measurable benefit** while adding indexing cost. A Feb 2026 practitioner report found it actively hurting table recall, because overlapping windows encode multiple partial versions of the same table as near-duplicates. Caveat honestly: that study used *sparse* retrieval and has not been shown to generalize to dense embeddings. Treat overlap as a tunable you validate, not a given.
- **Parent-child / small-to-big** (index small, return large parent) is the LangChain/LlamaIndex production default and structurally sound — it decouples retrieval granularity from generation granularity, which is exactly the failure semantic chunking hit. But its quoted accuracy splits are **blog-reported, not peer-reviewed**; no independent benchmark surfaced. Tune the auto-merge threshold on your own labeled set: wrong thresholds either merge whole documents back together or never merge at all. **Sentence-window** is the narrow variant — its real advantage is that the relevant sentence sits *centered* in returned context rather than at a boundary edge; its real cost is duplicated storage.
- **Hierarchical / RAPTOR** earns its indexing cost only on multi-hop QA, where it reaches F1 comparable to HippoRAG/SIRERAG-style graph methods ([arXiv:2502.11371](https://arxiv.org/abs/2502.11371), [MacRAG](https://arxiv.org/abs/2505.06569)). Its headline "+20% on QuALITY" is from the original 2024 paper and **not independently reproduced**; GMM+UMAP clustering over a large corpus is genuinely expensive.
- **Agentic chunking** costs 10–50× fixed-size indexing and is **non-deterministic** — the same document chunks differently across reruns, which alone disqualifies it from a continuously re-ingesting pipeline. It is also buying into the bounded 8–9 point prize. Reserve for high-value, structurally complex, low-volume, ingest-once corpora (long contracts with cross-references and nested exceptions is the credible case). Strongest research-grade evidence is [TopoChunker](https://arxiv.org/abs/2603.18409): +8% absolute generation accuracy over the best LLM-based baseline with 23.5% less token overhead, by *not* applying LLM reasoning to structurally simple text — single paper, unreproduced.

## Contextualization: two mechanisms, no head-to-head

Both target the same failure — a chunk that lost its document context — by opposite means.

| | **Contextual Retrieval** ([Anthropic, Sept 2024](https://www.anthropic.com/engineering/contextual-retrieval)) | **Late chunking** ([arXiv:2409.04701](https://arxiv.org/abs/2409.04701)) |
|---|---|---|
| Mechanism | Prepend an LLM-generated 1–2 sentence explanation of the chunk (whole doc as context) *before* embedding | Embed the whole document first, then mean-pool token embeddings into per-chunk vectors — context arrives via attention, no LLM call |
| Published gain | Top-20 failure 5.7% → 3.7% (embeddings) → 2.9% (+contextual BM25) → 1.9% (+rerank) | +3.63% relative nDCG over naive chunking with sentence boundaries, +3.46% for fixed-size (3 models × 4 BeIR datasets) |
| Cost | One LLM call per chunk at ingest; cacheable | Free at ingest; requires a long-context embedding model with mean pooling |
| Constraint | Works with any embedding model; pairs with hybrid + rerank, which is where its largest gains come from | Locks you to a specific model class; any document edit forces a full re-embed of that document |
| Scaling | Domain-tailored prompts beat the generic one substantially: Unstructured reported **84%** failure reduction on SEC 10-Ks with a modified one-sentence prompt vs **47%** for Anthropic's generic prompt under matched conditions | Gains grow with document length — longer docs lose more cross-chunk context to naive splitting |

**No source anywhere in this research measures them against each other.** That is a real gap in the public evidence base as of Aug 2026, not a gap in searching. Anyone who tells you which one wins is extrapolating. One competing 2025 evaluation found ContextualRankFusion beating late chunking on an NFCorpus subset, so late chunking is not universally dominant either. Pick on the constraint row, not on the gain row: if you cannot change embedding models, Contextual Retrieval; if you cannot afford an LLM call per chunk, late chunking.

## Metadata, near-duplicates, and re-ingest

**Metadata that earns its slot** is metadata a filter or a tiebreak will actually read: source document ID, path/URL, section/header ancestry, timestamp (for recency tiebreak), ACL/tenant, content hash, chunking-config version. For structured formats put the structure *in metadata, not inline*: sender/timestamp for email messages, speaker labels/timestamps for transcripts — inline they pollute the embedding, in metadata they enable attribution and filtering. Everything else is index bloat you will pay for on every filtered query.

**Near-duplicate accumulation is a slow-acting poison** — multiple revisions of one report, boilerplate-heavy templates, cross-referenced KB articles. Two costs: top-k returns several near-identical passages (**30–50% of context tokens in one measured case**), and more subtly, large candidate pools of near-duplicates make cross-encoder scores sensitive to small non-meaningful differences, pushing the *wrong* copy to the top. Dedup at ingest by content hash and again at retrieval by similarity ceiling.

**Incremental re-ingest, the invariants:**
- **Content-hash every source and every chunk; make upserts idempotent under a stable ID** derived from (document ID, chunk index, content hash). Without this, re-ingestion re-upserts everything under fresh IDs — storage doubles and the index fills with duplicates, a documented longitudinal production failure.
- **Deleting a source document must delete its chunks.** Orphaned chunks keep getting retrieved, and the generator receives context citing documents that no longer exist — with no built-in signal. HNSW does not cleanly remove entries; verify the deletion actually reached the graph, and see the security reference for why soft delete is not erasure.
- **Renames are the sneaky orphan case:** a moved file indexed as a new document orphans the old path's chunks. Reconcile by **content hash, not path**.
- **Version-tag the chunking config and re-index the whole corpus on change.** Mixed chunk-boundary conventions in one index make retrieval quality impossible to reason about — you cannot tell whether a regression came from the new config or the old remnants.

## Non-prose formats

| Format | The actual failure | What works |
|---|---|---|
| **Code** | Character/paragraph splitting severs declarations and orphans braces | AST/syntax-aware splitting (per-function, per-class), fallback for huge files; consider a code-specialized embedder |
| **Spreadsheets / pivots** | Multi-level headers and merged cells defeat row-by-row reconstruction | Pass the raw table to an LLM at ingest for a prose summary; accept the latency |
| **Slides** | Not a chunking problem — the meaning often lives in a diagram the text never describes ("Q3 Architecture Decision" with the decision only in the dependency graph) | One slide = one chunk (bullets + speaker notes + OCR'd text) **plus a vision pass on the diagram** |
| **Email threads** | Quoted-reply nesting and threading order break naive splitting | One message = one structural unit; sender/timestamp as metadata |
| **Transcripts / chat** | Rapid speaker changes and non-standard punctuation break the sentence-segmentation that recursive splitters assume | Sliding-window or sentence-based; keep a speaker turn intact; labels/timestamps as metadata |
| **Forms** | Flat text dumping loses which value belongs to which field — same failure as an unheadered table row | Structure-preserving label→value extraction |

## NEVER — ingestion landmines

- **NEVER treat parser output as ground truth without a validation pass.** WHY: VLM OCR hallucinates plausible, well-formed wrong content instead of failing loudly; it passes every downstream stage and surfaces as a confident answer with a valid citation.
- **NEVER split a table without repeating the header in every sub-chunk.** WHY: the embedding loses column semantics and the reader cannot name what the numbers mean — the chunk is retrievable but unusable.
- **NEVER pick semantic chunking because it sounds more sophisticated.** WHY: it optimizes chunk coherence for *retrieval* and frequently loses on *generation accuracy* by producing fragments too small to answer from — and you pay embedding compute at ingest for the privilege.
- **NEVER keep overlap "because that's the standard advice" without measuring it.** WHY: the one controlled 2026 study found zero benefit, and on tables it created near-duplicate fragments that degraded recall.
- **NEVER send every page to a frontier VLM "to be safe."** WHY: 2–3× the cost of staged OCR past a handful of questions per document, and the gain over a specialist OCR-VLM is marginal on clean-to-moderate pages. Spend the premium on the hard subset.
- **NEVER change chunk size or strategy without a new index version.** WHY: old and new boundary conventions coexisting in one index makes every subsequent measurement uninterpretable.
- **NEVER quote a parser leaderboard number as a neutral fact.** WHY: every 2026 head-to-head found here is vendor-adjacent, and OmniDocBench is saturated — a 2-point gap at the top is noise plus edge-case fitting.
