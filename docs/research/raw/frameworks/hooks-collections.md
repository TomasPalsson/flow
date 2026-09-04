# hooks-collections

## What it is (3 lines)

A pair of reference collections rather than a single framework: **claude-code-hooks-mastery** (disler) is a copy-into-your-repo `.claude/` template that wires all 13 Claude Code lifecycle hooks as `uv run --script` single-file Python scripts, demonstrating deterministic command blocking, JSON logging, TTS/LLM narration, and a Task-based builder/validator team with per-agent `PostToolUse` lint gates. **awesome-claude-code** (hesreallyhim) is a curated, CSV-driven link directory (162 rows, `THE_RESOURCES_TABLE_NEW.csv` → generated README) of the ecosystem, now organized by category (Security, Linting, Observability & Monitoring, Agent Orchestration, Skills, …) rather than a "Hooks"/"Workflow" section — hook-based projects are scattered across those categories.

- `claude-code-hooks-mastery`: last commit `Sun Feb 1 17:15:48 2026 -0600` (per clone), 3,908 GitHub stars (`disler/claude-code-hooks-mastery`).
- `awesome-claude-code`: last commit `Fri Sep 4 09:11:03 2026 +0000` (updated same day as this research), 53,482 GitHub stars (`hesreallyhim/awesome-claude-code`).
- Cloned to `/tmp/claude-1000/-home-tomas--dotfiles/65f7117c-29cb-4945-b826-0a4f06e8ef17/scratchpad/repos/{claude-code-hooks-mastery,awesome-claude-code}`.

## Workflow it implements (actual sequence, as implemented)

**hooks-mastery** is not a single pipeline; it's a hook-per-lifecycle-event demo plus one optional multi-agent workflow:

1. `SessionStart` → logs to `logs/session_start.json`; with `--load-context` injects git branch/uncommitted-count + `.claude/CONTEXT.md`/`TODO.md`/recent `gh issue list` into the transcript via `hookSpecificOutput.additionalContext`.
2. `UserPromptSubmit` → logs every prompt to `logs/user_prompt_submit.json`; with `--store-last-prompt --name-agent` also writes `.claude/data/sessions/<session_id>.json` and asks a local Ollama (falling back to Anthropic) model for a one-word session nickname. `--validate` mode exists but ships with an empty `blocked_patterns` list (no-op by default).
3. `PreToolUse` → runs before every tool call: blocks `.env` file access and dangerous `rm -rf`-style commands via regex, then appends the raw hook payload to `logs/pre_tool_use.json`.
4. `PostToolUse` → appends the payload to `logs/post_tool_use.json` (no blocking by default at the top level).
5. `PermissionRequest`/`PostToolUseFailure`/`SubagentStart` → newer hook events, each just logging to `logs/*.json` (stubs for future use).
6. `Stop` → logs to `logs/stop.json`; `--chat` converts the JSONL transcript to `logs/chat.json`; `--notify` picks the best available TTS engine (ElevenLabs → OpenAI → pyttsx3) and the best available LLM (OpenAI → Anthropic → Ollama → random fallback) to speak a completion message.
7. `SubagentStop` → same TTS/LLM narration pattern per-subagent, using a file lock (`utils/tts/tts_queue.py`) so concurrent subagents don't talk over each other.
8. `PreCompact` → logs the compaction trigger (`manual`/`auto`) and, with `--backup`, copies the transcript to `logs/transcript_backups/` before Claude Code compacts context.
9. `SessionEnd` / `Setup` → lifecycle logging bookends.
10. **Team workflow** (`plan_w_team.md` command): a `team-lead` agent (`disallowed-tools: Task, EnterPlanMode`) turns a `USER_PROMPT` into a spec file, gated by a **command-level `Stop` hook chain** (`validate_new_file.py` then `validate_file_contains.py`) that literally re-runs until a new `specs/*.md` file exists containing all seven required section headings. Once a plan exists, the lead uses `TaskCreate`/`TaskUpdate`/`TaskList`/`TaskGet` to hand tasks to `builder` agents (each with an inline `PostToolUse` hook running `ruff_validator.py` + `ty_validator.py` after every `Write|Edit`) and `validator` agents (`disallowedTools: Write, Edit, NotebookEdit`, read-only pass/fail report).

**awesome-claude-code** implements a curation/publishing workflow, not an agent workflow: `resources/*.py` scripts validate and append rows to `THE_RESOURCES_TABLE_NEW.csv` (via GitHub issue forms → `parse_issue_form.py` → `create_resource_pr.py` [CORRECTED: the report originally said `add_resource.py`, but `.github/workflows/handle-resource-submission-commands.yml` chains `python -m resources.parse_issue_form` then `python -m resources.create_resource_pr`; `add_resource.py` is a separate local/manual single-entry CLI — its own docstring calls itself "the local, single-entry counterpart to resources/create_resource_pr.py (which runs the full approve -> branch -> commit -> PR flow in CI)"]), `generate_readme.py` renders the CSV into `README.md` from `templates/README.template.md`, and `ticker/*.py` + a **scheduled GitHub Action** (`.github/workflows/update-repo-ticker.yml`, cron every 3 hours) regenerate star-count SVG badges [CORRECTED: not "a pre-commit hook" — the repo's `.pre-commit-config.yaml` has only one hook, `sync-issue-form`, which syncs the issue-form category dropdown from `config.yaml`; it has nothing to do with the ticker or README].

## Artifacts it produces (file names, where they live, schema)

- `logs/pre_tool_use.json`, `logs/post_tool_use.json`, `logs/user_prompt_submit.json`, `logs/session_start.json`, `logs/pre_compact.json`, `logs/stop.json` — each a JSON array of the raw hook-input payload, append-only, created under `Path.cwd() / "logs"`.
- `logs/chat.json` — full transcript, JSONL → JSON array, written by `stop.py --chat`.
- `logs/transcript_backups/<session>_pre_compact_<trigger>_<timestamp>.jsonl` — pre-compaction transcript snapshots.
- `.claude/data/sessions/<session_id>.json` — `{"session_id": ..., "prompts": [...], "agent_name": "..."}`, built incrementally by `user_prompt_submit.py`.
- `.claude/hooks/validators/*.log` — one log file per validator, next to the script (`ruff_validator.log`, `validate_new_file.log`, `validate_file_contains.log`), independent of the `logs/` tree.
- `specs/<descriptive-name>.md` — the plan artifact gated by `plan_w_team.md`'s Stop hooks; required headings quoted verbatim from the hook command: `## Task Description`, `## Objective`, `## Relevant Files`, `## Step by Step Tasks`, `## Acceptance Criteria`, `## Team Orchestration`, `### Team Members`.
- `awesome-claude-code`: `THE_RESOURCES_TABLE_NEW.csv` (columns: `ID,Display Name,Category,Sub-Category,Link,Author Name,Author Link,Active,Date Added,Last Checked,Description,Stale`) as source of truth; `README.md` is generated output, never hand-edited.

## Deterministic vs prompt (table)

| Mechanism | Enforced by script/hook/CLI | Asked of the model in prose |
|---|---|---|
| Block `.env` read/write/append | `pre_tool_use.py` regex, `sys.exit(2)` | — |
| Block `rm -rf`-style destructive commands | `pre_tool_use.py` regex, `sys.exit(2)` | — |
| Spec must exist with 7 required headings before `plan_w_team` stops | `validate_new_file.py` + `validate_file_contains.py`, chained command-level `Stop` hooks, exit 1 re-triggers | The *content* under each heading is entirely model-authored prose |
| Ruff lint passes after every `Write`/`Edit` by a `builder` agent | `ruff_validator.py`, agent-scoped `PostToolUse` hook, `{"decision":"block"}` JSON | — |
| Type-check passes after every `Write`/`Edit` | `ty_validator.py`, same pattern | — |
| Validator's pass/fail judgement of a completed task | — | Entirely prose: the `validator` agent is only denied `Write/Edit/NotebookEdit` tools; its verdict is free-text in a `## Validation Report` template, not machine-checked |
| Concurrent-subagent TTS doesn't overlap | `tts_queue.py` file lock (`acquire_tts_lock`/`release_tts_lock`) | — |
| Which LLM/TTS provider narrates completion | `get_tts_script_path()` / `get_llm_completion_message()` — deterministic priority-ordered fallback chain (env var presence) | The *content* of the narration is model/LLM-generated |
| TDD Red→Green→Refactor discipline (tdd-guard, cross-referenced) | `PreToolUse` hook intercepts every `Write/Edit/MultiEdit`, deterministically routes to a validator | The validator itself is an LLM call (`ClaudeAgentSdk`/`AnthropicApi`) graded against a 59-line prose rules doc (`src/validation/prompts/rules.ts`) — decision is model-judged, gate is deterministic |
| awesome-claude-code resource inclusion | `resources/add_resource.py`/`create_resource_pr.py` schema validation (category-in-config.yaml check, dedupe-by-link, 12-column CSV schema), gated by GitHub Actions (`validate-new-issue.yml` eligibility check + `create_resource_pr.py`'s `validate_changes()` diff-allowlist) [CORRECTED: the report originally cited "CI (`.pre-commit-config.yaml`)" — that file's only hook (`sync-issue-form`) syncs the issue-form category dropdown, not resource-inclusion validation; the actual gates are the two GitHub Actions workflows] | Curator (human) writes the description prose |

## Mechanisms worth stealing

1. **Command-level Stop-hook re-entry loop until an artifact exists and is well-formed**
   Problem solved: stops a "plan"/"spec" command from claiming done-ness without ever producing (or filling out) the deliverable file — the classic silent-skip failure mode.
   Repo path: `claude-code-hooks-mastery/.claude/commands/plan_w_team.md` (frontmatter) + `claude-code-hooks-mastery/.claude/hooks/validators/{validate_new_file.py,validate_file_contains.py}`.
   Snippet (command frontmatter):
   ```yaml
   hooks:
     Stop:
       - hooks:
           - type: command
             command: >-
               uv run $CLAUDE_PROJECT_DIR/.claude/hooks/validators/validate_new_file.py
               --directory specs --extension .md
           - type: command
             command: >-
               uv run $CLAUDE_PROJECT_DIR/.claude/hooks/validators/validate_file_contains.py
               --directory specs --extension .md
               --contains '## Task Description' --contains '## Objective'
               --contains '## Relevant Files' --contains '## Step by Step Tasks'
               --contains '## Acceptance Criteria' --contains '## Team Orchestration'
               --contains '### Team Members'
   ```
   Fit for a solo dotfiles harness: attach the same pattern to any "write a plan"/"write a commit message"/"write a changelog entry" slash command in `claude/.claude/` — a generic `validate_file_contains.py`-style script (directory + extension + required substrings) is a two-argument reusable gate, not bespoke per command.

2. **Per-agent, tool-scoped `PostToolUse` quality gate (format/lint-on-edit)**
   Problem solved: "format on edit, lint on stop" without a separate top-level hook that fires for every tool call in every context — scopes the gate to only the agent (and only the tools) that should be linted.
   Repo path: `claude-code-hooks-mastery/.claude/agents/team/builder.md` frontmatter + `claude-code-hooks-mastery/.claude/hooks/validators/ruff_validator.py`.
   Snippet:
   ```yaml
   hooks:
     PostToolUse:
       - matcher: "Write|Edit"
         hooks:
           - type: command
             command: uv run $CLAUDE_PROJECT_DIR/.claude/hooks/validators/ruff_validator.py
   ```
   ```python
   if result.returncode == 0:
       print(json.dumps({}))
   else:
       print(json.dumps({"decision": "block", "reason": f"Lint check failed:\n{error_output[:500]}"}))
   ```
   Fit: define this once as a shared, language-agnostic `lint_validator.py` (swap the subprocess command per project via an env var or arg) and attach it in agent frontmatter for any "coder" subagent in a personal fleet — cheaper than a repo-wide hook because it only runs when that agent, not the orchestrator, touches files.

3. **Deterministic dangerous-command blocklist as a regex pre-filter, not a prompt instruction**
   Problem solved: destructive `rm -rf`/`.env`-exfiltration commands get blocked before execution, unconditionally, regardless of what the model "intends" to do — closes the gap prompt-only guardrails leave open.
   Repo path: `claude-code-hooks-mastery/.claude/hooks/pre_tool_use.py`.
   Snippet:
   ```python
   patterns = [
       r'\brm\s+.*-[a-z]*r[a-z]*f',
       r'\brm\s+.*-[a-z]*f[a-z]*r',
       r'\brm\s+--recursive\s+--force',
       r'\brm\s+--force\s+--recursive',
       r'\brm\s+-r\s+.*-f',
       r'\brm\s+-f\s+.*-r',
   ]
   ...
   print("BLOCKED: Dangerous rm command detected and prevented", file=sys.stderr)
   sys.exit(2)  # exit code 2 blocks the tool call and shows Claude the error
   ```
   Fit: drop straight into a global `~/.claude/hooks/pre_tool_use.py` (`PreToolUse`, matcher `Bash`) for a solo dev's dotfiles harness — this is exactly the kind of "never delete my home directory" backstop that belongs at the user level, not per-project.

4. **LLM-as-judge TDD gate that blocks the edit itself, not just CI** (tdd-guard, `nizos/tdd-guard`, 2,328 stars — cross-referenced from local scratchpad, not currently listed in awesome-claude-code's CSV)
   Problem solved: test-tampering / skipping Red before Green — a `PreToolUse` hook intercepts `Write|Edit|MultiEdit|TodoWrite` and routes the diff + prior test output through a second Claude call graded against an explicit rules doc, before the edit is allowed to land.
   Repo path: `tdd-guard/plugin/hooks/hooks.json`, `tdd-guard/src/validation/prompts/rules.ts`, `tdd-guard/docs/enforcement.md`.
   Snippet (hook wiring):
   ```json
   "PreToolUse": [{"matcher": "Write|Edit|MultiEdit|TodoWrite",
     "hooks": [{"type": "command", "command": "npx tdd-guard@latest"}]}]
   ```
   Snippet (anti-tamper hardening, `docs/enforcement.md`) [CORRECTED: the doc gives these as two separate JSON config blocks under two headings ("Protect Guard Settings" and "Block File Operation Bypass"), not one merged object as originally shown here — content is accurate, form was flattened]:
   ```json
   // "Protect Guard Settings"
   { "permissions": { "deny": ["Read(.claude/tdd-guard/**)"] } }
   // "Block File Operation Bypass" (separate block, only needed if shell commands auto-approve)
   { "permissions": { "deny": [
       "Bash(echo:*)", "Bash(printf:*)", "Bash(sed:*)", "Bash(awk:*)", "Bash(perl:*)"
   ] } }
   ```
   Fit: overkill for most solo dotfiles work, but the *pattern* — deny-list the agent's own config path plus the shell commands that could bypass a `Write/Edit`-scoped hook (`echo >>`, `sed -i`) — is a cheap, generally-applicable hardening step for any hook-based gate in this repo's `claude/.claude/` settings, not just TDD.

5. **Session nickname / friendly session identity, generated once and cached**
   Problem solved: distinguishing concurrent Claude Code sessions in a status line or TTS narration without re-asking an LLM every turn.
   Repo path: `claude-code-hooks-mastery/.claude/hooks/user_prompt_submit.py` (`manage_session_data`, `--name-agent`).
   Snippet:
   ```python
   if name_agent and "agent_name" not in session_data:
       result = subprocess.run(["uv", "run", ".claude/hooks/utils/llm/ollama.py", "--agent-name"], timeout=5)
       ...
   ```
   Fit: this repo already runs `status_line.py`-equivalent things via `starship`/`fish`; a one-time local-Ollama-generated session name, cached to a JSON file keyed by `session_id`, is a nice touch for a tmux/zellij status bar showing "which agent is which" across panes — cheap because it only calls the LLM once per session, with a local model first.

6. **Provider-fallback chains as a reusable pattern, not hardcoded to one API**
   Problem solved: hook scripts that need an LLM or TTS call shouldn't hardcode a single provider or die if a key is missing.
   Repo path: `claude-code-hooks-mastery/.claude/hooks/stop.py` (`get_tts_script_path`, `get_llm_completion_message`).
   Snippet:
   ```python
   # Priority order: ElevenLabs > OpenAI > pyttsx3 (TTS)
   # Priority order: OpenAI > Anthropic > Ollama > fallback to random message (LLM)
   ```
   Fit: directly reusable in this repo's own `bin/.local/bin/` scripts (e.g. `easycommit` already does AI commit messages) — the priority-fallback-with-timeout idiom generalizes to any script that wants "best available local/remote model, degrade gracefully."

7. **`uv run --script` PEP 723 inline-dependency single-file hooks**
   Problem solved: hook scripts need per-script dependencies (`python-dotenv`, `anthropic`) without a shared virtualenv or `requirements.txt` to keep in sync, and must start fast on every tool call.
   Repo path: every file under `claude-code-hooks-mastery/.claude/hooks/*.py`, e.g.:
   ```python
   #!/usr/bin/env -S uv run --script
   # /// script
   # requires-python = ">=3.11"
   # dependencies = [
   #     "python-dotenv",
   # ]
   # ///
   ```
   Fit: this dotfiles repo is Node.js-centric (`bin/.local/bin/*` are Node CLIs per `CLAUDE.md`), but any Python-based hook added to `~/.claude/hooks/` should use this exact pattern — zero-install, self-documenting deps, works identically on any machine with `uv` installed (already a stated Active Technology for other tools in this repo's ecosystem).

8. **Config-file-driven curated list with generated (never hand-edited) README** (awesome-claude-code)
   Problem solved: keeping a long list (162 entries) internally consistent — categories, stale-link checks, star badges — without the README drifting from a canonical source.
   Repo path: `awesome-claude-code/THE_RESOURCES_TABLE_NEW.csv` (source) → `awesome-claude-code/generate_readme.py` + `templates/README.template.md` (render); regeneration is enforced by `.github/workflows/regenerate-readme.yml`, a GitHub Action that triggers on any push to `main` touching the CSV/`config.yaml`/template and re-runs `make generate` then commits the result [CORRECTED: the report originally attributed this to "`.pre-commit-config.yaml`" — that file's one local hook (`sync-issue-form`) only syncs the issue-form category dropdown from `config.yaml`; it does not regenerate or check `README.md`/the CSV at all].
   Fit: not hook-shaped, but the CSV→generate→CI-commit pattern is directly applicable if this dotfiles repo ever wants a self-maintaining "installed tools" or "keybindings" table instead of hand-maintained markdown.

## Weaknesses / ceremony cost

- **Ceremony**: `plan_w_team.md`'s two chained `Stop` hooks mean the *team-lead* agent can be forced to re-run arbitrarily many times if it keeps writing a spec missing one heading — no hard retry cap is visible in the hook script itself (retry pressure is entirely Claude Code's Stop-hook-loop behavior, not bounded in the validator).
- **Silent-skip surface, hooks-mastery**: `PostToolUse`, `SessionEnd`, `PermissionRequest`, `PostToolUseFailure`, `SubagentStart` are wired only to append-only JSON loggers — they enforce nothing by default; a user who assumes "hooks are firing" gets pure telemetry, not a gate, unless they've separately added a `builder`-style validator hook.
- **`user_prompt_submit.py --validate` is a no-op by design**: `blocked_patterns = []` — the validation *hook point* exists, but no actual prompt-level policy ships; someone has to fill it in themselves.
- **Ordering/log-size cost**: every `pre_tool_use.json`/`post_tool_use.json` log is read-fully-into-memory + rewritten on every single tool call (`json.load` → append → `json.dump`) — O(n²) I/O over a long session; fine for a demo, a real problem past a few thousand tool calls.
- **13 hook scripts × several hundred lines of Python is a lot of surface to keep working** across Claude Code hook-schema changes; the repo visibly tracks new hook events (`PermissionRequest`, `PostToolUseFailure`, `SubagentStart`, `Setup`) added since the original 8, meaning "mastery" here is a moving target, not a stable contract.
- **awesome-claude-code has no "Hooks" or "Workflow" category** as of this clone — it was reorganized into Security/Linting/Observability/Agent Orchestration/etc., so the star-ranking requested by the brief had to be reconstructed from cross-cutting greps rather than read off a single section; a few of the "hook" hits are guides/docs, not runnable hooks (e.g. `Claude Code Hooks: Complete Guide` is a blog post).
- **Star counts as a ranking signal are noisy**: two of the top entries (`claude-code-infrastructure-showcase` at 10,016★ and `ralph-claude-code` at 9,621★) are explicitly labeled by their own README as reference/showcase material ("This is NOT a working application") rather than installable hook packages — high stars don't imply low ceremony to adopt.

## Plugin/packaging structure

- **claude-code-hooks-mastery**: no `.claude-plugin/plugin.json`, no marketplace entry. Install is `git clone` + copy `.claude/` into your project root (README's own instructions), or manually merge `settings.json`'s `hooks` block. All 12 events registered in `settings.json` (`PreToolUse, PostToolUse, Notification, Stop, SubagentStop, UserPromptSubmit, PreCompact, SessionStart, SessionEnd, PermissionRequest, PostToolUseFailure, SubagentStart, Setup`), each `matcher: ""` (fires for every tool/event) except `builder.md`'s agent-scoped `PostToolUse` (`matcher: "Write|Edit"`).
- **tdd-guard** (cross-reference, same install pattern as a proper plugin): ships `plugin/.claude-plugin/plugin.json` (`name/version/description/author/repository/keywords`) plus `.claude-plugin/marketplace.json` (`{"plugins":[{"name":"tdd-guard","source":"./plugin", ...}]}`), installable as `claude plugin install tdd-guard` via marketplace, registering `PreToolUse` (`Write|Edit|MultiEdit|TodoWrite`), `UserPromptSubmit`, and `SessionStart` (`startup|resume|clear`) hooks that all shell out to `npx tdd-guard@latest`.
- **awesome-claude-code**: pure metadata repo — no runtime install; distributes itself as a README/CSV, with `requirements.txt`/`requirements-dev.txt` for its own maintainer tooling (`generate_readme.py`, tests). CSV/README consistency is gated by the `regenerate-readme.yml` GitHub Action (push-triggered on CSV/config/template changes), not by `.pre-commit-config.yaml` [CORRECTED: that file's single local hook only syncs the issue-form category dropdown from `config.yaml`, unrelated to README/CSV consistency].

## Verdict: adopt / borrow parts / ignore

**Borrow parts, don't adopt wholesale.** Cloning either repo whole into `~/.claude` is wrong for a solo dotfiles harness — hooks-mastery's 3,100+ lines of Python hooks are a teaching demo (crypto-analysis agents, TTS narration, 9 status-line variants) with real signal buried in a handful of files, and awesome-claude-code is a link index, not code to run.

Concretely worth lifting into `claude/.claude/hooks/` in this repo:
- The `pre_tool_use.py` dangerous-`rm`/`.env` blocklist almost verbatim (mechanism 3) — cheap, deterministic, zero false-positive risk for a solo dev.
- The `uv run --script` PEP-723 single-file pattern (mechanism 7) for any future Python hook, matching the "no shared venv to rot" property this repo already gets from Node CLIs having no transpilation step.
- The generic "validate a new/updated file contains required headings" Stop-hook gate (mechanism 1), generalized as one reusable script rather than tied to `specs/`.
- The agent-scoped `PostToolUse` lint/format gate (mechanism 2) if/when this repo adds a coding subagent that writes files unattended (e.g. via `flow`/`feature` skills already in use) — attach a `stylua`/`prettier`/`ruff` check the same way, scoped to that agent's frontmatter, not global.
- tdd-guard's deny-list hardening idea (mechanism 4's second snippet) — worth applying to *any* hook-based gate this repo adds: deny `Read` on the hook's own state and deny the shell commands (`sed -i`, `echo >>`) that bypass a `Write/Edit`-matched hook.

Ignore: the TTS/LLM narration stack (ElevenLabs/OpenAI/Ollama voice announcements), the crypto-analysis agents, the 9 status-line variants, and the full `plan_w_team.md` multi-agent Task-orchestration system — this repo already has `flow`/`feature`/`ultracode` skills covering that ground with more current tooling (`TaskCreate`/`TaskUpdate` equivalents), and re-implementing a second, hook-driven task board would duplicate existing infrastructure rather than extend it.

## Second-reader additions

Mechanisms present in the two clones that the first pass didn't flag as "worth stealing":

1. **Deterministic diff-allowlist gate before a script opens a PR** (awesome-claude-code)
   Problem solved: an automated/agent-driven "propose a change" pipeline (issue → parsed data → CSV append → README regen → PR) can silently touch files it shouldn't (a bad regex, a stray write) and nobody notices until review. This script fails loudly, before the PR exists, if `git status` shows anything outside an explicit allowlist.
   Repo path: `awesome-claude-code/resources/create_resource_pr.py`.
   Snippet:
   ```python
   ALLOWED_CHANGES = {"README.md", "THE_RESOURCES_TABLE_NEW.csv"}
   IGNORED_CHANGES = {"resource_data.json", "validation_result.json", "pr_result.json"}

   def validate_changes(status_stdout: str) -> None:
       ...
       for line in status_stdout.splitlines():
           path = line[3:].split(" -> ", 1)[-1]
           if path not in ALLOWED_CHANGES and path not in IGNORED_CHANGES:
               unexpected.append(path)
       if unexpected:
           raise RuntimeError(f"Unexpected changes outside generated outputs: {', '.join(unexpected)}")
   ```
   Fit: directly reusable pattern for any script/skill in this repo that lets an agent generate a file then open a PR/commit unattended (e.g. a future auto-changelog or auto-keybindings-table generator) — a two-line allowlist check on `git status --porcelain` output is a cheap backstop against scope creep in an automated commit.

2. **SessionStart context injection via `hookSpecificOutput.additionalContext`, deterministic not prompted** (claude-code-hooks-mastery)
   Problem solved: instead of asking the model to "check git status and recent issues before starting," a hook does it once, deterministically, and hands the model a ready-made context block — cheaper and can't be skipped or hallucinated.
   Repo path: `claude-code-hooks-mastery/.claude/hooks/session_start.py` (`load_development_context`, `--load-context`).
   Snippet:
   ```python
   branch, changes = get_git_status()
   if branch:
       context_parts.append(f"Git branch: {branch}")
       if changes > 0:
           context_parts.append(f"Uncommitted changes: {changes} files")
   for file_path in [".claude/CONTEXT.md", ".claude/TODO.md", "TODO.md", ".github/ISSUE_TEMPLATE.md"]:
       if Path(file_path).exists():
           ...
   issues = get_recent_issues()
   ...
   output = {"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": context}}
   print(json.dumps(output))
   ```
   Fit: this repo's `CLAUDE.md` already carries an "Active Technologies / Recent Changes" section maintained by hand — a `SessionStart` hook that deterministically prepends current git branch + uncommitted-file count + the tail of `CLAUDE.md` would save a manual "let me check git status" round-trip at the start of every session, at zero token cost beyond the injected text itself.

3. **PreCompact transcript backup before context is discarded** (claude-code-hooks-mastery)
   Problem solved: Claude Code's automatic context compaction is opaque and lossy — once it fires, the pre-compaction transcript is gone unless something copies it out first. This hook does that copy deterministically, keyed by trigger type (`manual`/`auto`) and timestamp, with zero model involvement.
   Repo path: `claude-code-hooks-mastery/.claude/hooks/pre_compact.py` (`backup_transcript`, `--backup`).
   Snippet:
   ```python
   def backup_transcript(transcript_path, trigger):
       backup_dir = Path("logs") / "transcript_backups"
       backup_dir.mkdir(parents=True, exist_ok=True)
       timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
       session_name = Path(transcript_path).stem
       backup_name = f"{session_name}_pre_compact_{trigger}_{timestamp}.jsonl"
       shutil.copy2(transcript_path, backup_dir / backup_name)
   ```
   Fit: cheap insurance for long-running Claude Code sessions in this repo (e.g. mid-`flow`/`ultracode` runs) — a global `~/.claude/hooks/pre_compact.py` that copies the transcript to `~/.claude/transcript_backups/` before every auto-compaction costs nothing and gives a recovery path if compaction drops something the user needed later, without requiring `--chat`/manual transcript exports.
