---
name: portfolio-global-data
description: Cross-jurisdiction fundamentals normalization (IFRS/US GAAP/J-GAAP), currency handling, the Yahoo suffix-exchange-currency map, and data sourcing for global equities. Load at BUILD Stage 2-3 (screening and fundamentals) whenever any candidate is non-US. Do NOT load for US-only universes or for the weekly hazard-scan.
---

# Global Data: Sourcing, Currency, Accounting Normalization

Non-US candidates only. Skip this file entirely for a US-only screen.

## 1. Data sourcing reality (VERIFIED this session, 2026-08-01, `yahoo-finance2` 3.14.0)

- **`yf.quote()`/`yf.quoteSummary()` core modules (`summaryDetail`, `defaultKeyStatistics`, `financialData`, `price`) = 100% coverage** across 21 large/mid-cap symbols spanning 17 non-US markets. Non-US large/mid-cap coverage is NOT thin on free Yahoo data — do not assume otherwise.
- **Statement-history modules (`incomeStatementHistory`, `balanceSheetHistory`, `cashflowStatementHistory`) are flaky and can return EMPTY WITH NO ERROR.** Populated for 19/21 tested; empty for exactly 2 (`ITX.MC` Inditex, `D05.SI` DBS) despite the same deprecation warning firing identically on every call regardless of outcome. Never infer "data exists" from the warning being present or absent — **check the module payload itself is non-empty before using it**, per name, every run. Silent-degradation trap, not a hard failure — treat empty as "no data" (drop-or-flag), not transient.
- **`fundamentalsTimeSeries` FAILS on every symbol tested** with `option type invalid`, using the exact call shape the house `investment/scripts/fetch-financials.js` already uses. Do not route to it as a working fallback — dead code pending root-cause, not "available." (Possible version skew: installed 3.14.0 vs latest 4.0.0.)
- **`yf.search()` throws `Failed Yahoo Schema validation`** in the pinned 3.14.0 on every query. Workaround confirmed working: pass `{ validateResult: false }` as the third arg.
- **FinancialFilings MCP returned 403 on every data tool** this session (companies_list, isins_retrieve, companies_financials_retrieve, filing_categories_list). Account-linkage issue, not a code problem (needs signup at financialreports.eu under the same email as the connector identity). **Use opportunistically if it works; NEVER hard-require it** — a skill that requires it is currently 100% non-functional.
- Fallback ladder: (1) `yahoo-finance2` quote+quoteSummary → (2) FinancialFilings if its preflight (`filing_categories_list`) succeeds → (3) direct regulator source (SEC EDGAR, ESMA/national authority, Companies House, TDnet/EDINET, HKEXnews, ASX announcements — none tested this session, theoretical next rung only) → (4) **drop the candidate and say so** rather than build on half-verified data. Given the observed 24% currency-mismatch rate and 2/21 silently-empty statement histories, "drop rather than guess" is routine, not an edge case.

## 2. Currency — highest-stakes content in this file

Two distinct, independently-sourced currency concepts on every Yahoo symbol. Never assume they match.

- **`quote.currency`** (== `price.currency` == `summaryDetail.currency`, identical in every test) = **trading currency** — what the shares quote in.
- **`financialData.financialCurrency`** = **reporting currency** — what the statements are prepared in. `defaultKeyStatistics` never carries a currency field at all.
- **VERIFIED to differ on 5/21 tested names (24%)**: SHOP.TO (CAD shares/USD financials), ULVR.L (GBp shares/EUR financials — Unilever), EQNR.OL (NOK shares/USD financials — Equinor), BHP.AX (AUD shares/USD financials), 0700.HK (HKD shares/CNY financials — Tencent). Clustered exactly where expected: dual-currency multinationals and resource/ADR-heavy names. Using the wrong one produces a price in one currency over an earnings figure in another — nonsense P/E, EV/EBITDA, everything downstream.
- **Rule**: label every price/market-cap figure with `quote.currency` and every revenue/earnings/book-value figure with `financialCurrency`, explicitly, every time.

**The GBp trap (VERIFIED live)**: `SHEL.L` → `currency: "GBp"`, `regularMarketPrice: 3383.5`. The real price is **£33.835**, not £3383.50 — a 100x error if unhandled. `"GBp"` (lowercase p) is a distinct Yahoo string from `"GBP"` (used for some GBP-denominated LSE ETFs/gilts) — check the exact string.

**Detection rule**: a currency code ending in a lowercase letter after otherwise-uppercase ISO letters denotes minor-unit (sub-unit) quoting — divide by 100 before use in any calculation (position sizing, market-cap sanity check, cross-source safety check). `GBp` is the one case observed live; `ZAc` (Johannesburg cents), `ILa` follow the same documented Yahoo convention but were not independently reproduced — high-confidence by mechanism, not re-verified per currency.

**IBKR has no currency field, anywhere** (verified in the original research pass, not re-tested this session): `search_contracts`, `get_price_snapshot`, `get_price_history` return **no currency field on any contract or price**. Currency must be *inferred* from the matched exchange — which is exactly what the reconciliation check below tests. Resolve IBKR contracts by company name via `search_contracts` (never by reusing the Yahoo ticker string — local tickers differ across venues, e.g. Nestlé is `NESN` on EBS but `NESR` on IBIS/DE and `NSRGY` on PINK/US), match by exchange code (table below), then run the safety check.

**Reconciliation safety gate** (not enforced by either MCP server — the skill must implement it):
1. Normalize the Yahoo price to major units first (apply the GBp rule if applicable).
2. Pull IBKR's price for the matched contract (no currency label — assumed from step-3 exchange match).
3. If Yahoo's currency and IBKR's exchange-inferred currency differ, convert same-day or reject the match outright — a mismatch here almost always means the wrong IBKR row (e.g. ADR instead of primary listing).
4. **Reject if prices differ >2%** (absorbs IBKR's observed 15-20 min delay + Yahoo latency without waving through a wrong-venue match). A 10%+ gap matching the ratio between two listings of the same company (ADR vs primary) is conclusive evidence of a wrong match, not a data artifact — VERIFIED pattern: ASML US-vs-NL (~14% gap), BHP ADR-vs-ASX (~40% gap, non-1:1 ADR ratio).
5. **On failure: stop.** Do not average, do not guess, do not draft an order. Surface both raw prices, both currencies, both source identifiers to the user/log.

## 3. Suffix ↔ exchange ↔ IBKR code ↔ currency map

`[V]` = VERIFIED, observed live in `search_contracts` output. `[inf]` = standard public IBKR convention, never observed in either probe — spot-check with a live `search_contracts` call before trusting in skill logic. Lot size: **not covered by either source** — verify live via `search_contracts`/`get_option_parameters`, do not assume 1.

**Machine-readable source of truth: `data/exchange-currency-map.json`** (relative to this skill's root). It mirrors this table and is what the pipeline should actually load and key off of — `execution-prompt-build.md` Stage 2 loads it before normalizing any price. It carries three things this prose table compresses out: a per-entry `verified: true/false` boolean on every IBKR exchange code (the exact `[V]`/`[inf]` distinction above, machine-readable), an explicit `lot_size: null` on every market with a `_meta.lot_size_note` explaining that neither source document establishes a real lot-size number anywhere — never infer one, verify live — and an `_meta.warning` spelling out that every `trading_currency` value is an *inference* from the exchange, not an IBKR-confirmed fact, which is exactly what the reconciliation gate in §2 above and `references/05-ibkr-handoff.md` tests at runtime. Keep the two in sync if either changes; treat the JSON as canonical for anything a script or agent resolves programmatically, this table as the canonical explanation of why.

| Suffix | Exchange | IBKR code | Currency | Traps |
|---|---|---|---|---|
| *(none)* | NYSE/Nasdaq | `NYSE`,`NASDAQ`,`ARCA`,`BATS` [V] | USD | Baseline. |
| `.TO` | Toronto | `TSE` [V] | CAD | Financials may report in USD despite CAD shares (Shopify) — check `financialCurrency`. |
| `.V` | TSX Venture | `VENTURE` [inf] | CAD | Not tested. |
| `.L` | London (LSE) | `LSE` [V] | **GBp** (pence, most equities), GBP for some ETFs/gilts | #1 trap — see Sec 2. Check exact string, not just presence of "GB". |
| `.IR` | Euronext Dublin | `ISE` [inf; Yahoo `fullExchangeName:"Irish"` matches the verified `country_code:"IE"` but never searched] | EUR | — |
| `.AS` | Euronext Amsterdam | `AEB` [V] | EUR | Yahoo's own code is `AMS` — different systems, different short codes; never cross-feed one to the other. |
| `.DE` | Deutsche Börse Xetra | `IBIS` (also `FWB`/`FWB2`) [V] | EUR | Yahoo's own code is `GER`, displayed `"XETRA"` — third distinct code. |
| `.PA` | Euronext Paris | `SBF` [V] | EUR | Yahoo code `PAR`. |
| `.SW` | SIX Swiss Exchange | `EBS` [V] | CHF | Rare case where Yahoo and IBKR share the same short code — don't generalize. |
| `.MC` | Bolsa de Madrid | `MEFF`/`BM` [inf] | EUR | Statement-history modules empty for the one Spanish name tested (Inditex) — verify per-name. |
| `.MI` | Borsa Italiana | `BVME` [inf] | EUR | — |
| `.ST` | Nasdaq Stockholm | `SFB`/`OMX` [inf] | SEK | — |
| `.OL` | Oslo Børs | `OSE` [inf] | NOK | `financialCurrency:"USD"` observed for Equinor — oil/gas majors commonly report USD regardless of home listing currency. |
| `.CO` | Nasdaq Copenhagen | `CSE` [inf] | DKK | — |
| `.HE` | Nasdaq Helsinki | `HEX`/`HSE` [inf] | EUR | — |
| `.T` | Tokyo (JPX) | `TSEJ` [V] | JPY | No sub-unit trap (JPY has none) but large nominal magnitudes — sanity-check scale. |
| `.HK` | Hong Kong (HKEX) | `SEHK` [inf] | HKD | `financialCurrency:"CNY"` observed for Tencent — mainland-domiciled HK issuers commonly report in CNY. Do not assume HK listing ⇒ HKD financials. |
| `.AX` | ASX | `ASX` [V] | AUD | `financialCurrency:"USD"` observed for BHP — large diversified miners with USD global ops often report USD despite ASX/AUD listing. |
| `.SI` | Singapore Exchange | `SGX` [inf] | SGD | Statement-history modules empty for the one name tested (DBS) — verify per-name. |
| `.KS` | Korea Exchange | `KRX` [V] | KRW | — |
| `.TW` | Taiwan Stock Exchange | `TWSE`/`TAIWAN` [inf] | TWD | — |

## 4. Accounting-regime normalization (only distortions that move a screen's output)

**Flagship counterintuitive finding — J-GAAP still amortizes goodwill.** Textbook knowledge says goodwill is impairment-only under both IFRS (post-2004) and US GAAP (post-2001) — true. But **Japanese GAAP requires straight-line goodwill amortization over up to 20 years, and IFRS adoption in Japan is voluntary**, not mandatory. Large-cap Japanese names sit side-by-side on J-GAAP and IFRS within the same index. **Check regime per Japanese company before trusting net income, EBIT, or goodwill-linked multiples** — a J-GAAP name carries a recurring amortization drag an IFRS/US-GAAP peer with similar M&A history does not, making it look structurally worse "quality" purely from accounting mechanics.

| Item | Distortion direction/magnitude | Metrics hit |
|---|---|---|
| Leases (IFRS 16 vs ASC 842) | IFRS 16 capitalizes all leases and splits the expense into depreciation (stays in EBIT/EBITDA) + interest (falls below EBIT); ASC 842 keeps one operating-lease expense line. **Mechanically inflates IFRS EBITDA/EBIT ~5-15%+** for lease-heavy sectors (retail, airlines, hotels, restaurants) vs an economically identical US GAAP presentation — order-of-magnitude heuristic, not a peer-reviewed constant; compute the adjustment from the lessee's own ROU depreciation/interest footnote rather than a blanket haircut. | EV/EBITDA, EBIT margin |
| R&D/development costs | US GAAP expenses as incurred; IFRS (IAS 38) capitalizes development costs once feasibility/intent/ability are demonstrated. Inflates IFRS near-term net income and assets, deflates near-term expense — reverses over time via amortization but distorts any snapshot comparison. Concentrated in pharma, software, late-stage-development industrials. | Net margin, ROIC, R&D intensity |
| Goodwill (J-GAAP) | See flagship finding above. | Net income, ROE, book value trend |
| LIFO | Permitted US GAAP only, banned under IFRS. In inflationary periods, US LIFO filers report lower inventory/gross margin/net income than an IFRS FIFO peer holding identical inventory. Add back the disclosed LIFO reserve for comparable book value/inventory. Concentrated in oil & gas, autos/parts, industrial distributors, some retail. | COGS, gross margin, book value/P/B |
| PP&E revaluation | US GAAP: historical cost only. IFRS (IAS 16): elective cost or revaluation model, per asset class. Where elected (concentrated in real-estate-heavy sectors, some UK/continental property/utility names), inflates book value/equity vs a US GAAP historical-cost peer with identical assets. Elective and inconsistent even within IFRS — check the accounting policy note. | P/B, ROE |
| Minority interests (NCI) | Both regimes present NCI within equity post-2009 convergence. IFRS allows an acquisition-by-acquisition election between full-goodwill (fair value) and partial-goodwill (proportionate net assets) methods — two IFRS peers can be inconsistent with each other, not just vs US GAAP. Check whether consolidated equity includes NCI consistently. | Consolidated ROE/ROIC |

**No single "IFRS is more/less conservative" rule** — direction is item-specific and some effects partially offset (IFRS 16 inflates EBITDA; US LIFO understates book value, partially offsetting IFRS's other inflationary tendencies). A mechanical cross-regime rank without adjustment ranks accounting-policy choice as much as business quality.

## 5. Reporting-cadence mismatch → TTM staleness

US 10-K/10-Q = quarterly, 90-day max staleness. Most EU/UK/APAC ex-Japan = **semi-annual** (EU abolished mandatory quarterly reporting in 2013 under the Transparency Directive; UK DTR followed the same shift; ASX mandates half-yearly via Appendix 4D) → TTM refreshes only **twice a year**, up to **~180 days stale**, roughly double US staleness. Japan is the exception in practice: the *statutory* quarterly securities report was abolished April 2024, but **TSE listing rules still mandate quarterly "kessan tanshin" flash reports** within 45 days of quarter-end — Japan functions as a quarterly market via tanshin despite the formal filing being gone (an FSA panel was pushing in 2025 to re-mandate quarterly reporting formally — status is actively in flux, re-check before hard-coding). Foreign private issuers on US exchanges file 20-F annually with no mandated 10-Q-equivalent (6-K interim disclosure is voluntary and inconsistent in depth) — do not flag a legitimate FPI as stale/delinquent for lacking a quarterly print.

**Rule**: never label a fundamental "TTM" bare — always store the actual as-of/period-end date the TTM window covers, so a US name's ~30-day-old TTM and a semi-annual EU name's ~150-day-old TTM are visibly different, not silently equated.

## 6. ADR vs local line

- **Ratio errors corrupt per-share metrics exactly like an unadjusted split.** EPS, DPS, and book-value-per-share from the home filing must be multiplied/divided by the current ADR ratio before combining with the ADR price — a feed that skips this produces a P/E off by exactly the ratio factor, silently and plausibly.
- **Ratios change mid-series** (e.g. Natuzzi 1:1 → 1:5, effective Feb 2019) — an unadjusted historical series shows a fake EPS jump/price crash at the change date. Treat exactly like a corporate action requiring back-adjustment; re-verify the ratio for every distinct historical period in a multi-year pull.
- **Sponsorship level gates disclosure reliability**: Level I (OTC, no SEC registration, no GAAP reconciliation — highest risk of stale/incomplete "reported" financials in a US-centric database) < Level II (exchange-listed, partial US GAAP reconciliation) < Level III (exchange-listed, full US GAAP compliance). Unsponsored ADRs have no issuer disclosure obligation at all and can fragment liquidity across competing programs.
- **Fees**: ADR pass-through/custody fees typically **$0.01-$0.03/share**, deducted from dividends or billed directly — a permanent structural drag vs the local line, additive to (not a substitute for) withholding tax.
- **When the ADR is the wrong instrument**: illiquid ADR ratio creating awkward per-share economics despite a liquid home market; Level I/unsponsored ADRs where the home filing is materially more complete — **default to sourcing fundamentals from the home-market filing even when the position is held via ADR**, treating the ADR strictly as the trading/custody wrapper; also when the depositary bank's dividend withholding handling defaults to statutory (not treaty) rates absent investor paperwork, vs a broker holding the local line directly with relief-at-source.

## 7. Dividend withholding tax (rough hierarchy — Low-Medium confidence, verify at build time)

**Machine-readable source of truth: `data/withholding-tax.json`** (relative to this skill's root). It mirrors this table and carries `verify_before_use: true` on every single entry plus a per-jurisdiction `confidence` rating and `reclaim_difficulty` field this markdown table compresses into prose. Load it at BUILD Stage 4 wherever withholding or after-tax total return matters for a non-US, dividend-paying candidate, and respect `verify_before_use` literally — it is not decorative, re-check the current rate before it drives a decision, never treat a cached figure as settled. Its `_meta.not_covered_by_source` block also names jurisdictions with NO entry at all (several exchanges present in `exchange-currency-map.json` have no withholding-rate row here) — do not infer a 0% or any other default rate for an uncovered jurisdiction from its absence.

| Jurisdiction | Statutory | Treaty (US portfolio) | Note |
|---|---|---|---|
| UK | 0% | 0% | Structural outlier, no withholding to reclaim at all. |
| Japan | ~15.315% | 10% (portfolio) / 5% (≥10%) | Relief-at-source reasonably well supported by major custodians. |
| Canada | 25% | 15% | Relief-at-source reasonably well supported. |
| Germany | ~26.375% | 15% (portfolio) / 5% (≥10%) | ~11-pt gap needs active reclaim (Steuerbescheinigung); free via German broker, costly otherwise. |
| France | 25% (verify current PFU rate) | ~15% | Reclaim via country-specific forms through the custodian; real friction. |
| Switzerland | 35% (one of the highest developed-market rates) | 15% (portfolio) / 5% (≥10%) | ~20-pt gap, document-heavy reclaim (apostille, multi-language forms) — textbook worst-case reclaim jurisdiction absent relief-at-source. |
| Australia | ~30% unfranked / N/A franked | 15% unfranked | **Franking credits mean headline yield ≠ after-tax-yield proxy.** Franked-portion dividends carry NO withholding at all; franking credits themselves are not usable by foreign holders. Must know franked/unfranked status per distribution, not per company. |
| Taiwan | ~21% for non-resident individuals (verify current rate) | **NONE — no US tax treaty exists** | Structural, not administrative, gap. Worse position than Japan/Korea/Australia despite being lumped into "developed APAC." Flag explicitly whenever a Taiwanese candidate appears. |
| South Korea | higher absent treaty | ~10-15% depending on instrument | — |
| China (mainland) | — | 10% (1984 treaty) | Effective rate varies materially by access route (QFII/Stock Connect/direct H-share/ADR) — verify per instrument, don't blend. |

Reclaim difficulty is a portfolio-construction cost, not an admin footnote: whether the statutory-to-treaty gap is ever captured depends on the custodian's relief-at-source capability. **Model expected total return net of the realistically achievable rate given the actual custody arrangement, not the theoretical treaty rate**, unless relief-at-source is confirmed. Every rate above is Low-Medium confidence on the exact current figure and should be re-verified against current treaty text at build time — do not harden into a constant, particularly France's PFU rate and Taiwan's exact statutory percentage.

## 8. Fiscal-year misalignment

Not all FY-ends are December: Apple (~Sept), most Japanese majors (March 31 — the Japanese default, not an exception), UK retailers (late Jan/early Feb to capture the holiday season). A raw "FY figure" compared across two different FY-ends compares non-overlapping real time windows. **Normalize to TTM** (`latest annual + current YTD interim − prior-year YTD interim`) as the default — lower-maintenance and more robust to seasonality than calendarization (interpolating onto a common calendar year), which is analyst-grade manual work, not worth automating for a 5-10 name book. TTM still inherits the Section 5 staleness gap — a March-FY, semi-annual Japanese name and a Dec-FY, quarterly US name will have different effective as-of freshness even after TTM normalization. A company that changes FY-end mid-history produces a stub period (≠12 months) — exclude or annualize it explicitly before it silently distorts a growth-rate or margin trend.

## 9. Concrete rules + failure modes

1. Read `quote.currency` fresh for every candidate, every run — never assume from suffix alone.
2. Divide by 100 whenever a currency code ends in a lowercase letter (`GBp` confirmed live; `ZAc`/`ILa` by documented convention, not independently re-verified).
3. Read `financialData.financialCurrency` separately, always — 24% of a 21-name sample differed from `quote.currency`. Label every monetary figure with the currency it actually carries.
4. Never trust a bare ticker as a cross-source (Yahoo↔IBKR) key — resolve by company name + exchange, run the 2%-tolerance price safety gate before any order instruction, stop on failure.
5. Treat empty statement-history modules as "no data," not a retry-able error.
6. Do not call `fundamentalsTimeSeries` until its `option type invalid` failure is root-caused.
7. Pass `{ validateResult: false }` to `yf.search()` on the pinned 3.14.0.
8. Pre-flight FinancialFilings (`filing_categories_list`) and fall through silently on 403 — never surface it as a user-facing error, never block on it.
9. Flag J-GAAP-vs-IFRS regime per Japanese name before trusting net-income-based multiples.
10. Flag Taiwan explicitly whenever it appears — no-treaty is structural, not a reclaim-process issue.
11. Never combine a home-market per-share figure with an ADR price without applying the current ratio; re-verify the ratio hasn't changed across a multi-year series.
12. Store an explicit as-of date on every "TTM" label — never a bare tag.
13. When a candidate clears neither Yahoo nor a reachable direct source: drop it and say so.

| Symptom | Detection | Response |
|---|---|---|
| Nonsense P/E or EV/EBITDA for a global name | `quote.currency` ≠ `financialData.financialCurrency` | Relabel each figure with its own currency; never mix numerator/denominator currencies. |
| Price 100x off for an LSE name | `currency` string ends in lowercase letter | Divide by 100; re-run downstream calcs. |
| Statement-history fields present in one run, gone in the next for the same symbol | Module payload empty, no thrown error | Treat as no-data (drop/flag), do not retry, do not assume Section-1 cause without checking the payload directly. |
| Cross-source price mismatch >2% | Reconciliation gate (Sec 2) | Stop pipeline; surface both prices/currencies/IDs; require corrected match or human confirmation — never average or guess. |
| J-GAAP Japanese name looks "lower quality" than IFRS peer | Net margin/ROE unexplained by business fundamentals | Check regime; add back goodwill amortization for comparability if J-GAAP. |
| EU/APAC name's "cheap" multiple traces to stale earnings | TTM as-of date >90 days old | Surface staleness explicitly; do not rank on TTM alone without the as-of date visible. |
| FinancialFilings call hangs or errors | 403 on preflight | Fall through silently to Yahoo-only path; never hard-require. |
