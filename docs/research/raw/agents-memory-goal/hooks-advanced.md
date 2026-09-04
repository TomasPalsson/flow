# Advanced Claude Code Hooks (Sept 2026): Prompt/Agent Hooks, PermissionRequest, Async, Fleet Control, and More

## TL;DR

- Claude Code hooks now have **five handler types**: `command`, `http`, `mcp_tool`, `prompt`, and `agent`. `prompt` sends a single-turn evaluation to a Claude model (Haiku by default) returning `{"ok": true|false, "reason": ...}`; `agent` spawns a subagent with up to 50 tool-use turns (60s default timeout) that can Read/Grep/run commands before deciding — official docs call agent hooks **experimental** and recommend command hooks for production. (PRIMARY, code.claude.com/docs/en/hooks-guide, fetched 2026-09-04)
- **`PermissionRequest`** fires right before Claude Code would show you a permission dialog. It ignores exit code 2 entirely — you must return `{"hookSpecificOutput": {"hookEventName": "PermissionRequest", "decision": "allow"|"deny"|"ask", "decisionReason": "..."}}`. Hooks can tighten but never loosen permissions past what deny rules and `requiresUserInteraction` MCP tools require. (PRIMARY, code.claude.com/docs/en/hooks)
- **Async hooks**: `"async": true` runs in the background, ignoring `timeout`, and is unsuitable for anything that must block. `"asyncRewake": true` runs in the background and **wakes Claude** only on exit code 2, feeding stderr (or stdout if stderr is empty) back as a system reminder — this is the mechanism for long-running background checks (test suites, builds) that interrupt the session later rather than blocking it now. (PRIMARY, code.claude.com/docs/en/hooks)
- **Stop-hook loops have a hard, documented cap**: Claude Code overrides (force-stops) a `Stop` hook after it blocks **8 times in a row without progress**. Hooks must check the `stop_hook_active` input field and exit 0 once it's `true`; the cap is raisable via the `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` env var. There is **no such cap for other loop-prone events** (e.g. `TeammateIdle`, `TaskCompleted`) — you own loop safety there. (PRIMARY, code.claude.com/docs/en/hooks-guide)
- **Fleet control**: `SubagentStart`/`SubagentStop` fire on subagent spawn/finish (matcher = `agent_type`), `TaskCreated`/`TaskCompleted` fire on the Task-tracking lifecycle and both can be blocked/rolled back with exit code 2. In skill/agent frontmatter, a `Stop` hook you declare is silently converted to `SubagentStop` when running inside that subagent's own scope. (PRIMARY, code.claude.com/docs/en/hooks; cross-checked SECONDARY claudefa.st)
- **`once: true` is narrower than commonly assumed**: it is honored *only* in **skill frontmatter**, not in agent/subagent frontmatter and not in settings files — a fact one synthesis pass got wrong and a targeted re-fetch corrected. (PRIMARY, code.claude.com/docs/en/hooks, verbatim quote below)
- `FileChanged` (watches literal filenames on disk, e.g. `.envrc|.env`) and `CwdChanged` (fires on every directory change, no matcher support) are the documented mechanism for direnv-style reactive environment reloads. `ConfigChange` can block config edits (exit 2) except for `policy_settings`, and the security docs explicitly recommend it for auditing settings changes mid-session. (PRIMARY, code.claude.com/docs/en/hooks and code.claude.com/docs/en/security)
- The **hookify** plugin is real, official (bundled under `anthropics/claude-code`'s plugins), and lets you write hooks as markdown+YAML-frontmatter "rules" (`warn`/`block` actions, Python-regex matchers) instead of hand-editing `settings.json` hook JSON, via `/hookify "<instruction>"`. (PRIMARY, raw.githubusercontent.com/anthropics/claude-code/main/plugins/hookify/README.md)
- Practitioner consensus (multiple independent blogs, mid-2026): hooks are valued as the one layer that runs "whether or not the model cooperates," but the sharpest complaints are the **exit-code footgun** (only exit code 2 blocks — exit 1 is silently non-blocking), **loop risk on `Stop`**, and the fact that a compromised or careless hook runs with **the same shell credentials as the logged-in user** (not sandboxed) — though this exact "full user permissions" wording could not be verified verbatim in the current live docs and may be paraphrased/superseded language. (SECONDARY, blakecrosley.com and thepromptshelf.dev, both 2026)

---

## Findings

1. **Claim**: Hooks support five handler types, set via `"type"`: `command`, `http`, `mcp_tool`, `prompt`, `agent`.
   **Evidence**: "Most hooks use `\"type\": \"command\"`, which runs a shell command. Four other types are available" plus dedicated subsections for each.
   **URL**: https://code.claude.com/docs/en/hooks-guide (also https://code.claude.com/docs/en/hooks)
   **Date fetched**: 2026-09-04. **PRIMARY**. **Consensus** (confirmed across two independent doc-page fetches).

2. **Claim**: Prompt hooks (`type: "prompt"`) send the hook's JSON input plus your prompt text to a Claude model — **Haiku by default**, overridable via `model` — for a single-turn decision returned as `{"ok": true}` or `{"ok": false, "reason": "..."}`.
   **Evidence** (verbatim): "Instead of running a shell command, Claude Code sends your prompt and the hook's input data to a Claude model, Haiku by default, to make the decision. You can specify a different model with the `model` field if you need more capability. The model's only job is to return its decision as JSON."
   **URL**: https://code.claude.com/docs/en/hooks-guide. **Date**: 2026-09-04. **PRIMARY**. **Consensus**.

3. **Claim**: The `ok:false` outcome behaves differently per event: on `Stop`/`SubagentStop` the `reason` is fed back to Claude to keep working (unless `"impossible": true` is also set, which lets the stop proceed); on `PreToolUse` the tool call is denied and by default ends the turn, unless `continueOnBlock: true` is set (added behavior; before v2.1.210 the reason always continued the turn); on `PostToolUse` similarly gated by `continueOnBlock`; on `PostToolBatch`/`UserPromptSubmit`/`UserPromptExpansion` the turn always ends with the reason shown as a warning.
   **Evidence**: quoted directly from the "Prompt-based hooks" section (see raw excerpt captured from https://code.claude.com/docs/en/hooks-guide, lines ~847-854).
   **URL**: https://code.claude.com/docs/en/hooks-guide. **Date**: 2026-09-04. **PRIMARY**. **Consensus** — this is a precise, versioned behavior spec, not opinion.

4. **Claim**: Agent hooks (`type: "agent"`) spawn a subagent with tool access (Read, Grep, run commands), use the same `ok`/`reason` schema as prompt hooks but with **60s default timeout and up to 50 tool-use turns**, have no `impossible` field, and are marked **experimental** with a documented recommendation to prefer command hooks for production.
   **Evidence** (verbatim Warning box): "Agent hooks are experimental. Behavior and configuration may change in future releases. For production workflows, prefer command hooks." And: "Use prompt hooks when the hook input data alone is enough to make a decision. Use agent hooks when you need to verify something against the actual state of the codebase."
   **URL**: https://code.claude.com/docs/en/hooks-guide. **Date**: 2026-09-04. **PRIMARY**. **Consensus**.

5. **Claim**: Hook type timeouts differ: `command`/`http`/`mcp_tool` default to 10 minutes (30s for `UserPromptSubmit`/`PreModelSwitch`/`PostModelSwitch`, 10s for `MessageDisplay`); `prompt` defaults to 30s; `agent` defaults to 60s; `SessionEnd` hooks of any type share a 1.5s budget (raised to match a longer explicit `timeout`, capped at 60s).
   **Evidence**: verbatim bullet list under "Limitations and troubleshooting → Limitations" in the hooks guide.
   **URL**: https://code.claude.com/docs/en/hooks-guide. **Date**: 2026-09-04. **PRIMARY**. **Consensus**.

6. **Claim (cost/latency of prompt vs agent hooks)**: No official docs page gives token-cost numbers for prompt/agent hooks; the only quantified guidance found anywhere is the timeout difference (30s vs 60s) and the qualitative claim that agent hooks are "more thorough... but slower." Practitioner commentary found (Blake Crosley) explicitly declines to evaluate whether the added latency is acceptable or discuss pricing.
   **Evidence**: "He mentions these briefly in configuration but offers no practitioner commentary on cost or latency."
   **URL**: https://blakecrosley.com/blog/claude-code-hooks-explained. **Date**: 2026-07-01. **SECONDARY**. **Gap / open question**, not consensus.

7. **Claim**: The `PermissionRequest` hook input carries `session_id`, `prompt_id`, `transcript_path`, `cwd`, `permission_mode`, `hook_event_name: "PermissionRequest"`, `tool_name`, `tool_input`, `tool_use_id`, `permission_decision_required: true`.
   **Evidence**: verbatim JSON example fetched directly from the `#permissionrequest` anchor of the reference page.
   **URL**: https://code.claude.com/docs/en/hooks#permissionrequest. **Date**: 2026-09-04. **PRIMARY**.

8. **Claim**: `PermissionRequest` output schema: `hookSpecificOutput.decision` is one of `"allow"`, `"deny"`, or `"ask"` (i.e. it **can force a manual prompt**, not just allow/deny), plus `decisionReason`. Exit code 2 is explicitly **not honored** for this event — "The permission flow proceeds unchanged regardless of exit code. Deny through the `decision` object instead."
   **Evidence**: field table quoted verbatim: "`decision` | string | Permission decision: `\"allow\"`, `\"deny\"`, or `\"ask\"`. ... `\"allow\"` approves the tool call, `\"deny\"` rejects it, and `\"ask\"` asks the user."
   **URL**: https://code.claude.com/docs/en/hooks#permissionrequest. **Date**: 2026-09-04. **PRIMARY**. Note: an earlier, less-targeted fetch of the same page summarized this as allow/deny only, omitting `"ask"` — the anchor-targeted re-fetch is the more complete and authoritative read. **Contested only in the sense that summarization quality varied across fetches of the same primary source**, not in the underlying docs.

9. **Claim**: A real, filed bug (GitHub issue #19298, opened 2026-01-19, Claude Code v2.1.12, macOS) reported that `PermissionRequest` hook decisions were silently ignored — the interactive prompt always appeared regardless of `permissionDecision`, `decision`, or `deny: true` output, or exit code 2. Issue closed as "not planned" / went stale, no maintainer response recorded in the thread.
   **Evidence**: issue body and label summary fetched directly.
   **URL**: https://github.com/anthropics/claude-code/issues/19298. **Date**: 2026-01-19 (issue), fetched 2026-09-04. **PRIMARY** (GitHub issue tracker). **Contested/historical** — this is an old-version bug report (v2.1.12); current docs (Sept 2026) describe `decision` as functional, and no confirmation was found that the bug persists in current releases. Flag this as a known historical failure mode worth testing for regression before relying on `PermissionRequest` for security-critical denial.

10. **Claim**: Async fields on command hooks — `async` (bool, no default stated as required): "If `true`, runs in the background without blocking." `asyncRewake` (bool): "If `true`, runs in the background and wakes Claude on exit code 2. The hook's stderr, or stdout if stderr is empty, is shown to Claude as a system reminder so it can react to a long-running background failure."
    **Evidence**: verbatim field table from anchor-targeted fetch of `#async-hooks`.
    **URL**: https://code.claude.com/docs/en/hooks#async-hooks. **Date**: 2026-09-04. **PRIMARY**. **Consensus**.

11. **Claim**: `async: true` hooks explicitly ignore the `timeout` field, and the docs' own qualitative guidance elsewhere (per synthesis of the reference) is that async is "best for logging and analytics, backup creation" — i.e. explicitly **unsuitable for security-blocking work**, since a blocking decision requires the hook to finish before the tool runs.
    **Evidence**: cross-referenced synthesis fetch: "Claude Code ignores `timeout` on async hooks... 'Best for: Logging and analytics, Backup creation' but unsuitable for security blocking."
    **URL**: https://code.claude.com/docs/en/hooks (synthesis fetch), cross-checked structurally against #async-hooks anchor fetch above. **Date**: 2026-09-04. **PRIMARY** (docs content), **paraphrase framing is SECONDARY-flavored** since it came through a summarizing fetch rather than an exact quote — treat the "best for" phrasing as approximate, not verbatim.

12. **Claim**: `SubagentStart` fires when a subagent is spawned; input includes `agent_type`, `agent_id`, `permission_mode`, `cwd`, `session_id`; matcher is on `agent_type` (built-ins: `"general-purpose"`, `"Explore"`, `"Plan"`; custom/plugin-scoped names need anchors like `^my-plugin:reviewer$` for exact match).
    **Evidence**: JSON example and matcher guidance from synthesis fetch of the reference page, structurally consistent with the "Agentic Loop (13 events)" event list independently returned by a second fetch (claudefa.st) that enumerates `SubagentStart, SubagentStop, TaskCreated, TaskCompleted` among 30 total lifecycle events.
    **URL**: https://code.claude.com/docs/en/hooks; cross-check https://claudefa.st/blog/tools/hooks/hooks-guide. **Date**: 2026-09-04 fetch (SECONDARY blog says published/updated 2026-05-31, v2.1.141+). **PRIMARY for the docs content, SECONDARY for the 30-event count/taxonomy** (the "30 lifecycle events" framing itself is the blog's own organizing scheme, not a docs-verbatim phrase I could independently confirm).

13. **Claim**: `SubagentStop` fires when a subagent finishes; carries `last_assistant_message` (the subagent's final assistant text) explicitly so you can read final output "without parsing transcript, which may lag." In skill/agent frontmatter, a hook you register under `Stop` is converted to `SubagentStop` automatically when it's running inside that subagent's scope.
    **Evidence**: JSON example plus explicit note quoted in synthesis fetch of the reference page.
    **URL**: https://code.claude.com/docs/en/hooks. **Date**: 2026-09-04. **PRIMARY**.

14. **Claim**: `TaskCreated` and `TaskCompleted` fire on Task-tool lifecycle events; exit code 2 on `TaskCreated` **rolls back the creation**, exit code 2 on `TaskCompleted` **prevents the task from being marked complete** — i.e. both are usable as hard gates for "fleet"/task-tracking control (e.g., a gate that blocks marking a task done until CI is green).
    **Evidence**: synthesis fetch quoting the reference's exit-code-behavior notes per event.
    **URL**: https://code.claude.com/docs/en/hooks. **Date**: 2026-09-04. **PRIMARY**.

15. **Claim**: `once: true` on a hook definition is honored **only in skill frontmatter** — not in settings files, and (contrary to an initial less-careful read) **not in subagent/agent frontmatter either**.
    **Evidence** (verbatim, from a targeted re-fetch): "`once` | no | If `true`, Claude Code removes the hook after its first successful run. A run that fails, blocks with exit code 2, or times out leaves the hook in place, so it runs again on the next matching event. Only honored for hooks declared in [skill frontmatter](#hooks-in-skills-and-agents); ignored in settings files and agent frontmatter"
    **URL**: https://code.claude.com/docs/en/hooks.md. **Date**: 2026-09-04. **PRIMARY**. **Corrects an earlier, broader synthesis** (a first-pass fetch of the same page had summarized `once` as usable in both skill and agent frontmatter — the anchor/verbatim re-fetch is authoritative).

16. **Claim**: Hooks declared in **skill frontmatter** run when the skill is invoked, persist for the rest of the session, and run even in `-p` (non-interactive) sessions in **untrusted folders** — no workspace-trust gate. Hooks in **subagent frontmatter** run only while that subagent is active, are removed when it finishes, and require the user to have **accepted the workspace trust dialog** for the folder the agent file came from; a `-p` session does not count as trust acceptance. Before v2.1.218, subagent frontmatter hooks could run from untrusted folders (this was a gap that has since been closed).
    **Evidence**: "Frontmatter hooks in a project subagent run only after you accept the workspace trust dialog for the folder the agent file came from." / "Before v2.1.218, these hooks could run from folders you hadn't trusted."
    **URL**: https://code.claude.com/docs/en/hooks. **Date**: 2026-09-04. **PRIMARY**. **Consensus but security-relevant asymmetry**: skill hooks are the more dangerous surface precisely because they carry no trust gate.

17. **Claim**: `Notification` hook matcher values documented include `permission_prompt`, `idle_prompt`, `auth_success`, `elicitation_dialog`, `elicitation_url_dialog`, `elicitation_complete`, `elicitation_response`, `agent_needs_input`, `agent_completed`, `quota_auto_resume_fired`, `quota_auto_resume_stale`, `quota_auto_resume_disabled`. Exit codes/output are otherwise ignored on this event except `terminalSequence`, which is the documented hook for desktop notifications (native OS notification via terminal escape sequences) — the walkthrough for setting up a first hook in the guide is literally a desktop-notification `Notification` hook.
    **Evidence**: matcher-value list from synthesis fetch of the reference page; guide's own worked example: "This walkthrough creates a desktop notification hook, so you get alerted whenever Claude is waiting for your input instead of watching the terminal," using `osascript`/`notify-send`/PowerShell `msg`/dialog commands per OS.
    **URL**: https://code.claude.com/docs/en/hooks and https://code.claude.com/docs/en/hooks-guide. **Date**: 2026-09-04. **PRIMARY**. Slack/TTS routing is **not itself a built-in feature** — it's just "run any shell command," so a Slack or TTS notification hook is a `command`-type hook whose script posts to a webhook or calls a TTS binary; docs do not ship a first-party Slack/TTS integration. **Consensus that this is DIY, not built-in.**

18. **Claim**: `FileChanged` watches literal filenames on disk (matcher is an exact-match set — letters, digits, `_`, and `|` only; hyphens/spaces/commas fall back to full regex, and only `|` separates alternatives for this event specifically) and fires with `file_path`, `cwd`, `change_type`. The documented worked example is exactly the direnv use case: `matcher: ".envrc|.env|.env.local"` running `direnv reload` or `eval $(direnv export bash)` with `"async": true`.
    **Evidence**: verbatim matcher/example JSON from synthesis fetch of the reference page.
    **URL**: https://code.claude.com/docs/en/hooks. **Date**: 2026-09-04. **PRIMARY**. **Consensus** — this is a docs-endorsed pattern, not a workaround.

19. **Claim**: `CwdChanged` fires on every directory change (e.g. a `cd` inside a Bash tool call) with `cwd`, `previous_cwd`, `session_id`; it has **no matcher support** — it always fires. Documented pairing pattern: run `direnv allow` on cwd change.
    **Evidence**: synthesis fetch quoting reference JSON and the "No matcher support; fires on every directory change" note.
    **URL**: https://code.claude.com/docs/en/hooks. **Date**: 2026-09-04. **PRIMARY**.

20. **Claim**: `ConfigChange` fires when a config file changes mid-session; matcher values are `user_settings`, `project_settings`, `local_settings`, `policy_settings`, `skills`. Exit code 2 blocks the change from taking effect **except** for `policy_settings` ("blocking this doesn't prevent change" — i.e. managed/admin policy changes cannot be blocked by a user-level hook). Official security guidance explicitly recommends this hook: "Audit or block settings changes during sessions with `ConfigChange` hooks."
    **Evidence**: reference synthesis fetch + verbatim line from the Security doc's "Team security" checklist.
    **URL**: https://code.claude.com/docs/en/hooks and https://code.claude.com/docs/en/security. **Date**: 2026-09-04. **PRIMARY**. **Consensus, docs-endorsed practice**.

21. **Claim**: `PreToolUse` hooks fire before **any** permission-mode check, in every mode including `dontAsk` — a hook returning `permissionDecision: "deny"` blocks the tool call even in `bypassPermissions` mode or with `--dangerously-skip-permissions`. The reverse doesn't hold: a hook returning `"allow"` cannot bypass deny rules from settings, and cannot suppress prompts for MCP tools marked `requiresUserInteraction` or org-`ask`-flagged connector tools. "Hooks can tighten restrictions but not loosen them past what permission rules allow."
    **Evidence**: verbatim from "Hooks and permission modes" subsection.
    **URL**: https://code.claude.com/docs/en/hooks-guide. **Date**: 2026-09-04. **PRIMARY**. **Important for the "PermissionRequest / auto-allow-deny-ask" part of this brief** — this is the core mechanism practitioners use to enforce policy that can't be bypassed by switching to a looser permission mode.

22. **Claim**: The **Stop-hook block cap is 8 consecutive blocks without progress**, after which Claude Code force-overrides the hook and ends the turn with a warning. A hook must check the boolean `stop_hook_active` field on its JSON input and exit 0 (allow the stop) once that flag is `true`, or it will hit the cap. The cap is configurable via the `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` environment variable.
    **Evidence** (verbatim): "Claude Code overrides a Stop hook after it blocks eight times in a row without progress. Your hook script needs to check whether it already triggered a continuation. Parse the `stop_hook_active` field from the JSON input and exit early if it's `true`" ... "If your hook legitimately needs more than eight iterations to converge, raise the cap with `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`."
    **URL**: https://code.claude.com/docs/en/hooks-guide (section "Stop hook hits the block cap"). **Date**: 2026-09-04. **PRIMARY**. **Consensus** — this is the single most load-bearing, precisely-specified fact in this brief (exact number, exact field name, exact env var).

23. **Claim**: The block-cap protection is **built in only for `Stop`**. For other loop-prone events used in fleet-style patterns (`TeammateIdle`, `TaskCompleted`), you are responsible for your own loop safety — there is no automatic cap.
    **Evidence**: "Built-in flag only covers `Stop`. If gating `TeammateIdle` or `TaskCompleted`, you own loop safety."
    **URL**: (synthesis) https://claudefa.st/blog/tools/hooks/hooks-guide, cross-referenced against the absence of any cap-mechanism documented for those events on the primary reference page. **Date**: 2026-09-04 fetch / blog dated 2026-05-31. **SECONDARY** for the exact framing, but **structurally consistent with PRIMARY** docs, which document a cap only under the `Stop` troubleshooting section and nowhere else. **Practitioner opinion elevated to practical consensus** — treat as a real gap to design around.

24. **Claim**: There is no general, cross-event loop-prevention mechanism: e.g. a `PostToolUse` hook that edits a file can trigger `FileChanged`, whose hook can run a Bash command that triggers another `PostToolUse`, and so on — Claude Code does not detect or break such cascades automatically.
    **Evidence**: "Claude Code has no automatic loop detection preventing hooks from triggering other hooks... Best Practice: Use `async: true` for non-critical hooks... Design hooks that modify files to be idempotent... Avoid chains of hooks that trigger each other."
    **URL**: (synthesis of) https://code.claude.com/docs/en/hooks, fetched 2026-09-04. **PRIMARY docs content relayed through a summarizing fetch** — treat specific wording as paraphrase, but the substantive claim ("no built-in cross-hook loop detection, cap only applies to Stop") is corroborated independently by findings #22–23 above from a differently-targeted fetch of the same docs. **Consensus**.

25. **Claim**: The **hookify** plugin is a real, first-party-adjacent Claude Code plugin that lets you author hooks as markdown files with YAML frontmatter rather than raw `settings.json`. It supports `/hookify "<instruction>"` to generate a rule from a natural-language directive, bare `/hookify` to scan recent conversation for problematic patterns and propose a rule, plus `/hookify:list`, `/hookify:configure`, `/hookify:help`. Rules use Python-regex matchers, support `warn` (message only) and `block` (prevents the operation) actions, monitor five event categories (bash commands, file modifications, stop signals, user prompts, all events), can chain multiple required conditions, and take effect immediately without a session restart. Requires Python 3.7+, no external dependencies.
    **Evidence**: fetched and summarized directly from the plugin's own README.
    **URL**: https://raw.githubusercontent.com/anthropics/claude-code/main/plugins/hookify/README.md. **Date fetched**: 2026-09-04 (no publish date shown in the file). **PRIMARY** (author's own plugin README). Note: a separate GitHub-search-style fetch returned a list of *forked/patched* hookify repos (`hookify-plus-fork`, `cc-hookify-patched`, `hookify-windows-fix`, `steerhook`, etc.) — that search-result page could not be independently verified and reads as possibly fabricated/low-confidence output from the fetch tool's own summarization step; it is **not relied on** for any claim in this report beyond noting that community forks of hookify plausibly exist (unverified).

26. **Claim (security)**: Official Claude Code security documentation (general, not hook-specific) frames the relevant safeguard as permission-based architecture ("Claude Code only has the permissions you grant it. You're responsible for reviewing proposed code and commands for safety before approval") plus a specific hook-relevant recommendation to use `ConfigChange` hooks to audit/block settings changes. No sentence containing "full user permissions," "can modify, delete, or access any files your user account can access," or "without confirmation" could be located verbatim anywhere on the current live `hooks`, `hooks-guide`, or `security` docs pages despite three independently-targeted searches of the full page text.
    **Evidence**: direct full-text search of https://code.claude.com/docs/en/hooks for those phrases returned no matches; https://code.claude.com/docs/en/security's closest statement is the "User responsibility" paragraph quoted above.
    **URL**: https://code.claude.com/docs/en/hooks, https://code.claude.com/docs/en/security. **Date**: 2026-09-04. **PRIMARY** (absence-of-evidence search). **Disagreement flagged below** against SECONDARY sources that assert this phrasing exists.

27. **Claim (contested against #26)**: Two independent practitioner blogs assert, in their own words attributed as quoting "the official reference," that hooks "run with your full user permissions" / "can modify, delete, or access any files your user account can access," and that "a compromised hook is equivalent to a compromised shell session."
    **Evidence**: "Crosley doesn't shy away from the elephant: hooks 'run with your full user permissions.' The official reference warning he cites states they 'can modify, delete, or access any files your user account can access.'" and, from a second, independent blog: "The article candidly warns: 'A compromised hook is equivalent to a compromised shell session' running with user credentials."
    **URL**: https://blakecrosley.com/blog/claude-code-hooks-explained (2026-07-01) and https://thepromptshelf.dev/blog/claude-code-hooks-complete-reference-2026-v2/ (dated 2026-05-31, v2.1.141+). **SECONDARY**, both. **Contested/unverifiable against current primary docs**: either (a) this exact language existed in an earlier docs revision and was later softened/removed (docs churn is visible elsewhere in this research, e.g. version-gated behavior changes at v2.1.198/200/203/210/211/218/234/236/247/251/257), or (b) both blogs are paraphrasing the same widely-circulated characterization rather than quoting verbatim. Either way, **the underlying substance is true and uncontested**: command hooks are plain shell processes that inherit the invoking user's OS-level permissions and are not sandboxed by Claude Code's own permission system, since permission checks are what triggers the hook, not a boundary the hook itself runs inside.

28. **Claim**: Testing hooks is officially documented as: (a) pipe a sample JSON payload into your script manually and check exit code (`echo '{"tool_name":"Bash",...}' | ./my-hook.sh; echo $?`); (b) use `/hooks` (a **read-only** browser) to confirm a hook is registered under the right event with the right matcher; (c) enable debug logging with `claude --debug-file /tmp/claude.log` (or `/debug` mid-session) and `tail -f` it to see which hooks matched, their exit codes, stdout/stderr, timeout details, and JSON-parse/validation failures.
    **Evidence**: verbatim commands and prose from the "Limitations and troubleshooting → Debug techniques" and "Hook not firing" / "Hook error in output" subsections.
    **URL**: https://code.claude.com/docs/en/hooks-guide. **Date**: 2026-09-04. **PRIMARY**. **Consensus**; note the *reference* page (`hooks.md`) itself was checked separately and found to have **no dedicated testing section** — testing guidance lives specifically in the `hooks-guide` walkthrough page, not the reference page.

29. **Claim**: A common silent-failure testing gotcha — if your shell profile (`.bashrc`/`.zshrc`) echoes anything on startup, that text prepends to your hook's stdout, so "the combined output no longer starts with `{`," Claude Code treats the whole thing as plain text, and on exit 0 nothing is reported anywhere except the debug log. Fix: guard profile echoes to only run in interactive shells.
    **Evidence**: verbatim from the guide's troubleshooting section, corroborated independently by Crosley's blog ("a shell profile that echoes on startup corrupts your hook's JSON output").
    **URL**: https://code.claude.com/docs/en/hooks-guide (PRIMARY) and https://blakecrosley.com/blog/claude-code-hooks-explained (SECONDARY, 2026-07-01). **Date**: 2026-09-04. **Consensus** across primary and independent secondary source.

30. **Claim**: The classic "exit 1 does nothing" footgun is real and documented implicitly through the exit-code semantics (only exit code 2 is a "blocking error"; other non-zero codes are non-blocking errors shown as a `<hook name> hook error` notice), and is called out explicitly as the single biggest practitioner gotcha by an independent blog.
    **Evidence**: "The biggest issue is that 'exit 1 does not block anything.' This violates Unix convention and catches developers expecting standard behavior. Only exit 2 enforces blocking on supported events." Cross-checked against primary: "Exit code 2 means a blocking error" and the non-blocking-error stdout/stderr handling described in the reference's exit-code section.
    **URL**: https://blakecrosley.com/blog/claude-code-hooks-explained (SECONDARY, 2026-07-01), cross-checked https://code.claude.com/docs/en/hooks (PRIMARY). **Date**: 2026-09-04. **One practitioner's framing of a documented mechanism — not contested, just not itself an official "gotcha" callout in the docs.**

31. **Claim**: HTTP hooks (`type: "http"`, added per one blog's dating to Feb 2026) POST the same JSON a command hook gets on stdin to a URL and expect the same JSON schema back in the response body; blocking requires a **2xx response** with the right `hookSpecificOutput` — "HTTP status codes alone can't block actions." Gated by an `allowedHttpHookUrls` allowlist (merged across settings levels) and `allowedEnvVars`/`httpHookAllowedEnvVars` for header interpolation; unlisted `$VAR` references in headers resolve to empty strings rather than erroring.
    **Evidence**: verbatim from hooks-guide HTTP hooks section and reference synthesis.
    **URL**: https://code.claude.com/docs/en/hooks-guide, https://code.claude.com/docs/en/hooks. **Date**: 2026-09-04. **PRIMARY** for the mechanism; the "added Feb 2026" dating is **SECONDARY** (claudefa.st) and unverified against a changelog.

32. **Claim**: `PermissionDenied` (distinct from `PermissionRequest`) fires when auto mode's classifier denies a tool call. Its output supports `hookSpecificOutput.retry: true` to tell Claude it may retry the denied call — but "Claude Code ignores `retry` when the classifier produced no verdict" (i.e. when the block came from a separate safety refusal rather than an actual classifier judgment).
    **Evidence**: JSON example and retry-field description from the synthesis fetch of the reference page, consistent with the permission-modes page's own description of classifier fallback behavior ("no verdict" cases).
    **URL**: https://code.claude.com/docs/en/hooks; cross-check https://code.claude.com/docs/en/permission-modes ("When the classifier produces no verdict on the action... Claude Code denies the action without the notification"). **Date**: 2026-09-04. **PRIMARY**.

33. **Claim**: Auto mode's classifier (the thing `PermissionRequest`/`PermissionDenied` hooks interact with) runs on **Claude Sonnet 5 by default** regardless of your session's `/model` selection (falling back to the session model if Sonnet 5 is unavailable, or an Opus model for Fable-model sessions); classifier calls count toward token usage on Enterprise/API/Bedrock/etc plans; a network-access verdict for a given host+port is **cached/reused** rather than re-run per connection, until new conversation content or compaction invalidates it. **[UNVERIFIED: the caching half of this claim oversimplifies — the source actually gives three separate expiry rules (allow → new content only; context-overflow deny → new content or compaction; ordinary evaluated deny → turn boundary / rest-of-run in non-interactive mode), not one uniform "new content or compaction" rule. See independent source check below.]**
    **Evidence**: verbatim from the "Cost and latency" accordion on the permission-modes page.
    **URL**: https://code.claude.com/docs/en/permission-modes. **Date**: 2026-09-04. **PRIMARY**. This is the closest official "cost and latency" numbers get for LLM-mediated permission decisions generally — it's about the classifier, not `type:"prompt"`/`type:"agent"` hooks specifically, but is the closest documented analog and is directly relevant to anyone weighing script vs. LLM-judged permission gating.

34. **Claim**: Auto mode (the built-in classifier layer, adjacent to but distinct from hook-based `PermissionRequest`/`PreToolUse` gating) has its own **repeated-block fallback**: if the classifier blocks an action 3 times in a row, or 20 times total in a session, auto mode pauses and Claude Code resumes prompting the user; these thresholds are **not configurable**.
    **Evidence** (verbatim): "if the classifier blocks an action 3 times in a row or 20 times total, auto mode pauses and Claude Code resumes prompting... These thresholds are not configurable."
    **URL**: https://code.claude.com/docs/en/permission-modes. **Date**: 2026-09-04. **PRIMARY**. Worth distinguishing from finding #22 (the *Stop-hook* 8-block cap, which is a different mechanism, different number, and configurable via env var) — these are two separate "block cap" concepts in Claude Code and are easy to conflate.

---

## Downsides and failure modes

- **Exit-code semantics are a footgun**: only exit code 2 blocks; exit 1 (and any other non-zero code) is a *non-blocking* error, silently different from what most shell scripters expect. (SECONDARY opinion, corroborated by PRIMARY exit-code spec — see #30)
- **`PermissionRequest` decisions have a documented history of being ignored** in at least one released version (v2.1.12, Jan 2026); the bug report went stale with no maintainer confirmation of a fix. Anyone building security-critical auto-deny logic on `PermissionRequest` should write a regression test against their current Claude Code version rather than trusting the docs alone. (PRIMARY GitHub issue — see #9)
- **No general cross-hook loop detection.** A `PostToolUse` hook that writes a file can cascade through `FileChanged` → another hook → another tool call → `PostToolUse` again, indefinitely, with nothing stopping it except your own idempotency discipline. The only built-in cap is the Stop-hook 8-in-a-row cap; `TeammateIdle` and `TaskCompleted` (both plausible fleet-control gates) have **no** built-in cap at all. (PRIMARY — see #22–24)
- **Two different, easy-to-confuse "block cap" concepts exist**: the Stop-hook loop cap (8 consecutive blocks, `stop_hook_active` field, `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` env var) vs. the auto-mode classifier's own fallback (3-in-a-row or 20-total, not configurable). Confusing them when debugging "why did it stop looping / why did it start prompting me" is a realistic mistake. (PRIMARY — see #22, #34)
- **Agent hooks are explicitly experimental** — the docs themselves discourage relying on them in production and warn behavior may change. (PRIMARY — see #4)
- **Silent JSON-corruption failure mode**: a shell profile that echoes on startup silently breaks a hook's JSON output with no error shown to the user on exit 0 — only visible in the debug log. (PRIMARY + SECONDARY corroboration — see #29)
- **`once: true` is far narrower than it sounds**: it does not work in settings files or agent/subagent frontmatter, only skill frontmatter, and even then only after a *successful* run (a failed, blocked, or timed-out run leaves it registered). Easy to misconfigure and get silent re-execution. (PRIMARY — see #15)
- **Security surface is asymmetric between skills and subagents**: skill frontmatter hooks run even in untrusted, non-interactive (`-p`) folders with no workspace-trust gate at all; subagent frontmatter hooks require the trust dialog to have been accepted (closed as a gap only as of v2.1.218). A malicious or careless skill is therefore a stronger hook-injection vector than a malicious subagent file. (PRIMARY — see #16)
- **Async hooks trade enforcement for non-blocking speed** — by design they cannot be used for anything that must gate an action before it runs; only `asyncRewake`'s exit-2-wakes-Claude path lets a background async hook eventually have consequences, and even then only after the fact. (PRIMARY — see #10–11)
- **No official cost/latency benchmark exists** for prompt vs. agent hook types beyond the timeout defaults (30s / 60s); practitioners so far haven't published numbers either. Treat "prompt hooks are cheap, agent hooks are expensive" as directionally true (agent hooks can burn up to 50 tool-use turns) but unquantified. (Gap — see #6)
- **Notification/Slack/TTS routing is entirely DIY**: there's no first-party Slack or TTS integration; you get a `Notification` event with a matcher on notification *type* and you write the `command` hook that calls a webhook or a TTS binary yourself. (PRIMARY — see #17)

## Concrete practices / configs

All JSON below is either directly quoted from official docs or lightly assembled from docs-verbatim field tables; each is annotated with its source.

**1. Prompt hook — cheap LLM judgment on a Stop event** (verbatim from docs):
```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "prompt",
            "prompt": "Check if all tasks are complete. If not, respond with {\"ok\": false, \"reason\": \"what remains to be done\"}."
          }
        ]
      }
    ]
  }
}
```
Source: https://code.claude.com/docs/en/hooks-guide (PRIMARY)

**2. Agent hook — verify tests actually pass before letting Claude stop** (verbatim from docs):
```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "agent",
            "prompt": "Verify that all unit tests pass. Run the test suite and check the results. $ARGUMENTS",
            "timeout": 120
          }
        ]
      }
    ]
  }
}
```
Source: https://code.claude.com/docs/en/hooks-guide (PRIMARY)

**3. PermissionRequest — policy-as-code allow/deny/ask** (schema assembled from verbatim field table, docs example structure):
```json
{
  "hookSpecificOutput": {
    "hookEventName": "PermissionRequest",
    "decision": "deny",
    "decisionReason": "Command blocked by security policy"
  }
}
```
`decision` must be `"allow"`, `"deny"`, or `"ask"`. Exit code 2 is ignored for this event — you must emit this JSON. Source: https://code.claude.com/docs/en/hooks#permissionrequest (PRIMARY). **Test this against your actual installed Claude Code version** before depending on it for anything security-critical (see finding #9).

**4. Async background test run that wakes Claude only on failure**:
```json
{
  "type": "command",
  "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/validate.sh",
  "asyncRewake": true,
  "timeout": 600
}
```
Source: https://code.claude.com/docs/en/hooks#async-hooks (PRIMARY, field table + example)

**5. Stop hook that correctly avoids the block cap**:
```bash
#!/bin/bash
INPUT=$(cat)
if [ "$(echo "$INPUT" | jq -r '.stop_hook_active')" = "true" ]; then
  exit 0  # Allow Claude to stop
fi
# ... rest of your hook logic (exit 2 to keep blocking, with JSON reason)
```
Source: https://code.claude.com/docs/en/hooks-guide, "Stop hook hits the block cap" (PRIMARY, verbatim). To raise the 8-block default, set `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` in your environment.

**6. direnv reload on env-file change (FileChanged)**:
```json
{
  "hooks": {
    "FileChanged": [
      {
        "matcher": ".envrc|.env|.env.local",
        "hooks": [
          { "type": "command", "command": "eval $(direnv export bash)", "async": true }
        ]
      }
    ]
  }
}
```
Source: https://code.claude.com/docs/en/hooks (PRIMARY, verbatim example)

**7. direnv allow on cwd change (CwdChanged, no matcher)**:
```json
{
  "hooks": {
    "CwdChanged": [
      { "hooks": [ { "type": "command", "command": "direnv allow", "async": true } ] }
    ]
  }
}
```
Source: https://code.claude.com/docs/en/hooks (PRIMARY, verbatim example)

**8. Audit config changes, block non-policy edits**:
```json
{
  "hooks": {
    "ConfigChange": [
      {
        "matcher": "project_settings",
        "hooks": [
          { "type": "command", "command": "git diff .claude/settings.json", "async": true }
        ]
      }
    ]
  }
}
```
Source: https://code.claude.com/docs/en/hooks (PRIMARY, verbatim example); recommended explicitly by https://code.claude.com/docs/en/security's team-security checklist.

**9. Desktop notification when Claude is waiting on you** (the docs' own first-hook walkthrough; macOS example):
```bash
osascript -e 'display notification "Claude is waiting for input"'
```
Wired as a `command` hook under `Notification`, matcher `"permission_prompt|idle_prompt"`. On Linux use `notify-send`; on Windows, a PowerShell dialog via `powershell.exe` (works from WSL if on `PATH`). Slack/TTS notifications follow the identical pattern but with your own `curl`-to-webhook or TTS-binary command in place of `osascript`/`notify-send` — this is DIY, not a built-in integration. Source: https://code.claude.com/docs/en/hooks-guide (PRIMARY).

**10. Skill frontmatter hook with `once: true`** (structure per docs' field description):
```yaml
---
name: secure-operations
description: Perform operations with security checks
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: prompt
          prompt: "Is this a safe command? $ARGUMENTS"
          once: true
---
```
`once: true` here means: after the prompt hook returns a successful decision once, it's removed from the skill's registered hooks for the rest of the session. A failure, a block (exit 2), or a timeout leaves it registered so it fires again. This field is **honored in skill frontmatter only** — not settings files, not agent/subagent frontmatter. Source: https://code.claude.com/docs/en/hooks.md (PRIMARY, verbatim field description — see finding #15).

**11. hookify plugin usage** (natural-language hook authoring):
```
/hookify Don't use console.log in TypeScript files
/hookify:list
/hookify:configure
```
Produces a markdown file with YAML frontmatter defining a Python-regex-matched rule with a `warn` or `block` action against one of five event categories (bash commands, file modifications, stop signals, user prompts, all events). Source: https://raw.githubusercontent.com/anthropics/claude-code/main/plugins/hookify/README.md (PRIMARY).

**12. Testing a hook by hand before trusting it**:
```bash
echo '{"tool_name":"Bash","tool_input":{"command":"ls"}}' | ./my-hook.sh
echo $?
```
Combine with `claude --debug-file /tmp/claude.log` in a separate session and `tail -f /tmp/claude.log` to see exactly which hooks matched, their exit codes, and any JSON schema-validation failures. Source: https://code.claude.com/docs/en/hooks-guide (PRIMARY).

**For a solo developer, a pragmatic starting hook set** (synthesized from the above, not a docs-verbatim block — mark as advice, not quote): desktop `Notification` hook on `permission_prompt|idle_prompt` (item 9); `FileChanged`/`CwdChanged` for direnv (items 6–7); a `PostToolUse` formatter on `Edit|Write` matcher as an `async` command hook so it never blocks the loop; a `Stop`-hook completion gate using the prompt or agent type with the `stop_hook_active` guard (items 1–2 + 5) if you actually need "keep going until tests pass" behavior — most solo setups don't need this and it's the single biggest source of loop-cap surprises; and `ConfigChange` auditing (item 8) if you ever run Claude Code against other people's repos or with elevated permission modes.

## Disagreements and open questions

- **`PermissionRequest`'s `decision` field: does `"ask"` actually work reliably, and was the January-2026 "decisions ignored" bug (#19298) ever fixed?** Current docs describe `"allow"|"deny"|"ask"` as fully functional (see #8); the only field evidence I could find of real-world breakage is from Jan 2026 on a much older point release (v2.1.12). I found no changelog entry or maintainer comment confirming a fix. **Recommend the user test this directly against their installed version rather than trust either the docs or the stale issue.**
- **Did the docs used to say "hooks run with your full user permissions" / "can modify, delete, or access any files your user account can access," and was that language later removed or softened?** Two independent 2026 blogs quote this framing as if lifted from the official reference; three independently-targeted full-text searches of the current live `hooks`, `hooks-guide`, and `security` pages turned up no such sentence. This is either stale/superseded docs language the blogs picked up from an earlier snapshot, or a paraphrase both blogs independently converged on. The underlying technical fact (hook shell processes are not sandboxed and inherit the invoking user's OS permissions) is not in dispute — only the exact wording and whether it's still a docs-stated warning today.
- **Cost/latency numbers for `type: "prompt"` and `type: "agent"` hooks specifically (as opposed to the auto-mode classifier)** are not published anywhere I found — only default timeouts (30s / 60s) and the qualitative "agent hooks are slower but more thorough." No practitioner blog found had benchmarked this either. Treat this as a genuine gap, not settled either way.
- **Whether `TeammateIdle` and `TaskCompleted` genuinely have zero loop protection**, versus simply not documenting one, rests on one secondary source's framing ("Built-in flag only covers Stop") that I could not find an equivalent explicit primary-docs sentence for — though the primary docs' cap section is scoped entirely to `Stop` and nowhere else, which is consistent with (though not proof of) the secondary claim.
- **HTTP hooks' "added Feb 2026" and async hooks' "added Jan 2026" dating** come from one secondary source's own event-taxonomy framing and were not corroborated against an official changelog; treat as plausible but unverified.
- **The GitHub-search-derived list of hookify forks** (hookify-plus-fork, cc-hookify-patched, hookify-windows-fix, steerhook, etc.) could not be independently verified as real repositories and is excluded from load-bearing claims in this report; only the official `anthropics/claude-code` `plugins/hookify/README.md` was used as a source.

## Sources

- https://code.claude.com/docs/en/hooks — Hooks reference. PRIMARY. Fetched 2026-09-04 (multiple targeted anchor fetches: `#permissionrequest`, `#async-hooks`, full-page verbatim searches).
- https://code.claude.com/docs/en/hooks.md — Same page, raw markdown variant, used for the exact `once` field-table quote. PRIMARY. Fetched 2026-09-04.
- https://code.claude.com/docs/en/hooks-guide — "Automate actions with hooks" quickstart/guide. PRIMARY. Fetched 2026-09-04 (full page + grep of saved output for loop/block-cap/testing sections).
- https://code.claude.com/docs/en/permission-modes — Permission modes reference, including the auto-mode classifier's cost/latency accordion and repeated-block fallback. PRIMARY. Fetched 2026-09-04 (full page saved and read).
- https://code.claude.com/docs/en/security — Security doc, general permission architecture and `ConfigChange` audit recommendation. PRIMARY. Fetched 2026-09-04.
- https://code.claude.com/docs/llms.txt — Documentation index, used to locate related pages. PRIMARY. Fetched 2026-09-04.
- https://raw.githubusercontent.com/anthropics/claude-code/main/plugins/hookify/README.md — hookify plugin's own README. PRIMARY. Fetched 2026-09-04.
- https://github.com/anthropics/claude-code/issues/19298 — Bug report, "PermissionRequest hook decision ignored," opened 2026-01-19, v2.1.12, closed not-planned/stale. PRIMARY (issue tracker). Fetched 2026-09-04.
- https://blakecrosley.com/blog/claude-code-hooks-explained — Practitioner opinion piece, published 2026-07-01. SECONDARY.
- https://thepromptshelf.dev/blog/claude-code-hooks-complete-reference-2026-v2/ — Practitioner reference/opinion, dated 2026-05-31 (v2.1.141+). SECONDARY.
- https://claudefa.st/blog/tools/hooks/hooks-guide — "Complete Guide to All 30 Lifecycle Events," used for the SubagentStart/Stop/TaskCompleted event-taxonomy cross-check and the Stop-only-cap framing. SECONDARY.
- https://www.developersdigest.tech/guides/permission-request-hook — PermissionRequest-focused guide with practitioner gotchas (logging discipline, latency risk, over-restriction risk). SECONDARY, no date shown.
- Not independently verified / excluded from load-bearing claims: a GitHub search result listing purported hookify forks (github.com/search?q=hookify+claude+code+plugin) — content could not be confirmed as real and is flagged as possibly fabricated by the fetch tool's summarization step.

## Source check (independent)

Six of the most load-bearing claims (specific numbers, field names, verbatim quotes, and an attribution) were re-checked directly against the cited primary sources on 2026-09-04, independent of the original research pass.

1. **Finding #5 — hook-type timeout defaults** (command/http/mcp_tool 10min; UserPromptSubmit/PreModelSwitch/PostModelSwitch 30s; MessageDisplay 10s; prompt 30s; agent 60s; SessionEnd 1.5s budget raised to match a longer timeout, capped at 60s).
   **Verdict: CONFIRMED.**
   Exact quote from https://code.claude.com/docs/en/hooks-guide: *"Hook timeouts vary by type. Override per hook with the `timeout` field in seconds. `command`, `http`, `mcp_tool`: 10 minutes. Claude Code lowers this default to 30 seconds for `UserPromptSubmit`, `PreModelSwitch`, and `PostModelSwitch` hooks, and to 10 seconds for `MessageDisplay`. `prompt`: 30 seconds. `agent`: 60 seconds. [`SessionEnd`](/docs/en/hooks#sessionend) hooks of any type share a 1.5-second budget. If your settings set a longer per-hook `timeout`, Claude Code raises the budget to match, up to 60 seconds."* Matches the claim number-for-number.

2. **Finding #22 — Stop-hook block cap of 8 consecutive blocks, `stop_hook_active` field, `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` env var.**
   **Verdict: CONFIRMED.**
   Exact quote from https://code.claude.com/docs/en/hooks-guide: *"Claude Code overrides a Stop hook after it blocks eight times in a row without progress. Your hook script needs to check whether it already triggered a continuation. Parse the `stop_hook_active` field from the JSON input and exit early if it's `true`... If your hook legitimately needs more than eight iterations to converge, raise the cap with [`CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`](/docs/en/env-vars)."* Matches exactly.

3. **Finding #2 — prompt hooks (`type: "prompt"`) use Haiku by default, overridable via `model`.**
   **Verdict: CONFIRMED.**
   Exact quote from https://code.claude.com/docs/en/hooks-guide: *"For decisions that require judgment rather than deterministic rules, use `type: \"prompt\"` hooks. Instead of running a shell command, Claude Code sends your prompt and the hook's input data to a Claude model, Haiku by default, to make the decision. You can specify a different model with the `model` field if you need more capability."* Matches exactly.

4. **Finding #33 — auto-mode classifier runs on Claude Sonnet 5 by default (with stated fallbacks), and a network-access verdict for a host+port is cached/reused until "new conversation content or compaction" invalidates it.**
   **Verdict: PARTIAL.** The Sonnet-5-by-default claim and its fallbacks are confirmed verbatim; the caching claim is a simplification of a three-way rule, not a single uniform "cached until new content or compaction" behavior.
   Exact quote (model default), https://code.claude.com/docs/en/permission-modes: *"The classifier runs on Claude Sonnet 5 by default rather than on your `/model` selection. A classifier model that Anthropic configures server-side takes precedence over that default. When your session's model is Claude Sonnet 4.6, or when `availableModels` excludes Sonnet 5, the classifier runs on the session's model instead, or on an Opus model when the session runs on a Fable model..."* — this part is CONFIRMED exactly as reported.
   Exact quote (caching), same page: *"An allow is reused until new content enters the conversation, at which point that host is checked again. Claude Code v2.1.234 and later reuse a deny caused by the conversation outgrowing the classifier's context window until new content enters the conversation, or until compaction shrinks what the classifier reads. Claude Code then checks the host again. A deny that the classifier reached by evaluating the request lasts for the turn in the interactive CLI. In non-interactive mode and Agent SDK sessions, Claude Code reuses that deny for the rest of the run..."* — the docs actually describe **three distinct expiry rules** (allow → new content; context-overflow deny → new content or compaction; ordinary evaluated deny → turn boundary, or rest-of-run in non-interactive mode), not one uniform "new content or compaction" rule as the research brief summarized. The "3 times in a row or 20 total, not configurable" repeated-block claim also checked out verbatim: *"if the classifier blocks an action 3 times in a row or 20 times total, auto mode pauses and Claude Code resumes prompting... These thresholds are not configurable."*

5. **Finding #15 — `once: true` is honored only in skill frontmatter, not in settings files or agent/subagent frontmatter.**
   **Verdict: CONFIRMED.**
   Exact quote from https://code.claude.com/docs/en/hooks.md: *"`once` | no | If `true`, Claude Code removes the hook after its first successful run. A run that fails, blocks with exit code 2, or times out leaves the hook in place, so it runs again on the next matching event. Only honored for hooks declared in [skill frontmatter](#hooks-in-skills-and-agents); ignored in settings files and agent frontmatter."* Matches exactly, word for word.

6. **Finding #9 — GitHub issue #19298 (PermissionRequest hook decisions ignored), opened 2026-01-19, v2.1.12, macOS, closed not-planned/stale, no maintainer response.**
   **Verdict: CONFIRMED.**
   Fetched directly via `gh issue view 19298 --repo anthropics/claude-code`. `createdAt: 2026-01-19T19:03:50Z`; body specifies `Claude Code version: v2.1.12`, `OS: macOS (Darwin 24.6.0)`; `state: CLOSED`, `stateReason: NOT_PLANNED`; labels include `bug`, `has repro`, `platform:macos`, `area:core`, `stale`. All 6 comments on the thread are from community accounts (`mattcamp`, `ehsan`, `Sanchay-T` ×2) plus two `github-actions` bot messages ("Closing for now — inactive for too long" / auto-lock notice) — no Anthropic-maintainer reply is present in the thread, confirming the "no maintainer response recorded" characterization.

**Reliability note**: All 6 checked claims survive contact with their cited primary sources, and 5 of 6 are exact verbatim matches (including precise numbers, field names, and env-var names) — this brief's sourcing discipline is high. The one PARTIAL (auto-mode verdict caching, finding #33) isn't wrong so much as compressed: the source describes three different expiry conditions depending on verdict type (allow / context-overflow deny / ordinary deny) and the brief flattened them into one "new content or compaction" rule. Worth a light edit in the original doc; does not affect the brief's core claims about hooks proper.

## Gaps

- No official numeric cost/latency comparison of `type: "prompt"` vs `type: "agent"` hooks (only default timeouts are documented).
- Could not confirm whether GitHub issue #19298 (PermissionRequest decisions ignored) was fixed in a later release — no changelog was fetched.
- Could not verify verbatim "hooks run with your full user permissions" language in current docs despite it being asserted as a quote by two SECONDARY sources — likely superseded or paraphrased docs language; not independently locatable as of 2026-09-04.
- Did not fetch a dedicated Claude Code changelog/release-notes page, so several version-gated behaviors (e.g. HTTP hooks "added Feb 2026," async hooks "added Jan 2026," v2.1.210 continueOnBlock change) rely on in-docs version callouts or one SECONDARY source's dating rather than a changelog cross-check.
- Did not find and could not fetch a Reddit/HN/X discussion thread giving a broader practitioner-sentiment sample (WebSearch quota was exhausted after 2 queries this session, before six distinct queries could be run — see note below); practitioner-opinion coverage in this report rests on the handful of blog posts that were reachable via WebFetch from the initial search result set, not a full 6-query search sweep.
- Note on method compliance: the task specified at least 6 distinct WebSearch queries; this session's WebSearch quota (200/session, apparently already consumed before this task began) was exhausted after 2 queries, so queries 3-6 could not run. Coverage was extended instead via 9+ WebFetch calls (exceeding the 8-page minimum) built from the two searches' result sets plus direct URL guesses/anchors, but this is a narrower query-phrasing sweep than the method called for.
