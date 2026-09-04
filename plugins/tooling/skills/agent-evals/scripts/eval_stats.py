#!/usr/bin/env python3
"""
eval_stats.py — the eval math humans get wrong.

Three subcommands:
  power    How many examples do I need to detect a delta? (two-proportion z-test)
  compare  Is the difference between two eval runs real or noise? (paired McNemar + bootstrap CI)
  kappa    Is my LLM judge trustworthy? (Cohen's kappa, TPR, TNR vs human labels)

Stdlib only — no numpy/scipy. Fails loudly on bad input.

Examples:
  python eval_stats.py power --baseline 0.80 --delta 0.04
  python eval_stats.py compare --a run_a.json --b run_b.json
  python eval_stats.py kappa --judge judge.json --human human.json

Input files are JSON arrays. Elements may be 0/1, true/false, or strings
("pass"/"fail", "correct"/"incorrect", "yes"/"no"). For `compare` and `kappa`
the two arrays MUST be aligned element-for-element (same eval items, same order).
"""
import argparse
import json
import math
import random
import sys

PASS_WORDS = {"pass", "correct", "true", "yes", "good", "1", "ok"}
FAIL_WORDS = {"fail", "incorrect", "false", "no", "bad", "0"}


def die(msg):
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(2)


def norm(v):
    """Normalize an element to 1 (pass) or 0 (fail). Raises on unknown."""
    if isinstance(v, bool):
        return 1 if v else 0
    if isinstance(v, (int, float)):
        if v in (0, 1):
            return int(v)
        die(f"numeric label must be 0 or 1, got {v!r} (use `compare --scores` for continuous values)")
    if isinstance(v, str):
        s = v.strip().lower()
        if s in PASS_WORDS:
            return 1
        if s in FAIL_WORDS:
            return 0
        die(f"unrecognized label {v!r}; use pass/fail, correct/incorrect, 0/1")
    die(f"unsupported label type: {type(v).__name__}")


def load_labels(path):
    try:
        with open(path) as f:
            data = json.load(f)
    except FileNotFoundError:
        die(f"file not found: {path}")
    except json.JSONDecodeError as e:
        die(f"{path} is not valid JSON: {e}")
    if not isinstance(data, list) or not data:
        die(f"{path} must be a non-empty JSON array")
    return [norm(x) for x in data]


def load_scores(path):
    try:
        with open(path) as f:
            data = json.load(f)
    except FileNotFoundError:
        die(f"file not found: {path}")
    except json.JSONDecodeError as e:
        die(f"{path} is not valid JSON: {e}")
    if not isinstance(data, list) or not data:
        die(f"{path} must be a non-empty JSON array")
    try:
        return [float(x) for x in data]
    except (TypeError, ValueError):
        die(f"{path} must contain numbers when using --scores")


# ---- normal / chi-square helpers (stdlib only) ----
def norm_cdf(z):
    return 0.5 * math.erfc(-z / math.sqrt(2))


def chi2_1df_sf(x):
    """P(X > x) for chi-square with 1 df."""
    if x <= 0:
        return 1.0
    return math.erfc(math.sqrt(x / 2.0))


Z_ALPHA_2 = 1.959963985  # two-sided alpha=0.05
Z_BETA_80 = 0.841621234  # power=0.80


def cmd_power(args):
    p1 = args.baseline
    if not (0 < p1 < 1):
        die("--baseline must be in (0,1)")
    if args.delta <= 0:
        die("--delta must be > 0")
    p2 = p1 + args.delta
    if not (0 < p2 < 1):
        die(f"--baseline + --delta = {p2:.3f} must be in (0,1)")
    pbar = (p1 + p2) / 2
    n = (
        Z_ALPHA_2 * math.sqrt(2 * pbar * (1 - pbar))
        + Z_BETA_80 * math.sqrt(p1 * (1 - p1) + p2 * (1 - p2))
    ) ** 2 / (args.delta ** 2)
    n = math.ceil(n)
    print(f"To detect a {args.delta*100:.1f}-point move ({p1*100:.0f}% -> {p2*100:.0f}%)")
    print(f"at alpha=0.05 (two-sided), power=0.80:")
    print(f"  INDEPENDENT arms : ~{n} examples PER arm  ({2*n} total)")
    print(f"  PAIRED (same inputs, McNemar): typically ~3-10x fewer — run `compare` to test directly.")
    se = math.sqrt(p1 * (1 - p1) / n)
    print(f"  (sanity: at n={n}, 95% CI on the baseline is +/- {1.96*se*100:.1f} points)")
    if args.delta < 0.05:
        print("  NOTE: deltas under 5 points need large n. Prefer a paired design on a curated golden set.")


def _bootstrap_diff(a, b, iters, seed):
    """Paired bootstrap of mean(b)-mean(a). Returns (point, lo, hi)."""
    rng = random.Random(seed)
    n = len(a)
    point = sum(b) / n - sum(a) / n
    diffs = [b[i] - a[i] for i in range(n)]
    boots = []
    for _ in range(iters):
        s = 0.0
        for _ in range(n):
            s += diffs[rng.randrange(n)]
        boots.append(s / n)
    boots.sort()
    lo = boots[int(0.025 * iters)]
    hi = boots[min(int(0.975 * iters), iters - 1)]
    return point, lo, hi


def cmd_compare(args):
    if args.scores:
        a = load_scores(args.a)
        b = load_scores(args.b)
    else:
        a = load_labels(args.a)
        b = load_labels(args.b)
    if len(a) != len(b):
        die(f"paired comparison needs equal-length aligned arrays: A={len(a)} B={len(b)}. "
            f"If runs are not aligned per-item, you cannot use a paired test.")
    n = len(a)
    mean_a, mean_b = sum(a) / n, sum(b) / n
    print(f"n = {n} paired items")
    print(f"  A mean = {mean_a:.4f}")
    print(f"  B mean = {mean_b:.4f}")
    print(f"  raw difference (B-A) = {mean_b-mean_a:+.4f}")

    point, lo, hi = _bootstrap_diff(a, b, args.iters, args.seed)
    print(f"\nPaired bootstrap 95% CI on (B-A): [{lo:+.4f}, {hi:+.4f}]  ({args.iters} resamples)")

    if not args.scores:
        # McNemar on discordant pairs
        b_only = sum(1 for i in range(n) if a[i] == 1 and b[i] == 0)  # A pass, B fail
        c_only = sum(1 for i in range(n) if a[i] == 0 and b[i] == 1)  # A fail, B pass
        disc = b_only + c_only
        print(f"\nMcNemar (binary):")
        print(f"  A-pass/B-fail = {b_only}   A-fail/B-pass = {c_only}   discordant = {disc}")
        if disc == 0:
            print("  No discordant pairs — runs are identical on every item. No detectable difference.")
            chi2, p = 0.0, 1.0
        else:
            chi2 = (abs(b_only - c_only) - 1) ** 2 / disc  # continuity-corrected
            p = chi2_1df_sf(chi2)
            print(f"  chi-square (cont. corrected) = {chi2:.3f}   p = {p:.4f}")
        ci_real = lo > 0 or hi < 0
        mc_real = p < 0.05
        print("\nVERDICT:")
        if mc_real and ci_real:
            print("  ✅ REAL — significant (p<0.05) and the bootstrap CI excludes zero.")
        elif mc_real or ci_real:
            print("  ⚠️  WEAK — one test fires, the other doesn't. Treat as inconclusive; gather more data.")
        else:
            print("  ❌ NOISE — not significant and the CI includes zero. Do NOT ship on this delta.")
    else:
        print("\nVERDICT:")
        if lo > 0 or hi < 0:
            print("  ✅ REAL — bootstrap CI on the score difference excludes zero.")
        else:
            print("  ❌ NOISE — bootstrap CI includes zero. Difference is within sampling noise.")


def cmd_kappa(args):
    judge = load_labels(args.judge)
    human = load_labels(args.human)
    if len(judge) != len(human):
        die(f"judge ({len(judge)}) and human ({len(human)}) must be aligned, equal-length arrays")
    n = len(judge)
    # confusion vs human-as-truth. positive class = FAIL (the defect we want the judge to catch) = 0.
    # define: "flag" = judge says fail(0); "defect" = human says fail(0).
    tp = sum(1 for i in range(n) if human[i] == 0 and judge[i] == 0)  # real defect, judge caught
    fn = sum(1 for i in range(n) if human[i] == 0 and judge[i] == 1)  # real defect, judge missed
    tn = sum(1 for i in range(n) if human[i] == 1 and judge[i] == 1)  # real pass, judge passed
    fp = sum(1 for i in range(n) if human[i] == 1 and judge[i] == 0)  # real pass, judge false-alarmed
    agree = (tp + tn) / n
    # Cohen's kappa
    p_yes_j = sum(1 for x in judge if x == 0) / n
    p_yes_h = sum(1 for x in human if x == 0) / n
    pe = p_yes_j * p_yes_h + (1 - p_yes_j) * (1 - p_yes_h)
    kappa = (agree - pe) / (1 - pe) if pe != 1 else 1.0
    tpr = tp / (tp + fn) if (tp + fn) else float("nan")
    tnr = tn / (tn + fp) if (tn + fp) else float("nan")
    prec = tp / (tp + fp) if (tp + fp) else float("nan")

    print(f"n = {n}   (positive class = FAIL — the defect the judge should catch)")
    print("  (labels normalized: pass/correct/true/1 -> PASS; fail/incorrect/false/0 -> FAIL. "
          "If your raw 1 means 'fail', relabel before running so TPR/TNR aren't inverted.)")
    print(f"  raw agreement (accuracy) = {agree:.3f}   <- DO NOT trust this alone")
    print(f"  Cohen's kappa            = {kappa:.3f}")
    print(f"  TPR / failure recall     = {tpr:.3f}   (of real failures, judge caught this fraction)")
    print(f"  TNR / pass specificity   = {tnr:.3f}   (of real passes, judge passed this fraction)")
    print(f"  precision (flag->defect) = {prec:.3f}")
    print(f"  confusion: caught={tp} missed={fn} false-alarms={fp} correct-pass={tn}")
    print("\nVERDICT:")
    thr = args.threshold
    if not math.isnan(tpr) and tpr < 0.7:
        print(f"  ❌ Judge MISSES {(1-tpr)*100:.0f}% of real failures — recall too low to trust as a gate.")
    if kappa >= max(thr, 0.85):
        print(f"  ✅ kappa {kappa:.2f} — strong agreement; usable for high-stakes gating.")
    elif kappa >= thr:
        print(f"  ✅ kappa {kappa:.2f} >= {thr} — acceptable for non-critical gating; keep iterating.")
    else:
        print(f"  ❌ kappa {kappa:.2f} < {thr} — NOT validated. Read every disagreement, fix the rubric, re-test.")
    if agree > 0.9 and (math.isnan(tpr) or tpr < 0.5):
        print("  ⚠️  High accuracy + low recall = the 'passes everything' illusion. Add hard negatives.")


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)

    pw = sub.add_parser("power", help="sample size needed to detect a delta")
    pw.add_argument("--baseline", type=float, required=True, help="current pass rate, e.g. 0.80")
    pw.add_argument("--delta", type=float, required=True, help="absolute improvement to detect, e.g. 0.04")
    pw.set_defaults(func=cmd_power)

    cp = sub.add_parser("compare", help="is the A->B difference real or noise?")
    cp.add_argument("--a", required=True, help="JSON array of run A results (aligned with B)")
    cp.add_argument("--b", required=True, help="JSON array of run B results (aligned with A)")
    cp.add_argument("--scores", action="store_true", help="treat inputs as continuous scores, not pass/fail")
    cp.add_argument("--iters", type=int, default=10000, help="bootstrap resamples (default 10000)")
    cp.add_argument("--seed", type=int, default=1234, help="bootstrap RNG seed (reproducible)")
    cp.set_defaults(func=cmd_compare)

    kp = sub.add_parser("kappa", help="validate an LLM judge against human labels")
    kp.add_argument("--judge", required=True, help="JSON array of judge verdicts (aligned with human)")
    kp.add_argument("--human", required=True, help="JSON array of human ground-truth labels")
    kp.add_argument("--threshold", type=float, default=0.6, help="min kappa to accept (default 0.6)")
    kp.set_defaults(func=cmd_kappa)

    args = p.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
