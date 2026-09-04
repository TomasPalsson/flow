---
name: portfolio-construction-sizing
description: Position weighting, cluster capping, floors/caps, cash sleeve, and whole-share reconciliation for a concentrated 5-10 name book. Load at BUILD Stage 5 (sizing) and at REVIEW quarterly re-score. Do NOT load for weekly hazard-scan or for data-fetch stages.
---

# Position Weighting, Cluster Caps & Sizing (5-10 Names)

## 0. The counterintuitive result up front

At N=5-10, **optimization sophistication and out-of-sample quality are inversely related.**
DeMiguel, Garlappi & Uppal (2009): 14 mean-variance-type optimizers (Bayesian shrinkage,
constrained variants) vs. naive 1/N across seven datasets — none consistently beat 1/N in
out-of-sample Sharpe, certainty-equivalent return, or turnover. Their own reported estimate of
the data needed to reliably beat 1/N: **~3,000 months for 25 assets, ~6,000 for 50** (the
paper's figures, approximate — no discretionary investor holds anywhere near this history).
Michaud (1989): MVO is an **"error-maximizer"** — it overweights assets whose (noisiest-in-the-
system) expected-return inputs it wrongly believes are best. **Counterpoint, not hidden**:
Kritzman (2006) called the error-maximizer framing overstated; defenders say the fix is better
inputs (shrinkage, Black-Litterman), not abandoning optimization. Synthesis: MVO isn't "wrong,"
it's **input-starved at N=5-10** — and the failure mode, concentrating into noise, holds either
way.

## 1. The weighting engine — tiered conviction anchored to 1/N

1. **Anchor at 1/N.**
2. **Assign 2-3 conviction tiers** on qualitative, stated factors only — thesis strength/
   variant view, payoff asymmetry, valuation cushion, business resilience. Never a numeric
   expected-return input; that reintroduces the false-precision trap of §2.
3. **Tilt band per tier** (illustrative, not prescriptive):

| Tier | Weight vs. 1/N |
|---|---|
| Highest conviction | ≈1.3-1.6x |
| Baseline | 1.0x |
| Lower conviction | ≈0.6-0.8x |

4. **Renormalize** to (100% − cash sleeve %).
5. **Round to whole or half points, never decimals** — decimals imply precision the qualitative
   tiers don't have. A weight of "12.7%" is not more rigorous than "13%"; it just hides that.

## 2. Why Kelly is fragile, not merely risky

Kelly's inputs are a win probability and payoff ratio (continuous form: excess return / variance).
In blackjack these come from known deck composition. In discretionary equity investing **the
"edge" is not measured, it's guessed** — a multi-year return estimate is a qualitative judgment
dressed as a number. Feeding a guess into a formula optimal *conditional on the guess being
right* produces false precision: "Kelly says 34.7%" inherits 100% of the guess's uncertainty and
shows none of it. Worse than ordinary estimation error because Kelly is **first-order sensitive**
to the return estimate — numerator return, denominator variance, no discount for confidence. Two
structural problems compound this for a portfolio: (a) the classical formula assumes
**independent, sequential bets** with capital recycled; a book of simultaneous correlated
positions violates this — independent per-name Kelly sizes can jointly produce far more risk than
any one calculation implies; (b) fixing that via multi-asset Kelly reintroduces the same
covariance-estimation problem that kills MVO at this N (§0, §3).

**Conclusion**: Kelly serves only as a clearly-labelled **quarter-Kelly-or-smaller sanity
ceiling** on a haircut (not base-case) edge estimate — never the generative formula, never
surfaced as "the" weight. Illustrative, approximate, conditional on the edge being right: half-
Kelly keeps ~75% of full-Kelly growth while roughly halving variance; one cited figure puts P(50%
loss) at ~1/2 under full Kelly vs. ~1/8 under half.

**Deliberate divergence from the sibling `investment` and `alpha-hunt` skills**, which do use
Kelly generatively: those run shorter-horizon, higher-turnover books where positions recycle
capital fast enough to approximate the sequential-bet assumption and recalibrate edge against
realized outcomes. A 1-5yr concentrated hold has neither — bets are simultaneous and correlated,
with no fast feedback to correct a bad guess. The horizon is what justifies Kelly-as-ceiling here.

## 3. Cluster mapping — the most important practical technique

Eight tickers are very often three real bets. A covariance matrix is unestimable at this N: 8x8
has 28 off-diagonal entries, and 2-5yr histories don't supply enough independent observations —
distinguishing 0.62 from 0.71 is noise at ~100-150 data points. Clustering must therefore be
**qualitative and structural, not statistical**:

- **Shared end-market/revenue driver** — same demand driver (AI capex, one commodity) regardless
  of GICS sector.
- **Shared customer/supplier concentration** — a shock to one shared node hits both holdings.
- **Shared dominant macro sensitivity** — duration/rates, commodity input costs, FX, credit.
  "Different industry" names can both be, functionally, "long duration growth."
- **Shared regulatory/geopolitical single point of failure** — one jurisdiction's headline moves
  multiple names.
- **GICS as a floor, not the whole test** — necessary flag, not sufficient; same-sector can be
  different bets, different-sector can be the same bet.
- **Benchmark co-movement as a coarse flag only** — directional signal to review, not a
  correlation coefficient to trust at this N.

**Required output**: an explicit cluster map. Cap **aggregate cluster weight** as an independent
constraint on top of per-name caps (§4) — a book can pass every per-name cap and still be one
dominant factor bet.

## 4. Hard floors and caps

| Constraint | Value | Why |
|---|---|---|
| Per-name floor | ~5% | Below this a position can't move total return even doubling (at 1%, a 100% gain adds ~1pp); it consumes monitoring/cost attention the concentration mandate can't spare. |
| Per-name cap (initiation) | ~20-25% | Idiosyncratic single-company risk (fraud, product failure, lost customer) can't be diversified away within one name, regardless of conviction. |
| Aggregate cluster cap | ~50-60% | Independent layer on §3 — stops per-name caps individually passing while the book is still one factor bet. |

Practitioner heuristics, **low-medium confidence on the exact numbers** — no single authoritative
standard exists. High confidence on the structural point: *some* floor and cap should exist,
stated up front. The cap binds over the tier tilt — high conviction is never license to override it.

## 5. Name count: 5-10, never pad

Fewer than 5 genuinely differentiated ideas → prefer a smaller book with a larger, disclosed cash
sleeve over a filler idea. 5-10 is a design target, not satisfied by lowering idea quality.

Best-ideas research is genuinely **mixed**. For: managers' single highest-conviction picks,
isolated, tend to outperform (Cohen, Polk & Silli) — some samples cite roughly 1-2.5pp/quarter
excess for the top idea vs. the rest of the book. Against: realized fund-level concentration is
associated with *worse* net performance (Pollet & Wilson 2008; Sapp & Yan 2008; Huang, Sialm &
Zhang 2011) — plausibly higher vol, higher error cost when the thesis is wrong, fee drag.
**Reconciliation**: the case for concentration is strongest at "which ideas get capital," weakest
at "how few positions total" — supporting 5-10 specifically, concentrated enough for real
differentiation, not so concentrated (1-3) that one wrong thesis dominates.

## 5a. The small-book fallback, implemented — `--allow-small-book`

The doctrine above ("prefer a smaller book with a larger, explicitly policy-driven cash sleeve")
is not just prose — `scripts/compute-weights.js` implements it as an explicit, opt-in path, not a
relaxation of the default band.

**When it is legitimate**: Stage 6 (post-adversary) genuinely leaves fewer than 5 names that
cleared the conviction bar, and the honest alternative is padding the book with a name that didn't
clear it. It is **not** legitimate as a way to avoid doing the research to find a 5th idea, and it
is never legitimate to reach for it before the adversary pass has actually run.

**How to invoke it**: pass `--allow-small-book` on the CLI (or `allow_small_book: true` in the
input JSON) alongside a `positions` array of 1-4 names. Without the flag, 1-4 names still hard-
errors exactly as before — **the default stays strict**; 5-10 is still enforced with no other
change in behavior. The flag never relaxes the upper bound of 10 names.

**It is not silently permissive.** Engaging it *requires* `cash_sleeve_pct` to expand to absorb
the undeployed capital — the script computes a minimum required sleeve from the shortfall and
refuses to run if the caller passes a small sleeve with a small book. The rule: a book of N < 5
names may not deploy more than N/5 of the equity portion a full 5-10 name book would deploy; the
remainder must sit in disclosed cash. Concretely, minimum `cash_sleeve_pct` = 100 × (1 − N/5):

| N (names) | Max equity deployed | Min required cash sleeve |
|---|---|---|
| 4 | 80% | 20% |
| 3 | 60% | 40% |
| 2 | 40% | 60% |
| 1 | 20% | 80% |

(N=3 → 40% matches the worked example already documented in `execution-prompt-build.md`: "a
disciplined 3-name book with 40% disclosed cash is a valid output.") This floor **replaces** the
normal cash-sleeve band (policy range ~2-10%, hard ceiling 20%) for a small book only — the normal
band still applies unchanged to a 5-10 name book, flag or no flag. There is also a wide sanity
ceiling on the sleeve (95%) so a caller cannot type an absurd value and have it accepted as
"policy" without comment.

**What the output carries**: every small-book result sets `small_book: true` and a
`small_book_rationale` string explaining the shortfall and the sleeve math — both fields are
always present (`small_book: false` / `small_book_rationale: null` on a normal book), so no
downstream consumer (drafts, thesis memos, the decision log) can mistake a deliberately
under-deployed book for a normal one. `flags` also carries a `SMALL BOOK:` entry for visibility in
any report.

**Everything else stays locked.** The per-name floor/cap, cluster cap, and the MAX_NAMES=10
ceiling apply identically to a small book — they still error rather than clamp, exactly as for a
normal-band book.

## 6. The Bessembinder tension, stated not softened

Full CRSP universe since 1926: a bit over half of stocks had lifetime returns below one-month
T-bills; **the top ~4% of stocks accounted for the market's entire net wealth creation, and
roughly the top ~0.3% (~90 of ~26,000 companies) for over half of it.** A 5-10 name book bets on
identifying the thin right tail; the narrower the count, the higher the odds of missing it.

**How to handle it**: (a) concentration is only defensible when selection is conviction/quality-
driven, not random — the unconditional base rate covers ~26,000 stocks including every failure,
not a diligenced shortlist, but it's a reminder that stock-picking skill has to be doing real
work; (b) where the mandate allows, bias selection toward **asymmetric/convex payoff profiles**
(optionality, secular tailwinds) since the payoff to the right few positions is extremely skewed;
(c) the **5-name floor exists partly to hedge this** — a 2-3 name book has materially higher odds
of missing the outlier without much conviction-expression gain.

## 7. Cash sleeve — policy, never market view

Size by **policy tied to investor constraints** (liquidity need, drawdown tolerance, add
capacity) — never a near-term market view. Practitioner range roughly **2-10%**; treat as a rough
heuristic, not a derived optimum. "Dry powder" for a better entry lacks reliable empirical
support — it requires being right twice, and investors are typically poor at redeployment,
leaving cash idle through much of a rally. It can serve a legitimate behavioral role (staying
disciplined through drawdowns), but that's not a timeable expected-value edge — **disclose
explicitly that cash is not a market-timing lever**, and keep it separate from rounding-residual
cash (§8) so the two are never conflated.

## 8. Whole-share reconciliation — run after weights are set

- Fractional shares available/assumed → target and actual weights are effectively identical.
- Not available → **recompute actual post-rounding weights, compare to target, disclose the
  delta.** Round toward keeping higher-conviction names at or above target; share price must
  never become a de facto sizing signal.
- **Rounding forces a name >2-3pp off target → flag it explicitly**, don't silently absorb the
  residual into cash or another name. At small accounts/high per-share prices no whole-share
  quantity may sit near the target at all — consider excluding the name for that account size
  rather than force-including it distorted.

## Anti-Patterns

- **Presenting Kelly- or MVO-derived weights as "the mathematically optimal allocation."**
  Mechanism: launders a qualitative guess through a precise-looking formula — "34.7%" is less
  honest about its own uncertainty than a round-number tier, not more rigorous.
- **Counting tickers as a diversification proxy.** Mechanism: skips the shared-factor check
  (§3); "8 stocks" that are functionally 3 bets is more dangerous than obvious concentration
  because it looks diversified on a position-count basis.
- **Computing a covariance matrix from 2-5yrs of history and trusting it.** Mechanism:
  insufficient independent observations for 28+ off-diagonal entries; small differences between
  estimated correlations are spurious precision, not signal.
- **Treating dry powder as a market-timing edge.** Mechanism: a forecasting bet dressed as
  construction — the evidence investors redeploy such cash well on time is weak.
- **Ignoring whole-share rounding until weights are finalized**, then presenting pre-rounding
  targets as the realized portfolio. Mechanism: presented weights stop matching actual holdings,
  and the gap compounds silently across every future review.
- **Sub-floor "starter" positions.** Mechanism: too small to move return, still consumes full
  monitoring/transaction-cost overhead — contradicts the concentration mandate's own logic.
- **Applying institutional diversified-mandate caps (e.g., 5%) to a 5-10 name book.** Mechanism:
  mechanically forces near-equal-weight regardless of conviction, defeating concentration.
