# Claude Code `/goal`, `/loop`, Routines, ralph-loop, and Remote Control — in depth (Sept 2026)

## TL;DR

- `/goal` sets a natural-language completion condition; after every turn a small fast model (Haiku by default) reads the transcript and returns **Not yet met / Met / Impossible** — it never runs commands itself, so the condition must be something Claude's own output proves. [PRIMARY, code.claude.com/docs/en/goal.md, fetched 2026-09-04]
- `/goal` is literally implemented as a session-scoped **prompt-based Stop hook**. If Claude answers the evaluator without doing tool work for **8 consecutive turns**, Claude Code force-stops the loop, warns, and hands control back (the goal stays set). This is the general "Stop hook block cap," configurable via `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`. [PRIMARY, goal.md + hooks-guide.md]
- Evaluator tokens are billed on the small/fast model and are "typically negligible" vs. main-turn spend; you can point evaluation at a different model via `ANTHROPIC_DEFAULT_HAIKU_MODEL` (which also affects other background functionality, e.g. summarization). [PRIMARY, goal.md]
- `/loop` re-runs a prompt on a fixed interval or a self-chosen delay (1 min–1 hr) and is session-scoped; it auto-expires after 7 days and stops firing if you close the terminal. Routines are the durable, machine-independent alternative: cloud-run, cron/API/GitHub-triggered, 1-hour minimum interval, no permission prompts (fully autonomous). [PRIMARY, scheduled-tasks.md, routines.md]
- The **official** ralph-loop implementation is the `ralph-wiggum` plugin bundled in Anthropic's own demo marketplace (`anthropics/claude-code`), providing `/ralph-loop "<prompt>" --max-iterations <n> --completion-promise "<text>"` and `/cancel-ralph`, built on the same Stop-hook re-injection mechanism as `/goal`. [PRIMARY, github.com/anthropics/claude-code/tree/main/plugins/ralph-wiggum]
- The technique's originator, Geoffrey Huntley, states flatly he would never run Ralph against an existing codebase ("There's no way in heck would I use Ralph in an existing code base") and that it's for greenfield bootstrapping with fresh, cheap-to-throw-away specs. [PRIMARY-author-source, ghuntley.com/ralph]
- Both the official plugin docs and independent practitioners give the same top failure-mode warning almost verbatim: **"if you aren't careful, Claude will happily burn through all your tokens"** — always set `--max-iterations`, and use `HARD STOP` / human-confirmation checkpoints for steps where errors compound. [PRIMARY + SECONDARY]
- Remote Control (phone/browser control of a **local** session) and Claude Code on the web / cloud sessions (`--cloud`, `--teleport`, Routines) are distinct: Remote Control keeps execution and filesystem access on your machine; cloud sessions run on Anthropic-managed (or self-hosted) VMs with no local access. `/goal` works in both. [PRIMARY, remote-control.md, claude-code-on-the-web.md]
- `/goal` shipped in **Week 20, 2026 (May 11–15, v2.1.139–142)**; self-paced `/loop` shipped **Week 15 (Apr 6–10)**; Routines shipped **Week 16 (Apr 13–17)**. As of Sept 2026 both remain young features with limited independent practitioner literature — most public discussion still centers on the older, community-originated "Ralph Wiggum" pattern rather than `/goal` specifically. [PRIMARY, code.claude.com/docs/en/whats-new + CHANGELOG.md]

## Findings

1. **Claim**: `/goal` sets a completion condition and Claude keeps working, unprompted, until a fresh model verdict says the condition is met, impossible, or an unrecoverable error clears it.
   **Evidence**: "The `/goal` command sets a completion condition and Claude keeps working toward it without you prompting each step. After each turn, a small fast model checks whether the condition holds... The goal clears automatically once the condition is met, if the model judges the condition impossible to satisfy, or if a turn fails on an error you have to fix."
   **URL**: https://code.claude.com/docs/en/goal.md — fetched 2026-09-04. **PRIMARY**. Consensus (official spec).

2. **Claim**: The evaluator only reads what's already in the conversation transcript — it does not run commands or read files independently — so a condition must be something Claude's own output demonstrates (e.g. test output already printed).
   **Evidence**: "The evaluator judges your condition against what Claude has surfaced in the conversation. It doesn't run commands or read files independently, so write the condition as something Claude's own output can demonstrate. 'All tests in `test/auth` pass' works because Claude runs the tests and the result lands in the transcript."
   **URL**: same as above. **PRIMARY**. Consensus.

3. **Claim**: The three verdicts are Not yet met / Met / Impossible, each returned with a short reason visible via Ctrl+O and in `/goal` status.
   **Evidence**: "Not yet met: Claude keeps working... Met: Claude Code clears the goal... Impossible: the evaluator judged that the condition can never be satisfied. Claude Code clears the goal and records a failed entry."
   **URL**: goal.md. **PRIMARY**. Consensus.

4. **Claim**: `/goal` is architecturally a session-scoped prompt-based `Stop` hook, not a separate subsystem.
   **Evidence**: "`/goal` is a wrapper around a session-scoped prompt-based Stop hook. Each time Claude finishes a turn, Claude Code sends the condition and the conversation so far to your configured small fast model, which defaults to Haiku on the Claude API."
   **URL**: goal.md. **PRIMARY**. Consensus.

5. **Claim**: Evaluation model is Haiku by default (on the Claude API; provider default varies for third-party platforms), overridable via `ANTHROPIC_DEFAULT_HAIKU_MODEL`, which also changes the model used for other background functionality (e.g. auto-summarization).
   **Evidence**: goal.md §"Evaluation model and cost" + explicit Warning block: "Claude Code reads `ANTHROPIC_DEFAULT_HAIKU_MODEL` everywhere it uses the small fast model, not only for `/goal` evaluation... and runs background functionality, such as conversation summarization, on it."
   **URL**: goal.md. **PRIMARY**.

6. **Claim**: Evaluation tokens are billed on the small/fast model and are typically negligible next to main-turn spend.
   **Evidence**: "Evaluation tokens are billed on the small fast model configured for your provider and are typically negligible compared to main-turn spend."
   **URL**: goal.md. **PRIMARY**.

7. **Claim**: Force-stop after tool-less turns — if Claude answers the evaluator repeatedly with no tool use for several turns in a row, Claude Code stops the loop, warns, and returns control, with the goal still set (resumes on your next prompt).
   **Evidence**: goal.md: "If Claude keeps answering the evaluator without making progress (no tool use for several turns in a row), Claude Code stops the loop, prints a warning, and returns control to you with the goal still set." Cross-referenced in hooks-guide.md §"Stop hook hits the block cap": "Claude Code overrides a Stop hook after it **blocks eight times in a row** without progress... If your hook legitimately needs more than eight iterations to converge, raise the cap with `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`."
   **URL**: goal.md; hooks-guide.md. **PRIMARY**. The exact number (8) is documented in the general hooks reference, not restated numerically in goal.md itself, but goal.md explicitly says this is "the underlying mechanism."

8. **Claim**: Errors that clear a goal automatically (rather than leaving it active) are limited to four kinds: an auth failure Claude Code itself manages, an exhausted credit balance, a context overflow auto-compaction couldn't clear, or an unavailable model. All other failures (including rate limits/overload) leave the goal active.
   **Evidence**: goal.md §"Errors you have to fix clear the goal." Warning message format is exact: "Goal cleared after an unrecoverable error ... Run /goal again to continue."
   **URL**: goal.md. **PRIMARY**.

9. **Claim**: Background work (subagents, background shell) defers evaluation to the next turn that finishes clean; after 30 minutes of deferral a "check-in" fires, with idle check-ins capped at 3 per goal between prompts (as of ≥ v2.1.246) and backoff doubling up to 4x the base interval, configurable via `CLAUDE_CODE_GOAL_CHECKIN_MINUTES` (0 = off).
   **Evidence**: goal.md §"Background work defers evaluation": "Once background work has kept the goal waiting for 30 minutes, a check-in is due... Claude Code waits twice as long before each later check-in, up to four times the first interval... In the third idle check-in, Claude Code says that idle check-ins are paused until you send another prompt." "Before v2.1.246, idle check-ins were uncapped."
   **URL**: goal.md. **PRIMARY**.

10. **Claim**: You can bound goal runtime yourself by writing a turn/time clause into the condition text (the evaluator, not a hard system cap, enforces it), e.g. `"... or stop after 20 turns"`.
    **Evidence**: "To bound how long a goal runs, include a turn or time clause in the condition, such as `or stop after 20 turns`. Claude reports progress against that clause each turn and the evaluator judges it from the conversation." Max condition length is 4,000 characters.
    **URL**: goal.md. **PRIMARY**. Important nuance: this is a soft, LLM-judged bound, not a hard cap like `--max-iterations` in ralph-wiggum.

11. **Claim**: `/goal`, `/loop`, and Stop hooks are three ways to keep a session running, differing in what starts the next turn and what stops it (comparison table). `/goal` and a Stop hook both fire after every turn; `/goal` is the session-scoped, no-config shortcut, a Stop hook is durable/scriptable across sessions.
    **Evidence**: goal.md comparison table: `/goal` → next turn starts when the previous turn finishes (or a background check-in), stops on Met/Impossible/error/`\`/goal clear\``; `/loop` → next turn starts when a time interval elapses, stops when you stop it or Claude decides it's done; Stop hook → next turn starts when previous turn finishes, stops per your own script/prompt logic.
    **URL**: goal.md. **PRIMARY**.

12. **Claim**: Auto mode and `/goal` are complementary, not overlapping: auto mode approves tool calls within a turn; `/goal` decides whether to start another turn at all.
    **Evidence**: "Auto mode on its own approves tool calls within a single turn but doesn't start a new one... `/goal` adds a separate evaluator that checks your condition after every turn... auto mode removes per-tool prompts, and `/goal` removes per-turn prompts."
    **URL**: goal.md. **PRIMARY**.

13. **Claim**: Good conditions have one measurable end state, a stated check (how Claude proves it, e.g. "npm test exits 0" / "git status is clean"), and constraints on what must not change.
    **Evidence**: goal.md §"Write an effective condition" (verbatim bullets quoted).
    **URL**: goal.md. **PRIMARY**. This is the docs' own worked template for "good" vs implicitly "bad" (vague, unverifiable) conditions.

14. **Claim**: `/goal` works non-interactively (`claude -p "/goal ..."`), running the loop to completion in one invocation; output is silent by default (looks stuck) unless you add `--output-format stream-json --verbose`.
    **Evidence**: goal.md §"Run non-interactively."
    **URL**: goal.md. **PRIMARY**.

15. **Claim**: Resuming a session restores an active goal (condition text carried over, but turn count/timer/token baseline reset); this now works on every resume path including the `--resume` picker, fixed as of v2.1.239 (previously the picker path was excluded).
    **Evidence**: goal.md §"Resume with an active goal."
    **URL**: goal.md. **PRIMARY**.

16. **Claim**: `/goal` requires the same workspace-trust rule as hooks, and is unavailable when `disableAllHooks` is true or `allowManagedHooksOnly` is set — it tells you why rather than silently no-op'ing.
    **Evidence**: goal.md §"Requirements."
    **URL**: goal.md. **PRIMARY**.

17. **Claim**: `/loop` behavior branches on what you supply: interval+prompt → fixed cron schedule; prompt only → Claude dynamically picks a 1-minute–1-hour delay each iteration based on observed state, printing the delay and reason; neither → built-in maintenance prompt (continue unfinished work → tend the branch's PR → cleanup passes) or your own `loop.md`.
    **Evidence**: scheduled-tasks.md tables and prose (verbatim quoted above in TL;DR).
    **URL**: https://code.claude.com/docs/en/scheduled-tasks.md, fetched 2026-09-04. **PRIMARY**.

18. **Claim**: Self-paced `/loop` can be ended by Claude itself calling `ScheduleWakeup` with `stop:true`; if an iteration ends without rescheduling or stopping, Claude Code schedules one fallback wakeup ~20 minutes later and then ends the loop if that also doesn't reschedule.
    **Evidence**: "In self-paced mode, Claude can also end the loop on its own... Claude calls the `ScheduleWakeup` tool with `stop: true`... If an iteration ends without either rescheduling or stopping, Claude Code schedules one fallback wakeup about 20 minutes later and ends the loop when that iteration doesn't reschedule either."
    **URL**: scheduled-tasks.md. **PRIMARY**.

19. **Claim**: Session-scoped `/loop` tasks expire after 7 days, don't survive a closed terminal, don't catch up on missed fires, and are cleared by starting a fresh conversation (but restored on `--resume`/`--continue` if unexpired).
    **Evidence**: scheduled-tasks.md §"Seven-day expiry" and §"Limitations."
    **URL**: scheduled-tasks.md. **PRIMARY**.

20. **Claim**: Scheduling comparison — cloud Routines run without your machine on, persist across restarts, have no local file access (fresh clone), no permission prompts (fully autonomous), 1-hour minimum interval; Desktop tasks need the machine on but keep local file access; `/loop` needs both machine on and an open session, minimum 1-minute interval.
    **Evidence**: scheduled-tasks.md §"Compare scheduling options" table (verbatim).
    **URL**: scheduled-tasks.md. **PRIMARY**.

21. **Claim**: Routines (cloud scheduled agents) are session-independent, run as full autonomous cloud sessions with **no permission-mode picker and no approval prompts during a run**; scope is controlled entirely by which repos/connectors/environment you attach.
    **Evidence**: "Routines run autonomously as full Claude Code cloud sessions: there is no permission-mode picker and no approval prompts during a run... What a routine can reach is determined by the repositories you select, the environment's network access and variables, and the connectors you include."
    **URL**: https://code.claude.com/docs/en/routines.md, fetched 2026-09-04. **PRIMARY**.

22. **Claim**: A routine's fire-time `text` payload (from API trigger or "Run now") is wrapped in a `<routine-fire-payload>` block and explicitly labeled untrusted — Claude won't act on it unless the routine's own saved prompt tells it to reference that block. This is a deliberate prompt-injection defense (before v2.1.213, fire text was even more conservatively treated as an untrusted background notification the session could refuse outright).
    **Evidence**: "The `text` value doesn't reach the routine as a bare message. It arrives wrapped in a `<routine-fire-payload>` block that labels it as untrusted data and tells Claude not to follow instructions inside it unless the routine's own prompt says to."
    **URL**: routines.md. **PRIMARY**.

23. **Claim**: A green "run" status in the routine list only means the session started/exited without infrastructure error — it does **not** mean the task succeeded; you must open the transcript to check.
    **Evidence**: "A green status in the run list means the session started and exited without an infrastructure error. It does not mean the task in your prompt succeeded. Open the run to read the transcript and confirm what Claude actually did."
    **URL**: routines.md. **PRIMARY**. Directly relevant to "agents narrating success" risk — official docs flag this exact failure mode.

24. **Claim**: The official ralph-loop implementation is the `ralph-wiggum` plugin in Anthropic's own demo marketplace repo `anthropics/claude-code` (installed via `/plugin marketplace add anthropics/claude-code`), not part of the curated `claude-plugins-official` marketplace.
    **Evidence**: discover-plugins.md lists the official marketplace's plugin catalog with no `ralph-wiggum` entry; the "demo plugins marketplace" section names `anthropics/claude-code` (`claude-code-plugins`) as a separate, manually-added marketplace "with example plugins that show what's possible with the plugin system." Directory listing of `github.com/anthropics/claude-code/tree/main/plugins` includes `ralph-wiggum` alongside `code-review`, `commit-commands`, `security-guidance`, etc.
    **URL**: https://code.claude.com/docs/en/discover-plugins.md; https://github.com/anthropics/claude-code/tree/main/plugins/ralph-wiggum. **PRIMARY**.

25. **Claim**: `/ralph-loop` command syntax and flags: `/ralph-loop "<prompt>" --max-iterations <n> --completion-promise "<text>"`; `--max-iterations` defaults to unlimited; `--completion-promise` is required and matched by exact string; `/cancel-ralph` stops the loop.
    **Evidence**: plugin README (fetched via GitHub directory view): "Usage: `/ralph-loop "<prompt>" --max-iterations <n> --completion-promise "<text>"`... `--max-iterations <n>` – Stop after N iterations (default: unlimited). `--completion-promise <text>` – Phrase that signals completion (exact string matching)."
    **URL**: https://github.com/anthropics/claude-code/tree/main/plugins/ralph-wiggum (README.md), fetched 2026-09-04. **PRIMARY**.

26. **Claim**: The ralph-wiggum plugin's mechanism is a `Stop` hook (`hooks/stop-hook.sh`) that intercepts Claude's exit attempt and re-feeds the **same, unchanged** prompt every iteration; progress is carried entirely through files/git history, not through prompt mutation.
    **Evidence**: "1. Claude works on the task 2. Claude tries to exit 3. Stop hook blocks the exit 4. Stop hook feeds the SAME prompt back 5. Loop repeats until completion... The prompt never changes between iterations... Claude autonomously improves by reading its own past work."
    **URL**: same repo. **PRIMARY**.

27. **Claim**: The plugin's own documented guidance on when to use / not use it: good for well-defined tasks with clear success criteria, iteration/refinement work with automatic verification (tests/linters), greenfield projects you can walk away from; bad for tasks needing human judgment, one-shot operations, unclear success criteria, or production debugging.
    **Evidence**: README "When to Use Ralph" good/bad lists (quoted verbatim above).
    **URL**: same repo. **PRIMARY**.

28. **Claim**: The Ralph technique's originator (Geoffrey Huntley) states the core loop is literally `while :; do cat PROMPT.md | claude-code ; done`, one task per loop iteration, and warns against using it on an existing/legacy codebase.
    **Evidence**: "There's no way in heck would I use Ralph in an existing code base." Loop structure: "search codebase → implement one feature → run targeted tests → update documentation → commit → refresh task list."
    **URL**: https://ghuntley.com/ralph/, fetched 2026-09-04. **PRIMARY** (author's own site — this is the originating description of the technique the Anthropic plugin is named after). One practitioner's opinion, but it is the canonical source most others (including Anthropic's own plugin) cite/build on.

29. **Claim**: Huntley documents concrete failure modes: non-deterministic ripgrep/search misses causing Claude to wrongly assume something isn't implemented; reward-hacking toward placeholder/stub implementations that merely compile; effective context window degrading well below the advertised limit (he cites ~147–152k of a 200k window) when loops accumulate context; and a single bad/duplicated spec line silently corrupting a month of autonomous work.
    **Evidence**: "DO NOT IMPLEMENT PLACEHOLDER OR SIMPLE IMPLEMENTATIONS. WE WANT FULL IMPLEMENTATIONS" (his mitigation instruction); "the 'real' context window for Claude clips around 147k-152k tokens despite advertised 200k limits"; duplicate keyword definition discovered one month into the CURSED project.
    **URL**: ghuntley.com/ralph. **PRIMARY** (author), **one practitioner's own numbers** — his 147–152k context figure is model/version-specific and not corroborated elsewhere in this research; treat as anecdotal/contested rather than a general spec.

30. **Claim**: Huntley reports the technique's economics can be extreme — one example: a $50,000-scope contract delivered for ~$297 in API spend, but only by combining heavy subagent parallelism (up to ~500 concurrent agents) with the vertical-scaling loop.
    **Evidence**: "$50,000 contract delivered for $297 USD using the technique with Claude." "up to 500 concurrent agents."
    **URL**: ghuntley.com/ralph. **PRIMARY (author's own claim)** — a single anecdote, not a benchmark; presented here as one practitioner's opinion/result, not consensus.

31. **Claim**: Community re-implementations independently converge on the same guardrail vocabulary as the official plugin: hard iteration caps, "backpressure" gates (tests/lint/typecheck) that reject incomplete work before advancing, and an explicit completion token the agent must emit (`LOOP_COMPLETE` in one implementation, `--completion-promise` in the official one) rather than trusting free-text claims of "done."
    **Evidence**: "Ralph iterates until it outputs `LOOP_COMPLETE` or hits the iteration limit." "Backpressure — Gates that reject incomplete work (tests, lint, typecheck)."
    **URL**: https://raw.githubusercontent.com/mikeyobrien/ralph-orchestrator/main/README.md, fetched 2026-09-04. **SECONDARY** (independent community project, not Anthropic). Consensus pattern across implementations, not contested.

32. **Claim**: A community write-up on the ralph-wiggum plugin (published Jan 4, 2026, i.e. before `/goal` shipped) explicitly warns: "If you aren't careful, Claude will happily burn through all your tokens," recommends always setting `--max-iterations`, watching for "error compounding" in workflows with cascading steps, adding `HARD STOP` checkpoints requiring `AskUserQuestion` confirmation for risky steps, and flags that tasks depending on timeouts/rate-limited external services can hang or misbehave across iteration boundaries.
    **Evidence**: quoted verbatim above (Failure Modes & Pitfalls section).
    **URL**: https://looking4offswitch.github.io/blog/2026/01/04/ralph-wiggum-claude-code/, fetched 2026-09-04. **SECONDARY**, one practitioner's write-up, but consistent with the official plugin README's own framing (not contested).

33. **Claim**: A practitioner ran Claude Code in a continuous autonomous loop for 15+ hours building a multi-tenant todo app, producing 118+ commits with minimal intervention, and explicitly credits **end-to-end tests as what kept the agent grounded in reality** during the run.
    **Evidence**: HN Ask thread ("Continuous agents and what happens after Ralph Wiggum?"): "In 15 hours it created a full multi-tenant auth system from scratch and todos with assignees due dates, email reminders, tags and full text search," with end-to-end tests called out as critical.
    **URL**: https://news.ycombinator.com/item?id=46632445 (summarized via HN Algolia API), fetched 2026-09-04. **SECONDARY**, single practitioner anecdote — supports (does not independently prove) the "tests as machine-checkable finish line" pattern; direct comment thread could not be fetched (HTTP 429) so counter-opinions in the thread are a gap.

34. **Claim**: `/goal` shipped in Week 20 of 2026 (May 11–15, v2.1.139–142); self-paced `/loop` shipped Week 15 (Apr 6–10, v2.1.92–101); Routines shipped Week 16 (Apr 13–17, v2.1.105–113); a per-loop token/run breakdown was added to `/usage` in v2.1.243 (mid/late Aug 2026).
    **Evidence**: whats-new digest entries (Week 20: "`/goal` keeps Claude working across turns until a completion condition holds"; Week 15: "`/loop` self-paces when you omit the interval"; Week 16: "Routines on Claude Code on the web fire templated cloud agents from a schedule, GitHub event, or API call"); CHANGELOG v2.1.243: "Added a Loops breakdown to `/usage`: per-loop run count, total tokens, tokens per run, and last run."
    **URL**: https://code.claude.com/docs/en/whats-new; https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md. **PRIMARY**.

35. **Claim**: Remote Control (`claude remote-control` / `--remote-control` / `/remote-control`) is architecturally distinct from cloud sessions: it keeps the session and all filesystem/tool access **on your own machine** and only relays control from phone/browser; it survives laptop sleep/network drops (auto-reconnect, queued messages) but not the machine being off, and is unavailable with Bedrock/Vertex/Foundry, a non-default `ANTHROPIC_BASE_URL`, or several telemetry-disabling env vars.
    **Evidence**: "Unlike Claude Code on the web, which runs on cloud infrastructure, Remote Control sessions run directly on your machine and interact with your local filesystem... Claude Code reconnects automatically when your machine comes back online... `DISABLE_TELEMETRY`, `DO_NOT_TRACK`, `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`, and `DISABLE_GROWTHBOOK` each disable the feature-flag evaluation that Remote Control availability depends on."
    **URL**: https://code.claude.com/docs/en/remote-control.md, fetched 2026-09-04. **PRIMARY**.

36. **Claim**: Cloud sessions (`--cloud`, `--teleport`) are one-directional from CLI: you can pull a cloud session into your terminal with `--teleport` but cannot push a running terminal session to the web from the CLI (only the Desktop app's "Continue in" menu can do that); `--cloud <session-id>` with `-p` queues a fire-and-forget message into an existing cloud session from any machine.
    **Evidence**: "From the CLI, session handoff is one-way: you can pull cloud sessions into your terminal with `--teleport`, but you can't push an existing terminal session to the web... The command posts one message and exits: `claude -p "your message" --cloud <session-id>`."
    **URL**: https://code.claude.com/docs/en/claude-code-on-the-web.md, fetched 2026-09-04. **PRIMARY**.

37. **Claim**: `/goal` explicitly works "in non-interactive mode, in the desktop app, and through Remote Control" — i.e. `/goal` is a supported autonomy primitive across all three "keep working while I'm away" surfaces (headless `-p`, Remote Control, cloud/web).
    **Evidence**: goal.md §"Run non-interactively": "`/goal` works in non-interactive mode, in the desktop app, and through Remote Control."
    **URL**: goal.md. **PRIMARY**.

## Downsides and failure modes

- **Unverifiable / self-reported conditions.** The evaluator "doesn't run commands or read files independently" — it only judges what Claude already put in the transcript. A condition like "the code is clean" or "this looks good" has no way to be grounded; only conditions Claude can *demonstrate* (test output, exit codes, file counts) work reliably. [PRIMARY, goal.md]
- **Agents narrating success without proof.** Anthropic's own Routines docs warn that a green run status "does not mean the task in your prompt succeeded" — you must read the transcript. This is the general-purpose version of the "agent claims done, nothing actually changed" failure mode. [PRIMARY, routines.md]
- **Token/budget burn.** Both the official `ralph-wiggum` README and an independent practitioner write-up single out unlimited iteration as the top risk ("Claude will happily burn through all your tokens" — looking4offswitch.github.io, Jan 2026), which is why `--max-iterations` exists and defaults to *unlimited* unless set. `/goal`'s equivalent bound is a soft, LLM-judged clause in the condition text (e.g. "stop after 20 turns"), not a hard system cap — so a badly-worded goal condition could in principle run far longer than intended, bounded only by the 8-consecutive-no-tool-use force-stop. [PRIMARY, ralph-wiggum README + goal.md; SECONDARY, looking4offswitch]
- **Error compounding / scope drift.** Community guidance recommends inserting `HARD STOP` checkpoints requiring explicit human confirmation (`AskUserQuestion`) at points where a wrong decision cascades into more wrong decisions, and warns that tasks depending on external timeouts/rate limits can hang or misbehave across loop iterations. Huntley separately documents "reward hacking" toward placeholder/stub code that merely compiles, and non-deterministic search tools causing an agent to wrongly re-implement things that already exist. [SECONDARY, looking4offswitch; PRIMARY-author, ghuntley.com]
- **Existing-codebase risk.** The technique's own originator says he would never run it against an existing/legacy codebase — it's designed for greenfield work where a bad spec or stub implementation is cheap to discard, not for systems with complex interdependencies. The official plugin README echoes this ("Not good for: ... Production debugging"). [PRIMARY-author, ghuntley.com; PRIMARY, ralph-wiggum README]
- **Context degradation over long loops.** Huntley's anecdotal finding that effective context clips well below the advertised window (~147–152k of 200k, on the model/version he used) when a loop keeps accumulating context is a single practitioner's own measurement — treat as **contested/anecdotal**, not a documented Anthropic spec; it is not corroborated in the official docs fetched for this report.
- **Prompt injection via routine fire payloads.** Anthropic's own docs treat this as enough of a real risk to build a specific defense: API-triggered `text` payloads for Routines are wrapped in an explicit `<routine-fire-payload>` untrusted-data block, and (before v2.1.213) were rejected outright unless the routine's saved prompt opted in to reading them. This implies Anthropic considers "someone else feeds malicious instructions into your autonomous agent's trigger" a live failure mode for cloud/scheduled autonomy generally. [PRIMARY, routines.md]

## Concrete practices / configs (copy-pasteable)

**1. A `/goal` condition that is machine-checkable (tests green + git clean + artifact exists), with a soft turn cap:**
```text
/goal `npm test` exits 0 in every package under packages/, `git status --porcelain` is empty on branch feature/auth-migration, and CHANGELOG.md has a new entry dated today — or stop after 25 turns and report what's blocking
```
This satisfies the docs' own template: one measurable end state (all three conditions true), a stated check Claude must run and surface (`npm test`, `git status --porcelain`), and an explicit turn-based safety clause the evaluator will judge each turn. [Based on goal.md's "Write an effective condition" guidance — PRIMARY]

**2. Check status / interrupt a runaway goal:**
```text
/goal                 # shows condition, elapsed time, turns evaluated, token spend, evaluator's last reason
/goal clear            # aliases: stop, off, reset, none, cancel
```
[PRIMARY, goal.md]

**3. Run a goal unattended from a script, with visible progress instead of silence:**
```bash
claude -p "/goal all tests in test/auth pass and the lint step is clean" \
  --output-format stream-json --verbose
```
[PRIMARY, goal.md]

**4. Raise/lower the "tool-less turns" force-stop cap (default 8):**
```bash
export CLAUDE_CODE_STOP_HOOK_BLOCK_CAP=12
```
[PRIMARY, hooks-guide.md]

**5. Bound background check-in cadence for goals waiting on long-running work (default 30 min, backs off ×2 up to 4× the base, max 3 idle check-ins between prompts):**
```bash
export CLAUDE_CODE_GOAL_CHECKIN_MINUTES=15   # or 0 to disable check-ins
```
[PRIMARY, goal.md]

**6. Point `/goal` evaluation (and other background small-model use) at a specific model:**
```bash
export ANTHROPIC_DEFAULT_HAIKU_MODEL=claude-haiku-4-5   # example; use your provider's current small/fast model id
```
[PRIMARY, goal.md]

**7. `loop.md` — a durable, project-scoped default for bare `/loop` (self-paced, no hard cost ceiling beyond what you write in):**
```markdown
<!-- .claude/loop.md -->
Check the `release/next` PR. If CI is red, pull the failing job log,
diagnose, and push a minimal fix. If new review comments have arrived,
address each one and resolve the thread. If everything is green and
quiet, say so in one line.
```
Project-level `.claude/loop.md` beats `~/.claude/loop.md`; max 25,000 bytes; edits take effect on the next iteration. [PRIMARY, scheduled-tasks.md]

**8. Fixed-interval `/loop` with an explicit machine-checkable stop condition folded into the prompt itself (since `/loop` has no built-in completion-promise the way ralph-loop does):**
```text
/loop 15m check whether CI is green on main and `git log -1 --format=%H` on main matches origin/main; if both hold for two consecutive checks, say "STABLE" and stop rescheduling
```
[Derived from PRIMARY docs on self-paced `/loop`'s `ScheduleWakeup(stop:true)` mechanism — this pattern is not verbatim in the docs but follows directly from how self-pacing/stopping is documented to work]

**9. The official ralph-loop plugin, with a hard iteration cap and an exact-string completion promise (never omit `--max-iterations`, per both the official README and independent practitioner warnings):**
```text
/plugin marketplace add anthropics/claude-code
/plugin install ralph-wiggum@claude-code-plugins

/ralph-loop "Build a REST API for todos. Requirements: CRUD operations, input validation, tests. When every requirement is met and `npm test` exits 0, output <promise>COMPLETE</promise> and nothing else." \
  --completion-promise "COMPLETE" \
  --max-iterations 50

/cancel-ralph   # to stop early
```
[PRIMARY, ralph-wiggum README, verbatim example adapted]

**10. Track cost after the fact:**
```text
/usage   # includes a "Loops" breakdown as of v2.1.243: per-loop run count, total tokens, tokens/run, last run
```
[PRIMARY, CHANGELOG.md v2.1.243]

**11. When NOT to reach for `/goal` / ralph-loop / Routines at all (synthesized from official plugin guidance + originator's own rule):**
- The success criterion cannot be reduced to something Claude's own tool output proves (visual/UX judgment calls, "does this feel right," ambiguous product decisions) — the evaluator literally cannot check these. [PRIMARY, goal.md]
- You're working against an existing/legacy codebase with complex interdependencies rather than bootstrapping something new — the technique's own originator refuses to use it there. [PRIMARY-author, ghuntley.com]
- Steps where a wrong decision cascades (migrations touching prod data, infra changes, anything non-reversible) — insert `HARD STOP`/`AskUserQuestion` checkpoints instead of full autonomy. [SECONDARY, looking4offswitch; consistent with PRIMARY plugin README's "production debugging" caution]
- You have no budget ceiling in mind — always set an explicit `--max-iterations` (ralph-loop) or a turn/time clause in the goal condition; unlimited is the default and is explicitly called out as the main way people get burned. [PRIMARY, ralph-wiggum README; SECONDARY corroboration]

## Disagreements and open questions

- **Hard cap vs. soft cap philosophy.** The official `ralph-wiggum` plugin gives you a true hard stop (`--max-iterations`, enforced by the plugin's own script/hook), whereas `/goal`'s only built-in hard stop is the generic 8-consecutive-no-tool-use force-stop — a turn/time budget you write into the condition (e.g. "stop after 20 turns") is enforced by the *same LLM evaluator* being asked to judge the substantive condition, not a separate deterministic counter. Whether this soft enforcement is reliable enough for unattended runs is not addressed in the docs and is a legitimate open question this research could not resolve with primary sources.
- **Huntley's ~147–152k effective context figure** is a single author's own measurement on his own long-running project (CURSED) and is not corroborated by Anthropic's docs or any other source found here — treat it as anecdotal, likely model/version-specific, and probably stale for current models as of Sept 2026.
- **Practitioner literature specifically about `/goal`** (as opposed to the older, community-driven "Ralph Wiggum" pattern) is thin as of Sept 2026 — the feature is only ~4 months old at time of writing, and HN/blog search here surfaced almost nothing beyond the doc-announcement itself. Most "what goes wrong" reporting available today is about ralph-style loops generally (plugin- or script-driven), not `/goal`'s LLM-judge mechanism specifically. This should be read as a gap, not as evidence that `/goal` has no failure reports.
- **The 15-hour/118-commit HN anecdote's comment thread** (praise vs. skepticism from other commenters) could not be fetched (HN returned HTTP 429 on repeated attempts) — only the top-level story summary was captured via the Algolia API. Any contrarian voices in that thread are a gap in this report.

## Sources

- [Keep Claude working toward a goal](https://code.claude.com/docs/en/goal.md) — PRIMARY, code.claude.com, fetched 2026-09-04
- [Run prompts on a schedule (`/loop`)](https://code.claude.com/docs/en/scheduled-tasks.md) — PRIMARY, code.claude.com, fetched 2026-09-04
- [Automate work with routines](https://code.claude.com/docs/en/routines.md) — PRIMARY, code.claude.com, fetched 2026-09-04
- [Automate actions with hooks (hooks-guide)](https://code.claude.com/docs/en/hooks-guide.md) — PRIMARY, code.claude.com, fetched 2026-09-04 (Stop hook block cap, prompt-based hooks, agent-based hooks)
- [Continue local sessions from any device with Remote Control](https://code.claude.com/docs/en/remote-control.md) — PRIMARY, code.claude.com, fetched 2026-09-04
- [Use Claude Code on the web](https://code.claude.com/docs/en/claude-code-on-the-web.md) — PRIMARY, code.claude.com, fetched 2026-09-04
- [Discover and install prebuilt plugins through marketplaces](https://code.claude.com/docs/en/discover-plugins.md) — PRIMARY, code.claude.com, fetched 2026-09-04
- [What's new (weekly digest index)](https://code.claude.com/docs/en/whats-new) — PRIMARY, code.claude.com, fetched 2026-09-04
- [Claude Code CHANGELOG.md](https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md) — PRIMARY, GitHub, fetched 2026-09-04
- [`anthropics/claude-code` — `plugins/ralph-wiggum` directory + README](https://github.com/anthropics/claude-code/tree/main/plugins/ralph-wiggum) — PRIMARY, official Anthropic demo-marketplace plugin source, fetched 2026-09-04
- [The Ralph Wiggum Software Engineering Technique](https://ghuntley.com/ralph/) — PRIMARY (author's own site; originator of the technique), fetched 2026-09-04
- [Ralph-Wiggum: Run long, multi-step tasks autonomously with Claude](https://looking4offswitch.github.io/blog/2026/01/04/ralph-wiggum-claude-code/) — SECONDARY, practitioner blog, published 2026-01-04, fetched 2026-09-04
- [Ask HN: Continuous agents and what happens after Ralph Wiggum?](https://news.ycombinator.com/item?id=46632445) — SECONDARY, practitioner anecdote (fetched via HN Algolia API only; full comment thread not accessible, HTTP 429), fetched 2026-09-04
- [`mikeyobrien/ralph-orchestrator` README](https://raw.githubusercontent.com/mikeyobrien/ralph-orchestrator/main/README.md) — SECONDARY, independent community project, fetched 2026-09-04
- Attempted but not usable/found: `jpcaparas.medium.com` post on Ralph Wiggum practitioner usage (HTTP 403, paywalled/blocked); Simon Willison's blog search (no matching posts as of index checked); Google/Bing/DuckDuckGo web search (blocked by consent/CAPTCHA walls when accessed via WebFetch); this session's `WebSearch` tool was already at its 200/200 budget before this task began, so only one WebSearch query executed successfully — all other source-finding was done via WebFetch (GitHub, HN Algolia API, direct doc URLs), which is noted as a methodological gap below.

## Source check (independent)

Re-fetched the six most load-bearing claims (numbers, exact quotes, field/env-var names, attributions) directly from their cited sources on 2026-09-04. All six sources resolved and loaded without redirects or errors, so no WebSearch fallback was needed.

**1. Claim 7 — Stop hook force-stops after 8 consecutive no-progress blocks; raise via `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`.**
Source: https://code.claude.com/docs/en/hooks-guide.md, §"Stop hook hits the block cap".
Exact quote: *"Claude Code overrides a Stop hook after it blocks eight times in a row without progress... If your hook legitimately needs more than eight iterations to converge, raise the cap with `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`."*
**Verdict: CONFIRMED.** Number, mechanism, and env var name all match exactly.

**2. Claim 9 — Background check-in: 30 min first interval, doubles each time up to 4x base, capped at 3 idle check-ins between prompts (cap added v2.1.246), env var `CLAUDE_CODE_GOAL_CHECKIN_MINUTES`.**
Source: https://code.claude.com/docs/en/goal.md, §"Background work defers evaluation".
Exact quote: *"Once background work has kept the goal waiting for 30 minutes, a check-in is due... Claude Code waits twice as long before each later check-in, up to four times the first interval... Claude Code starts at most three idle check-ins per goal between your prompts... Before v2.1.246, idle check-ins were uncapped... To change the first interval, set `CLAUDE_CODE_GOAL_CHECKIN_MINUTES`."*
**Verdict: CONFIRMED.** Every number, the version gate, and the env var name match exactly (doc adds one extra nuance the claim omits: before v2.1.239 only *idle* check-ins backed off — a turn-end check-in used to recur at the flat first interval — and idle check-ins specifically require v2.1.236+; doesn't contradict the claim, just slightly under-specified).

**3. Claim 25 — `/ralph-loop "<prompt>" --max-iterations <n> --completion-promise "<text>"`; `--max-iterations` default unlimited; `--completion-promise` matched by exact string; `/cancel-ralph` stops it.**
Source: https://raw.githubusercontent.com/anthropics/claude-code/main/plugins/ralph-wiggum/README.md (fetched raw, not via GitHub UI).
Exact quotes: *"`/ralph-loop "<prompt>" --max-iterations <n> --completion-promise "<text>"`"*; *"`--max-iterations <n>` - Stop after N iterations (default: unlimited)"*; *"The `--completion-promise` uses exact string matching, so you cannot use it for multiple completion conditions... Always rely on `--max-iterations` as your primary safety mechanism."*; *"/cancel-ralph ... Cancel the active Ralph loop."*
**Verdict: PARTIAL.** Syntax, the unlimited default, exact-string matching, and `/cancel-ralph` all confirmed verbatim. The one embellishment: the claim calls `--completion-promise` "required" — the README never states this explicitly (it's listed as a flag like any other, with no "required" or "optional" marker); this is a reasonable inference from the Quick Start example always including it, not a sourced fact.

**4. Claim 30 — Huntley reports a $50,000-scope contract delivered for ~$297, "combining heavy subagent parallelism (up to ~500 concurrent agents) with the vertical-scaling loop."**
Source: https://ghuntley.com/ralph/ (fetched raw HTML, stripped to text).
Exact quotes: *"From my iMessage (shared with permission) Cost of a $50k USD contract, delivered, MVP, tested + reviewed with @ampcode. $297 USD."* (a tweet Huntley shared, quoting someone else's iMessage to him about a contract done with the Amp tool, not Claude Code, and not Huntley's own project) — and, separately, in the CURSED build prompts: *"You may use up to 500 parrallel subagents for all operations but only 1 subagent for build/tests of rust."*
**Verdict: PARTIAL — misleading link, both underlying numbers real.** Both figures are genuine quotes from the page, but they are unconnected in the source: the $297/$50k anecdote is a third party's result (via a different agentic tool, @ampcode) that Huntley is relaying, with no mention of subagent count; the "500 concurrent agents" figure comes from an unrelated part of the article describing Huntley's own CURSED compiler prompts. The research doc's framing — that the $297 result was achieved "only by combining" the loop "with... up to ~500 concurrent agents" — asserts a causal link the source does not make. Treat the two numbers as separate anecdotes, not one explained result.

**5. Claim 34 — `/goal` shipped Week 20 (May 11–15 2026, v2.1.139–142); self-paced `/loop` shipped Week 15 (Apr 6–10, v2.1.92–101); Routines shipped Week 16 (Apr 13–17, v2.1.105–113); `/usage` Loops breakdown added in v2.1.243.**
Source: https://code.claude.com/docs/en/whats-new (for the three ship dates) and https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md (for v2.1.243).
Exact quotes: Week 20 entry (tags `v2.1.139–v2.1.142`): *"`/goal` keeps Claude working across turns until a completion condition holds"*. Week 15 entry (tags `v2.1.92–v2.1.101`): *"`/loop` self-paces when you omit the interval"*. Week 16 entry (tags `v2.1.105–v2.1.113`): *"Routines on Claude Code on the web fire templated cloud agents from a schedule, GitHub event, or API call"*. CHANGELOG v2.1.243: *"Added a Loops breakdown to `/usage`: per-loop run count, total tokens, tokens per run, and last run, so runaway or chatty `/loop` tasks are easy to spot."*
**Verdict: CONFIRMED.** All three week ranges, date ranges, and version-tag ranges match exactly; the v2.1.243 changelog line matches (with one extra clause the research doc trimmed for brevity, not a distortion).

**6. Claim 10 — Huntley states he would never run Ralph against an existing codebase; the technique is for greenfield bootstrapping.**
Source: https://ghuntley.com/ralph/ (fetched raw HTML, stripped to text).
Exact quote: *"As a final closing remark, I'll say, 'There's no way in heck would I use Ralph in an existing code base' though, if you try, I'd be interested in hearing what your outcomes are. This works best as a technique for bootstrapping Greenfield, with the expectation you'll get 90% done with it."*
**Verdict: CONFIRMED** for the quote and the greenfield framing. Minor embellishment: the research doc's paraphrase "fresh, cheap-to-throw-away specs" is not a phrase Huntley uses anywhere on the page — it's the report's own gloss on the greenfield/"90% done" framing, not a sourced characterization. Doesn't misrepresent his position, just adds color he didn't supply.

### Reliability note
Of the six checked, 4/6 are exact-match CONFIRMED (claims 7, 9, 34, and 10 modulo one unsourced paraphrase), and 2/6 are PARTIAL — both partials are in the Huntley/ralph-wiggum material rather than the official Anthropic docs. The official `code.claude.com` doc citations in this report (goal.md, hooks-guide.md, whats-new, scheduled-tasks.md, routines.md) checked out verbatim on every spot-check, including exact numbers, version gates, and env var names — that source tier looks highly reliable. The two weak spots were both in claim 30 (Huntley's $297/500-agents anecdote): the report silently merged two separate, unconnected facts from the same article into a single causal claim. Treat every other Huntley-sourced anecdote in this report (the ~147–152k context-window figure, the reward-hacking/placeholder-code claims) with similar caution — it is one practitioner's own blog, and this spot-check found the report has a tendency to over-synthesize connections between adjacent-but-separate statements on that page. No claim checked here was outright fabricated or misattributed to the wrong entity.
