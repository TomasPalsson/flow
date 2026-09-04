# tdd-and-quality-plugins

## What it is
TDD Guard (nizos/tdd-guard) is a TypeScript CLI + Claude Code plugin that runs as a `PreToolUse` hook on `Write|Edit|MultiEdit`, blocking file changes that violate Red-Green-Refactor TDD discipline by combining deterministic AST checks with an LLM-as-judge call. [CORRECTED: the LLM call is NOT a `claude` CLI subprocess by default — `Config.ts` sets `DEFAULT_CLIENT: ClientType = 'sdk'`, and `ModelClientProvider.getModelClient` resolves the unset case to `ClaudeAgentSdk` (`@anthropic-ai/claude-agent-sdk`'s in-process `query()`, `maxTurns: 1`, no subprocess/timeout). The `claude` CLI subprocess (`ClaudeCli.ts`, `execFileSync`, `--max-turns 5`, 60s timeout) only runs if `VALIDATION_CLIENT=cli` or the legacy `MODEL_TYPE=claude_cli` env var is set — see `src/config/Config.ts:121-125,167-176` and `src/providers/ModelClientProvider.ts`.] It ships per-language test-result reporters (Vitest, Jest, pytest, RSpec, Minitest, JUnit5, PHPUnit, Go, Rust, .NET, Storybook) that write JSON test output to `.claude/tdd-guard/data/test.json`, which the guard reads as evidence.
- Repo: https://github.com/nizos/tdd-guard — clone HEAD commit date (`git log -1 --format=%cd`): **Sun Aug 16 13:33:11 2026 +0200**. Stars not shown (no GitHub API call made; not fetched from git clone).
- Companion find: checkwash (taipei49314/greenwash on GitHub, package name `checkwash`) — a separate, zero-LLM, all-AST test-tampering detector installable as a Claude Code `Stop` hook. Clone HEAD commit date: **Thu Sep 3 11:31:13 2026 +0800** (1 day before today — actively developed).
- Also inspected (lighter pass, both stale as of Sep 2026): dhofheinz/claude-code-quality-hook (last commit Jul 4 2025) and decider/claude-hooks (last commit Jul 20 2025) — PostToolUse lint/type-check enforcement hooks, useful for the exit-code/dispatcher patterns, not for anything TDD-specific.

## Workflow it implements (tdd-guard, actual sequence)
1. `SessionStart` hook (`startup|resume|clear`) runs `npx tdd-guard@latest` → `SessionHandler.processSessionStart` resets per-session state.
2. `UserPromptSubmit` hook intercepts every prompt; if the literal text is `tdd-guard on` / `tdd-guard off`, `GuardManager` flips a `guardEnabled` flag in `.claude/tdd-guard/data/config.json` and the hook returns `stopSession(...)` (a `continue:false` result that ends the turn) — this is the CLI's only user-facing command surface, no slash commands.
3. On every `Write`/`Edit`/`MultiEdit`/`TodoWrite` call, the `PreToolUse` hook runs `npx tdd-guard@latest` again with the tool-call JSON on stdin (`src/hooks/processHookData.ts`):
   a. Skip if the target path matches an ignore glob (`*.md`, `*.json`, `*.yml`, … via `minimatch`) or guard is disabled → `allow`.
   b. For `Write`, `enrichWriteOperation` reads the file's pre-existing content from disk (`readOldFileContent`) so an "overwrite" can be told apart from a fresh file.
   c. `isAllowedTestAddition`: if the path is a test file and a **deterministic AST count** of test blocks (added minus removed) equals exactly 1, short-circuit to `allow` **without calling the model at all**.
   d. If a PreToolUse edit targets a file with previously-flagged, unfixed lint issues, block immediately with a canned message (no model call) — `checkLintNotification`.
   e. Otherwise, build a `Context` (`buildContext`) from stored test output / todos / lint data + the diff, render it into one big prompt (`generateDynamicContext`), and call the model client — [CORRECTED: default is the in-process Claude Agent SDK (`ClaudeAgentSdk`, `maxTurns: 1`), not a `claude` CLI shell-out; CLI is opt-in via `VALIDATION_CLIENT=cli`/`MODEL_TYPE=claude_cli` — see `src/providers/ModelClientProvider.ts`]. Parse the model's JSON `{decision, reason}` response into a block/allow verdict.
4. On `PostToolUse` for the same matcher, `PostToolLintHandler` re-runs the configured linter (ESLint/RuboCop/golangci-lint) and stores results; a second write after a first "you have lint issues" notification blocks until fixed.
5. Test-result reporters (installed separately per project language) hook into the test runner itself (e.g. a Vitest reporter class, a pytest `pytest11` plugin) and write structured JSON test results to `.claude/tdd-guard/data/test.json` after every test run — this is what step 3e's prompt shows the model as "previous test output."

## Artifacts it produces
All under `.claude/tdd-guard/data/` (`src/config/Config.ts`):
- `test.json` — last test run's structured results (from a reporter)
- `todos.json` — last `TodoWrite` payload, shown to the model as developer intent
- `modifications.json` — the tool-call operation being reviewed
- `lint.json` — `{errorCount, warningCount, issues[], hasNotifiedAboutLintIssues}`
- `config.json` — `{guardEnabled: bool, ignorePatterns: string[]}`
- `instructions.md` — optional project-supplied override for the entire `RULES` prompt block (`context.instructions ?? RULES` in `context.ts`)

checkwash's artifact is `.greenwash/allow.toml`, an allowlist ledger with schema (from the live file):
```toml
[[allow]]
fingerprint = "RULE_NAME/path/unit_name/hash"
rule = "EXPECTATION_DEFINITION_CHANGED"
reason = "human-written justification"
author = "play"
created = "2026-09-01"
expires = "2026-11-30"
```
Fingerprint-scoped, time-boxed exceptions — reviewers can un-flag a specific finding without disabling the rule, and the exception self-expires.

## Deterministic vs prompt

| Mechanism | Enforced by script/hook/CLI (deterministic) | Asked of the model in prose |
|---|---|---|
| "Is this a test file vs impl file" | Regex on path (`fileTypeDetection.ts`: `.test.`, `.spec.`, `test/`, `_test.go$`, etc.) | — |
| "How many new tests were added" | AST-based count via `@ast-grep/napi` per language (`testCounter.ts`) — real parsers for JS/TS, Python, Go, PHP, Ruby, Rust | The model is *also* told how to count (`COUNT_NEW_TESTS` prompt block) as a fallback/cross-check inside its own reasoning, but the code-level short-circuit (`isAllowedTestAddition`) bypasses the model entirely when the AST count is exactly 1 |
| "Single new test in a test file, no test output required" | `allow` returned in code before any model call | — |
| Ignore certain file types (docs, config) | `minimatch` glob list in `GuardManager` | — |
| Lint pass/fail and re-block on unresolved lint | Real linter run (ESLint/RuboCop/golangci-lint) via `Linter` interface, error/warning counts compared | — |
| "Is this edit over-implementation / premature / a valid refactor" | — (no static analysis of *behavior*) | 100% prompt: `RULES` + `FILE_TYPES` + operation-specific prompt (`EDIT`/`WRITE`/`OVERWRITE`/`MULTI_EDIT`) fed to Claude, which returns `{decision, reason}` |
| "Are 'relevant' tests green before allowing a refactor" | Reporter-provided JSON is deterministic data | Judging *relevance* and whether tests "exercise the code being refactored" is left entirely to the model's reading of the prompt |
| Model response parsing | Deterministic multi-strategy JSON extractor (code-fence, generic fence, regex-scraped `{"decision":...}`) in `validator.ts` | — |
| checkwash: assertion removed/weakened/substituted, tolerance loosened, test disabled, conftest patches prod, CI test-step weakened, guardrail file touched | 100% deterministic Python AST diffing (`src/checkwash/detectors/*.py`, `src/checkwash/gating.py`) — zero LLM calls anywhere in the tool | none — checkwash has no model dependency at all |
| checkwash: block vs warn vs info once a tamper signature is found | Deterministic escalator/de-escalator table (D1–D3/E1–E2, see below) run against `has_evidence = _repair_evidence(...)` (did production code actually change to justify the test edit) | none |

## Mechanisms worth stealing

1. **Deterministic short-circuit before the LLM call** — "single new test in a test file, allow without a model round-trip." Solves: cuts one model call to zero for the single most common TDD action (write one new test), removing cost and judge-flakiness for the case that needs no judgment.
   Repo path: `tdd-guard/src/hooks/processHookData.ts` (`isAllowedTestAddition`) + `tdd-guard/src/hooks/testCounter.ts`.
   Snippet:
   ```ts
   function isAllowedTestAddition(operation: FileModification): boolean {
     const filePath = operation.tool_input.file_path
     if (!isTestFile(filePath)) return false
     const language = detectLanguage(filePath)
     if (!language) return false
     return countAddedTests(operation, language) === 1
   }
   ```
   Fit for a solo-dev global harness: any PreToolUse hook you write should first ask "can I answer this with a parser/regex/exit-code, and only fall through to an LLM call for the genuinely fuzzy 10%?" — keeps hooks fast and removes an entire class of judge non-determinism.

2. **Real per-language AST parsing for a structural count, not regex** — uses `@ast-grep/napi` with per-language pattern rules (`test($$$A)`, `it.each($$$I)($$$A)`, Python `function_definition` named `test_*`, Go `Test*`/`Benchmark*`, Rust `#[test]`, PHP by both naming and `#[Test]` attribute).
   Repo path: `tdd-guard/src/hooks/testCounter.ts`.
   Fit: reusable as a generic "count/detect syntactic construct X across N languages" utility for any dotfiles hook needing cross-language structural detection (e.g. counting `TODO`, detecting a new public API surface) — ast-grep's pattern DSL is far more robust than line-based regex and already handles 6+ languages in one file.

3. **JSON-decision protocol on stdout with exit 0, not exit-code blocking** — the hook always exits 0 and only emits a JSON payload (`{decision, reason}`) when *not* allowing; Claude Code's hook runner interprets that payload rather than relying on `stderr`+exit code 2 (the older convention still used by `claude-code-quality-hook` and `claude-hooks`).
   Repo path: `tdd-guard/src/cli/tdd-guard.ts` (`if (!isAllow(result)) console.log(JSON.stringify(result))`) vs `claude-code-quality-hook/quality-hook.py` (`sys.exit(main())`, blocking via exit code 2 + stderr, `quality-hook.py:875`).
   Fit: worth standardizing on the JSON-stdout form for any new dotfiles hook — it composes better (can carry a `reason` string Claude actually reads) and doesn't depend on exit-code plumbing surviving whatever wraps the hook command.

4. **Escalator/de-escalator gating table with "repair evidence"** — every tamper-shaped diff (assertion removed, weakened, substituted; test disabled; tolerance loosened; expected value changed) is only a genuine violation if there's no correlated production-code change that explains it (`_repair_evidence`/`_package_evidence`/`_symbol_match`, keyed off module-reachability from the test's own imports). This is the deterministic core of what would otherwise require an LLM to guess intent.
   Repo path: `checkwash/src/checkwash/gating.py` (`apply_gates`, `ORACLE_RULES`, `_repair_evidence`).
   Snippet:
   ```python
   has_evidence = (
       _file_repair_evidence(f.path, ir)
       if unit is None
       else _repair_evidence(unit, ir, f.path, via_helper=f.rule != "TEST_DISABLED")
   )
   ...
   if has_evidence and not suite_control:
       f.deescalators.append("REPAIR_EVIDENCE")
   ...
   else:
       f.severity = "high"
       f.escalators.append(
           "COLLECTION_CONTROL_UNEXPLAINED"
           if suite_control and has_evidence
           else "NO_PROD_CHANGE_IN_DIFF"
       )
   ```
   [CORRECTED: the final `else` branch's escalator append is a ternary in the actual source (`gating.py:718-722`), not a bare `"NO_PROD_CHANGE_IN_DIFF"` append — the original snippet's last line was simplified in a way that doesn't match the literal code. Fixed above to match `gating.py` verbatim.]
   Fit: directly applicable as a Stop-hook or PostToolUse gate for a solo dev's own repos — catches an agent (or the dev, tired) silently weakening an assertion to get CI green, gated on "did anything in production actually change," which needs no LLM and produces zero false positives on honest refactors that also touched implementation.

5. **Time-boxed, fingerprinted allowlist ledger for false positives** — instead of an on/off switch or a broad ignore pattern, every accepted finding is allowlisted by an exact `rule/path/unit/hash` fingerprint with a mandatory human `reason`, `author`, and `expires` date; expired entries silently stop suppressing.
   Repo path: `checkwash/.greenwash/allow.toml`, consumed by `active_fingerprints()` in `checkwash/src/checkwash/allowlist.py` (referenced from `gating.py`).
   Fit for solo-dev harness: false-positive handling that doesn't rot — an ignore rule from six months ago that nobody remembers approving auto-expires instead of permanently blinding the gate; cheap to adopt as a TOML/JSON pattern for any of the dotfiles' own hooks.

6. **Multi-strategy tolerant JSON extraction from an LLM's free-text response** — tries a `json` fenced block, then any fenced block, then a regex-scraped `{...}` containing `"decision"`, falling back to raw text, always taking the *last* match (assumes the model may "think out loud" before its final answer).
   Repo path: `tdd-guard/src/validation/validator.ts` (`extractJsonString`, `extractFromJsonCodeBlock`, `extractPlainJson`).
   Fit: directly reusable boilerplate for any dotfiles script that shells out to `claude -p` and needs a structured verdict back — this parsing dance is the single most reinvented piece of "LLM-as-a-judge" plumbing and this implementation is already defensive (multiple fenced blocks, malformed trailing text, non-fenced JSON).

7. **Ignore-by-glob + ignore-by-state layering before any expensive check** — `GuardManager.shouldIgnoreFile` checks a `minimatch` glob list (`*.md`, `*.json`, `*.yml`, …) *before* the guard-enabled check, and the guard-enabled check happens before any parsing — a strict, ordered cascade of cheap deterministic gates before the request ever reaches a linter or the model.
   Repo path: `tdd-guard/src/hooks/processHookData.ts` (ordering of `shouldIgnoreFile` → `SessionStart` → user command → disabled-check → lint-notify → model call).
   Fit: a template for ordering any new hook: filesystem/glob checks (cheapest) → stored-state checks (cheap) → static-analysis checks (moderate) → LLM call (expensive), each returning early.

8. **Reporter-as-plugin pattern for capturing ground truth from the real test runner** — rather than trying to re-run or re-parse test output textually, each language gets a first-class plugin registered through the runner's own extension point (a Vitest `Reporter` class, a pytest `pytest11` entry-point plugin autoloaded on install, a JUnit5 extension) that writes normalized JSON straight from the runner's internal result objects.
   Repo path: `tdd-guard/reporters/vitest/src/VitestReporter.ts`, `tdd-guard/reporters/pytest/tdd_guard_pytest/pytest_reporter.py`.
   Fit: the correct way to get *actually reliable* pass/fail state into any hook that needs it — parsing captured stdout/stderr of `npm test` is fragile (filters, custom reporters, color codes); hooking the runner's structured API is not.

## Weaknesses / ceremony cost

- **Prompt size per invocation (tdd-guard)**: a typical `Edit` PreToolUse call assembles `SYSTEM_PROMPT` (10 lines, confirmed) + `RULES` (59 lines, confirmed) + `FILE_TYPES` (50 lines, confirmed) + `EDIT` operation prompt, which itself inlines `COUNT_NEW_TESTS` + `MATCH_FAILURE_TYPE` (both live in `shared.ts`, 33 lines combined) + `RESPONSE` (35 lines, confirmed) — **≈190-210 lines of fixed prompt text before any actual diff, test output, todos, or lint content is appended**, on *every single* Edit/Write call that doesn't hit the single-new-test short-circuit. `Write`'s own template (49 lines, confirmed) is comparable; `MultiEdit`'s (58 lines, confirmed) is larger. This is a full model round-trip for every implementation edit — real latency and token cost per keystroke-adjacent action. [CORRECTED: by default this round-trip is an in-process Claude Agent SDK call (`maxTurns: 1`), not a `claude` CLI subprocess with `--max-turns 5` / 60s timeout — that specific cost profile (`ClaudeCli.ts`, `execFileSync`) only applies when `VALIDATION_CLIENT=cli` or `MODEL_TYPE=claude_cli` is set. The per-call prompt-size and latency point stands either way.]
- **Gates the model can silently misjudge, not skip**: nothing forces the model to actually apply the rules — a wrong "null" decision (allow) from Claude Sonnet is indistinguishable from a correct one; the only backstop is a human reading `reason` text after the fact. There is no re-verification pass.
- **Fragile response contract**: if the model emits anything the multi-strategy extractor can't parse, `validator.ts` throws `"The model did not return valid JSON"` and the whole hook call becomes a block with that raw error as the reason — a spurious block on a model formatting hiccup, not a real TDD violation.
- **Number of gates before reaching the LLM**: ignore-glob → guard-enabled → SessionStart handling → user on/off command → lint-notification-block → allowed-test-addition-shortcut → model call → PostToolUse relint. Seven sequential deterministic checks feeding one non-deterministic one; each is a place a future contributor can introduce a bypass or a false negative.
- **checkwash's ceremony is heavier but load-bearing**: 12 detector files, a 733-line gating engine, and a large adjudicated benchmark corpus (`benchmarks/adjudication-*.json`, multiple dated re-sweeps) — this is a genuinely researched adversarial tool, not a quick hook; adopting it means adopting its AST-based Python analysis pipeline (`src/checkwash/ir/`, `frontends/python`, `frontends/javascript`) as a dependency, not just a prompt.
- **Both stale competitor repos** (`claude-code-quality-hook`, `claude-hooks`) are frozen mid-2025 and use the older exit-code-2/stderr blocking convention exclusively — no evidence of the newer JSON-hookSpecificOutput protocol, so they may be behind current Claude Code hook semantics.

## Plugin/packaging structure

- **tdd-guard**: distributed as an npm package (`npx tdd-guard@latest`, pinned to `@latest` in the hook command itself — no lockstep versioning with the plugin) **and** as a Claude Code plugin via `plugin/.claude-plugin/plugin.json` (name `tdd-guard`, version `1.3.0`) referenced from a marketplace manifest at `.claude-plugin/marketplace.json`. The plugin's `plugin/hooks/hooks.json` registers three hooks: `PreToolUse` (matcher `Write|Edit|MultiEdit|TodoWrite`), `UserPromptSubmit` (no matcher — every prompt), `SessionStart` (matcher `startup|resume|clear`) — all three run the identical `npx tdd-guard@latest` command and let `processHookData` branch on `hook_event_name`. Language reporters are separate installable packages per ecosystem (npm for Vitest/Jest/Storybook, PyPI for pytest, RubyGems for RSpec/Minitest, NuGet for .NET, a Go module, a Gradle/JUnit5 artifact, Composer for PHPUnit) — each a thin adapter that imports the core `tdd-guard` npm package's exported schemas (`src/index.ts` exports `Storage`, `Config`, schemas) and writes to the shared `Config.testResultsFilePath`.
- **checkwash**: PyPI package `checkwash` (current version at clone time per PyPI search: 0.2.10+ / listed 0.1.49 mid-search — versions differ by search snapshot). Installs a Claude Code `Stop` hook via its own CLI: `checkwash hook install --agent claude-code [--local]`, which idempotently appends `{"hooks":[{"type":"command","command":"checkwash check --format hook-json"}]}` to `.claude/settings.json`'s `hooks.Stop` array (or `settings.local.json` with `--local`, explicitly to avoid the tool's own `GUARDRAIL_TOUCHED` detector firing on itself when installed into the shared file). Also ships a pre-commit hook (`.pre-commit-hooks.yaml`) and a GitHub Action (`action/action.yml`) for PR-comment posting.

## Verdict: adopt / borrow parts / ignore

**Borrow parts, don't adopt either whole.**

- **tdd-guard whole-tool**: not worth adopting as-is for a solo-dev dotfiles harness — its value (strict Red-Green-Refactor enforcement) targets teams practicing textbook TDD, and its cost (a full model round-trip [CORRECTED: an in-process Claude Agent SDK call by default, not a `claude` CLI subprocess — see corrections above], ~200+ lines of fixed prompt, on nearly every implementation edit) is real latency/token overhead a solo dev doing exploratory work would fight constantly (the tool literally exists to interrupt "extra features/anticipatory coding," which is often exactly what solo hacking wants). **Steal the plumbing**: the deterministic-short-circuit-before-LLM pattern (#1), the AST-based structural counter (#2), the JSON-stdout hook protocol (#3), and the tolerant LLM-JSON-response parser (#6) are all directly reusable in a lighter-weight personal hook that only asks the model something genuinely fuzzy.
- **checkwash**: the stronger candidate to actually adopt, wired as a `Stop` hook (matches this repo's existing pattern of Stop/Monitor-based automation, e.g. `slack-watch`). It is zero-LLM, deterministic, already adversarially red-teamed (see its own `docs/redteam-weaknesses.md`, `THREATMODEL.md`, dated adjudication benchmarks), and targets a failure mode a solo dev running an autonomous agent genuinely has: the agent quietly weakening or deleting a test to get to green. Its allowlist-with-expiry pattern (#5) is worth copying even if checkwash itself isn't installed.
- **claude-code-quality-hook / claude-hooks**: ignore as products (stale, mid-2025, no evidence of maintenance into 2026) but keep the exit-code-2 vs JSON-stdout contrast (#3) and the staged-fixing idea (linter → type checker, then `auto_fix.py`'s traditional auto-fix, escalating to `claude_code_fixer.py`'s LLM fixer with git-worktree-isolated parallel Claude fixes merged back) as a design reference if a future dotfiles hook needs to *auto-fix* rather than just block. [CORRECTED: this staged-fixing/worktree pattern exists only in **claude-code-quality-hook** (`claude_code_fixer.py`, `auto_fix.py`, `quality-hook-design.md`) — a targeted `grep -rl worktree` across claude-hooks found zero matches, so claude-hooks contributes nothing to this specific bullet beyond the exit-code-2 contrast.]

## Second-reader additions

Mechanisms in the clones the first pass didn't call out:

1. **Hallucinated-import detector (`IMPORT_UNRESOLVED`)** — checkwash flags any new `import` whose module resolves against neither the stdlib, the repo's own source tree, nor the project's declared dependencies, labeling it explicitly as a "hallucination fingerprint." This is a deterministic, zero-LLM check for the single most common agent failure mode outside of test-tampering — importing a package or module that doesn't exist.
   Repo path: `checkwash/src/checkwash/detectors/globals_rules.py` (`detect_import_unresolved`), sourced from `checkwash/src/checkwash/engine.py:671,693` (`g.unresolved_imports.append(...)`).
   Snippet:
   ```python
   def detect_import_unresolved(ir: IR) -> list[Finding]:
       return [
           Finding(
               rule="IMPORT_UNRESOLVED",
               severity="warn",
               message=(
                   f"new import '{module}' resolves against neither the stdlib, the repo, "
                   "nor declared dependencies (hallucination fingerprint)"
               ),
               ...
           )
           for path, module in ir.globals.unresolved_imports
       ]
   ```
   Fit for a solo-dev harness: a cheap PostToolUse or Stop-hook check — resolve every newly-added import against `sys.stdlib_module_names`/the repo's own file tree/`package.json`/`requirements.txt` — that catches an agent inventing an API before a human ever runs the code.

2. **Self-exemption detection (`EXEMPTION_ADDED`)** — checkwash treats its own allowlist file (`.greenwash/allow.toml`) as part of the diff it scans: if a single diff both trips a rule *and* adds the allowlist entry that would suppress that same finding, it raises a distinct `EXEMPTION_ADDED` warning ("this diff exempts itself ... review the reason") on top of the underlying finding, rather than silently letting the new entry swallow it. This closes the obvious hole in mechanism #5 (the time-boxed allowlist) — an agent (or a tired human) writing itself a permission slip in the same commit that needs one.
   Repo path: `checkwash/src/checkwash/detectors/globals_rules.py` (`detect_guardrail`, the `EXEMPTION_ADDED` block, lines ~166-177).
   Fit: any allowlist/ignore-file pattern adopted from mechanism #5 should pair with this — diff the allowlist file itself and flag (don't just silently honor) a same-commit addition that exempts a same-commit finding.

3. **Guardrail/CI config files treated as part of the oracle, with a "created vs relaxed" distinction (`GUARDRAIL_TOUCHED` / `CI_WORKFLOW_TOUCHED`, gating E4)** — checkwash extends "don't let the agent weaken the test" to "don't let the agent weaken the thing that checks the test": editing a CI workflow file is itself flagged, escalated to `critical` at gate E4 specifically when the diff *relaxes* an existing guardrail (a detector disabled, `fail_on` raised) — but only warn, not critical, when the guardrail file is newly *created* (since defaults were already in force, creating one config file relaxes nothing). It separately detects and reports the specific CI line that weakened a test-invocation command (e.g. dropping `--strict` or narrowing a test glob) inside `CI_WORKFLOW_TOUCHED`'s message.
   Repo path: `checkwash/src/checkwash/detectors/globals_rules.py` (`detect_guardrail`, `detect_ci_touched`); escalation logic in `checkwash/src/checkwash/gating.py:487-507` (comment explicitly narrates a real false-positive this rule caused and was tuned to avoid: running the tool's own README-documented install-then-commit sequence).
   Snippet (gating.py:502-507):
   ```python
   created = f.path in ir.globals.guardrail_files_created
   loosening = f.path in ir.globals.guardrail_configs_created_loosening
   if created and not loosening:
       f.escalators.append("GUARDRAIL_CREATED")
   else:
       f.severity = "critical"
   ```
   Fit: directly applicable to any dotfiles hook that has its own config/threshold file — treat edits to the hook's *own* settings (and CI files that invoke it) as findings in their own right, distinguishing "someone is adopting this for the first time" (create, low severity) from "someone with it already installed just turned a knob down" (relax an existing constraint, high severity) — the same asymmetry a solo dev would want on their own `.claude/settings.json` hook entries.
