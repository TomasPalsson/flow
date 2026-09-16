# Diff-impact and structural-decay gates (2024-2026): tools, evidence, and how to fit them into flow

## Summary

ImpactGate exists, and its formula, thresholds and exit codes match its README. It is also very young: 38 commits, 13 stars, and three PyPI releases all published on one day. It is worth copying as a design, but not safe to install as a gate. The mature tool that works on diffs the same way is CodeScene Delta Analysis, which is paid. The free tools each cover one piece: lizard, radon, xenon, complexipy and ruff C901 measure complexity; jscpd finds new duplication; code-maat finds churn and hotspots.

flow already runs two of these mechanically. `slop_tools.py` calls ruff C901 as NS-12 and jscpd with `--baseline-from-ref --fail-on-new-clones` as NS-01, and both are advisory. **The first thing to build is a lizard adapter in `slop_tools.py` (new row NS-17) that compares each changed function's complexity before and after. It stays advisory, and the existing `slop` adversary lens confirms or dismisses what it reports.** It needs no new hook, no new G### gate and no stored baseline.

Confidence tags used below: **[V]** re-checked against the primary source (live repo, API, PDF or local file). **[S]** single source, not re-checked. **[X]** contradicted or corrected on re-check.

---

## 1. ImpactGate at source level

| Aspect | Finding | Confidence |
|---|---|---|
| Metric | `impact = files_changed * Σ max(WMC_other,1) * CC * Δlines` over changed functions. WMC_other is the complexity already in the container being edited, measured before the change. Adding to a heavy class costs a lot; a brand-new file or class costs little. [github.com/officefloor/ImpactGate](https://github.com/officefloor/ImpactGate) | [V] verbatim in README, checked by 4 independent passes |
| Thresholds | Warn at 50,000, block at 200,000. Enforcement is `off`, `warn` or `block`. Configured in `.impact-gate.yml` or with CLI flags. Files over `max_diff_lines` (200,000) are listed as "skipped" instead of being scored. | [V] |
| Modes | `staged` (the pre-commit default), `worktree`, and `range` (merge-base..HEAD, for CI). | [V] |
| Exit codes | 0 = ok or warn, 1 = usage or environment error, 2 = blocked. | [V] |
| Baseline | Blends a seed prior (per-language percentile tables from a 20-repo corpus) with the project's own merged-history distribution, weighted w = n/(n+K), K=200 by default. `impact-gate baseline` writes `.impact-gate-baseline.json`. A new repo is graded almost entirely against the seed tables until it has about 200 merged changes. | [V] K and blend. [S] baseline file name |
| Output and CI | `--format json`, text and markdown. GitHub Actions composite action with a job summary and a sticky PR comment. GitLab sticky MR note, Jenkins snippet, pre-commit framework, `install-hook`, ghcr.io Docker image, `pip install impact-gate`. | [V] |
| Parser and languages | The README does not name them. `pyproject.toml` reportedly says "lizard is the only runtime dependency (multi-language CC + line ranges)" and notes a lizard 1.24.0 Java-annotation bug. So language support is whatever lizard supports. Which languages have seed tables is not documented. | [S] one checker read pyproject; the README-only research missed it [X] |
| JSON schema | Not documented beyond `--format json` existing. | Gap |
| Maturity | Apache-2.0, 38 commits, 0 forks, 0 open issues. Stars were 11 when researched and 13–14 on re-check. There are 8 merged PRs dated 2026-08-26 to 08-31, so the claim "0 PRs" is wrong. PyPI 0.1.0, 0.2.0 and 0.3.0 were all released 2026-09-13, marked Beta, Python 3.10–3.13. | [V] counts, [X] "0 PRs", [S] PyPI dates. The repo predates PyPI by about 3 weeks, so "3 days old" applies only to the package |
| Reception | [HN item 49726329](https://news.ycombinator.com/item?id=49726329), framed as "a merge gate that scores the structural decay AI adds". Commenters liked the idea, but some doubted a project that reads as AI-generated. No one reported false-positive rates. | [V] thread exists |
| False positives: new code vs edits | No measured false-positive data has been published. **By construction the formula favours new files over edits.** An agent that puts logic in a new module scores low even when it duplicates existing code, and that directly contradicts flow's Ruling that reuse is zero-tolerance (PROGRESS.md:37). Because `files_changed` multiplies everything, one cross-cutting rename or a small fix touching many files scores high. | Inference from the formula, not measured |

## 2. Peer tools that gate on diff complexity or decay

| Tool | Measures | Diff-aware? | License / cost | CLI / JSON | Languages | Confidence |
|---|---|---|---|---|---|---|
| CodeScene Delta Analysis | Code Health (1–10, built from smells), how much health drops in this PR, complexity trend inside hotspots, and co-changes that should have happened but didn't | Yes, by design | Commercial, per seat | REST API and PR integration | Many | [V] docs across versions 3.x–6.6.16 ([docs](https://docs.enterprise.codescene.io/versions/6.6.16/guides/delta/automated-delta-analyses.html)) |
| SonarQube new-code gate | Complexity, duplication and issues on new code, measured against a baseline (previous version, N days, or a reference branch). Duplication conditions are skipped until there are at least 20 new lines. 2025.1 "Sonar way" requires 0 new issues. | Yes | Commercial; Community edition is limited | Server | Many | [S] ([docs](https://docs.sonarsource.com/sonarqube-server/2025.1/user-guide/about-new-code)) |
| radon | Cyclomatic complexity, maintainability index, Halstead metrics. Reporting only. | No | MIT | JSON | Python | [S] |
| xenon | CI pass/fail on radon ranks (`--max-absolute B`, etc.) | No; absolute thresholds | MIT | exit code | Python | [S] |
| wily | Complexity trend across git history | By history, not per diff | Apache-2.0 | CLI | Python | [S], not researched in depth |
| lizard | Cyclomatic complexity, function length and parameter count; copy-paste detection | No, but it is the engine ImpactGate uses | MIT | CSV/XML | 15+ languages | [S] |
| complexipy | Cognitive complexity (Sonar-style), written in Rust | No | MIT | CLI/JSON | Python | [S] 5.5.0 released May 2026, 4.8M downloads ([repo](https://github.com/rohaquinlop/complexipy)) |
| Code Climate → Qlty | Code Climate Quality shut down 2025-07-18. Qlty is a free CLI running 70+ linters plus a maintainability score. | Wraps per-file scores | Free CLI (FSL/BUSL-style; license not verified) | CLI | 40+ languages | [S] ([qlty](https://github.com/qltysh/qlty)) |
| code-maat | Churn, hotspots (complexity × churn), temporal coupling, code age | No, reads repo history | GPL-3.0 | CSV | Language-agnostic | [S] ([repo](https://github.com/adamtornhill/code-maat)) |
| diffgate (srbsa) | Grades each changed line green/yellow/orange for how much review it needs; AST-based for about 9 languages; exposes an MCP tool | Yes | Apache-2.0; 5 stars, 122 commits | MCP, CLI, VS Code | JS/TS, Py, PHP, Go, Ruby, Java, C#, Kotlin | [S] not re-verified ([repo](https://github.com/srbsa/diffgate)) |
| diff-cover | Test coverage on changed lines only; not a complexity tool | Yes | Apache-2.0 | JSON/HTML | Any coverage XML | Not researched; known pattern only |
| fallow | **Not covered by any research angle.** | — | — | — | — | Gap |

## 3. Architecture drift and duplication gates

| Tool | What it enforces | Diff-aware usage | Confidence |
|---|---|---|---|
| jscpd | Copy-paste clones | `--baseline-from-ref <ref> --fail-on-new-clones` fails only on new clones. flow already calls exactly these flags and falls back when the installed jscpd rejects them (`slop_tools.py:106-109`). Community actions (e.g. getunlatch/pull-requests-jscpd) add PR comments. Research also cites jscpd issue #1018 as a roadmap item for diff-awareness, which is at least partly out of date given the shipped flags. | [V] local code. [S] exact version (5.1.0) and CI docs ([jscpd.dev](https://jscpd.dev/ci-and-hooks/ci)) |
| dependency-cruiser | JS/TS dependency rules | Not a graph diff. PRs are scoped with changed-file globs, or MH4GF/dependency-cruiser-report-action reports only changed files. | [S] ([action](https://github.com/MH4GF/dependency-cruiser-report-action), [xebia](https://xebia.com/blog/taking-frontend-architecture-serious-with-dependency-cruiser/)) |
| import-linter | Python layer, independence and forbidden-import contracts | Whole tree, fast (about 1s) | [S] ([docs](https://import-linter.readthedocs.io/)) |
| ArchUnit / ArchUnitTS | Architecture rules written as unit tests | A "freeze" baseline allows existing violations and can only shrink, a one-way ratchet | [S] ([repo](https://github.com/TNG/archUnit)) |
| deptrac, madge, pytestarch | PHP layers, JS circular dependencies, Python architecture tests | No source found showing diff-scoped use | [S] searched, nothing found |

All of these need contracts written by hand for each project. They solve a different problem from complexity growth. Where flow wants them, they belong as `G###` gates a project opts into, and that mechanism already exists.

## 4. Evidence

**Metrics that predict defects or review effort**
- WMC and the other CK metrics correlate with fault-proneness (Basili et al. 1996, cited in a [2023 survey](https://www.researchgate.net/publication/370761578_The_Relationship_between_Code_Complexity_and_Software_Quality_An_Empirical_Study)). [S] Established result.
- Churn relative to component size predicts defect density ([Nagappan & Ball, ICSE 2005](https://www.microsoft.com/en-us/research/wp-content/uploads/2016/02/icse05churn.pdf)). Large, recent changes are disproportionately risky (Graves et al.). [S] Established result. This is the basis for weighting by Δlines and files_changed.
- Models using complexity, patch size and developer experience predict review effort at AUC 0.84–0.88 ([arXiv 2404.10703](https://arxiv.org/html/2404.10703v2)). [S]
- Cloned code is linked to 15–50% more defects ([devclass summary of GitClear](https://www.devclass.com/ai-ml/2025/02/20/ai-is-eroding-code-quality-states-new-in-depth-report/1626250)). [S] Secondary source.

**Growth in AI-agent code**
- GitClear 2025, 211M lines from 2020–2024: copy/pasted share rose from 8.3% to 12.3%; moved (refactored) code fell from 24.1% to 9.5%; 2024 was the first year copy/paste exceeded moved code; commits containing duplicated blocks of 5+ lines rose about 8x ([GitClear](https://www.gitclear.com/ai_assistant_code_quality_2025_research)). [V] The "8x" applies specifically to 5+ line duplicate blocks.
- Churn rose from about 3.3% before AI to 5.7–7.1% ([GitClear 2026 "Maintainability Gap"](https://www.gitclear.com/the_ai_code_quality_maintainability_gap)). [V] report exists, 623M changes 2023–2026. [S] exact churn figures.
- CodeScene whitepaper, January 2026 (v2 March 2026): AI velocity gains are "fully cancelled out after just two months" by rising complexity ([PDF](https://codescene.com/hubfs/whitepapers/AI-Ready-Code-How-Code-Health-Determines-AI-Performance.pdf)). [V] quote. **[X] Struck:** the "75% of tech leaders" statistic and the list of four named smells do not appear in this PDF.
- SlopCodeBench ([arXiv 2603.24755](https://arxiv.org/pdf/2603.24755), March 2026): verbosity rises in 89.8% of agent trajectories and structural erosion in 80%; correctness alone is not enough. [V] **[X] Corrected:** the benchmark has 20 problems and 93 checkpoints across 11 models, not 36 and 196.

**What actually correlates:** churn, change size, duplication, and complexity in code that is already complex (hotspots). A single composite score has no published validation. That includes ImpactGate, which has no published data on how well it predicts defects.

**Risk that the agent games the metric:** in flow the agent sees the score. `build-slices.js:169` tells the developer to run `slop-check` before reporting done, so the agent optimises against whatever the check reports. Documented dodges ([keypup](https://www.keypup.io/blog/goodharts-law-in-action-why-your-dev-metrics-are-being-gamed-and-how-to-fix-it/), [S]):
- splitting functions to get under complexity thresholds
- copy-pasting instead of editing a flagged function
- for ImpactGate specifically, creating new files instead of editing existing ones

The defences are checks that pull against each other plus a judge that reads the code. flow already has both: jscpd NS-01 punishes the copy-paste dodge, and the `slop` lens with its reuse rule punishes the new-file dodge.

## 5. Integration into flow: the real seams

All of the following was checked locally [V]:

- **Ruling (PROGRESS.md:36):** mechanical slop checks are advisory; only the `slop` lens with a receipt can block. `slop-check` returns 1 only under `--strict` (`skills/no-slop/scripts/slop-check:351`). The Ruling does not mention diff-impact scoring. Applying it here is this report's argument, not something the repo already says [X on claim 11 framing]. The argument is strong, though: same kind of risk, and no measured false-positive rate.
- **Ruling (PROGRESS.md:38):** a loop exits on a verifier the harness runs. Any blocking impact check would therefore have to be an exit-code command, never a model's judgment.
- **Ruling (PROGRESS.md:37):** reuse of an existing helper is zero-tolerance. ImpactGate's formula pulls the other way (see §1).
- **`skills/no-slop/scripts/slop_tools.py`:** already holds adapters for ruff (C901, PLR0913 and PLR0915 map to NS-12 at line 56), tsc, and jscpd (NS-01). All of them only report on added lines and are skipped silently when the tool is missing.
- **`hooks/size_guard.py`:** uses `--baseline` pre-edit content and reports only what this edit introduced (lines 16-22). NS-17 should follow the same rule.
- **`hooks/hooks.json`:** runs only per-edit PostToolUse checks (format-lint, size-guard, tamper-notice) and Stop checks (stop-gate, loop-gate). No hook looks at the diff across multiple files.
- **`skills/no-slop/references/integration-seams.md:15`:** allows an optional hook that calls `slop-check --files` through `hook_note`, never `hook_deny`.
- **`workflows/review-diff.js:56`:** default lenses are `['correctness','security','gaming','cross-file','slop']`.
- **`workflows/build-slices.js:191,225`:** runs the `slop` adversary lens on each slice.
- **`flow-templates/TASKS.md:23-26`:** gates G001 (`flow check --fix`), G002 (a PASS file exists) and G003 (verify/ is not empty). `skills/next/SKILL.md:70` writes `PASS-<HEAD-sha>.md` naming each gate, its command and its exit code; any later commit makes it stale.

**Where a diff-impact score fits**

| Question | Answer |
|---|---|
| Advisory or blocking? | Advisory, per Ruling 36, until there is a measured false-positive rate on flow's own history. Blocking only through the `slop` lens with a path:line receipt. |
| Per task or per gate? | Per task or slice, inside `slop-check`, which already runs in build-slices and review-diff. Not a new `G###` gate: a gate is pass/fail, and an advisory number would make G-lines mean something different. |
| Hook? | No. Per-edit hooks cannot see a diff across multiple files, and a Stop hook runs on every turn, which costs too much. |
| Baseline storage? | Not needed for step 1: the baseline is the base ref (`git show base:file`), the same way size_guard works. A percentile baseline from history (ImpactGate-style) comes only if step 2 is taken. |
| Loop | Leave `flow loop check` and the K-F veto alone. |

## Recommendation table

| Tool | Fit for flow | Effort | Verdict |
|---|---|---|---|
| **lizard** (as a slop_tools adapter) | Multi-language cyclomatic complexity with function line ranges; ImpactGate's own engine [S]; can run via `uvx lizard` | Low: about 1 function and 1 eval case | **Build first (NS-17, advisory)** |
| jscpd `--fail-on-new-clones` | Already NS-01, diff-aware | None | Keep as-is |
| ruff C901 / PLR0915 | Already NS-12; Python only; fires above an absolute threshold, not on growth | None | Keep; NS-17 complements it |
| ImpactGate | Right idea, unproven; the formula rewards new files and clashes with the reuse Ruling; no false-positive data | Low to wire, high to trust (the baseline needs about 200 merges) | Watch; borrow the "piling onto heavy containers" weighting later |
| radon / xenon | Python only, absolute thresholds, overlaps with ruff | Very low | Skip |
| complexipy | Cognitive complexity for Python, actively maintained | Low | Skip for now; revisit if NS-17 turns out noisy on nesting |
| wily / code-maat | History and hotspot ranking, not a check on one diff | Medium | Skip for gating; code-maat is useful for choosing hotspot weights later |
| diffgate | Triage of changed lines plus MCP; immature, not re-verified | Low–Medium | Watch |
| CodeScene Delta | Richest signal available (health drop, hotspots, missing co-changes) | High: paid, external SaaS | Reject as a default; teams can adopt it independently |
| SonarQube new-code | Mature, needs a server | Medium–High | Skip; duplicates the advisory layer |
| Qlty | Runs many linters, scores per file | Medium | Skip |
| dependency-cruiser / import-linter / ArchUnit / deptrac / madge / pytestarch | Architecture drift, a different problem; needs hand-written rules | Medium per project | Out of scope; opt-in `G###` per project |
| diff-cover | Coverage, not decay | Low | Out of scope |

## Smallest integration to build first

Add `run_lizard(toplevel, base, files, added)` to `/Users/tomas/Desktop/Projects/flow/plugins/flow/skills/no-slop/scripts/slop_tools.py`, following the pattern of `run_ruff` and `run_jscpd`:

1. **Run lizard on both versions.** For each changed file, run `uvx lizard` on the HEAD file and on `git show <base>:<file>`, written to a temp file; an empty string means a new file. If lizard is missing, skip silently.
2. **Match functions.** Pair functions by name and keep only those whose line range overlaps `added`.
3. **Report only regressions**, using size_guard's rule. Emit `NS-17` when a function's cyclomatic complexity crosses the existing limit, or when it grows while already over the limit. Put `CC before→after, Δlines` in the message.
   - Reuse the ruff C901 limit if one is already set. Do not add a new config value or flag.
   - A function left alone, or one whose complexity went down, stays silent.
4. **Add the NS-17 row.** Add it to the `slop-check` JSON output and to the rubric in `skills/no-slop/SKILL.md`, plus one eval case under `plugins/flow/evals/` (a quality-* case, per the integration-seams convention).
   - Exit code stays 0; only `--strict` returns 1.
   - The existing `slop` lens in `build-slices.js` and `review-diff.js` confirms or dismisses the finding with a receipt. That is the only way it can block.

**Acceptance check:** `slop-check --json` flags a fixture where an existing CC-9 function grows to CC-12, and stays silent on:
- a new CC-4 function
- an untouched CC-15 function
- a function that shrank

The exit code is 0 in every case.

**Skipped, and when to add it:**
- An ImpactGate-style aggregate score and a percentile baseline: add once NS-17 has run on about 30 merged flow features and its false-positive rate has been measured and recorded as a Ruling.
- A `G###` gate or a hook: add only if that measured rate justifies overriding Ruling 36.