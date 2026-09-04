---
name: position-sizing
description: Kelly criterion sizing with capital-scale and temperament adjustments, plus tranching rules for entry. Load when computing the final position size in the thesis memo.
---

# Position Sizing — Kelly with Real-World Adjustments

## Kelly Criterion (continuous form for stocks)

```
f* = (μ − r) / σ²
```
Where:
- **μ = ANNUALIZED expected return** (must be annualized — see below)
- r = risk-free rate (10Y Treasury yield, annualized)
- σ = ANNUALIZED expected volatility (3-year realized annualized as proxy)
- f* = Kelly-optimal capital fraction

**CRITICAL — Annualization step**: The 3-scenario model in the thesis memo produces a 3-year cumulative expected value (e.g., EV = +60% over 3 years). This is NOT μ — it's a 3-year return. Convert before plugging into Kelly:

```
EV_3year = 0.2 × Bear_return + 0.6 × Base_return + 0.2 × Bull_return
μ_annual = (1 + EV_3year)^(1/3) − 1
```

Example: if EV_3year = +60%, then μ_annual = 1.60^(1/3) − 1 = 16.96%, NOT 60%.

Skipping this step inflates Kelly sizes 3-5×, producing dangerously concentrated positions.

**Full Kelly is too aggressive.** Empirically, full Kelly produces ~50% drawdown probability. Even Thorp used half-Kelly. The skill defaults to half-Kelly; quarter-Kelly for uncertain or edge cases.

## Default Kelly Fractions by Confidence

| CS100 + Catalyst Score Combined | Kelly Fraction | Rationale |
|--------------------------------|----------------|-----------|
| CS100 ≥ 75 AND catalyst score ≥ 80 | 1/2 Kelly | High conviction, well-cataclyzed |
| CS100 65-75 AND catalyst score 60-80 | 1/3 Kelly | Standard |
| CS100 55-65 OR uncertain edges | 1/4 Kelly | Edge case |
| CS100 ≥ 75 BUT financial / cyclical / spinoff | 1/3 Kelly | Sector or structure uncertainty |
| First time investing in this name | Apply -1 step (move down one tier) | Path-dependent caution |

## Capital Scale Adjustments (CRITICAL)

Kelly math assumes infinite divisibility and zero friction. Real portfolios deviate.

### < $50K Portfolio (Kelly Math Breaks)

DO NOT use Kelly directly. Use simpler heuristics:
- Maximum single position: 10% of portfolio ($5K on $50K)
- Minimum tradeable position: 2.5% of portfolio (commissions and bid-ask matter)
- Strongly advise no more than 5-7 positions total (concentration vs diversification)
- Recommendation: skill should warn that single-stock picking at this scale carries high ruin risk; index funds may be preferable

[SURPRISING] data: Bessembinder 2018 — 96% of net US market gains 1926-2016 came from just 4% of stocks. At small scale with concentration, you NEED to pick correctly; the math of stock-picking is brutal at small sizes.

### $50K - $5M Portfolio (Standard Kelly Applies)

- Half-Kelly default
- Hard cap: 25% single position
- Hard cap: 40% per sector
- Hard cap: 60% per asset class (within equity)
- Cash position: 5-25% strategic dry powder

### > $5M Portfolio (Liquidity Constraints Active)

- Half-Kelly BUT clamped to ≤ 5% of stock's 30-day ADV
- More positions feasible (15-25 total)
- Tax-lot strategy matters (specific identification vs FIFO)
- Consider direct-indexing / tax-loss harvesting at scale

## Temperament Adjustments

The user's risk tolerance modifies Kelly:

| User Self-Assessed Tolerance | Kelly Adjustment |
|------------------------------|-----------------|
| "Can hold through 50% drawdown" | Standard (half-Kelly) |
| "Can hold through 30% drawdown" | Third-Kelly |
| "Can hold through 20% drawdown" | Quarter-Kelly |
| "Can hold through 10% drawdown" | STOP — recommend index funds instead, single-stock picking is wrong |
| "I don't know" | Quarter-Kelly default + explicit drawdown education |

**Education**: A high-quality compounder can easily draw down 30-40% during business-cycle troughs WITHOUT thesis breaks. Apple drew down 38% in 2018 and 27% in 2022. Berkshire drew down 50% in 2008-2009. These were NOT thesis breaks.

## Catalyst Multiplier (from catalysts.md)

After computing base Kelly:
```
Position Size = Base Kelly × Catalyst Multiplier × Capital Scale Adjustment × Temperament Adjustment
```

Catalyst multiplier range: 0.5x to 2.0x.

Hard ceiling still applies: 25% single position regardless of multiplier stack.

## Three-Tranche Entry Plan

NEVER buy 100% at once. Use 3-tranche tranching:

### Tier 1: Wide-Moat Compounder (high conviction, low patience required)
- Tranche A (now): 50% of target position
- Tranche B (-7% from entry OR within 60 days): +25%
- Tranche C (-15% from entry OR after Q+1 earnings confirms thesis): +25%
- Maximum Entry Price: Tranche A price × 1.10 (don't chase)

### Tier 2: GARP / Growth (standard conviction)
- Tranche A: 40% now
- Tranche B (-10% OR after confirmation): +30%
- Tranche C (-20% OR major milestone): +30%
- Maximum Entry Price: × 1.05

### Tier 3: Deep Value / Turnaround
- Tranche A: 33% now
- Tranche B (after first earnings confirms turnaround thesis): +33%
- Tranche C (after second confirmation): +34%
- Maximum Entry Price: × 1.00 (no chasing — discipline matters more for value)

### Tier 4: Cyclical
- Tranche A: 33% now
- Tranche B (-15% OR cycle indicator improves): +33%
- Tranche C (-25% OR mid-cycle indicator confirmed): +34%

### Tier 5: Special Situation (Spinoff / Activist)
- Tranche A (after forced-selling pressure subsides — for spinoffs, Days 10-45 post-distribution): 50%
- Tranche B (after Form 10 quiet period ends OR activist next move): 30%
- Tranche C (-15% OR after first earnings as independent): 20%

## Margin of Safety by Stock Type

Required discount to intrinsic value (base case):

| Stock Type | Required MOS | Rationale |
|-----------|--------------|-----------|
| Wide-Moat Compounder | 15-25% | Compounding makes up for paying near-IV |
| GARP / Growth | 25-35% | Standard discount |
| Cyclical | 40-50% | High intrinsic uncertainty around cycle position |
| Special Situation | 25-35% | Catalyst clarity reduces required MOS |
| Deep Value / Turnaround | 40-50% | High uncertainty about quality recovery |

[SURPRISING]: Klarman's MOS protects against the BEAR CASE, not the base case. A 30% MOS to base case might only be 5% MOS to bear case. The skill should compute MOS against BOTH and report the binding constraint.

**Asymmetry Ratio** = (Bull case − Current Price) / (Current Price − Bear case)
- Required: ≥ 2:1
- Preferred: ≥ 3:1
- If asymmetry < 2:1: reduce position size by 0.5x multiplier OR reject

## Concentration Discipline

When a winner becomes > 20% of total portfolio: trim back to 15-18%. Sell highest-cost-basis lots first.

[SURPRISING] Bessembinder caveat: extreme winners are rare and tend to be HUGE outliers (Apple, Microsoft, Amazon multibaggers). Trimming a long-term compounder too aggressively forfeits the tail. Balance: trim only modestly (15-18% target), not aggressively (back to original 5%).

## Cash Position

Strategic cash:
- 5% baseline cash (transaction friction)
- Add 10-20% additional cash when CAPE > 35 (current May 2026 = 42 → add cash)
- Add 5-10% cash when CS100 of best opportunity < 65 (no compelling picks)
- Cash is OPTION VALUE — the ability to deploy at lower prices when others are forced sellers

[SURPRISING] Marks: Oaktree never raises cash for "market timing" — cycle awareness works by tilting between more/less risky assets within fully-invested portfolio. The skill's "patient cash" output is an exception specifically for retail context where 100% deployment isn't required by mandate.

## Reporting in the Thesis Memo

The position-size section should show:
```
RECOMMENDED POSITION SIZE: X% of equity portfolio (= $Y of $Z portfolio)

Kelly Calculation:
- Expected annual return: μ = X%
- Volatility (3y realized): σ = X%
- Risk-free rate: r = X%
- Raw Kelly f* = X%
- Adjusted to (half/third/quarter)-Kelly: X%

Multipliers Applied:
- Catalyst quality (composite Y/125): ×Z
- Capital scale: ×Z
- Temperament: ×Z

FINAL SIZE: X% (capped at 25% per single-position rule)

Tranching plan:
- Tranche A (now): A% of target = $A
- Tranche B (trigger: condition): B% of target = $B
- Tranche C (trigger: condition): C% of target = $C

Maximum Entry Price: $MAX (= Tranche A × 1.0X)
```
