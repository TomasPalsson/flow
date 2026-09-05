---
name: thin-domain
description: For categories with little cultural material of their own (SRE tooling, invoicing, generic B2B, internal admin). How to derive grounded physical antecedents from the audience's world, write them as probability-tagged candidates, and hand them to roll.mjs --grounded so an external pick lands on the tail instead of the cliché. Load from Step 0 only when the category is thin.
---

# Thin domains: grounded antecedents

Some subjects resist every catalog roll because the world dealt has nothing to hold onto in the product's own culture. The fix is a second source of material: **physical antecedents from the audience's lived world**, picked from the tail of Mr Claude's own list by the script, not by Mr Claude.

## 1. The physical-object method

Ask: *what would this be as a physical artifact, and what did that world look like before the web?* Then:

1. **Name three real antecedents, not one.** The first is the cliché (bank → vault; fitness → gym poster; dashboard → glass cards). The good answer lives at #2 or #3.
2. **Extract a constraint, not a texture.** A ledger is not "beige and lined"; it forces every figure to reconcile in a paired column. A cockpit panel is flush, not floating. A rulebook numbers things because they are cross-referenced. The constraint becomes a layout rule.
3. **Include graphic traditions, not only objects**: the notation, publications, identity programmes, data graphics and interfaces this audience reads daily (a surveyor's field book, a racing programme, a broadcast lower-third, a pharmacy label, a shipping manifest).
4. Reject any antecedent that is the category's standard page or its predictable opposite; spend at most one candidate on the product's own name or metaphor.

Worked examples (condensed):

| Subject | Cliché to skip | Better antecedents | Constraint extracted |
|---|---|---|---|
| SaaS monitoring dashboard | glass KPI cards | control-room gauge panel; ship's bridge cluster; household electricity meter | gauges with tick-marked ranges, flush console grid, colour only for signal state |
| Invoicing tool | fintech blue + gradient button | double-entry ledger; carbon-copy invoice pad; rubber date stamp | hairline-ruled rows, right-aligned tabular amounts, a stub region for totals, stamped status |
| Dev-tool docs | three feature tiles over a sidebar tree | aircraft maintenance manual; board-game rulebook; lab notebook | numbered callouts cross-referenced from prose; flat numbered index instead of a nested tree |
| Fitness app | hero photo + "Start your journey" | boxing-gym chalk round timer; flip-digit scoreboard; coach's logbook | flip-digit counters, a dated ledger spine for history, no progress rings |

## 2. Write the candidates file

Use this wording to yourself, then write the answer as JSON:

> List 5 to 7 real, concrete physical antecedents — objects, places, rituals, printed matter, or graphic traditions — that this surface's actual audience would recognise from their own lived culture, not from this product's category. For each, give a one-line grounding and a probability from 0 to 1 estimating how likely you would be to reach for it if left alone. Give each a genuinely different probability; list them in the order you thought of them, not sorted.

```json
[
  {"name": "ship's bridge instrument cluster", "p": 0.45, "why": "operators watch it for hours; every reading has a range and an alarm state"},
  {"name": "household electricity meter with a rolling counter", "p": 0.15, "why": "one number, mechanically honest, read at a glance"},
  {"name": "1970s NASA mission-control console", "p": 0.30, "why": "dense, monochrome, status lamps; the audience grew up on the imagery"},
  {"name": "railway signal box lever frame", "p": 0.05, "why": "physical interlocks make invalid states impossible"},
  {"name": "hospital patient monitor", "p": 0.05, "why": "waveform + number + alarm colour, nothing decorative"}
]
```

Save it (for example `.vary/candidates.json`; roll.mjs gitignores `.vary/`) and roll:

```bash
node <skill-dir>/scripts/roll.mjs --mode <mode> --platform <p> --grounded .vary/candidates.json --project .
```

The script ranks by `p`, drops the top third (the queue you would have built anyway), and picks from the tail. It prints the pick as **GROUNDED ANTECEDENT** alongside the dealt WORLD.

## 3. Fuse, do not blend

- The **WORLD** supplies the skeleton grammar, motion envelope, type classes and refuse list.
- The **GROUNDED ANTECEDENT** supplies materials, the thesis, the memorable element, and any structural constraint you extracted in §1.
- **Product facts win every conflict**; clarity beats both.
- If the dealt world genuinely cannot carry the antecedent's constraint (a poster world for a reconciling-ledger constraint), that is a named factual ground: `--from <key> --reroll 1` once, keeping the same candidates file. Do not swap the antecedent for your #1 candidate: that is the argmax coming back through the side door.
- Discard the rest of the candidates list from the contract entirely; carrying a losing branch forward invites re-litigating a closed decision.

Then continue at SKILL.md Step 2.
