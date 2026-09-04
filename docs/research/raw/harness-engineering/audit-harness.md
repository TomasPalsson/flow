# Claude Code Harness Audit — dotfiles → ~/.claude

Read-only audit. All paths absolute. "Live" = actually reachable by a running
Claude Code session via `~/.claude`; "dotfiles" = the source package at
`~/.dotfiles/claude/.claude/`.

---

## 1. Deployment gaps

`ls -la ~/.claude` shows these symlinks back into the dotfiles package:
`agents`, `commands`, `get-shit-done`, `scripts`, `settings.json`, `skills`,
`statusline-command.sh`. Everything else in `~/.claude` is either real local
state (history, projects, sessions, plugins…) or **simply absent** — it was
never stowed.

| Dotfiles file | Live at `~/.claude/...`? | Consequence |
|---|---|---|
| `claude/.claude/CLAUDE.md` | **No** — `~/.claude/CLAUDE.md` does not exist (verified: `test -e` → MISSING) | **None of the global rules in CLAUDE.md are active in any session, on any machine, ever**, including: the "Mr Claude" third-person directive, "surgical changes only / no drive-by refactors", "define verifiable success criteria first", the whole Subagent Model Selection tier table, the Workflow-tool opt-in policy, the `uv`/`bun`/Next.js tooling defaults, and the `.pc` dev-host allowlist. The file is pure dead weight sitting in git — it costs 103 lines of maintenance for zero runtime effect. `@RTK.md` inside it never resolves either. |
| `claude/.claude/hooks/*.sh` | **No** — `~/.claude/hooks/` doesn't exist at all (`ls`: "No such file or directory") | `rtk-fast.sh` / `rtk-rewrite.sh` never run. Moot anyway: **`settings.json` has no `hooks` key** (confirmed by `grep -i hook` → no match, and `~/.claude.json` also has no `hooks` key), so even a correctly symlinked hooks dir would not be wired into any event. Two independent breaks, either one sufficient to fully disable RTK. |
| `claude/.claude/RTK.md` | **No** | Irrelevant since (a) it's only reachable via the dead `@RTK.md` include in the non-live CLAUDE.md, and (b) the `rtk` binary itself is not installed (`command -v rtk` → exit 1). RTK is triple-dead: no binary, no hook wiring, no CLAUDE.md include path live. |
| `claude/.claude/.claude.json` | **No** (by design — `~/.claude.json` is a distinct real file with live session state, not a symlink target) | Correct as-is; not a gap. |

**Bonus finding**: `hooks/rtk-fast.sh` hardcodes `CACHE_FILE="/Users/tomas/.claude/hooks/.rtk-fast-cache"` and uses `stat -f %m` (BSD/macOS `stat` syntax) — this script would not even run correctly on this Linux/Arch machine (`/home/tomas`, GNU `stat` uses `-c %Y`) even if wired up. It's stale, platform-mismatched dead code, not just unwired.

**Net effect**: the only things a real session on this machine actually inherits from the dotfiles package today are `agents/` (developer, adversary), `commands/`, `get-shit-done/`, `scripts/`, `settings.json`, `skills/` (all ~69 of them), and the statusline. No global behavioral rules, no hooks, no RTK.

---

## 2. Rule inventory — prose rules vs. what actually enforces them

Classification key:
- **(a) hook/lint/CI** — a mechanism that runs automatically, independent of the model's compliance, and blocks/alters behavior deterministically.
- **(b) script/schema** — a script or structured-output schema exists that *would* give a deterministic verdict, but only if the model chooses to invoke it; nothing forces the call.
- **(c) prose only** — enforcement is entirely "the model reads this and complies." No backstop.

### CLAUDE.md (dotfiles — currently not even live, see §1; classified as if it were)
| Rule | Class |
|---|---|
| Mr Claude third-person, always, self-sweep before sending | (c) |
| "Surface assumptions... ask, don't pick silently" | (c) |
| "Minimum code that solves the problem, no speculative abstractions" | (c) |
| "Surgical changes only... no drive-by refactors" | (c) — note: `shared/scripts/diff-scope` exists and is referenced by `feature/references/quality-gates.md`, so a scope-checking script *exists* in the harness, but CLAUDE.md's rule doesn't invoke it — a missed (b) opportunity |
| "Define verifiable success criteria before implementing; write the reproducing test first for bugs" | (c) |
| "Use `model` param, default cheapest that can handle it" | (c) |
| "Escalation rule: haiku shallow → re-run sonnet, don't retry same tier twice" | (c) |
| "Any task with 2+ independent pieces runs as a Workflow" | (c) |
| "Workflow `agent()` calls: sonnet for code/reasoning, haiku for mechanical" | (c) |
| "`isolation: 'worktree'` only when agents mutate files in parallel" | (c) |
| Tooling defaults (`uv`, `bun`, Next.js) | (c) |
| `.pc` host allowlist for dev servers | (c) |
| **Total: 12 rules, 0(a) / 0(b) / 12(c)** | |

### flow/SKILL.md — "NEVER do" section (14 items) + inline MUST/HARD-GATE statements
| Rule | Class |
|---|---|
| NEVER create GitHub issues/AFK-HITL tags | (c) |
| NEVER run spec-judge more than once | (c) |
| NEVER soften the harsh judge | (c) |
| NEVER move a human gate (plan approval, user verification) into a subagent/team/workflow | **(b)** — partially structural: the Workflow tool genuinely cannot call an interactive user-facing prompt mid-script, so a workflow *must* return control. That's a real capability boundary, not just a rule the model reads. Still relies on the model choosing to route the gate through the main loop rather than, e.g., auto-approving on the workflow's behalf. |
| NEVER skip the orchestration-mode decision | (c) |
| NEVER write implementation in Red / never accept an agent's self-reported "tests fail" | **(b)** for the exit-code check itself (a real `TEST_CMD` exit code is a deterministic fact) / (c) for whether the model actually runs it instead of trusting the sub-agent's report — nothing traps a fabricated report |
| NEVER skip Browser Verification or Refactor | (c) |
| NEVER let scanner verify/fix its own findings (scanner≠fixer≠verifier) | (c) — orchestration convention only; nothing prevents the same context from doing all three |
| NEVER emit a deepening slice changing an interface without explicit user decision | (c) |
| NEVER duplicate referenced files into flow | (c) |
| NEVER start a build phase with an ungathered load-bearing assumption | (c) |
| NEVER add scope beyond the approved plan | (c) |
| NEVER treat scalable components as a mandatory checklist | (c) |
| NEVER let `--unattended` weaken a verification invariant | (c) |
| NEVER promote an unattended PR to ready / delete its evidence | (c) — `gh pr ready` is a real command but nothing blocks calling it; the completion checklist in `execution-prompt.md` tells the model to check `isDraft` itself, which is self-policing |
| NEVER chain shell commands in a pipeline step (`;`/`&&`/`||`/`|`) | (c) |

Additional hard gates / MUST statements across `flow/SKILL.md`, `orchestration.md`, `planning.md`, `execution-prompt.md`:
- "Red exits non-zero / Green exits zero, verified by *you*" — **(b)** the exit code is real and script-checkable (`check-all`, `test-changed`); **(c)** that the orchestrator actually runs it rather than trusting a sub-agent remains unenforced.
- Quality-gate agents write a **fixed schema** (`verdict`/`findings`/`checked`/`not-checked`, or in Workflow mode a literal JSON-schema object `SLICE_RESULT`/`FINDING`/`VERDICT`) — **(b)**, a genuine structured-output contract, the strongest enforcement mechanism found anywhere in the harness.
- `check-all --fix` gate order (typecheck→lint→format→test) — **(b)**, a real script with real exit codes (see §5).
- User Verification hard gate ("STOP. Do NOT proceed... silence ≠ approval") — (c), purely a prompt-discipline instruction; nothing prevents the model from proceeding anyway.
- "MANDATORY — READ ENTIRE FILE" directives (≈9 of them across the pipeline) — (c), a citation the model can silently skip.
- `execution-prompt.md` §5 Completion Check (13 checkboxes, "RUN IT NOW") — (c)/(b) mixed: each checkbox names a real command with a real exit code (b-capable), but the checklist itself is only ever executed if the model chooses to actually run every line rather than assert compliance — no external gate re-runs it.

### Rough total across both files
Counting each distinct prose rule/gate once: **≈40 rules** identified.
- **(a) true hook/lint/CI enforcement: 0** — confirmed zero hooks are wired anywhere in this harness (§1), so *nothing* in the entire ruleset has a real automatic backstop today.
- **(b) script/schema-backed (voluntary invocation, deterministic once invoked): ≈6** — Red/Green exit-code gates, `check-all`'s pass/fail JSON, the quality-gate fixed schema, the Workflow `SLICE_RESULT`/`FINDING`/`VERDICT` JSON schemas, the structural inability of Workflow to prompt a user mid-script.
- **(c) prose-only, model-compliance-dependent: ≈34** — the overwhelming majority, including every "NEVER", both HARD GATEs' actual stop behavior, and all of CLAUDE.md.

The skill text is self-aware about this: flow/SKILL.md line 24 states outright — *"Nothing enforces these — they are rules you follow here, not guards that stop you; no error fires if you delegate a gate or trust an agent's word, so the only thing holding them is you."*

---

## 3. Flow pipeline shape, and what's most likely to get skipped/faked

**Phases**: 8 (0 Setup, 1 Spec, 2 Harsh judge, 3 Build plan, 4 TDD build, 5 Gates+Verify, 6 PR, 7 Deepen-optional).

**Gates** (points that can block progress): Phase 0.3 speccability guard, Phase 2 judge (Medium+ only), Phase 3 plan approval (HARD), Phase 3 code-design adversary lens (conditional), Phase 5.1 inline gates, Phase 5.2 E2E (Large-UI only), Phase 5.3 quality swarm (4 dims), Phase 5.4 browser verification (non-skippable), Phase 5.5 user verification (HARD), Phase 5.6 QA pass, Phase 6 pre-ready re-verification, Phase 7 deepen approval (HARD, optional) — **≈12 named gates**, of which exactly **2 are true human hard-gates that can never be delegated** (Phase 3 plan approval, Phase 5.5 user verification).

**Distinct files an agent must load for a Medium run** (no ultracode/no code-design trigger — the common case), each carrying a "MANDATORY — READ ENTIRE FILE" or equivalent:
1. `flow/SKILL.md` (266 lines)
2. `flow/orchestration.md` (213 lines, mandatory before Phase 0)
3. `shared/project-detection.md` (86 lines) or the `detect-project` script directly
4. `flow-spec/references/question-bank.md` (278 lines)
5. `flow-spec/references/spec-template.md` (401 lines)
6. `spec-judge/SKILL.md` (707 lines, Medium+ only)
7. `flow/planning.md` (122 lines)
8. `feature/planning.md` (438 lines, referenced by #7 for the phase-table format)
9. `feature/execution-prompt.md` (271 lines, mandatory, reused unchanged)
10. `feature/references/quality-gates.md` (340 lines, mandatory)
11. `shared/claude-in-chrome-reference.md` (45 lines, UI) or `shared/verification.md` (77 lines, non-UI)
12. `clean-code` skill (97 lines, mandatory every Refactor sub-phase)
13. `qa/SKILL.md` (343 lines, Phase 5.6)
14. `shared/e2e-testing.md` (56 lines, Large-UI only — skipped on Medium)

**≈13 distinct files, ~3,300+ lines**, for a *Medium* run that never touches the Large-only code-design doctrine (`code-design-doctrine.md`, 200 lines + `pattern-forces.md`, 76 lines — would add ~276 more if a shared seam triggers it) or `showcase` (217 lines, only if the feature has UI and no design direction yet).

**Phases most likely to be skipped or faked under time pressure, and why**:
- **Phase 5.3 Quality swarm / scanner≠fixer≠verifier discipline** — the skill's own text flags this as trust-based ("NEVER let a scanner verify its own findings"); nothing stops one context from doing scan+fix+verify to save round-trips, and the failure is invisible until a real vuln ships behind a clean badge.
- **Phase 4's "verify the exit code yourself"** — the single highest-leverage skip: trusting a sub-agent's self-reported `redExit`/`greenExit` instead of re-running `TEST_CMD` is strictly cheaper in the moment and produces no visible difference in the transcript until the PR breaks. Both `orchestration.md` and `execution-prompt.md` call this out explicitly as the exact failure mode agents fall into.
- **Phase 5.5 User Verification** — the hardest gate on paper, but its enforcement is purely "the model stops and waits." Under attended mode nothing but model discipline prevents treating an ambiguous "ok" or a long silence as approval (the skill anticipates this: "'maybe'/'hmm' ≠ approval" is a written warning, not a check).
- **"MANDATORY — READ ENTIRE FILE" citations (9+ of them)** — each is a single line the model can silently not act on; with 13 files and ~3,300 lines to load for a Medium run, partial/skimmed reads are the path of least resistance and there is no way to detect one happened from the output alone.
- **Phase 3's code-design trigger test** ("two or more slices share a name/id type/error shape/module boundary/shared resource") — a judgment call with no test harness behind it; under time pressure it's easy to under-call the trigger and skip the entire 200+76-line doctrine.
- All of these are named directly by the skill's own "Nothing enforces these" admission (flow/SKILL.md:24) — the document is honest that its rigor is aspirational, not structural.

---

## 4. Contradictions and dead weight

- **`better-plan`**: `flow/SKILL.md` Phase 3 says *"Preferred: render the plan with `better-plan`... If the CLI is on PATH..."* — `command -v better-plan` → exit 1 (not installed). There is also no `better-plan` skill package under `~/.claude/skills/` (only a same-named project directory at `~/Desktop/Projects/better-plan`, unrelated to the harness). Every Phase-3 plan therefore silently falls back to "present inline," making the entire better-plan branch of the instructions dead prose on this machine.
- **`rtk`**: `command -v rtk` → exit 1. Not installed. RTK.md, both hook scripts, and the dotfiles CLAUDE.md's `@RTK.md` include are all dead in triplicate (see §1) — no binary, no hook wiring, no live CLAUDE.md path to reach the include at all.
- **`detect-project`**: **not dead** — `command -v detect-project` fails (exit 1, it's not a global PATH binary) but the actual reference is always `.claude/skills/shared/scripts/detect-project`, which **does exist** (24KB, executable) and is correctly invoked by `check-all` and `project-detection.md` via its full relative path, never via bare `command -v detect-project`. This one is a false alarm — it works as designed.
- **The "Mr Claude" third-person directive**: 21 lines of CLAUDE.md dedicated to a self-narration bit — currently costs zero tokens since the file isn't live (§1), but if the user ever symlinks CLAUDE.md into place, it becomes a standing tax on *every single response forever*: a mandatory pre-send self-sweep for "I"/"I'll"/"I'm"/"my"/"me"/"let me" across the entire conversation, for a persona effect with no functional purpose. It's the single worst token/attention-cost-to-value line item in the whole file if activated as-is.
- **Duplication between CLAUDE.md and flow's own routing matrix**: CLAUDE.md's "Subagent Model Selection" section (haiku/sonnet/orchestrator tiers, escalation rule, delegation loop) substantially overlaps `flow/SKILL.md`'s own "Routing matrix" table (which independently assigns `haiku`/`sonnet`/orchestrator per work item) and `orchestration.md`'s per-mode model assignments. Since CLAUDE.md isn't live, flow's routing matrix is currently the *only* copy that actually governs anything — but if CLAUDE.md were symlinked in, the two would need to agree by hand-maintained convention; nothing cross-checks them, and CLAUDE.md's "orchestrator" tier (main-loop-only) rows lightly conflict with flow's explicit "user verification: main loop only, never delegated" — same idea stated twice in two independently-editable places.
- **Workflow "standing opt-in" language**: CLAUDE.md says *"treat this as a standing opt-in to multi-agent orchestration [for] any task with 2+ independent pieces"* — this is a much lower bar than flow's own Phase-0 mode detection, which defaults to **Subagents** unless an explicit ultracode signal, Large+4-slices, or an explicit "team/swarm" ask is present. If CLAUDE.md were live, its blanket "2+ pieces → Workflow" instruction would contradict flow's own mode-detection order (Workflow only on explicit ultracode signal) for every ordinary Medium run.

---

## 5. What `check-all` / `detect-project` actually enforce today

- **`check-all`** (`~/.claude/skills/shared/scripts/check-all`, Node.js, real, executable): detects ecosystem by lockfile/manifest (`package.json`→Node, `pyproject.toml`/`setup.cfg`/`setup.py`→Python, `Cargo.toml`→Rust, `go.mod`/`go.sum`→Go), falls back to the `detect-project` script for monorepos with no root manifest. Builds a `{typecheck, lint, format, test}` command set per ecosystem (checking real tool presence via `which`/script existence for Python/Go, reading `package.json` scripts for Node, hardcoded `cargo`/`go` subcommands for those two). Runs the four gates **in fixed order, stopping at first failure unless `--continue`**, truncates output to 20 lines, and — critically — **always emits a JSON summary to stdout** (`{gates, summary}`) with a real process exit code (0 = all passed/skipped, 1 = any failed). This is the one piece of the entire harness that is genuinely deterministic end-to-end *once invoked*: an agent cannot fabricate a passing `check-all` run without either actually passing the gates or lying about output it never captured. It enforces nothing on its own, though — it is not wired as a hook; a run only happens if the model calls it, exactly as flagged in §2.
- **`detect-project`** (24KB, executable, real): environment/toolchain detection only — package manager, test/lint/format/typecheck/dev commands, monorepo structure, framework, project-local skills. It enforces nothing by itself; it's a fact-gathering script consumed by `check-all` and by `project-detection.md`. Its only real guardrail is negative: `project-detection.md`'s NEVER list explicitly forbids it from running anything with side effects (no `npm install`/`cargo build`/`pip install`) and from guessing a package manager when no lockfile is found — both are prose constraints on the *script's authors*, not runtime checks the script itself performs.

Net: these two scripts are the most solid pieces of the harness — real, present, correctly cross-referenced, and genuinely enforce pass/fail on the gates they cover — but their enforcement is entirely opt-in per invocation. Nothing compels flow (or a rushed model mid-pipeline) to call them, and no hook exists to call them automatically on file writes.

---

## File
`docs/research/raw/harness-engineering/audit-harness.md`
