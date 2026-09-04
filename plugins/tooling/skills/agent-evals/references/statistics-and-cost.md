---
name: statistics-and-cost
description: Statistical rigor (sample sizing, bootstrap CIs, paired McNemar, multiple-comparison correction), the tiered eval pyramid, CI/CD scheduling cadences, cost-control tactics, and the data flywheel. Load when designing the eval pipeline, arguing whether a result is significant, choosing sample sizes, scheduling evals, or cutting cost.
---

# Statistics, Cost & Scheduling

## Is the result real? — statistical rigor

LLM evals have **two** variance sources: data noise (which examples you sampled) and prediction noise (the model's own stochasticity — often ~2× the data noise at small n). Both must be controlled before a delta means anything.

### Sample sizing (independent arms)

| Detectable delta | Examples needed per arm |
|------------------|-------------------------|
| 12 pt | ~165 |
| 7 pt | ~480 |
| 4 pt | ~1,580 |
| 2 pt | ~6,300 |

**A 100-example eval only resolves ~15-point deltas.** At n=100, p=0.8, the 95% CI is ±8 pt — a 4-point "win" is inside the noise.

### Use bootstrap, not the CLT, below a few hundred

Eval scores cluster near 0 and 1 (bimodal) — CLT-based intervals are invalid at small n. Bootstrap: resample with replacement 1,000–10,000×, recompute the metric each time, take the 2.5th/97.5th percentiles. If a delta's CI excludes 0, it's real. Binary SE shortcut: `SE = sqrt(p(1-p)/n)`.

### Paired designs are ~10× more efficient

Run both variants on **identical inputs**; analyze only **discordant pairs** (one passed, one failed) with **McNemar's test**. Concordant pairs carry zero information. A 5% net edge needs ~290 paired examples vs thousands unpaired. This is why A/B-on-the-same-golden-set beats independent arms for prompt/model comparisons.

### Other rigor

- **pass@k vs pass^k:** capability vs reliability; `0.75^3 ≈ 42%`. Run k trials at temp>0, compute both.
- **Multiple comparisons:** testing 10 prompts at α=0.05 ≈ 40% chance of a false positive — apply Bonferroni (α/k) or Benjamini-Hochberg FDR. For sequential peeking use O'Brien-Fleming boundaries (strict early, looser later).
- **Clustered data** (same prompt in many languages, related docs) → cluster SEs; naïve SE can understate by 3×.
- **Any result without a CI is a point estimate, not a finding.**

Bundled tool: `python scripts/eval_stats.py power --baseline 0.8 --delta 0.04` and `... compare --a a.json --b b.json --paired`.

## The tiered eval pyramid

```
   △  Tier 3   human review / canary / A-B test      pre-release    hours–weeks   $$$
  ◢◣  Tier 2   LLM-judge on curated golden set        per-PR / nightly  minutes    $$
 ◢——◣ Tier 1   deterministic asserts + cheap classifiers  every commit  seconds    ¢
```

Inverting it (LLM-judge on every PR over the full set) prices the gate out of existence — which is why most teams build only Tier 3 and then never run it. **Build Tier 1 first.**

- **Tier 1 (every commit, <5 min, <$1):** JSON/schema validity, regex blocklists (secrets/PII/injection), tool-call presence asserts, latency/cost budgets, sub-10ms classifiers. Path-scope it (only fire if `prompts/`, `src/agent/`, `src/tools/`, `evals/` changed); `cancel-in-progress` in CI.
- **Tier 2 (per-PR on 20–100 golden cases; nightly on 500–2,000):** binary judge rubrics; gate on McNemar/Welch vs a 7-day rolling baseline (`p<0.05 AND effect > ~0.03`), not on a raw point move. Nightly commits a fresh baseline JSON.
- **Tier 3 (pre-release):** human spot-check of 100–200 tail cases; canary 1–5% traffic; auto-rollback if rolling-mean drifts >2–3 pt over 15–60 min.

## Cost-control tactics

1. **High-signal golden set over volume** — 50 curated, stratified, ~50/50 pass:fail cases beat 500 random. 20–100 for CI gates; 300–800 total across routes for nightly.
2. **Content-addressed verdict cache** — key on `hash(judge_version, prompt_template, input)`; re-runs are cache hits ≈ $0. Batch APIs add ~50% async discount.
3. **Coarse-to-fine cascade** — deterministic → cheap classifier (filters 30–50%) → frontier judge only on the residual. A 100-case suite can run for pennies.
4. **Cheaper judges** — open-weight classifiers (LlamaGuard-class) or Haiku/4o-mini for most rubrics; reserve frontier judges for genuinely hard reasoning (100× cost lever).
5. **Affected-only runs** — a script reads the PR diff, runs only affected routes; unchanged routes reuse cached baselines.
6. **Only build expensive evaluators for recurring problems** — a one-off failure gets a targeted deterministic check, not a new judge.

## Scheduling cadences

| Cadence | What runs | Gate |
|---------|-----------|------|
| Pre-commit (sec) | deterministic unit checks, local | block obvious breakage |
| CI per-PR (<5 min, <$1) | Tier 1 + judge on golden smoke set, affected routes | fail on det. failure or pass-rate below absolute floor |
| Nightly (15–30 min) | full judge sweep, McNemar vs rolling baseline | alert on route regression; commit new baseline |
| Pre-release (hours) | red-team + human sample + full rubric battery | no rubric below floor; no significant regression vs last release |
| Online/prod (ongoing) | 5–10% traffic sampled + cheap evaluators | rollback on >2–3 pt rolling drift; human queue for flags |

**Regression suite:** every confirmed production bug becomes a dedicated golden-set case **before** the fix ships — prevents silent re-introduction across model/prompt/dependency changes.

## The data flywheel

The cheapest way to scale evals is to make production generate them:

```
prod traffic → sample & auto-score (5–10%) → flag low/guardrail-trip traces →
human triage → confirmed failures → one-click into golden set → CI catches the class →
fix ships → traffic improves → repeat
```

- Promote failing prod traces to dataset entries (LangSmith/Braintrust support one-click).
- Track golden-set coverage against observed failure modes — a new prod pattern with no representative case = a blind spot.
- Stratify by cohort (segment, query type, language, route), not pure random — random over-samples the majority class.
- Refresh ~20% of the set per quarter; version it in git (LFS for JSON); code-review changes like prompt changes.
- Read ≥100 fresh traces every 2–4 weeks; stop at the 20-trace saturation point.

A golden set that never changes is slowly becoming irrelevant — high scores on a stale benchmark while new failures accumulate unseen.
