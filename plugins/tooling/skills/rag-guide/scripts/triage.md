---
name: triage
description: Fill-in worksheet that forces measurement before optimization on a failing RAG system. Open and complete it BEFORE changing chunking, embeddings, hybrid search, or adding GraphRAG/agentic retrieval. Skip it only if you have already localized the failure with numbers.
---

# RAG triage worksheet

Copy this into the working session and fill it in. Every blank you cannot fill is a change you are not yet entitled to make. The point is not ceremony — it is that the standard fix list (smaller chunks, add hybrid, add a reranker, add a graph, retrieve more) contains fixes that *actively hurt* when applied to the wrong failure.

## 0. Scope

- System: ______________________________________________
- Corpus size (docs / tokens): __________________________
- Who reported the failure, and what did they actually type? ____________________
- Is this **one** bad answer, or a **class** of bad answers? ____________________
  - One-off → fix the document or the chunk. Do not re-architect for n=1.
  - A class → continue.

## 1. Ten real failing queries

Not queries you invented. Pull them from logs. If you have no query logs, stop and add
logging first — every downstream decision here depends on knowing what users actually ask.

| # | Query as typed | Expected source doc | Is that doc in the index? |
|---|---|---|---|
| 1 | | | |
| 2 | | | |
| 3 | | | |

**Gate:** if the expected document is *not in the index* for several rows, you have an
ingestion or coverage problem. Stop. No retrieval tuning fixes a missing document.

## 2. Read what the retriever returned

For at least 3 failing queries, paste the top-5 chunks actually retrieved.

- Query: ______________________________________________
- Chunk 1: ____________________________________________
- Chunk 2: ____________________________________________
- ...

Mark each chunk: `GOLD` (contains the answer) · `NEAR` (topically close, no answer) ·
`JUNK` (irrelevant) · `BROKEN` (truncated mid-table, missing header, garbled parse).

Tally: GOLD ___ · NEAR ___ · JUNK ___ · BROKEN ___

Read the tally, not your intuition:
- Many **BROKEN** → parsing. Highest leverage and unbounded — fix first.
- Many **NEAR**, no GOLD → the ranking is surfacing exactly the class of distractor that
  hurts most. Reranking, a relevance floor, or contextualization — not bigger k.
- **GOLD present but answer still wrong** → generation-side. Go to §4.
- Many **JUNK** → filters, index staleness, or an embedding mismatch.

## 3. Put numbers on it

```bash
python scripts/rag_calc.py recall  --file run.jsonl          # recall@k curve, where k saturates
python scripts/rag_calc.py ceiling --oracle ____ --live ____ # retrieval- or generation-bound
```

- recall@k at your production k: ______
- k where recall saturates: ______  (retrieving past this adds distractors, not answers)
- closed-book score (no context at all): ______
- oracle score (hand-fed correct context): ______
- live score: ______

**Gate:** if `live` < `closed-book`, retrieval is making the system *worse than no
retrieval*. This happens and is invisible without the floor. Fix or disable retrieval
for the affected query class before anything else.

## 4. Is this even a retrieval question?

Classify the ten queries from §1:

- Lookup ("what does X say about Y") → ______ of 10 → vector + rerank is right.
- Aggregate ("how many", "top N", "trend") → ______ of 10 → **no embedding can answer
  these.** Route to SQL / a semantic layer. Better retrieval is wasted effort.
- Traversal ("how are A and B connected", "themes across the corpus") → ______ of 10 →
  only here does a graph earn its extraction cost. If this count is 0-1, do not build one.
- Exact identifier / symbol / error string → ______ of 10 → lexical or grep beats semantic.

## 5. The change you are now entitled to make

- Failure localized to: ______________________________________
- Evidence (numbers from §2-3): ______________________________
- Single change being made: __________________________________
- Metric that will move if this worked, measured on a **frozen** eval set: ____________
- Result after the change: ___________________________________

Change **one** thing. Two simultaneous changes to a stochastic pipeline teach you nothing.

## 6. Before you claim it is fixed

- [ ] Re-ran the same frozen eval set — not a regenerated one (regenerating makes runs incomparable).
- [ ] Checked the change did not *lower* a metric elsewhere — reranking can raise Recall@10 while lowering the strict all-gold Accuracy@3.
- [ ] Confirmed the eval set was not built by asking an LLM to write questions from the chunks (that circularity inflates recall and quietly endorses whatever chunking you already had).
- [ ] Spot-read retrieved chunks again for the previously-failing queries. Aggregates hide boundary failures.
