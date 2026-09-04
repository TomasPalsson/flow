# SYNTHESIS-2 — Recommendations for Tomas's Claude Code setup

Date: 2026-09-04. Every claim cites a research file finding (`file.md F#`) or the usage audit (`audit §#`). `[UNVERIFIED]` markers in the research are treated as opinion and labelled as such.

Framing fact that governs everything below: **the audit shows a 67-skill / 10-agent / 13-command library serving a working set of about five things** — `fix`-shaped asks (90 keyword hits), `flow` (15), `design`/`impeccable`, `brainstorm`, and CLI plumbing (`/clear`, `/mcp`, `/resume`) — with `/goal` (45 hits, all since August) the single most-typed token and *not backed by any file* (audit §2, §6). Nothing in `agents/` or `commands/` is genuinely invoked (audit §3, §6). So the dominant move is **deletion**, not addition: every defined subagent's `description` is loaded every session whether or not it fires (subagents.md F2), and a ~17-agent/~40-skill harness is exactly the shape that made the main agent silently skip delegation and do the work inline at large token cost (subagents.md F15, issue #90182).

---

## 1. Agents to create

### Ranking rationale

The only role independently reinvented by Anthropic's built-ins, Anthropic's own `feature-dev` plugin, Anthropic's best-practices doc, and the highest-adoption community methodology is **fresh-context adversarial review** (subagents.md F5, F6, F10, min-set #1). Tomas already has that (`adversary`). Everything past it must be justified by *his measured dispatch frequency* or by *a documented failure mode his setup is exposed to*. Both new agents below clear that bar; nothing else does.

---

#### 1. `verifier` — the anti-fabrication agent (highest value)

**Role.** Given a claim set ("tests pass", "committed", "the gate is green") and a diff, re-run the evidence and return CONFIRMED / UNSUPPORTED per claim. Never edits.

**Why it earns its context cost.** This is the single failure class best-documented against unattended work, and Tomas runs unattended work by habit. Issue #74136: four fabrications in one session including a "committed and deployed as v0.8.59" that never existed in git history, plus a post-compaction summary that invented a user instruction (failure-stories.md F13, source-checked CONFIRMED). Issue #72480 is titled "Claude Code cannot be trusted: every response requires adversarial verification" and the reporter built a hook for exactly this (failure-stories.md F12). Anthropic's own Routines doc says a green run status "does not mean the task in your prompt succeeded" (goal-and-autonomy.md F23). And `/goal`'s evaluator **does not run commands or read files** — it only judges what is already in the transcript (goal-and-autonomy.md F2), so a fabricated "tests pass" line satisfies a `/goal` condition. The verifier is the thing that closes that loop. Fabrications cluster at two identified trigger points: right after compaction and right after a tool-call failure (failure-stories.md F13) — dispatch it there.

```yaml
---
name: verifier
description: Re-runs the evidence behind status claims (tests pass, committed, deployed, gate green) and returns CONFIRMED or UNSUPPORTED per claim with the command output. Read-only. Use before trusting any "done" report, and always after a compaction or a failed tool call.
tools: Read, Grep, Glob, Bash, BashOutput
model: sonnet
effort: high
maxTurns: 25
permissionMode: default
color: red
---
```

*Field notes.* `maxTurns` marks output partial rather than looping (subagents.md F1, v2.1.246+). No `memory:` — subagent memory is siloed per agent name and cannot be seen by any other agent (memory.md F10), and stale memory silently primes every session with no freshness signal (memory.md F16, issue #85075); a verifier must derive everything fresh or it defeats its own purpose. Keep `model: sonnet` — the work is running commands and diffing, not reasoning.

**Spawned in.** End of every `/flow` slice; before any `/goal` clears; the first turn after a `PostCompact`; whenever the main session says "tests pass" without you having seen the run.

**Downside to watch.** A reviewer prompted to find gaps will report some even on sound work (subagents.md F5, Anthropic's own warning) — so scope it to *claims already made*, never "find problems". Second downside: the subagent's report can arrive as a bare pointer with no body, unrecoverably, burning the whole run (subagents.md F15, issue #88822, ~190k tokens lost in one observed case) — so have it write findings to a file as well as returning them.

---

#### 2. `scout` — lean read-only explorer (add now, *because of his MCP count specifically*)

**Role.** Codebase search and file-map answers with a hard-restricted toolset and no MCP inheritance.

**Why it earns its context cost.** The generic advice is *don't* build a custom explorer — the built-in `Explore` is free and maintenance-free — and only replace it when it measurably breaks (subagents.md min-set #2). Tomas is the documented breaking case: `lean-agents` (PR #38045) exists because "users with 10+ MCP servers configured experience silent subagent failures because all MCP tool schemas (~200k+ tokens) are passed to subagents regardless of their `tools:` frontmatter. This makes Explore, Plan, and general-purpose agents unusable" (subagents.md F13). He runs serena, claude-in-chrome, context7, playwright, google-ads, datadog plus a dozen claude.ai connectors — over the threshold. Note the mitigating change: MCP definitions are now **deferred by default** as of v2.1.232+, so only names and server instructions load until a tool is used (mcp-tools.md F1) — which may have already fixed this. Treat `scout` as **conditional**: add it the first time `Explore` returns "prompt too long"; not before.

```yaml
---
name: scout
description: Fast read-only codebase exploration — locate files, trace call paths, answer "where does X live". Returns file:line references and a short summary, never a plan and never an edit.
tools: Glob, Grep, Read, LS, Bash, BashOutput
mcpServers: {}
model: sonnet
maxTurns: 20
color: cyan
---
```

*Field note, stated honestly:* `mcpServers: {}` is the documented lever for scoping servers per-agent (subagents.md F1), but PR #38045's whole complaint is that MCP schemas pass through **regardless of the `tools:` allowlist**, and the research could not confirm whether that gap is fixed as of 2026-09-04 (subagents.md "Disagreements", open question). If the empty map does not shrink the payload, the working fallback is disabling servers for the session with `/mcp` (mcp-tools.md practices).

**Spawned in.** Phase 0 of `/flow`; the "take a look at X" and "can you find out" prompts that are 11 of his top openers (audit §4).

**Downside.** A second explorer alongside the built-in is a description-token tax with no gain if `Explore` is working. Verify the failure before adding.

---

#### 3. `repro` — bug triage before the main session opens (add now)

**Role.** Given an error string, reproduce it, localise it to a file:line, and return the minimal failing command. Does not fix.

**Why it earns its context cost.** This is the one role justified by his own measured behaviour rather than by a doctrine: `fix`-language is the top keyword at 90 hits, "why am i getting" is his #2 opener at 10, "im getting a bunch" at 4, "can you figure out" at 6 (audit §4, §5) — and he types the error rather than `/fix` (audit §6). The research's own bar for a new named agent is exactly this: worth the description-token cost "once you're dispatching the same role with the same constraints often enough that re-typing the prompt each time is the bigger cost" (subagents.md min-set #4). Triage also floods the main context with log/stack noise that is never referenced again — the canonical case for delegation (subagents.md F5).

```yaml
---
name: repro
description: Reproduces a reported error and localises it. Returns the minimal failing command, the exact error text, the file:line where it originates, and the top two candidate causes. Never edits code and never proposes a fix.
tools: Read, Grep, Glob, Bash, BashOutput, KillShell
model: sonnet
effort: medium
maxTurns: 30
color: yellow
---
```

**Spawned in.** Automatically on any "why am I getting / it's broken / this crashes" prompt; as step 1 of the `fix` skill.

**Downside.** Isolation cuts both ways — it will not know what he just changed unless the dispatch says so. Every dispatch must paste the actual error text, not reference "the bug" (subagents.md F12, obra dispatch template and its four named anti-patterns: too broad, no context, no constraints, vague output).

---

#### Deliberately NOT created

- **A separate `judge`/final-reviewer agent.** obra's SDD assigns models *by task type within a run*, and puts the final whole-branch review on the most capable model (subagents.md F11). But since v2.1.251 the **per-invocation `model` parameter outranks the agent's frontmatter** (subagents.md F3) — so dispatch the existing `adversary` with `model: opus` for the final pass instead of paying a permanent description-token cost for a second reviewer identity. This also sidesteps the unresolved disagreement over review model tier (wshobson pins Opus; Anthropic's own `code-reviewer` pins Sonnet; nobody explains why — subagents.md "Disagreements").
- **A worktree-refactor agent.** `isolation: worktree` is a one-line frontmatter flag on any agent (teams-parallel.md F20), not a role.
- **A memory-curator agent.** Human-timed, side-effecting, monthly — that is a command with `disable-model-invocation: true` (slash-commands.md F9), not an agent.
- **Per-language / per-framework specialists.** The 158–202-agent catalogs (wshobson, VoltAgent, claude-code-templates) publish no evidence any individual role is necessary, and both mitigate their own bloat by shipping as separately-installable plugins — which is itself the admission (subagents.md F7, F8, F10, downsides).

---

### Verdict on the existing 10 agents

Audit §3 mention counts, with the audit's own caveat that `test`/`cli`/`document`/`readme` counts are "contaminated by the plain English words appearing in ordinary sentences, not actual `@agent` invocations" (audit §6).

| Agent | Mentions | Verdict | Reason |
|---|---|---|---|
| `adversary` | 0 | **KEEP** | The one cross-corroborated role (subagents.md F5/F6/F10). Zero mentions because `/flow` and `/ultracode` dispatch it by `agentType`, not by name — the audit only counts typed prompts. |
| `developer` | 0 | **KEEP** | Same: the fleet implementer his CLAUDE.md delegation contract names explicitly. Keep pinned to sonnet — model quality beats fan-out, but not at reviewer prices (subagents.md F12). |
| `test` | 16 (contaminated) | **DELETE** | TDD Red/Green/Refactor already lives inside `flow` and `feature`. A second path to the same behaviour is the "name-collision ambiguity across five namespaces" failure mode (slash-commands.md downsides). |
| `orchestrate` | 0 | **DELETE** | Superseded by the Workflow tool, which his CLAUDE.md already mandates for 2+ independent pieces, and which is documented as the primitive where "the script holds the loop… Claude's context holds only the final answer" (teams-parallel.md F14). |
| `cli` | 7 (contaminated) | **DELETE** | Duplicates the `cli` and `node-cli-builder` skills. |
| `sst` | 4 | **DELETE** | Duplicates the `sst` skill; 4 hits are "run the sst agent" against a skill that also exists. |
| `document` | 3 | **DELETE** | One-off prompt, not a standing role. |
| `readme` | 2 | **DELETE** | Same. |
| `comment` | 2 | **DELETE** | Same, and it's the kind of always-available micro-automation the sprawl literature specifically warns degrades performance (slash-commands.md F38, opinion). |
| `cleanup` | 0 | **DELETE** | The bundled `/simplify` skill covers it, at Anthropic's maintenance cost rather than his (slash-commands.md F18). |

**Net: 10 → 2 kept + 3 new = 5.** That is a direct, permanent context refund on every session (subagents.md F2: combined descriptions over 15,000 tokens trigger a startup warning; the tax is paid whether or not an agent fires).

---

## 2. Slash commands to create or delete

### Delete all 13 existing command files

`cleanup`, `cli`, `comment`, `document`, `document-notion`, `fix`, `improve`, `improve-pr`, `improve-workflow`, `orchestrate`, `readme`, `sst`, `test`. Reasons, in order of force:

1. **Commands were merged into skills in 2026.** `.claude/commands/deploy.md` and `.claude/skills/deploy/SKILL.md` both produce `/deploy` and "work the same way"; skills are the recommended path (slash-commands.md F1, F2). Every one of these 13 has a skill twin or a bundled-skill equivalent.
2. **A skill beats a same-named command file** in the resolution order (slash-commands.md F7) — so `commands/fix.md` is already dead code that only creates ambiguity about which `/fix` runs.
3. **Zero real invocations** across nine months (audit §3, §6).
4. `improve-pr` is covered by the bundled `/code-review --comment`, `improve` by `/simplify`, `document-notion` by the Notion connector (slash-commands.md F18).

### Create — four, all human-timed

#### `/btw` — make his own convention real (highest value; 13 uses of a command that does not exist)

The audit's sharpest finding: `/btw` was typed 13 times and `/goal` 45 times, and *neither is an installed skill or command* — "an ad-hoc personal convention the user adopted" (audit §6). `/goal` is a real built-in; `/btw` is not. Give it a file so the intent lands somewhere durable instead of evaporating into a context window that will be compacted away.

```yaml
---
name: btw
description: Capture a side note, correction, or preference without derailing the current task.
argument-hint: [the note]
disable-model-invocation: true
---
```
Body outline: (1) Do not change course on the current task. (2) Classify the note: durable project fact → propose one line for `./CLAUDE.md`; durable personal preference → propose one line for `~/.claude/CLAUDE.md`; ephemeral/session-only → acknowledge in one line and continue. (3) Never write to a memory file without saying which file and which line. (4) Resume the interrupted task.

`disable-model-invocation: true` because it has side effects and its timing is his to choose — the docs' own criterion, with `/commit` and `/deploy` as the cited examples (slash-commands.md F9). The classification step is the manual "promote to CLAUDE.md" ratification that auto-memory lacks and that issue #78398 is an open feature request for (memory.md F17).

#### `/wrap` — session handoff to a ledger file

```yaml
---
name: wrap
description: End-of-session handoff — write the ledger, list what is unfinished, and state the exact next command.
disable-model-invocation: true
allowed-tools: Bash(git status *) Bash(git log *) Bash(git diff *)
---
```
Body outline: run `git status --porcelain` and `git log --oneline -10`; rewrite `PROGRESS.md` (his existing harness artifact, capped at 60 lines per his CLAUDE.md) with: current phase, files touched, the exact command to resume, red gates, and open decisions. No narrative.

Justification: "Conversation memory does not survive compaction. In real sessions, controllers that lost their place have re-dispatched entire completed task sequences — the single most expensive failure observed. Track progress in a ledger file, not only in todos" (subagents.md F16). Anthropic's own long-running-harness pattern is the same shape: progress file + checklist + init script, read at the start of every session (memory.md F15). And checkpoints will not save him: `/rewind` does not cover Bash-driven file changes, background subagent edits, or symlinked paths — and his entire config **is** a stow symlink farm, which the docs name explicitly as a restore-skipping case (sessions-context.md F6, downsides).

#### `/ship` — commit and PR, human-triggered

```yaml
---
name: ship
description: Stage, commit, push, and open a PR for the current branch.
disable-model-invocation: true
allowed-tools: Bash(git add *) Bash(git commit *) Bash(git status *) Bash(git diff *) Bash(git push *) Bash(gh pr create *)
---
```
The only two custom commands any practitioner source claims survive long-term are commit and PR/review workflows (slash-commands.md F37, secondary/uncorroborated — the research explicitly flags that no longitudinal data exists). `disable-model-invocation` is mandatory here, and note `allowed-tools` grants **clear on his next message**, not at session end (slash-commands.md F5, source-checked CONFIRMED) — re-invoking re-applies them.

#### `/memory-audit` — monthly prune

```yaml
---
name: memory-audit
description: Review auto-memory and CLAUDE.md for staleness, secrets, and content derivable from the codebase.
disable-model-invocation: true
---
```
Body outline: list `~/.claude/projects/<project>/memory/` with `modified` timestamps; flag anything older than 60 days or describing structure that no longer exists; grep for credential-shaped strings; propose deletions and CLAUDE.md promotions as a diff, apply nothing without approval.

Justification: no automatic pruning or expiry exists; both proposed fixes (#85075 freshness expiry, #78398 promote/keep/discard ratification) are open feature requests, not shipped behaviour (memory.md F16, F17, downsides).

### Built-ins to make habitual

Ranked by expected value for his specific habits:

1. **`/context`** — before starting anything long. It shows the per-item breakdown and flags memory bloat and context-heavy tools (slash-commands.md F21). It is the only way to see what his 67 skills and dozen connectors actually cost him at startup (sessions-context.md F1 gives the anatomy: system prompt ~4.2K, auto memory ~680, skill descriptions ~450, project CLAUDE.md ~1.8K).
2. **`/clear` after two failed corrections.** Anthropic's stated rule, verbatim: "After two failed corrections, `/clear` and write a better initial prompt… A clean session with a better prompt almost always outperforms a long session with accumulated corrections" (sessions-context.md F2, source-checked CONFIRMED). His #1 opener is "continue" (16×) — the exact habit this rule targets (audit §4).
3. **`/doctor`** — quarterly. It finds unused skills/MCP/plugins *versus their context cost*, deduplicates CLAUDE.md, and migrates always-loaded guidance into skills (slash-commands.md F20). Anthropic built it because skill bloat is a common problem; he has the worst case in the corpus. He has run it once (audit §2).
4. **`/insights`** — monthly. First-party session-log mining: up to 200 unseen sessions per run, HTML report at `~/.claude/usage-data/report.html`, covering friction points and misunderstood requests (observability.md F5, source-checked CONFIRMED). Zero install; replaces every third-party dashboard he might be tempted by.
5. **`/usage`** — weekly, specifically for the **Loops breakdown** (v2.1.243+: per-loop run count, total tokens, tokens per run, last run — "so runaway or chatty `/loop` tasks are easy to spot", goal-and-autonomy.md F34) and the **Prompt cache (main)** line (v2.1.251+, observability.md F15). Both are the early-warning system for the $6,000-overnight failure mode.
6. **`/rewind`** — instead of asking Claude to undo. But know its five documented blind spots (sessions-context.md F6).
7. **`/fewer-permission-prompts`** — once. It scans his own transcripts and writes an allowlist (slash-commands.md F19). Cheaper than hand-curating `autoMode.soft_deny`.
8. **`/branch`** — for "try it a different way", instead of arguing in the same context (sessions-context.md F12).
9. **`/code-review` and `/security-review`** — bundled, forked-subagent, effort-tiered (slash-commands.md F18). He should not maintain private equivalents.

---

## 3. Memory policy

### The four scopes, and what belongs in each

| Scope | Contents | Rule |
|---|---|---|
| `~/.claude/CLAUDE.md` (user) | Cross-project preferences, the persona, tooling defaults. **Currently 25 lines — correct.** | Hard cap 200 lines; "longer files consume more context and reduce adherence" is Anthropic's own stated fact (memory.md F71, persona-output.md F5, both source-checked CONFIRMED). |
| `./CLAUDE.md` (project) | Build/test commands, conventions that differ from tool defaults, pitfalls, rationale. | Ratified record. Nothing derivable from the codebase — `/doctor` cuts exactly that category (memory.md "what NOT to store"). |
| `./CLAUDE.local.md` (gitignored) | Sandbox URLs, `*.pc:<port>` host quirks, machine-specific paths. | Keeps Mac-vs-Arch divergence out of the stowed, shared file. |
| `.claude/rules/*.md` with `paths:` frontmatter | Anything long and file-type-specific. | Loads **only** when Claude touches a matching file — the one mechanism that adds guidance without adding startup cost (memory.md F4). This is where his `uv`/`bun`/Next.js tooling block belongs if it grows. |
| Auto-memory (`~/.claude/projects/<p>/memory/`) | Claude's own notes: role, corrections, ongoing decisions. **Keep ON.** | Treat as a *draft*, never as the record. |
| Agent memory (`memory:` frontmatter) | — | **Do not use, for now.** See below. |
| `thoughts/` directory | — | **Skip.** The research could not verify HumanLayer's pattern against any live source (404s, repo deprecated) and deliberately excluded all claims about its mechanics (memory.md F20, gaps). `PROGRESS.md` + `/wrap` covers the same need with a sourced justification (subagents.md F16). |

### Never store

Secrets, API keys, tokens — the memory-tool docs say Claude "usually refuses" to write sensitive data but explicitly state this is not a guarantee to rely on (memory.md F12). Note the sharper local risk: transcripts are plaintext and unencrypted, and "if a tool reads a `.env` file or a command prints a credential, that value is written to `projects/<project>/<session>.jsonl`" (observability.md F6, source-checked CONFIRMED). His tree contains `.env` files across many subprojects and Terraform state — already enumerated by his own auto-mode environment block in `settings.json`. Also never store: anything derivable from the codebase (directory layouts, dependency lists), or fixes Claude can re-derive by reading the code (memory.md, "what NOT to store").

### Agent memory: not yet

`memory: project` is available on subagents and is the docs' recommended default (memory.md F9). Skip it anyway, for three reasons: it is siloed — "your `code-reviewer` subagent's `MEMORY.md` is invisible to your `security-auditor` subagent, and vice versa", with no synthesis or relevance filtering (memory.md F10); it inherits the same 200-line/25KB silent-truncation rule (memory.md F9, source-checked CONFIRMED); and it is a strict subfeature of auto-memory, so it is inert if auto-memory is ever disabled. For a solo dev with three agents, the ratified path (`/btw` → CLAUDE.md) is strictly better than five divergent private caches.

### Pruning cadence

- **Monthly** `/memory-audit`. The staleness failure is documented, not theoretical: a `MEMORY.md` index untouched ~3 months kept describing "a project that no longer exists in that form", with no freshness signal at session start or in `/context` even though a `modified` timestamp exists since v2.1.214 (memory.md F16, issue #85075, source-checked CONFIRMED).
- **After any architectural change**, say it out loud: "the old memory about X is now wrong, update or delete it." It does not self-correct (memory.md practices #11).
- **Quarterly** `/doctor` for the CLAUDE.md trim.
- **In CI / ephemeral runs**: `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1` — persistent local memory has no value in a throwaway environment and only adds staleness and attack surface (memory.md rec #9).

### Downsides, and the mitigation adopted

| Downside | Source | Mitigation |
|---|---|---|
| Unreviewed machine-written notes accrue instruction-like weight "gradually and invisibly, which is worse for debuggability than an explicit write" | memory.md F17, issue #78398 (open) | `/btw` supplies the missing ratification step by hand. Accept the residual risk; the feature does not exist. |
| Per-machine divergence — Mac and Arch will develop different auto-memory with no reconciliation path back to the stowed CLAUDE.md | memory.md F17 | Auto-memory is machine-local by design and **not synced** (memory.md F7). Do not try to stow it. Reconcile by promoting facts into the stowed CLAUDE.md via `/btw`. |
| Memory poisoning via prompt injection is a real observed vector | memory.md F18, issue #89943 — a hidden `display:none` payload instructing `rm -rf` of the memory directory, inside a well-formed API response; the model refused, the injection still landed | Review `/memory` contents like a diff from an untrusted contributor. Do not rely on the model's refusal as the only defence. |
| Memory is context, not enforced configuration | memory.md F71, failure-stories.md F15 (both source-checked) | Anything that must always hold goes in a `PreToolUse` hook or `permissions.deny` — which his harness already does. |

### Is a community memory system worth it?

**No.** claude-mem, mem0, and Serena all converge on the same index-file + detail-files + on-demand-retrieval shape that Claude Code already ships natively (memory.md F11, F19) — which is evidence the native design is the standard pattern, not that a replacement is needed. mem0's marketing page names LoCoMo/LongMemEval/BEAM but published **no actual numbers** for accuracy or latency (memory.md F19, flagged contested). Serena's own token-efficiency framing is self-reported with no independent benchmark against the now-built-in LSP plugins (mcp-tools.md F12, "Disagreements"). Adding one buys an unbenchmarked dependency and a second stale-state store.

---

## 4. `/goal`, `/loop` and unattended work

### What `/goal` actually is

A session-scoped **prompt-based Stop hook**. After each turn, the condition plus the conversation go to a small fast model (Haiku by default) which returns Not-yet-met / Met / Impossible (goal-and-autonomy.md F1, F4). Evaluator tokens are billed on the small model and are "typically negligible" against main-turn spend (F6). It works non-interactively, in the desktop app, and through Remote Control (F37) — which matters for a two-machine setup.

**The load-bearing constraint:** the evaluator "doesn't run commands or read files independently, so write the condition as something Claude's own output can demonstrate" (goal-and-autonomy.md F2, F13). A condition it cannot see proof of is a condition it cannot enforce — and it will happily accept a fabricated proof (see `verifier`, §1).

### When to use which

| Situation | Tool | Why |
|---|---|---|
| One end state, machine-checkable, you're at the keyboard or nearby | `/goal` | Condition-based, stops on Met/Impossible (F1, F11). |
| Poll something external until it settles, session stays open | `/loop <interval>` | Interval-based, 1-minute minimum, 7-day expiry, dies with the terminal (F17, F19). |
| Must run without your machine on | Routines (`/schedule`) | 1-hour minimum, cloud, **no permission-mode picker and no approval prompts** (F21). |
| Greenfield bootstrap you can throw away | `ralph-loop` with `--max-iterations` | Hard cap, exact-string completion promise (F25). |
| Existing codebase | **None of the loops** | The technique's originator: "There's no way in heck would I use Ralph in an existing code base" (F28, source-checked CONFIRMED). |

`/goal` and auto mode are complementary, not overlapping: "auto mode removes per-tool prompts, and `/goal` removes per-turn prompts" (F12). He runs auto mode already; this is the missing half.

### Reusable `/goal` condition templates

Every one has (a) one measurable end state, (b) a stated check whose output lands in the transcript, (c) a constraint on what must not change, (d) a turn clause — the docs' own template (F13), plus the turn-bound mechanism (F10).

**Build a slice:**
```
/goal `bun test` exits 0 with a test count >= the count on main, `git status --porcelain` is empty
on the current branch, and no file under src/ outside the slice's declared paths appears in
`git diff --name-only main...HEAD` — or stop after 25 turns and report exactly what is blocking
```

**Fix a bug:**
```
/goal the reproducing test added in this session fails on `git stash` and passes after `git stash pop`,
the full suite exits 0, and the diff touches no test file except the new one — or stop after 15 turns
and report the root cause you found and why the fix is not landing
```

**Green the CI:**
```
/goal `gh pr checks --watch` reports every check as pass on this branch and the last commit message
does not contain "skip", "wip", or "xfail" — or stop after 20 turns and paste the failing job log
```

**Harness change (a self-check he will actually need):**
```
/goal `harness doctor` exits 0, every script under ~/.claude/scripts/tests passes, and
`git diff --stat` shows no change under ~/.claude/skills/ — or stop after 12 turns
```

**Anti-template — do not write these:** "the code is clean", "this looks good", "the UI feels right". The evaluator literally cannot check them (goal-and-autonomy.md F167, "when NOT to reach for /goal").

### Turn and cost caps

`/goal`'s only *hard* stop is the generic force-stop after **8 consecutive turns with no tool use**; the turn clause in the condition is enforced by the same LLM judging the substantive condition, not a deterministic counter — the research flags this soft-vs-hard gap as a genuine unresolved question for unattended runs (goal-and-autonomy.md F7, "Disagreements"). So layer these:

```bash
export CLAUDE_CODE_STOP_HOOK_BLOCK_CAP=8       # keep the default; do not raise it for /goal
export CLAUDE_CODE_GOAL_CHECKIN_MINUTES=15     # default 30, backs off ×2 to 4×, max 3 idle check-ins
export CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS=12 # default 20 [flagged low-confidence, teams-parallel.md F19]
```
- `/usage` weekly for the Loops breakdown (goal-and-autonomy.md F34).
- Workspace spend limits in billing settings, and disable auto-reload — the named guardrail from the runaway-cost write-ups (failure-stories.md practices #7).
- Watch the cache: the $6,000 overnight incident was a 30-minute polling loop rebuilding an ~800k-token context ~48 times after a prompt-cache TTL change (failure-stories.md F5, secondary, the causal diagnosis is the poster's own and unconfirmed by Anthropic). Keep loop intervals inside the cache TTL, or start a fresh session each cycle.
- For workflow fan-outs specifically, `workflowSizeGuideline` is **advice, not a cap** — the runtime's real limits are 16 concurrent agents, 4,096 items per `parallel()`/`pipeline()` call, and 1,000 agents per run (teams-parallel.md F15, F16, source-checked CONFIRMED). A run scheduling >25 agents or projecting >1.5M tokens warns but does not pause.

### Run it unattended, visibly

```bash
claude -p "/goal <condition>" --output-format stream-json --verbose
```
Without the flags the output is silent and looks stuck (goal-and-autonomy.md F14).

### What not to automate

1. **Anything against an existing codebase in a Ralph-style loop** (F28, and the official plugin's own "not good for: production debugging", F27).
2. **Non-reversible steps** — prod migrations, infra changes, anything where a wrong decision cascades. Insert an explicit `HARD STOP` requiring `AskUserQuestion` (F32, secondary but consistent with the official README).
3. **Visual and product judgment.** The evaluator cannot check it (F167).
4. **Routines with broad connector scope.** Routines run with no approval prompts at all; scope is determined entirely by which repos, connectors, and network access you attach (F21). Given his dozen claude.ai connectors, this is the highest-blast-radius switch in the whole setup.
5. **`--dangerously-skip-permissions` outside a container** — the single most-cited root cause of catastrophic incidents, unanimous in the wiped-home-directory thread (failure-stories.md F3). Note his `settings.json` currently has `"skipDangerousModePermissionPrompt": true`, which removes the *confirmation* for entering that mode. Use `/sandbox` instead (failure-stories.md practices #1).
6. **Trusting a green run status.** Anthropic's own words: it "does not mean the task in your prompt succeeded" (F23).

---

## 5. Advanced hooks worth adding

He already ships session-context, turn-stamp, git-guard, format-lint, size-guard, tamper-notice, stop-gate, pre-compact-backup. Verdicts on what is left:

| Hook | Verdict | Reasoning |
|---|---|---|
| **`Notification` → desktop/sound** on `permission_prompt\|idle_prompt` | **Add now** | It is the docs' own first-hook walkthrough (hooks-advanced.md F17). He runs unattended work on two machines; the alternative is watching a terminal. Slack/TTS is the same pattern with a different command — there is no first-party integration, it is just "run a shell command" (F17). Downside: none material. |
| **`PostCompact` → re-dispatch `verifier`** | **Add now** | Fabrications cluster at compaction boundaries, including an invented user instruction inside the auto-summary (failure-stories.md F13). PostCompact cannot block — it is informational only (sessions-context.md F7) — which is fine; the job is to trigger a check, not to gate. |
| **`SubagentStop` → log `last_assistant_message` to a ledger** | **Add now** | It carries the subagent's final assistant text explicitly "so you can read final output without parsing transcript, which may lag" (hooks-advanced.md F13). This is the direct mitigation for the bare-pointer report loss that cost one user ~190k tokens with no retrieval path (subagents.md F15). Cheap, `async: true`. |
| **`asyncRewake: true` on a background test run** | **Add now** | Runs in the background and wakes Claude only on exit code 2, feeding stderr back as a system reminder (hooks-advanced.md F7, F10). This is how you get "the suite is red" to interrupt a long build without blocking every turn on a slow test run. Downside: it is after-the-fact by construction; it cannot gate. |
| **`PreToolUse` prompt hook (LLM judgment) on Bash** | **Later** | Haiku by default, `{"ok": bool}` (F2). His `git-guard.sh` already covers the destructive cases deterministically and more cheaply. Add only if a class of bad commands proves un-regexable. |
| **`PermissionRequest` allow/deny/ask** | **Later, and test it first** | Real capability — `decision` accepts `"allow"`, `"deny"`, **or `"ask"`**, and exit code 2 is ignored entirely for this event (F8). But issue #19298 reported the decisions being *silently ignored* on v2.1.12, closed not-planned with no maintainer reply and no confirmation of a fix (F9). Never build security-critical denial on it without a regression test against his installed version. Meanwhile `permissions.deny` is the documented hard gate (failure-stories.md practices #4). |
| **`ConfigChange` audit** | **Later** | Anthropic's security checklist recommends it explicitly (F20). Low value for a solo dev on his own machine; genuinely useful the moment he runs Claude Code against someone else's repo. Note `policy_settings` changes cannot be blocked. |
| **`FileChanged` / `CwdChanged` → direnv** | **Later** | The docs' own worked example is literally the direnv case (F18, F19), and he uses direnv. Pure convenience; `async: true`. |
| **Agent hooks (`type: "agent"`)** | **Never (for now)** | The docs carry a Warning box: "Agent hooks are experimental. Behavior and configuration may change in future releases. For production workflows, prefer command hooks" (F4). Up to 50 tool-use turns per invocation with no published cost data (F6). His `stop-gate` already does the job deterministically. |
| **`once: true` anywhere outside skill frontmatter** | **Never** | Honored **only** in skill frontmatter; ignored in settings files *and* in agent frontmatter, and even there only after a *successful* run (F15, source-checked CONFIRMED verbatim). Easy to misconfigure into silent re-execution. |
| **Hook chains that trigger other hooks** | **Never** | There is no cross-event loop detection. The 8-block cap covers `Stop` **only**; `TeammateIdle` and `TaskCompleted` have none (F22, F23, F24). |

### Two hook facts to design around

- **Only exit code 2 blocks.** Exit 1 is a silent non-blocking error, against Unix convention (hooks-advanced.md F30, failure-stories.md F7 source-checked). Worth grepping his eight existing hooks for `exit 1` used as a gate.
- **`$CLAUDE_PROJECT_DIR` is resolved once at session start and never re-resolved.** A `PreToolUse` security hook anchored to it goes silently dark for the rest of the session once a worktree-merge deletes that directory — "the guard the user installed to prevent `git push --force`… is offline for the remainder of the session with no visible signal beyond a stderr line buried in tool output" (failure-stories.md F8, issue #61616, open). His `git-guard.sh` should use an absolute path captured independently.
- **Skill frontmatter hooks run with no workspace-trust gate at all**, including in `-p` runs in untrusted folders — a stronger injection vector than a malicious subagent file, whose hooks *do* require trust acceptance since v2.1.218 (hooks-advanced.md F16). Relevant every time he clones someone else's repo.

---

## 6. Sessions, teams, MCP, plugins, observability, persona

### Sessions and context

**Decision.** Adopt three habits: name sessions (`claude -n auth-refactor`, resumable by name — sessions-context.md F10); `/clear` after two failed corrections rather than continuing (F2); and the spec-then-fresh-session pattern — have Claude interview him with `AskUserQuestion` into `SPEC.md`, then execute in a *new* session that reads only the spec, because "time spent making the spec precise pays off more than time spent watching the implementation" (F16). His `flow-spec` skill already does the first half; the fresh-session boundary is the missing half.

Also: put a `# Compact instructions` block in CLAUDE.md so it applies to *every* compaction including auto-compact (F3) — his current file has none.

**Downside.** He is on Fable 5.1 `[1m]`. Capacity is not quality: Anthropic's own engineering blog attributes context rot to transformer scaling limits, Chroma's 18-model study finds non-uniform degradation on even simple retrieval as length grows, and a detailed GitHub issue arguing effective reliable context is ~256K was closed as invalid with no point-by-point rebuttal (F21, F22, F23 — the last flagged contested, single-source). Treat 1M as headroom for one big read, not as permission to stop managing the session. Second downside, specific to him: **`/rewind` skips symlinked and hard-linked paths and prints "Restored the code, but skipped N files"** (F6) — his whole `~/.claude` is a stow symlink farm. Git is his only real undo there.

### Teams and parallelism

**Decision. Do not enable agent teams.** Keep the Workflow tool (his standing ultracode opt-in) as the parallelism primitive, plus `--worktree` for hand-run parallel sessions.

Reasons: teams cost "approximately 7x more tokens than standard sessions when teammates run in plan mode" (teams-parallel.md F6, source-checked CONFIRMED verbatim); they get **no automatic worktree isolation** — "Two teammates editing the same file leads to overwrites. Break the work so each teammate owns a different set of files" is the entire documented mitigation (F8); `/resume` and `/rewind` do not restore in-process teammates (F10); split-pane mode is unsupported in Ghostty, which is his terminal (F10). Meanwhile the Workflow tool is the only primitive that is resumable mid-run and keeps his context small regardless of swarm size, and it makes the orchestration a diffable `.js` artifact — which is exactly what his four saved workflows already are (F13, F14, decision-rule 6).

**Downside accepted.** Workflows have no mid-run user input, no direct filesystem access from the script, and a failed agent mid-fan-out forces every agent that started after it to rerun on resume (F15, downsides). Mitigate by keeping `subagentPromptCacheTtl` at `1h` for large runs (F83) and keeping fan-outs under the `medium` guideline.

### MCP

**Decision.** Keep context7 (2 tools, no CLI equivalent, solves hallucinated-APIs) and claude-in-chrome (no CLI equivalent for authenticated visual browsing). **Audit playwright against claude-in-chrome for redundancy** — playwright is ~21 tools/~13.6k tokens raw and is the canonical "many-tool MCP that should be one code-execution tool" case (mcp-tools.md keep/drop, F4). **Audit serena against LSP plugins**: Anthropic now ships first-party LSP code-intelligence plugins (pyright, typescript, rust-analyzer, gopls, …) giving a built-in LSP tool for go-to-definition, find-references, and live diagnostics, explicitly recommended for cost reduction (F11); where they overlap for a language he actually uses, the built-in path wins on cost. **Prune the claude.ai connectors hard** using `/plugin`'s "Not used recently" flag.

Governing rule, verbatim from Anthropic: "Prefer CLI tools when available… `gh`, `aws`, `gcloud`, and `sentry-cli` are still more context-efficient than MCP servers because they don't add any per-tool listing" (F6, source-checked CONFIRMED). He already has `gh-cli` as a skill — that is the right shape.

**Downside.** The security argument is stronger than the cost one now that tool definitions are deferred by default (F1). The lethal trifecta — private data + untrusted content + external communication in one session — is satisfied *by the combination*, not any single connector (F9), and his set (Gmail, Drive, Notion, IBKR, browser, filesystem) satisfies all three legs comfortably. Disable per-project rather than leaving everything user-global.

### Plugins

**Decision.** Install `security-guidance` (enabled by default anyway) and one LSP plugin per language he actually works in. Do **not** install `feature-dev`, `code-review`, `commit-commands`, or `pr-review-toolkit` — they duplicate his flow/adversary/ship harness, and the layered-adoption hierarchy CLAUDE.md → Skills → Subagents → MCPs → Plugins puts plugins last precisely because they are "bundled collections of the above" (plugins.md F14). Use `/plugin`'s **Context cost** estimate and **Not used recently** flag (unused ≥2 weeks over ≥10 sessions) as the standing audit (F11, source-checked CONFIRMED).

Worth knowing: `claude plugin eval` exists in the shipped CLI with an `--ablation with-without` baseline arm that reports the score delta a plugin actually buys (plugins.md F8, verified against the local CLI at v2.1.260, undocumented on the web). That is the honest way to settle any keep/drop argument — and the same harness would work on his own skills.

**Downside.** Plugins "can execute arbitrary code on your machine with your user privileges" and Anthropic explicitly disclaims verifying that bundled MCP servers work as intended, even for screened community plugins (F15, quote source-checked CONFIRMED). Toggling plugins mid-session invalidates the prompt cache and forces a full context re-read (downsides).

### Observability

**Decision.** Free and built-in only: keep his statusline, add `/usage` weekly, `/insights` monthly, `/context` before long runs. **Skip OpenTelemetry** — it is the only way to get real per-tool time series (observability.md F8) but requires standing up a collector, and the one metric worth having, `claude_code.code_edit_tool.decision`, conflates six unrelated rejection sources (`config`, `hook`, `user_permanent`, `user_temporary`, `user_abort`, `user_reject`), which no practitioner source accounts for (F9, downsides).

If he wants a "did the harness change help" signal, the sourced answer is: track **ratios against a rolling baseline**, not absolute numbers — commits per 1M tokens, cache-hit rate, edit-reject rate — because "a single day of low output could just mean developers were working on complex refactors" (F10, secondary opinion; the specific thresholds are one blogger's starting points, not Anthropic's). Given today's harness shipped in one day, a 7-day before/after on `/insights` friction points is the cheapest honest measurement available.

**Downside.** The `/usage` dollar figure is not his bill on a subscription plan — it is an API-equivalent estimate at list price, meaning "usage intensity", not money (F87). Local JSONL parsers drift 10–20% from the real invoice (F88). And background token usage (resume summarization, goal check-ins, cross-session messages) silently pollutes any delta comparison (F89).

### Persona and output style

**Decision.** Keep the two-line third-person persona in `~/.claude/CLAUDE.md`. Set `"outputStyle": "Concise"`. Do **not** build a custom output style for the persona, and do **not** add a third steering layer.

Reasoning: output styles modify the system prompt directly; CLAUDE.md is delivered as a *user message after* the system prompt (persona-output.md F1) — so the style is the stronger channel. But a **custom** style gets only a generic fallback per-turn reminder while built-ins like Concise get a tailored `turnReminder` re-injected after every user turn and every tool-result batch (F8, mechanism source-checked CONFIRMED from the raw issue body; note the "maintainer confirmed" framing in that thread is an attribution error — both parties are `authorAssociation: NONE`). Concise is also the exact behaviour he wants: leads with the result, skips preamble, and explicitly keeps full detail for error reports, security warnings, and destructive-action confirmations (F4).

**Downside, stated plainly.** Issue #89939 is a user running *three simultaneous layers* of anti-verbosity steering — a ~20-line CLAUDE.md rule, `outputStyle: "Concise"`, and a `UserPromptSubmit` hook — and the trained-in closing-paragraph behaviour still leaked "several times per session", including synonym drift around a banned phrase (F9). Stacking a fourth layer will not fix it. Two lines is the right price for a persona; twenty is not. And Anthropic's own prompting guidance warns that aggressive imperative framing ("CRITICAL: you MUST") now causes *overtriggering* on current models (F12) — his current phrasing ("Sweep every reply for a stray I") is close to that line.

---

## 7. Downsides register

Every downside surfaced across the thirteen files, with the mitigation this setup adopts or the reason it accepts the risk.

**Agents and delegation**
1. *Every agent's description loads every session, invoked or not; >15k combined triggers a warning* (subagents.md F2) → cut 10 agents to 5.
2. *MCP tool schemas may pass into subagents regardless of `tools:`, breaking Explore/Plan/general-purpose at 10+ servers* (F13, unconfirmed as fixed) → `scout` as a conditional fallback; prune connectors; deferred loading (mcp-tools.md F1) may already have solved it.
3. *A subagent's report can return as a bare pointer with no body, unrecoverably* (F15, ~190k tokens lost in one case) → `SubagentStop` hook logs `last_assistant_message`; agents write findings to a file too.
4. *The main agent can silently skip delegation and do the work inline at large token cost* (F15, issue #90182) → a smaller roster is itself the mitigation; verify delegation happened rather than assuming.
5. *Uncapped fan-out with no dedup: 437 agents / ~6M tokens in <15 min for 10 real issues* (F14) → workflow hard caps (16 concurrent / 1,000 per run) plus `workflowSizeGuideline`; never fan out reviewers without dedup.
6. *Isolation means every fact must be re-stated in the dispatch* (F109) → the four-part dispatch template: scope, self-contained context (paste the actual error), constraints, output spec.
7. *Multi-agent uses ~15× the tokens of a chat turn* (F12, 2025-era figures on a superseded model line) → accepted; it buys a measured capability gain on parallelizable work, not on everything.
8. *Forked subagents inherit the full parent conversation and can act on unrelated pending items* — one implemented an unauthorized DB migration in 41 minutes (failure-stories.md F11) → prefer non-inheriting subagents for narrow tasks; `git status` before committing.
9. *Worktree agents can branch from a stale commit, run green tests against the wrong tree, and report success indistinguishably from a clean run* (failure-stories.md F10, 77 commits stale) → force `git fetch` before spawning; pass an explicit base SHA.

**Commands and skills**
10. *A skill's rendered content stays in context across turns until compaction; after compaction only the most recent invocation of each survives, 5,000 tokens each within a 25,000-token shared budget* (slash-commands.md F10) → keep the working set small; `/doctor` quarterly.
11. *`allowed-tools` grants clear on the next message, not at session end* (F5) → do not design commands assuming persistent grants.
12. *A failed `` !`cmd` `` injection aborts the whole skill invocation silently; Claude never sees the content* (F33) → append `|| true` on anything that can legitimately exit non-zero.
13. *Project skills' `allowed-tools` are not gated by workspace trust — a repo's skill can grant itself broad access in a `-p` run in a folder never trusted* (F150) → read `allowed-tools` before running Claude Code in a cloned repo.
14. *Name collisions across five namespaces make `/x` ambiguous* (F153) → deleting the 13 command files removes his entire collision surface.
15. *Autonomous skill invocation can silently stop influencing behaviour with no error* (F151) → for anything that must happen, use a hook.

**Memory** — see §3 table (staleness with no freshness UI; authority leak; injection; unenforceability; per-machine divergence).

**Autonomy**
16. *`/goal`'s turn clause is judged by the same LLM judging the condition — not a deterministic counter* (goal-and-autonomy.md F10, "Disagreements") → keep the 8-block cap at default; add the machine-checkable clause anyway; check `/usage`.
17. *Routines run with zero approval prompts* (F21) → not adopted for anything with connector access.
18. *Routine fire payloads are an injection vector Anthropic built a specific defence for* (`<routine-fire-payload>` untrusted wrapper, F22) → evidence the risk class is live; another reason to skip Routines.
19. *Reward-hacking toward placeholder/stub code that merely compiles* (F29, one practitioner's own numbers) → the `verifier` plus his existing test-weakening tamper-notice hook.
20. *Runaway cost: $6,000 overnight, $1,800/2 days, $437/14k tool calls* (failure-stories.md F5, F6, secondary; one "$500M/30 days" figure is flagged as almost certainly garbled) → spend caps, no auto-reload, short loop intervals, `/usage`.
21. *Agents narrating success without proof* (F23, F13, F12) → the `verifier` is the single mitigation this whole document most insists on.

**Hooks**
22. *Only exit 2 blocks; exit 1 is silently non-blocking* (hooks-advanced.md F30).
23. *A timed-out PreToolUse hook does not block; PostToolUse can never block* (failure-stories.md F7) → do not treat a slow hook as a gate.
24. *`$CLAUDE_PROJECT_DIR` staleness silently disarms security hooks mid-session* (F8, issue #61616 open) → absolute paths.
25. *A shell profile that echoes on startup silently corrupts hook JSON, visible only in the debug log* (hooks-advanced.md F29) → guard profile echoes to interactive shells; he runs fish, worth checking.
26. *`PermissionRequest` decisions were reported ignored in a released version, closed not-planned* (F9) → test before depending on it.
27. *Two confusable block caps: Stop-hook 8-in-a-row (configurable) vs auto-mode classifier 3-in-a-row / 20-total (not configurable)* (F22, F34) → know which one fired before debugging.
28. *No cross-hook loop detection outside `Stop`* (F23, F24) → idempotent hooks, `async: true` for non-critical ones.

**Sessions, MCP, plugins, persona**
29. *Checkpoints miss Bash changes, background subagent edits, symlinks, and anything past 30 days / 100 checkpoints* (sessions-context.md F4, F6) → git is the undo layer; his symlinked config is explicitly in the miss set.
30. *Auto-compact is itself an expensive request; `/clear` costs nothing* (F180) → prefer `/clear` between unrelated tasks.
31. *Resuming a >1h idle, >100k-token session re-processes the full history once* (F11) → use the summary option or `/clear`.
32. *Context rot is real and starts well before the ceiling* (F21, F22) → 1M is headroom, not a strategy.
33. *Fast mode charges the full uncached input price for the entire existing conversation on first activation mid-session* (F184) → enable at session start or not at all.
34. *Tool schemas are static for the rest of the conversation once loaded, even under deferred loading* (mcp-tools.md F70) → prune.
35. *Bloated tool lists degrade tool-selection quality, not just cost* (plugins.md F129, one practitioner's claim) → same.
36. *Plugins execute arbitrary code with user privileges; a documented exploit chain rewrites permission settings via plugin hooks* (plugins.md F15; note the article's key quote is misattributed — it is a reader comment, not the researcher's text) → install only first-party or personally-read plugins.
37. *Toggling plugins mid-session invalidates the prompt cache* (plugins.md downsides) → batch plugin changes at session start.
38. *Trained-in behaviours survive triple-stacked steering, with synonym drift around banned phrases* (persona-output.md F9) → accept; two lines of persona, one built-in style, no third layer.
39. *Custom output styles get weaker per-turn reinforcement than built-ins* (persona-output.md F8) → use built-in Concise.
40. *Transcripts are plaintext and unencrypted; any credential printed by a tool lands in the JSONL* (observability.md F6) → lower `cleanupPeriodDays` to 14; never sync `~/.claude` transcripts.

---

## 8. What others have done that we should copy, and what we should improve on

1. **Copy: Anthropic's read-only reviewer with a hard confidence floor.** `code-reviewer` in the official `feature-dev` plugin has no Edit/Write at all and a rule: "**Only report issues with confidence ≥ 80.** Focus on issues that truly matter - quality over quantity" (subagents.md F6, source-checked verbatim). **Improve on it:** his `adversary` already has the harder protocol (self-commit before reading the diff, deterministic sweep for skipped tests). Add the confidence floor to it — his fleets produce volume, and the 437-agent incident was 140 findings that were really ~10 (F14).

2. **Copy: obra/superpowers' ledger requirement.** "Conversation memory does not survive compaction… controllers that lost their place have re-dispatched entire completed task sequences — the single most expensive failure observed. Track progress in a ledger file, not only in todos" (subagents.md F16). **Improve on it:** he already has `PROGRESS.md` under a 60-line cap; `/wrap` makes writing it a reflex instead of a good intention.

3. **Copy: obra's model-selection *by task type*, not by agent identity.** Mechanical → cheap model, integration/judgment → standard, architecture and the final whole-branch review → the most capable (subagents.md F11). **Improve on it:** use the per-invocation `model` override (which since v2.1.251 outranks frontmatter, F3) rather than minting a second reviewer agent — same benefit, no description-token cost.

4. **Copy: Anthropic's own interview-then-fresh-session pattern.** `AskUserQuestion` interview → `SPEC.md` → *new* session that reads only the spec (sessions-context.md F16). **Improve on it:** his `flow-spec` + `spec-judge` already beat the interview stage; what is missing is the session boundary. `/flow` currently specs and builds in one context, which is exactly the "kitchen sink session" the same doc names as an anti-pattern (F2).

5. **Copy: the ralph-wiggum plugin's hard `--max-iterations`, and its warning that unlimited is the default.** Both the official README and independent practitioners lead with the same line: "if you aren't careful, Claude will happily burn through all your tokens" (goal-and-autonomy.md F11, F25, F32). **Improve on it:** `/goal` has no equivalent hard cap — only a soft LLM-judged clause. Write the turn clause into every condition *and* keep `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` at 8.

6. **Copy: the ralph loop's explicit completion token** — an exact string the agent must emit, rather than trusting free-text "done" (goal-and-autonomy.md F25, F31, independently reinvented as `LOOP_COMPLETE` by a community implementation). **Improve on it:** pair it with the `verifier`, so the token has to be *earned* by command output rather than merely typed.

7. **Copy: Anthropic's `/doctor` and `/plugin` context-cost accounting.** Anthropic shipped a per-plugin "Context cost" estimate, a "Not used recently" flag at ≥2 weeks over ≥10 sessions, and a `/doctor` pass that finds unused skills/MCP/plugins versus their cost (plugins.md F11, slash-commands.md F20). **Improve on it:** nothing equivalent exists for *skills*, and he has 67 with 42 never named (audit §3). His `skills-lint` script should grow a usage arm that cross-references `~/.claude/history.jsonl` — that is a genuinely novel piece of tooling.

8. **Copy: `claude plugin eval --ablation with-without`.** Anthropic built an A/B harness that runs a no-plugin baseline arm and reports the score delta (plugins.md F8, verified against the shipped CLI). **Improve on it:** point it at his own skills. He has 64 skills and no evidence any of them beats the baseline — this is the only sourced mechanism in the entire corpus for actually answering that.

9. **Copy: the `stop_hook_active` guard pattern.** Parse the field, exit 0 when true, or hit the 8-block cap (hooks-advanced.md F22, practices #5). **Improve on it:** check his existing `stop-gate.sh` implements it; a Stop hook without that guard converges into a force-override with a warning rather than a clean stop.

10. **Copy: the "prefer CLI over MCP" rule, straight from Anthropic's cost docs** (mcp-tools.md F6). **Improve on it:** Ronacher's end position after reversing twice in six months is one step further — *skills that teach the agent to drive existing CLIs*, because MCP schemas are static once loaded and drift out from under hand-written docs (mcp-tools.md F7, contested, one practitioner). His `gh-cli` skill is already that shape. Extend it before adding any new MCP server.

---

## 9. Build list

Ordered by value. Every path under `~/.dotfiles/claude/.claude/`.

1. `agents/verifier.md` — anti-fabrication claim-checker; read-only, sonnet, `maxTurns: 25`; the single highest-value addition given his unattended habit.
2. **Delete** `agents/{cleanup,cli,comment,document,orchestrate,readme,sst,test}.md` — eight agents, zero real invocations, permanent description-token tax.
3. **Delete** all 13 files in `commands/` — superseded by skills, and a same-named skill wins the resolution order anyway.
4. `commands/btw.md` — `disable-model-invocation: true`; gives his 13-times-typed convention a real file and a promote-to-CLAUDE.md step.
5. `agents/repro.md` — bug triage; justified by `fix`-language being his #1 keyword at 90 hits.
6. `commands/wrap.md` — ledger writer; the mitigation for the most expensive documented failure (re-dispatching completed work after compaction).
7. `settings.json`: add `"outputStyle": "Concise"` — built-in, gets the tailored per-turn reminder a custom style cannot.
8. `settings.json`: add the `Notification` hook on `permission_prompt|idle_prompt` (`notify-send` on Arch, `osascript` on Mac).
9. `hooks/postcompact-verify.sh` + `PostCompact` wiring — re-check status claims at the boundary where fabrications cluster.
10. `hooks/subagent-log.sh` + `SubagentStop` wiring, `async: true` — captures `last_assistant_message` so a bare-pointer report loss is recoverable.
11. `CLAUDE.md`: add a `# Compact instructions` block — applies to every compaction including auto-compact; his file has none.
12. `settings.json`: `"cleanupPeriodDays": 14` — shortens plaintext transcript retention given the `.env` files his own auto-mode block already enumerates.
13. `commands/memory-audit.md` — the monthly prune that no shipped feature performs.
14. `scripts/skills-lint`: add a usage arm cross-referencing `~/.claude/history.jsonl` — 42 of 67 skills have never been named; nothing in the ecosystem measures this.
15. `agents/scout.md` — **conditional**: create only after `Explore` first fails with "prompt too long".
16. `hooks/git-guard.sh`: replace `$CLAUDE_PROJECT_DIR` anchoring with an absolute path; grep every hook for `exit 1` used as a gate.
17. `settings.json` env block: `CLAUDE_CODE_GOAL_CHECKIN_MINUTES=15`, keep `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` unset (default 8).
18. Run `/doctor`, then `/plugin` → Not used recently, then `/mcp` — prune connectors, audit playwright against claude-in-chrome and serena against the LSP plugins.
