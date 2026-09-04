#!/usr/bin/env python3
"""
rag_calc.py — the four RAG numbers people guess wrong.

Subcommands:
  index      What will this index actually cost in RAM/disk/$? (quantization + graph overhead)
  stuff      Retrieve, or just put the whole corpus in a cached prompt? (break-even)
  recall     Read a retrieval run: recall@k curve, MRR, and where k saturates.
  ceiling    Is my bottleneck retrieval or generation? (oracle-context comparison)

Stdlib only. Fails loudly on bad input.

Examples:
  python rag_calc.py index --vectors 10_000_000 --dims 1536 --quant int8
  python rag_calc.py stuff --corpus-tokens 180000 --queries-per-day 500
  python rag_calc.py recall --file run.jsonl
  python rag_calc.py ceiling --oracle 0.81 --live 0.44

Prices move. Every default price is a DEFAULT, not a quote — pass your own
with the flags and check the vendor's live pricing page before you budget.
"""
import argparse
import json
import math
import sys

# ---------------------------------------------------------------- utilities


def die(msg):
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(2)


def human_bytes(n):
    for unit in ("B", "KiB", "MiB", "GiB", "TiB"):
        if abs(n) < 1024.0:
            return f"{n:,.1f} {unit}"
        n /= 1024.0
    return f"{n:,.1f} PiB"


def rule(title):
    print(f"\n=== {title} ===")


# ------------------------------------------------------------------- index

# bytes per dimension by storage type
QUANT_BYTES = {
    "float32": 4.0,
    "float16": 2.0,
    "int8": 1.0,
    "binary": 0.125,  # 1 bit per dimension
}

# Typical recall retained vs float32 baseline, from published MTEB-wide
# measurements. Binary is a RANGE, not a constant — some model families
# (notably E5) degrade far worse than average. Always rescore.
QUANT_RECALL_NOTE = {
    "float32": "baseline",
    "float16": "essentially lossless",
    "int8": "~-2 pts avg on MTEB across models; near-free",
    "binary": "-2 to -36 pts depending on MODEL FAMILY (avg ~-7); "
              "mandatory rescoring + 2-3x oversampling to recover ~96-99%",
}


def cmd_index(a):
    if a.vectors <= 0 or a.dims <= 0:
        die("--vectors and --dims must be positive")
    if a.quant not in QUANT_BYTES:
        die(f"--quant must be one of {sorted(QUANT_BYTES)}")

    bpd = QUANT_BYTES[a.quant]
    vec_bytes = a.vectors * a.dims * bpd
    # HNSW graph: M connections per node, ~8 bytes per link (pointer+metadata).
    # This is the part that does NOT shrink when you quantize the vectors.
    graph_bytes = a.vectors * a.m * 8.0
    total = vec_bytes + graph_bytes
    replicated = total * a.replicas

    rule("Index sizing")
    print(f"  vectors            {a.vectors:,}")
    print(f"  dimensions         {a.dims:,}")
    print(f"  storage type       {a.quant}  ({bpd} bytes/dim)")
    print(f"  HNSW M             {a.m}")
    print()
    print(f"  vector payload     {human_bytes(vec_bytes)}")
    print(f"  graph overhead     {human_bytes(graph_bytes)}   <- does NOT shrink with quantization")
    print(f"  index total        {human_bytes(total)}")
    print(f"  x{a.replicas} replicas       {human_bytes(replicated)}")
    print()
    print(f"  recall impact      {QUANT_RECALL_NOTE[a.quant]}")

    # What quantizing would save, if they haven't
    if a.quant == "float32":
        rule("If you quantized")
        for q in ("int8", "binary"):
            v = a.vectors * a.dims * QUANT_BYTES[q]
            t = v + graph_bytes
            pct = 100.0 * (1 - t / total)
            print(f"  {q:8s} -> {human_bytes(t):>12s}  ({pct:.0f}% smaller)   {QUANT_RECALL_NOTE[q]}")
        print("\n  Note the floor: graph overhead is "
              f"{human_bytes(graph_bytes)} regardless of quantization.")

    rule("Where this lands")
    if a.vectors < 100_000:
        print("  <100K vectors: brute force (NumPy/FAISS-flat) is a legitimate default,")
        print("  not a hack. An ANN index may return literally the same top-k here.")
    elif a.vectors < 10_000_000:
        print("  <10M vectors: pgvector/pgvectorscale territory. A dedicated vector DB")
        print("  is usually justified by FILTERING, MULTI-TENANCY, or QPS — not by count.")
    elif a.vectors < 50_000_000:
        print("  10M-50M: pgvectorscale (StreamingDiskANN) still viable; dedicated engines")
        print("  start earning their operational cost.")
    else:
        print("  >50M vectors: dedicated engine, or SSD-resident (DiskANN-family) /")
        print("  object-storage-backed (Turbopuffer, S3 Vectors, LanceDB) architectures,")
        print("  where RAM cost is the binding constraint rather than latency.")

    if a.ram_gb_price > 0:
        monthly = (replicated / (1024 ** 3)) * a.ram_gb_price
        print(f"\n  At ${a.ram_gb_price:.2f}/GB-month memory-resident: ~${monthly:,.0f}/month")
        print("  (object storage runs ~$0.02/GB-month cold — up to ~100x cheaper if")
        print("   your access pattern tolerates cold-start latency.)")


# ------------------------------------------------------------------- stuff


def cmd_stuff(a):
    if a.corpus_tokens <= 0:
        die("--corpus-tokens must be positive")
    if a.queries_per_day <= 0:
        die("--queries-per-day must be positive")

    # Per-query input tokens under each strategy
    stuff_cached = a.corpus_tokens          # read from cache each query
    retrieve_in = a.retrieved_tokens + a.overhead_tokens

    # Costs are per million tokens
    M = 1_000_000.0

    # Cache warmth is the thing people get wrong. A prompt cache entry expires
    # after TTL of inactivity, and every read RESETS the TTL. So the question is
    # not "how many TTL windows fit in a day" — it is "does the next query arrive
    # before the entry goes cold".
    gap_min = (24 * 60.0) / a.queries_per_day
    warm = gap_min < a.cache_ttl_min
    if warm:
        # Traffic sustains the entry: pay the write once, then read all day.
        writes_per_day = 1.0
        reads_per_day = max(0.0, a.queries_per_day - 1.0)
    else:
        # Every query finds a cold cache: you pay the WRITE premium every time
        # and never get the read discount. This is strictly worse than not caching.
        writes_per_day = float(a.queries_per_day)
        reads_per_day = 0.0

    stuff_write_cost = writes_per_day * (a.corpus_tokens / M) * a.price_cache_write
    stuff_read_cost = reads_per_day * (stuff_cached / M) * a.price_cached_read
    stuff_total = stuff_write_cost + stuff_read_cost

    # Retrieval: normal input price on a small context, plus embedding the query.
    retrieve_llm = a.queries_per_day * (retrieve_in / M) * a.price_input
    retrieve_embed = a.queries_per_day * (a.query_tokens / M) * a.price_embed
    retrieve_total = retrieve_llm + retrieve_embed

    rule("Stuff-the-corpus (with prompt caching) vs retrieve")
    print(f"  corpus                 {a.corpus_tokens:,} tokens")
    print(f"  queries/day            {a.queries_per_day:,}")
    print(f"  retrieved ctx/query    {a.retrieved_tokens:,} tokens (+{a.overhead_tokens:,} overhead)")
    print(f"  cache TTL              {a.cache_ttl_min:.0f} min")
    print(f"  mean gap between qs    {gap_min:.1f} min -> cache stays "
          f"{'WARM' if warm else 'COLD'}")
    print()
    if not warm:
        print("  !! Queries arrive slower than the cache TTL, so every query finds a cold")
        print("     entry: you pay the 1.25-2x WRITE premium every time and never collect")
        print("     the 90% read discount. Caching is COSTING you money here. Either raise")
        print("     the TTL (1h tiers exist), batch traffic, or do not cache this prefix.")
        print()
    print(f"  STUFF   cache writes   ${stuff_write_cost:8,.2f}/day  ({writes_per_day:,.0f} write(s))")
    print(f"          cache reads    ${stuff_read_cost:8,.2f}/day  ({reads_per_day:,.0f} read(s))")
    print(f"          total          ${stuff_total:8,.2f}/day   (${stuff_total*30:,.0f}/mo)")
    print()
    print(f"  RETRIEVE llm input     ${retrieve_llm:8,.2f}/day")
    print(f"           embedding     ${retrieve_embed:8,.2f}/day")
    print(f"           total         ${retrieve_total:8,.2f}/day   (${retrieve_total*30:,.0f}/mo)")
    print()
    print("  (Generation/output cost is identical under both and is excluded —")
    print("   it is typically the dominant line item in the real bill.)")

    rule("Verdict")
    cheaper = "STUFF" if stuff_total < retrieve_total else "RETRIEVE"
    ratio = max(stuff_total, retrieve_total) / max(1e-9, min(stuff_total, retrieve_total))
    print(f"  {cheaper} is cheaper by {ratio:.1f}x at this volume.")

    # The real break-even is on CORPUS SIZE, not query volume. Once the cache is
    # warm the write cost amortizes to ~nothing, and the fight is per-query:
    #   corpus * cached_read_price   vs   (retrieved + overhead) * input_price
    # so stuffing wins while corpus < retrieved_ctx * (input_price/cached_price).
    if warm and a.price_cached_read > 0:
        discount_ratio = a.price_input / a.price_cached_read
        breakeven_corpus = retrieve_in * discount_ratio
        print(f"  Cached reads are {discount_ratio:.0f}x cheaper than uncached input, so")
        print(f"  stuffing stays cheaper while the corpus is under ~{breakeven_corpus:,.0f} tokens")
        print(f"  (= {retrieve_in:,} tokens of retrieved context x {discount_ratio:.0f}).")
        if a.corpus_tokens < breakeven_corpus:
            print("  Your corpus is UNDER that line — stuffing is the cheaper architecture,")
            print("  and it is also far less machinery to build and operate.")
        else:
            print("  Your corpus is OVER that line — retrieval is the cheaper architecture.")
        print()
        print("  Note what this does NOT depend on: query volume. Once traffic keeps the")
        print("  cache warm, adding queries scales both strategies linearly and the")
        print("  ranking never flips. Corpus size is the lever; QPS is not.")
    else:
        print("  With a cold cache the comparison is dominated by the write premium —")
        print("  fix cache warmth first, then re-run this to get a meaningful break-even.")

    rule("But cost is not the only axis")
    if a.corpus_tokens <= 200_000:
        print("  Corpus fits in a frontier context window. Anthropic's own guidance is to")
        print("  SKIP retrieval entirely below ~200K tokens. Retrieval infrastructure you")
        print("  do not build is infrastructure you do not operate, monitor, or re-index.")
    else:
        print("  Corpus exceeds ~200K tokens — it does not fit a single context window")
        print("  cleanly, so stuffing means chunked/multi-call strategies anyway.")
    print()
    print("  CONTEXT ROT: quality degrades well before the advertised window limit, and")
    print("  it is not uniform. A full window has materially less usable reasoning than")
    print("  an empty one. Cheaper-to-stuff does NOT imply better answers — measure")
    print("  accuracy at both context sizes, not just cost.")


# ------------------------------------------------------------------ recall


def load_runs(path):
    rows = []
    try:
        with open(path) as f:
            for i, line in enumerate(f, 1):
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                except json.JSONDecodeError as e:
                    die(f"{path}:{i}: invalid JSON ({e})")
                if "retrieved" not in obj or "gold" not in obj:
                    die(f"{path}:{i}: every line needs 'retrieved' (list) and 'gold' (list)")
                ret = obj["retrieved"]
                gold = obj["gold"]
                if not isinstance(ret, list) or not isinstance(gold, list):
                    die(f"{path}:{i}: 'retrieved' and 'gold' must both be lists of ids")
                rows.append((ret, gold))
    except FileNotFoundError:
        die(f"file not found: {path}")
    if not rows:
        die(f"no usable rows in {path}")
    return rows


def cmd_recall(a):
    rows = load_runs(a.file)
    kmax = a.k_max or max(len(r) for r, _ in rows)

    rule(f"Retrieval run: {len(rows)} queries")

    # recall@k curve
    curve = []
    for k in range(1, kmax + 1):
        tot = 0.0
        for ret, gold in rows:
            if not gold:
                continue
            hit = len(set(ret[:k]) & set(gold))
            tot += hit / len(gold)
        curve.append(tot / len(rows))

    # MRR (first gold hit)
    mrr = 0.0
    for ret, gold in rows:
        gs = set(gold)
        for rank, doc in enumerate(ret, 1):
            if doc in gs:
                mrr += 1.0 / rank
                break
    mrr /= len(rows)

    print(f"  MRR                {mrr:.3f}")
    print()
    print("  k   recall@k   gain over k-1")
    prev = 0.0
    sat_k = None
    for k, v in enumerate(curve, 1):
        gain = v - prev
        bar = "#" * int(round(v * 40))
        print(f"  {k:<3d} {v:.3f}      +{gain:.3f}  {bar}")
        if sat_k is None and k > 1 and gain < a.saturation:
            sat_k = k - 1
        prev = v

    rule("Reading this")
    if sat_k:
        print(f"  Recall saturates around k={sat_k} (marginal gain < {a.saturation}).")
        print(f"  Retrieving beyond k={sat_k} adds tokens and distractors, not answers.")
    else:
        print(f"  Recall had not saturated by k={kmax} — your first stage is still")
        print("  finding new gold documents. Retrieve wider, then rerank down.")

    final = curve[-1]
    if final < 0.7:
        print(f"\n  recall@{kmax} = {final:.2f} is LOW. No amount of reranking, prompting,")
        print("  or model choice fixes a gold document the retriever never returned.")
        print("  Fix ingestion/retrieval before touching generation.")
    else:
        print(f"\n  recall@{kmax} = {final:.2f}. The gold document is usually present —")
        print("  so if answers are still wrong, the bottleneck is ranking or generation,")
        print("  not first-stage retrieval. Run `ceiling` to tell which.")

    print()
    print("  CAUTION: recall@k assumes your gold labels are right and complete. If your")
    print("  eval set was LLM-generated FROM the chunks, the query was written from the")
    print("  very chunk you now score as correct — that circularity inflates recall and")
    print("  quietly endorses whatever chunking you already chose. Mine real query logs.")
    print()
    print("  Also: the k that maximizes recall is NOT the k that maximizes answer")
    print("  quality. Published runs show recall still climbing while end-task F1 has")
    print("  already peaked and begun to fall. Tune retrieval k and generation k")
    print("  SEPARATELY, against different metrics.")


# ----------------------------------------------------------------- ceiling


def cmd_ceiling(a):
    for name, v in (("--oracle", a.oracle), ("--live", a.live)):
        if not (0.0 <= v <= 1.0):
            die(f"{name} must be between 0 and 1 (got {v})")
    if a.live > a.oracle + 1e-9:
        print("WARNING: live score exceeds oracle score. Either the oracle context is")
        print("not actually correct/complete, or the two runs are not comparable.\n")

    gap = a.oracle - a.live
    rule("Oracle-context test")
    print(f"  oracle (perfect context)   {a.oracle:.3f}   <- generation ceiling")
    print(f"  live   (real retrieval)    {a.live:.3f}")
    print(f"  gap                        {gap:.3f}")
    print()
    print("  The oracle run feeds the generator known-correct context. It measures the")
    print("  best your generator could do IF retrieval were perfect.")

    rule("Diagnosis")
    if a.oracle < 0.75:
        print(f"  GENERATION-BOUND. Even with perfect context you only reach {a.oracle:.2f}.")
        print("  Retrieval work is capped by this ceiling — improving it buys you nothing")
        print("  above the ceiling. Look at: prompt architecture (put documents FIRST and")
        print("  the query LAST; Anthropic reports 'up to 30%' from this in internal tests")
        print("  — an upper bound, not a typical gain), model choice/faithfulness, answer")
        print("  format, and whether the question is even answerable from the corpus.")
    elif gap > 0.15:
        print("  RETRIEVAL-BOUND. Your generator performs well on correct context but")
        print("  is not being given it. Spend effort upstream, in this order of leverage:")
        print("    1. Parsing quality      (unbounded downside; a dropped table is gone)")
        print("    2. Contextual retrieval (chunk-level context; largest published gain)")
        print("    3. Reranking            (cheap precision at the top)")
        print("    4. Chunking strategy    (bounded: ~8-9 recall points best-to-worst)")
    else:
        print("  BALANCED. Retrieval is delivering close to the generator's ceiling, and")
        print("  the ceiling itself is decent. Further gains need BOTH sides moved, or a")
        print("  reframing: is the corpus missing the answer entirely? Are these queries")
        print("  actually aggregation questions that no passage can answer?")

    print()
    print("  Run this BEFORE adopting GraphRAG, agentic retrieval, or a new embedding")
    print("  model. Each is expensive and each fixes only one of these two failures.")


# -------------------------------------------------------------------- main


def main():
    p = argparse.ArgumentParser(
        description="RAG sizing, break-even, and diagnostic math.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    sub = p.add_subparsers(dest="cmd", required=True)

    pi = sub.add_parser("index", help="index memory/storage/cost sizing")
    pi.add_argument("--vectors", type=lambda s: int(s.replace("_", "")), required=True)
    pi.add_argument("--dims", type=int, required=True)
    pi.add_argument("--quant", default="float32", choices=sorted(QUANT_BYTES))
    pi.add_argument("--m", type=int, default=16, help="HNSW M (connections/node), default 16")
    pi.add_argument("--replicas", type=int, default=1)
    pi.add_argument("--ram-gb-price", type=float, default=0.0,
                    help="$/GB-month for memory-resident storage, e.g. 2.0")
    pi.set_defaults(func=cmd_index)

    ps = sub.add_parser("stuff", help="stuff-with-caching vs retrieve break-even")
    ps.add_argument("--corpus-tokens", type=lambda s: int(s.replace("_", "")), required=True)
    ps.add_argument("--queries-per-day", type=lambda s: int(s.replace("_", "")), required=True)
    ps.add_argument("--retrieved-tokens", type=int, default=4000,
                    help="tokens of retrieved context per query (default 4000)")
    ps.add_argument("--overhead-tokens", type=int, default=1000,
                    help="system prompt + question tokens (default 1000)")
    ps.add_argument("--query-tokens", type=int, default=50)
    ps.add_argument("--cache-ttl-min", type=float, default=5.0,
                    help="prompt-cache TTL in minutes (default 5)")
    ps.add_argument("--price-input", type=float, default=3.0, help="$/M uncached input")
    ps.add_argument("--price-cached-read", type=float, default=0.30, help="$/M cached read")
    ps.add_argument("--price-cache-write", type=float, default=3.75, help="$/M cache write")
    ps.add_argument("--price-embed", type=float, default=0.02, help="$/M embedding tokens")
    ps.set_defaults(func=cmd_stuff)

    pr = sub.add_parser("recall", help="recall@k curve + saturation from a JSONL run")
    pr.add_argument("--file", required=True,
                    help='JSONL: {"retrieved": ["id",...], "gold": ["id",...]} per line')
    pr.add_argument("--k-max", type=int, default=0, help="0 = longest retrieved list")
    pr.add_argument("--saturation", type=float, default=0.01,
                    help="marginal recall gain below which k is 'saturated' (default 0.01)")
    pr.set_defaults(func=cmd_recall)

    pc = sub.add_parser("ceiling", help="oracle-vs-live: retrieval-bound or generation-bound?")
    pc.add_argument("--oracle", type=float, required=True,
                    help="score with known-correct context injected (0-1)")
    pc.add_argument("--live", type=float, required=True,
                    help="score with your real retrieval pipeline (0-1)")
    pc.set_defaults(func=cmd_ceiling)

    a = p.parse_args()
    a.func(a)


if __name__ == "__main__":
    main()
