---
name: no-slop-evidence
description: The claims register behind the no-slop skill — each rule's sources, whether they are independent, and how much weight the rule may carry. Load when a rule is challenged, when tuning a threshold, or when writing an eval that cites a number.
---

# Evidence register

Verdicts: CORROBORATED = two or more sources that did not copy each other; SINGLE = one source; CONTESTED = sources disagree. Research workspace: `.skill-forge/no-slop/` (waves 1 to 3, 2026-09-12).

| # | Claim the skill relies on | Sources | Verdict | Weight |
|---|---|---|---|---|
| 1 | AI-era code duplicates more and refactors less: copy/paste share 8.3% → 12.3% (2020 to 2024), refactor share 25% → under 10%, block duplication +81% (2023 to 2026 YTD), error-masking constructs +47% | GitClear 2025 and 2026 reports, fetched from gitclear.com | SINGLE (one vendor's longitudinal data), PRIMARY | Cite as GitClear's number, not an industry consensus |
| 2 | AI co-authored PRs carry about 1.7x more review issues; error-handling gaps about 2x; naming about 2x; formatting 2.66x | CodeRabbit, 470 OSS PRs | SINGLE, vendor | Direction only |
| 3 | Comment density and restating comments are the strongest stylometric tell of LLM code | arXiv 2506.17323 (attribution); arXiv 2607.01867 (comment content) | CORROBORATED | Rule NS-23 |
| 4 | Guards on impossible states are a named LLM failure | CodeRabbit; two practitioner catalogs; Anthropic's own "Defensive coding" countermeasure text | CORROBORATED across vendor, practitioner and model-vendor | Rule NS-22 |
| 5 | Unrequested features are named in maintainer policies and in both vendors' prompts | arXiv 2609.07542 quoting Docusaurus and Flink; Anthropic "Scope"; OpenAI Codex "Do not attempt to fix unrelated bugs" | CORROBORATED | Rule NS-24 |
| 6 | No tool reliably catches semantic (Type-4) reinvention; detectors lose 9 to 43% F1 under rewrites | arXiv 2606.25272 | SINGLE, PRIMARY | Justifies search-before-write as the mitigation |
| 7 | Search-before-write is the convergent practitioner mitigation | four independent practitioner sources; no named methodology | CORROBORATED (practice), unmeasured in literature | Measured here instead: 0/3 → 3/3 (claim 20) |
| 8 | Token clone detectors catch Type-1 (and Type-2 only with identifier normalisation); AST similarity tools reach Type-3 | tool documentation; toolbench measurement | CORROBORATED, with a correction: jscpd needs `--ignore-identifiers`; similarity-ts/py 0.5.0 compare within one file only | NS-01 uses jscpd with the flag and a baseline ref |
| 9 | Same-model self-review silently endorses its own drift: 31.7% (83/262), per-model 0 to 100% | arXiv 2605.21537; general unreliability also in arXiv 2608.18167 and 2604.19049 | CORROBORATED (general), SINGLE (number) | Adversary is a separate pass with its own evidence |
| 10 | Adversarial review must be evidence-gated; unanimous reviewer consensus was wrong once and one empirical test caught it | arXiv 2604.19049; Anthropic `code-review` command: "If you are not certain an issue is real, do not flag it" | CORROBORATED (academic + shipped vendor prompt) | Lens evidence rule |
| 11 | Purpose-built test-weakening detectors self-report about a third false positives | checkwash PyPI: 22 of 60 (36.7%) | SINGLE, self-reported alpha tool | Mechanical layer is advisory |
| 12 | Coverage does not track fault detection in LLM tests; mutation score does | arXiv 2606.08588; arXiv 2506.02954 | CORROBORATED | NS-26, NS-28; mutation testing as the oracle when Bash is available |
| 13 | LLM test oracles capture actual, not expected, behaviour (accuracy under 50%) | arXiv 2410.21136; obra/superpowers TDD doctrine independently | CORROBORATED | Red must be a real gate (NS-28) |
| 14 | Anthropic's over-engineering block is vendor text for Opus 4.5 and 4.6, section "Overeagerness" | platform.claude.com prompting best practices, fetched raw | PRIMARY | Pasted verbatim in the developer block |
| 15 | "Three similar lines beat a premature abstraction" / Rule of Three | leaked Claude Code prompt (unverified provenance); this repo's audit doctrine citing Sandi Metz | CORROBORATED, one leg unverified | Attribute to Rule of Three, not to Claude Code |
| 16 | Function-length evidence is contradictory (one study: LLM functions average under 19 lines) | slop-signatures.md open question | SINGLE | Keep the 60-line guard; target padding |
| 17 | Clean repos cut Claude Code tokens 7 to 8% and file revisits 34%, pass rate unchanged (660 trials) | arXiv 2605.20049 | SINGLE, controlled | Cost argument for cleanliness |
| 18 | Process discipline: +41% process score, +17% outcome correctness | RigorBench, arXiv 2606.22678 | SINGLE | Supporting only |
| 19 | File-scoped linters re-report legacy violations; dead-code tools are whole-repo | eslint-plugin-diff exists for this; vulture/knip/staticcheck docs | CORROBORATED | Script scopes to added lines; dead-code left to the project linter |
| 20 | Search instruction changes behaviour: Anthropic block alone 0/3 on a reuse case, block + search step 3/3; S2 (minimal method) and S3 (comments) passed at baseline | this workspace, `wave-2/exp-plugin`, 12 cases × 3 runs, $2.17 | SINGLE, measured here | The developer block keeps the search step; re-measure per model |
| 21 | Vendors disagree on comments: Codex "do not add inline comments unless explicitly requested"; Anthropic "only where the logic isn't self-evident"; Claude Code "default none, one short WHY line" | openai/codex repo prompts; platform.claude.com; leak mirror | CORROBORATED as a disagreement | Skill adopts the Anthropic position |
| 22 | DORA 2024/2025 stability figures | secondary blogs only; primary page is a JS shell | UNVERIFIED | Not cited |

## Corrections carried from wave 2 and 3

- `code-simplifier` and `comment-analyzer` live in `anthropics/claude-code`, plugin `pr-review-toolkit`.
- Anthropic's section is titled "Overeagerness" and names Opus 4.5 and 4.6.
- `security-guidance` is three layers (regex patterns, Stop-hook LLM diff review, commit-time agent), not one hook.
- The Codex prompt is in the official `openai/codex` repo; no leak needed.
- Duplication is GitClear's finding alone; CodeRabbit's top categories are error handling, naming, formatting.
