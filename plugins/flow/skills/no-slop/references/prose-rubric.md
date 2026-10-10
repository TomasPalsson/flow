---
name: no-slop-prose-rubric
description: The PASS/FAIL rubric for AI tells in prose a human reads (PR bodies, reports, docs). Rows with a script detector run under `slop-check --prose`; the rest are lens rows. Load when writing or reviewing a PR body or a doc.
---

# no-slop prose rubric

Scope is one markdown document: a PR body, a final report, a README or a doc page. Fenced code and inline code are never scored. A row PASSES when its condition holds for every sentence; it FAILS on the first counter-example, and the finding carries `path:line`.

Severity is `block` or `advise`, as in [`rubric.md`](rubric.md). The script is always `advise`: a reader's own style and a quoted source can trip any of these patterns, so a person confirms each line.

If following a row makes a sentence worse, fix it another way; the rows serve the reader, not the other way round.

Style is not scored. Long dashes and colons are the author's choice and have no row here. The rows below cover substance (is the claim backed) and the few phrasings that carry no information.

## A. Claims and evidence

Examples count as claims: NP-13 covers a made-up case, number or sample that the reader could take for real.

| ID | PASS condition | Detector | Severity | False-positive guard |
|---|---|---|---|---|
| NP-01 | Each factual claim says measured, inferred, or guess, or carries the command or `path:line` that shows it, in the same sentence. A prediction or an unseen cause is a guess. | lens | block | A claim that restates the task or a quoted requirement needs no label. |
| NP-02 | Each count or size claim ("12 files", "3 callers", "40% faster") carries the command that regenerates it. | lens | block | A number copied from a tool's output pasted right above it already has its command. |
| NP-03 | Every link, citation or transcript reference points at something produced or read this session. | lens (open each link or path) | block | A link to the repo's own docs found by search this session passes. |
| NP-09 | A sentence that pairs a perf number (N%, Nx, N ms/s, req/s, p50/p95/p99) with a comparison (faster, slower, reduced, "from X to Y", `->`) also names a run count (runs, median, n=) or an inline command. Otherwise run `benchmark-checklist` and fix the claim before `gh pr create` | `slop-check --prose` | advise | A number with no comparison ("timeout set to 500 ms") passes. Fenced code is never scored. |
| NP-10 | A feeling is replaced by the mechanism or a number, and no sentence could sit unchanged in another project's docs | lens | advise | A sentence that frames a decision the reader must make is content. |
| NP-11 | A doc edit does not reword a sentence whose meaning did not change | lens (reads the diff) | advise | A rewording that fixes an error or a term the rest of the edit renames passes. |
| NP-13 | Every example, sample value or case in the doc comes from the repo, this session or the user. Where none exists, the doc says what is missing or cuts the section. | lens | block | An example labelled hypothetical or "sample data" passes. |

## B. Phrasing that carries nothing

| ID | PASS condition | Detector | Severity | False-positive guard |
|---|---|---|---|---|
| NP-04 | No word from the AI-tell list: additionally, crucial, delve, enduring, enhance, fostering, garner, interplay, intricate, landscape, pivotal, showcase, tapestry, testament, underscore, vibrant, utilize, leverage, facilitate, plus "serves as" and "stands as". Say "is", "use", "help", or the concrete word. | `slop-check --prose` | advise | Quoted text, a product or API name, and the word as the subject of discussion ("leverage" in finance) pass. |
| NP-05 | No sentence stacks two hedges ("might possibly", "could potentially", "may perhaps"). One hedge, or the measured number. | `slop-check --prose` | advise | A hedge paired with its evidence ("probably a cache miss; the trace shows 3 cold reads") is one hedge per claim, not a stack. |
| NP-06 | No "not just X, but Y" or "it is not X, it is Y" reflex. State Y. | `slop-check --prose` | advise | A real contrast the reader needs ("the flag is not a timeout, it is a retry count" when the code confuses the two) passes. |
| NP-07 | No throat-clearing opener ("It is important to note that", "It's worth noting", "Certainly!", "Great question") and no summary closer ("In conclusion", "In summary", "To sum up", "I hope this helps", "Let me know if"). Start with the point; stop when it is made. | `slop-check --prose` | advise | A summary in a long report that adds the next step or an open decision is content, not a closer. |
| NP-08 | No sentence over 30 words. Split it, or drop the clause that carries a second idea. | `slop-check --prose` | advise | A sentence that is mostly a list of names or paths, and table rows, pass. |
| NP-12 | No jargon-metaphor noun: substrate (say base or layer), wedge (entry point), flywheel (feedback loop), north star (main goal), growth or strategic "vector" (path, direction) | `slop-check --prose` | advise | Quoted text, a product name (capitalised mid-sentence) and the word as the subject of discussion pass. `ratchet` is flow's own term and is not on the list. |

## What is not slop (do not flag)

- Quoted text, commit messages and error output pasted as evidence.
- Long dashes, colons, bold lead-ins: house style, not substance.
- A repeated term. One word for one thing is the rule; do not vary it to avoid repeating.
- Pre-existing prose in lines the PR did not touch.

## Grader mapping for evals

| Rubric row | Grader type | Target |
|---|---|---|
| NP-04 to NP-09, NP-12 | `regex` `not_contains` on the script's `--json` output, or the tell's own pattern on the file | file |
| NP-01 to NP-03, NP-10, NP-11, NP-13 | `llm` with the row's PASS condition as the criteria, `focus: {source: file, path}` | file |

Credit: adapted from cursor/plugins pstack skills/unslop/SKILL.md @ ccb5507 (MIT).
