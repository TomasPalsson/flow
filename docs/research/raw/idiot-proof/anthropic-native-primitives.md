# Anthropic-native idiot-proofing primitives — source-level delta

Angle: what Claude Code itself ships for idiot-proofing, and which flow shell hooks are now
re-implementations of a platform primitive. All sources fetched **2026-09-07**.
PRIMARY = vendor/author source (code.claude.com docs, anthropics/* repos). SECONDARY = anything else.
Delta only: hook event/exit semantics already covered in `07-harness-smoothness-2026.md` §A are not
restated except where an idiot-proofing consequence changes.

---

## 0. BLUF

1. flow enforces in ~2,000 lines of bash what Claude Code now enforces in the client, at OS level,
   or in a classifier — and flow's own author documented the weakness: `git-guard.sh:4` says
   *"This is a regex blocklist over a command string… it is not a security boundary — `bash -c`,
   `eval`, variable construction, and a helper script written via Edit all evade it."*
2. `~/.claude/settings.json` on this machine (read 2026-09-07) has **no `permissions` key, no
   `sandbox` key, no `defaultMode`**. Every guarantee in this harness is carried by the evadable
   layer, and none by the unevadable one. This is the single largest idiot-proofing gap.
3. `permissions.deny` is evaluated *before* PreToolUse hooks and *cannot* be overridden by a hook
   returning `allow` (PRIMARY, permissions.md). It is the only rule tier that is strictly stronger
   than git-guard.
4. Claude Code has two built-in circuit breakers flow does not know about: **protected paths**
   (`.git`, `.claude`, `.envrc`, `.pre-commit-config.yaml`, `.mcp.json`, shell rc files — never
   auto-approved, and `permissions.allow` cannot pre-approve them) and **critical paths** (`rm`/
   `rmdir` targeting `/`, `~`, cwd or its parents — no allow rule and no PreToolUse `allow` can
   approve them).
5. The Bash sandbox is OS-enforced (Seatbelt / bubblewrap+seccomp) and covers *child processes*,
   which is exactly the class git-guard cannot see: a python script that calls `shutil.rmtree`.
   Default read scope is still the whole disk unless `sandbox.credentials` or `denyRead` is set.
6. `sandbox.failIfUnavailable: true` converts the sandbox from fail-open to fail-closed. Default is
   fail-open with a warning — a silent degradation flow's "nothing silently degrades" rule forbids.
7. Hook `if:` (permission-rule syntax, e.g. `"if": "Bash(git commit:*)"`) is the native answer to
   flow's 12 hooks that each spawn a process and then `grep` themselves out. `worklog-hook.sh` runs
   on **7 events with no matcher** — it is the most expensive no-op in the harness.
8. `asyncRewake` + `rewakeMessage`/`rewakeSummary` is the native "expensive check that doesn't block
   the turn, but re-wakes Claude if it finds something". Anthropic's own `security-guidance` plugin
   uses it for post-commit review; flow's `stop-gate.sh` blocks synchronously for up to 600 s.
9. `/goal` is a supported session-scoped prompt Stop hook with a fresh-model evaluator, impossible-
   condition detection, unrecoverable-error clearing, and background-work deferral. flow's
   `stop-gate.sh` re-implements the loop-control half of it (wedge valve at 3 identical blocks)
   without the evaluator half.
10. `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` (default 8 consecutive blocks, then force-override) means a
    Stop gate can never wedge a session permanently. flow's 3-block wedge valve is a stricter, and
    therefore still useful, private version — keep it, but stop treating it as the only backstop.
11. Auto memory (`type: feedback`) already writes corrections to
    `~/.claude/projects/<project>/memory/` by default. `lesson-nudge.sh` is a phrase-matcher that
    prompts a human to do what the platform is already doing silently.
12. Diagnostics are now native and specific: `claude doctor` (read-only, catches invalid settings
    files and dropped `hooks` keys), `/doctor` (proposes fixes), `/hooks`, `/permissions`,
    `/context`, `/status`, `/skill-doctor` (unused-skill context cost, v2.1.261),
    `claude plugin validate <dir>` (v2.1.233+, catches frontmatter YAML errors).
13. Escape hatches are native and discoverable: `--safe-mode` / `CLAUDE_CODE_SAFE_MODE` (all
    customization off, managed policy still on), `disableAllHooks`, `--restricted`,
    `CLAUDE_CONFIG_DIR=/tmp/clean`. flow's `.claude/flow.off` marker is a private fourth escape
    hatch that `/hooks` and `claude doctor` cannot see.
14. Fail-open is the platform default nearly everywhere (hook timeout on PreToolUse does not block;
    invalid hook JSON is a non-blocking error; sandbox unavailable runs unsandboxed). The two
    fail-closed events are `WorktreeCreate` (any nonzero exit aborts) and `dontAsk` mode.
15. Adoption order: put a real `permissions.deny` block in `~/.claude/settings.json` first, turn on
    the sandbox second, add `if:` to every flow hook third. Everything else is polish.

---

## 1. Sources

All PRIMARY, all fetched 2026-09-07. Docs pages under `https://code.claude.com/docs/en/`:
**S1** `hooks` · **S2** `hooks-guide` · **S3** `permissions` · **S4** `permission-modes` ·
**S5** `sandboxing` · **S6** `memory` · **S7** `skills` · **S8** `goal` · **S9** `checkpointing` ·
**S10** `debug-your-config` · **S11** `commands` · **S12** `settings-reference`.
**S13** = `raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md` (through v2.1.263).
Files from `anthropics/claude-plugins-official`: **S14** `security-guidance/hooks/{hooks.json,
extensibility.py,_base.py}` · **S15** `hookify/{hooks/*.py,examples/*.local.md,skills/writing-rules/
SKILL.md}` · **S16** `ralph-loop/hooks/stop-hook.sh` · **S17** `claude-security/hooks/hooks.json` ·
**S18** `claude-code-setup/.../references/hooks-patterns.md`. **S19** = local
`~/.claude/settings.json` + `plugins/flow/hooks/*`.

Repo scan: the complete set of plugins in `anthropics/claude-plugins-official` carrying a `hooks/`
dir is `claude-security`, `explanatory-output-style`, `hookify`, `learning-output-style`,
`ralph-loop`, `security-guidance`. All six fetched; the two output-style plugins register only a
`SessionStart` banner script and carry no idiot-proofing mechanism.

---

## 2. Primitive catalog

Format per primitive: **mistake class removed → defaults → fail open/closed → escape →
flow duplication**.

### 2.1 `permissions.deny` / `ask` / `allow`  (S3)

* **Removes**: the entire class "the model ran a destructive command the harness meant to forbid".
* **Mechanism, quoted**: *"Rules are evaluated in order: deny, then ask, then allow. The first match
  in that order determines the outcome, and rule specificity doesn't change the order."* And, decisively:
  *"Hook decisions don't bypass permission rules. Claude Code evaluates deny and ask rules regardless
  of what a PreToolUse hook returns."*
* **Defaults**: empty. On this machine: **absent entirely** (S19).
* **Fail**: closed for deny (a bare tool-name deny *removes the tool from Claude's context*, so it is
  never even attempted). Allow rules fail open by design.
* **Escape**: `/permissions` UI; `--permission-mode`; `bypassPermissions` skips prompts but *not*
  deny rules; `permissions.disableBypassPermissionsMode` locks that off.
* **Sharp edges**: compound commands split on `&& || ; | |& &` + newlines and a deny matches *any*
  subcommand, including inside `$( )`/backticks/`for` bodies; deny/ask match past leading env
  assignments (`FOO=bar rm -rf tmp/` matches `Bash(rm *)`), allow rules do not; wrappers
  `timeout time nice nohup stdbuf command builtin noglob` and bare `xargs` are stripped, but
  `devbox run`/`npx`/`docker exec` are **not** (`Bash(devbox run *)` would approve
  `devbox run rm -rf .`); `Bash(command:rm *)` is *ignored with a startup warning*; a `Read(...)`
  deny also blocks Edit and Write but **not** NotebookEdit. Deny rules do *not* cover arbitrary
  subprocesses: *"They don't apply to… a Python or Node script that opens files itself. For
  OS-level enforcement… enable the sandbox."*
* **flow duplication**: `hooks/git-guard.sh` (7.4 KB, tokenizer + regex fallback + 20,000-char cap).
  Covers `git push --force`, `reset --hard`, `clean -f`, `checkout -- .`, `restore .`, `branch -D`,
  `commit --no-verify`, `rm -rf`, `chmod -R 777`. **Every one of these is expressible as a
  `permissions.deny` entry** that also survives `bash -c`, env-var prefixes and subshells, which
  git-guard's own header admits it does not.

### 2.2 Protected paths — built-in, unbypassable by allow rules (S4)

* **Removes**: "the agent edited its own config / git internals / your shell rc and widened its own
  permissions".
* **Quoted**: *"`permissions.allow` rules in settings files do not pre-approve protected-path writes.
  The safety check runs before Claude Code evaluates allow rules."*
* **Dirs**: `.git`, `.config/git`, `.vscode`, `.idea`, `.husky`, `.cargo`, `.devcontainer`, `.yarn`,
  `.mvn`, `.claude` (except `.claude/worktrees`). **Files**: `.gitconfig`, `.gitmodules`, every
  bash/zsh rc + `.profile` + `.envrc`, `.npmrc`, `.yarnrc(.yml)`, `.pnp.cjs`, `.pnpmfile.cjs`,
  `bunfig.toml`, `.bazelrc`, `.pre-commit-config.yaml`, `lefthook.y*ml`, `gradle-wrapper.properties`,
  `.devcontainer.json`, `.ripgreprc`, `pyrightconfig.json`, `.mcp.json`, `.claude.json`.
* **Per mode**: `default`/`acceptEdits` → prompted; `plan` → classifier or prompt; `auto` → classifier;
  `dontAsk` → **denied**; `bypassPermissions` → allowed. Fail-closed except under
  `bypassPermissions`; `--restricted` (v2.1.248+) also forbids the classifier from approving them.
* **flow duplication**: none — flow has *no* protection for `.claude/`, `.envrc` or `.pre-commit-config.yaml`.
  `tamper-notice.sh` warns after the fact on gate-config edits only. **This is a gap, not a duplication.**

### 2.3 Critical paths — `rm` circuit breaker (S4)

* **Removes**: `rm -rf /`, `rm -rf ~`, `rm -rf "$UNSET_VAR"/*`, and the same hidden inside `$( )`.
* **Quoted**: *"Claude Code never lets a `permissions.allow` rule or a `PreToolUse` hook that returns
  `"allow"` approve an `rm` or `rmdir` command that targets a critical path."*
* Targets: filesystem root, any direct child of root, home dir, drive roots, **cwd and its parents**,
  and a glob/trailing slash under a shell variable. `dontAsk` denies; `bypassPermissions` still asks.
* v2.1.263 extended the check to `rm -rf` on positional parameters and inside double-quoted `sh -c`.
* **flow duplication**: `git-guard.sh` `rm -rf`-on-root-like-target branch. Native version is
  strictly stronger (variable-aware, substitution-aware, cwd-parent-aware).

### 2.4 Bash sandbox — OS-level, covers child processes (S5)

* **Removes**: "a script the agent wrote deleted/read something outside the project"; "a build tool
  exfiltrated `~/.aws/credentials`"; "an install script phoned home".
* **Defaults**: writes allowed to cwd + session temp + `additionalDirectories`. **Reads default to
  the entire computer**, *"Note that this default still allows reading credential files such as
  `~/.aws/credentials` and `~/.ssh/`."* No domains pre-allowed; first new domain prompts (or goes to
  the classifier in auto mode). `autoAllowBashIfSandboxed` defaults **true**.
* **Fail**: **open by default** — *"if the sandbox cannot start because dependencies are missing or
  the platform is unsupported, Claude Code shows a warning and runs commands without sandboxing."*
  `sandbox.failIfUnavailable: true` makes it fail closed.
* **Escapes, layered and discoverable**: the `dangerouslyDisableSandbox` retry — Claude sees the
  named path/host it violated and may retry outside, going through the normal permission flow, with
  the prompt titled *"Bash command (unsandboxed)"* so you can always tell;
  `"allowUnsandboxedCommands": false` = **Strict sandbox mode** in the `/sandbox` Overrides tab;
  an `ask` rule for `Bash(dangerouslyDisableSandbox:true)` prompts on every retry even in auto mode;
  `sandbox.excludedCommands` for tools that genuinely cannot be sandboxed.
* **Protected-within-allowed**: the sandbox separately denies writes to the config/code files Claude
  loads, *"There is no way to exempt one of these paths."*
* **Credentials** (v2.1.187+): `sandbox.credentials.files`/`.envVars` with `mode: deny|mask`. `deny`
  unsets the var inside the sandbox; `mask` shows a sentinel and the proxy substitutes the real value
  only on `injectHosts`. `deny` entries merge across *every* settings scope; no scope can remove one.
* **Network**: `network.allowedDomains`, `deniedDomains`, `strictAllowlist: true` (v2.1.219+, denies
  instead of prompting), `allowManagedDomainsOnly` (managed only); `WebFetch(domain:...)` allow rules
  feed the same allowlist.
* **flow duplication**: none, and this is the biggest missing layer. `post-bash-write.sh` exists
  *because* Bash writes bypass the Edit hooks; the sandbox makes those same writes bounded regardless
  of whether any hook fires.

### 2.5 Permission modes and the auto-mode classifier (S4)

Modes: `default` (alias `manual`), `acceptEdits`, `plan`, `auto`, `dontAsk`, `bypassPermissions`.
`auto` is the built-in start mode on Pro/Max/Team; a second model reviews each non-trivial action.
Worth stealing conceptually: *"if the classifier blocks an action 3 times in a row or 20 times total,
auto mode pauses and Claude Code resumes prompting"* (not configurable) — flow's stop-gate wedge
valve at 3 identical blocks is the same idea, independently invented. Conversational boundaries
("don't push") are honoured by the classifier but *"are not stored as rules… a boundary can be lost
if context compaction removes the message… For a hard guarantee, add a deny rule instead."*
`dontAsk` is the CI-safe mode: auto-denies anything not in `permissions.allow`, never waits.
Trap: `defaultMode: "auto"` and `"bypassPermissions"` are **silently ignored** in project/local
settings and only apply from `~/.claude/settings.json` or managed settings — catch it with `/status`.
flow duplication: `spec-gate.sh` partially overlaps plan mode, but plan mode has no repo-specific
plan-lint notion. **Keep spec-gate.**

### 2.6 Hook `if:` — permission-rule filter on a handler (S1, S13, S14, S17)

```json
{ "type": "command", "command": "...", "if": "Bash(git commit:*)", "asyncRewake": true }
```
* Added v2.1.~232 *"reducing process spawning overhead"*; fixed for Read/Edit/Write path patterns and
  for compound/env-prefixed commands in later releases (S13 lines 1988, 3707, 566).
* Anthropic's own plugins use it as the primary dispatch mechanism: `security-guidance` registers
  five separate `Bash` PostToolUse handlers keyed on `Bash(git commit:*)`, `Bash(git push:*)`,
  `Bash(gt create:*)`, `Bash(gt modify:*)`, `Bash(gt submit:*)`; `claude-security` uses
  `"if": "Bash(python3 *claude-security*scripts/*.py *)"`.
* **flow duplication**: every flow hook opens with `hook_skip_if_off`, then re-reads stdin, then
  greps its own applicability. `worklog-hook.sh` is registered on SessionStart, UserPromptSubmit,
  PreToolUse (no matcher), PostToolUse (no matcher), Stop, SubagentStop, SessionEnd — 7 registrations,
  zero matchers, spawning a process on **every tool call**.

### 2.7 `statusMessage`, `once`, `async`, `asyncRewake` (S1, S14)

`statusMessage` = custom spinner text while a hook runs; directly addresses "the harness went quiet
for 40 s and I didn't know why" — `stop-gate.sh` has `timeout: 600` and no status message.
`once: true` = remove the hook after its first successful run (**skill frontmatter only**).
`async: true` = background, non-blocking, *timeout not enforced*. `asyncRewake: true` = background,
and **exit 2 wakes Claude** with stdout/stderr as a system reminder; pairs with `rewakeMessage` /
`rewakeSummary` (used verbatim by `security-guidance`, e.g.
`"rewakeSummary": "Commit security review found issues"`). Timeout defaults: 600 s command/http/
mcp_tool, 30 s prompt, 60 s agent; forced to 30 s on `UserPromptSubmit`, 10 s on `MessageDisplay`;
SessionEnd hooks share a 1.5 s budget. Fail-open: on `PreToolUse`, *"a timed-out command/http/
mcp_tool doesn't block"*.

### 2.8 Hook events flow does not use (S1, S13)

Blocking (exit 2): **`PostToolBatch`** — stops the agentic loop before the next model call after a
whole parallel batch resolves, the right place for a once-per-batch gate instead of a per-edit one;
**`ConfigChange`** — blocks a settings change mid-session except `policy_settings`, the native
anti-tamper hook; **`WorktreeCreate`** — *"fails on any nonzero exit regardless of JSON output"*, the
only strictly fail-closed event. Non-blocking: **`PermissionRequest`** (answer prompts
programmatically via the `decision` object; `updatedInput` is re-checked against `permissions.deny`,
S13:3344); **`PermissionDenied`** (fires after an auto-mode classifier denial — *"return
`{retry: true}` to tell the model it can retry"*, S13:3684); **`PostToolUseFailure`** (react to a
*failed* tool call — flow currently sees only successes); **`FileChanged`** (matcher is a literal
filename list, `.envrc|.env`); **`InstructionsLoaded`** (log which CLAUDE.md/rules actually loaded);
**`Setup`** (`--init`/`--maintenance` in `-p`); **`SubagentStart`**.

### 2.9 Prompt/agent hooks and the Stop-hook safety net (S2, S13:2578, S13:2143)

`type: "prompt"` sends the hook input to Haiku (or `model:`) and returns `{"ok": bool, "reason": str}`.
On `Stop`, `ok:false` feeds `reason` back and Claude keeps working — unless `"impossible": true`,
which ends the turn. `continueOnBlock: true` turns a `PreToolUse`/`PostToolUse` block into
feed-back-and-continue. `type: "agent"` is the same with the default model. Together these are the
supported way to write a judgement gate without a shell script. Safety net:
*"Claude Code overrides a Stop hook after it blocks eight times in a row without progress"*
(`CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`); hooks must read `stop_hook_active` and exit 0 when true. Since
v2.1.~215 `Stop`/`SubagentStop` can return `hookSpecificOutput.additionalContext` to give feedback
and keep the turn going *without being labelled a hook error* — strictly nicer than `hook_block`.

### 2.10 `/goal` (S8)

A session-scoped prompt-based Stop hook with fresh-model evaluation each turn; three verdicts
(met / not yet / **impossible**); automatic clearing on unrecoverable errors (auth failure, exhausted
credits, unclearable context overflow, unavailable model) with the message
`Goal cleared after an unrecoverable error … Run /goal again to continue`; deferral while background
work runs, with backing-off check-ins (`CLAUDE_CODE_GOAL_CHECKIN_MINUTES`, `0` = off, max 3 idle
check-ins per goal); and no-tool-use stall detection. Unavailable — *with an explanatory message, not
silently* — when `disableAllHooks` or `allowManagedHooksOnly` is set.

### 2.11 Auto memory, path-scoped rules, checkpointing (S6, S9)

**Auto memory** is on by default: Claude writes four `type`s — `user`, `feedback`, `project`,
`reference` — to `~/.claude/projects/<project>/memory/`, shared across worktrees of one repo and
excluded from the `cleanupPeriodDays` sweep. `MEMORY.md` index: first 200 lines / 25 KB loaded every
session; over the limit the write succeeds but Claude Code *returns an error telling Claude to
rewrite the index*. Disable via the `/memory` toggle → `autoMemoryEnabled`, or
`CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`; relocate via `autoMemoryDirectory`. `feedback` is explicitly
*"corrections you give Claude"* — the exact payload `lesson-nudge.sh` nags a human about.

**`.claude/rules/*.md` with `paths:`** load only when Claude touches a matching file (brace-expansion
budget 1,000 patterns / 4 MiB, symlink-resolved) — the native way to stop a long CLAUDE.md being paid
every session. `claudeMdExcludes` (glob, merges across layers) skips other teams' files.

**Checkpointing** snapshots before each user prompt, 100 per session, survives resume, swept after
`cleanupPeriodDays`. `/rewind` or double-`Esc`. It does **not** cover files changed by Bash commands,
background subagent edits, external edits, or symlinked/hard-linked paths (skipped with a
`Restored the code, but skipped N files` warning). A harness that pushes writes through Bash — which
auto mode's own instructions encourage — is opting out of undo.

### 2.12 Escape hatches and diagnostics (S10, S11, S13)

| Mechanism | What it turns off | Discoverable via |
|---|---|---|
| `--safe-mode` / `CLAUDE_CODE_SAFE_MODE` | CLAUDE.md, skills, plugins, hooks, MCP, custom commands/agents. Managed hooks + policy stay | `claude --help`, docs |
| `disableAllHooks` | all hooks + statusLine + fileSuggestion; respects managed hierarchy | `/hooks`, `claude doctor` |
| `--restricted` / `CLAUDE_CODE_RESTRICTED=1` | command/code-running tools + WebFetch; refuses bypassPermissions; ignores user/project/local settings | v2.1.248 |
| `CLAUDE_CONFIG_DIR=/tmp/clean` | everything under `~/.claude` | docs |

Diagnostics: `claude doctor` (terminal, no session — invalid settings files, a `hooks` key rejected
as a schema error, unreliable sandbox domain spellings); `/doctor` (that plus unused extensions,
duplicate subagent names, and proposed CLAUDE.md trims, with fixes offered); `/hooks` (read-only
browser of every registered hook, by event, with source); `/permissions` (resolved rules plus a
**Recently denied** tab where `r` retries); `/context` (what actually occupies the window, incl.
bundled skills); `/status` (which settings sources are active); `/skill-doctor` (per-skill token cost
+ invocation frequency + unused skills, v2.1.261, terminal only); `/insights` (HTML report over
recent sessions); `/usage` aka `/cost` (tokens, costs, likely prompt-cache-miss cause);
`claude plugin validate <dir>` (skill frontmatter YAML errors, v2.1.233+).

Silent-failure traps the docs name explicitly (all catchable by the above): a `matcher` given as a
JSON **array** rejects the *entire* settings file; a lowercase `"bash"` matcher matches nothing;
hooks placed in a standalone file are ignored (only plugins get `hooks/hooks.json`); `permissions`/
`hooks`/`env` written into `~/.claude.json` instead of `~/.claude/settings.json` are ignored.

### 2.13 What Anthropic's own plugins do (S14–S18)

* **hookify** — user-writable rules as `.claude/hookify.<name>.local.md` with YAML frontmatter
  (`name`, `enabled`, `event: bash|file|stop|prompt|all`, `action: warn|block`, `pattern`, or a
  `conditions:` list of `field`/`operator`/`pattern`). Four thin Python entry points, each ending
  `finally: sys.exit(0)` under the comment *"ALWAYS exit 0 - never block operations due to hook
  errors"*; import errors still emit `{"systemMessage": "Hookify import error: …"}` — fail-open but
  never silent. This is the shipped answer to "let the user add a rule without writing a hook".
* **security-guidance** — `asyncRewake` + `if:` for post-commit/push review. `extensibility.py`
  documents an additive-only extension model: guidance capped at 8 KB, ≤50 custom patterns, regexes
  rejected for ReDoS structure, *"Built-in patterns cannot be disabled"*, kill switch all-or-nothing
  (`ENABLE_PATTERN_RULES=0`), discovery precedence mirroring settings (`~/.claude/` → project →
  `*.local.*`). `_base.py` keeps state under `~/.claude/security` and refuses `/tmp` as
  world-writable (TOCTOU/symlink surface) — worth copying; flow's stamps live in `${TMPDIR:-/tmp}`.
* **ralph-loop** — Stop hook returning `{"decision":"block","reason":<prompt>,"systemMessage":…}`,
  with **session isolation** (compares `session_id` in the state file against the hook input, so a
  loop started in one session cannot block another) and a corruption path that prints a diagnosis to
  stderr, deletes the state file, and exits 0. The model for "loud refusal, remediation in message".
* **claude-security** — `UserPromptExpansion` with matcher `^claude-security:claude-security$` to
  attach a banner to one slash command; `asyncRewake` metrics on `PostToolUse` **and**
  `PostToolUseFailure`.
* **hooks-patterns.md** — Anthropic's own recommendation table: Prettier/ESLint/Ruff/gofmt/rustfmt →
  PostToolUse format; tsconfig → `tsc --noEmit`; `.env`/`credentials.json`/`.git/` → **PreToolUse
  block**; lock files → **PreToolUse block**. flow implements the formatter row and neither block row.

---

## 3. Duplication ledger — flow shell vs native primitive

| flow file | Native primitive | Verdict |
|---|---|---|
| `hooks/git-guard.sh` | `permissions.deny` + critical-path breaker + sandbox | **Replace the enforcement, keep the file as a teaching layer.** Move every pattern to `permissions.deny` in `~/.claude/settings.json`; keep git-guard only for patterns deny cannot express (`chmod -R 777`, `--no-verify`) and let it emit the *reason*, since deny's message is terse. |
| *(nothing)* | protected paths + `sandbox.filesystem` | **Adopt.** No flow equivalent exists for `.claude/`, `.envrc`, `.pre-commit-config.yaml`, `.mcp.json`. |
| `hooks/post-bash-write.sh` | sandbox (bounds Bash writes) + `FileChanged` | **Keep, but shrink.** Sandbox removes the danger; the hook still adds format/size/tamper coverage. Add `if:` so it stops spawning on read-only commands. |
| `hooks/format-lint.sh` | PostToolUse + `if: "Edit(**/*.ts)"` + `statusMessage` | **Keep the script, adopt `if:` + `statusMessage`.** No native formatter hook exists; S18 confirms Anthropic's own answer is also "write a PostToolUse hook". |
| `hooks/size-guard.sh`, `hooks/size_guard.py` | none | **Keep.** No native equivalent. |
| `hooks/tamper-notice.sh` | `ConfigChange` (for settings files) + protected paths | **Keep for test-weakening; delegate config-file tamper to `ConfigChange` + protected paths.** |
| `hooks/lesson-nudge.sh` | auto memory `type: feedback` | **Replace.** The platform already records corrections by default; the nudge adds per-turn output for something already happening. Keep `/lesson` the *skill*; drop the hook. |
| `hooks/stop-gate.sh` (600 s, blocking) | Stop + `stop_hook_active` + `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` + `additionalContext`; `/goal`; `asyncRewake` | **Keep, modernise.** Add `statusMessage`; switch the non-fatal path to `additionalContext` instead of a block; consider `asyncRewake` for the full sweep so the turn is not held. |
| `hooks/spec-gate.sh` | plan mode | **Keep.** Plan mode has no plan-lint / approved-plan-on-disk notion. |
| `hooks/session-context.sh` | SessionStart stdout-to-context (native) | **Keep** — it already uses the documented mechanism, with a 20-line self-cap. |
| `hooks/notify.sh` | hook JSON `terminalSequence` field | **Simplify.** `terminalSequence` emits bells/notifications *without a controlling terminal* — a `notify-send`/`osascript` shell-out is no longer required. |
| `hooks/subagent-log.sh` | already `async: true` | **Keep.** |
| `hooks/worklog-hook.sh` × 7 events, no matcher | `if:` filters + real matchers | **Fix.** Highest per-turn cost in the harness for zero enforcement value. |
| `flow off` → `.claude/flow.off` | `disableAllHooks`, `--safe-mode`, `--restricted` | **Keep, but make it visible.** A private marker is invisible to `/hooks` and `claude doctor`. Either write `disableAllHooks` into `.claude/settings.local.json` (visible in `/status`) or keep the marker and have `flow doctor` report it. `session-context.sh` already prints an OFF banner — that is the right instinct. |
| `flow doctor` | `claude doctor`, `/doctor`, `/hooks`, `/permissions`, `/skill-doctor`, `claude plugin validate` | **Keep, and have it shell out.** `flow doctor` should run `claude doctor --json` and `claude plugin validate plugins/flow/skills` rather than re-deriving deployment health. |
| `hooks/codebase-map.sh` | none | **Keep.** |
| `scripts/skills-lint` | `claude plugin validate`, `/skill-doctor` | **Keep the repo-specific rules, delegate YAML validity + unused-skill cost.** |

---

## 4. Ten most adoptable mechanisms, ranked

1. **`permissions.deny` block** in `~/.claude/settings.json` → prevents force-push, `reset --hard`,
   `clean -f`, `--no-verify`, `.env` reads — *unbypassable by any hook, subshell or env prefix*.
2. **Bash sandbox** (`sandbox.enabled` + `sandbox.credentials` + `failIfUnavailable: true`) →
   prevents a script the agent wrote from touching `~/.ssh`, `~/.aws`, or an un-allowlisted host,
   and stops the sandbox from silently degrading to unsandboxed.
3. **Hook `if:` on every flow handler** → removes ~10 process spawns per tool call and the
   grep-yourself-out boilerplate; the same mechanism Anthropic's own plugins use.
4. **`asyncRewake` + `rewakeMessage`** on the expensive Stop-gate sweep → removes the 600 s
   synchronous block while keeping the finding; verbatim the `security-guidance` pattern.
5. **`statusMessage`** on `stop-gate.sh`, `format-lint.sh`, `post-bash-write.sh` → removes "the
   harness froze and I don't know which hook is running".
6. **`stop_hook_active` + `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` + `additionalContext`** → removes the
   wedged-session class and stops non-fatal gate feedback from being reported as a hook error.
7. **Auto memory as the `/lesson` substrate** (drop `lesson-nudge.sh`) → removes per-turn nudge
   output for something the platform already does by default.
8. **`ConfigChange` + protected paths** → prevents the agent from editing `.claude/`, `.envrc`,
   `.pre-commit-config.yaml` or `.mcp.json` and thereby widening its own permissions.
9. **`flow doctor` shells out to `claude doctor --json` / `claude plugin validate` / `/skill-doctor`**
   → prevents a broken deployment (array matcher rejecting a whole settings file, lowercase matcher,
   invalid skill frontmatter) from looking healthy.
10. **`dontAsk` mode for workflow/fleet runs** (with an explicit `permissions.allow`) → prevents an
    unattended fleet agent from hanging on a prompt or silently taking an unapproved action; it
    auto-denies instead, and never waits for input.

Each maps to a file: 1–2 → `~/.claude/settings.json` (not in the plugin; `plugins/flow/bin/flow init`
should write them); 3–5 → `plugins/flow/hooks/hooks.json`; 6 → `plugins/flow/hooks/stop-gate.sh`;
7 → delete `plugins/flow/hooks/lesson-nudge.sh`, edit `plugins/flow/skills/…/lesson`; 8 → new handler
in `plugins/flow/hooks/hooks.json` + `tamper-notice.sh`; 9 → `plugins/flow/bin/flow`; 10 →
`plugins/flow/workflows/*.js`.

---

## 5. UNVERIFIED register

* **`once: true` outside skill frontmatter** — S1 lists `once` under common handler fields but
  annotates it "(skill frontmatter only)". Whether a plugin `hooks.json` handler honours it: UNVERIFIED.
* **Exact defaults for `sandbox.*` / `permissions.*` keys** — S12's reference table returned
  descriptions without defaults; every default quoted above comes from S4/S5 prose instead.
* **`/insights` and `/usage` output** — only the one-line descriptions in S11 plus changelog
  bug-fix lines; neither page fetched. Whether `/insights` can be scripted: UNVERIFIED.
* **`skillOverrides` schema** — named in S12 and S13 but the key's shape was not fetched.
* **Whether a `permissions.deny` rule can be evaded via `git -c core.fsmonitor=<script>`** — S3 notes
  the *allow* direction matches `-c`; the deny direction is untested.
* **`.claude/flow.off` vs `disableAllHooks`** — `plugins/flow/hooks/tests/test_flow_off.sh` has no
  case for the native flag. flow's OFF banner cannot print when hooks are disabled natively (the
  SessionStart hook is itself disabled): a real discoverability hole, asserted not measured.
* **Local Claude Code version** — not checked; every "requires v2.1.x" note is from S13 and may
  exceed what is installed.
