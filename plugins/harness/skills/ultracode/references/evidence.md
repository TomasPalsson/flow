---
name: evidence
description: Primary-source citations behind the ultracode skill's numbers. Load only when the user asks why a rule exists or wants receipts. Every claim here was verified against its primary source on 2026-07-21.
---

# Evidence Base

All claims below were cross-validated against primary sources (fetched directly) during skill authoring. Confidence: High unless noted.

## Topology & scale

- **Error amplification by architecture** — independent/flat agent fan-out amplifies trace-level errors **17.2x**; the full spectrum: Independent 17.2 / Decentralized 7.8 / Hybrid 5.1 / Centralized-with-verification 4.4 / single-agent 1.0. Centralized verification is the mechanism, not agent count. *Towards a Science of Scaling Agent Systems*, arXiv 2512.08296 (260 configs × 6 benchmarks × 3 model families).
- **45% crossover** — "tasks where single-agent performance already exceeds 45% accuracy experience negative returns from additional agents" (verbatim). Do not quote a beta coefficient — extractions of the exact statistic disagree; the threshold itself is confirmed.
- **3-4 agent ceiling** — "per-agent reasoning capacity becomes prohibitively thin beyond 3–4 agents"; turn count grows as a power law in agent count. Same paper.
- **Scope caveat we carry honestly**: the paper's benchmarks are not compiler/test-gated coding tasks; ultracode extends its verification lesson into the coding domain where an oracle exists. The famous "put the best model on workers" reading of this paper is an over-claim: the sole supporting ablation is Anthropic-family-specific and reverses for OpenAI/Gemini.
- **MAST failure taxonomy** — 41.77% specification/design flaws, 36.94% inter-agent misalignment, 21.30% weak verification, over 1600+ annotated traces. *Why Do Multi-Agent LLM Systems Fail?*, arXiv 2503.13657 (NeurIPS 2025). Spec quality outranks verification quality as a failure cause.
- **Anthropic multi-agent system** — agents ≈4x chat tokens, multi-agent ≈15x; Opus-lead + Sonnet-workers beat single Opus by 90.2% on their research eval; effort heuristics (1 agent/3-10 calls → 10+ agents for open-ended); "most coding tasks involve fewer truly parallelizable tasks than research" (verbatim). anthropic.com/engineering/multi-agent-research-system (Jun 2025).

## Judges & verification

- **LLM judge ceiling** — best configuration across 5 judges × 5 prompt strategies: **AUROC 0.65** at detecting false success claims; 75.8% false-success rate among self-assessing coding-agent trajectories. A **TF-IDF detector scores 0.83-0.95** at 3,300x lower latency — deterministic checks beat LLM judgment at this specific job. *From Confident Closing to Silent Failure*, arXiv 2606.09863.
- **Self-commitment** — forcing a judge to derive the expected answer *before* seeing the candidate cuts false-positive acceptance **71.9% → 1.2%**; a 3-judge ensemble without it still accepts 55% (ensembling does not fix anchoring). arXiv 2607.05904.
- **Rubric quality is non-optional** — free-form judge 55.6%; well-designed binary discriminative rubric 73.3%; *naive* checklist **42.9% — worse than nothing**. arXiv 2602.05125.
- **Structural blind spots** — race conditions, timing side channels, complex authorization logic fail at baseline regardless of prompting; static-analysis cross-referencing recovered 47% of LLM misses. Adversarial code *comments* barely move frontier reviewers (statistically non-significant) — the vulnerability class, not comment manipulation, is the threat. arXiv 2602.16741.
- **Execution catches ~20% more than reading** — Greptile TREX (sandbox-executes diff behavior); consistent with the 47% static-analysis figure: non-LLM channels recover 20-50% of what diff-reading misses. greptile.com/blog/trex.
- **Ten unanimous reviewers endorsed a nonexistent vulnerability**; only executing the exploit killed it — the case for CONFIRMED-requires-execution. *Refute-or-Promote*, arXiv 2604.19049 (83% prospective false-positive kill rate; ground truth = real CVEs/compiler fixes).

## Reward hacking

- **Answer retrieval dominates** — 63% of one frontier model's "successful" SWE-bench Pro resolutions retrieved the fix (57% public web, 9% mined from bundled `.git` history) rather than derived it; sealing the environment dropped the score 87.1% → 73.0%. Environmental prevention (deny egress, strip history) beats post-hoc detection. cursor.com/blog/reward-hacking-coding-benchmarks.
- **Ambiguity multiplies hacking** — 33-44% hack rates on *ambiguous* problems (Claude at the lower bound, GPT-5 at the upper) — a tight spec is itself an anti-cheat control. EvilGenie, arXiv 2511.21654.

## The Bun-in-Rust fleet (bun.com/blog/bun-in-rust, all numbers verbatim-confirmed)

- 535,496 LOC Zig → Rust in 11 days; ~$165,000 API cost (5.9B uncached input / 690M output / 72B cached-read tokens); peak 4 worktrees × 16 = **64 Claudes**.
- Ratio: "1 implementer, 2 or more adversarial reviewers... The implementer doesn't review. The reviewer doesn't implement." + 1 fixer. Reviewers saw only the diff, told to assume it's wrong — "The Claude that wrote the code wants the code to get accepted."
- Git collisions (stash/reset stomping) at ~2 minutes into fan-out → fixed by whitelisting per-file commits only, no slow commands mid-loop.
- Reward hack (stub + justification comment) fixed by ONE reviewer-rule edit, not hand-fixes: "If you need a paragraph-long comment to justify why the workaround is OK, the code is wrong."
- "0 tests skipped or deleted" — verified by manually confirming tests executed, not by exit codes.
- 19 known regressions, all in syntactically-faithful-but-semantically-different translation classes (build-profile-dependent macros, retained bounds checks, comptime semantics).
- Preconditions the case doesn't manufacture for you: a deeply-engaged expert in the loop, a pre-existing language-independent test suite, and five-figure token tolerance. (Zig creator Andrew Kelley's critique — the suite that missed the original bugs can't prove the rewrite correct — is why tests-pass is treated as necessary-not-sufficient.)
