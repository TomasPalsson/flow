# Claude Code Hooks System — Current State (September 2026)

## TL;DR

- As of Sept 2026, Claude Code ships **33 distinct hook events** (up from the original 8-9 "core" events of 2025) covering session lifecycle, the tool loop, subagents/teammates, tasks, config/file watching, worktrees, compaction, model switching, and MCP elicitation. Full authoritative list: `code.claude.com/docs/en/hooks`, current as of this fetch (PRIMARY, Sept 4 2026).
- Exit-code contract is unchanged in spirit but event-specific in effect: **0** = no objection (stdout becomes context only for `UserPromptSubmit`, `UserPromptExpansion`, `SessionStart`, `PostModelSwitch`; otherwise debug-log only); **2** = blocking error, reason goes to Claude (feedback) or the user depending on event, with several events unable to block at all; **any other code** = non-blocking, JSON on stdout still wins if it validates against schema.
- Instead of exit-code-only control, hooks can print structured JSON to stdout with fields like `decision`, `reason`, `continue`, `stopReason`, `systemMessage`, `suppressOutput`, and nested `hookSpecificOutput.{permissionDecision, permissionDecisionReason, additionalContext, updatedInput, decision.behavior, retry}` — the exact field set is **event-specific**, not universal (e.g. `PreToolUse` uses `hookSpecificOutput.permissionDecision`; `PostToolUse`/`Stop` use top-level `decision: "block"`; `PermissionRequest` uses `hookSpecificOutput.decision.behavior`).
- Hooks now come in **five handler types**: `command` (shell), `http` (POST to a webhook, same JSON contract), `mcp_tool` (call an already-connected MCP tool), `prompt` (single-turn Haiku-by-default judgment call returning `{"ok": true/false, "reason": ...}`), and `agent` (experimental multi-turn subagent with tool access, up to 50 turns) — this is new/matured relative to 2025's command-only model.
- Hooks are configured in `~/.claude/settings.json` (user, all projects), `.claude/settings.json` (project, shareable/committable), `.claude/settings.local.json` (project, gitignored), managed/enterprise policy settings, a plugin's `hooks/hooks.json`, and now also directly in **skill frontmatter** (registered for rest of session) and **subagent frontmatter** (active while that subagent runs, where its `Stop` becomes `SubagentStop`). All levels merge; they don't override each other except `disableAllHooks`.
- The canonical "Stop hook blocks until done" pattern (tests/lint gate) is standard and Anthropic now bakes in an anti-infinite-loop safety net: Claude Code auto-overrides a Stop hook after **8 consecutive blocks without progress**, and exposes `stop_hook_active` in the hook's JSON input plus a `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` env var to raise/lower that cap. This is official, documented guidance — not just community folklore.
- Community practice (disler/claude-code-hooks-mastery, Matt Pocock's git-guardrails, various "block dangerous git commands" writeups) converges on the same shape: `PreToolUse` + `Bash` matcher + regex blocklist (`rm -rf`, `git push --force`, `git reset --hard`, `sudo`, `chmod 777`) + `exit 2` with a stderr reason so Claude self-corrects instead of silently failing.
- New-in-2026 official capabilities worth flagging: `PermissionRequest` hooks can auto-approve/deny/escalate permission prompts (`hookSpecificOutput.decision.behavior: "allow"|"deny"|"ask"`) and even switch the session's permission mode (`updatedPermissions: [{type: "setMode", ...}]`); `FileChanged`/`CwdChanged` react to disk/directory changes independent of which tool caused them (e.g., reloading `direnv` env vars); `ConfigChange` can block or audit live edits to settings/skills files; `async`/`asyncRewake` let a command hook run in the background and only interrupt Claude if it later fails.

## Findings

1. **Claim:** The full, current hook event list (33 events) is: `SessionStart`, `Setup`, `UserPromptSubmit`, `UserPromptExpansion`, `PreToolUse`, `PermissionRequest`, `PermissionDenied`, `PostToolUse`, `PostToolUseFailure`, `PostToolBatch`, `Notification`, `MessageDisplay`, `SubagentStart`, `SubagentStop`, `TaskCreated`, `TaskCompleted`, `Stop`, `StopFailure`, `TeammateIdle`, `InstructionsLoaded`, `ConfigChange`, `CwdChanged`, `DirectoryAdded`, `FileChanged`, `WorktreeCreate`, `WorktreeRemove`, `PreCompact`, `PostCompact`, `PreModelSwitch`, `PostModelSwitch`, `Elicitation`, `ElicitationResult`, `SessionEnd`.
   **Evidence:** Full table with "when it fires" description for each, directly fetched from the official reference and guide pages.
   **Source:** https://code.claude.com/docs/en/hooks (fetched 2026-09-04) and https://code.claude.com/docs/en/hooks-guide (fetched 2026-09-04). PRIMARY. Standard/consensus (this is the vendor's own current documentation, not an opinion).
   **Note:** `Notification` is a single event with many sub-*types* selected via matcher (`permission_prompt`, `idle_prompt`, `agent_needs_input`, `quota_auto_resume_*`, etc.), which is likely why some third-party posts round the count up to "30" or "32+" by counting notification subtypes or matcher values as if they were separate events. The user's question named `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `Stop`, `SubagentStart`/`Stop`, `PreCompact`, `Notification`, `PermissionRequest` — **all 10 of these exist and are current**; nothing on that list has been removed or renamed.

2. **Claim:** `PostToolUseFailure` is real, current, and distinct from `PostToolUse` — it fires after a tool call *fails* (vs. succeeds), matches on tool name, supports the `if` field, but exit code 2 on it only "shows stderr to Claude" (the action already happened, it can't be undone) — same limitation as `PostToolUse`.
   **Evidence:** Table row "`PostToolUseFailure` — After a tool call fails" and the exit-code-2-per-event table row "`PostToolUse`, `PostToolUseFailure` | Shows stderr to Claude (action already occurred)".
   **Source:** https://code.claude.com/docs/en/hooks (fetched 2026-09-04). PRIMARY. Standard/consensus.

3. **Claim:** Matcher syntax has three modes: `"*"`/empty/omitted = match everything; a value made only of letters/digits/`_`/`-`/spaces/`,`/`|` = an exact-string or list match (comma support requires ≥v2.1.191, hyphen-in-exact-match requires ≥v2.1.195); anything else = evaluated as an **unanchored JavaScript regex** (e.g. `^Notebook`, `mcp__memory__.*`). Not all events support matchers — `UserPromptSubmit`, `PostToolBatch`, `Stop`, `TeammateIdle`, `TaskCreated`, `TaskCompleted`, `WorktreeCreate`, `WorktreeRemove`, `CwdChanged`, `MessageDisplay` always fire on every occurrence regardless of matcher.
   **Evidence:** "Matcher Evaluation Rules" and "Event-Specific Matcher Values" tables, plus the guide's "no matcher support" row.
   **Source:** https://code.claude.com/docs/en/hooks (fetched 2026-09-04). PRIMARY. Standard/consensus.

4. **Claim:** A separate, narrower filter — the `if` field — uses **permission-rule syntax** (`"Bash(git *)"`, `"Edit(*.ts)"`) to filter by tool name *and arguments together*, only on the tool-call events (`PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PermissionRequest`, `PermissionDenied`); adding `if` to any other event prevents the hook from running at all. Because Bash argument parsing is best-effort (can't resolve `$VAR` expansions), Anthropic explicitly warns not to rely on `if` as a hard security boundary — use the permission system for that.
   **Evidence:** "Bash `if` Pattern Matching" table with concrete examples (`Bash(git *)` matches `FOO=bar git push` because leading assignments are stripped; matches subcommands inside `$()`; when Claude Code can't resolve a variable it runs the hook regardless).
   **Source:** https://code.claude.com/docs/en/hooks (fetched 2026-09-04) and https://code.claude.com/docs/en/hooks-guide (fetched 2026-09-04). PRIMARY. Standard/consensus.

5. **Claim:** Exit-code semantics are per-event, not universal. Exit 0 = "no objection" (only 4 events treat stdout as auto-injected context: `UserPromptSubmit`, `UserPromptExpansion`, `SessionStart`, `PostModelSwitch`; everything else logs stdout to debug only unless it parses as JSON). Exit 2 = blocking, but its *effect* differs: blocks the tool (`PreToolUse`), blocks prompt processing (`UserPromptSubmit`), prevents the turn from stopping (`Stop`, `SubagentStop`), rolls back a task (`TaskCreated`), stops the agentic loop before the next model call (`PostToolBatch`), is **NOT honored at all** on `PermissionRequest` (must use the `decision` object instead), and on `StopFailure` the exit code/output is ignored except for a `terminalSequence` field. Any other exit code: if stdout is valid JSON that passes schema validation, the JSON alone decides the outcome (exit code ignored, no error reported); if it's invalid JSON or plain text, it's treated as a non-blocking error and the action proceeds, with `<hook name> hook error` shown in the transcript. `WorktreeCreate` is the outlier where *any* nonzero exit aborts worktree creation.
   **Evidence:** Full "Exit Code Semantics Per Event" table and "Exit Code Output" prose section, both reproduced verbatim in the fetch.
   **Source:** https://code.claude.com/docs/en/hooks (fetched 2026-09-04). PRIMARY. Standard/consensus — this directly supersedes older "exit 0/1/2" blog explanations that treat exit-2 as uniformly blocking everywhere (e.g. several 2025-era community posts state "exit 2 always blocks," which the current docs qualify heavily per-event).

6. **Claim:** JSON stdout output fields recognized by the current system: `hookSpecificOutput` (event-specific decision object — required nesting point for `additionalContext`, `permissionDecision`, `permissionDecisionReason`, `updatedInput`, and `decision.behavior`), plus top-level `decision` (used by `PostToolUse`/`Stop`-style events as `"block"`), `reason`, `continue` (Stop hooks forcing continuation), `stopReason`, `systemMessage`, `suppressOutput` (hide tool output display), `retry` (tell the model it may retry a denied tool call, `PermissionDenied` only), and `terminalSequence` (escape sequence side-effect, all events). Anthropic explicitly warns `additionalContext` placed at the *top level* of the JSON (not nested under `hookSpecificOutput`) is **silently ignored**.
   **Evidence:** "JSON Output Fields" table + "For `UserPromptSubmit` hooks, use `hookSpecificOutput.additionalContext`... Nest `additionalContext` inside `hookSpecificOutput`; if you place it at the top level of the JSON, Claude Code silently ignores it."
   **Source:** https://code.claude.com/docs/en/hooks and https://code.claude.com/docs/en/hooks-guide (both fetched 2026-09-04). PRIMARY. Standard/consensus. (This nesting gotcha is a frequent source of "my hook JSON has no effect" bugs per the docs' own troubleshooting section.)

7. **Claim:** `PreToolUse`'s `permissionDecision` has four possible values, not two: `"allow"` (skip the interactive prompt, but enterprise deny/ask rules and MCP `requiresUserInteraction` tools still apply — a hook allow can tighten but never loosen policy), `"deny"` (cancel + feed `permissionDecisionReason` to Claude), `"ask"` (show the normal prompt), and `"defer"` (headless `-p` mode only — exits with the tool call preserved so an Agent SDK wrapper can resume it later).
   **Evidence:** Direct enumeration with definitions in the guide's "Structured JSON output" section.
   **Source:** https://code.claude.com/docs/en/hooks-guide (fetched 2026-09-04). PRIMARY. Standard/consensus.

8. **Claim:** `PreToolUse` hooks fire before *any* permission-mode check, in every mode including `bypassPermissions`/`--dangerously-skip-permissions`/`dontAsk` — meaning a `permissionDecision: "deny"` hook is a hard boundary users can't get around by loosening their permission mode. This is presented as a deliberate security design, not an edge case.
   **Evidence:** "Hooks and permission modes" section: "A hook that returns `permissionDecision: 'deny'` blocks the tool even in `bypassPermissions` mode... This lets you enforce policy that users can't bypass by changing their permission mode."
   **Source:** https://code.claude.com/docs/en/hooks-guide (fetched 2026-09-04). PRIMARY. Standard/consensus.

9. **Claim:** Five hook handler types exist: `command` (shell, stdin/stdout JSON, supports exec-form via `args:[]` to avoid a shell entirely, or shell-form for pipes/`&&`), `http` (POST the same JSON payload to a URL, response body carries the same output schema, only 2xx bodies can block — HTTP status codes alone cannot), `mcp_tool` (call a tool on an already-connected MCP server with `${...}` input substitution), `prompt` (single LLM call, Haiku by default, model overridable, returns `{"ok": bool, "reason": str, "impossible": bool}`), and `agent` (**explicitly labeled experimental**, may change; spawns a real subagent with Read/Grep/tool access, up to 50 tool-use turns, 60s default timeout, no `continueOnBlock` field — behaves like `continueOnBlock: true` always).
   **Evidence:** Full field tables for each of the five types plus worked JSON examples for each.
   **Source:** https://code.claude.com/docs/en/hooks and https://code.claude.com/docs/en/hooks-guide (fetched 2026-09-04). PRIMARY. Standard/consensus — `http`, `mcp_tool`, `prompt`, and `agent` handler types are a maturation beyond the "hooks are just shell scripts" model most 2025 community writeups (including claude-code-hooks-mastery) still describe.

10. **Claim:** Async execution options: `"async": true` on a command hook runs it in the background without blocking Claude's flow, and Claude Code does not enforce a timeout on it (the `timeout` field is ignored). `"asyncRewake": true` also backgrounds the hook but wakes Claude with the hook's stderr/stdout as a system reminder specifically if the hook later exits with code 2 — letting a long-running check (e.g. a slow CI/test suite) interrupt Claude asynchronously if it fails.
   **Evidence:** "Async Hook Options" section with both JSON examples.
   **Source:** https://code.claude.com/docs/en/hooks (fetched 2026-09-04). PRIMARY. Standard/consensus.

11. **Claim:** Timeout defaults are type- and event-specific: `command`/`http`/`mcp_tool` default to 600s (10 min), lowered automatically to 30s for `UserPromptSubmit`/`PreModelSwitch`/`PostModelSwitch` and 10s for `MessageDisplay`; `prompt` hooks default to 30s; `agent` hooks default to 60s; all `SessionEnd` hooks of any type share a combined 1.5s budget (extendable up to 60s if a per-hook `timeout` is set higher). All are overridable per-hook via the `timeout` field (seconds).
   **Evidence:** "Common Hook Fields" table and the guide's "Limitations" bullet list, both giving the same numbers.
   **Source:** https://code.claude.com/docs/en/hooks and https://code.claude.com/docs/en/hooks-guide (fetched 2026-09-04). PRIMARY. Standard/consensus.

12. **Claim:** Hooks live in seven configurable locations that merge (don't override each other, aside from `disableAllHooks`): `~/.claude/settings.json` (user, all projects, not shareable), `.claude/settings.json` (project, committable/shareable), `.claude/settings.local.json` (project, gitignored/personal), managed/enterprise "policy settings" (org-wide, admin-controlled), a plugin's bundled `hooks/hooks.json` (active whenever the plugin is enabled), **skill YAML frontmatter** (hooks register for the rest of the session once the skill is invoked, support a skill-only `once: true` flag to auto-remove after first successful run), and **subagent YAML frontmatter** (hooks active only while that subagent runs; a subagent's `Stop` event is automatically converted to `SubagentStop` for the parent session).
   **Evidence:** "Hook Configuration Locations" table plus the "Hooks in Skills and Agents" section with worked YAML frontmatter examples for both skill and subagent.
   **Source:** https://code.claude.com/docs/en/hooks and https://code.claude.com/docs/en/hooks-guide (fetched 2026-09-04). PRIMARY. Standard/consensus — this directly answers the "skill frontmatter" part of the research question; it's genuinely new/distinct from the older "settings.json only" model most 2025 tutorials describe.

13. **Claim:** An enterprise `allowManagedHooksOnly` setting exists that force-disables user/project/local/plugin hooks (except force-enabled plugins) and narrows `statusLine`/`fileSuggestion`/`subagentStatusLine` to managed-only sources, plus disables command-sourced plugins and marketplace `headersHelper` auth commands unless explicitly re-enabled.
   **Evidence:** "Enterprise Restriction: allowManagedHooksOnly" section.
   **Source:** https://code.claude.com/docs/en/hooks (fetched 2026-09-04). PRIMARY. Standard/consensus (enterprise-tier feature, not something a solo developer needs but relevant for teams).

14. **Claim:** Multiple hooks matching the same event all run to completion **in parallel**; deny/allow decisions are then merged (most restrictive wins, in the order `deny > defer > ask > allow`), and text from every hook's `additionalContext` is kept and concatenated — but one hook returning `deny` does **not** stop a sibling hook's side effects from executing (e.g. a logging hook still writes its log entry even though a sibling hook denies the command).
   **Evidence:** "Combine results from multiple hooks" section with a worked two-hook example (a logger + a `rm -rf` blocker both firing on the same `Bash` `PreToolUse` matcher).
   **Source:** https://code.claude.com/docs/en/hooks-guide (fetched 2026-09-04). PRIMARY. Standard/consensus — an important gotcha for anyone stacking hooks for defense-in-depth.

15. **Claim:** The "Stop hook that won't let Claude finish until tests pass" pattern is official, documented, first-class behavior, not just a community hack: a `Stop` (or `SubagentStop`) hook returns `{"decision": "block", "reason": "..."}` (or exits 2) with the reason fed back to Claude as its next instruction, and Claude Code has a **built-in safety valve**: after 8 consecutive Stop-hook blocks with no progress, Claude Code force-overrides the hook and lets the turn end anyway, showing a warning. Hook authors must check `stop_hook_active` (true when the hook already forced a continuation) to avoid needless repeated blocking, and can raise/lower the 8-block cap via the `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` env var.
   **Evidence:** "Stop hook hits the block cap" troubleshooting section with exact bash snippet checking `stop_hook_active`, plus cross-reference to `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` in `/docs/en/env-vars`.
   **Source:** https://code.claude.com/docs/en/hooks-guide (fetched 2026-09-04). PRIMARY. Standard/consensus. Corroborated independently by community practitioner posts (claudefa.st Stop-hook guide, augmentedswe.com) describing the identical `stop_hook_active` check as "critical" — SECONDARY confirmation that this is the community-standard idiom, not a niche opinion. https://claudefa.st/blog/tools/hooks/stop-hook-task-enforcement (fetched 2026-09-04, SECONDARY, undated author); https://www.augmentedswe.com/p/guide-to-claude-code-hooks (fetched 2026-09-04, SECONDARY, undated author).

16. **Claim:** A first-class "done criteria" pattern now exists as a **`prompt`-type** Stop hook, letting a fast model (Haiku by default) judge completion instead of a deterministic script: `{"type": "prompt", "prompt": "Check if all tasks are complete. If not, respond with {\"ok\": false, \"reason\": \"what remains to be done\"}."}`. If the model returns `ok: false`, the `reason` becomes Claude's next instruction and the turn continues; setting `"impossible": true` in the model's response lets Claude Code allow the stop anyway (marks the condition as permanently unsatisfiable, avoiding an infinite loop). An `agent`-type Stop hook variant can actually run the test suite itself rather than just reasoning about whether it *probably* passed.
   **Evidence:** Verbatim JSON examples for both the `prompt` and `agent` Stop-hook "verify before allowing stop" patterns.
   **Source:** https://code.claude.com/docs/en/hooks-guide (fetched 2026-09-04). PRIMARY. Standard/consensus — this is the officially documented, more sophisticated version of what community repos call "verify-before-stop."

17. **Claim:** `SessionStart` context injection is officially documented with a `compact` matcher specifically for **re-injecting context lost after compaction** (distinct from ordinary session-start injection, which Anthropic recommends doing via CLAUDE.md instead): `{"matcher": "compact", "hooks": [{"type": "command", "command": "echo 'Reminder: use Bun, not npm...'"}]}`. Plain stdout text (not JSON) from a `SessionStart` hook is auto-appended to Claude's context.
   **Evidence:** "Re-inject context after compaction" worked example with exact JSON.
   **Source:** https://code.claude.com/docs/en/hooks-guide (fetched 2026-09-04). PRIMARY. Standard/consensus.

18. **Claim:** Blocking edits to protected paths (`.env`, `package-lock.json`, `.git/`) is an officially documented recipe, not just community folklore: a `PreToolUse` hook matched on `Edit|Write` runs a script that string-matches the target path against a `PROTECTED_PATTERNS` array and `exit 2`s with a `Blocked: ...` stderr message that becomes Claude's feedback.
   **Evidence:** Full worked example including the exact bash script (`protect-files.sh`) and the settings.json registration.
   **Source:** https://code.claude.com/docs/en/hooks-guide (fetched 2026-09-04). PRIMARY. Standard/consensus.

19. **Claim:** Auto-formatting after Edit/Write is the docs' own canonical first recipe: `PostToolUse` + `Edit|Write` matcher running `jq -r '.tool_input.file_path' | xargs npx prettier --write` (piping stdin JSON through `jq` to extract the changed file path, then formatting it). The docs note this only reformats files Claude edited directly with Edit/Write tools — if Claude formats via a Bash command instead, use a `FileChanged` hook for full coverage.
   **Evidence:** Exact JSON config reproduced verbatim; explicit caveat about Bash-driven writes needing `FileChanged` instead.
   **Source:** https://code.claude.com/docs/en/hooks-guide (fetched 2026-09-04). PRIMARY. Standard/consensus.

20. **Claim:** Blocking dangerous git commands (`git push`/`--force`, `git reset --hard`, `git clean -f`/`-fd`, `git branch -D`, `git checkout .`, `git restore .`) via a `PreToolUse` + `Bash` regex blocklist + `exit 2` is the community-standard pattern, independently reinvented by multiple practitioners with near-identical scripts.
   **Evidence:** Matt Pocock's "git-guardrails" skill ships the exact bash script (`DANGEROUS_PATTERNS` array, `grep -qE`, `echo "BLOCKED: ..." >&2; exit 2`), published as a Claude Code Skill (not a bare hook) at github.com/mattpocock/skills. Multiple independent posts (Dicklesworthstone/misc_coding_agent_tips_and_scripts, sandlabs.com.au, duet.so) describe the same shape.
   **Source:** https://www.aihero.dev/this-hook-stops-claude-code-running-dangerous-git-commands (fetched 2026-09-04, author Matt Pocock, published 2026-02-10). SECONDARY (practitioner blog, though the author is a known/credible Claude Code educator). Standard/consensus pattern across independent authors — i.e., convergent community practice, not one person's idiosyncratic opinion. Exact script:
   ```bash
   #!/bin/bash
   INPUT=$(cat)
   COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command')
   DANGEROUS_PATTERNS=(
     "git push" "git reset --hard" "git clean -fd" "git clean -f"
     "git branch -D" "git checkout \." "git restore \."
     "push --force" "reset --hard"
   )
   for pattern in "${DANGEROUS_PATTERNS[@]}"; do
     if echo "$COMMAND" | grep -qE "$pattern"; then
       echo "BLOCKED: '$COMMAND' matches dangerous pattern '$pattern'." >&2
       exit 2
     fi
   done
   exit 0
   ```

21. **Claim:** disler/claude-code-hooks-mastery is the most-cited community reference repo for hooks; as of this fetch it demonstrates all hook events with UV single-file Python scripts, JSON logging of every event to a `logs/` directory, a TTS/notification layer, dangerous-Bash-pattern blocking (`rm -rf`, `sudo rm`, `chmod 777`, writes to `/etc/`) via the same `exit 2` idiom, and a "meta-agent" pattern for generating new subagents.
   **Evidence:** Repo structure and code excerpts reproduced in the fetch (dangerous_patterns regex list, logs/ directory layout, `.claude/hooks/` + `validators/` + `utils/tts/` layout).
   **Source:** https://github.com/disler/claude-code-hooks-mastery (fetched 2026-09-04). SECONDARY/PRIMARY-for-itself (it's the author's own repo describing his own patterns — primary for "what this repo contains," secondary/opinion for "best practice"). One practitioner's opinionated toolkit, widely forked/cited (multiple forks found in search: hiuuhouyhkuhh, slysik) — de facto community standard reference, not an official Anthropic artifact.

22. **Claim:** `awesome-claude-code-hooks` curated lists exist from multiple maintainers (ianymu, ithiria894) cataloguing reusable hook packs; one such pack — the "Productivity Hook Pack" — bundles `verify-before-stop` (a Stop hook that blocks completion when files changed but no "VERIFIED" log entry exists from the last 5 minutes — described by its author as catching "lies of completion"), `cost-tracker`, `block-secrets`, `force-progress-update`, `pre-compact-diary`, and `enforce-autoplan`. This pack is sold commercially ($19-49), not free/open-source in full.
   **Evidence:** Repo README description of the six-hook pack and its pricing tiers.
   **Source:** https://github.com/ianymu/awesome-claude-code-hooks (fetched 2026-09-04). SECONDARY. One maintainer's curation/commercial offering — illustrates a recurring pattern name ("verify-before-stop") but is not itself an official or majority-consensus artifact.

23. **Claim:** Enforcing max file size on Write via a hook is a documented community pattern: set a `MAX_FILE_SIZE` byte threshold (example given: 500,000 bytes / 500KB) and implement a `guard_write` function in the `PreToolUse` hook script that measures the incoming content size and blocks (`exit 2`) if it exceeds the threshold.
   **Evidence:** Search-result summary describing the `MAX_FILE_SIZE` variable and `guard_write` function pattern; the source article itself (Cobus Greyling, Medium) could not be fetched directly (HTTP 403 on WebFetch) so this claim rests on the search engine's own extraction, not a verified page read.
   **Source:** Search snippet only, from a WebSearch result for "Claude Code hook enforce max file size max function length limit" (queried 2026-09-04); underlying article: https://cobusgreyling.medium.com/claude-code-hooks-f5a4a8b0e53c — **fetch failed (403)**, so treat this claim as low-confidence/SECONDARY-unverified. No official-docs equivalent recipe for max file size or max function length was found — this appears to be a DIY pattern practitioners build themselves on top of `PreToolUse`, not a documented Anthropic recipe or a widely-repeated named pattern across multiple independent sources.

## Concrete practices / configs

All of these are reproduced verbatim from the sources cited in Findings above (mostly the official docs), ready to copy into `.claude/settings.json` or a hook script.

**1. Auto-format after Edit/Write (official recipe)**
```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          { "type": "command", "command": "jq -r '.tool_input.file_path' | xargs npx prettier --write" }
        ]
      }
    ]
  }
}
```

**2. Block edits to protected paths (official recipe)** — `.claude/hooks/protect-files.sh` (chmod +x):
```bash
#!/bin/bash
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
FILE_PATH="${FILE_PATH//\\//}"
PROTECTED_PATTERNS=(".env" "package-lock.json" ".git/")
for pattern in "${PROTECTED_PATTERNS[@]}"; do
  if [[ "$FILE_PATH" == *"$pattern"* ]]; then
    echo "Blocked: $FILE_PATH matches protected pattern '$pattern'" >&2
    exit 2
  fi
done
exit 0
```
registered as:
```json
{ "hooks": { "PreToolUse": [ { "matcher": "Edit|Write", "hooks": [ { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/protect-files.sh" } ] } ] } }
```

**3. Block dangerous rm / git commands (official + community consensus)** — official minimal version uses `permissionDecision: deny` JSON output rather than bare exit 2:
```bash
#!/bin/bash
# .claude/hooks/block-rm.sh
COMMAND=$(jq -r '.tool_input.command')
if echo "$COMMAND" | grep -q 'rm -rf'; then
  jq -n '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:"Destructive command blocked by hook"}}'
else
  exit 0
fi
```
Community git-guardrails variant (Matt Pocock) blocks a wider set (`git push`, `--force`, `reset --hard`, `clean -f/-fd`, `branch -D`, `checkout .`, `restore .`) via `grep -qE` + `exit 2` — see Finding 20 for the full script.

**4. Stop hook that blocks completion until tests pass, with infinite-loop guard (official + community consensus)**
```python
#!/usr/bin/env python3
import json, sys, subprocess
input_data = json.load(sys.stdin)
if input_data.get('stop_hook_active', False):
    sys.exit(0)  # already forced once — let it stop
result = subprocess.run(['npm', 'test'], capture_output=True, timeout=60)
if result.returncode != 0:
    print(json.dumps({"decision": "block", "reason": "Tests are failing. Fix them before completing."}))
sys.exit(0)
```
```json
{ "hooks": { "Stop": [ { "hooks": [ { "type": "command", "command": "python .claude/hooks/stop-validation.py" } ] } ] } }
```
Raise/lower the built-in 8-block override cap with the `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` env var if a legitimate check needs more iterations.

**5. "Done criteria" Stop hook using an LLM judge instead of a script (official, newer pattern)**
```json
{ "hooks": { "Stop": [ { "hooks": [ { "type": "prompt", "prompt": "Check if all tasks are complete. If not, respond with {\"ok\": false, \"reason\": \"what remains to be done\"}." } ] } ] } }
```
Agent-hook variant that actually runs the tests rather than just judging:
```json
{ "hooks": { "Stop": [ { "hooks": [ { "type": "agent", "prompt": "Verify that all unit tests pass. Run the test suite and check the results. $ARGUMENTS", "timeout": 120 } ] } ] } }
```

**6. Session-start context injection, including post-compaction re-injection (official)**
```json
{
  "hooks": {
    "SessionStart": [
      { "matcher": "compact", "hooks": [ { "type": "command", "command": "echo 'Reminder: use Bun, not npm. Run bun test before committing. Current sprint: auth refactor.'" } ] }
    ]
  }
}
```
General session-start (no matcher = every start) can pull live data instead of a static string, e.g. `git status --short && echo '---' && cat TODO.md`, or `gh issue list --assignee @me --limit 5`.

**7. Auto-approve a specific permission prompt (official, `PermissionRequest`)**
```json
{
  "hooks": {
    "PermissionRequest": [
      { "matcher": "ExitPlanMode", "hooks": [ { "type": "command", "command": "echo '{\"hookSpecificOutput\": {\"hookEventName\": \"PermissionRequest\", \"decision\": {\"behavior\": \"allow\"}}}'" } ] }
    ]
  }
}
```
Keep the matcher narrow — an empty/`.*` matcher here auto-approves *every* permission prompt including file writes and shell commands.

**8. Reload env vars on directory/file change (official, `CwdChanged` + `FileChanged` + `direnv`)**
```json
{
  "hooks": {
    "SessionStart": [ { "hooks": [ { "type": "command", "command": "direnv export bash > \"$CLAUDE_ENV_FILE\"" } ] } ],
    "CwdChanged":   [ { "hooks": [ { "type": "command", "command": "direnv export bash > \"$CLAUDE_ENV_FILE\"" } ] } ]
  }
}
```

**9. Desktop notification when Claude needs input (official, `Notification`, cross-platform)**
```json
{ "hooks": { "Notification": [ { "matcher": "", "hooks": [ { "type": "command", "command": "notify-send 'Claude Code' 'Claude Code needs your attention'" } ] } ] } }
```
(macOS: `osascript -e 'display notification ...'`; Windows PowerShell: `[System.Windows.Forms.MessageBox]::Show(...)`.)

**10. Max file size guard on Write (community DIY, unverified/low-confidence — see Finding 23)**
Pattern only, not a verified exact script: set `MAX_FILE_SIZE` (e.g. 500000 bytes) and check `tool_input.content` length in a `PreToolUse` + `Write` hook, `exit 2` if over. No official docs recipe or independently-corroborated exact script was found for this or for "max function length" enforcement — build it yourself on the documented `PreToolUse`/`tool_input` contract if needed; there's nothing special about it beyond the general blocking pattern.

**Practical gotchas worth keeping in mind (all official, from the troubleshooting section):**
- `additionalContext` must be nested under `hookSpecificOutput` — top-level placement is silently ignored.
- Shell-form command hooks spawn a non-interactive shell that can still source `~/.bashrc`/`~/.zshrc` on some platforms (Git Bash on Windows); unconditional `echo` in your profile can prepend text to your hook's JSON stdout and silently break parsing. Guard profile echoes with `if [[ $- == *i* ]]; then ... fi`.
- Prefer exec form (`"args": [...]`) over shell-form string concatenation with `${CLAUDE_PROJECT_DIR}` to avoid quoting bugs and unwanted shell interpretation.
- When several `PreToolUse` hooks each return `updatedInput`, the *last one to finish* wins (hooks run in parallel, order is non-deterministic) — don't have two hooks rewrite the same tool's input.
- `PostToolUse` hooks cannot undo the action — the tool has already run by the time they fire; use `PreToolUse` if you actually need to stop something.

## Disagreements and open questions

- **Event count is reported inconsistently across sources**, purely as a counting-convention issue, not a factual conflict: official docs list 33 named hook events; various blogs say "27 distinct events, 32+ with subtypes" (thepromptshelf.dev) or "30 lifecycle events" (claudefa.st, not independently verified here) or "13 hook events" (disler/claude-code-hooks-mastery, which is describing what *that specific repo* implements, not the full platform). Readers should treat the official reference table as ground truth and treat round numbers like "30" in blog titles as approximate/marketing rather than a precise spec.
- **The official `claude.com/blog/how-to-configure-hooks` post appears dated relative to the current reference** — a WebFetch of it returned content describing only "8 hook types," which (if accurately extracted) reflects an earlier, smaller feature surface, consistent with a Dec 2025 publish date inferred from the fetched content, predating the 2026 expansion to task/worktree/model-switch/elicitation events. This should be treated as introductory/superseded material, not the current spec — I was not able to independently re-verify the blog's exact publish date beyond what the fetch tool extracted, so treat that date with some caution.
- **`morphllm.com/claude-code-hooks` could not be fetched** (HTTP 429, rate-limited) despite appearing relevant in three separate search queries claiming "30 Hook Events, JSON Input, Exit Codes" for 2026 — its specific claims are omitted from this report rather than reported second-hand from a search snippet.
- **`cobusgreyling.medium.com`'s exact "max file size" hook script could not be fetched** (HTTP 403) — the `MAX_FILE_SIZE`/`guard_write` claim in Finding 23 rests only on a search-engine-generated summary, not a verified page read, and should be treated as unconfirmed.
- **No official or multiply-corroborated recipe exists for "enforce max function length" via hooks.** This is plausible to build (a `PreToolUse`/`Write`/`Edit` hook that parses the diff/content and counts lines per function) but no source — official or community — was found actually publishing one. Treat this as an open gap, not an established pattern.
- **Commercial vs. free tension in the community ecosystem**: at least one widely-linked "awesome-claude-code-hooks" curation (ianymu) packages its most-praised hook (`verify-before-stop`) as part of a $19-49 paid bundle rather than distributing it as free source — so "the community's best Stop-hook pattern" is not uniformly open, unlike the fully-open official docs examples and disler's MIT-licensed repo.

## Sources

**Primary (official Anthropic documentation, fetched directly, 2026-09-04):**
- Hooks reference — https://code.claude.com/docs/en/hooks (redirect target of docs.claude.com/en/docs/claude-code/hooks)
- Automate actions with hooks (guide) — https://code.claude.com/docs/en/hooks-guide (redirect target of docs.claude.com/en/docs/claude-code/hooks-guide)
- Claude Code power user customization: How to configure hooks (Anthropic blog) — https://claude.com/blog/how-to-configure-hooks (fetched; content suggests an earlier/introductory snapshot, ~Dec 2025 per extracted metadata — treat as superseded by the two reference/guide pages above)

**Secondary — community repos and practitioner posts (fetched directly, 2026-09-04 unless noted):**
- disler/claude-code-hooks-mastery — https://github.com/disler/claude-code-hooks-mastery
- The Prompt Shelf, "Claude Code Hooks: The Complete 2026 Production Reference" (published 2026-05-16) — https://thepromptshelf.dev/blog/claude-code-hooks-complete-reference-2026/
- augmentedswe.com, "You're using Claude Code hooks wrong" — https://www.augmentedswe.com/p/guide-to-claude-code-hooks
- claudefa.st, "Claude Code Stop Hook: Force Task Completion" — https://claudefa.st/blog/tools/hooks/stop-hook-task-enforcement
- aihero.dev / Matt Pocock, "This Hook Stops Claude Code Running Dangerous Git Commands" (published 2026-02-10) — https://www.aihero.dev/this-hook-stops-claude-code-running-dangerous-git-commands
- ianymu/awesome-claude-code-hooks — https://github.com/ianymu/awesome-claude-code-hooks

**Consulted via WebSearch snippets only (not independently fetched/verified — used for triangulation, not as cited factual claims):**
- morphllm.com, "Claude Code Hooks (2026): Block Claude Reading .env + 30 Hook Events" — https://www.morphllm.com/claude-code-hooks (WebFetch returned HTTP 429; not verified)
- cobusgreyling.medium.com, "Claude Code Hooks" — https://cobusgreyling.medium.com/claude-code-hooks-f5a4a8b0e53c (WebFetch returned HTTP 403; not verified)
- claudefa.st, "Claude Code Hooks: Complete Guide to All 30 Lifecycle Events" — https://claudefa.st/blog/tools/hooks/hooks-guide (search snippet only, not fetched)
- blakecrosley.com, "Claude Code Hooks Explained" / "Why Each of My 95 Hooks Exists" — https://blakecrosley.com/blog/claude-code-hooks-explained, https://blakecrosley.com/blog/claude-code-hooks (search snippets only)
- Dicklesworthstone/misc_coding_agent_tips_and_scripts, "DESTRUCTIVE_GIT_COMMAND_CLAUDE_HOOKS_SETUP.md" — https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/blob/main/DESTRUCTIVE_GIT_COMMAND_CLAUDE_HOOKS_SETUP.md (search snippet only)
- mattpocock/skills, git-guardrails-claude-code SKILL.md — https://github.com/mattpocock/skills/blob/main/skills/misc/git-guardrails-claude-code/SKILL.md (search snippet only; underlying script corroborated via the aihero.dev fetch above)

## Source check (independent)

Six of the report's most load-bearing claims (numeric counts, direct quotes, and a named attribution) were independently re-fetched from their cited sources on 2026-09-04. All six are CONFIRMED — the sources say what the report says they say, including exact numbers and quoted language. One fetch of the same URL initially returned a contradictory summary ("43 distinct hook events" in a header, followed by a 33-item enumeration); a second, more targeted fetch of the same page resolved this as an artifact of the fetch tool's own summarization, not a property of the source page — see Claim 1 below.

**Claim 1 — 33 hook events, full list (Finding 1 / TL;DR bullet 1)**
Source: https://code.claude.com/docs/en/hooks
Verdict: **CONFIRMED**
A targeted re-fetch asking specifically for the canonical "Hook Events" table (not the lifecycle diagram or matcher tables) returned exactly 33 rows, numbered 1–33, with event names and descriptions matching the report's list token-for-token (SessionStart, Setup, UserPromptSubmit, UserPromptExpansion, PreToolUse, PermissionRequest, PermissionDenied, PostToolUse, PostToolUseFailure, PostToolBatch, Notification, MessageDisplay, SubagentStart, SubagentStop, TaskCreated, TaskCompleted, Stop, StopFailure, TeammateIdle, InstructionsLoaded, ConfigChange, CwdChanged, DirectoryAdded, FileChanged, WorktreeCreate, WorktreeRemove, PreCompact, PostCompact, PreModelSwitch, PostModelSwitch, Elicitation, ElicitationResult, SessionEnd), ending with the page's own line: "**Total count: 33 hook events**". Note: an earlier, less-targeted fetch of the same URL produced a self-contradictory summary claiming "43 distinct hook events" in its header while still only enumerating 33 items beneath it — that "43" did not survive a second, narrower fetch and appears to be a fetch-tool/summarizer artifact rather than something the page itself states.

**Claim 2 — Exit-code semantics are per-event; exactly 4 events treat exit-0 stdout as auto-injected context; PermissionRequest doesn't honor exit 2 at all; WorktreeCreate aborts on any nonzero exit (Finding 5)**
Source: https://code.claude.com/docs/en/hooks
Verdict: **CONFIRMED**
Exact quote on the exit-0 exception list: "For most events, Claude Code writes stdout to the debug log and doesn't show it in the transcript. The exceptions are `UserPromptSubmit`, `UserPromptExpansion`, `SessionStart`, and `PostModelSwitch`, where Claude Code adds plain-text stdout as context that Claude can see and act on." Exact quote on PermissionRequest: "Exit code 2 isn't honored for this event and the permission flow proceeds unchanged. Deny through the `decision` object instead." Confirmed on WorktreeCreate: "`WorktreeCreate` fails creation on any nonzero exit no matter what your JSON says" — i.e. any nonzero exit, not just 2.

**Claim 3 — PreToolUse hooks fire before any permission-mode check, including bypassPermissions/--dangerously-skip-permissions/dontAsk, as a deliberate security boundary (Finding 8)**
Source: https://code.claude.com/docs/en/hooks-guide
Verdict: **CONFIRMED**
Exact quote: "`PreToolUse` hooks fire before any permission-mode check, in every permission mode, including `dontAsk`. A hook that returns `permissionDecision: "deny"` blocks the tool even in `bypassPermissions` mode or with `--dangerously-skip-permissions`. This lets you enforce policy that users can't bypass by changing their permission mode." — matches the report's paraphrase closely, including the "users can't bypass" framing.

**Claim 4 — Built-in Stop-hook safety net after 8 consecutive blocks without progress; `stop_hook_active` field; `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` env var to adjust the cap (Finding 15)**
Source: https://code.claude.com/docs/en/hooks-guide
Verdict: **CONFIRMED**
Exact quote: "Claude Code overrides a Stop hook after it blocks eight times in a row without progress. Your hook script needs to check whether it already triggered a continuation. Parse the `stop_hook_active` field from the JSON input and exit early if it's `true`... If your hook legitimately needs more than eight iterations to converge, raise the cap with `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`." Also confirmed: "Claude keeps working instead of stopping, then ends the turn with a warning that the Stop hook blocked too many consecutive times."

**Claim 5 — Hooks configurable in skill YAML frontmatter (registered for rest of session, `once: true` flag) and subagent YAML frontmatter (active while subagent runs, Stop→SubagentStop) (Finding 12)**
Source: https://code.claude.com/docs/en/hooks and https://code.claude.com/docs/en/hooks-guide
Verdict: **CONFIRMED**
The reference page's "Hooks in skills and agents" section states: "In addition to settings files and plugins, hooks can be defined directly in skills and subagents using frontmatter, in the same configuration format as settings-based hooks," and for skills specifically: "Claude Code registers them when you or Claude invoke the skill and keeps running them for the rest of the session... To have Claude Code remove a hook after its first successful run instead, set `once: true` on it." The guide page's configuration-locations table independently corroborates both frontmatter locations: "Skill frontmatter | The rest of the session once the skill is invoked... Yes, defined in the skill file" and "Subagent frontmatter | While that subagent is running... Yes, defined in the subagent file." (The specific "Stop becomes SubagentStop" wording was not re-quoted verbatim in this pass, but the SubagentStop event itself and its "when a subagent finishes" firing condition are independently confirmed in the reference page's event table — consistent with, though not a direct restatement of, the report's phrasing.)

**Claim 6 — Matt Pocock authored the git-guardrails dangerous-git-command-blocking pattern, published 2026-02-10 at aihero.dev, with the exact quoted bash script (Finding 20)**
Source: https://www.aihero.dev/this-hook-stops-claude-code-running-dangerous-git-commands
Verdict: **CONFIRMED**
Author and date confirmed: "Matt Pocock" (referenced as "mattpocock" in the skill installation path), published/updated 2026-02-10T14:25:36.457Z, matching the report's "published 2026-02-10." The fetched script matches the report's reproduced script verbatim, including the `DANGEROUS_PATTERNS` array, `grep -qE` matching, and `exit 2` on match — with one small addition the report's excerpt omitted: the live script's blocked-message text is "BLOCKED: '$COMMAND' matches dangerous pattern '$pattern'. The user has prevented you from doing this." (the report's Finding 20 reproduction drops the trailing sentence "The user has prevented you from doing this." — a minor, non-substantive truncation, not a misquote of meaning).

**Summary:** 6/6 checked claims CONFIRMED, 0 unsupported, 0 misattributed. No inline `[UNVERIFIED: ...]` markers were added to the report body since nothing failed verification. The two official-docs pages (code.claude.com/docs/en/hooks and hooks-guide) that anchor nearly every Finding in this report checked out accurately on every specific number, table row, and verbatim quote sampled — including unusual, easy-to-get-wrong specifics (the WorktreeCreate any-nonzero-exit outlier, the PermissionRequest exit-2-ignored quirk, the exact 8-block cap and its env var name). The one wrinkle encountered was a transient fetch-tool artifact (a "43 events" header contradicting the same response's own 33-item list), which a second fetch resolved in the source's favor — worth flagging as a reminder that single WebFetch summaries can self-contradict and are worth re-querying when a headline number and a detailed enumeration disagree, but not evidence of a flaw in the underlying report. Overall reliability of this report, based on this sample: high — the report's PRIMARY-sourced claims are trustworthy as written, and its own internal hedging on weaker SECONDARY claims (Finding 23's max-file-size pattern, the morphllm.com and cobusgreyling.medium.com fetch failures) was already appropriately flagged by the report's author rather than overstated.
