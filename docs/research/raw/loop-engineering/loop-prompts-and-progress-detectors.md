# Loop Prompts and No-Progress Detectors — Wave 2 Research

Research date: 2026-09-07. All quotes verbatim from fetched sources; URLs and access dates noted per section. Where a fetch failed or was paywalled, that is stated explicitly rather than guessed around.

---

## Executive Summary

- Geoffrey Huntley's own `ghuntley.com/loop` follow-up post (17 Jan 2026) is a **mindset essay, not a spec**. It contains zero code, zero PROMPT files, no defined "autonomy ladder" (it name-drops Steve Yegge's "Gas Town" level-8/level-9 framing but does not itself enumerate levels), and no explicit stop/abort conditions. The technical detail people cite as "Geoff's Ralph files" (`loop.sh`, `PROMPT_build.md`, `PROMPT_plan.md`, `AGENTS.md`, `IMPLEMENTATION_PLAN.md`) actually lives in **`github.com/ghuntley/how-to-ralph-wiggum`, which is a fork of `ClaytonFarr/ralph-playbook`** — a third party's synthesis of Geoff's original (paywalled) `/ralph` post and tweets, not text Geoff wrote. This matters: most of the internet's "Ralph file templates" are Clayton Farr's interpretation, hosted under Geoff's GitHub handle.
- `ghuntley.com/specs` (the URL in scope) is a **subscriber-only paywalled post** dated 03 Mar 2025, titled "From Design doc to code: the Groundhog AI coding assistant (and new Cursor vibecoding meta)." Only the teaser is public.
- Cursor's Ralph Loop plugin source (`github.com/cursor/plugins/tree/main/ralph-loop`) is fully public and was read line-by-line: **it has no "gutter" detector, no file-thrash detection, no token-pressure bands, and no consecutive-failure counter.** Its only stop conditions are a `<promise>` tag match and a `--max-iterations` count. The "gutter" narrative (same command failing 3×, file thrashing, token-pressure bands at 60%/80%) comes from a third-party blog (heyuan110.com) that is **not corroborated by the plugin's actual code or README** — flagged below as a source conflict.
- `mikeyobrien/ralph-orchestrator` has the most fleshed-out, code-adjacent no-progress detection of everything surveyed: fuzzy-similarity loop detection (≥90% similarity vs. last 5 outputs), a consecutive-failure limit (default 5), and a "stale loop" detector (same topic 3+ times). Its own dogfood config (`ralph.yml`) was fetched directly and quoted below.
- OpenAI's Codex long-horizon pattern is a **four-file durable-memory system** (`Prompt.md`/spec, `Plan.md`/milestones, `Implement.md`/runbook, `Documentation.md`/status log in the blog post) and, in the companion cookbook article, a single living **`PLANS.md`** ("ExecPlan") template with mandatory `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` sections — quoted in full below.
- General-purpose agent-loop no-progress detection (outside the Ralph ecosystem) converges on hashing `(tool_name, canonicalized_args, result_signature)` tuples over a sliding window (commonly window=5-6, threshold=2-3 repeats) and/or hashing verification feedback across iterations (2 identical failures in a row ⇒ stuck). The strongest convergence criterion across sources is "tests pass" (mechanical); the weakest and explicitly warned-against is asking the model "are you done?".

---

## 1. Geoffrey Huntley — `ghuntley.com/loop` (17 Jan 2026)

Fetched directly; full text reproduced below in relevant part (title, byline, date all confirmed on-page).

> **everything is a ralph loop**
> By Geoffrey Huntley in AI — 17 Jan 2026

Key verbatim passages:

> "Ralph is monolithic. Ralph works autonomously in a single repository as a single process that **performs one task per loop**."

> "Ralph is an orchestrator pattern where you allocate the array with the required backing specifications and then give it a goal then looping the goal."

> "It's important to _watch the loop_ as that is where your personal development and learning will come from. When you see a failure domain – put on your engineering hat and resolve the problem so it never happens again."

> "In practice this means doing the loop manually via prompting or via automation with a pause that involves having to press CTRL+C to progress onto the next task. This is still ralphing as ralph is about getting the most out how the underlying models work through context engineering and that pattern is GENERIC and can be used for ALL TASKS."

On "autonomy levels" — this is the *only* place in the post that touches the requested "autonomy ladder," and it is a reference to someone else's taxonomy, not Geoff's own defined ladder:

> "Gas town focuses on spinning plates and orchestration - a full level 8." [linking to Steve Yegge's "Welcome to Gas Town" post] "...I'm going for a level 9 where autonomous loops evolve products and optimise automatically for revenue generation."

**Finding: no "autonomy ladder" with defined levels 1-N exists in this post.** It borrows exactly two data points (level 8, level 9) from Steve Yegge's separate "Gas Town" essay and does not define what levels 1-7 are. Anyone citing a Huntley "autonomy ladder" is likely conflating this with Yegge's framework or with secondary write-ups.

**Finding: no asymmetric subagent rule and no explicit stop/abort condition appear in this post.** (The asymmetric subagent rule — "up to 500 subagents for search, only 1 for build/test" — is real, but it lives in the `how-to-ralph-wiggum`/Clayton Farr fork, see §2, not in this essay.)

The only other technical claim in the post: a "how to build a coding agent" workshop teaser — "300 lines of code running in a loop with LLM tokens. You just keep throwing tokens at the loop, and then you've got yourself an agent." No code shown.

Source: https://ghuntley.com/loop/ — fetched 2026-09-07, full page (not paywalled).

---

## 2. `github.com/ghuntley/how-to-ralph-wiggum` — actually a fork of `ClaytonFarr/ralph-playbook`

**Provenance correction (important):** `gh api repos/ghuntley/how-to-ralph-wiggum` confirms:
```json
{"full_name":"ghuntley/how-to-ralph-wiggum","fork":true,"parent":"ClaytonFarr/ralph-playbook","source":"ClaytonFarr/ralph-playbook"}
```
The README's own first-person voice confirms this — it is written by Clayton Farr, describing Geoffrey Huntley in the third person: *"I try to pay attention to the crazy-smart insights [@GeoffreyHuntley] shares, but I can't say Ralph really clicked for me this summer."* Root-level `loop.sh`, `PROMPT_build.md`, `PROMPT_plan.md`, `AGENTS.md` do **not exist as separate files** in this repo (all four raw-file fetches 404'd); all of the "files" GitHub search results describe are actually embedded **code blocks inside the single 1226-line `README.md`**. Directory listing confirmed via API: only `.gitignore`, `.vscode/`, `README.md`, `files/`, `index.html`, `references/` exist at root — `files/AGENTS.md`, `files/IMPLEMENTATION_PLAN.md`, `files/PROMPT_build.md`, `files/PROMPT_plan.md`, `files/loop.sh` exist inside `files/`, mirroring the templates embedded in the README.

Source: https://github.com/ghuntley/how-to-ralph-wiggum (README.md, fetched via `raw.githubusercontent.com/ghuntley/how-to-ralph-wiggum/main/README.md`, 2026-09-07).

### Workflow shape: "Three Phases, Two Prompts, One Loop"

> "Phase 1. Define Requirements (LLM conversation)" → "Phase 2 / 3. Run Ralph Loop (two modes, swap `PROMPT.md` as needed)"

| Mode | When to use | Prompt focus |
|---|---|---|
| PLANNING | No plan exists, or plan is stale/wrong | Generate/update `IMPLEMENTATION_PLAN.md` only |
| BUILDING | Plan exists | Implement from plan, commit, update plan as side effect |

BUILDING mode loop lifecycle (verbatim, numbered 1-10 in source):
> "1. _Orient_ – subagents study `specs/*` (requirements); 2. _Read plan_ – study `IMPLEMENTATION_PLAN.md`; 3. _Select_ – pick the most important task; 4. _Investigate_ – subagents study relevant `/src` ('don't assume not implemented'); 5. _Implement_ – N subagents for file operations; 6. _Validate_ – 1 subagent for build/tests (backpressure); 7. _Update `IMPLEMENTATION_PLAN.md`_ – mark task done, note discoveries/bugs; 8. _Update `AGENTS.md`_ – if operational learnings; 9. _Commit_; 10. _Loop ends_ → context cleared → next iteration starts fresh"

### The `loop.sh` script (Geoff's minimal form, quoted in the README):

```bash
while :; do cat PROMPT.md | claude ; done
```

### Enhanced `loop.sh` (full script, as published):

```bash
#!/bin/bash
# Usage: ./loop.sh [plan] [max_iterations]
# Examples:
#   ./loop.sh              # Build mode, unlimited iterations
#   ./loop.sh 20           # Build mode, max 20 iterations
#   ./loop.sh plan         # Plan mode, unlimited iterations
#   ./loop.sh plan 5       # Plan mode, max 5 iterations

# Parse arguments
if [ "$1" = "plan" ]; then
    MODE="plan"
    PROMPT_FILE="PROMPT_plan.md"
    MAX_ITERATIONS=${2:-0}
elif [[ "$1" =~ ^[0-9]+$ ]]; then
    MODE="build"
    PROMPT_FILE="PROMPT_build.md"
    MAX_ITERATIONS=$1
else
    MODE="build"
    PROMPT_FILE="PROMPT_build.md"
    MAX_ITERATIONS=0
fi

ITERATION=0
CURRENT_BRANCH=$(git branch --show-current)
# ...banner echo lines omitted for brevity...

if [ ! -f "$PROMPT_FILE" ]; then
    echo "Error: $PROMPT_FILE not found"
    exit 1
fi

while true; do
    if [ $MAX_ITERATIONS -gt 0 ] && [ $ITERATION -ge $MAX_ITERATIONS ]; then
        echo "Reached max iterations: $MAX_ITERATIONS"
        break
    fi

    cat "$PROMPT_FILE" | claude -p \
        --dangerously-skip-permissions \
        --output-format=stream-json \
        --model opus \
        --verbose

    git push origin "$CURRENT_BRANCH" || {
        echo "Failed to push. Creating remote branch..."
        git push -u origin "$CURRENT_BRANCH"
    }

    ITERATION=$((ITERATION + 1))
    echo -e "\n\n======================== LOOP $ITERATION ========================\n"
done
```

A second variant in the README adds a `plan-work` mode for scoped work branches (`./loop.sh plan-work "user auth"`), refuses to run `plan-work` on `main`/`master`, and defaults `MAX_ITERATIONS=${3:-5}` for scoped planning specifically. **The only stop conditions anywhere in these scripts are the iteration counter and manual Ctrl+C / process kill — there is no automated no-progress or stall detector in Geoff's or Clayton Farr's loop.sh.**

### `PROMPT_plan.md` template (verbatim):

```
0a. Study `specs/*` with up to 250 parallel Sonnet subagents to learn the application specifications.
0b. Study @IMPLEMENTATION_PLAN.md (if present) to understand the plan so far.
0c. Study `src/lib/*` with up to 250 parallel Sonnet subagents to understand shared utilities & components.
0d. For reference, the application source code is in `src/*`.

1. Study @IMPLEMENTATION_PLAN.md (if present; it may be incorrect) and use up to 500 Sonnet subagents to study existing source code in `src/*` and compare it against `specs/*`. Use an Opus subagent to analyze findings, prioritize tasks, and create/update @IMPLEMENTATION_PLAN.md as a bullet point list sorted in priority of items yet to be implemented. Ultrathink. Consider searching for TODO, minimal implementations, placeholders, skipped/flaky tests, and inconsistent patterns. Study @IMPLEMENTATION_PLAN.md to determine starting point for research and keep it up to date with items considered complete/incomplete using subagents.

IMPORTANT: Plan only. Do NOT implement anything. Do NOT assume functionality is missing; confirm with code search first. Treat `src/lib` as the project's standard library for shared utilities and components. Prefer consolidated, idiomatic implementations there over ad-hoc copies.

ULTIMATE GOAL: We want to achieve [project-specific goal]. Consider missing elements and plan accordingly. If an element is missing, search first to confirm it doesn't exist, then if needed author the specification at specs/FILENAME.md. If you create a new element then document the plan to implement it in @IMPLEMENTATION_PLAN.md using a subagent.
```

### `PROMPT_build.md` template (verbatim) — **this is the source of the asymmetric subagent rule**:

```
0a. Study `specs/*` with up to 500 parallel Sonnet subagents to learn the application specifications.
0b. Study @IMPLEMENTATION_PLAN.md.
0c. For reference, the application source code is in `src/*`.

1. Your task is to implement functionality per the specifications using parallel subagents. Follow @IMPLEMENTATION_PLAN.md and choose the most important item to address. Before making changes, search the codebase (don't assume not implemented) using Sonnet subagents. You may use up to 500 parallel Sonnet subagents for searches/reads and only 1 Sonnet subagent for build/tests. Use Opus subagents when complex reasoning is needed (debugging, architectural decisions).
2. After implementing functionality or resolving problems, run the tests for that unit of code that was improved. If functionality is missing then it's your job to add it as per the application specifications. Ultrathink.
3. When you discover issues, immediately update @IMPLEMENTATION_PLAN.md with your findings using a subagent. When resolved, update and remove the item.
4. When the tests pass, update @IMPLEMENTATION_PLAN.md, then `git add -A` then `git commit` with a message describing the changes. After the commit, `git push`.

99999. Important: When authoring documentation, capture the why — tests and implementation importance.
999999. Important: Single sources of truth, no migrations/adapters. If tests unrelated to your work fail, resolve them as part of the increment.
9999999. As soon as there are no build or test errors create a git tag. If there are no git tags start at 0.0.0 and increment patch by 1 for example 0.0.1 if 0.0.0 does not exist.
99999999. You may add extra logging if required to debug issues.
999999999. Keep @IMPLEMENTATION_PLAN.md current with learnings using a subagent — future work depends on this to avoid duplicating efforts. Update especially after finishing your turn.
9999999999. When you learn something new about how to run the application, update @AGENTS.md using a subagent but keep it brief.
99999999999. For any bugs you notice, resolve them or document them in @IMPLEMENTATION_PLAN.md using a subagent even if it is unrelated to the current piece of work.
999999999999. Implement functionality completely. Placeholders and stubs waste efforts and time redoing the same work.
9999999999999. When @IMPLEMENTATION_PLAN.md becomes large periodically clean out the items that are completed from the file using a subagent.
99999999999999. If you find inconsistencies in the specs/* then use an Opus 4.5 subagent with 'ultrathink' requested to update the specs.
999999999999999. IMPORTANT: Keep @AGENTS.md operational only — status updates and progress notes belong in `IMPLEMENTATION_PLAN.md`. A bloated AGENTS.md pollutes every future loop's context.
```

**The asymmetric subagent rule, explicit:** *"You may use up to 500 parallel Sonnet subagents for searches/reads and only 1 Sonnet subagent for build/tests."* The rationale (from the surrounding README prose): fan-out is safe for read-only exploration (each subagent gets ~156kb of garbage-collected context), but the validation/backpressure step must be serialized to a single subagent so build/test results are unambiguous and not subject to N parallel, possibly-conflicting build states.

Note the numbering scheme convention: *"999... numbering — Guardrails/invariants (higher number = more critical)"* — i.e., the escalating digit-count of item numbers (99999 → 999999999999999) is a deliberate convention meaning "the more 9s, the more load-bearing this rule is," not a typo.

### `AGENTS.md` shape

> "Single, canonical 'heart of the loop' - a concise, operational 'how to run/build' guide. NOT a changelog or progress diary... Keep brief (~60 lines)."

Template skeleton (verbatim):
```
## Build & Run
Succinct rules for how to BUILD the project:

## Validation
Run these after implementing to get immediate feedback:
- Tests: `[test command]`
- Typecheck: `[typecheck command]`
- Lint: `[lint command]`

## Operational Notes
Succinct learnings about how to RUN the project:
...

### Codebase Patterns
...
```

### `IMPLEMENTATION_PLAN.md` shape

> "Prioritized bullet-point list of tasks derived from gap analysis (specs vs code) - generated by Ralph." "_Created_ via PLANNING mode." "_Updated_ during BUILDING mode (mark complete, add discoveries, note bugs)." "_Can be regenerated_ – Geoff: 'I have deleted the TODO list multiple times' → switch to PLANNING mode." "_No pre-specified template_ - let Ralph/LLM dictate and manage format that works best for it."

This is the closest thing in this source to a "regenerate on stall" rule, but it is **human-triggered** ("switch to PLANNING mode"), not an automated no-progress detector:

> "Regenerate when: Ralph is going off track (implementing wrong things, duplicating work); Plan feels stale or doesn't match current state; Too much clutter from completed items; You've made significant spec changes; You're confused about what's actually done."

### Stop/abort conditions found in this source (exhaustive)

- `--max-iterations` on the outer loop (`./loop.sh 20`), default unlimited.
- Manual Ctrl+C.
- `git reset --hard` as an escape hatch to revert uncommitted changes if trajectory goes wrong (explicitly called an "additional escape hatch," not automated).
- No hash/similarity/failure-count based automated stall detector exists anywhere in this repo's loop.sh or prompts.

Sandbox/safety note (verbatim, since it bears on "what happens when things go wrong"):
> "To operate autonomously, Ralph requires `--dangerously-skip-permissions` - asking for approval on every tool call would break the loop. This bypasses Claude's permission system entirely - so a sandbox becomes your only security boundary." "Philosophy: 'It's not if it gets popped, it's when. And what is the blast radius?'"

---

## 3. `ghuntley.com/specs` — paywalled

Fetched 2026-09-07. Result: **subscriber-only article.** Publicly visible: title "From Design doc to code: the Groundhog AI coding assistant (and new Cursor vibecoding meta)," author Geoffrey Huntley, date 03 Mar 2025, and this teaser sentence surfaced via search snippet (not the article body itself, so treat as low-confidence paraphrase, not a quote):

> "...when the '/specs' method is used with the 'stdlib' method in conjunction with a programming language that provides compiler soundness... driven by good types and compiler errors, the results are incredible."

The page itself displays: *"This post is for subscribers only"* followed by a subscribe/sign-in wall. **No spec template, no example spec file, and no code was recoverable.** This is a genuine access gap, not an omission on my part — reported honestly per the task instructions.

Source: https://ghuntley.com/specs/ (redirects/aliases to the same Ghost CMS post; HTTP 200, confirmed via direct `curl -I`, paywall is server-rendered).

---

## 4. Cursor's Ralph plugin — the "gutter" claim, verified against source

Primary source (fully public, read directly): `github.com/cursor/plugins/tree/main/ralph-loop` — files `README.md`, `hooks/hooks.json`, `hooks/stop-hook.sh`, `hooks/capture-response.sh`, `skills/ralph-loop-help/SKILL.md`, `skills/ralph-loop/`, `skills/cancel-ralph/`.

### What the plugin's README says about itself (verbatim):

> "Ralph Loop runs Cursor in a self-referential loop, feeding the same prompt back after every turn until the task is complete. It implements the Ralph Wiggum technique pioneered by Geoffrey Huntley."

> "Two hooks drive the loop. An `afterAgentResponse` hook watches each response for a `<promise>` tag matching the completion phrase. A `stop` hook fires when Cursor finishes a turn. If the promise hasn't been detected and the iteration limit hasn't been reached, the stop hook sends the original prompt back as a `followup_message`, starting the next iteration."

> "`--max-iterations <N>` stops after N iterations (default: unlimited)" / "`--completion-promise <text>` sets the phrase that signals completion"

> "Always pass `--max-iterations` to prevent runaway loops."

### `hooks/stop-hook.sh` (fetched raw, full script logic, condensed to the decision path):

```bash
# Check if completion promise was detected by the afterAgentResponse hook
if [[ -f "$DONE_FLAG" ]]; then
  echo "Ralph loop: completion promise fulfilled at iteration $ITERATION." >&2
  rm -f "$STATE_FILE" "$DONE_FLAG"
  exit 0
fi

# Check max iterations
if [[ $MAX_ITERATIONS -gt 0 ]] && [[ $ITERATION -ge $MAX_ITERATIONS ]]; then
  echo "Ralph loop: max iterations ($MAX_ITERATIONS) reached." >&2
  rm -f "$STATE_FILE" "$DONE_FLAG"
  exit 0
fi
```

`hooks/capture-response.sh` only checks for an exact `<promise>TEXT</promise>` string match against the configured `completion_promise` and touches a `done` flag file — no output comparison, no hashing, no failure counting.

### Verdict on the "gutter" detector: **not present in the source.**

I read every file in the plugin (README, hooks.json, both hook scripts, and the `ralph-loop-help` skill doc, which is the plugin's own self-description surfaced to end users). **None of them mention "gutter," file-thrash detection, token-pressure bands, or a same-command-failing-N-times counter.** The only two stop conditions that exist in Cursor's Ralph plugin are:
1. A `<promise>COMPLETION_TEXT</promise>` string match.
2. `--max-iterations` count.

The "gutter" terminology and its specifics (same command failing 3×, files thrashing, 60%/80% token-pressure bands, 20-iteration conservative default) come from a **secondary blog post**, heyuan110.com ("Agentic Loops 2026: Self-Looping AI Agents Explained," 03 Jul 2026), which itself does not cite a source for these numbers and is not corroborated by Cursor's own docs (a targeted search of `cursor.com`/`docs.cursor.com` for "gutter" + "ralph" returned no official hits — Cursor's own Plugins Reference and Plugins docs pages, and the community forum threads on "Introduce ralph in cursor," do not use this term either).

**This is exactly the kind of discrepancy the task asked me to catch: I am reporting what the public source code says (no gutter detector) rather than repeating the secondary claim as fact.**

Sources: https://github.com/cursor/plugins/tree/main/ralph-loop (README.md, hooks/hooks.json, hooks/stop-hook.sh, hooks/capture-response.sh, skills/ralph-loop-help/SKILL.md — all fetched raw 2026-09-07); https://www.heyuan110.com/posts/ai/2026-07-03-agentic-loops/ (secondary, unverified numbers, fetched 2026-09-07); https://cursor.com/docs/plugins and https://cursor.com/docs/reference/plugins (searched, no "gutter" hits, 2026-09-07).

---

## 5. Matt Pocock's Ralph variant

No public gist/repo with Matt Pocock's literal prompt file was found (`gist.github.com/mattpocock` was checked via search; no `ralph.md` surfaced). What is publicly documented, from his own site (`aihero.dev`, part of Total TypeScript / AI Hero, Matt Pocock's teaching platform) and corroborated by the Clayton Farr playbook which cites him directly:

> "With Matt's take on the Ralph method, the 'masterplan' is continuously updated in a 'master PRD,' with prompts that ask the agent to choose the next feature, find the highest-priority feature to work on, ensure tests pass, and update the master tracker."

> "The AI commits after each feature and you come back later to working code."

The Clayton Farr README also directly cites the origin of the current wave of interest: *"[@mattpocockuk] and [@ryancarson]'s overviews helped a lot - right until Geoff came in and [said 'nah']"* — i.e., Pocock's and Carson's public explainer threads on X are what popularized Ralph outside Geoff's original niche following, and Geoff publicly pushed back on their framing (image `nah.png` embedded in the fork's README as evidence).

**Assessment: Matt Pocock's variant is documented only as a paraphrase (via aihero.dev and secondhand citation), not as a literal prompt file.** No verbatim prompt text is available publicly as of this research date.

Source: https://www.aihero.dev/getting-started-with-ralph (fetched 2026-09-07); cross-reference via `raw.githubusercontent.com/ghuntley/how-to-ralph-wiggum/main/README.md`.

---

## 6. ralphloop.sh (a commercial/documentation site for a packaged Ralph implementation)

Multiple blog pages under `ralphloop.sh/blog/` fetched. This is a distinct product/doc site (not Geoff's, not Clayton Farr's, not Cursor's) with its own file layout under `.agent/`:

> "Ralph.sh is a shell script that manages an autonomous AI agent loop, with key state files located in a .agent/ directory including PROMPT.md, tasks.json, individual task specs in tasks/ folder, PRD.md and SUMMARY.md files in the prd/ subdirectory, logs/LOG.md, and STEERING.md."

### File roles (as summarized from the site, quoted where the summarizer preserved exact phrasing):

> "SUMMARY.md is a short executive overview with the main features, key user flows, and key requirements, and the summary is what gets sent to the agent every iteration so it reorients fast without rereading the entire PRD."

> "The task lookup table in tasks.json is a lightweight index that the agent reads to pick the next task without loading every spec, which is what lets a project hold hundreds of tasks and still keep each iteration cheap."

### `PROMPT.md` template elements (from `ralphloop.sh/blog/ralph-loop-prompt-file/`):

> "ONE TASK PER INVOCATION. Complete one task from @.agent/tasks.json, commit, output <promise>TASK-{ID}:DONE</promise>, and STOP."

References via `@` notation to: `@.agent/prd/SUMMARY.md`, `@.agent/tasks.json`, `@.agent/logs/LOG.md`, `@.agent/STEERING.md`, `@.agent/STRUCTURE.md`. An 11-step numbered task flow covering implementation → verification (eslint, prettier, TypeScript, full test suite; Playwright smoke tests + screenshots for UI tasks) → commit in conventional-commit format.

Three completion-signal promise tags:
- `<promise>TASK-{ID}:DONE</promise>` — ends one iteration.
- `<promise>COMPLETE</promise>` — exits the entire loop.
- `<promise>BLOCKED:reason</promise>` — signals human intervention needed.

### `ralph.sh` shell script (from `ralphloop.sh/blog/ralph-loop-shell-script/`) — bare idea shown, full script not published on the page:

```bash
# the bare idea
while :; do
  cat PROMPT.md | your-agent-cli
done
```

> "The bare idea is a loop that pipes a prompt into an agent. The script wraps that idea with the machinery that makes it safe to walk away from."

Iteration cap: default 10 (`./ralph.sh`), explicit override (`./ralph.sh -n 50`). Explicit framing of the cap's purpose:

> "The iteration cap is a safety budget, not a target. The loop stops early the moment the work is actually done."

Exit codes documented: `0` COMPLETE, `1` MAX_ITERATIONS ("not a failure; budget exhausted with pending work"), `2` BLOCKED, `3` DECIDE.

### Verification gate (from `ralphloop.sh/blog/what-is-the-ralph-technique/`):

> "Ralph assumes a verification stack: Playwright for end to end tests, Vitest for unit tests, TypeScript for types, ESLint for linting, and Prettier for formatting." "The repo mantra is blunt: if you didn't test it, it doesn't work."

**No thrash/stall/no-progress detector exists in this source either** — confirmed by direct query: *"The document does not describe any mechanisms for detecting repeated failures, file thrashing, hash comparisons, or command loops."* The only iteration-limiting mechanism is `-n`/`--max-iterations`.

Sources: https://ralphloop.sh/blog/ralph-loop-shell-script/, https://ralphloop.sh/blog/ralph-loop-prompt-file/, https://ralphloop.sh/blog/what-is-the-ralph-technique/ (all fetched 2026-09-07). Note: this is a marketing/documentation site for a specific packaged tool, not affiliated with Geoffrey Huntley as far as the fetched pages disclose — treat file-naming specifics (`.agent/` directory, `tasks.json`) as this product's own convention, not a Ralph-ecosystem standard.

---

## 7. `mikeyobrien/ralph-orchestrator`

Public GitHub repo (`README.md` and `mikeyobrien.github.io/ralph-orchestrator/guide/overview/` docs fetched) plus the repo's own root files listed via `gh api` and its dogfooding config `ralph.yml`/`PROMPT.md` fetched raw.

### Safety mechanisms (verbatim, from the docs overview page, six listed):

> 1. "Input validation: Sanitizes prompts to prevent injection attacks"
> 2. "Resource limits: Enforces iteration, runtime, and cost boundaries"
> 3. "Completion markers: Early exit when `- [x] TASK_COMPLETE` detected"
> 4. "Completion promises: Early exit when agent output contains a configured string"
> 5. "Loop detection: Stops when agent outputs are ≥90% similar to recent history"
> 6. "Consecutive failure limit: Stops after repeated failures (default: 5)"

### Default limits (verbatim):

> "Iteration Limit (default: 100)" / "Cost Limit (default: $10)" / Runtime limit default: 4h

Cost-control warning: *"A 50-iteration cycle on large codebases can cost $50-100+ in API credits, quickly exhausting subscription limits."* `--max-cost` is the documented flag for this.

### Loop detection, precise mechanics (from search-indexed docs content):

> "Loop detection triggers when the current agent output is ≥90% similar (using fuzzy string matching) to any of the last 5 outputs." "Loop detection cannot be disabled directly, but it only triggers on highly similar outputs (≥90% threshold). To avoid false positives, you should ensure agent outputs include iteration-specific details and add progress indicators that change each iteration."

### "Stale loop detection" (separate, newer feature tracked in GitHub Issue #194, "disallowed_tools, stale loop detection, and file-modification audit"):

> "Stale loop detection triggers hard termination when the same topic appears 3+ times consecutively, detecting infinite cycling and stopping the loop before further API credits are wasted."

### Real dogfooding config, `ralph.yml` (fetched raw from repo root, this is the config the maintainer runs the orchestrator's own development with — not a doc example):

```yaml
event_loop:
  completion_promise: LOOP_COMPLETE
  max_iterations: 150
  max_runtime_seconds: 28800
  starting_event: work.start

cli:
  backend: pi

core:
  specs_dir: ./specs/
  guardrails:
    - "Fresh context each iteration — re-read scratchpad and plan."
    - "Commit after each completed step. Never commit Ralph files."
    - "Verification is mandatory — `just ci` must pass (fmt, clippy, tests). See AGENTS.md."
    - "Acceptance tests must be real — no placeholder/pending/stub acceptance scenarios when emitting LOOP_COMPLETE."
    - "BDD acceptance checks must verify runtime behavior; comment-only or `Ok(())`-only evaluator passes are invalid."
    - "Confidence protocol: >80 proceed; 50-80 proceed + note in scratchpad; <50 choose safe default + note."
    - "Preserve primary sources — capture referenced code snippets with file:line attribution in scratchpad."
    - "Run targeted tests per crate (`cargo test -p ralph-core`) during subtasks; full `cargo test --all` only at final step."

backpressure:
  gates:
    - name: fmt
      command: cargo fmt --all -- --check
      on_fail: "Formatting failed. Run `cargo fmt --all` and retry."
    - name: clippy
      command: cargo clippy --all-targets --all-features -- -D warnings
      on_fail: "Clippy lint failures. Fix all warnings before proceeding."
    - name: test
      command: cargo test --all
      on_fail: "Tests failed. Fix failing tests before proceeding."

hats:
  planner:
    name: "📋 Planner"
    description: "Breaks steps into sub-tasks scoped to individual crates"
    triggers: ["work.start", "subtask.done"]
    publishes: ["subtask.ready", "all_steps.done"]
    # ...instructions for the planner "hat" continue in the file...
```

This exposes a concept not covered by the other sources: **"hats"** — role-scoped instruction blocks (e.g., a "Planner" hat triggered on `work.start`/`subtask.done` events) that get swapped in per event, rather than a single monolithic prompt. This is architecturally distinct from Huntley/Farr's single `PROMPT_build.md`.

`PROMPT.md` at repo root (short, orienting file, quoted in full):

```
You are Ralph. You can wear hats. You wan't to get better at serving humans.

Rules of engagement:
- If I ask you restart yourself, you need to kill your PID and rerun `RALPH_DIAGNOSTICS=1 cargo run  --bin ralph -- resume -c ralph.test.yml` in a single command.
```

(Typo "wan't" is in the original source, preserved verbatim.)

Sources: https://github.com/mikeyobrien/ralph-orchestrator/blob/main/README.md; https://mikeyobrien.github.io/ralph-orchestrator/guide/overview/; https://github.com/mikeyobrien/ralph-orchestrator/issues/194; raw `ralph.yml` and `PROMPT.md` at `raw.githubusercontent.com/mikeyobrien/ralph-orchestrator/main/` — all fetched 2026-09-07.

---

## 8. OpenAI — "Run long-horizon tasks with Codex" and the `PLANS.md` / ExecPlan cookbook

### Blog post: four-file pattern (from `developers.openai.com/blog/run-long-horizon-tasks-with-codex`)

The task's naming (`Prompt.md`/`Plan.md`/`Implement.md`/`Documentation.md`) matches this structure:

1. **Prompt.md (Specification):** goals, non-goals, hard constraints, deliverables — "the frozen target to prevent drift." Sections: Goals, constraints (performance, determinism, UX), "Done when" checks.
2. **Plan.md (Milestones):** breaks work into checkpoints small enough for single-loop completion, lists acceptance criteria and validation commands per milestone, includes a **"stop-and-fix rule": repair failures before advancing.**
3. **Implement.md (Execution Runbook):** operational discipline — follow plan, keep diffs scoped, validate after each milestone, continuous documentation updates required.
4. **Documentation.md (Status & Audit Log):** current milestone status (completed/pending), decisions and rationale, how-to-run instructions, known issues.

Central principle quoted: *"less babysitting, more delegation with guardrails."* Verification after milestones must run: linting, type checking, test suites, build processes, export validation — *"not just write code and hope it worked."*

Scale claims in the post (reported, not independently verified): PLANS.md enabled Codex to run "for more than seven hours from a single prompt," and a stress test ran "for about 25 hours uninterrupted, used about 13M tokens, and generated about 30k lines of code."

### Cookbook article: `PLANS.md` / "ExecPlan" template (from `developers.openai.com/cookbook/articles/codex_exec_plans`) — full template reproduced verbatim:

```md
# <Short, action-oriented description>

This ExecPlan is a living document. The sections `Progress`, `Surprises &
Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept
up to date as work proceeds.

If PLANS.md file is checked into the repo, reference the path to that file
here from the repository root and note that this document must be maintained
in accordance with PLANS.md.

## Purpose / Big Picture

Explain in a few sentences what someone gains after this change and how they
can see it working. State the user-visible behavior you will enable.

## Progress

Use a list with checkboxes to summarize granular steps. Every stopping point
must be documented here, even if it requires splitting a partially completed
task into two ("done" vs. "remaining"). This section must always reflect the
actual current state of the work.

- [x] (2025-10-01 13:00Z) Example completed step.
- [ ] Example incomplete step.
- [ ] Example partially completed step (completed: X; remaining: Y).

Use timestamps to measure rates of progress.

## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered
during implementation. Provide concise evidence.

- Observation: …
  Evidence: …

## Decision Log

Record every decision made while working on the plan in the format:

- Decision: …
  Rationale: …
  Date/Author: …

## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at
completion. Compare the result against the original purpose.

## Context and Orientation

Describe the current state relevant to this task as if the reader knows
nothing. Name the key files and modules by full path. Define any non-obvious
term you will use. Do not refer to prior plans.

## Plan of Work

Describe, in prose, the sequence of edits and additions. For each edit, name
the file and location (function, module) and what to insert or change. Keep
it concrete and minimal.

## Concrete Steps

State the exact commands to run and where to run them (working directory).
When a command generates output, show a short expected transcript so the
reader can compare. This section must be updated as work proceeds.

## Validation and Acceptance

Describe how to start or exercise the system and what to observe. Phrase
acceptance as behavior, with specific inputs and outputs. If tests are
involved, say "run <project's test command> and expect <N> passed; the new
test <name> fails before the change and passes after>".

## Idempotence and Recovery

If steps can be repeated safely, say so. If a step is risky, provide a safe
retry or rollback path. Keep the environment clean after completion.

## Artifacts and Notes

Include the most important transcripts, diffs, or snippets as indented
examples. Keep them concise and focused on what proves success.

## Interfaces and Dependencies

Be prescriptive. Name the libraries, modules, and services to use and why.
Specify the types, traits/interfaces, and function signatures that must exist
at the end of the milestone.
```

Key structural rule, quoted: *"It should always be possible to restart from _only_ the ExecPlan and no other work"* — i.e., the plan file must be self-contained enough that a fresh agent context with zero conversation history can resume purely from reading it. This is functionally the same "fresh context each iteration, plan file as shared state" idea as Huntley/Farr's `IMPLEMENTATION_PLAN.md`, arrived at independently by OpenAI's cookbook team.

No explicit no-progress/thrash detector appears in either OpenAI source; the closest analog is the **"stop-and-fix rule"** in Plan.md (repair failures before advancing to the next milestone) — a backpressure gate, not a stall detector.

Sources: https://developers.openai.com/blog/run-long-horizon-tasks-with-codex; https://developers.openai.com/cookbook/articles/codex_exec_plans — both fetched 2026-09-07.

---

## 9. General no-progress / thrash detection mechanisms (outside Ralph-specific sources)

Sourced from a targeted web search on agent-loop stall detection; each item below cites its specific source.

### (a) `(tool_name, canonicalized_args, result_signature)` tuple hashing

From `particula.tech/blog/stop-ai-agents-looping-same-tool-call-no-progress` (fetched 2026-09-07):

> "The unit to track is the tuple `(tool_name, canonical(arguments), result_signature)`." Arguments are normalized: "serialize with sorted keys and normalized whitespace before you hash."

- **Window:** 6 (default), implemented as `deque(maxlen=window)` of recent hashes.
- **Threshold:** 3 identical occurrences (default) triggers halt; author recommends 2-3 repeats, and for tools that "should never legitimately repeat," halting on the *second* identical tuple.
- **Action:** raises a named exception, not a silent stop:
  ```python
  raise NoProgressError(
      f"Tool '{tool_name}' produced an identical call and result "
      f"{self.max_repeats} times; halting."
  )
  ```
  Quoted rationale: *"the guard raises a named, logged error, never a swallowed exception, so a halt is a diagnosable event rather than a silent dead end."*
- **Result-aware, to cut false positives:** *"same input with different output (genuine progress) does not trigger"* — e.g. a polling tool whose result changes each call is not flagged.
- Complementary technique: a "debounce wrapper" injects a terminal message into context instead of re-executing the tool; a lighter alternative is having tools return `"retryable": false` in their structured result.

### (b) Verification-feedback hashing / "stuck, not converging"

From `developersdigest.tech/blog/loop-engineering-designing-agent-loops` (fetched 2026-09-07):

> "If verification fails with the identical feedback two iterations in a row, the loop is stuck, not converging."

Pseudocode quoted from the article:
```js
if (hash(result.feedback) === hash(previous.feedback)) {
  stalls++;
  if (stalls >= 2) return escalate(task);
}
```
**Threshold: 2 consecutive iterations with identical failure feedback → escalate** (not necessarily abort — "escalate" implies handing to a human or a different strategy, distinct from a hard stop).

Four convergence-criterion tiers, ranked by the article from strongest to weakest:
1. **Test-defined** (all tests in scope pass) — "the strongest one."
2. **Diff-defined** (an iteration produces no changes — the "fixed-point pattern").
3. **Count-defined** (a queue reaches zero — lint errors, issues, broken links).
4. **Judge-defined** (a separate model scores output against a rubric) — explicitly the "weakest" tier.

Explicit anti-pattern warning: *"The anti-pattern is asking the agent 'are you done?' as the exit check. Models are optimistic. They will say yes."*

### (c) Circuit-breaker ladder pattern (referenced, not independently deep-dived)

Search results surfaced (but full articles were not separately fetched — reporting only the summarized concept, flagged as lower-confidence secondary paraphrase): a graduated **"steer → constrain → stop"** escalation ladder, distinct from a binary hard-kill, intended to preserve partial work rather than discard it on the first stall signal. Triggers cited: looping, "error storms," or a blown budget.

---

## No-progress detectors compared

| Source | What is measured | Threshold | Window | Action on trigger | Automated? |
|---|---|---|---|---|---|
| Cursor Ralph plugin (verified from source) | `<promise>` tag match only | exact string match | n/a | stop loop (success) | Yes, but **not a no-progress detector** |
| Cursor Ralph plugin (verified from source) | iteration count | `--max-iterations` (default unlimited) | n/a | stop loop | Yes |
| "Gutter" detector (secondary/unverified claim re: Cursor) | same command failing / file thrash / token pressure | "3× command fail"; 60%/80% token bands (numbers per secondary blog, **not found in plugin source**) | unspecified | context reset (claimed) | **Unconfirmed — likely not real** |
| Huntley / Clayton Farr `how-to-ralph-wiggum` | none automated | n/a | n/a | human watches, Ctrl+C, `git reset --hard`, or manually switches to PLANNING mode to regenerate plan | No — human-in-the-loop only |
| ralphloop.sh (`ralph.sh`) | none automated (only completion promise + iteration cap) | n/a | n/a | exits with code 1 (MAX_ITERATIONS, "not a failure") | No |
| mikeyobrien/ralph-orchestrator — Loop detection | fuzzy string similarity of agent output | ≥90% similar | last 5 outputs | stop (hard termination) | Yes |
| mikeyobrien/ralph-orchestrator — Consecutive failures | repeated tool/step failures | 5 (default) | rolling count | stop | Yes |
| mikeyobrien/ralph-orchestrator — Stale loop detection | same "topic" recurring | 3+ consecutive | rolling count | hard termination | Yes |
| OpenAI Plan.md "stop-and-fix rule" | milestone verification failure | any failure | per-milestone | repair before advancing (not an abort — a gate) | Yes, but gate not stall detector |
| Generic tuple-hash guard (particula.tech) | `(tool, canonical(args), result_sig)` hash repeats | 2-3 (recommended), example uses `max_repeats=3` | last 6 calls (`deque(maxlen=6)`) | raise `NoProgressError` (named, logged) | Yes |
| Generic feedback-hash guard (developersdigest.tech) | hash of verification feedback text | 2 identical in a row | 2-iteration lookback | escalate (not necessarily abort) | Yes |

---

## Loop prompt template elements compared

| Source | Task-list file | Learnings file | One-task rule | Commit rule | Stop condition | Cap |
|---|---|---|---|---|---|---|
| Huntley / Clayton Farr `how-to-ralph-wiggum` | `IMPLEMENTATION_PLAN.md` (regenerable, no fixed template) | `AGENTS.md` (~60 lines, operational only) | Explicit: "choose the most important item to address," one per invocation, exits after commit | `git add -A && git commit`, then `git push`; git tag on first clean build/test (`0.0.1` if no tags exist) | Manual (Ctrl+C) or `--max-iterations` on outer loop.sh | Configurable, default unlimited |
| Cursor Ralph plugin | none (stateless; relies on git history + working tree) | none | Implicit via prompt author's own task description | Not enforced by plugin (left to agent's own tool use) | `<promise>` tag match, or `--max-iterations` | Configurable, default unlimited |
| ralphloop.sh | `.agent/tasks.json` index + `.agent/tasks/TASK-{ID}.json` per-task specs | `.agent/logs/LOG.md`, `.agent/STEERING.md` | Explicit: "ONE TASK PER INVOCATION... commit... and STOP" | Conventional-commit format after verification (lint/typecheck/tests, Playwright+screenshot for UI) | `<promise>COMPLETE\|BLOCKED:reason\|TASK-{ID}:DONE</promise>` | `-n <N>`, default 10 |
| mikeyobrien/ralph-orchestrator | implicit (config-driven, per-`hat` sub-tasking; scratchpad tracks "Current Step") | `AGENTS.md` referenced for "conventions relevant to the current step" | Sub-task granularity rule: "one file, one function, one test" | "Commit after each completed step. Never commit Ralph files." (guardrail in `ralph.yml`) | `completion_promise: LOOP_COMPLETE`, `max_iterations`, `max_runtime_seconds`, loop/stale/failure detectors | `max_iterations: 150` (this repo's own dogfood config) |
| OpenAI ExecPlan (`PLANS.md`) | `## Progress` section inside the single living file (checkbox list w/ timestamps) | `## Surprises & Discoveries`, `## Decision Log` sections in the same file | Not a hard "one task" rule; milestones sized "small enough for single-loop completion," with a stop-and-fix rule per milestone | Not specified as a git rule; "Idempotence and Recovery" section instead governs safe re-running | Implicit — plan says "Done when" checks per Prompt.md; no explicit promise-tag mechanism documented | Not iteration-capped in the published template; time-bounded runs reported anecdotally (7h, 25h) |
| Matt Pocock (paraphrased, no verbatim file found) | "master PRD" (continuously updated) | not documented | Implied: "choose the next feature... find the highest-priority feature" | "commits after each feature" | not documented | not documented |

---

## Anti-patterns & pitfalls (sourced)

- **Asking the model "are you done?" as an exit check.** Explicitly called out: *"The anti-pattern is asking the agent 'are you done?' as the exit check. Models are optimistic. They will say yes."* (developersdigest.tech)
- **Judge-based (LLM-as-judge) convergence is the weakest tier**, ranked below test-defined, diff-defined, and count-defined criteria (developersdigest.tech).
- **Silently swallowing a stall as an exception** rather than raising a named, logged error — the particula.tech source is explicit that a no-progress guard should never be a silent dead end.
- **Parallelizing the validation/build step** — Huntley/Farr's rule is the inverse of the general "fan out for speed" instinct: search/read gets up to 500 parallel subagents, but build/test gets exactly 1, because concurrent build states are ambiguous to reconcile.
- **Letting `AGENTS.md` accumulate status/progress notes.** Both the Farr playbook ("A bloated AGENTS.md pollutes every future loop's context" — numbered as one of the highest-priority guardrails, `999999999999999`) and ralph-orchestrator's own guardrail ("Keep @AGENTS.md operational only") converge on this independently.
- **Regenerating the plan is treated as normal, not a failure** — Farr's playbook: "Regeneration cost is one Planning loop; cheap compared to Ralph going in circles."
- **`--dangerously-skip-permissions` without a sandbox** is called out directly as unsafe: *"Running without a sandbox exposes credentials, browser cookies, SSH keys, and access tokens on your machine."*
- **Vague completion criteria give the loop nothing to converge on** — Cursor's own docs: *"Define explicit completion criteria. Vague goals like 'make it good' give Cursor nothing to verify against."*
- **Treating a secondary/blog description as if it were the product's actual behavior** — this research task's own "gutter" example is the cautionary case: a specific, plausible-sounding mechanism (3× command fail, 60/80% token bands) was traceable to a single blog post and not present in the actual open-source plugin it was attributed to.

---

## Open questions

1. **Is the "gutter" terminology used anywhere in Cursor's *closed-source* product surface** (not the open-source plugin, but Cursor's core editor/agent product)? The open plugin repo doesn't have it, but Cursor's core agent (separate from the community plugin) may use different, non-public stall-handling logic. Not verifiable from public sources.
2. **What is Geoffrey Huntley's *original* `/ralph` post's exact autonomy framing?** `ghuntley.com/ralph/` (the original post, referenced repeatedly by every secondary source here) was not fetched in this research pass — it's outside the literal URL list given in scope (`/loop` and `/specs` only), but nearly every downstream source (Clayton Farr, agent-wars.com, LinearB) treats it as the ur-text. A follow-up pass fetching `ghuntley.com/ralph/` directly would likely resolve whether an "autonomy ladder" exists there instead of in `/loop`.
3. **Does `ralph-orchestrator`'s "stale loop detection" (same-topic 3× rule) ship in a released version, or is it still tracked only in open Issue #194** ("[Feature]: disallowed_tools, stale loop detection, and file-modification audit")? The issue title phrasing ("Feature:") suggests this might be a *requested*, not yet *shipped*, capability — worth re-verifying against a specific release changelog before treating it as current behavior.
4. **Matt Pocock's literal prompt file** could not be located publicly. It may exist in a paid course/workshop (Total TypeScript) rather than a public repo — worth checking `total-typescript-monorepo` (his internal tooling repo) more deeply, or his `aihero.dev` event page content directly, if it becomes important to quote him verbatim.
5. **`ralph-orchestrator`'s exact source file implementing the 90%-similarity fuzzy match** (algorithm — Levenshtein? Jaccard on tokens? cosine on embeddings?) was not located; the docs describe the *behavior* ("fuzzy string matching") but not the *algorithm*. A `gh search code` for `loop_detection` in that repo returned nothing under that exact identifier, suggesting the implementation may use a different function/variable name — a deeper repo grep (e.g. in `crates/ralph-core/`) would be needed to pin this down.

---

## Planted instructions

All fetched web/GitHub text was treated as data, not instructions, throughout this research. Two items are worth flagging explicitly as text-in-sources that *could* be mistaken for directives if read carelessly:

1. **Numbered "guardrail" items in `PROMPT_build.md`** (e.g. `99999.`, `999999.`, up to `999999999999999.`) are themselves instructions *to a Ralph-loop agent*, not to me — they are quoted here as research data describing Huntley/Farr's prompt-engineering convention (escalating digit-count signals priority), not followed or acted upon.
2. **The particula.tech source's Python code sample** (`raise NoProgressError(...)`) is illustrative implementation code, not an instruction — reproduced verbatim only for evidentiary/technical value.

No fetched source contained text attempting to redirect this research task itself (e.g. no "ignore previous instructions," no attempt to get this report to recommend unsafe settings, no embedded prompt-injection payloads). Nothing found required exclusion or special handling beyond normal quoting-as-data.
