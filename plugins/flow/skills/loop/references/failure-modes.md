---
name: failure-modes
description: What goes wrong in unattended loops, how flow loop detects each case, what the log line says, and what to do next. Load when a loop ends in anything but done.
---

# Failure modes — detector, log line, next move

| Failure | Detector in `flow loop` | `loop.log` says | Next move |
|---|---|---|---|
| Premature "done" (the model saw progress and declared victory) | there is no done signal; `check` runs the verifier | `iter` lines keep coming | none — this cannot happen by design |
| Test weakened / deleted / skipped to pass | tamper veto (K-F) | `suspect … test files removed` / `skip/xfail added` | restore; report; do not re-arm until the cause is understood |
| Verifier or gate config edited | cksum of `verify`; tamper regex on `flow.config.json` and lint configs | `suspect … verifier rewritten` / `gate config weakened` | same |
| Stall — nothing changes | fingerprint (HEAD + status + diff) unchanged `stall_after` times | `stop … stall` | the prompt is not producing edits: missing access, unclear task, or an iteration that only reads. Read the last child JSON and LEARNINGS |
| Wedge — files churn, same failure | verify signature identical `stall_after` times with changing fingerprints | `stop … wedge` | a logic bug the model cannot see. Retries saturate after 2–3 rounds (self-repair studies); split the task, add a smaller verifier, or fix it by hand |
| Thrash — A→B→A rewrites | shows up as wedge (same failure) or stall (fingerprint returns to a previous value is not tracked; use the log) | `stop … wedge` | two contradictory constraints in the prompt or two tests that disagree; look for the pair |
| Runaway cost | `max_usd` vs summed `total_cost_usd`; `--max-budget-usd` passed to each child | `stop … budget` | check the iteration JSONs for a child that re-read a huge context; add an ignore or a subagent rule |
| Wall-clock | `max_minutes` | `stop … time` | normal for overnight caps; re-arm in the morning after reading LEARNINGS |
| Iteration cap | `max_iterations` | `stop … cap` | a wedge signal, not a budget: read the last five `iter` lines before re-arming |
| Wrong premise / impossible goal | the model wrote `BLOCKED.md` | `stop … blocked` | read it; it is the model's only honest exit and usually right |
| Child session errors (auth, credits, mode, context overflow) | non-zero exit or `is_error` three times in a row | `error` ×3 then `stop … error` | `flow loop run --dry-run` to see the argv; fix credentials or `--permission-mode` |
| Session-shape loop dies after 8 continuations | Claude Code's 8-consecutive-block cap | last `iter` at 8, no `stop` | expected; `flow loop status`; re-arm as fresh |
| Stale contract from another session | `flow doctor` WARN; `tick` allows on `session_id` mismatch | — | `flow loop stop --reason stale` |
| Corrupt contract | non-numeric fields / empty verify | `loop.md.corrupt` appears | `flow loop stop`; `init` again |
| Context rot inside a session loop | not detected (it is the shape's cost) | quality drops after a few iterations | switch to fresh |
| Reward hacking against visible tests only | not detected locally | green | held-out job in CI on a protected branch; compare pass rates |

## Reading a run

`flow loop log -n 40` prints one line per event: `<utc> <event> iter=<n> head=<before>..<after> verify=<rc> sig=<sig> changed=<0|1> cost=<usd> dur=<s> <note>`. Three patterns tell most stories: `changed=0` repeating (stall), `sig` constant with `changed=1` (wedge), `cost` climbing with `verify` constant (a wedge that is expensive). `.claude/loop/verify.last` is the full last verifier output; `.claude/loop/iterations/NNN.json` is each child's payload (fresh shape).

## Three things that are not failures

- A loop that stops at the cap with real progress in git. Read, `/wrap`, re-arm with a smaller task list.
- A `suspect` on a legitimate test move. Say so in the reply, restore or re-run `flow loop check`, and record the ruling.
- A `blocked` that names a missing decision. That is the loop handing a human gate back, which is the design.
