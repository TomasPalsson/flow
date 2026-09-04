---
name: brainstorm
description: "Explore a codebase systematically using parallel exploration agents, then generate bold improvement ideas from transformative redesigns to quick wins using structured divergent/convergent ideation, and deliver them as a single-file interactive HTML site. Outputs ideas with 7-field Idea Passports (problem, evidence, who, impact, solution, effort, confidence) grouped into Foundation/Growth/Delight tiers, rendered as a polished, shareable HTML page styled via the frontend-design skill. Use INSTEAD of ad-hoc brainstorming when structured, evidence-backed output is needed. Trigger when: user asks to brainstorm, generate ideas, suggest improvements, 'what should I build', 'how can I improve this', 'what's missing', 'ideas for', 'what would make this better', 'opportunities in this codebase', 'UX improvements', 'DX improvements', 'what should we change', review for opportunities."
---

# Brainstorm

Generate genuinely useful, codebase-grounded improvement ideas — from bold transformations to quick wins.

## Core Mindset

**Feature-suggestion machines produce plausible-sounding additions that miss where the experience actually breaks down.** Think like a senior engineer doing a codebase audit with product instincts: find the specific friction points in the code, then propose solutions grounded in what you found.

**When exploration, generation, and evaluation happen in a single pass, ideas regress to whatever sounds safe and reasonable** — premature convergence. The only fix: strict phase separation. Explore completely first. Generate without judging second. Evaluate third. Never collapse these phases.

**The #1 reason developers dismiss AI suggestions is lack of codebase-specific grounding.** "Add better error handling" is worthless. "The `deploy.sh` script exits silently on auth failure (line 47) — add a diagnostic message with the token refresh command" is actionable. Every idea must point to a specific file or pattern. No file path = no idea.

**Training data overwhelmingly celebrates what was built, not what was simplified or removed.** You will only generate addition ideas unless you force yourself otherwise. Explicitly generate "what should be deleted or consolidated?" — these are often the highest-value ideas and they will never emerge unprompted.

---

## MANDATORY: Load Frontend Design Skill First

**Before writing the HTML output in Phase 4, you MUST invoke the frontend-design skill.** This is non-negotiable. The frontend-design skill provides the aesthetic guidance that prevents generic, flat, AI-looking output. Without it, the brainstorm page will look like every other AI-generated page and undermine the credibility of the ideas themselves.

```
Skill tool call:
  skill: "frontend-design:frontend-design"
```

Apply its guidance to every visual decision — palette, typography, spacing, component styling, motion. The brainstorm skill owns *structure and content* (tiers, Passports, evidence); frontend-design owns *aesthetics*. Invoke it BEFORE you start the HTML in Phase 4, not after — retrofitting aesthetic choices onto a finished page produces worse results than designing with them from the start.

---

## Phase 1: Explore — Build the Friction Map

### Exploration Cache

Before deploying agents, check if `.brainstorm/exploration.md` exists in the repo root.

**If the cache exists**, read the `git_hash` from its frontmatter and run `git diff --stat <cached-hash>..HEAD`:
- **No changes:** Use the cache directly. Read it and skip to Phase 2. Tell the user: "Using cached exploration from [date]. Run with `--fresh` or say 'explore fresh' to force a full re-exploration."
- **Some files changed:** Run a targeted re-exploration of ONLY the changed files through each lens. Merge new findings into the existing cache — update entries for changed files, keep entries for unchanged files, remove entries for deleted files. Update the git hash.
- **>30% of files changed or cache is >30 days old:** Full re-exploration. The codebase has shifted enough that incremental updates risk missing structural changes.

**If no cache exists**, proceed with full exploration below.

### Writing the Cache

After any exploration (full or incremental), write findings to `.brainstorm/exploration.md`:

```markdown
---
git_hash: <current HEAD hash>
explored_at: <ISO date>
repo_type: <detected type from Adapting to Repo Type table>
---

## Mental Model
- **User:** <who uses this and what job they hire it for>
- **Core transformation:** <what the user is trying to accomplish>

## Findings by Lens

### Structure
- <finding with file path>

### Friction
- <finding with file path>

### Complexity
- <finding with file path>

### Gaps
- <finding with file path>

### Users
- <finding with file path>
```

Keep the cache lean — findings only, no commentary or ideas. One bullet per finding. The cache should be readable in under 60 seconds on a subsequent run.

### Full Exploration

Deploy 3-5 parallel Explore agents to cover the codebase systematically. Do NOT generate ideas during exploration.

**Agent assignments** (adapt based on repo size):

| Agent | Focus | Key Question |
|-------|-------|-------------|
| Structure | README, entry points, directory layout, help text, config files | "What does a new user see first, and where do they get stuck?" |
| Friction | Error handling, empty catches, `|| true`, `2>/dev/null`, workaround comments, TODO/HACK/FIXME | "Where does the system lie to the user or absorb pain silently?" |
| Complexity | Largest files, deepest nesting, most-changed files (git log), dependency inventory | "What's carrying disproportionate complexity and why?" |
| Gaps | Missing tests, undocumented flags, config without defaults, hardcoded values | "What implicit knowledge is required to use this successfully?" |
| Users | Identify who uses this (end user, developer, CLI operator, the author themselves) and how | "Who experiences this system and what transformation are they trying to make?" |

**If parallel agents are unavailable**, run the five lenses sequentially. The value is in the orthogonal perspectives, not the parallelism. Do NOT skip lenses to save time.

**Every finding must include a file path.** No file path = the finding doesn't count. Findings like "the error handling could be better" are worthless; "empty catch block in `src/api.js:134`" is actionable.

**After exploration**, synthesize into a mental model:
1. Who the user is and what job they hire this tool for
2. Where the user's transformation breaks down (specific moments of friction)
3. What the codebase's complexity hotspots are and why they exist
4. What implicit knowledge is required that isn't documented

**Reading sparse signals:** Commit messages like "stuff" or "fix" = personal tool optimized for author muscle memory, not handoff. No README = author is the sole user. Prioritize self-documentation and recoverability (context if they return in 6 months), not discoverability or architecture.

**If exploration surfaces very little** (tiny repo, 1-2 files, no git history): skip the agent deployment entirely. Read the files directly, then proceed to Phase 2 with whatever you found. A 50-line script doesn't need 5 exploration agents — it needs 5 minutes of careful reading.

**When findings contradict** (e.g., Structure agent says "well-documented", Gaps agent says "key flags undocumented"): both are usually true at different scopes. Note contradictions explicitly — they often signal that documentation exists at one level (README) but not another (CLI flags, error states).

---

## Phase 2: Diverge — Generate Without Judging

Generate ideas across ALL of these categories. Do not let any category be empty — each surfaces a different class of improvement that the others miss:

### Category Prompts

**1. Foundation fixes** — Where are the must-be failures? Error messages that don't help, silent failures, missing defaults, broken onboarding steps. These are the highest-value quick wins.

**2. Removal & simplification** — What should be deleted, merged, or simplified? What complexity exists that users absorb but shouldn't have to? What config could have sensible defaults? What features are never used?

**3. The "what would make this WORSE?" inversion** — List 5 things that would degrade the experience. Now invert each into an improvement. This reliably surfaces blind spots that positive brainstorming misses.

**4. Architectural unlocks** — What single structural change would make multiple future improvements cheap? The "unlock" heuristic: one change that removes friction from many subsequent decisions.

**5. Bold redesigns** — If you rebuilt this from scratch knowing what you know now, what would be fundamentally different? Don't constrain by effort — this is moonshot territory.

**6. DX/UX polish** — What would make the common path delightful? Better feedback, smarter defaults, progressive disclosure of complexity, composition with other tools.

### Anti-Generic Techniques

After your first pass, apply these to escape safe/obvious suggestions:

**Exclusion constraint:** Name the 3 most obvious improvements you generated. Now generate 3 more that have NOTHING to do with those. This forces exploration past the first cluster of obvious ideas.

**The "embarrassment" filter:** Which ideas would be most embarrassing to NOT have tried? Which will seem obvious in hindsight? These surface asymmetric-upside ideas.

**Cross-domain analogy:** Pick an unrelated domain (logistics, game design, journalism). What principle from that domain, applied here, would produce a non-obvious improvement?

---

## Phase 3: Converge — Evaluate and Structure

Now apply judgment. For each idea, assess:

### The Idea Passport (required for top 5 ideas)

| Field | What to Write |
|-------|--------------|
| **Problem** | What's broken or suboptimal? 1-2 sentences, present tense, user-centric |
| **Evidence** | Specific file, line number, or pattern in this codebase |
| **Who** | Which user type is affected and how often |
| **Impact** | What changes if this is fixed — be concrete |
| **Solution** | Specific enough to start work tomorrow |
| **Effort** | T-shirt size (XS/S/M/L/XL) |
| **Confidence** | High (direct code evidence) / Medium (inferred from patterns) / Low (hypothesis) |

### Required data fields on every idea (not just top-5)

Every idea — whether or not it gets a full Passport — must carry these machine-readable fields. They drive the Phase 4 visualizations; missing fields silently degrade the output.

| Field | Type | Purpose |
|-------|------|---------|
| `id` | string (e.g. `F.01`, `G.03`) | Stable reference for cross-linking |
| `tier` | Foundation / Growth / Delight | Sectioning |
| `level` | 1-5 | Impact axis + badge |
| `effort` | XS / S / M / L / XL | Effort axis + badge |
| `confidence` | High / Med / Low | Epistemic-border encoding |
| `cited_findings` | array of finding IDs | **Required.** Enables linked brushing; without it the evidence trail collapses to prose. |
| `dependencies` | array of idea IDs | Enables the DAG. Empty array is valid; omitting the field breaks the sequence diagram. |

Findings must also carry stable IDs (not just array indices) and a `severity` (High/Med/Low) so the treemap can size tiles.

### Three-Tier Grouping

**Foundation** (fix first regardless of effort) — Must-be failures: broken functionality, confusing errors, trust-destroying silent failures. If Foundation issues exist, don't lead with Delight ideas.

**Growth** (compounds over time) — Each one makes the tool more productive or reliable. "More is better" improvements — better DX layers, performance, composability.

**Delight** (unexpected value) — Ideas that would make users enthusiastic advocates. Only present these if Foundation is solid.

### Calibration

- **8-15 total ideas** across the spectrum. Over 20 is a laundry list that signals lack of judgment. For very small repos (under 5 files), 5-8 well-grounded ideas is better than padding to 8.
- **Top 5 get full Idea Passports.** The rest get a 1-2 sentence summary with effort and confidence.
- **At least 1 bold idea (Level 4-5)** and at least 2 quick wins (Level 1-2). A brainstorm dominated by one level fails to inspire OR produce near-term wins.
- **At least 1 removal/simplification idea.** Force yourself.

**Calibration overrides — do not fabricate to fill quotas:**
- **No bold ideas warranted:** "No Level 4-5 ideas emerged because the tool's scope is narrow and well-executed" is honest and useful. Fabricating moonshots violates the grounding principle.
- **No Foundation issues found:** Before concluding the Foundation is solid, re-run the Friction lens: empty catches, `|| true`, `2>/dev/null`, silent exits. If none found, write "Foundation: No must-fix issues found — codebase handles failure gracefully" and proceed to Growth. This is a good signal, not a gap to fill.

### The Bold-to-Incremental Spectrum

Label each idea:

| Level | Type | Signal |
|-------|------|--------|
| 1 | **Patch** | Fixes a specific broken thing. No mental model change. |
| 2 | **Polish** | Improves existing interaction. Same architecture. |
| 3 | **Enhancement** | Adds meaningful new capability within existing model. |
| 4 | **Redesign** | Changes mental model or architecture of one component. |
| 5 | **Transformation** | Changes the fundamental value proposition. Makes Level 1-3 ideas irrelevant. |

**Before moving to Phase 4, verify:**
- Top 5 ideas have complete Idea Passports with file-level Evidence fields
- The bold-to-incremental distribution is honest — not manufactured to fill quotas
- If Foundation issues exist, they are listed BEFORE Growth and Delight items
- At least 1 idea involves removal or simplification

If any check fails, revisit Phase 2 or Phase 3 before presenting.

---

## Phase 4: Present — Build the HTML Site

The output is a single self-contained HTML file, not a chat reply. The chat response is a short summary plus the file path; the ideas themselves live in the HTML.

**The first idea the user sees sets their expectations for the rest.** If the hero surfaces a Level 2 Polish idea, they won't be primed to take your Level 5 Transformation idea seriously. Lead the page with the insight that reframes how they think about their codebase, not with the cheapest quick win.

### Before writing any HTML

1. **Confirm the frontend-design skill was invoked** (see the MANDATORY section near the top). If not, invoke it now. Its color, typography, spacing, and motion guidance drives every visual decision below. Without it, the page will look like default AI output and the ideas will inherit that credibility hit.
2. **Choose the aesthetic direction** that fits the codebase. A brainstorm for a CLI tool should not look like a consumer SaaS landing page. Match the visual voice to the subject: editorial restraint for infra/tooling, higher energy for product UX brainstorms.

### What the HTML must contain

Single `.html` file — CSS in `<style>`, JS in `<script>`, libraries via CDN only.

**Required sections, in this order:**

1. **Hero** — Bold title ("Brainstorm: <repo name>"), one-sentence framing of the core insight, stats (findings, ideas, F/G/D counts, count of L4-5 bold bets), generated-at timestamp. Keep stats to real numbers with clear unit labels — not decorative fragments like "1 bold" or "4/11/4". A reader should decode every stat in under a second.
2. **Core insight (the reframe)** — One paragraph. The single most important thing you learned. This is the thesis of the entire document and must be visually distinct from every other section heading — larger type, different accent, or a before/after transform panel. If the reframe reads at the same weight as "Friction Map" and "Ideas," the thesis is invisible.
3. **Friction Map** — Findings grouped by lens. **Lead with a treemap** (ECharts built-in) sized by finding count × severity — readers see where pain concentrates in under 2 seconds. Finding cards follow, with severity icons (●●● / ●● / ●), file paths as code chips, and cross-lens tags when a file appears in multiple lenses.
4. **Distribution** — Stacked bar of tier × level (the current Chart.js setup is correct for this). Optional heatmap of lens × effort if `idea.primary_lens` is populated. The framing sentence is editorial honesty: "Here is what the process actually produced — X incremental patches, Y bold bets."
5. **Ideas — the full inventory** — Starts with an **Impact × Effort 2×2 quadrant scatter** (ECharts or Observable Plot): effort on X, impact (level, or confidence-as-proxy) on Y, tier as color, idea ID as label, click-dot → scroll-to-card. This is the orientation chart. Below: filter chips + tier tabs (now URL-hash persisted) + card grid. Cards use **claim-first titles** (verb-driven sentences, not noun phrases), **epistemic-status left-border** (solid/dashed/dotted for confidence), and evidence in a right-margin column on wide viewports (Tufte-CSS sidenote pattern), collapsing inline on mobile.
6. **Passports — evidence traceability** — Top-5 full Passports. Above them: a **linked-brushing bipartite overlay** — findings on the left, ideas on the right, lines drawn from each idea's `cited_findings[]` to its findings. Click a finding, ideas citing it light up; click an idea, its findings light up. This is the analytically-most-valuable diagram in the report — it answers "which ideas have evidence, which are floating." It falls back to per-card evidence chips on mobile.
7. **Sequence — what to build when** — Replaces the old "three cards with a dependency string" layout. Render the full **dependency DAG** (d3-dag sugiyama layout, or Cytoscape with dagre): nodes = ideas colored by tier, edges = `dependencies`. "If you did three things" becomes the highlighted critical path through this graph, with the three ideas rendered as the primary path and rationale text adjacent. Three different relation types (Blocks / Unlocks / Cheapens) need three different edge styles.
8. **Footer** — Generated-by line, regeneration command hint (`Use /brainstorm to regenerate`), cache note if cache was used.

**Optional Section 0 (Executive Summary):** For decision-maker audiences, precede the Hero-and-Insight with a "top 2 per tier" summary block — six full idea cards visible without scrolling or interaction. Use when the reader's job is to decide, not explore. Skip when the reframe is strong enough to open the report on its own.

### Hard requirements (non-negotiable)

- Single self-contained `.html` file. No external CSS or JS files. Libraries via CDN only.
- **Three required diagrams** — the report fails without them:
  1. **Treemap** of findings by lens × severity at the top of the Friction Map (ECharts `treemap`).
  2. **Impact × Effort 2×2 quadrant** at the entry to the Ideas section (ECharts `scatter` + `markArea` for quadrants, or Observable Plot).
  3. **Dependency DAG** in the Sequence section (d3-dag sugiyama layout, or Cytoscape with dagre). "If you did three things" is rendered as the highlighted critical path, not as three standalone cards.
  - Keep the stacked bar for the Distribution section (already appropriate).
- **Required interactions** — all three must work:
  1. **URL hash state persistence.** Every filter combination produces a shareable URL (filter chips + tier tabs write to `location.hash`; the page reads it on load).
  2. **Linked brushing.** Clicking a finding in the Friction Map highlights every idea whose `cited_findings` contains it, and dims the rest. Clicking an idea card does the reverse. Implement with a ~20-line vanilla pub/sub bus so Friction and Ideas (potentially far apart in the DOM) can cross-communicate.
  3. **Scroll-spy Table of Contents.** Sticky side or top ToC with "you are here" highlight driven by IntersectionObserver using `rootMargin: '-10% 0px -85% 0px'` for the thin-band trigger. Non-negotiable for a 1,500+ line document.
- **Priority stack default state.** Foundation tier expanded on load. Growth shows the first 2 lines of each card with a "Show more" reveal. Delight is collapsed behind a single reveal affordance. Hierarchy should be visible before any interaction.
- **Epistemic border on every idea card.** Confidence is rendered as a left-border treatment — solid (High), dashed (Med), dotted (Low) — not only as a badge. Still include the badge for screen-reader clarity.
- **Tier color applied consistently.** Foundation/Growth/Delight each get one accent color (from the frontend-design palette) and that color appears on cards, tabs, legend, and chart series. Don't let the Chart.js legend be the only place tiers are color-coded.
- **Dark/light theme toggle** with correct color tokens from the frontend-design palette. For ECharts, read CSS vars via `getComputedStyle(document.documentElement)` at init and on theme change, then pass to ECharts options (ECharts themes are JSON, not CSS-driven).
- **Mobile responsive** at 375px. The bipartite brushing view collapses to per-card chip tags; the DAG collapses to a numbered "what requires what" list; the treemap collapses to a sorted severity list.
- **Accessibility** — skip link first, semantic HTML (`<main>`, `<section>`, `<article>` per idea), `aria-label` on tabs, ARIA live region for brushing announcements ("Idea X cites 3 findings"), `prefers-reduced-motion` disables animations. Every diagram has a textual `<details>` data-table fallback.
- **No placeholder text.** Every word is a real finding, idea, or evidence citation about this specific codebase.

### Library toolkit (CDN includes)

Use these — do not hand-roll chart code from scratch.

```html
<!-- ECharts 6 — primary visualization library. Treemap, Sankey, scatter quadrant,
     force graph, heatmap, chord — all built in. Native dark-mode switching. -->
<script src="https://cdn.jsdelivr.net/npm/echarts@6/dist/echarts.min.js"></script>

<!-- D3 v7 — precision escape hatch for custom layouts (DAG, linked brushing bipartite) -->
<script src="https://cdn.jsdelivr.net/npm/d3@7/dist/d3.min.js"></script>
<!-- d3-dag for sugiyama layout (DAG) -->
<script src="https://cdn.jsdelivr.net/npm/d3-dag@1/dist/d3-dag.iife.min.js"></script>

<!-- Mermaid 11 — upgrade from 10.x. Adds hand-drawn theme, Kanban, Wardley, Venn, ELK. -->
<script type="module">
  import mermaid from "https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs";
  mermaid.initialize({ startOnLoad: true, theme: "base" });
</script>

<!-- Chart.js 4.4 — keep for the Distribution stacked bar. -->
<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4/dist/chart.umd.min.js"></script>

<!-- Cytoscape.js — only if d3-dag proves too finicky for the DAG. -->
<!-- <script src="https://cdn.jsdelivr.net/npm/cytoscape@3/dist/cytoscape.min.js"></script>
     <script src="https://cdn.jsdelivr.net/npm/cytoscape-dagre@2/cytoscape-dagre.js"></script> -->
```

**Ruled out — do not use:** visx, nivo, Excalidraw, tldraw (React-only, no UMD/CDN). roughViz (abandoned April 2024). Perspective.js (requires WASM + asset hosting, breaks single-file constraint). Plotly full bundle (1.4 MB gzipped — use ECharts instead).

### Editorial patterns

These are what separate a competent-looking page from a page that reads as a curated argument:

- **Claim-first titles.** Idea titles are full sentences with a verb, not noun phrases. "Mobile-first SplitView rewrite" → "SplitView breaks on every phone — one-week fix." A reader skimming 15 titles should be able to triage without opening a single card.
- **Evidence in the margin.** On wide viewports, each card uses a Tufte-CSS sidenote pattern — the claim and solution in the main column, the file path + one-line stat in a right margin column. On mobile, evidence collapses to an inline block below the claim. Evidence must be adjacent to the claim, never buried in footnotes.
- **Epistemic status as visual primitive.** Confidence is not just a badge — it is a left-border treatment: solid (strong evidence), dashed (directional signal), dotted (working hypothesis). Readable at a glance, gracefully degrades without color.
- **Tier breaks as scene changes, not headings.** Each tier starts with a full-width typographic break, a one-sentence editorial framing ("These three ideas have the strongest evidence and the lowest effort"), and a compact 3-item overview strip — not just an `<h2>`. The reader enters each tier knowing the editorial argument before seeing the details.
- **Guided argument then explorer.** For decision-maker audiences, optionally precede the full grid with an Executive Summary (top 2 per tier as full cards). Decision-makers skim the summary and stop; analysts scroll to the full filterable grid. Serves both without compromise.
- **Typography hierarchy matches information hierarchy.** The thesis (core insight) must be visually larger or more prominent than the supporting section headers. Never let a decorative element (quote mark, Roman numeral, stat number) be the largest text on the page.

### HTML skeleton

```html
<!DOCTYPE html>
<html lang="en" data-theme="dark">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta name="color-scheme" content="dark light">
  <title>Brainstorm: [repo name]</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <!-- Fonts (frontend-design picks the families), ECharts, D3, d3-dag, Mermaid 11, Chart.js — see Library toolkit above -->
  <style>
    /* Tokens from frontend-design skill (light + dark) */
    /* Reset / base / layout / components / motion */
    /* Tier colors: --tier-foundation, --tier-growth, --tier-delight — used on cards, tabs, chart series */
    /* Epistemic borders: .idea[data-conf="high"] { border-left: 3px solid var(--accent) } etc. */
    @media (prefers-reduced-motion: reduce) {
      *, *::before, *::after {
        animation-duration: 0.01ms !important;
        transition-duration: 0.01ms !important;
      }
    }
  </style>
</head>
<body>
  <a href="#main" class="skip-link">Skip to content</a>
  <nav class="toc" aria-label="Table of contents"><!-- Scroll-spy ToC --></nav>
  <header class="hero"><!-- Title, stats, generated-at --></header>
  <main id="main">
    <section id="summary" hidden><!-- Optional Executive Summary — top 2 per tier --></section>
    <section id="insight"><!-- The reframe, visually distinct --></section>
    <section id="friction"><!-- Treemap first, then finding cards by lens --></section>
    <section id="distribution"><!-- Stacked bar + optional heatmap --></section>
    <section id="ideas"><!-- 2×2 quadrant, then filters, then cards --></section>
    <section id="passports"><!-- Linked-brushing bipartite + top-5 full Passports --></section>
    <section id="sequence"><!-- Dependency DAG with critical path highlighted --></section>
  </main>
  <footer><!-- Generated by, timestamp, cache note --></footer>
  <script>
    // ~20-line pub/sub event bus for cross-chart linked brushing
    const bus = {
      _l: {},
      on(e, fn) { (this._l[e] ??= []).push(fn); },
      emit(e, d) { (this._l[e] ?? []).forEach(fn => fn(d)); }
    };
    // Theme toggle, tier tabs, filter chips (URL-hash persisted),
    // ECharts init with CSS-var palette, D3 DAG, scroll-spy ToC, brushing handlers
  </script>
</body>
</html>
```

### Save and open

Write the file to `~/.brainstorm/` (create the directory if missing). Name it `brainstorm-<repo-name>-<YYYY-MM-DD>.html`.

```bash
mkdir -p ~/.brainstorm
# Save file
open ~/.brainstorm/brainstorm-<repo-name>-<YYYY-MM-DD>.html
```

### Chat response after the file is written

Keep it short. The HTML carries the content. The chat reply should contain only:

1. File path that was written.
2. One-sentence version of the core insight (the same one that leads the HTML).
3. The three "If you did three things" titles as a bulleted list.
4. Nothing else. No re-listing all ideas. The user opens the file for that.

### Quality checklist before delivering

- [ ] Frontend-design skill was invoked BEFORE writing HTML, and its palette/typography/motion guidance is visible in the output
- [ ] Every idea has `cited_findings[]` populated — no idea floats without evidence
- [ ] Top 5 ideas render as full Passports with all 7 fields populated
- [ ] Every finding and every idea has a file path — no ungrounded content
- [ ] At least 1 removal/simplification idea is present and visible
- [ ] Foundation issues appear BEFORE Growth and Delight in the DOM
- [ ] **Treemap** renders in the Friction Map (lens × severity)
- [ ] **Impact × Effort 2×2 quadrant** renders at the Ideas section entry
- [ ] **Dependency DAG** renders in the Sequence section; "three things" shown as critical path
- [ ] **Linked brushing** works bidirectionally (click finding → ideas highlight; click idea → findings highlight)
- [ ] **URL hash state persistence** — filter combinations produce shareable URLs
- [ ] **Scroll-spy ToC** works and follows the reader
- [ ] Idea card titles are claim-first sentences, not noun phrases
- [ ] Confidence rendered as left-border (solid/dashed/dotted), not only as a badge
- [ ] Tier color applied across cards, tabs, and chart series — not only in the legend
- [ ] Core insight (the reframe) is visually distinct from other section headers
- [ ] Dark/light theme toggle works; ECharts re-reads CSS vars on theme change
- [ ] Skip link is the first focusable element
- [ ] `prefers-reduced-motion` disables animations
- [ ] Every diagram has a `<details>` text/table fallback for screen readers
- [ ] Page is readable at 375px width; brushing view collapses to per-card chips; DAG collapses to a numbered list

If any box is unchecked, fix before delivering the path to the user.

---

## NEVER Do These

- **NEVER generate ideas before exploring the codebase.** Ungrounded ideas are "trendslop" — trendy recommendations (add observability, add caching, extract a shared library) that sound authoritative but aren't relevant to THIS repo. This is a property of LLM training distributions, not prompt quality — grounding in actual code is the only fix.

- **NEVER suggest things without checking if they already exist.** "Add error handling for missing config" when the code already handles it at `config.js:23` destroys all credibility. Grep before you suggest. This is the single fastest way to get your entire brainstorm dismissed.

- **NEVER skip the removal/simplification category.** Training data overwhelmingly celebrates what was built, not what was deliberately removed. Without explicit invocation, you will produce only addition ideas. Deletion and simplification are often the highest-value improvements — "remove the 200-line custom retry logic and use the stdlib" is a real idea.

- **NEVER generate ideas that optimize the wrong metric.** The most common brainstorm failure: producing correct solutions to the wrong problem. "Improve CI pipeline speed" when the actual friction is that devs don't understand WHY the pipeline failed. Always trace from user-visible pain backward to root cause, not from code pattern forward to solution.

- **NEVER present transformation-level ideas when the foundation is broken.** "Add a plugin system" is worthless advice to a user whose error messages say "Error: undefined." The Foundation tier exists to enforce this — never bury must-fix issues below exciting redesigns.

- **NEVER suggest adding a dependency for something the standard library handles.** "Add lodash for array filtering" or "add axios for HTTP" in a codebase using built-ins adds maintenance cost for zero user benefit. Always check what's already imported and available before proposing new dependencies.

- **NEVER treat effort as a proxy for impact.** A two-week refactor for "cleaner internal architecture" has zero user-visible impact. A one-line default value change can eliminate every new user's first error. Effort and impact are nearly uncorrelated — every idea must justify its value through user-visible or developer-visible transformation, not engineering elegance.

- **NEVER prescribe unfamiliar technology in a Solution field without evidence it fits.** "Migrate to GraphQL" when the codebase uses REST with zero GraphQL dependencies, or "refactor to event-driven architecture" in a 300-line script, prescribes expertise the team may not have. When solution complexity exceeds what the codebase warrants, write "Research spike needed" — not a confident prescription for territory the code doesn't support.

- **NEVER trust a stale cache for findings about files that changed.** The cache is an optimization, not a source of truth. If `git diff` shows a file changed, re-explore it through all lenses — a one-line change to error handling can flip a Friction finding entirely. Only trust cached findings for files with no diff.

- **NEVER mirror the user's framing uncritically.** If the user describes their project as "a well-structured React app," resist generating only React-ecosystem improvements. The most valuable insight might be "this doesn't need React at all" or "the state management is the bottleneck, not the component library." Challenge the frame when the code warrants it.

- **NEVER use a Sankey diagram for findings → ideas or lenses → ideas.** Sankey's visual grammar implies proportional flow magnitude. The finding-to-idea relationship is categorical (cited / not cited), not quantitative. Rendering it as Sankey implies false precision — "User lens generates 40% of Growth tier" is a statement the data does not support. Use the linked-brushing bipartite overlay instead.

- **NEVER use a chord diagram for the 5×5 lens co-occurrence matrix.** Chord diagrams require the reader to decode arc position + chord width + direction simultaneously. For sparse 5×5 data a heatmap is ~10× more readable for the same information, and a heatmap scales down to mobile. Chord is a chart for dense, high-magnitude bidirectional flows — brainstorm data is neither.

- **NEVER use a force-directed "theme cluster" graph for ideas.** Force layouts require similarity weights between nodes. The brainstorm data has `dependencies` (structural) and `tier`/`level` (categorical) but no semantic similarity. Without weights, the clustering is random positional noise that looks meaningful. Use the dependency DAG (real structural meaning) instead.

- **NEVER use scrollytelling for the full idea list.** Scrollytelling locks reading order. The 15+ ideas in a brainstorm report need random access — the reader wants to jump to the Foundation L1 items, then to the Delight bets. Scrollytelling is only appropriate for the top 2-3 featured ideas where a problem → evidence → solution arc rewards sequential reading.

- **NEVER add decorative visual weight that competes with content for attention.** Particle backgrounds, parallax hero layers, mouse-follower cursors, giant decorative numerals, 180px quote marks — all of these push the thesis of the report down the visual hierarchy. A brainstorm report is a decision document. Ornament that obscures the argument destroys the document's job.

- **NEVER render dependency information as body text when a graph would show it.** "Blocks: G.01 · D.01 · D.04" in 11px monospace is the graph, typeset as text. If a relationship can be drawn, draw it. If the data is a graph, the visualization is a graph.

---

## Adapting to Repo Type

| Repo Type | Signal | Exploration Focus | Idea Emphasis |
|-----------|--------|-------------------|---------------|
| Personal tools/dotfiles | Hardcoded paths, commit msgs like "stuff", no README | Optimize for author's future self who forgot context | Portability, self-documentation, sensible defaults |
| Library/SDK | Public API surface, examples/, README with install | DX layers: discoverability → learnability → productivity | API ergonomics, error messages, missing examples |
| CLI tool | arg parsing, --help, interactive prompts | Entry point, happy path, first failure mode | Composability, machine-readable output, help text |
| Web app | Routes, components, state management | User journeys end-to-end | Performance, error recovery, accessibility |
| Early-stage/prototype | Few files, no tests, rapid changes | What's the core bet? What should NOT be built yet? | Focus over breadth — what's the one thing that matters? |
