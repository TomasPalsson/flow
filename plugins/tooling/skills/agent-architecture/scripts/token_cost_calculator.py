#!/usr/bin/env python3
"""
token_cost_calculator.py — estimate Claude agent token cost, prompt-caching break-even,
and the single-vs-multi-agent cost delta, BEFORE you build.

Stdlib only. Prices are mid-2026 USD per 1M tokens and WILL drift — verify against the live
Anthropic/AWS pricing page. Multipliers (cache read 0.1x, 5m write 1.25x, 1h write 2.0x,
batch 0.5x) are stable structural facts; the per-model base prices are the part to re-check.

Examples:
  python token_cost_calculator.py --model opus-4.8 --input 30000 --output 800 \
      --calls-per-day 5000 --cache-hit 0.8 --cached-frac 0.7
  python token_cost_calculator.py --model sonnet-4.6 --input 12000 --output 1500 \
      --calls-per-day 20000 --multiagent
"""
import argparse, sys

# base input / output $ per 1M tokens
PRICES = {
    "opus-4.8":   (5.0, 25.0),
    "opus-4.5":   (5.0, 25.0),
    "sonnet-4.6": (3.0, 15.0),
    "sonnet-4.5": (3.0, 15.0),
    "haiku-4.5":  (1.0,  5.0),
    "haiku-3.5":  (0.8,  4.0),
}
CACHE_READ_MULT  = 0.10   # 90% discount
CACHE_W5_MULT    = 1.25   # 5-minute write premium
CACHE_W1H_MULT   = 2.00   # 1-hour write premium
BATCH_MULT       = 0.50   # flat 50% off
# token multipliers vs a one-shot chat turn (Anthropic BrowseComp): single ~4x, multi ~15x
SINGLE_AGENT_MULT = 4.0
MULTI_AGENT_MULT  = 15.0
MIN_CACHE = {  # tokens required before a breakpoint caches at all (silent no-op below)
    "opus-4.8": 1024, "sonnet-4.6": 1024, "sonnet-4.5": 1024,
    "opus-4.5": 4096, "haiku-4.5": 4096, "haiku-3.5": 2048,
}


def per_million(tokens, price):
    return tokens / 1_000_000 * price


def call_cost(inp, out, in_price, out_price, cached_frac=0.0, cache_hit=0.0, ttl="5m"):
    """Cost of one call. cached_frac = fraction of INPUT tokens in the cacheable prefix;
    cache_hit = probability that prefix is already warm (read) vs cold (write)."""
    write_mult = CACHE_W1H_MULT if ttl == "1h" else CACHE_W5_MULT
    cached = inp * cached_frac
    fresh = inp - cached
    read = cached * cache_hit
    write = cached * (1 - cache_hit)
    in_cost = (per_million(fresh, in_price)
               + per_million(read, in_price) * CACHE_READ_MULT
               + per_million(write, in_price) * write_mult)
    return in_cost + per_million(out, out_price)


def fmt(x):
    return f"${x:,.2f}"


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--model", default="sonnet-4.6", choices=sorted(PRICES))
    ap.add_argument("--input", type=int, default=10000, help="input tokens per call")
    ap.add_argument("--output", type=int, default=800, help="output tokens per call")
    ap.add_argument("--calls-per-day", type=int, default=1000)
    ap.add_argument("--cached-frac", type=float, default=0.7,
                    help="fraction of input that is the stable cacheable prefix (system+tools)")
    ap.add_argument("--cache-hit", type=float, default=0.0,
                    help="prefix warm-hit rate 0..1 (0 = caching off)")
    ap.add_argument("--ttl", choices=["5m", "1h"], default="5m")
    ap.add_argument("--batch", action="store_true", help="apply Batch API 0.5x (half-price) discount")
    ap.add_argument("--multiagent", action="store_true",
                    help="show single-vs-multi-agent monthly cost delta")
    a = ap.parse_args()

    in_price, out_price = PRICES[a.model]
    base = call_cost(a.input, a.output, in_price, out_price)             # no caching
    cached = call_cost(a.input, a.output, in_price, out_price,
                       a.cached_frac, a.cache_hit, a.ttl)
    if a.batch:
        base *= BATCH_MULT
        cached *= BATCH_MULT

    day = a.calls_per_day
    print(f"\n  model={a.model}  in={a.input}  out={a.output}  calls/day={day:,}"
          f"  batch={'on' if a.batch else 'off'}")
    print("  " + "-" * 64)
    print(f"  per call  no-cache {fmt(base)}     with-cache "
          f"(hit={a.cache_hit:.0%}, {a.ttl}) {fmt(cached)}")
    print(f"  per day   no-cache {fmt(base*day)}   with-cache {fmt(cached*day)}")
    print(f"  per month no-cache {fmt(base*day*30)}   with-cache {fmt(cached*day*30)}")
    if a.cache_hit > 0:
        saved = (base - cached) * day * 30
        pct = (1 - cached / base) * 100 if base else 0
        print(f"  caching saves ~{fmt(saved)}/month ({pct:.0f}% off)")

    # caching break-even sanity
    prefix = a.input * a.cached_frac
    mn = MIN_CACHE[a.model]
    if prefix < mn:
        print(f"\n  ⚠  cacheable prefix ~{int(prefix)} tok < {mn} min for {a.model}: "
              f"cache SILENTLY no-ops (cache_creation_input_tokens=0, no error).")
    else:
        wm = CACHE_W1H_MULT if a.ttl == "1h" else CACHE_W5_MULT
        be = (wm - 1.0) / (1.0 - CACHE_READ_MULT)  # extra writes covered per read saving
        print(f"\n  break-even: {a.ttl} cache pays off after ~{be:.2f} reads "
              f"(≈1 for 5m, ≈2 for 1h). Prefix {int(prefix)} tok ≥ {mn} min ✓")

    if a.multiagent:
        # cost scales ~ with token multiplier vs a chat turn
        single = cached * (SINGLE_AGENT_MULT)
        multi = cached * (MULTI_AGENT_MULT)
        print("\n  single-vs-multi-agent (token multipliers vs chat: 4x / 15x):")
        print(f"    single-agent  ~{fmt(single*day*30)}/month")
        print(f"    multi-agent   ~{fmt(multi*day*30)}/month   "
              f"({MULTI_AGENT_MULT/SINGLE_AGENT_MULT:.2f}x the single-agent cost)")
        print("    → multi-agent must deliver ≥3.75x the value of single-agent to justify it.")
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
