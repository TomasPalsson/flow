# Wave 1 — primary sources read directly by the orchestrator (2026-09-07)

Every claim below was read verbatim from the cited page or file on 2026-09-07. Local copies: /tmp/loopdocs/.

## Claude Code Stop hook (code.claude.com/docs/en/hooks.md)
- Stop input: `stop_hook_active`, `last_assistant_message`, `background_tasks[]`, `session_crons[]` (from CronCreate, ScheduleWakeup, /loop). "The `stop_hook_active` field is `true` when Claude Code is already continuing as a result of a stop hook. Check this value or process the transcript to avoid blocking on a condition that will never resolve. Claude Code overrides the hook and ends the turn after 8 consecutive blocks."
- Decision: `{"decision":"block","reason":"..."}`; or `hookSpecificOutput.additionalContext` ("Non-error feedback ... shown in the transcript as hook feedback rather than a hook error"; "keeps the conversation going through the same loop protections as decision: block, namely the stop_hook_active input and the 8-consecutive-continuation cap"). Exit 2 routes stderr as the reason.
- "All matching hooks run in parallel." Multiple `additionalContext` values are all delivered. (No documented merge rule for two competing `block` reasons — assume only one reason is shown; design so loop hook and stop-gate do not both block in the same turn, or accept that the loop hook's reason may be dropped.)
- Output strings capped at 10,000 chars; longer output is written to a file and replaced with a preview + path.
- `transcript_path` "may lag the in-memory conversation" — use `last_assistant_message` for the promise check.
- Default command-hook timeout 600 s (Stop not lowered). `statusMessage` spinner text supported. `asyncRewake` wakes Claude on exit 2 from a background hook.
- env-vars.md: `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` "Maximum number of consecutive times a Stop or SubagentStop hook may block ... (default: 8). Set to 0 to disable the cap. Raise this if your hook legitimately needs more iterations to resolve".
- hooks-guide.md §"Stop hook hits the block cap": "Claude Code overrides a Stop hook after it blocks eight times in a row without progress."
- CONSEQUENCE: an in-session Stop-hook loop (ralph-loop plugin shape) gets at most 8 continuations per user prompt unless the cap env var is raised in the launching shell. ralph-loop's `--max-iterations 50` is therefore unreachable in-session with defaults.

## /goal (code.claude.com/docs/en/goal.md)
- "a wrapper around a session-scoped prompt-based Stop hook"; evaluator = small fast model (Haiku default); verdicts Not yet met / Met / Impossible; "It doesn't run commands or read files independently, so write the condition as something Claude's own output can demonstrate."
- Stops on: met, impossible, unrecoverable error (auth, credits, context overflow that auto-compact can't clear, model unavailable), `/goal clear`; "If Claude keeps answering the evaluator without making progress (no tool use for several turns in a row), Claude Code stops the loop".
- Bound with a clause in the condition ("or stop after 20 turns"); condition ≤ 4,000 chars; one goal per session; restored on resume with counters reset; works with `claude -p "/goal ..."`.
- Background work defers evaluation; check-ins at 30 min doubling to 4×; max three idle check-ins per goal.
- Comparison table on the page: /goal (turn ends → evaluator), /loop (time interval), Stop hook (your script/prompt decides).
- Evidence on this machine: `/goal` appears 49× in ~/.claude/history.jsonl; `/ralph-loop` 0×.

## /loop and scheduled tasks (code.claude.com/docs/en/scheduled-tasks.md)
- `/loop 5m <prompt>` fixed interval; `/loop <prompt>` self-paced (ScheduleWakeup, 1 min–1 h, prints delay + reason); bare `/loop` = built-in maintenance prompt or `.claude/loop.md` / `~/.claude/loop.md` (project wins; ≤ 25,000 bytes; edits take effect next iteration).
- Session-scoped; 7-day expiry; fires only while the session is running and idle; `Esc` stops a self-paced loop; `ScheduleWakeup {stop:true}` ends it; a fallback wakeup ~20 min later if an iteration neither reschedules nor stops; `CLAUDE_CODE_DISABLE_CRON=1` disables.
- A scheduled fire only runs skills Claude may invoke on its own.
- Monitor tool preferred over polling when available.

## Headless `claude -p` (cli-reference.md)
- `--max-turns N` (print mode; "Exits with an error when the limit is reached"), `--max-budget-usd` (print mode; subagent spend counts; v2.1.217+ cap enforcement), `--permission-mode auto|acceptEdits|bypassPermissions|...`, `--dangerously-skip-permissions`, `--output-format json|stream-json`, `--json-schema`, `--bare` (skips hooks/skills/CLAUDE.md — NOT wanted for a harness loop), `--continue` skips `-p` sessions in interactive mode, `--resume <id>`, `--name`, `--restricted`.

## Official ralph-loop plugin v1.0.0 (~/.claude/plugins/cache/claude-plugins-official/ralph-loop/1.0.0)
- Stop hook: state file `.claude/ralph-loop.local.md` (YAML frontmatter: active, iteration, session_id, max_iterations, completion_promise, started_at; body = prompt). Session isolation via `session_id`. Self-disarms (`rm` state) on any corrupt/unjudgeable condition. Completion = exact `<promise>TEXT</promise>` in the last assistant text block, compared with `[[ = ]]`. Re-feeds the SAME prompt as `reason`, iteration counter in `systemMessage`. Max iterations 0 = unlimited (default). Reads the transcript (not `last_assistant_message`) — the doc now says the transcript may lag.
- Command frontmatter uses `hide-from-slash-command-tool: "true"` so the model cannot arm it itself; `allowed-tools` restricts to the setup script.
- README: "Not good for: tasks requiring human judgment ... unclear success criteria"; "Always rely on --max-iterations as your primary safety mechanism" because the promise is exact-match and single-valued.
- Weakness for our purposes: exit is a self-reported promise, not a verifier; no cost/time budget; no no-progress detector; same context accumulates (context rot); capped at 8 by the block cap anyway.

## Huntley, "Ralph Wiggum as a software engineer" (ghuntley.com/ralph)
- "Ralph is a Bash loop": `while :; do cat PROMPT.md | claude-code ; done` — FRESH process/context per iteration.
- "watch this to learn why the claude code plugin isn't it" — the author explicitly distinguishes his fresh-context loop from Anthropic's in-session plugin.
- "one item per loop. I need to repeat myself here—one item per loop"; "allocate the stack the same way every loop" (plan @fix_plan.md + specs read first every loop); "approximately 170k of context window to work with ... quality clips at the 147k–152k mark"; "Your primary context window should operate as a scheduler" (subagents do expensive reads).
- Signs: prose guards added when Ralph repeats a mistake ("don't assume not implemented; search first"); tests as back pressure; write the *why* of each test because future loops lack the reasoning; "loop back is everything" (make outputs the agent can evaluate: logs, IR, test output); self-improve AGENT.md with learnings; log discovered bugs to fix_plan.md rather than fixing them now; commit + push when tests pass; "models have been trained to chase their reward function, and the reward function is compiling code" — expect placeholders; run more loops to find them.

## snarktank/ralph (github.com/snarktank/ralph: README.md, ralph.sh, prompt.md)
- "Each iteration is a fresh instance with clean context. Memory persists via git history, progress.txt, and prd.json." Loop: `for i in 1..MAX; claude --dangerously-skip-permissions --print < CLAUDE.md`; exit on `<promise>COMPLETE</promise>` in output; default 10 iterations; archives prior run per branch.
- prompt.md: read prd.json, read progress.txt (Codebase Patterns first), pick highest-priority `passes:false` story, implement ONE, run quality checks, update AGENTS.md with reusable learnings, commit `feat: [ID] - [title]`, set `passes:true`, APPEND to progress.txt (never replace), browser-verify UI stories, promise only when ALL pass.
- "Each PRD item should be small enough to complete in one context window"; "CI must stay green (broken code compounds across iterations)".

## Anthropic Engineering, "Effective harnesses for long-running agents" (anthropic.com/engineering/effective-harnesses-for-long-running-agents)
- Two failure patterns: (1) "tried to do too much at once—essentially to attempt to one-shot the app ... running out of context in the middle"; (2) "a later agent instance would look around, see that progress had been made, and declare the job done."
- Fix: initializer agent (writes feature list JSON with every feature `passes:false`, init.sh, claude-progress.txt, initial commit) + coding agent per session (read progress + git log, run basic e2e smoke, pick ONE feature, implement, verify end-to-end as a user would, commit with descriptive message, update progress file, leave a clean mergeable state).
- "we use strongly-worded instructions like 'It is unacceptable to remove or edit tests'"; JSON chosen because "the model is less likely to inappropriately change or overwrite JSON files compared to Markdown files".
- Compaction alone "isn't sufficient".
