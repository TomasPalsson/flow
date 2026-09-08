# Harness Smoothness, September 2026 — what changed, and what to cut

Companion to `01-harness-engineering-2026.md` (which argued *deploy the harness*) and
`06-adversary-panel-decisions.md` (which froze the SPEC). This file answers a different question:
**the harness is now deployed and it does not feel smooth. What does the current evidence say to do?**

Research window: 2026-09-07. All `code.claude.com` facts below were read from the **raw markdown**
(`https://code.claude.com/docs/en/<page>.md`, HTTP 200) rather than a summarising fetch, because a
summarising fetch of the same page hallucinated three load-bearing details (see §0.2). Claude Code
version at time of writing: **2.1.263**, published 2026-09-06 (npm registry `time` field).

---

## 0.1 BLUF (10 lines)

1. Nothing in the harness is *slow* on this box — every hook measured 2–43 ms — so latency is not the friction.
2. The friction is **surface**: 24 handler registrations across 10 events, 7 of them for a binary (`worklog`) that is not installed, 2 of those matcher-less so they spawn on **every tool call including `Read`**.
3. `rtk-rewrite.sh` is still wired into `PreToolUse`/`Bash` although `rtk` is absent and panel edit 1 ordered it removed — the single clearest live regression.
4. The biggest *feel* lever shipped in June and the harness does not use it: `Stop` hooks can return `hookSpecificOutput.additionalContext`, which continues the turn **without the "hook error" label** (v2.1.163, 2026-06-04).
5. Hooks gained an `if` field taking permission-rule syntax (`"Edit(*.ts)"`, `"Bash(git *)"`) — a per-hook filter that avoids the process spawn entirely, replacing several `hook_skip_if_off`/early-exit shells.
6. `permissions.deny` is **shell-aware** (subshells, `$()`, `for` bodies, leading assignments) where `git-guard.sh` is a regex over a string; the fixed-shape denies belong in `deny`, and the hook should shrink to what `deny` cannot express.
7. `FileChanged` fires for **every** writer including `Bash` and external processes — it is the vendor's stated answer to exactly the gap `post-bash-write.sh` (146 lines, on every Bash call) was built to close.
8. Boris Cherny's own format hook ends in `|| true`; `format-lint.sh` exits 2 on formatter failure. Format-on-edit is still endorsed, **blocking on it is not**.
9. `/skill-doctor` shipped two days ago (v2.1.261, 2026-09-04) and reports which listed skills have never been invoked and what each costs — the measurement doc 01 said did not exist.
10. Consensus across Anthropic, Cherny, HumanLayer and one public harness post-mortem: the win comes from **deleting**, and every deletion should be a testable ablation, not a vibe.

## 0.2 What I could not verify, and one correction to make loudly

- A summarising `WebFetch` of `code.claude.com/docs/en/hooks` returned a **fabricated** Stop-hook contract: block cap "default 5", a `"forceOverride": true` field, and a `permissionDecision: "deny"` output shape for `Stop`. **None of these exist** in the raw page. The real contract is `decision: "block"` + `reason`, cap **8**, tuned by `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` (default 8, `0` disables) — confirmed verbatim in `env-vars.md`. Doc 01 had this right; do not let a fetch summary revise it.
- Whether `PostToolUse` **exit 2** renders a visible red `hook error` notice to *the user* (as opposed to reaching the model) is **not documented**. The exit-2-vs-`additionalContext` framing difference is explicitly documented only for `Stop`. The PostToolUse recommendation below is therefore by analogy and should be A/B'd, not assumed.
- No study measures "does harness change X improve a solo developer's outcomes." Every ROI number below is vendor-reported or n=1. Doc 01 §8 said the same thing and it is still true.
- I did not run `/doctor` or `/skill-doctor` (not available to a subagent). The skill-index numbers in doc 01 §3 are unre-verified here.
- Practitioner claims routed through search-result summaries (marked SECONDARY-via-search) were not opened at source: the Cherny X post, and the `howborisusesclaudecode.com` aggregation. Treat the `|| true` config snippet as indicative, the sentence about "the last 10%" as the quoted claim.

---

## A. Official hook semantics as of 2026-09-07

All PRIMARY, from `code.claude.com/docs/en/hooks.md` unless noted.

### A.1 Stop

- `stop_hook_active` is `true` "when Claude Code is already continuing as a result of a stop hook."
- > "Claude Code overrides the hook and ends the turn after 8 consecutive blocks."
- `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` — PRIMARY, `env-vars.md`: "Maximum number of consecutive times a Stop or SubagentStop hook may block the turn from ending before Claude Code overrides it… (default: 8). Set to `0` to disable the cap."
- **NEW and unused here.** `hookSpecificOutput.additionalContext` on `Stop`:
  > "Non-error feedback for Claude. The conversation continues so Claude can act on it, but unlike `decision: "block"` it is shown in the transcript as hook feedback rather than a hook error."
  > "It keeps the conversation going through the same loop protections as `decision: "block"`, namely the `stop_hook_active` input and the 8-consecutive-continuation cap, but the transcript labels it `Stop hook feedback` and no hook error notification is shown."
  Shipped v2.1.163, **2026-06-04** (changelog: "Stop and SubagentStop hooks can now return `hookSpecificOutput.additionalContext` to give Claude feedback and keep the turn going without being labeled a hook error").
- **NEW.** Stop input now carries `background_tasks[]` and `session_crons[]` (v2.1.145): they "let hooks distinguish 'session is done' from 'session is paused waiting for background work to wake it back up'."
- `StopFailure` (API errors) ignores output and exit code entirely, except `terminalSequence`.

### A.2 PostToolUse

- Exit 2: "Shows stderr to Claude; the tool already ran." Cannot block.
- Exit 0 stderr: > "Stderr from a hook that exits 0 goes to the debug log only, never the transcript, and Claude never sees it."
- Decision-control fields now include `additionalContext` ("String added to Claude's context alongside the tool result"), `updatedToolOutput`, and — v2.1.236, 2026-08-19 — `classifierContext`, a note aimed at the **auto-mode classifier** rather than the model, capped at 2,000 chars per call, ignored on async hooks.
- Vendor statement that matters to `post-bash-write.sh`:
  > "Claude Code doesn't run a `PostToolUse` hook matching `Edit|Write` when a `Bash` command or a process outside Claude Code rewrites the same file." → the doc's own remedy is `FileChanged`.

### A.3 `async`, `asyncRewake`, `once`, `if`, `statusMessage`, `args`

- `async: true` — command hooks only; "Claude Code doesn't enforce `timeout` on it"; output delivered **next conversation turn**; under `-p` any still-running async hook is killed at teardown with outcome `cancelled`; no dedup across firings; completion notices hidden unless `--verbose`.
- `asyncRewake: true` — background, but "wakes Claude on exit code 2… shown to Claude as a system reminder so it can react to a long-running background failure." `timeout` **is** enforced. This is the primitive for "run the tests off the hot path and only interrupt if they fail."
- `once: true` — removes the hook after its first successful run; **only honored in skill frontmatter**, "ignored in settings files and agent frontmatter." Not usable by this plugin.
- **`if`** — a permission-rule-syntax filter on the handler: `"Bash(git *)"`, `"Edit(*.ts)"`. Only evaluated on `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PermissionRequest`, `PermissionDenied`; "On other events, a hook with `if` set never runs." One rule per handler, no `&&`/`||`. Best-effort by design: "Because the `if` filter is best-effort, use the permission system rather than a hook to enforce a hard allow or deny." Bugs fixed as recently as v2.1.243 (2026-08-24) for `$()`-containing commands.
- `statusMessage` — "Custom spinner message displayed while the hook runs." Pure perceived-smoothness lever, zero cost.
- `args` (exec form) — spawns the executable directly with no shell; recommended "whenever the hook references a path placeholder."

### A.4 Timeouts and what happens on timeout

- Defaults: **600 s** for `command`/`http`/`mcp_tool`; 30 s `prompt`; 60 s `agent`. Lowered to 30 s on `UserPromptSubmit`/`PreModelSwitch`/`PostModelSwitch`, 10 s on `MessageDisplay`.
- **`SessionEnd` hooks share a 1.5-second budget**, raised to match the highest per-hook `timeout` in *settings files* — and `env-vars.md` adds: "**Timeouts on plugin-provided hooks do not raise the budget.**" This harness ships `SessionEnd` from a plugin with `timeout: 15`, so it gets 1.5 s, not 15.
- On timeout the hook is "cancel[led]… discarding the hook's output, so on most events a timed-out hook renders no decision." On `PreToolUse` specifically: "A timed-out `command`, `http`, or `mcp_tool` hook doesn't block the tool call… **don't count on a stalled hook to act as a gate.**"

### A.5 FileChanged and PostToolBatch

- **`FileChanged`** — "Claude Code detects changes with a filesystem watcher, not by inspecting tool calls, so it runs the hook no matter what changed the file: an `Edit` or `Write` tool call, a script Claude runs with `Bash`, or a process outside Claude Code entirely." Matcher is split on `|` into a **literal filename watch list**; `watchPaths` (array of absolute paths) in the JSON output replaces the dynamic watch list; `event` is `change`/`add`/`unlink`; **no decision control** — it cannot block. Seeding requires at least one named file or a `SessionStart`/`CwdChanged` hook returning `watchPaths`.
- **`PostToolBatch`** — "After a full batch of parallel tool calls resolves, before the next model call." Payload carries `tool_uses[]` with `tool_name`, `tool_input`, `tool_use_id`, `tool_output`. Exit 2 "Stops the agentic loop before the next model call." This is the event that lets one check run **per batch** instead of per edit.

### A.6 Cross-cutting

- "All matching hooks run in parallel." Duplicate handlers across settings files run once; "A plugin's or skill's copy of the same handler stays separate."
- Hook output strings (`additionalContext`, `systemMessage`, plain stdout) are capped at **10,000 characters**; overflow is written to a file and replaced with a preview + path.
- `PreToolUse` still fires "before any permission-mode check, in every permission mode, including `dontAsk`", and a hook `deny` holds even under `--dangerously-skip-permissions`.
- `disableAllHooks` exists as a settings key, and `--settings '{"disableAllHooks": true}'` overrides project settings for one run. `--safe-mode` / `CLAUDE_CODE_SAFE_MODE=1` (v2.1.169, 2026-06-08) disables CLAUDE.md, plugins, skills, hooks, MCP together for troubleshooting.
- The doc now counts **~33 documented events** in dedicated sections (the reference table lists 33 named events; doc 01's "33" still holds).

---

## B. Friction and harness fatigue

**The one hard data point with a reproduction.** `ruvnet/ruflo` issue #1530 (PRIMARY as an artifact — pulled via GitHub API; opened **2026-04-05**, closed 2026-04-06). A project whose `.claude/settings.json` "registers 11+ hooks across 9 lifecycle events" took **18–21 s per prompt** inside the project vs **4.867 s** outside it; `claude --version` was 0.088 s and the network 0.16 s, so the delta was hooks. Root cause: "Each hook spawns a Node.js process." The reporter's stated bar: *"Hooks should not add more than 1-2s of overhead to CLI interactions."* Their proposed fixes are the generic ones — narrower matchers, lazy init, opt-in registration, a `--no-hooks` escape.

**Applied to this harness (measured here, 2026-09-07, audit-only).** Per-hook wall time on this box, fed synthetic payloads:

| hook | ms | note |
|---|---|---|
| `worklog-hook.sh` | 2 | `worklog` not installed → pure spawn |
| `codebase-map.sh` | 5 | opt-in, exits early |
| `tamper-notice.sh` | 6 | |
| `turn-stamp.sh` / `lesson-nudge.sh` / `size-guard.sh` | 7 | |
| `tool-stamp.sh` / `git-guard.sh` / `format-lint.sh` | 9 | formatter absent for the probe file |
| `post-bash-write.sh` | 20 | no files changed in the probe |
| `session-context.sh` | 43 | once per session |

So this harness is **not** ruflo: bash + `jq` beats `node` by an order of magnitude, and the total per-edit chain is ~25 ms. The honest conclusion is that *measured latency is not the smoothness problem*, and any recommendation that leans on latency is weak. The problem is registration count, error framing, and dead weight.

**Registration census (measured):** 24 handler registrations across 10 events. `worklog-hook.sh` accounts for **7** of them, two of which sit on matcher-less `PreToolUse`/`PostToolUse` groups and therefore fire on *every* tool call — `Read`, `Grep`, `Glob` included — for a binary that `command -v worklog` says is not installed. `rtk-rewrite.sh` is still first in the `PreToolUse`/`Bash` chain although `rtk` is absent and `06-adversary-panel-decisions.md` **Edit 1** ordered it dropped; that edit did not survive into `hooks.json`.

**What the best-regarded setups look like.** HumanLayer, *Skill Issue: Harness Engineering for Coding Agents*, **2026-03-12** (SECONDARY): *"I have thrown away many more hooks than we actually use today."* *"Our CLAUDE.md is under 60 lines."* *"we only spend time on harness configuration to the extent that it's actually enabling us to ship more high-quality code faster."* Their Stop hook is a nudge, not a gate: *"we have a `Stop` hook that prompts the agent to increase coverage if it drops"* — advisory, one signal, not a full sweep.

**The ablation rule.** Boris Cherny, YC Startup School, talk **2026-08-02** (SECONDARY, via barath.ai write-up, attributed as a direct quote): *"every six months, delete your CLAUDE.md, your skills, your hooks — and see what the model does before adding anything back."* The write-up's own paraphrase: the Claude Code team "delete everything, measure each line's impact through ablations, and restore only what demonstrably helps."

**Do people run tests on every Stop?** No consensus, and the practice splits exactly along the axis this harness already chose. Anthropic's `best-practices` lists the Stop hook as the hardest of four gating tiers — "Each step trades setup for attention" — and pairs it immediately with the 8-block override. HumanLayer runs a *coverage nudge*, not a suite. The harness's `scoped` default (`test-changed` per turn, occasional full promotion, 3-identical-block wedge valve) is more conservative than either and is the right shape; the remaining fix is framing, not scope.

**A post-mortem of a harness that got heavy.** `ovidiueftimie.substack.com`, *"[Part 6] The release that deleted things"*, **2026-08-23** (SECONDARY, n=1, self-reported): *"v4.0's headline win was a deletion: always-on context dropped from roughly 14.7K tokens to 4.2K."* *"The platform absorbing your scaffolding is success, not defeat. Version by version, this harness has deleted custom coordination for Agent Teams, custom installation for `/plugin`, and prose recovery for lifecycle hooks."* *"every deletion made it more reliable."*

Anthropic states the same principle as design doctrine — *Scaling Managed Agents*, **2026-04-08**: *"Harnesses encode assumptions that go stale as models improve."*

---

## C. Where enforcement should live

**`permissions.deny` is stronger than doc 01 credited, for a specific class.** PRIMARY, `permissions.md`:

- > "Deny and ask rules apply when any subcommand matches them, including a command nested inside a subshell, a command substitution, or a control-flow body such as a `for` loop."
- > "A deny or ask rule matches past any leading assignment, so `Bash(rm *)` in deny still matches `FOO=bar rm -rf tmp/`."
- Precedence: "If a tool is denied at any level, no other level can allow it"; "Hook decisions don't bypass permission rules."

That is a real shell parser doing the work. `git-guard.sh`'s own header concedes it is "a regex blocklist over a command string… `bash -c`, `eval`, variable construction, and a helper script written via Edit all evade it." For `git push --force`, `git reset --hard`, `git clean -f`, `git commit --no-verify` — fixed command shapes — a `deny` rule is **strictly better**: parsed, subshell-aware, unbypassable by permission mode, and zero process spawn.

**But `deny` is explicitly not the whole answer.** The same page warns:
> "Bash permission patterns that try to constrain command arguments are fragile."
…and lists the failure modes (options before the argument, protocol variants, variables, extra spaces). Its own recommended mitigations are, in order: deny the tool family, **"Use PreToolUse hooks"**, and CLAUDE.md guidance "paired with one of the options above." Wildcards match anywhere, but everything before the first `*` matches literally, so `Bash(git push --force*)` misses `git push -f` and `git push origin main --force`. **A hook is still needed for flag-position variation.**

Also PRIMARY: "A blocking hook also takes precedence over allow rules. A hook that exits with code 2 stops the tool call before permission rules are evaluated." So the two layers compose; neither replaces the other.

**Verdict for angle C, part 1 — is a regex git-guard still recommended in 2026?** Yes, but **thinner**. Move the fixed shapes into `permissions.deny`; keep the hook only for the flag-position and force-push-lease cases the doc admits patterns handle badly. Auto mode's classifier is a third layer, not a replacement: it is documented as blocking "scope escalation, unknown infrastructure, and hostile-content-driven actions", and v2.1.161-era changelog shows Anthropic hardening dangerous-flag handling separately (`/commit-push-pr` "git/gh commands with dangerous flags (`--force`, `--amend`, `--no-verify`, etc.) are no longer auto-approved"). Nothing in the corpus says the classifier subsumes an explicit deny.

**Verdict for angle C, part 2 — formatter on every edit?** Still yes, and it is the vendor team's own practice. Boris Cherny (SECONDARY-via-search, X thread tip 9): *"We use a PostToolUse hook to format Claude's code. Claude usually generates well-formatted code out of the box, and the hook handles the last 10% to avoid formatting errors in CI later."* The circulated config for it is `"command": "bun run format || true"` — **it never blocks**. Meanwhile the broader practitioner consensus for *linting* is the opposite of format-on-edit: pre-commit for cheap checks ("If a check can't finish in a few seconds, it probably belongs in CI or a pre-push hook"), CI as the authoritative gate. `format-lint.sh` already got the format/lint split right (panel edit 10 moved `eslint --fix` to the once-per-turn stop-gate). What it still gets wrong versus Cherny's version is `exit 2` on formatter failure — a failing formatter usually means a *syntax error mid-edit*, which is the one moment blocking helps least.

---

## D. Context hygiene in 2026

**SessionStart.** PRIMARY: "SessionStart runs on every session, so keep these hooks fast. Only `type: "command"` and `type: "mcp_tool"` hooks are supported." No token budget is published for injected context. New in v2.1.251 (2026-08-28): resumed/forked sessions get `seconds_since_last_response`, `context_tokens`, `prompt_cache_likely_expired`, and `estimated_cache_write_usd` — "Your hook can use them to report what resuming a stale conversation costs before the first request." `session-context.sh` currently reports repo state; it could report *this* instead, which is information the model cannot derive.

**The per-turn injected-context budget that *is* published is the skill listing.** PRIMARY, `skills.md`: "The budget scales at 1% of the model's context window. When the listing overflows, Claude Code drops descriptions starting with the skills you invoke least." Per-entry cap 1,536 chars (`skillListingMaxDescChars`). Two levers doc 01 did not name: `skillOverrides` set to `"name-only"` lists a skill without its description, and `SLASH_COMMAND_TOOL_CHAR_BUDGET` sets a fixed character count.

**`/skill-doctor` — new, 2026-09-04, v2.1.261** (doc says v2.1.252+). PRIMARY: "Run `/skill-doctor` to see what each of your skills costs and how often it gets used, so you can decide which ones to turn off… It flags skills in the listing that have never been invoked and says where to turn them off. It also lists plugins you haven't used recently." Doc 01 recommended cutting 66 skills → ~20 on priors; there is now a measurement to do it with.

**CLAUDE.md.** Unchanged and still blunt: "Bloated CLAUDE.md files cause Claude to ignore your actual instructions!" New line worth reading against this harness's design: **"If Claude already does something correctly without the instruction, delete it or convert it to a hook."** Also new: `/doctor` on a checked-in CLAUDE.md "proposes cuts for content it can derive from the codebase."

**Does per-turn injected output change model behaviour?** The nearest measured evidence is about *decay*, not injection cost. arXiv **2604.20911** (2026-04-22), 4,416 trials, 12 models, 8 providers: prohibition-type ("never do X") compliance falls **73% at turn 5 → 33% at turn 16**, while requirement-type ("always do X") compliance holds at 100% — they name the asymmetry Security-Recall Divergence, and find "Re-injecting constraints before the per-model Safe Turn Depth restores compliance without retraining." Read against this harness: the prose invariants it repeats (*do not weaken a test*) are exactly the decaying kind, which argues **for** a per-turn re-injection — and argues that `tamper-notice.sh`, a detector rather than a prohibition, is the right shape. arXiv **2605.01771** (2026-05-03) adds the complementary result: the "Compliance Gap" between what an agent says it did and what it did is "undetectable from text alone." Both support gates that consume evidence over gates that print rules. Neither measures the cost of a hook's own per-turn output; I found no study that does.

---

## E. The last ~90 days (2026-06-01 → 2026-09-07)

Version-to-date mapping from the npm registry: 2026-06-01 ≈ **v2.1.160**, today **v2.1.263**. Everything below is from the official `CHANGELOG.md` (PRIMARY) within that range unless dated otherwise.

| Ship | Version / date | Why it matters here |
|---|---|---|
| `Stop`/`SubagentStop` `additionalContext` | v2.1.163, 2026-06-04 | Continue a turn without the hook-error label. Directly fixes stop-gate's framing. |
| `--safe-mode` / `CLAUDE_CODE_SAFE_MODE` | v2.1.169, 2026-06-08 | One flag disables CLAUDE.md + plugins + skills + hooks + MCP. Makes Cherny's ablation rule a single command; overlaps `flow off`. |
| `if:` path-pattern fixes (`Edit(src/**)`, `Read(.env)`) | v2.1.176, 2026-06-12 | `if` filters became trustworthy for file tools. |
| `DirectoryAdded` event | v2.1.219, 2026-07-24 | — |
| Single-segment `dir/**` `if:` narrowed to `<cwd>/dir` | ~v2.1.214, 2026-07-18 | Write `**/dir/**` for any-depth. Gotcha for anyone adopting `if`. |
| `classifierContext` on PostToolUse | v2.1.236, 2026-08-19 | Talk to the auto-mode classifier without spending model context. |
| `if: Bash(...)` no longer over-fires on `$()`/backticks | v2.1.243, 2026-08-24 | |
| `PreModelSwitch`/`PostModelSwitch`; SessionStart resume-staleness + `estimated_cache_write_usd` | v2.1.251, 2026-08-28 | New SessionStart signal worth more than repo state. |
| **`/skill-doctor`** | v2.1.261, 2026-09-04 | Per-skill cost + never-invoked flag. The measurement doc 01 lacked. |
| `/context` falls back to a local token estimate | v2.1.261, 2026-09-04 | Context accounting no longer costs extra requests. |
| Workflow tool description cut 5.7k → ~1k tokens | ~v2.1.203 era | Anthropic pruning its own per-turn footprint, in-product. |
| Blocking-Stop-hook fix: turn after a block no longer loses reasoning / misses the prompt cache | ~v2.1.257+ (top 200 lines) | A real cost of Stop blocks existed and was only recently fixed — evidence that blocking Stop is not free. |
| `--permission-prompts none` for unattended hosts | within window | Cleaner than a custom deny wall for `--unattended`. |
| Fix: "focus mode showing `Ran N PostToolUse hooks` timing lines under each response" | within window | Anthropic treating per-turn hook chrome as a defect. |

No post-mortem of a *Claude Code plugin* harness collapsing under its own weight surfaced in this window; the closest artifacts are the ruflo issue (April, different runtime) and the vv-claude-harness v4.0 deletion write-up (August). Absence of evidence, noted as such.

---

## F. Delta vs `01-harness-engineering-2026.md`

### New (not in 01)
- `Stop` `hookSpecificOutput.additionalContext` — the non-error continuation path. **The single most relevant new fact for "doesn't feel smooth."**
- The handler `if` field (permission-rule syntax), `statusMessage`, and `args`/exec form.
- `asyncRewake` semantics spelled out: background **and** wakes Claude on exit 2, with `timeout` still enforced (unlike plain `async`).
- `PostToolUse` `classifierContext` (v2.1.236) and `updatedToolOutput`.
- `Stop` input `background_tasks` / `session_crons`.
- `FileChanged` fires for tool-driven writes too, plus dynamic `watchPaths`.
- `PostToolBatch` payload shape (`tool_uses[]` with outputs) — per-batch instead of per-edit checks.
- `SessionEnd`'s 1.5 s shared budget **and** that plugin-provided timeouts do not raise it.
- `/skill-doctor`, `skillOverrides: "name-only"`, `SLASH_COMMAND_TOOL_CHAR_BUDGET`, `--safe-mode`.
- 10,000-char cap on hook output strings.
- `permissions.deny` shell-awareness (subshells, `$()`, `for` bodies, leading assignments).
- arXiv 2604.20911 (constraint decay, with numbers) and 2605.01771 (compliance gap undetectable from text).

### Changed / refined
- **Hook timeout default is 600 s**, not unspecified; and a timed-out `PreToolUse` hook **does not block** ("don't count on a stalled hook to act as a gate"). Doc 01's `git-guard` framing implicitly assumed the opposite.
- `once: true` is **skill-frontmatter-only** — doc 01 listed it among general hook features without that constraint.
- Event count: doc 01 said "33 hook events" and quoted a "Total count: 33" line; the current page's table lists 33 named events. Same number, but the phrasing doc 01 quoted is not on the page today.
- Doc 01's §5 reference `stop-gate.sh` used `check-all --continue` at `timeout: 300`; panel edits 5/7 already moved this to fail-fast at 600 with a scoped default. §5 of doc 01 is superseded by the shipped script.

### Contradicted / corrected
- **Doc 01 §5 prescribes `exit 2` for the format hook.** Cherny's own published hook is `|| true` and never blocks. Format-on-edit survives; blocking on it does not.
- **Doc 01 §5's git-guard is presented as the only local layer.** `permissions.deny` is shell-aware and higher-precedence; the hook should shrink, not stand alone.
- **Doc 01 recommends `post-bash-write`-style gap closing** (panel finding 28 deferred it to wave 2, and it shipped). The vendor's documented answer to the same gap is `FileChanged`, which doc 01 mentioned only as "react to disk state."
- **Doc 01's `skillListingBudgetFraction` advice** is now second-best: `/skill-doctor` measures which skills to cut, and `skillOverrides: "name-only"` frees budget without deleting anything.
- Doc 01 said the harness had "zero hooks wired." That is stale — it now has 24 registrations, and the failure mode inverted.

---

## G. Checklist — ranked by friction removed vs safety lost

Each item names the file it touches and a check that decides whether it worked. Ordered by (friction removed) ÷ (safety lost).

| # | Change | Touches | Friction removed | Safety lost | Test |
|---|---|---|---|---|---|
| 1 | **Delete the 7 `worklog-hook.sh` registrations** (or gate the whole set behind one `SessionStart` probe that removes them when `worklog` is absent). Two of them are matcher-less on `PreToolUse`/`PostToolUse` and spawn on every `Read`/`Grep`. | `hooks.json` | High — 2 spawns per tool call, permanently | **None** — `worklog` is not installed; `worklog-hook.sh` already `exit 0`s | `python3 -c` census shows 24 → 17 registrations; `command -v worklog` still exit 1 |
| 2 | **Drop `rtk-rewrite.sh` from `PreToolUse`/`Bash`.** Panel edit 1 ordered this; it did not land. | `hooks.json` | Medium — one spawn per Bash call | None — `rtk` absent | `jq '.hooks.PreToolUse'` contains no `rtk` |
| 3 | **Switch `stop-gate.sh`'s advisory path to `hookSpecificOutput.additionalContext`;** keep `decision:"block"` only for a genuinely red gate. The degraded post-3-identical-blocks path especially. | `lib/hookout.sh` (`hook_block`), `stop-gate.sh` | **Highest perceived** — removes the red "hook error" from every nudge; documented to keep the same loop protections | Near zero — same 8-block cap, same continuation | Transcript shows `Stop hook feedback`, not a hook error, on a scoped-gate nudge |
| 4 | **Add `if:` filters to the per-edit chain** — `"Edit(**/*.ts)"`-style for format-lint, and drop the shell-side extension guards it duplicates. Remember `**/dir/**` for any-depth (v2.1.214 change). | `hooks.json`, `format-lint.sh`, `size-guard.sh` | Medium — no spawn at all for non-matching files | Low — `if` is best-effort, so keep the in-script guard for anything security-relevant (i.e. keep it in `git-guard`, drop it in `format-lint`) | Edit a `.md`; debug log shows no `format-lint` invocation |
| 5 | **Stop `format-lint.sh` exiting 2 on formatter failure.** Report via `additionalContext` (or `\|\| true` semantics) and let the once-per-turn lint in stop-gate be the gate. | `format-lint.sh` | Medium-high — a formatter failing mid-edit is usually an intermediate syntax error, and blocking there is the most annoying false positive class | Low — stop-gate still lints once per turn; CI is the backstop | Write a deliberately unparseable `.ts`; the turn continues, stop-gate reports it |
| 6 | **Move fixed-shape git denies into `permissions.deny`** (`Bash(git push --force*)`, `Bash(git reset --hard*)`, `Bash(git clean -f*)`, `Bash(git commit --no-verify*)`) and shrink `git-guard.sh` to flag-position variants (`-f`, `--force` after a remote, `--force-with-lease` allow-listing) | `settings.json`, `git-guard.sh` | Low friction, but **safety gained**: `deny` is subshell/`$()`/assignment-aware where the regex is not | **Negative** (safety improves) | `echo "$(git reset --hard)"` is denied; `git push --force-with-lease` is allowed |
| 7 | **Add `statusMessage` to every hook that can take >100 ms** (`stop-gate`, `format-lint`, `post-bash-write`) | `hooks.json` | Medium perceived — the spinner names what is happening instead of stalling silently | None | Spinner reads e.g. "running scoped gates" |
| 8 | **Fix the `SessionEnd` timeout illusion.** The plugin's `timeout: 15` does not raise the 1.5 s shared budget. Either accept 1.5 s and make the hook fit, or move it out of `SessionEnd`. | `hooks.json` | Low friction; removes a silent truncation | None | Hook completes inside 1.5 s or is deleted |
| 9 | **Evaluate `asyncRewake` for the test half of `stop-gate`:** run `test-changed` in the background on `PostToolUse`, wake Claude only on failure; keep a thin synchronous Stop check for the tamper/spec invariants. | `hooks.json`, `stop-gate.sh`, new script | High if the suite is slow — takes the suite off the turn's critical path entirely | **Real**: a turn can end before the tests report; the wake lands on the next turn. Do **not** adopt for `--unattended` without a Stop-side backstop | Turn ends immediately; a seeded failing test produces a system reminder within the next turn |
| 10 | **Evaluate `FileChanged` as a replacement for `post-bash-write.sh`.** Vendor-endorsed for exactly this gap. | `hooks.json`, delete `post-bash-write.sh` (146 lines) | Medium — removes a 90 s-timeout hook from every Bash call and 146 lines of mtime-diffing | **Real limitation**: the watch list is literal filenames, seeded from a matcher or `watchPaths`. There is no glob. Verify a `SessionStart` `watchPaths` seed from `git ls-files` is workable before deleting anything | A heredoc write via Bash triggers the format hook with no `post-bash-write.sh` registered |
| 11 | **Run `/skill-doctor`, then cut or set `skillOverrides: "name-only"` on everything it flags as never-invoked.** | `settings.json` | High per-turn context, on every turn of every session | Low — `"name-only"` keeps the skill invokable by name | `/context` Skills row shrinks; the kept skills still fire on their trigger phrases |
| 12 | **Replace `session-context.sh`'s repo digest with the resume-cost fields** (`context_tokens`, `prompt_cache_likely_expired`, `estimated_cache_write_usd`) on `resume`/`fork`, and keep the digest only on `startup`. | `session-context.sh`, `hooks.json` matchers | Low-medium — stops paying for branch/dirty-count on every resume, which the model can derive | None — it is additive information the model cannot derive | A resumed session's first message reports staleness; a fresh one reports repo state |
| 13 | **Retire `flow off` / `.claude/flow.off` in favour of `disableAllHooks` + `--safe-mode`,** unless per-directory granularity is genuinely used. | `lib/hookout.sh` (`hook_skip_if_off` in 8 scripts) | Low friction, but deletes a `hook_off_here` call from every hook and one bespoke concept | Low — `--settings '{"disableAllHooks":true}'` is per-run, `flow off` is per-directory; keep `flow off` if the directory scope matters | `--safe-mode` produces the same silence `flow off` did |
| 14 | **Standing:** every model release, run Cherny's ablation — disable the plugin with `--safe-mode` for a day and re-add only what you miss. Record the result in `PROGRESS.md`. | process | The only mechanism that keeps this list from growing back | None if recorded | A dated ablation note exists |

**Explicitly not recommended.**
- Do **not** raise `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`. 8 is the anti-wedge valve, and the harness's own 3-identical-signature valve fires first.
- Do **not** move to `PostToolBatch` for the format/size chain yet. Exit 2 there "Stops the agentic loop before the next model call" — a heavier hammer than the per-edit advisory it would replace, and the batch payload gives you tool outputs, not a changed-file set.
- Do **not** delete `tamper-notice.sh`. arXiv 2604.20911's result is that prohibition-type instructions decay from 73% to 33% compliance over eleven turns while a detector does not; it is the highest-value hook in the set per line of code.
- Do **not** loosen `spec-gate.sh`'s default. `requireSpec: "flow-branches"` already confines it to `flow/*` branches; the friction it causes elsewhere should be zero, and if it is not, that is a bug to reproduce rather than a threshold to lower.

---

## H. Sources

PRIMARY (fetched 2026-09-07, raw markdown, HTTP 200):
- https://code.claude.com/docs/en/hooks.md — 3,773 lines; all hook semantics in §A
- https://code.claude.com/docs/en/env-vars.md — `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`, `CLAUDE_CODE_SESSIONEND_HOOKS_TIMEOUT_MS`, `CLAUDE_CODE_SAFE_MODE`
- https://code.claude.com/docs/en/permissions.md — deny precedence, Bash rule matching, the argument-pattern fragility warning
- https://code.claude.com/docs/en/skills.md — `/skill-doctor`, listing budget, `skillOverrides`
- https://code.claude.com/docs/en/best-practices.md — verification tiers, CLAUDE.md guidance, plan-mode threshold
- https://code.claude.com/docs/en/hooks-guide.md — limitations list, block-cap troubleshooting
- https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md — §E
- https://registry.npmjs.org/@anthropic-ai/claude-code — version→date mapping
- https://api.github.com/repos/ruvnet/ruflo/issues/1530 — 2026-04-05, hook latency reproduction
- arXiv 2604.20911 (2026-04-22), arXiv 2605.01771 (2026-05-03) — abstracts via the arXiv API

SECONDARY:
- https://www.humanlayer.dev/blog/skill-issue-harness-engineering-for-coding-agents (2026-03-12)
- https://www.barath.ai/learnings/boris-cherny-yc-startup-school-2026 (talk 2026-08-02) — Cherny quotes are this author's attribution, not a transcript
- https://x.com/bcherny/status/2007179852047335529 — format-hook quote, reached via search snippet only
- https://ovidiueftimie.substack.com/p/part-6-the-release-that-deleted-things (2026-08-23) — n=1 harness deletion post-mortem
- https://www.anthropic.com/engineering/managed-agents (2026-04-08)

AUDIT-ONLY (measured on this machine, 2026-09-07 — re-verify before acting):
- 24 handler registrations across 10 events in `plugins/flow/hooks/hooks.json`
- per-hook wall times 2–43 ms (table in §B)
- `worklog`, `rtk` both absent (`command -v` → exit 1); `jq` present
