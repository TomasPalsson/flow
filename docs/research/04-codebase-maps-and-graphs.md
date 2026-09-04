# Do the readers need a map? — code graphs, repo maps, and memory for the flow harness

Synthesis of four research passes, all dated 2026-09-04:
- `graphify-and-code-graphs.md` — what Graphify is, and the whole code-knowledge-graph field
- `lsp-and-serena.md` — Serena, native Claude Code LSP plugins, and the grep-vs-LSP evidence
- `repo-maps-and-docs.md` — CLAUDE.md, ARCHITECTURE.md, aider repo map, generated maps
- `code-location-memory.md` — subagent memory, auto-memory, what to persist vs. recompute

**Question being answered:** would a code graph (graphify.net) or memory help the flow skill's three read-only explorer subagents "know where the code is"?

**Short answer:** the graph is a no for now; a narrow, dated, verify-before-use memory on the explorers is a yes; and the largest available win is free — it is in the explorer *brief*, not in any new tool. The single most relevant measured finding in the whole corpus is that agents given semantic-navigation tools chose them 0–6% of the time for localization tasks, and forcing semantic-first *lowered* success from 100% to 89% (`lsp-and-serena.md` #9). Tools that agents route around do not solve "know where the code is."

---

## 1. What graphify.net actually is

| Question | Answer | Confidence |
|---|---|---|
| Is `graphify.net` the product? | **No.** It is an SEO/AdSense directory-style marketing page describing an open-source project whose real home is `github.com/Graphify-Labs/graphify` (PyPI `graphifyy`, CLI `graphify`). | **High** — verified twice, including an independent source-check pass (`graphify-and-code-graphs.md` §Source check #2) |
| Is the site trustworthy? | **No.** Three verified factual errors vs. its own linked sources: claims MIT (GitHub says Apache-2.0); claims "3.7k+ stars" (GitHub API: 114,624); its "Install & Run" block names a completely different package (`private-context-mcp` / CLI `private-context`). Anyone installing from that page installs the wrong thing. | **High** — re-fetched verbatim via curl; WebFetch 403s on the domain |
| What is the real Graphify? | Open-source Apache-2.0 skill + CLI + MCP server. Tree-sitter AST over ~37–40 grammars builds a local NetworkX graph (calls/imports/inherits edges) with **no LLM call for code**; docs/PDFs/images/video **do** cost LLM calls. Query verbs: `query`, `path`, `explain`. Ships a Claude Code `PreToolUse` hook that nudges (or in `--strict` blocks-once) raw file reads toward graph queries. | **High** (README verified verbatim) |
| Is it a funded product? | Yes — YC S26 badge, and a separate commercial hosted layer (`app.graphify.com`) in early access on top of the free CLI. | **High** |
| Do its numbers hold up? | **Unknown.** "71.5× token reduction" is a homepage stat computed on a *mixed document corpus* (3 repos + 5 papers + 4 diagrams), not on code navigation. The LOCOMO/LongMemEval benchmark table is the vendor's own harness, LLM-judged. No third-party benchmark of Graphify or any peer was found. | **Low** on the claims; **High** that they are vendor-only |
| Adoption signal? | **Do not trust it.** 0 → 114,624 stars in ~5 months. Peers show the same shape (codebase-memory-mcp 0 → 42k in 6 months). Star-history could not be pulled; organic-vs-inflated is unresolved. | **Low** |

**Two structural warnings that outrank any of the above.** First, Nx — a major vendor with a real project graph — publicly *deleted most of its MCP tools* and moved workspace exploration to on-demand skills, on the grounds that a permanently-loaded graph-query tool surface hurt agents (`graphify-and-code-graphs.md` #17). Second, Anthropic's own context-engineering guidance recommends exactly the opposite of a pre-built index: lightweight identifiers plus just-in-time grep/glob, "avoiding the issues of stale indexing and complex syntax trees" (`code-location-memory.md` #5). Both vendors are arguing against the graph pitch from inside the graph-building camp.

---

## 2. The options, compared

Freshness = what happens when code moves. Context cost = tokens paid per use, in the main thread or in the explorer's. Evidence = how much of the claim is independently verified.

| Option | Mechanism | Freshness | Context cost | Integration effort | Evidence strength | Main downside |
|---|---|---|---|---|---|---|
| **Graphify** | Tree-sitter → local NetworkX graph + Leiden clusters; CLI/skill/MCP; `PreToolUse` hook redirects reads | Auto-rebuild on commit/checkout; **manual `graphify update .` after pull/merge**; working-tree edits not covered | Query returns a scoped subgraph (~1.7k tok claimed); MCP tool surface is always-resident | Medium: `uv tool install graphifyy`, `graphify install`, hook install, `.claudeignore` the output | **Weak** — vendor-only, on a doc corpus not code nav; marketing site provably wrong; star anomaly | Third staleness axis; hook that blocks real file reads fights the harness's receipt discipline |
| **GitNexus** | Browser-only KG builder + chat-style Graph RAG over a repo URL/ZIP | N/A — one-shot per upload | N/A to agents | **No CLI/MCP path documented** | Weak (stars only) | Not addressable from Claude Code at all; standalone exploration tool |
| **CodeGraphContext / codebase-memory-mcp / code-graph-rag** | MCP servers over a real graph DB or native index; Tree-sitter (+ hybrid LSP for 10 langs in codebase-memory) | Not documented as auto-resync in the sources fetched | Per-query tool calls + resident tool surface | Medium (MCP registration; codebase-memory has no runtime) | **Weak** — codebase-memory's "83% quality, 10× fewer tokens" is a **self-published arXiv preprint**, not peer-reviewed | Same category risk as Graphify, less mature integration; unverified |
| **Serena (already installed)** | LSP-backed symbol find/refs/overview + symbol-level *editing* + cross-session memories; 40+ langs | Index claims auto-update on file change; **open bug #1937: silently partial TS results while the graph loads** | Per-call; MCP tool surface resident | **Zero — already configured** | **Mixed.** Vendor eval is qualitative with no numbers. Seven open Aug–Sep 2026 issues verified live | **#1944/#1966: concurrent instances on one workspace = unbounded CPU/RAM or outright failure — and flow spins worktrees and fans out 3 explorers** |
| **Native Claude Code LSP plugins** | `.lsp.json`, Anthropic-managed process; go-to-def/refs/hover/rename/diagnostics as first-class tools; 13 languages | Live from the language server — cannot go stale | `diagnostics: true` (default) auto-injects after every edit; `false` keeps nav and kills that cost | **Low** — `/plugin install <lang>-lsp@claude-plugins-official` + install the server binary yourself | **Strongest in the corpus, and it cuts both ways.** agentconnect.md: clean typed TS +0.000 F1 at **+16% tokens**; noisy TS +0.246 F1 at −12%; Python +0.072 F1 at **+19% tokens** | Payoff is workload-dependent, not universal; first-registered server wins per extension |
| **aider-style repo map** | Tree-sitter tags → file-node graph → PageRank rank → ~1k-token budget, resized by chat state | Recomputed every invocation — **cannot go stale** | ~1k tokens, budgeted and dynamic | **Not available.** Internal to the `aider` CLI; no MCP surface | Strong on mechanism (docs verified verbatim), no comparative benchmark | Unreachable from Claude Code; would have to be reimplemented |
| **Generated `codebase-map.md`** | Script: pruned tree + exported symbols + entry points from manifests, hard line cap, commit-hash stamp, `@`-imported from CLAUDE.md | Regenerates on SessionStart; **blind spot: a HEAD-hash short-circuit reports "unchanged" mid-refactor, exactly when it matters** | Whatever cap is set (<200 lines if always-loaded) | **Low** — one script + one hook, no dependency | Mechanism confirmed (CLAUDE.md re-read every session and after `/compact`); no benchmark | Reports *what* exists, never *why*; Anthropic explicitly lists "file-by-file descriptions" and "anything Claude can figure out by reading code" as things to **exclude** |
| **Subagent memory (`memory: project`)** | `.claude/agent-memory/<agent>/`; first 200 lines / 25KB of `MEMORY.md` auto-loaded into the subagent's system prompt; topic files read on demand | **Nothing validates a stored fact against the filesystem — in any tool surveyed** | 200 lines / 25KB ceiling, hard | **Lowest** — one frontmatter line on a subagent | Mechanics confirmed verbatim; the *risk* is confirmed by practitioner data: <20% of auto-proposed memory updates accepted, and self-pruning "never seen... across literal thousands of sessions" | Agents trust memory over ground truth; models are penalized in training for assuming input is wrong |
| **Auto-memory (`MEMORY.md`)** | Harness-written, timestamped (`modified`), per-repo, machine-local | Same 200-line/25KB ceiling; over-limit content dropped next load (with an error to Claude, not silently) | Loaded at every conversation start | Already on | Confirmed verbatim | **Deliberately excludes exactly what is being asked for**: "Claude skips anything it can derive from the codebase, such as architecture, **file paths**, or debugging fixes" |

---

## 3. Recommendation, in three tiers

### Tier 1 — Adopt now

**1a. Fix the explorer brief before buying any tool.** This is free, and it is the only item in this synthesis backed by a measurement of the actual failure mode. agentconnect.md found that returning *surrounding source context* alongside a search hit, rather than a bare location, raised pass@1 from 0.67 → 0.83 and cut follow-up file reads from 15.2 → 3.2 per task (`lsp-and-serena.md` #9). The flow explorers currently get an unstructured "map existing patterns, conventions and reusable code" instruction (`skills/flow/steps/01-spec.md` line 22). Make the return shape a contract, matching the receipt discipline `build-slices` already enforces on adversary findings:

In `.claude/skills/flow/steps/01-spec.md`, replace the codebase-research sentence with a brief that pins the output:

```
Each explorer returns ONLY this shape, ≤ 40 lines:
  entry_points:  path:line — one clause on what enters here
  seams:         path:line — the boundary this file owns (auth, config, migrations, routing)
  reusable:      path:line — signature, verbatim, plus 3-6 lines of surrounding source
  recipe:        the grep/glob that relocates each of the above if it moves
  dead_ends:     paths that look relevant and are not, with why
Every line carries a path:line receipt you opened this run. No receipt, no line.
```

Rationale: `path:line + signature + a few lines of source` is what turns a location into a usable one, and the recipe line is the self-healing form — a *procedure* for relocating something survives the refactor that invalidates the path (`code-location-memory.md` §Policy).

**1b. Give the explorers `memory: project`, scoped hard.** Promote the ad-hoc haiku explorer to a real agent definition so it can carry memory. Create `~/.dotfiles/claude/.claude/agents/explorer.md`:

```yaml
---
name: explorer
description: Read-only codebase reader for flow step 1. Returns locations with receipts.
tools: Read, Grep, Glob, Bash
model: haiku
memory: project
---
You map where code lives. You never write code.

BEFORE exploring: read MEMORY.md. Treat every entry as a HINT, never as a fact.
Any remembered path must be re-verified with one Glob or Read this run before you
report it. If it no longer resolves, delete the line and report the new location.

AFTER exploring, write back ONLY these four kinds of line, each dated YYYY-MM-DD:
  entry point | seam | search recipe | dead end
Never write: file contents, line numbers, signatures, dependency graphs, or anything
one Grep answers cheaply. Those are recomputed every run.
Keep MEMORY.md under 200 lines. When it approaches the cap, merge or drop the oldest
entries rather than appending.
```

Then in `orchestration/subagents.md`, change the step-1 row from `general-purpose` to `subagent_type: explorer` (drop the per-call `model: haiku` — the agent file pins it).

Two constraints make this safe rather than a new staleness source, and both come straight from the research: the *verify-before-use* line, because **no tool surveyed enforces this and agents demonstrably trust memory over the filesystem**; and the *never write paths/line numbers/signatures* line, because auto-memory's own documented exclusion rule is "skips anything it can derive from the codebase, such as architecture, file paths" (`code-location-memory.md` #4, #9, §Downsides).

Note the dependency: subagent memory requires `autoMemoryEnabled` globally, or it silently does nothing.

**1c. Keep Serena where it is, and keep it out of the explorer wave.** Serena stays — it is already configured, and it uniquely provides symbol-level *editing* (`replace_symbol_body`, `insert_before/after_symbol`) that the native LSP plugins do not expose. But two things say the parallel explorer wave should stay on Grep/Glob/Read: agents pick grep over semantic lookup 94–100% of the time for localization anyway, and **issues #1944 and #1966 are open bugs about exactly this harness's pattern** — concurrent instances against one workspace causing unbounded CPU/RAM (Eclipse JDTLS) or outright failure (Kotlin LSP). flow spins worktrees *and* fans out three explorers; that is N language servers on one workspace. The `tools:` line in 1b already enforces this.

Also, if Serena is ever reinstalled: **do not use `/plugin install serena@claude-plugins-official`**, even though Anthropic's official marketplace lists it. Serena's own README says marketplace installs carry "outdated and suboptimal installation commands." Use `uv tool install -p 3.13 serena-agent` + `serena init`.

### Tier 2 — Try for a week, with the measurement that decides

**2a. A generated `.claude/codebase-map.md`, cap 150 lines, `@`-imported from CLAUDE.md.** Script: pruned `tree -L 3`, exported symbols via tree-sitter or ctags, entry points from manifest fields (`package.json` `bin`/`main`, `pyproject.toml [project.scripts]`), truncated deterministically by import in-degree. Stamp the commit hash *and* `git status --porcelain` hash in an HTML comment (Claude Code strips block-level HTML comments before injection, so the stamp is free). Register as a `SessionStart` hook that short-circuits on an unchanged stamp.

The dirty-tree hash is not optional: a plain `HEAD` short-circuit reports "unchanged" during mid-refactor sessions, which is precisely when the map is most wrong (`repo-maps-and-docs.md` §Concrete setup, closing paragraph).

> **Decision measurement:** over one week of flow runs, count (i) explorer wave total tokens and (ii) how many slices in `build-slices` named the correct target files on the first brief without a follow-up search. Keep the map only if the explorer wave gets cheaper *and* first-try file accuracy does not drop. Kill it if the map's presence makes explorers report map contents instead of opening files — check this by grepping explorer returns for receipts that do not correspond to a Read this run.

Note the tension to watch: Anthropic's `/doctor` actively *trims* "directory layouts, dependency lists, and architecture overviews" out of CLAUDE.md. This experiment is deliberately betting against that guidance for the narrow case of a fan-out of cheap haiku readers, and the measurement above is what settles it.

**2b. One native LSP plugin for the primary language, `diagnostics: false`.** For a TS/JS or Python project:

```bash
npm install -g typescript-language-server typescript   # or: pip install pyright
```
```
/plugin install typescript-lsp@claude-plugins-official
/plugin        # confirm the server started — check the Errors tab
```

Then set `"diagnostics": false` in the plugin's `.lsp.json` to keep go-to-def / find-refs / hover / rename while suppressing the auto-injected diagnostics after every edit — the direct token lever.

> **Decision measurement:** the deciding variable is *codebase noisiness*, and the corpus gives the split explicitly: clean typed TS gained **+0.000 F1 at +16% tokens**; noisy TS gained **+0.246 F1 at −12% tokens**. So measure on the repo actually being built in: over a week, count rename/reference tasks where a grep-only pass missed an occurrence (in comments, strings, config) versus where semantic lookup missed one. Keep the plugin only if find-references catches something grep did not, *and* the run cost did not rise. On clean, well-typed code the honest expected outcome is "no gain, +16% tokens" — uninstall in that case.

### Tier 3 — Skip

| Skipped | Reason |
|---|---|
| **Graphify** | Every performance number is vendor-produced, and the headline 71.5× was measured on a mixed *document* corpus, not code navigation. Its marketing site is provably wrong on three verifiable facts, including the install command. Its `PreToolUse` hook redirects raw file reads to graph queries — directly at odds with the receipt discipline in `build-slices`, where a finding needs a `file:line` a reader actually opened. It adds a third staleness axis (code → graph → memory) with a manual `graphify update .` after every pull. **Revisit only if** the target changes to a >100k-LOC polyglot repo nobody on the project knows, and only after a third-party benchmark exists. |
| **GitNexus** | Browser-only, no CLI or MCP integration path. Cannot be reached from Claude Code. |
| **CodeGraphContext / codebase-memory-mcp / code-graph-rag** | Same category, same evidence problem, less integration maturity. codebase-memory's strongest claim rests on a **self-published, non-peer-reviewed preprint** by its own author. Nothing here is better-evidenced than Graphify, and Graphify is already a skip. |
| **aider repo map** | Genuinely the best-designed mechanism in the corpus (recomputed every call, so it cannot go stale) and **completely unavailable** — it lives inside the `aider` CLI with no MCP surface. Its *idea* is what Tier 2a borrows; the tool itself is not adoptable. |
| **Repomix / gitingest** | One-shot whole-repo dumps. Right shape for pasting a small repo into a chat UI, wrong shape for three agents doing targeted iterative queries. |
| **Multi-file generators (`codebase-md` and similar)** | Writes six near-duplicate context files (`CLAUDE.md`, `AGENTS.md`, `.cursorrules`, …), adding a second staleness axis — files drifting from *each other* on top of drifting from code — against Anthropic's explicit "one canonical file with an import" guidance. |
| **Sourcegraph MCP** | The best-evidenced option in the entire corpus (Sonnet 4.6 + MCP scored 0.698 at $1.02/quality-point vs. a bigger model on a local checkout at 0.568/$1.83) — and it is aimed at "when your codebase doesn't fit on your laptop." A solo dev on a 1M-context session and repos of this size is not the target. **Revisit if** the work moves to a large multi-repo org codebase. |
| **Serena's paid JetBrains backend** | Type hierarchy, move/inline, dependency search, debugger — real capabilities, but they serve *editing*, not "where is the code," and they cost money to answer a question grep answers free. |

---

## 4. How the explorers and build-slices should use this

The rule that organizes all of it: **memory is an index of where to look, never a cache of what will be found.**

**Explorer subagent (flow step 1), in order:**

1. **Read first, cheaply:** its own `MEMORY.md` (auto-loaded, ≤200 lines), then `.claude/codebase-map.md` if Tier 2a is live, then `PROGRESS.md` if the repo has one. Total ≤ ~2k tokens. All three are **leads**, not findings.
2. **Verify live, always, before reporting:** every path that will appear in the return, with a Glob or Read *this run*; every signature quoted, from the file, not from memory; anything the slice brief will name. A remembered path that fails to resolve is a memory bug — delete the line, report the new location. No tool surveyed does this check automatically, so it has to be an instruction.
3. **Never trust from any of the three sources:** line numbers, file contents, current signatures, dependency edges, test status. All are one cheap call away and all rot silently.
4. **Store back, dated, four kinds only:** entry points, seams, search recipes, dead ends. A search recipe ("the handler registry is wherever `FEATURE_FLAGS` is imported") outlives the refactor that breaks a path — prefer it to a path whenever both are available. Nothing else gets written.

**build-slices:** the slice brief already is the contract, and it already forbids reading beyond what it names — that discipline should not be loosened for a map or a graph. Concretely:

- The **brief** may carry map- or memory-derived locations, but only ones an explorer verified live in step 1, and they enter the brief as `path:line` receipts like any other. A developer agent reading `.claude/slices/N-brief.md` should never be told "consult the graph."
- **Adversary lenses must not read the map or the memory at all.** They read the brief and the diff, and their findings need a `receipt` of `file:line` or command output — a receipt sourced from a cached index is not a receipt. Feeding a scanner the same possibly-stale map that produced the code under review destroys the independence the two-lens design exists for.
- **Write-back happens once, from the explorer, at the end of step 1** — not from developer agents mid-build, and not from adversaries. One writer keeps the 200-line budget governable and keeps unreviewed build-time noise out of the index.
- **Prune on a schedule, not reactively.** Practitioner data says agents essentially never self-prune, and <20% of auto-proposed memory updates survive human review. Read `.claude/agent-memory/explorer/MEMORY.md` yourself monthly; anything undated or older than a quarter goes unless it still resolves.

---

## 5. Downsides register

| # | Downside | Where it bites here | Mitigation |
|---|---|---|---|
| 1 | **Agents trust memory over the filesystem.** Documented as the dominant real-world failure; models are penalized in training for assuming input is wrong. | The explorer confidently reports a path that moved three commits ago; the slice brief inherits it. | The verify-before-report rule in the agent body (§3, 1b). Non-negotiable — it is the only guard, because no tool enforces it. |
| 2 | **Nothing validates a stored fact against the code.** True of Claude Code memory, Serena, claude-mem, A-MEM, darc — all of them. | Silent drift accumulates across sessions and is never noticed. | Store recipes over paths; date every line; monthly human read of `MEMORY.md`; optionally a `test -e` lint over every path in the map/memory, run separately from the generator. |
| 3 | **Memory grows and is never pruned.** Over the 200-line/25KB cap, content is dropped from the next load. | The index silently loses its oldest and possibly most durable entries. | Hard four-category write rule; "merge or drop, don't append" in the agent body; monthly prune. |
| 4 | **A generated map goes stale mid-refactor.** A `HEAD`-hash short-circuit reports "unchanged" while the working tree has moved. | Exactly the sessions where accuracy matters most. | Stamp `git status --porcelain` alongside the HEAD hash; regenerate on either changing. |
| 5 | **Structure in CLAUDE.md degrades instruction-following.** Anthropic names "the over-specified CLAUDE.md" as a failure pattern and `/doctor` actively trims architecture overviews out. | A 150-line map imported into every session competes with real rules. | Keep the map in `.claude/codebase-map.md` behind an `@` import, cap it hard, and let the Tier-2a measurement kill it if it doesn't pay. |
| 6 | **Semantic tools cost tokens for zero gain on clean typed code** (+16% tokens, +0.000 F1). | Adding LSP everywhere on a well-typed repo is a pure loss. | One language, `diagnostics: false`, one week, the noisiness measurement in §3 2b. |
| 7 | **Semantic references are a strict subset of textual occurrences.** Renames must also touch comments, strings, config. Forcing semantic-first dropped success 100% → 89%. | A rename slice that trusts find-references ships an incomplete change. | Grep stays the completeness pass for any rename or localization, regardless of what else is installed. |
| 8 | **Concurrent language servers on one workspace blow up.** Open issues #1944 (unbounded CPU/RAM) and #1966 (outright failure). | This harness's default shape: worktrees plus a 3-wide explorer fan-out. | Keep Serena out of the parallel wave via `tools: Read, Grep, Glob, Bash`; watch RAM the first time a worktree run and an IDE session overlap. |
| 9 | **Serena can return silently partial results** while the TypeScript project graph is still loading (#1937). | A wrong answer with no warning is worse than a slow one. | Run `serena project index` after large structural changes despite the auto-update claim; cross-check reference lists with grep before acting. |
| 10 | **Every benchmark in this field is vendor-produced.** Graphify's 71.5×, codebase-memory's preprint, even Sourcegraph's CodeScaleBench (whose own post says "treat as an early signal, not a settled benchmark"). | Adoption decisions made on marketing numbers. | Both Tier-2 items ship with a local measurement that decides. Nothing in Tier 1 depends on a vendor claim. |
| 11 | **A graph adds a third staleness axis** (code → graph → memory) and a `PreToolUse` hook that discourages the raw file reads the receipt discipline depends on. | Would quietly undermine `build-slices`'s strongest property. | Tier 3 skip, with a named revisit trigger. |
| 12 | **Popularity signals in this category are unreliable.** 0 → 114k stars in five months, repeated across peers, unverified. | Choosing on stars. | Decide on mechanism, freshness story, and integration cost — never on stars. |

---

## Bottom line

The readers do not need a graph. They need a brief that demands `path:line` plus surrounding source, a small dated index of entry points and search recipes they are required to re-verify, and permission to keep using grep — which is what they will do regardless. Two cheap experiments (a capped generated map, one LSP plugin) are worth a week each, and each carries the measurement that ends it. Everything else in the category is a vendor claim wearing a star count.
