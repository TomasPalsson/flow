---
name: portfolio-horizon-signals
description: What actually predicts 1-5 year equity returns — momentum reversal at this horizon, ROIC fade, return decomposition, reverse-DCF falsification, and the Bessembinder base rate. Load at BUILD Stage 3-4 (scoring and thesis) and at REVIEW quarterly re-score. Do NOT load for the weekly hazard-scan, sizing, or data-fetch stages.
---

# What Predicts 1-5 Year Returns (and What Doesn't)

## 1. The horizon inversion — the reason this file exists

12-1 price momentum is a **3-12 month phenomenon that reverses at 3-5 years**. De Bondt & Thaler (1985)
— prior 3-5yr "loser" portfolios outperform prior "winner" portfolios over the *subsequent* 3-5yr
window — is one of the most replicated results in finance, independently re-confirmed against primary
sources: **treat this as settled, not hedged.** Lee & Swaminathan (2000) confirms the mechanism: the
bulk of 6-12mo momentum profit is offset by reversal over the following 2-5 years. The momentum-crash
literature (Daniel & Moskowitz 2016) shows the same decay-then-inversion pattern beyond ~12 months.

**Implication:** trailing 1-3yr price strength is NOT supporting evidence for a 1-5yr thesis. It is
neutral at best, mildly contrarian-negative at worst — a name that already re-rated hard over 3 years is
statistically more likely to be a De Bondt-Thaler "winner" due for reversion than a continuing
compounder, unless the re-rating is disentangled from genuine, sustained fundamental improvement (the
harder, more valuable judgment call).

**Nuance to hold exactly, not round off:** "avoid buying purely because of price strength" is
well-supported by the evidence above. "Actively fade/short strong performers" is a much bigger claim
with a thinner evidentiary base at the single-stock level — this skill does the former, never the
latter.

**Why `portfolio` cannot share a scoring spine with `alpha-hunt`:** alpha-hunt's momentum sleeve rewards
12-1 residual momentum and 52-week-high proximity because its holding period sits inside the
pre-reversal window; this skill's holding period sits on the far side of the same reversal. Same house,
same evidence base, opposite sign at the two horizons — a shared composite score would silently average
two contradictory signals into noise. Keep the scoring functions structurally separate.

## 2. Valuation anchors: index-level signal, single-stock noise

Predictive power of valuation ratios (CAPE, P/E-type) for forward returns **rises with horizon at the
index level** — Campbell & Shiller (1998) and follow-on CAPE regressions report R² anywhere from
roughly 0.1 to 0.8 for 10yr-forward S&P 500 returns depending on sample window [APPROXIMATE — heavily
sample-period-dependent, not a stable constant; do not cite a single R² as authoritative].

This does **not** transfer cleanly to single names. At the single-stock level the scatter of starting
valuation percentile against realized 5yr forward return stays wide — described in the practitioner
literature as shifting from "square" to "rhomboid" at 5yr horizons, i.e. less noisy than 1yr but far
from a tight line [APPROXIMATE, single source, directionally consistent with idiosyncratic risk
dominating at the single-name level]. Conflating the index-level R² with single-name predictive power
is a specific, named error this skill must not make.

**Conclusion:** single-stock cheapness is a moderate positive tilt, never a standalone buy trigger. A
statistically cheap stock can stay cheap, get cheaper, or be justifiably cheap (deteriorating moat,
secular decline) — cheapness alone does not resolve that ambiguity.

## 3. Quality/profitability — two claims, kept separate

**(a) Profitability persists as a cross-sectional factor.** Novy-Marx (2013) shows gross-profitability
return predictability persists more than 3 years post-formation, driven by underreaction, not
overreaction. AQR's Quality-Minus-Junk (Asness, Frazzini, Pedersen) independently confirms quality
persists as a factor, and low price-of-quality predicts higher future QMJ returns. Both well-replicated
— **state with confidence.**

**(b) Individual-company ROIC mean-reverts toward the cost of capital.** This is a *different* claim
from (a) and is the more load-bearing one for single-name selection. Conflating cross-sectional factor
persistence with single-company ROIC durability is a named anti-pattern (§11).

**ROIC fade is mandatory in any 5yr thesis regardless of magnitude precision.** Never hold current ROIC
flat through a terminal-value calculation on a currently-high-ROIC business. The specific fade
magnitude — sector persistence factors averaging ~0.79 (≈21%/yr fade of the *excess* return over cost
of capital, ranging ~10-30% by sector) — is a Counterpoint Global/HOLT-sourced synthesis rated
**Low-Medium confidence, single secondary source, not independently verified**. Treat it as illustrative
of "fade is real, sector-dependent, roughly a fifth to a third of excess ROIC erodes per year," never as
a computable constant to plug into a model without justification.

## 4. The Bessembinder base rate — the central tension

Bessembinder (2018): only **42.6%** of common stocks in CRSP (1926-2016) had a lifetime buy-and-hold
return exceeding one-month T-bills; the best-performing **~4%** of listed companies account for the
entire net wealth creation of the U.S. market since 1926. Both figures are **VERIFIED against
independent corroboration, including the exact 42.6% figure — cite with confidence.**

**State this plainly, do not soften it:** a 5-10 name book is a bet on identifying members of the thin
right tail, not a diversified sample of good businesses that will each modestly compound. Most
individual stock-picking processes, applied without edge, land disproportionately on the majority that
lag cash over long horizons. Every thesis must articulate why *this specific name* should sit in the
minority tail that drives returns — not present expected-return math as if it were the modal outcome.

Supporting color: JPMorgan's "Agony & Ecstasy" catastrophic-loss and median-underperformance figures
are **Medium confidence** (widely cited across report vintages, not independently re-verified here);
Petajisto's concentrated-position underperformance specifics are **Low confidence** (single secondary
source, not verified against the primary paper) — preserve both ratings, neither was independently
checked by the fact-check pass. **The "~75% of 15-stock portfolios fail to beat the market" claim is
UNVERIFIED and untraceable to a checkable primary study — omit it entirely; do not size on it and do
not repeat it even as color.**

## 5. Return decomposition as a thesis gate

`Total Return ≈ Dividend Yield + Per-Share Earnings/FCF Growth ± Multiple Change`

Attribution splits vary materially by window studied — one (1993-2020) reports roughly 1/5 dividends,
1/7 multiple expansion, 2/3 earnings growth; another reports roughly 44% EPS growth, 42% multiple
expansion, 14% dividends [both APPROXIMATE, single source each, window-dependent — give the range
honestly, do not pick one split and present it as the split]. The consistent, higher-confidence
qualitative conclusion across sources: **multiple expansion is historically the smallest and least
persistent long-run component**, even though it can dominate opportunistically over shorter windows.

**Rule:** require every thesis to state its expected decomposition explicitly. Flag as structurally
fragile any thesis where multiple expansion must be positive and contributes more than roughly a third
of projected 5yr return — a multiple is a sentiment/discount-rate object with no company-specific
mechanism forcing it to move, unlike dividends (directly observable from payout policy) or earnings
growth (forecastable, if imperfectly, from unit economics). A thesis that works at flat-or-lower exit
multiple is materially stronger evidence than one requiring re-rating.

## 6. Terminal value discipline

Terminal value typically represents **60-85% of total DCF value** under normal assumptions — a
practitioner convention (Wall Street Prep, Macabacus-type sources), not an academic constant
[APPROXIMATE, consistent with basic DCF math but sensitive to discount rate, forecast length, margin
assumptions]. A high TV share is **expected, not automatically a flaw** — Damodaran's explicit point.

The real flag is not the TV percentage in isolation. It is: (a) a small, hard-to-defend change in
terminal assumptions (growth rate, terminal margin, exit multiple) swinging the valuation conclusion by
more than a defensible assumption range would justify, or (b) TV exceeding roughly 85% of total value
**and** terminal assumptions simultaneously sitting above mid-cycle/peer norms — that combination is the
highest-risk pattern and should be flagged, not automatically rejected.

## 7. Reverse-DCF as falsification, not prediction

Forward-DCF-first is a motivated-reasoning machine: it forces a precise-looking point forecast from
uncertain inputs, and because terminal value dominates (§6), the analyst's own assumptions — not the
market's — drive the bulk of the output. This is a documented framework (Mauboussin/Rappaport,
"Expectations Investing"), well-established as methodology, not a disputed statistical claim.

**Reverse-DCF** solves backward from the current market price for the growth/margin/return assumptions
already implied. Its value is falsification: test the implied assumption against the company's own
historical range, industry growth rates, and TAM ceiling — ask whether it's *defensible*, not whether a
forward DCF can be tuned to hit a target price. **Require reverse-DCF before or alongside any forward
valuation**; a forward-only process is a process gap.

## 8. Per-share discipline

Per-share compounding, not aggregate business growth, is what a shareholder owns. SBC-driven share
count growth compounds over a 5yr hold in a way it does not over 1yr: "only" 2%/yr dilution is roughly
10% cumulative over 5 years, eroding per-share returns even if the underlying business grows well.
**Require dilution-adjusted per-share projections, never aggregate growth, for every thesis.**

Approximate flag thresholds from the source (treat as starting calibration, not validated constants):
trailing share-count growth **above ~2-3%/yr** warrants explicit dilution modeling; **above ~5%/yr** is
a significant headwind that must be explicitly overcome by underlying growth, not ignored; pre-profit /
high-dilution issuers can run **30-100%+/yr**, at which point per-share value destruction can occur even
alongside a successful business.

## 9. Capital allocation as a standing diligence item

Check, as a standing step rather than an optional note: buyback timing relative to valuation (buybacks
executed at cyclically high multiples are a negative signal), M&A frequency and record, dividend policy
stability, and trailing asset growth rate. The asset-growth anomaly — rapid asset growth associated with
poor subsequent shareholder returns — is **independently well-replicated in the academic
cross-sectional-finance literature, rated Medium-High confidence**, distinct from and corroborating the
single-source Mauboussin & Callahan capital-allocation synthesis it's often packaged with. **Rapid
trailing asset growth is a caution flag, not a growth-quality positive** — a management team's capital
allocation decisions compound over a 5yr hold; a bad acquisition doesn't cost one year, it resets the
compounding base for the rest of the hold.

## 10. Moats as fade-rate forecasting, not a binary label

The empirical record on moat-based total-return outperformance is **genuinely mixed — present this
honestly, do not resolve it in the skill's favor.** Boyd & Quinn (2006) reportedly found higher returns
and lower volatility for wide-moat firms at a 10-year horizon but **not** at 5 years — directly relevant
to this skill's holding period. Liu & Mantecon (2017) reportedly found wide-moat investing produces
higher *risk-adjusted* but not higher *total* returns. At least one study (Manditch 2018, secondary
source) reportedly found wide-moat-rated stocks *underperformed* no-moat stocks on total return —
counterintuitive, flagged explicitly rather than dropped. All three: [APPROXIMATE, single secondary
source each]. A structural confound compounds the ambiguity: wide-moat-rated companies are
disproportionately large-cap (reportedly ~5.6% of rated firms by count but ~62% of moat-universe market
cap in one analysis [APPROXIMATE, single source]) — a "wide moat" portfolio can statistically resemble a
large-cap index fund, muddying attribution of any outperformance to moat versus size/quality tilt.

**Practical read:** a moat claim must be tied to an explicit, below-sector-norm fade-rate justification
with a stated mechanism (switching costs, network effects, intangible/regulatory barriers, structural
scale cost advantage, efficient-scale niche) — not asserted from brand strength or market share alone.
"Has a moat" is not a binary screen; it is an input to how slowly ROIC is assumed to fade (§3).

## 11. Anti-patterns

- **Using trailing price strength as a positive signal.** The horizon-inversion evidence (§1) points the
  other way; strong 1-3yr trailing returns are, if anything, weak evidence of reversal risk.
- **Conflating index-level valuation R² with single-stock predictive power.** The index-level
  relationship is real and rises with horizon; it does not transfer cleanly to single names (§2).
- **Conflating cross-sectional profitability persistence with single-company ROIC durability.** These
  require different evidence — factor persistence is well-replicated, single-name ROIC mean-reversion is
  a company-specific claim that fades faster than a naive reading of the factor literature suggests (§3).
- **Sizing off unverified concentration statistics.** The "~75% of 15-stock portfolios fail to beat the
  market" figure is untraceable and must not appear in scoring or user-facing output (§4).
- **Backing into terminal assumptions that make the thesis work, instead of reverse-DCF-testing the
  market-implied baseline first.** The easiest way for a long-horizon thesis to become confirmation bias
  dressed as rigor (§6-7).
- **Projecting aggregate business growth instead of dilution-adjusted per-share growth.** Overstates 5yr
  expected returns whenever SBC issuance is nontrivial (§8).
- **Treating "wide moat" as a binary buy/no-buy screen.** The total-return evidence is mixed and
  confounded with large-cap size effects; a moat claim without a fade-rate mechanism is an assertion (§10).
- **Modeling 5-10 positions as independent, symmetric expected-return bets.** The Bessembinder skew means
  the realistic outcome distribution is "a few names carry the book, several are flat-to-negative vs.
  cash," not "each name independently compounds at its point estimate" (§4).
