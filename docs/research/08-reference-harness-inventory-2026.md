# Reference Harness Hook Inventory, September 2026 — the Smoothness Delta

Companion to `02-frameworks-source-review.md`. That document asked *what mechanisms do
shipped frameworks have*. This one asks a narrower, harsher question: **what does each
setup make the machine do on every turn, and what does that cost?** Same repos where they
overlap; the deliverable here is the hook inventory, the per-tool-call price, and where
flow sits against the field.

All fetches 2026-09-07 unless stated. Star counts and push dates via `gh api repos/<r>`
on that date. Anything not independently fetched is marked **UNVERIFIED** inline.

---

## 0. The platform facts that set the price

From `https://code.claude.com/docs/en/hooks` and `/hooks-guide` (fetched 2026-09-07 —
`docs.claude.com` now 301s to `code.claude.com`):

- **"All matching hooks run in parallel."** Wall-clock cost of an event is ~max(hook), not
  sum. Stacking cheap hooks is nearly free; one slow hook poisons the whole event.
- **Default `command` timeout is 600 s** (30 on `UserPromptSubmit`). A wedged hook holds
  the turn for ten minutes by default. **33 hook events exist**; nobody surveyed uses >10.
- **Hooks also fire inside subagents** — *"tool events such as PreToolUse and PostToolUse
  fire the same configured hooks as in the main conversation."* Per-tool-call cost
  multiplies by fan-out width.
- **Stop hooks are force-overridden after 8 consecutive blocks** (`CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`).
- **There is no official "keep hooks cheap" doctrine.** Searching `/hooks` and
  `/hooks-guide` for `fast|slow|latenc|performance|overhead|noise|sparingly` returns only
  the timeout table and one debug line, *"Successful run: you see nothing."* The restraint
  norm below is emergent from practitioners, not from Anthropic's docs.

---

## 1. Comparison table

Cost columns are wall-clock per event given the parallel-execution rule. "Context/turn"
is text injected into the model's context on a *typical* turn, not at session start.

| Setup | #hooks | Events | What blocks | Per-tool-call cost | Stop-time gate | Context injected /turn |
|---|---|---|---|---|---|---|
| **obra/superpowers** 6.3.0 (282,617★) | **1** | SessionStart only | **nothing** | **0** — no tool-call hooks exist | none | **0** (3.1 KB / 63 lines once per session) |
| **Anthropic `claude-code` `examples/hooks/`** | **1** | PreToolUse(Bash) | exit 2 on `grep`/`find -name` | 2 `re.search` calls | none | 0 |
| **ralph-loop** (official plugin) | 1 | Stop | `{"decision":"block"}` until `<promise>` or max-iter | 0 | yes — literal string compare on transcript tail | 1-line `systemMessage` |
| **claude-security** (official) | 3 | UserPromptExpansion, PostToolUse, PostToolUseFailure | nothing (metrics only) | ~0 — `if:`-gated to one script invocation | none | 0 |
| **explanatory/learning-output-style** (official) | 1 each | SessionStart | nothing | 0 | none | 0 |
| **hookify** (official) | 4 | Pre/PostToolUse, Stop, UserPromptSubmit | only via user rule JSON; executor always `exit 0` | rule-count dependent, cheap by default | opt-in, **disabled by default** | 0 |
| **security-guidance** (official) | **9** | SessionStart, UserPromptSubmit, PostToolUse×6, Stop | exit 2 — but **`asyncRewake:true`**, out-of-band | regex layer negligible; LLM layer `if:`-gated to `git commit/push/gt *` only | yes — LLM diff review vs `git stash create` baseline | warnings only when a pattern hits |
| **humanlayer/humanlayer** (11,474★) | **0** | — | — | 0 | none | 0 — control is ~30 command prompts + subprocess-per-phase |
| **automazeio/ccpm** (8,362★) | **0** | — | — | 0 | none | 0 |
| **buildermethods/agent-os** v3 (5,384★) | **0** | — | — | 0 | none | 0 |
| **steipete/agent-rules** (5,693★) | **0** published | — | — | 0 | none | 0 — CLAUDE.md + permissions posture |
| **gsd-build/get-shit-done** (64,584★) | 13 scripts | Pre/PostToolUse + statusline/session-state | **exactly 1**, `gsd-validate-commit.sh`, and it is **opt-in** (`hooks.community:true`) | in-process JS regex, no shell-outs, context-monitor debounced 1-in-5 | none found | 2 lines, only at a phase boundary |
| **mksglu/context-mode** (20,514★) | ~13 matchers | PreToolUse(9), PostToolUse, PreCompact, UserPromptSubmit, SessionStart, Stop | deny only on the user's own `permissions.deny` patterns | JS pattern routing, no shell-outs | present | routing block at SessionStart |
| **diet103/…-infrastructure-showcase** (10,017★) | 4 | UserPromptSubmit, PreToolUse, PostToolUse, Stop | skill-verification guard (exact exit code **UNVERIFIED**) | regex default; LLM classification opt-in | doc updater | prompt-time skill hint |
| **FlorianBruniaux/…-ultimate-guide** (5,909★) | 7 | SessionStart, PreToolUse, PostToolUse, Notification, UserPromptSubmit, Stop | `dangerous-actions-blocker.sh` (exit 2) | **3 of 7 marked `async:true`** to stay off the critical path | reminder only | small |
| **disler/claude-code-hooks-mastery** (3,912★) | 13 | all 13 lifecycle events (demo) | PreToolUse only (`rm -rf`, `.env`) | ruff + ty on relevant writes; uv subprocess per event | TTS summary, not a gate | git status at SessionStart |
| **ChrisWiles/claude-code-showcase** (6,060★) | 6 | UserPromptSubmit, PreToolUse, PostToolUse×4 | edit-on-`main` block (exit 2) | **worst in survey**: prettier + `npm install` + jest + `tsc --noEmit` stacked on every edit (30/60/90/30s timeouts) | none | none |
| **Hashimoto (ghostty)** | **0** — no `.claude/` in repo | — | — | 0 | none | AGENTS.md, checked in |
| **Willison** | **0** published | — | — | 0 | none | minimal AGENTS.md in `simonw/llm` |
| **Boris Cherny** (reconstruction, see §2) | ~2–3 | SessionStart, PostToolUse, Stop | **none blocking** | `npm run format` on write | advisory "keep going" echo | branch/commit line |
| **flow (this harness)** | **24 cmds / 18 scripts** | **10** | **7 scripts can block** | Bash pre ~18 ms · Edit post ~76 ms · **post-bash-write 12–81 ms idle, ~158 ms per changed file, ~7.9 s at its 50-file cap** | **`stop-gate.sh`, timeout 600 s, runs test-changed/check-all** | **0 lines** (17 at SessionStart, 6 at PostCompact) |

Correction to the brief: hooks.json registers 24 commands across **10** events, not 11
(`jq '.hooks | keys'` — SessionStart, UserPromptSubmit, PreToolUse, PostToolUse, Stop,
SubagentStop, PreCompact, PostCompact, Notification, SessionEnd).

---

## 2. Per-setup notes

**obra/superpowers** — `hooks/hooks.json` is nine lines: one `SessionStart` entry, matcher
`startup|clear|compact`. The whole `hooks/` tree is 4 files, and no PreToolUse, PostToolUse
or Stop hook has *ever* existed (`gh api repos/obra/superpowers/commits?path=hooks`, 60+
commits). The payload is `skills/using-superpowers/SKILL.md` — 63 lines / 3,108 bytes /
~780 tokens — wrapped in `<EXTREMELY_IMPORTANT>`. Everything behavioural is prose in that
skill. **The most-starred harness in the field enforces nothing mechanically.**
Two removals are on record: `640ce6c0` "Remove Codex hooks" — *"Codex reliably triggers
skills on its own, and the SessionStart hook made the UX worse rather than better"* — and
`d19703b0`, stop firing on `--resume` because resumed sessions "already have the context."
Issue #1040 proposed a `PreToolUse` worktree guard; it was deferred to a "Phase 4" that
never shipped and the community wrote prose guards instead. No verbatim Jesse Vincent
quote on hooks-vs-skills could be found (**UNVERIFIED**); the evidence is repo shape plus
two deliberate removals.

**Anthropic, official** — 6 plugins in `claude-plugins-official` ship a `hooks/hooks.json`:
ralph-loop(1), claude-security(3), hookify(4), security-guidance(9),
explanatory-output-style(1), learning-output-style(1). Nineteen entries across **six
single-purpose plugins** — each owns one concern and nobody stacks. The `claude-code`
repo's entire `examples/hooks/` directory is **one 83-line file**,
`bash_command_validator_example.py`, which swaps `grep`→`rg`.
The architecturally important one is `security-guidance`: its 5 Bash-matched PostToolUse
entries each carry `"if": "Bash(git commit:*)"` / `git push` / `gt create|modify|submit`
**and** `"asyncRewake": true`. Anthropic's own most expensive hook (a real LLM diff review)
therefore (a) never fires on an ordinary Bash call, and (b) never holds the turn — it wakes
the session later with `rewakeMessage`. That is the reference pattern for expensive checks.
Two internal inconsistencies worth knowing: `plugin-dev`'s hook-development skill still
documents a 60 s default (docs now say 600 s), and `security-guidance`'s docstring says
"two Haiku analyses" while `SECURITY_REVIEW_MODEL` defaults to `claude-opus-4-7`.

**Claude Code team dotfiles** — Boris Cherny, in his own words on Threads
(`threads.com/@boris_cherny/post/DTBVlMIkpcm`): *"My setup might be surprisingly vanilla!
Claude Code works great out of the box, so I personally don't customize it much."* The
widely-circulated `0xquinto/bcherny-claude` repo is **a third-party reconstruction of an X
thread, not his dotfiles** — its own README says so. It holds 3 hooks (SessionStart echo,
PostToolUse format, Stop "keep going" echo), **none blocking**; secondary write-ups
triangulate on the same formatter + Stop-verification pair. At YC Startup School 2026, per
multiple independent reports: *"Every six months, delete your CLAUDE.md, delete your
skills, delete your hooks, and see what the model does — it might surprise you."* Anthropic
cut Claude Code's own system prompt by >80% for Opus 5 on the same principle.
Thariq Shihipar (`github.com/ThariqS`), Cat Wu, Lydia Hallie: **UNVERIFIED** — real
accounts, no published hooks config, and the Willison-hosted fireside chat with Cat and
Thariq (`simonwillison.net/2026/Jul/21/cat-and-thariq/`) mentions hooks zero times.

**HumanLayer / ACE** — `.claude/settings.json` has `permissions`, `env` and
`enableAllProjectMcpServers` — **no `hooks` key at all**, no `.claude/hooks/` anywhere in
the monorepo, and their "Advanced Context Engineering" post never mentions hooks. Their
determinism is a *new OS process per phase* (`humanlayer launch … "/implement_plan"`) — a
fresh-context mechanism, not a gate.

**gsd (64.5k★)** — 13 hook scripts, and the authors' own source comments are the doctrine:
*"This is a SOFT guard — it advises, not blocks"*; *"Why advisory-only: Blocking would
prevent legitimate workflow operations"*; *"Advisory (does not block)."* The single
blocking hook (Conventional Commits) is **off unless you set `hooks.community: true`**. No
hook shells out; the context monitor is debounced to 1-in-5 tool calls.
gsd also owns the field's clearest hook post-mortem — commit `d1fda80c` (2026-01-21),
verified: *"Rolled back the intel system due to overengineering concerns: 1200+ line hook
with SQLite graph database, 21MB sql.js dependency, entity generation spawning additional
Claude calls, complex system with unclear value."* Net `+17 / -3,065`.

**Minimalists** — Mitchell Hashimoto: `gh api repos/ghostty-org/ghostty/contents/.claude`
returns 404. No hooks. His mechanical layer is AGENTS.md/CLAUDE.md (identical files,
build/test commands), purpose-built scripts, ordinary CI, and `mitchellh/vouch` (a
trust-gating GitHub Action). Quoted: *"Each line in that file is based on a bad agent
behavior, and it almost completely resolved them all."* Judgement is reserved for reading
every diff and deciding when *not* to use an agent; explicitly rejected are agent
notifications — *"Context switching is very expensive… Don't let the agent notify you."*
(No public `mitchellh/dotfiles` repo exists — the brief's assumption is **UNVERIFIED**.)
Simon Willison: a site search for "hooks" returns only Datasette/Django/React hooks and
webhooks — **he has never published a position on Claude Code's hooks feature** (an
absence-of-evidence finding). His mechanical layer is tests (*"they're effectively free…
no longer even remotely optional"*), CI baked into a project template, sandboxes, and
conformance suites. Both men enforce a lot mechanically; neither does it with hooks.

**Friction post-mortems** — I found no blog post titled "I removed my Claude Code hooks,"
and **no self-reported aggregate number** ("hooks cost me N seconds/turn") anywhere. What
does exist, every issue number verified via `gh api repos/anthropics/claude-code/issues/N`
on 2026-09-07:
- *Stop loops*: **#10205** infinite loop with hooks enabled; **#78121**, **#54360** Stop
  hook re-fires despite `stop_hook_active:true`.
- *Timeouts not enforced*: **#85250** a wedged hook "freezes the session permanently";
  **#87289** timeout doesn't apply while a hook blocks on stdin (~300 s); **#77078**
  Windows hooks left SUSPENDED, "hanging the turn for 30-60+ minutes."
- *Silent failure*: **#84302** a killed PreToolUse hook makes the CLI **allow** the gated
  tool (fail-open); **#88578** *"killed my memory hooks for 46 days"*; **#91473** oversized
  `UserPromptSubmit` output silently truncated to ~2 KB — *"running half-blind."*
- *Hidden cost*: **#84011** PreToolUse `additionalContext` loses a trailing newline and
  **breaks the prompt cache at the first tool call of every turn**.
- *Stacking hazard*: **#88338**, measured on CLI 2.1.234 — hooks on one event are
  **last-registered-wins**; a 50 ms redaction registered first was clobbered by a 250 ms
  sibling. Docs concede *"Avoid having more than one hook modify the same tool's input."*
- *Why gates die*: **#77686** — the 8-block Stop cap makes a slow-but-correct gate
  indistinguishable from no gate: *"that's how a real control gets abandoned… silently
  defeated by its own thoroughness and nobody can prove it happened."*
- Field estimate, not measured by me — Alex Dunlop: *"A hook that takes 300ms and fires on
  every Bash call is invisible in a chat session and brutal across thirty parallel
  agents… Hook bloat has no error message."*

---

## 3. flow's own numbers, measured

Benchmarked on this repo (765 tracked files) on 2026-09-07 by piping synthesized hook JSON
to each script. Per the parallel-execution rule, treat the per-event figure as ~max.

| Event | Scripts | Measured |
|---|---|---|
| SessionStart | session-context, codebase-map (opt-in), worklog | 232 ms, **17 lines** injected |
| UserPromptSubmit | turn-stamp, lesson-nudge, worklog | ~40 ms, 0 lines |
| PreToolUse/Bash | tool-stamp, rtk-rewrite, git-guard | ~36 ms |
| PreToolUse/Edit | spec-gate | ~42 ms |
| PostToolUse/Edit | format-lint, size-guard, tamper-notice | ~77 ms |
| PostToolUse/Bash | **post-bash-write** | 12 ms (no trigger) → 81 ms (trigger, no changes) → **~158 ms per changed file** → **~7.9 s at the 50-file cap** |
| Stop | stop-gate (**600 s**), worklog | project test suite |

Steady-state context injection per turn is **0 lines** — better than most of the field.
The pruned `find` is cheaper than expected: 65–86 ms even on a 991,776-file tree, because
`node_modules`/`.venv`/`target`/`dist`/`build` are pruned.

Two things I observed live while benchmarking, both reproducible:

1. **The `post-bash-write` trigger regex is `>|tee|sed -i|<<|mv |cp |python|node|perl`,
   unanchored.** So `grep -rn foo src/ 2>/dev/null` triggers it (the `>` in `2>`), and
   `ls node_modules` triggers it (substring `node`). Read-only commands routinely pay the
   full scan. Tested: 3 of 13 representative commands triggered, all three read-only.
2. **format-lint reformatted a file the model never edited, and the reformat itself tripped
   size-guard.** Pointing `format-lint.sh` at `hooks/size_guard.py` (which
   `post-bash-write` does automatically for every file newer than the tool stamp) rewrote it
   `+42/-9` in pure formatting churn, which pushed `main()` from 59 to 61 lines and produced
   a blocking `PostToolUse` error naming a violation that did not exist a second earlier.
   I reverted it with `git checkout --`.

---

## 4. What the smoothest setups have in common

Seven properties, each held by every low-friction setup surveyed and violated by every
setup that generated a complaint:

1. **One hook per concern, and the concern is named in the plugin.** Anthropic ships six
   plugins with hooks; not one registers a second hook for an unrelated purpose. Nobody
   stacks a general-purpose hook suite on shared events — except the two "showcase" repos,
   which say outright they are reference libraries, not applications.

2. **Advisory by default; blocking is the rare, named exception.** gsd at 64.5k★ has 13
   hooks and **one** blocks — and that one is off until you opt in. Its source comments
   state the rule outright: *"Blocking would prevent legitimate workflow operations."*
   Across the entire survey the blocking set is tiny and boring: destructive-command
   denies, commit-message format, edits on `main`.

3. **Expensive checks are `if`-gated to a specific command, not pattern-matched over all
   commands.** `security-guidance` runs its LLM review only when the Bash command literally
   matches `Bash(git commit:*)`. The gate is the *command identity*, not a substring guess
   about whether something might have been written.

4. **Expensive checks run out-of-band.** `asyncRewake: true` on all five of
   `security-guidance`'s Bash entries; `async: true` on 3 of 7 in the ultimate-guide repo,
   which its author uses explicitly to keep logging and formatting off the critical path.
   Nothing costly is allowed to hold a turn.

5. **Per-turn context injection is zero.** Superpowers injects 3.1 KB **once** and then
   never speaks again — and deliberately stopped firing on `--resume` because the context
   was already there. The one measured counter-example (#91473) is a bug report about a
   `UserPromptSubmit` hook printing so much that Claude Code silently truncated it.

6. **The real gate is CI and tests, not the harness.** Hashimoto (no hooks) and Willison
   (no hooks) both enforce more mechanically than most hook-heavy setups — via AGENTS.md
   command lists, project templates with CI pre-wired, sandboxes, and conformance suites.
   Willison: *"Tests… they're effectively free. I think tests are no longer even remotely
   optional."* The harness's job is to be quiet; the repo's job is to be strict.

7. **Periodic deletion is an explicit practice.** Boris Cherny: *"Every six months, delete
   your CLAUDE.md, delete your skills, delete your hooks, and see what the model does."*
   Superpowers deleted its Codex hook because *"the hook made the UX worse rather than
   better."* gsd deleted 3,065 lines of hook for *"unclear value."* Nobody in this survey
   has ever published an argument for *adding* a hook layer wholesale.

---

## 5. What flow does that nobody else does

Eight items. Each judged **justified invariant** (buys an enforcement no one else has, at a
price the measurements support) or **likely friction** (cost or blast radius exceeds what
the invariant is worth).

**5.1 — 24 hook commands across 10 events, on one shared surface.** The field maximum
outside demo repos is 9 (`security-guidance`), and that is one plugin with one concern.
**Likely friction** — not for latency (parallel execution keeps each event under ~80 ms)
but for the failure modes the platform documents: #88338's last-registered-wins
clobbering, #84302's fail-open on a killed PreToolUse hook, and the docs' own *"Avoid
having more than one hook modify the same tool's input."* flow puts 5 scripts on PreToolUse
and 5 on PostToolUse. The risk is silent — which is exactly how #77686 says controls die.

**5.2 — `post-bash-write`: re-dispatching the Edit hooks over a `find` of the tree after a
Bash command.** Genuinely unique; nobody else closes this gap. The gap is real — auto mode
writes through `cat`/`sed`, so the Edit-matched hooks never fire.
**Likely friction, as currently triggered.** Three specific problems, all measured:
(a) the trigger regex is unanchored, so `2>/dev/null` and the substring `node` fire it on
read-only commands; (b) it attributes *every file newer than the stamp* to the command,
including files a background process or a build touched; (c) it then runs a **formatter**
over those files, which mutates code the model never wrote — I reproduced a `+42/-9`
reformat of an untouched tracked file that then tripped size-guard. At the 50-file cap it
costs ~7.9 s. The invariant is worth keeping; the trigger should be command-identity-gated
the way `security-guidance` does it (`if:` on the actual write verbs) and should
intersect with `git diff --name-only` rather than trusting mtime.

**5.3 — A 600 s Stop gate that runs the project's tests.** The only comparable Stop gates
in the field are ralph-loop's string compare and `security-guidance`'s async LLM review;
gsd, ccpm, agent-os, humanlayer and superpowers have no Stop gate at all.
**Justified invariant** — this is the single highest-value thing flow has, and it is the
correct answer to `02`'s finding that `<promise>FEATURE COMPLETE</promise>` is an honor
system. Two caveats from the platform: the 8-block cap means a slow-but-correct sweep is
punished identically to no sweep (#77686), which is exactly why `scoped` mode +
`test-changed` + the wedge valve are the right design and should stay the default; and
600 s is the platform default, so it is not actually a chosen bound — pick a real one.

**5.4 — A worklog forwarder on 7 events.** Nobody else forwards lifecycle telemetry to an
external binary. **Justified** — 8 ms, guarded by `command -v worklog`, no stdout, the
cheapest thing in the harness. It is 7 of the 24 registrations, so it inflates the headline
count without inflating the cost; say so whenever that count gets quoted.

**5.5 — `spec-gate`: PreToolUse deny on editing source without an approved plan.**
Unique. `02` found that "a hard human approval gate before implementation" is a pattern
where *"kiro only makes it real"* and everyone else's is prose; flow makes it real without
an IDE. **Justified invariant**, conditional on its default scope — `requireSpec:
"flow-branches"` arms it only on `flow/*`, which is what keeps it from making ordinary work
miserable. Do not widen that default.

**5.6 — `tamper-notice`: weakened-test detection on the added lines of an edit.** The only
comparable tool is checkwash (external, per `02`), which nobody here installs. **Justified
invariant** — it exits 2 rather than denying, which is right (the write already happened;
the model can explain or revert), and it enforces the harness's most load-bearing prose rule.

**5.7 — `PostCompact` untrusted-summary injection + `PreCompact` transcript backup.** No
other surveyed setup uses either event. **Justified** — 6 lines, compaction-only, and the
only mechanism in the field that treats a compaction summary as untrusted. Effectively free.

**5.8 — Zero steady-state context injection, plus a global `flow off` kill switch.**
Both are unusual. Superpowers injects 3.1 KB once; the showcase repos inject on
`UserPromptSubmit`. flow injects **0 lines on a normal turn** and 17 at SessionStart, and
`hook_skip_if_off` gives every judging hook a per-directory off switch that
`session-context.sh` then announces. **Justified, and the strongest thing in the harness.**
This is the one dimension where flow already beats every reference setup, including the
minimalists — and it is what makes the 24-hook count survivable. It is also the thing most
easily lost: any future hook that prints on a normal turn spends a budget currently at zero.

**Net.** Six of eight are justified. The two that are not are the same defect in different
places — *guessing* which files a command touched (5.2) and *stacking* mutating hooks on
one event (5.1). Everything expensive in flow should adopt the `security-guidance` shape:
`if`-gated to a specific command, `asyncRewake` when it can be, and never a formatter
pointed at a file the model did not write.

---

## 6. UNVERIFIED register

- Jesse Vincent: no locatable verbatim hooks-vs-skills statement; the claim rests on repo
  shape plus two removal commits.
- No public `mitchellh/dotfiles` repo exists. Simon Willison has published nothing on
  Claude Code's hooks feature (absence of evidence).
- Thariq Shihipar, Cat Wu, Lydia Hallie: no published hooks configuration found.
  `0xquinto/bcherny-claude` is a reconstruction; Boris Cherny's real dotfiles are not public.
- `diet103`'s skill-verification guard: exact exit-code behaviour is in an unfetched `.ts`.
  disler has never explicitly disclaimed hooks-mastery as a demo rather than a daily driver.
- No published post-mortem of a hook removal *for friction* exists outside gsd's commit
  message, and no one has published a measured per-turn hook cost.
