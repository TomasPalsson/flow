# /design:diagram: diagram-design merged with graphics, plus AWS (2026-10-19)

## What shipped (design 0.8.0)

- `plugins/design/skills/diagram/`: [cathrynlavery/diagram-design](https://github.com/cathrynlavery/diagram-design) v2.6 (MIT, `LICENSE-diagram-design`) vendored: all 61 references, the templates, the 69 light `example-<type>.html` files, the stdlib scripts (`self_check.py`, `verify-geometry.py`, the draw.io / Mermaid / Excalidraw extractors, `export_svg.py`, `export_png.py`). Upstream's dark/full/animated examples (≈3 MB) and its doctor were left out.
- Our layer, in `SKILL.md`: the graphics priority order (reader's job, then the request, then the look); a **request ledger** (every requested step, decision, actor and parameter becomes its own element; "deletion first" only cuts our additions); skin resolution from a caller's brief, a profile, or the repo's own tokens before asking; a rendered **readability floor** (names ≥13px, other text ≥11px on screen); **short routes**; a **phone rule** (flows get a portrait twin, wide figures scroll from the entry point); a "Read as a list" text equivalent; render-and-look plus a critic subagent.
- **AWS mode**: `references/aws.md` (group boxes in AWS colours, placement rules, icon sizes, numbered steps) and `scripts/aws-icon.mjs` (809 official AWS Architecture Icons 01/30/2026 from the `aws-icons@3.3.0` npm package via jsDelivr, cached under `~/.cache/design-diagram/`; nicknames like `lambda`, `apigw`, `vpc`; `AWS_ICONS_DIR` for offline). 5 tests in `aws-icon.test.mjs`.
- `graphics` now sends schematic diagrams to `design:diagram`; drawn cutaways and maps stay in graphics.

## Bench

8 cases (4 AWS: serverless shop, VPC across two AZs, Bedrock RAG, Kinesis clickstream; 4 general: OAuth PKCE sequence, order state machine, incident flowchart, Mermaid redraw). Three arms, each built headless by Opus 5.5 with only that plugin loaded and no CLAUDE.md or memory: **new** (`/design:diagram`), **old** (`/design:graphics` from design 0.7.0), **upstream** (`/diagram-design:diagram-design`). Each output was rendered at 1440px and 390px, machine-checked (text overlaps, clipping, `self_check.py`, `verify-geometry.py`), then judged blind by Opus (A/B/C shuffled) on fidelity, clarity, hygiene, polish, and for the AWS cases also AWS conventions. Old and upstream were built once (round 1) and re-judged each round. Harness: `raw/26-diagram-bench/`.

| Round | Change | new | old | upstream | new best in |
|---|---|---|---|---|---|
| 1 | merge + AWS mode | 7.96 (min 7.25) | 7.79 | 7.07 | 4/8 (all AWS) |
| 2 | request ledger, readability floor, short routes, text list | 8.48 (min 7.88) | 7.80 | 6.80 | 7/8 |
| 3 | phone rule, AWS feature-icon fallback | 8.42 (min 8.00) | 7.66 | 6.67 | 6/8 |

- **AWS** (round 3): new 8.70 / 8.84 / 8.10 / 8.20; old 6.8–7.2; upstream 5.6–6.5. Judges' AWS-convention sub-score: new 8.5–9, old 1.5–5.5, upstream 1–2.5.
- **General**: round 1 lost all 4 to old (folded the SEV decision into a note, 14-character caps labels in the sequence, 8px type, loop routes). After round 2 it won 3/4. Round 3 lost the flowchart narrowly (8.50 vs 8.88) and the Mermaid redraw (8.00 vs 8.25), which it won in round 2 (8.75), so that case is noise-sized.
- Machine checks in round 3: new had 0 clipped text, `self_check` and geometry clean on 8/8, and 1 overlapping text pair (state-order). In round 1, old had 13 overlapping pairs and 1 `self_check` failure.
- Cost: about $64 of builds over 40 Opus builds (≈$1.6 each), plus 24 judge runs.

## Lessons

- Upstream's "deletion first" plus the 9-node budget silently drops what the user asked for. Pairing deletion with a request ledger fixed fidelity without losing restraint.
- Upstream's type ramp (8px arrow labels) is authored size. Measured at render size it was unreadable; the floor has to be stated in rendered pixels.
- Bench pitfall: a work dir under `~/.claude` makes Write a "sensitive file" in headless runs, so a builder falls back to shared `/tmp` scratch, where parallel runs collide. Keep bench trees in a unique `/tmp` dir and tell builders to keep their scratch files local.
- One run per arm per round. The ±0.5 swings per case (mermaid 8.75 → 8.00 with no relevant edit) are noise; the means and the AWS gap held across rounds.

## Open

- More cases outside the 8 (ER, Gantt, data charts) and `--runs 3` before trusting per-case differences.
- `smoothbrain` still draws its own diagrams; it could call `design:diagram` for schematic ones.

## Round 4: skins instead of one house look (2026-10-19, later)

The user found every diagram recognisable as the same tool (grey dotted paper, Instrument Serif title, letter-spaced mono caps eyebrow naming the diagram type, burnt-tangerine accent, type tags, `LEGEND` / `READ AS A LIST` in spaced caps, pale grey-on-grey boxes). Change: `data/skins.json` holds 10 skins (8 light, 2 dark), each with fonts, roles, a larger type ramp (names ≥15px), stroke width, corner radius, arrowhead, zone and focal treatment. Graphics' `pick-style.mjs` deals them: new `--data` and `--sticky` flags, so a project keeps one look and other projects get others. `--mood light|dark` filters by theme. SKILL.md bans the house tells in every skin. `skins.test.mjs` checks contrast (all text roles ≥4.5:1), sizes, and that no skin reuses upstream fonts or accent.

- Quality (blind, same rubric): new **8.42** (min 7.60, best 6/8), old 7.75, upstream 6.75. Unchanged from round 3 (8.42).
- Same-template judge over the 8 new-arm renders, round 3 vs round 4 shown blind as X/Y: **9 → 3**, clarity **7 → 8**. What still repeats: the title + subtitle block, the legend strip, the "Read as a list" disclosure.
- 7 different skins across 8 builds. 3 came out dark because no mood was passed, which is why `--mood light|dark` is now required (dark skins `avoid: light` and vice versa; tested).
