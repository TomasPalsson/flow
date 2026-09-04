# Skill Surface Audit — `~/.claude/skills`

Path is a symlink → `~/.dotfiles/claude/.claude/skills`. Audit is read-only; nothing under that path was modified.

Scope note up front: this audit covers only the 66 skill directories that actually live at that path (`flow-feature` is a symlink to `feature`, not a distinct skill, and `shared/` has no `SKILL.md` — it's a reference bundle other skills load, not a skill itself). Several names the user's cluster hypothesis mentioned — `speckit.*`, `orchestrate`, `code-review`, `simplify`, `test` — are **not** in this directory. `speckit.*` are 9 slash-commands living in the sibling `~/.dotfiles/.claude/commands/` directory (a different mechanism entirely); `orchestrate`, `code-review`, `simplify`, `test` are plugin/built-in skills injected by the harness, not files in this repo. Both are noted where relevant below but are out of scope for the line-count and dead-reference sections.

---

## 1. Skill inventory

| Skill | SKILL.md lines | Total incl. references (md/txt) | First sentence of description |
|---|---:|---:|---|
| agent-architecture | 175 | 659 | Architecture and token-economics for Claude agents: workflow vs agent vs multi-agent selection; subagent count; tool & MCP design; prompt caching; model routing; context-window blowup; AgentCore Runtime/Memory/Gateway/Identity/Code Interpreter/Observability. |
| agent-browser | 750 | 2,247 | Browser automation CLI for AI agents. |
| agent-evals | 140 | 509 | MUST use for evaluating LLM and agent systems — design, build, and operate trustworthy, cost-controlled evals. |
| agui-strands | 189 | 751 | Build or debug generative-UI chat apps on the AG-UI × Strands × Bedrock AgentCore × Vercel AI SDK (useChat) stack. |
| alpha-hunt | 285 | 12,385 | Aggressive weekly stock-HUNTING engine — builds a concentrated 5-15 name conviction book from momentum + catalyst + event-driven signals, sized for maximum return within a long-only, unleveraged eToro agent-portfolio, and hardened by an ultracode-style adversary fleet. |
| api-explorer | 299 | 743 | Reverse-engineer APIs and websites using Chrome DevTools MCP to produce detailed, agent-consumable specifications. |
| audit | 297 | 2,105 | Stage-gated parallel code audit for a whole codebase or module: recon → 6 parallel detection agents → dedup + triage → user approval gate → fix planning → second approval gate → serialized apply → verification. |
| aws-explore | 137 | 724 | Token-efficient AWS resource exploration during debugging. |
| aws-lambda-microvms | 213 | 1,187 | Builds, runs, debugs, and operates applications on AWS Lambda MicroVMs — Firecracker-isolated, snapshot-resumable serverless compute. |
| better-plan | 166 | 994 | Present a plan, design, proposal, or architecture as a polished, interactive, REVIEWABLE page instead of flat markdown. |
| brainstorm | 452 | 452 | Explore a codebase systematically using parallel exploration agents, then generate bold improvement ideas as a single-file interactive HTML site. |
| claude-improver | 236 | 1,081 | Scan a repo with a parallel subagent swarm to find and generate genuinely useful Claude Code improvements. |
| claude-md | 195 | 195 | Generate, audit, and optimize CLAUDE.md files for Claude Code projects. |
| claude-md-improver | 179 | 691 | Audit and improve CLAUDE.md files in repositories. |
| clean-code | 97 | 97 | This skill embodies the principles of "Clean Code" by Robert C. Martin. |
| cocoindex | 511 | 2,582 | Used when building data processing pipelines with CocoIndex, a Python library for incremental data transformation. |
| design | 219 | 1,842 | Five-phase design process that escapes AI-slop defaults. |
| develop-idea | 137 | 452 | Developmental thinking partner that GROWs a raw or half-formed idea — expanding, deepening, surfacing angles not yet considered. |
| etoro | 307 | 307 | Guides agents through creating, retrieving, and trading on behalf of eToro agent-portfolios. |
| explainer | 219 | 1,085 | Create stunning, interactive single-file HTML explainer pages that visually explain code, projects, concepts, or processes. |
| feature | 449 | 1,498 | TDD-first feature development pipeline. |
| figma-to-strapi | 255 | 591 | Convert Figma component designs into Strapi v5 component schemas AND matching React/Next.js components. |
| find-skills | 142 | 142 | Helps users discover and install agent skills. |
| fix | 198 | 337 | Systematic bug fix from triage through regression test and PR. |
| flow | 266 | 601 | End-to-end build pipeline merging flow-spec + flow-feature + flow-deepen into one pass. |
| flow-deepen | 122 | 275 | Closing architecture loop of the build flow — runs AFTER a spec's issues are built and PRs merged. |
| flow-feature | — | — | **Symlink → `feature`** (not a distinct skill). |
| flow-handoff | 95 | 95 | Split work into fresh, focused sessions by writing a small disposable handoff doc. |
| flow-spec | 266 | 1,221 | Forge a detailed, judge-scored specification for spec-driven development from a brief project description. |
| flow-to-issues | 197 | 242 | Turn a forged spec into a dependency-ordered set of tracer-bullet vertical-slice issues, tagged AFK or HITL. |
| gh-cli | 2,187 | 2,187 | GitHub CLI (gh) comprehensive reference for repositories, issues, pull requests, Actions, projects, releases, gists, codespaces, organizations. |
| google-ads | 373 | 985 | Use when working with Google Ads data through the official Google Ads MCP server. |
| grill-me | 10 | 10 | Interview the user relentlessly about a plan or design until reaching shared understanding. |
| grill-with-docs | 88 | 195 | Grilling session that challenges your plan against the existing domain model, sharpens terminology, and updates documentation inline. |
| icelandic-professor | 268 | 659 | Write flawless Icelandic at the level of a university professor. |
| impeccable | 85 | 5,240 | Use when the user wants to design, redesign, shape, critique, audit, polish, clarify, distill, harden, optimize, adapt, animate, colorize, extract, or otherwise improve a frontend interface. |
| investment | 164 | 5,754 | Pick one US large/mid-cap stock for 1-5+ year holding using multi-framework analysis with Beneish fraud veto and Kelly-sized position. |
| mobile-design | 142 | 533 | Mobile-native design for React Native/Expo and iOS/Android — the mobile layer the web /design skill lacks. |
| new-project | 281 | 1,107 | Scaffold a new project from a natural-language description. |
| node-cli-builder | 575 | 1,139 | Build beautiful, production-quality Node.js terminal CLI applications with excellent UX. |
| overkill | 120 | 120 | Maximum-depth research and task execution using massive parallel agent deployment. |
| pentest | 318 | 2,766 | Adversarial security review — find chained exploitable weaknesses before attackers do. |
| polish | 223 | 223 | Performs a final quality pass fixing alignment, spacing, consistency, and micro-detail issues before shipping. |
| portfolio | 385 | 3,181 | Builds and then recurrently reviews a concentrated 5-10 name GLOBAL equity portfolio held 1-5 years, handed off to Interactive Brokers as a watchlist plus DRAFT order instructions. |
| pr-reviewer | 450 | 1,458 | End-to-end pull request review pipeline that posts inline GitHub comments via a single atomic gh api call. |
| prompt-engineer | 244 | 704 | Design and write production-grade system prompts for AI agents and LLM applications. |
| prompt-injection-tester | 267 | 613 | Generate tailored prompt-injection / jailbreak TEST prompts to red-team a chatbot or agent you built and own. |
| python-code-style | 360 | 360 | Python code style, linting, formatting, naming conventions, and documentation standards. |
| qa | 343 | 1,262 | Use whenever the user asks to QA, test, verify, check for bugs, or check if something is ready to ship. |
| rag-guide | 172 | 1,323 | Building, debugging, and scaling retrieval systems — RAG, vector search, agentic retrieval, and whether to retrieve at all. |
| scrutinize-idea | 131 | 372 | Maximum-adversary idea critic — harsh, fair, structurally incapable of rubber-stamping. |
| seo-audit | 347 | 2,005 | Used when the user wants to audit, review, or diagnose SEO issues on their site. |
| showcase | 217 | 995 | Create a realistic in-context HTML mockup showing how a proposed UI component or feature would look inside the actual project. |
| skill-forge | 368 | 368 | Used when creating a new Agent Skill that requires exhaustive domain research and quality gating. |
| skill-improver | 247 | 679 | Used whenever the user asks to improve, refine, polish, fix, audit, optimize, or suggest improvements for an existing Agent Skill. |
| skill-judge | 752 | 997 | Evaluate Agent Skill design quality against official specifications and best practices. |
| slack | 97 | 97 | Wait for Slack messages using the `slack-watch` poller. |
| spec-judge | 707 | 707 | Evaluate software/product spec quality across 8 dimensions, scoring out of 120. |
| sst | 263 | 1,416 | Build and deploy full-stack applications on AWS using SST v3 (Ion). |
| strands-agentcore | 333 | 2,465 | Build production-quality AI agents using AWS Strands Agents SDK and deploy them to Amazon Bedrock AgentCore. |
| strands-steering-hooks | 262 | 1,010 | Strands Agents: steer — not just observe — an agent run at runtime. |
| ui-animation | 134 | 1,076 | Creates, reviews, and debugs UI motion and animation implementations. |
| ui-ux-pro-max | 658 | 658 | UI/UX design intelligence for web and mobile — 50+ styles, 161 color palettes, 57 font pairings, 161 product types, 99 UX guidelines, 25 chart types. |
| ultracode | 147 | 296 | Maximum-scale multi-agent coding orchestration — turn a task into a Sonnet agent fleet run through the Workflow tool. |
| version-audit | 213 | 487 | Audit every version reference in a repo and check each against the latest SAFE version. |
| website-cloner | 149 | 527 | Used whenever the user wants to clone, copy, replicate, recreate, or mirror a website or landing page. |
| worklog | 265 | 1,880 | Operate the user's worklog time-tracker — query blocks, assign Jira tickets, fix durations, sync to Tempo. |

*"Total incl. references" counts `.md`/`.txt` files only (SKILL.md + references/, execution-prompt.md, planning.md, etc.) — it deliberately excludes code/data/binary assets in `scripts/`, `data/`, and any vendored dependencies (see finding below).*

**Vendored-dependency finding**: `investment/` has a full `node_modules/` checked in (16 MB, ~217k lines across all files) — `yahoo-finance2` and its transitive deps. This is dead weight in the repo (not loaded into context, since it's not `.md`/`.txt` and nothing points an agent at it), but it bloats the skill directory's on-disk size ~30x over its actual content and will make `du`/`find`/backup operations over `.claude/skills` far slower than they should be. Recommend `.gitignore`-ing and removing it; the skill only needs `scripts/*.js` and `package.json` to reinstall.

---

## 2. Totals

- **Skill count**: 66 (67 directories on disk; `flow-feature` is a symlink to `feature`, not counted separately; `shared/` has no `SKILL.md` and isn't a skill)
- **Total SKILL.md lines** (all 66, summed): **19,538**
- **Total lines including text references** (`.md`/`.txt` only): **81,944**
- **Skill INDEX token cost per session**: every session pays for all 66 frontmatter `description` fields concatenated (that's the text shown in the `<system-reminder>` available-skills listing) — **49,972 characters → ≈ 12,493 tokens** at 4 chars/token, **before a single skill is invoked**. That's ~12.5K tokens of fixed overhead on every turn that includes the skill listing, roughly the size of a 25-page document, just to know what's available.
  - The three heaviest single descriptions are `portfolio` (1,654 chars), `alpha-hunt` (1,426 chars), and `flow-spec` (1,334 chars) — together ~4,400 chars (35%+ over three skills) of the 49,972-char index.

---

## 3. Overlap analysis

### Scope correction first
Of the clusters as originally hypothesized, several members aren't actually skills in this directory:
- **`speckit.*`** — real, but they're 9 **slash-commands** in `~/.dotfiles/.claude/commands/speckit.*.md` (1,390 lines total: constitution→specify→clarify→plan→tasks→analyze→checklist→implement→taskstoissues), a wholly separate Claude Code mechanism from the skills directory. This *is* a legitimate, load-bearing overlap finding (see Cluster A below) — just not one this line-count section captures, since commands aren't skills.
- **`get-shit-done`**, **`orchestrate`**, **`code-review`**, **`simplify`**, **`test`** — not present anywhere in this repo. `orchestrate`/`code-review`/`simplify`/`test` showed up in the session's available-skills list as plugin/built-in skills injected by the harness, unrelated to this dotfiles repo.

### Cluster A — spec-driven build pipeline: `flow`, `flow-spec`, `flow-feature`(=`feature`), `flow-deepen`, `flow-handoff`, `flow-to-issues`, plus the external `speckit.*` commands
This is **not** internal redundancy — it's one pipeline decomposed into composable stages, and `flow`'s own SKILL.md literally loads the others' files verbatim (confirmed by grep: `flow` MANDATORY-loads `flow-spec/references/question-bank.md`, `flow-spec/references/spec-template.md`, `feature/execution-prompt.md`, `feature/references/quality-gates.md`, and conditionally `flow-deepen/references/detection-heuristics.md`). What a user actually needs:
- **`flow`** — the default entry point for "spec it and build it" in one sitting; swallows flow-spec + feature + flow-deepen internally. Covers ~95% of solo use.
- **`flow-spec`** — call directly only when you want a spec written and reviewed *without* committing to build yet.
- **`flow-to-issues`** — call directly only when you want GitHub-tracked, AFK/HITL-tagged issues instead of flow's "build straight through in one session."
- **`feature`** — usable standalone for a smaller ask that doesn't want spec-judge ceremony; also what `flow`/`flow-to-issues` invoke per-slice under the hood.
- **`flow-deepen`** — a post-merge cleanup pass; rarely called by name, mostly reached via `flow`'s optional Phase 7 offer.
- **`flow-handoff`** — pure infrastructure (splits a long session), not a competing pipeline; connective tissue `flow-to-issues`/`feature` use internally.

**Real redundancy in this cluster**: the *external* `speckit.*` command family duplicates the same shape (constitution → spec → clarify → plan → tasks → implement) through an entirely separate mechanism (slash-commands, not skills) with no cross-reference to `flow`/`flow-spec` anywhere either direction — a user picking between "run `/flow-spec`" and "run `/speckit.specify`" gets two differently-shaped specs with no shared vocabulary. Worth consolidating on one system or explicitly documenting when to use which.

### Cluster B — massive-parallel-agent posture: `ultracode`, `overkill` (`orchestrate` not in this repo)
Legitimately distinct, not redundant: `ultracode` is code-execution-shaped (implementer + adversary-reviewer fleet through the Workflow tool, for migrations/refactors/big builds — explicitly says do NOT use it for a single feature, use `/feature`), while `overkill` is research/task-depth-shaped for *any* task and explicitly excludes itself from code builds too ("research-only fan-outs with no code written"). Both are bare-invocation posture-arming skills a power user turns on for the rest of a session. No consolidation needed.

### Cluster C — quality/testing gates: `qa`, `audit`, `pr-reviewer` (`code-review`, `simplify`, `test` not in this repo)
Not redundant — each operates on a different object and produces a different artifact:
- **`qa`** — verifies one branch pre-ship (live browser QA swarm + optional human browser session). "Does this work, is it ready to ship."
- **`audit`** — whole-codebase/module debt inventory across 6 dimensions, ending in a user-approved, serialized fix-apply. "What's wrong across this codebase."
- **`pr-reviewer`** — posts inline comments to an *open GitHub PR* via a single atomic `gh api` call, confidence-gated, 8-comment budget. "Review this PR on GitHub."
A user needs all three for different moments (own work before merge / periodic codebase health / reviewing an open PR). The only outstanding question is how these three interact with the harness's external `code-review`/`simplify` plugin skills, which weren't available to inspect from this repo — worth a follow-up check if the user has those plugins installed, since their descriptions (from the session listing) sound like they'd duplicate `audit`'s diff-review role.

### Cluster D — idea-development: `brainstorm`, `develop-idea`, `scrutinize-idea`, `grill-me`, (`grill-with-docs`)
The **least** redundant of the four named clusters — each sits at a distinct point on a spectrum, and their own descriptions cross-reference each other's boundaries explicitly (`develop-idea`'s SKILL.md: "Do NOT use for a kill-or-keep verdict... use scrutinize-idea"):
- **`brainstorm`** — codebase-grounded, generates *new* improvement ideas as a polished HTML deliverable (7-field Idea Passports, tiered).
- **`develop-idea`** — conversational, GROWS a raw idea the user already has; explicitly generative, not a verdict.
- **`scrutinize-idea`** — the opposite pole: adversarial teardown ending in a kill-or-keep verdict.
- **`grill-me`** — Socratic interview resolving a plan's decision tree one branch at a time; a 10-line skill that's essentially a system-prompt wrapper.
- **`grill-with-docs`** — `grill-me` plus live CONTEXT.md/ADR updates as decisions crystallize.
**One real redundancy**: `grill-me` vs `grill-with-docs` — for any project that doesn't maintain CONTEXT.md/ADRs, `grill-with-docs` degrades to `grill-me` with unused doc-update steps that never fire. A user who doesn't keep those docs only needs `grill-me`.

### Bonus cluster noticed but not asked for — `claude-md` vs `claude-md-improver`
These two are close to true duplicates: both audit/generate/improve CLAUDE.md files, triggered by near-identical phrasing ("audit/improve/fix CLAUDE.md"). `claude-md` is the newer, broader one (enforcement-hierarchy framing, hooks-vs-CLAUDE.md-vs-rules decision, "instruction budget" concept); `claude-md-improver` is older and narrower (scan → quality report → targeted updates). Worth merging or explicitly deprecating one — as written, both would plausibly fire on the same request and there's no cross-reference telling the agent (or the user) which one wins.

*(A 7-way frontend-design cluster — `design`, `impeccable`, `ui-ux-pro-max`, `mobile-design`, `polish`, `showcase`, `ui-animation` — also exists and would repay a dedicated overlap pass, but is outside the four clusters named for this audit.)*

---

## 4. Dead references

Grepped every `.md` file under the skills directory for `.claude/skills/...`, `~/.claude/...`, `<skill>/references/....md`, and `<skill>/scripts/....ext` path patterns (495 unique refs checked, including relative `../other-skill/...` cross-skill references), then resolved each against disk.

**Result: no genuine dead references found.** The skill set's internal cross-links are clean. Specifically ruled out as false positives after checking context:
- `alpha-hunt/execution-prompt.md` and `alpha-hunt/references/signals.md` reference `../investment/scripts/fetch-macro.js`, `fetch-universe.js`, `fetch-insider.js`, `fetch-quote.js`, `fetch-13f.js`, `compute-fraud-check.js` — my first grep pass dropped the `../investment/` prefix and flagged these as missing; all six exist in `investment/scripts/`.
- `portfolio/references/04-global-data.md` references `investment/scripts/fetch-financials.js` descriptively ("the house ... already uses") — exists.
- `skill-judge/SKILL.md:397` (`scripts/create-doc.py`) and `claude-md/SKILL.md:162` (`scripts/pre-commit-check.sh`) are illustrative code-fence examples of a documentation pattern, not literal load instructions for files those skills ship — neither skill has a `scripts/` directory, and neither is a bug (they're teaching syntax, e.g. "**MANDATORY**: Use exact script in `scripts/create-doc.py`" inside a "here's what a low-freedom instruction looks like" example block).
- `shared/project-detection.md` / `shared/verification.md` reference `.claude/scripts/start-dev-server.sh` / `stop-dev-server.sh` — these describe a *convention to look for in the user's own project*, not a file this skill package ships (compare `shared/scripts/start-dev-server`, no `.sh`, which is the skill's own script and does exist).
- `claude-md-improver/SKILL.md:29` lists `~/.claude/CLAUDE.md` in a documentation table of CLAUDE.md file-location types, not as an instruction to load it. (It happens not to exist for this user, but that's expected — it's optional.)
- `qa/references/agent-prompts.md:182` referencing `~/.claude/skills/agent-browser/SKILL.md` was a regex artifact (trailing period from end-of-sentence) — the real path exists.

---

## 5. `flow`'s MANDATORY-READ load chain for one Medium `/flow` run

Traced every `MANDATORY — READ` / `MANDATORY before Phase 0` / `Load [...]` instruction in `flow/SKILL.md`, transitively, for the default path: **Subagent mode** (the default for Medium — Agent-team requires Large+4-independent-slices or an explicit team request; Workflow mode requires an ultracode signal), a **UI** feature (browser-verification file choice), **code-design pass not triggered** (its trigger is shared contract surface across slices, not size — assumed not to fire for a baseline Medium run), and **deepen declined** (Phase 7 is offer-only, "never assume").

| # | File | Lines read | Why |
|---|---|---:|---|
| 1 | `flow/SKILL.md` (entry point, full read) | 266 | The skill itself |
| 2 | `orchestration.md` — frontmatter + "The one rule" + "Mode Detection" + Mode A (Subagents) section only | 64 of 213 | MANDATORY before Phase 0; the other two mode sections (~149 lines) are explicitly named "dead weight for this run" and skipped |
| 3 | `flow-spec/references/question-bank.md` | 278 | MANDATORY — READ ENTIRE FILE, before Phase 1's first clarifying question |
| 4 | `flow-spec/references/spec-template.md` | 401 | MANDATORY — READ ENTIRE FILE, before writing `spec.md` |
| 5 | `flow/planning.md` | 122 | MANDATORY — READ ENTIRE FILE, build-plan template |
| 6 | `feature/execution-prompt.md` | 271 | MANDATORY — READ ENTIRE FILE, the TDD Red/Green/Refactor state machine, reused unchanged |
| 7 | `feature/references/quality-gates.md` | 340 | MANDATORY — READ ENTIRE FILE, Phase 5 quality swarm (not size-gated, unlike E2E) |
| 8 | `shared/claude-in-chrome-reference.md` | 45 | MANDATORY — READ FIRST, Phase 5 browser verification (UI path; the non-UI alternative `shared/verification.md` is 77 lines) |
| **Total (this run)** | | **1,787** | |

**Conditional add-ons, not counted in the 1,787 baseline:**
- **Code-design pass** (fires only when 2+ slices share a name/id-type/error-shape/module-boundary/shared-resource, independent of size tier): `flow-spec/references/code-design-doctrine.md` (200) + `flow-spec/references/pattern-forces.md` (76) = **+276 lines**. Plausible on a real multi-slice Medium feature, so a more realistic worst-case-but-common total is **2,063 lines**.
- **Deepen pass** (Phase 7, offer-only, requires explicit user "yes"): `flow-deepen/references/detection-heuristics.md` = **+153 lines**.
- **E2E tests**: explicitly Large-UI-only — 0 lines for Medium, correctly excluded above.
- **`qa` skill** (Phase 5, step 6 — "invoke the `qa` skill against the branch"): not a `Load X.md` instruction so excluded per the literal pattern requested, but worth flagging — `qa` itself is another 343-line SKILL.md (1,262 incl. its references) the agent effectively also has to load mid-run if that step is taken literally.

**Full theoretical maximum** (code-design triggers + user accepts the deepen offer + qa's own SKILL.md counted): 1,787 + 276 + 153 + 343 ≈ **2,559 lines**, before any subagent/Workflow prompt or the codebase content itself is read.
