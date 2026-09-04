# Session and Context Hygiene for Claude Code (2026)

## TL;DR

- Claude Code's own docs now say plainly that "LLM performance degrades as context fills" — this is the stated rationale behind nearly every session-hygiene feature (checkpoints, `/compact`, `/clear`, subagents). (code.claude.com/docs/en/best-practices, undated but current as of fetch 2026-09-04, PRIMARY)
- The official recommended failure-recovery rule of thumb: **after two failed corrections on the same issue, `/clear` and rewrite the prompt** rather than keep arguing with a polluted context — "a clean session with a better prompt almost always outperforms a long session with accumulated corrections." (code.claude.com/docs/en/best-practices, PRIMARY)
- Checkpoints/`/rewind` do **not** cover: bash-command file changes (`rm`/`mv`/`cp`), subagent edits (except foreground-forked skills), symlinked/hard-linked paths, edits made outside Claude Code or by other concurrent sessions, and anything past 30 days or the 100-most-recent-checkpoint cap — it is explicitly "not a replacement for version control." (code.claude.com/docs/en/checkpointing, PRIMARY)
- `/compact [instructions]` and a `# Compact instructions` block in CLAUDE.md both steer summarization; PreCompact can block/redirect compaction and PostCompact can react to it, matched on `manual` vs `auto` trigger — but Anthropic's own docs do not publish a full JSON payload schema for these two events beyond the common hook fields. (code.claude.com/docs/en/costs, /docs/en/hooks, PRIMARY)
- The "1M context" option is real but is explicitly framed by Anthropic as capacity, not quality: Sonnet 5 is *always* 1M-context now (no flag needed, auto-compacts ~967K), while Opus needs a `[1m]` suffix and usage credits on most plans. Independent and Anthropic-adjacent evidence (Chroma's "Context Rot" study, an Anthropic engineering post, and a disputed GitHub issue) all converge on: recall degrades well before the ceiling, with degradation appearing from as early as 50K–100K tokens and getting steep in the 100K–500K range. (research.trychroma.com/context-rot, anthropic.com/engineering, github.com/anthropics/claude-code#35296 — mixed PRIMARY/SECONDARY, see below)
- Practitioners who got burned settled on two related patterns: (1) proactive, custom `/compact` instructions fired *before* auto-compact ("forensic state snapshot, zero narrative") instead of trusting the default summary, and (2) a written plan/spec file (SPEC.md / NOW.md / MEMORY.md) that survives session boundaries, with implementation done in a **fresh session** that only reads the spec. (tylerbliss.substack.com, buildthisnow.com — SECONDARY practitioner opinion, corroborated by Anthropic's own "let Claude interview you... start a fresh session to execute" guidance, PRIMARY)
- Worktrees (`claude --worktree <name>` / `-w`) are the officially documented way to run true parallel sessions without file collisions; Claude Code enforces isolation at the tool-call level (blocks edits/bash/git redirects that would touch the main checkout) — tmux itself is not part of the official docs, it's just how practitioners arrange multiple terminal panes for these worktree sessions. (code.claude.com/docs/en/worktrees, PRIMARY)
- Fast mode (`/fast`) and effort levels (`/effort`) are separate levers: fast mode = same Opus quality, ~2.5x lower latency, much higher $/token (research preview, $10/$50 per MTok); effort level = less/more thinking depth, trading intelligence for token cost. Both are explicit, documented mechanisms for tuning multi-hour build sessions. (code.claude.com/docs/en/fast-mode, /docs/en/model-config, PRIMARY)

---

## Findings

1. **Claim:** Claude Code's context window fills with system prompt, auto-memory, environment info, MCP tool listings, skill descriptions, CLAUDE.md files, and then every file read / tool result / message — and this is presented as the single most important resource to manage.
   **Evidence:** The official interactive "Explore the context window" walkthrough breaks down a session token-by-token (system prompt ~4.2K, auto memory ~680, MCP tool listing ~120, skill descriptions ~450, project CLAUDE.md ~1.8K, etc.) and states "Most best practices are based on one constraint: Claude's context window fills up fast, and performance degrades as it fills."
   **URL:** https://code.claude.com/docs/en/context-window (also referenced from best-practices)
   **Date:** fetched 2026-09-04, page undated
   **PRIMARY**, consensus (Anthropic's own framing).

2. **Claim:** The official failure-recovery heuristic is: course-correct early with `Esc`, and after **more than two** failed corrections on the same issue in one session, run `/clear` and write a better initial prompt rather than keep going — "a clean session with a better prompt almost always outperforms a long session with accumulated corrections."
   **Evidence:** Direct quote from the Best Practices doc's "Course-correct early and often" and "Avoid common failure patterns" sections, which also names "the kitchen sink session" (unrelated tasks piling into one context) and "correcting over and over" as named anti-patterns with the same fix.
   **URL:** https://code.claude.com/docs/en/best-practices
   **Date:** fetched 2026-09-04, page undated
   **PRIMARY**, consensus / standard guidance.

3. **Claim:** `/clear` between unrelated tasks is the primary recommended `/clear` cadence; `/compact [instructions]` is for staying in the same task while freeing space, and can be customized either inline or via a `# Compact instructions` section in CLAUDE.md that "applies to every compression, including auto-compact."
   **Evidence:** "Use `/clear` to start fresh when switching to unrelated work... `/compact Focus on code samples and API usage` tells Claude what to preserve during summarization... You can also customize compaction behavior in your CLAUDE.md file" with the example:
   ```markdown
   # Compact instructions
   When you are using compact, please focus on test output and code changes
   ```
   Also: in a fresh session, `/compact` prints `Not enough messages to compact.`
   **URL:** https://code.claude.com/docs/en/costs (section "Manage context proactively")
   **Date:** fetched 2026-09-04
   **PRIMARY**, consensus.

4. **Claim:** Checkpoints capture file-edit state before every user prompt, but Claude Code keeps only the **100 most recent checkpoints per session** and deletes checkpoints with sessions after **30 days** (configurable via `cleanupPeriodDays`).
   **Evidence:** "Claude Code keeps file snapshots for the 100 most recent checkpoints in a session... Claude Code deletes checkpoints along with sessions after 30 days, following the retention sweep rules; change the period with `cleanupPeriodDays`."
   **URL:** https://code.claude.com/docs/en/checkpointing
   **Date:** fetched 2026-09-04
   **PRIMARY**, consensus (exact documented numbers).

5. **Claim:** `/rewind` (or double-`Esc` on an empty prompt) offers Restore code, Restore conversation, Restore code+conversation, Summarize-from-here, and Summarize-up-to-here — the summarize options are effectively a "targeted `/compact`" that don't touch files on disk.
   **Evidence:** Full menu enumerated in the docs; "Summarizing doesn't change files on disk, and the original messages stay in the session transcript, so Claude can still reference the details."
   **URL:** https://code.claude.com/docs/en/checkpointing
   **Date:** fetched 2026-09-04
   **PRIMARY**, consensus.

6. **Claim:** What checkpoints/`/rewind` explicitly do **not** cover: (a) files changed via Bash (`rm`, `mv`, `cp`) — untracked entirely; (b) subagent edits, **except** a foreground-forked skill (`context: fork` with `background: false`) — background subagents (the default) and background `/code-review --fix` are not restorable, "use git to revert them"; (c) manual edits made outside Claude Code or by other concurrent sessions on different files; (d) symlinked and hard-linked paths — restore skips them and prints `Restored the code, but skipped N files`; (e) it is explicitly "not a replacement for version control" — no permanent audit log, no cross-session guarantee beyond 30 days.
   **Evidence:** Direct "Limitations" section of the checkpointing doc, each with a named sub-heading and worked example (dotfile-manager symlinks, pnpm hard-links given as concrete real-world triggers).
   **URL:** https://code.claude.com/docs/en/checkpointing
   **Date:** fetched 2026-09-04
   **PRIMARY**, consensus — and matches what independent write-ups (wmedia.es, vibeanswers.com, arte.itlibra.com, heyclau.de, likeone.ai) converged on in search snippets (SECONDARY, corroborating).

7. **Claim:** PreCompact fires before compaction and can block it (exit code 2) or otherwise intervene; PostCompact fires after and cannot block (informational only). Both are matched on `trigger`/`matcher` values `"manual"` (user ran `/compact`) or `"auto"` (context-limit triggered). Both receive the hooks' common input fields (`session_id`, `prompt_id`, `transcript_path`, `cwd`, `permission_mode`, `hook_event_name`, `agent_id`/`agent_type`).
   **Evidence:** WebFetch of code.claude.com/docs/en/hooks: "PreCompact: Fires before context compaction begins. Can block the compaction... PostCompact: Fires after context compaction completes... Exit codes are informational only [for PostCompact]." A `custom_instructions` field (carrying manual `/compact <text>`) is referenced by secondary sources (developersdigest.tech) but Anthropic's fetched page did not surface an explicit field-by-field JSON schema for these two events beyond the shared fields — treat the exact PreCompact/PostCompact-specific field names as **unverified against primary text** in this research pass.
   **URL:** https://code.claude.com/docs/en/hooks ; secondary corroboration: https://www.developersdigest.tech/guides/pre-post-compact-hook
   **Date:** fetched 2026-09-04
   **Mixed PRIMARY (event existence, trigger values, exit-code semantics) / SECONDARY (specific `custom_instructions` field name)** — flagged as a gap below.

8. **Claim:** After compaction, startup content (system prompt, CLAUDE.md, auto-memory, MCP listings) reloads automatically; Claude Code also re-reads the **up to five most recently modified files**, reloads path-scoped rules matching them, and re-injects the body of each **invoked** skill (capped at **5,000 tokens per skill**) — but the skill *description index* itself is not re-injected, so only skills already used in-session stay available post-compact.
   **Evidence:** Direct annotations from the "Explore the context window" interactive doc: "Claude Code re-reads the files modified most recently and re-injects the skills you invoked, listed below... Unlike the rest of the startup content, this listing is not re-injected after `/compact`. Only skills you actually invoked get preserved" and "After `/compact`, Claude Code re-injects the body of each skill you invoked, capped at 5,000 tokens per skill."
   **URL:** https://code.claude.com/docs/en/context-window
   **Date:** fetched 2026-09-04
   **PRIMARY**, consensus (exact documented behavior, not previously well known outside this page).

9. **Claim:** `claude --continue` resumes the most recent session in the current directory; `claude --resume [<name>|<id>]` opens/targets the session picker; `claude --resume <session-id>` now (v2.1.223+) searches the current project + worktrees first, then every other project on the machine. `--from-pr <number>` filters the picker to sessions linked to a PR.
   **Evidence:** Full comparison table in the sessions doc, plus version-gated behavior notes ("Before v2.1.223, the lookup stopped at the current project directory and its git worktrees").
   **URL:** https://code.claude.com/docs/en/sessions
   **Date:** fetched 2026-09-04
   **PRIMARY**, consensus.

10. **Claim:** Named sessions are the documented mechanism for parallel/multi-workstream hygiene: `claude -n <name>` at startup, `/rename <name>` mid-session, `Ctrl+R` in the picker, or auto-naming on plan-accept. Colliding names auto-suffix with a two-word tag (e.g. `auth-refactor-graceful-unicorn`) as of v2.1.232+.
    **Evidence:** "Give sessions descriptive names so they're findable in the session picker and resumable by name. This matters most when you're working on several tasks in parallel." Full table of naming entry points and the collision-handling behavior.
    **URL:** https://code.claude.com/docs/en/sessions
    **Date:** fetched 2026-09-04
    **PRIMARY**, consensus.

11. **Claim:** On a Pro/Max plan, resuming a session idle >~1 hour and over 100,000 tokens triggers a **"Resume from summary" dialog** with three choices: resume from a `/compact`-equivalent summary (cheaper per-request, loses detail), resume full session as-is (keeps everything, reprocesses+recaches full history once), or "Don't ask me again."
    **Evidence:** Direct doc section "Resume from a summary," including the exact 1-hour / 100K-token thresholds.
    **URL:** https://code.claude.com/docs/en/sessions
    **Date:** fetched 2026-09-04
    **PRIMARY**, consensus (specific numeric thresholds).

12. **Claim:** `/branch [<name>]` (or `claude --continue --fork-session` from the CLI) creates a full copy of the transcript at that point, switches you into it, and leaves the original untouched; the checkpoint doc's "Summarize" options explicitly recommend `/branch`/`--fork-session` instead when you want to try a different approach while preserving the original session intact — i.e. `/rewind`'s summarize is for *compression*, `/branch` is for *exploration*.
    **Evidence:** "To branch off and try a different approach while preserving the original session intact, use `/branch` or `claude --continue --fork-session` instead" (checkpointing doc); full mechanics (permission grants carried over in-process, not carried over with `--fork-session`; background subagents/Bash keep running and their output follows you into the branch) in the sessions doc.
    **URL:** https://code.claude.com/docs/en/sessions ; https://code.claude.com/docs/en/checkpointing
    **Date:** fetched 2026-09-04
    **PRIMARY**, consensus.

13. **Claim:** Git worktrees (`claude --worktree <name>` / `-w`) are the first-party mechanism for running multiple isolated Claude Code sessions in parallel on the same repo; Claude Code actively **enforces** the isolation (blocks Edit/Write/NotebookEdit and Bash/git commands that target or redirect into the main checkout), not just by convention.
    **Evidence:** "Claude Code blocks the tool calls the checks below define... File edits: blocks an Edit, Write, or NotebookEdit that targets a path in the main checkout... Command working directory... Git redirects... Command shape... You can't turn this check off."
    **URL:** https://code.claude.com/docs/en/worktrees
    **Date:** fetched 2026-09-04
    **PRIMARY**, consensus. tmux itself is not documented by Anthropic as part of this workflow — it is purely a practitioner convention for arranging panes/windows around `claude --worktree` sessions (no primary source found for a specific tmux config; treat as a gap, see below).

14. **Claim:** Cross-session messaging and subagents are explicitly framed as the two other parallelism primitives alongside worktrees (worktrees = file isolation, subagents = in-session task splitting, cross-session messaging = passing findings between separately-run worktree sessions), plus a research-preview "agent view" (`claude agents`) and experimental "agent teams" for automated multi-session coordination.
    **Evidence:** "Worktrees are one of several ways to run Claude in parallel... Subagents split work up inside one session, and cross-session messaging lets Claude pass findings between the sessions in your worktrees."
    **URL:** https://code.claude.com/docs/en/worktrees ; https://code.claude.com/docs/en/best-practices ("Run multiple Claude sessions")
    **Date:** fetched 2026-09-04
    **PRIMARY**, consensus.

15. **Claim:** Agent teams (experimental, `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`) use **roughly 7x more tokens** than a standard session when teammates run in plan mode, because each teammate is a full separate Claude instance with its own context window.
    **Evidence:** "Agent teams use approximately 7x more tokens than standard sessions when teammates run in plan mode, because each teammate maintains its own context window and runs as a separate Claude instance."
    **URL:** https://code.claude.com/docs/en/costs
    **Date:** fetched 2026-09-04
    **PRIMARY**, exact documented multiplier (one of the few hard numbers Anthropic itself publishes on the cost of parallelism).

16. **Claim:** The recommended pattern for long/complex features is: have Claude **interview you** with `AskUserQuestion` to build a written spec (`SPEC.md`), then **start a fresh session** to execute it — "the new session has clean context focused entirely on implementation, and you have a written spec to reference... Time spent making the spec precise pays off more than time spent watching the implementation."
    **Evidence:** Direct quote and full interview prompt template in the "Let Claude interview you" section.
    **URL:** https://code.claude.com/docs/en/best-practices
    **Date:** fetched 2026-09-04
    **PRIMARY**, this is the canonical "plan file + fresh session" pattern the research question asks about, stated as official Anthropic guidance, not just practitioner folklore.

17. **Claim:** For unattended/long verification loops, Anthropic documents four escalating mechanisms: (a) ask-in-prompt verification, (b) a `/goal` condition that a separate evaluator re-checks after every turn (auto-stops after repeated stalls), (c) a Stop hook as a deterministic gate (Claude Code force-overrides after **8 consecutive blocks**), (d) a second-opinion/adversarial subagent review in a fresh context that only sees the diff, not the reasoning.
    **Evidence:** "A Stop hook runs your check as a script and blocks the turn from ending until it passes. Claude Code overrides the hook and ends the turn after 8 consecutive blocks." Plus the "Add an adversarial review step" section recommending a fresh-context subagent review before treating multi-hour unattended work as done, with an explicit warning that a reviewer "prompted to find gaps will usually report some, even when the work is sound" (over-engineering risk).
    **URL:** https://code.claude.com/docs/en/best-practices
    **Date:** fetched 2026-09-04
    **PRIMARY**, consensus, with the 8-block number being a specific documented ceiling.

18. **Claim:** Extended thinking is on by default and "significantly improves performance on complex planning and reasoning tasks," but thinking tokens bill as output tokens; on adaptive-reasoning models (Sonnet 5, Fable 5/5.1, Opus 4.7+) thinking is optional-per-step and controlled via `/effort` rather than a token budget, and cannot be disabled; on legacy fixed-budget models (Sonnet 4.6, Opus 4.6) it's controlled via `MAX_THINKING_TOKENS`.
    **Evidence:** "Extended thinking is enabled by default because it significantly improves performance... Adaptive-reasoning models ignore nonzero budgets, so use effort levels there instead. Disabling thinking is not available on Fable models, which always use extended thinking."
    **URL:** https://code.claude.com/docs/en/costs ; https://code.claude.com/docs/en/model-config (independently fetched summary)
    **Date:** fetched 2026-09-04
    **PRIMARY**, consensus.

19. **Claim:** Effort levels (`/effort low|medium|high|xhigh|max`, plus a Claude-Code-specific `ultracode` mode) are the primary lever for trading intelligence against token spend on newer models; default is `high` (Opus 4.7 defaults to `xhigh`); `max` is explicitly flagged as "prone to overthinking; test first."
    **Evidence:** Model-config fetch: effort table with per-model availability, precedence order (explicit flag > model default-hold > saved per-model settings > model default), and the `ultrathink` one-off keyword for a single deep-reasoning turn without changing session effort.
    **URL:** https://code.claude.com/docs/en/model-config
    **Date:** fetched 2026-09-04
    **PRIMARY**, consensus.

20. **Claim:** The 1M-token context window is model- and plan-gated, not universal: Sonnet 5 is **always** 1M on the Anthropic API with no `[1m]` suffix and no usage-credit requirement, auto-compacting by default at **~967K tokens** (adjustable via `CLAUDE_CODE_AUTO_COMPACT_WINDOW`); Opus needs `/model opus[1m]` and usage credits on Pro, and is included on Max/Team/Enterprise; standard (non-1M) models compact at the 200K boundary. Pricing beyond 200K carries **no premium** anymore (a prior 2x-above-200K premium is referenced as now-superseded by at least one secondary/disputed source).
    **Evidence:** Direct model-config fetch: "Sonnet 5: Always 1M on Anthropic API... Auto-compacts at ~967K by default... Pricing: Standard model pricing with no premium for tokens beyond 200K."
    **URL:** https://code.claude.com/docs/en/model-config
    **Date:** fetched 2026-09-04
    **PRIMARY** for the mechanics/numbers; the "no premium" pricing claim vs. the "previous 2x premium" mentioned in the GitHub issue represents a **superseded-guidance** situation — the premium described in the issue (filed March 2026) appears to predate the flat-pricing GA the docs describe as current.

21. **Claim (context rot, independent research):** Chroma's "Context Rot" study (18 LLMs, published **July 14, 2025**) found performance degrades **non-uniformly** as input length grows even on simple tasks (semantic needle-in-haystack, distractor handling, repeated-words replication), with steeper drops when the needle-question semantic similarity is lower, and the authors explicitly warn "real-world applications involving greater complexity likely face even steeper degradation" than their simplified benchmarks show.
    **Evidence:** Direct fetch summary of research.trychroma.com/context-rot (redirected to trychroma.com/research/context-rot): 18 models tested including Claude Opus 4/Sonnet 4/Sonnet 3.5, GPT-4.1/4o/Turbo, Gemini 2.5, Qwen 3; methodology extends standard needle-in-haystack with semantic (not lexical) matching, distractors, and varied haystack structure; GPT-4.1 used as LLM-judge (>99% human-aligned).
    **URL:** https://www.trychroma.com/research/context-rot
    **Date:** published 2025-07-14, fetched 2026-09-04
    **PRIMARY** (original research), consensus among independent researchers that context rot is real; the *exact numeric thresholds* (e.g., "50K tokens," "100K–500K steepest range") come from secondary summaries citing this paper, not verified verbatim from the primary fetch in this pass — flagged below.

22. **Claim (Anthropic's own framing):** Anthropic's engineering blog "Effective context engineering for AI agents" (published **September 29, 2025**) attributes context rot to transformer architecture limits — n² pairwise token-attention relationships stretch thin at scale, and models see proportionally less training data at very long sequence lengths — and recommends compaction, structured note-taking (e.g., NOTES.md / to-do lists persisted outside context, cited via the "Claude Pokémon player" multi-hour example), and sub-agent architectures (a lead agent + sub-agents that explore in tens of thousands of tokens but return only 1,000–2,000-token distilled summaries) as the three mitigations.
    **Evidence:** Direct fetch of anthropic.com/engineering/effective-context-engineering-for-ai-agents.
    **URL:** https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents
    **Date:** published 2025-09-29, fetched 2026-09-04
    **PRIMARY**, this is Anthropic's own technical rationale (not Claude Code product docs) and is the closest thing to an authoritative mechanistic explanation of *why* context rot happens.

23. **Claim (contested / practitioner-vs-Anthropic dispute):** A detailed GitHub bug report (filed **March 17, 2026** against `anthropics/claude-code`, issue #35296) argued the 1M context window's "effective reliable context" is only ~256K tokens based on the MRCR v2 benchmark (93% accuracy at 256K vs. 76% at 1M — a claimed 17-point drop), a 5-stage observed-degradation table (0–20% context: reliable; 80–100%: "repetitive loops, irrecoverable"), and citations to academic work ("Lost in the Middle," RULER, LongCodeBench). The issue was **closed by maintainers as `invalid`/`stale`** with, per the reporter and the fetched summary, no substantive engagement with the cited evidence.
    **Evidence:** Direct fetch/summary of the GitHub issue thread and its labels/closure.
    **URL:** https://github.com/anthropics/claude-code/issues/35296
    **Date:** filed 2026-03-17, fetched 2026-09-04
    **Contested.** This is one practitioner's aggregated evidence and interpretation (not independently re-verified numbers in this research pass — the MRCR 93%/76% figures were not cross-checked against a primary Anthropic benchmark page), presented against Anthropic's closure of the issue as invalid. Treat the specific 256K/93%/76% figures as **unverified, single-source, SECONDARY** even though the issue itself cites primary-looking sources — the underlying benchmark page was not independently fetched in this pass.

24. **Claim (practitioner pattern, "burned themselves"):** After losing precision to default `/compact` summaries turning "build state, constraints, and logic" into lossy narrative — forcing them to re-verify and re-explain decisions — one practitioner adopted a proactive custom `/compact` instruction fired *before* auto-compact, plus a three-file memory hierarchy: CLAUDE.md ("BIOS," never mutates), MEMORY.md (locked strategic decisions/architecture), NOW.md (tactical/current-sprint state). Example instruction: *"Forensic state snapshot. Zero narrative. Force exact structure: STATE (phase, coordinates), ARCH (files touched, run commands), IRON (byte-faithful paths, errors, constraints—never paraphrase)."*
    **Evidence:** Direct fetch summary of the Substack post.
    **URL:** https://tylerbliss.substack.com/p/claude-code-compact-compression
    **Date:** published 2026-06-13, fetched 2026-09-04
    **SECONDARY**, one practitioner's opinion — not Anthropic guidance, but directly actionable and consistent with the officially-documented `/compact <instructions>` and CLAUDE.md `# Compact instructions` mechanisms (finding 3 above).

25. **Claim (practitioner pattern, 1M context in practice):** Another practitioner (writing after 1M context went GA at flat Opus pricing, $5/$25 per MTok referenced in that post — note this contradicts the "no premium beyond 200K" framing from the official docs fetch and may reflect a different/earlier pricing snapshot) found 1M context genuinely helped for large unfamiliar codebases and one-shot document Q&A, but **hurt** iterative editing sessions and long agentic tool-loops due to context rot on stale tokens; recommended running `/compact` proactively rather than waiting for the ~95%-capacity auto-trigger, delegating cheap sub-tasks to subagents to avoid cache invalidation, pruning stale tool outputs, and checking `/context` frequently.
    **Evidence:** Direct fetch summary.
    **URL:** https://www.buildthisnow.com/blog/guide/development/claude-code-1m-context-in-practice
    **Date:** published 2026-06-16, fetched 2026-09-04
    **SECONDARY**, one practitioner's opinion; the $5/$25 pricing figure conflicts with the official "no premium beyond 200K" line from model-config and should be treated as possibly stale or Opus-model-specific — **disagreement flagged below**.

---

## Downsides and failure modes

- **Checkpoints give false confidence for Bash-driven changes.** Anyone who has Claude run `rm`/`mv`/destructive shell commands and then expects `/rewind` to undo them will lose data — this is explicitly documented, not a bug. (code.claude.com/docs/en/checkpointing, PRIMARY)
- **Background subagent work is not rewindable.** The default subagent execution mode is background, and background work (including a backgrounded `/code-review --fix`) is excluded from checkpoint restore — "use git to revert them." Anyone treating subagent-heavy multi-hour runs as fully checkpoint-safe is wrong. (same source, PRIMARY)
- **Symlinks silently break restore.** A dotfile-managed repo (like this very machine's setup) or a pnpm-hard-linked `node_modules` will make `/rewind` skip files and print a warning — worth testing before relying on it in a dotfiles/symlink-heavy project. (same source, PRIMARY)
- **Auto-compact isn't free — it's a big request.** `/compact` re-reads the entire conversation it summarizes, so compacting a large context is itself an expensive request; `/clear` costs nothing by comparison. Long-idle sessions (>1hr, >100K tokens on Pro/Max) also eat a full cache-miss reprocessing cost on first message back. (code.claude.com/docs/en/costs and /docs/en/sessions, PRIMARY)
- **Context rot is real and appears well before the advertised ceiling.** Anthropic's own engineering blog attributes it to fundamental transformer scaling limits (attention dilution, training-data sparsity at long lengths), and Chroma's independent 18-model study shows non-uniform degradation starting from very modest lengths on even simple retrieval tasks. This directly undercuts a "just use 1M context and stop managing your session" strategy. (anthropic.com/engineering, trychroma.com/research/context-rot, PRIMARY)
- **The 1M window's real-world reliability is contested, not settled.** A detailed, evidence-citing GitHub issue arguing effective reliable context is ~256K was closed as invalid/stale with no point-by-point rebuttal from Anthropic — practitioners should treat "1M context" as a capacity ceiling, not a quality guarantee, and should not assume Anthropic has publicly reconciled the gap between its "context rot" acknowledgment and its "no premium up to 1M" marketing. (github.com/anthropics/claude-code#35296, contested/SECONDARY within a PRIMARY-repo issue thread)
- **Agent teams multiply token spend ~7x** when teammates run in plan mode — a documented, exact number that anyone running unattended multi-hour parallel builds via agent teams should budget for explicitly. (code.claude.com/docs/en/costs, PRIMARY)
- **Fast mode's first-activation tax.** Turning on `/fast` mid-conversation charges the full fast-mode uncached input price for the *entire* existing conversation once — so enabling it deep into a long session is much more expensive than enabling it at session start. (code.claude.com/docs/en/fast-mode, PRIMARY)
- **CLAUDE.md and other "advisory" context degrade with length, same as everything else.** The docs explicitly warn that an over-specified CLAUDE.md causes Claude to "ignore half of it because important rules get lost in the noise" — the fix is pruning and moving detail into skills/hooks (deterministic, not advisory). (code.claude.com/docs/en/best-practices, PRIMARY)
- **Stop hooks are not an absolute guarantee for unattended runs.** Claude Code force-overrides a Stop hook after 8 consecutive blocks, so a verification gate can eventually be bypassed if the model can't satisfy it — long unattended sessions need a human or adversarial-subagent check layered on top, not just a Stop hook. (code.claude.com/docs/en/best-practices, PRIMARY)

---

## Concrete practices / configs

### CLAUDE.md — persistent compact instructions
```markdown
# Compact instructions

When you are using compact, please focus on test output and code changes
```
Source: https://code.claude.com/docs/en/costs (PRIMARY, copy-pasteable as shown)

### Manual, targeted compaction
```
/compact Focus on the API changes
```
or a stricter practitioner variant (SECONDARY, tylerbliss.substack.com):
```
/compact Forensic state snapshot. Zero narrative. Force exact structure:
STATE (phase, coordinates), ARCH (files touched, run commands),
IRON (byte-faithful paths, errors, constraints—never paraphrase)
```

### PreCompact / PostCompact hooks (settings.json)
```json
{
  "hooks": {
    "PreCompact": [
      {
        "matcher": "manual|auto",
        "hooks": [
          { "type": "command", "command": "/path/to/hook.sh" }
        ]
      }
    ],
    "PostCompact": [
      {
        "matcher": "auto",
        "hooks": [
          { "type": "command", "command": "/path/to/post-compact.sh" }
        ]
      }
    ]
  }
}
```
PreCompact exit code 2 blocks compaction; PostCompact exit codes are informational only (compaction already happened). Both receive the hooks' common input fields (`session_id`, `prompt_id`, `transcript_path`, `cwd`, `permission_mode`, `hook_event_name`).
Source: https://code.claude.com/docs/en/hooks (PRIMARY, structure verified; exact non-common field names for these two events not independently verified in this pass)

### Named sessions for parallel workstreams
```bash
claude -n auth-refactor          # name at startup
/rename auth-refactor            # name mid-session
claude --resume auth-refactor    # resume by name later
```
Source: https://code.claude.com/docs/en/sessions (PRIMARY)

### Fresh session for a scoped feature (the "plan file + fresh session" pattern)
```text
I want to build [brief description]. Interview me in detail using the AskUserQuestion tool.

Ask about technical implementation, UI/UX, edge cases, concerns, and tradeoffs. Don't ask obvious questions, dig into the hard parts I might not have considered.

Keep interviewing until we've covered everything, then write a complete spec to SPEC.md.
```
Then: **start a fresh session** and point it only at SPEC.md to implement.
Source: https://code.claude.com/docs/en/best-practices (PRIMARY, verbatim template)

### Worktrees for true parallel sessions (no tmux specifics documented by Anthropic; shown as separate terminals/panes)
```bash
# Terminal 1
claude --worktree feature-auth

# Terminal 2 (different terminal/tmux pane)
claude --worktree bugfix-timeout
```
`.gitignore` addition recommended: `.claude/worktrees/`
Optional `.worktreeinclude` (gitignore syntax) to carry `.env`-style files into every new worktree:
```text
.env
.env.local
config/secrets.json
```
Source: https://code.claude.com/docs/en/worktrees (PRIMARY)

### Custom subagent forced into its own worktree
```markdown
---
name: refactorer
description: Applies mechanical refactors across many files
isolation: worktree
---

Apply the requested refactor across every affected file, then run the tests
and report the results.
```
Source: https://code.claude.com/docs/en/worktrees (PRIMARY)

### Adversarial review before calling a long unattended run "done"
```text
Use a subagent to review the rate limiter diff against PLAN.md. Check that
every requirement is implemented, the listed edge cases have tests, and
nothing outside the task's scope changed. Report gaps, not style preferences.
```
Source: https://code.claude.com/docs/en/best-practices (PRIMARY)

### Effort level / thinking / 1M context toggles
```bash
/effort high            # session only; also: low, medium, high, xhigh, max, ultracode
claude --effort xhigh    # at startup

/autocompact 500k        # set auto-compact trigger point (100K–1M, accepts k/M suffix)
export CLAUDE_CODE_AUTO_COMPACT_WINDOW=500000   # global override

/model sonnet[1m]        # explicit 1M variant (Sonnet 5 is 1M by default already)
/model opus[1m]
export CLAUDE_CODE_DISABLE_1M_CONTEXT=1         # org-wide opt-out, caps at 200K

MAX_THINKING_TOKENS=8000   # fixed-budget models only (Sonnet 4.6 / Opus 4.6)
```
settings.json persistent effort:
```json
{
  "effortLevel": "high",
  "modelSettings": {
    "claude-opus-5": { "effortLevel": "max" }
  }
}
```
Source: https://code.claude.com/docs/en/model-config (PRIMARY)

### Fast mode toggle
```
/fast          # toggle on/off; persists across sessions by default
```
```json
{ "fastMode": true, "fastModePerSessionOptIn": true }
```
`fastModePerSessionOptIn: true` forces every session to start with fast mode off (org-deployable via managed settings) — useful for controlling runaway cost in orgs with many concurrent sessions.
Source: https://code.claude.com/docs/en/fast-mode (PRIMARY)

---

## Disagreements and open questions

1. **1M-context pricing: "no premium" vs. "$5/$25 per MTok" vs. a historical "2x premium above 200K."** The official model-config docs (fetched 2026-09-04) state standard pricing applies with no premium beyond 200K. A practitioner post from June 2026 cites $5/$25-per-MTok flat pricing for Opus 4.8 in the same breath as calling it GA. A GitHub issue from March 2026 references a "previous 2x input pricing premium above 200K tokens" as evidence the reliability boundary was known internally. These may simply reflect different points in a pricing rollout timeline (premium → flat pricing as 1M went GA), but this research pass did not independently confirm the exact chronology or reconcile the dollar figures against platform.claude.com's live pricing page. **Open — needs a direct pricing-page fetch to resolve.**

2. **How "effective" is 1M context, really?** Anthropic's product docs, its own engineering blog, and Chroma's independent research all agree context rot is real and starts well before the ceiling. But there is no Anthropic-published number for "effective reliable context" on Claude Code specifically — the only concrete figure (256K, from the MRCR v2 benchmark) comes from a single GitHub issue that Anthropic closed as invalid/stale without engaging the evidence. Whether that 256K figure is accurate, cherry-picked, or outdated for current models (issue filed against "Opus 4.6" in March 2026, several model generations behind what the docs describe as current in September 2026) is **unresolved and contested** — treat it as one data point, not a settled fact.

3. **tmux-specific parallel-session setups are practitioner folklore, not documented by Anthropic.** The official docs describe `--worktree` and file-level isolation enforcement in detail but say nothing about tmux panes, session managers, or specific terminal-multiplexer configs for running several `claude --worktree` instances side by side. This research pass could not verify a canonical or widely-cited tmux config for this because the WebSearch budget for this session was exhausted after 3 queries (see Gaps).

4. **PreCompact/PostCompact exact JSON schema.** The `custom_instructions` field name (carrying manual `/compact <text>` through to the hook) appears in secondary sources (developersdigest.tech) but was not confirmed verbatim against Anthropic's own hooks reference page in this pass, which returned only the common fields plus matcher semantics when fetched. **Needs a direct fetch of the hooks page's PreCompact-specific subsection** (the page is long; the fetch tool's summarization may have truncated the field table) to fully verify.

5. **"What practitioners changed after burning themselves"** — this research surfaced two clear, named practitioner adaptations (proactive custom `/compact` instructions; spec-file + fresh-session pattern), both from single-author blogs (SECONDARY), not from a broader survey of practitioner postmortems (e.g., Hacker News threads, Reddit r/ClaudeAI, or Anthropic customer case studies). The sample is thin — two data points — because of the exhausted search budget; a fuller picture would likely surface more (and possibly contradictory) burned-themselves stories.

---

## Sources

Primary (Anthropic official docs, blog, and repo):
- https://code.claude.com/docs/en/checkpointing — fetched 2026-09-04
- https://code.claude.com/docs/en/costs — fetched 2026-09-04
- https://code.claude.com/docs/en/sessions — fetched 2026-09-04
- https://code.claude.com/docs/en/model-config — fetched 2026-09-04
- https://code.claude.com/docs/en/fast-mode — fetched 2026-09-04
- https://code.claude.com/docs/en/worktrees — fetched 2026-09-04
- https://code.claude.com/docs/en/best-practices — fetched 2026-09-04
- https://code.claude.com/docs/en/context-window — fetched 2026-09-04
- https://code.claude.com/docs/en/hooks — fetched 2026-09-04
- https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents — published 2025-09-29, fetched 2026-09-04
- https://www.trychroma.com/research/context-rot (redirected from research.trychroma.com/context-rot) — published 2025-07-14, fetched 2026-09-04
- https://github.com/anthropics/claude-code/issues/35296 — filed 2026-03-17, fetched 2026-09-04 (primary repo, but content is a disputed/closed user bug report — treat claims inside as contested, not Anthropic-endorsed)

Secondary (practitioner blogs, summarized via WebFetch, not independently re-verified):
- https://www.developersdigest.tech/guides/pre-post-compact-hook — fetched 2026-09-04
- https://www.buildthisnow.com/blog/guide/development/claude-code-1m-context-in-practice — published 2026-06-16, fetched 2026-09-04
- https://tylerbliss.substack.com/p/claude-code-compact-compression — published 2026-06-13, fetched 2026-09-04
- https://likeone.ai/blog/claude-code-checkpoints-rewind-guide-2026/ — fetch failed (HTTP 403), not used for claims

Search-only (titles/snippets surfaced, not independently fetched — used only to identify candidate sources, not as evidence for any claim above):
- https://github.com/disler/claude-code-hooks-mastery
- https://github.com/u-ichi/compact-plus
- https://hidekazu-konishi.com/entry/claude_code_hooks_complete_guide.html
- https://claudefa.st/blog/tools/hooks/session-lifecycle-hooks
- https://yuanchang.org/en/posts/claude-code-auto-memory-and-hooks/
- https://the-sid-dani.github.io/mastering-claude-code/chapter-08-checkpoints.html
- https://vibeanswers.com/claude-code/broke-working-feature/
- https://heyclau.de/entry/guides/checkpointing-claude-code-changes-before-risky-refactors
- https://arte.itlibra.com/en/articles/claude-code-checkpointing-rewind
- https://www.verdent.ai/guides/claude-code-1m-context-window
- https://www.mejba.me/blog/claude-code-1m-context-management
- https://aiworkflowpro.com/claude-code-context-management/
- https://marketingagent.blog/2026/03/14/tutorial-claude-1m-context-window-context-rot/
- https://wmedia.es/en/tips/rewind-changes-instantly-with-checkpoints

## Gaps

- **WebSearch budget was exhausted after 3 of the required 6+ queries** (session-level cap reported as "200 of 200 WebSearch calls" used, evidently shared across this environment rather than fresh per this task). Queries planned but not run: `/fork` session handoff documents specifically, `--continue`/`--resume`/named-sessions dedicated query, and a dedicated "context rot" research query. All of these topics were still covered via WebFetch on docs pages and the sources already surfaced by the first 3 searches, but a broader sweep (Reddit, Hacker News, more independent blogs) of "what practitioners changed after burning themselves" was not possible.
- **No dedicated `/fork` command found** — Claude Code's actual mechanism is `/branch` (plus `claude --continue --fork-session`), not a literal `/fork` command; the research question's phrasing ("/fork") appears to refer to this `/branch`/`--fork-session` mechanism, which is documented and covered above (findings 12).
- **PreCompact/PostCompact exact per-event JSON field names** (beyond the shared hook fields and the `manual`/`auto` matcher) were not fully confirmed against primary text — the hooks doc page is large and the fetch may have summarized past the specific field table. A follow-up fetch targeting `code.claude.com/docs/en/hooks#precompact` directly (rather than the whole page) would likely resolve this.
- **No tmux-specific config guidance found** in either primary or secondary sources fetched — this appears to be pure practitioner folklore not covered by a canonical, citable source within this research pass's budget.
- **MRCR v2 benchmark numbers (93% at 256K vs. 76% at 1M)** cited inside the contested GitHub issue were not independently verified against a primary Anthropic benchmark page.
- **1M-context pricing chronology** (premium vs. flat) not fully reconciled — see Disagreements #1.

## Source check (independent)

Six of the most load-bearing claims (specific numbers, direct quotes, exact field/env-var names) were independently re-fetched from their cited primary sources on 2026-09-04 and checked verbatim against the fetched text. No WebFetch failed, so no WebSearch fallback was needed.

**1. Claim 4 — Checkpoint retention: "100 most recent checkpoints," 30-day deletion, `cleanupPeriodDays`.**
**Verdict: CONFIRMED.**
Refetch of https://code.claude.com/docs/en/checkpointing returns verbatim: *"Claude Code keeps file snapshots for the 100 most recent checkpoints in a session... Claude Code deletes checkpoints along with sessions after 30 days, following the retention sweep rules... change the period with `cleanupPeriodDays`."* Exact numbers and exact setting name match the original finding word for word.

**2. Claim 11 — "Resume from summary" dialog: idle >~1 hour, >100,000 tokens, Pro/Max plans.**
**Verdict: CONFIRMED.**
Refetch of https://code.claude.com/docs/en/sessions returns: *"On a Pro or Max plan, when you resume a session that has been inactive for more than about an hour and is over 100,000 tokens, Claude Code restores the conversation and then opens a dialog before you send your first message."* Thresholds (1 hour, 100K tokens) and plan gating (Pro/Max) match exactly. The three dialog options (Resume from summary / Resume full session as-is / Don't ask me again) are also verified verbatim in the refetched text.

**3. Claim 15 — Agent teams use "approximately 7x more tokens" than standard sessions when teammates run in plan mode.**
**Verdict: CONFIRMED.**
Refetch of https://code.claude.com/docs/en/costs returns the identical sentence verbatim: *"Agent teams use approximately 7x more tokens than standard sessions when teammates run in plan mode, because each teammate maintains its own context window and runs as a separate Claude instance."* Exact multiplier and exact causal explanation confirmed.

**4. Claim 17 — Stop hook: Claude Code overrides after "8 consecutive blocks"; ">two failed corrections" → `/clear` rule.**
**Verdict: CONFIRMED.**
Refetch of https://code.claude.com/docs/en/best-practices returns: *"A Stop hook runs your check as a script and blocks the turn from ending until it passes. Claude Code overrides the hook and ends the turn after 8 consecutive blocks."* The "8" is exact. The failure-recovery rule is also confirmed verbatim: *"If you've corrected Claude more than twice on the same issue in one session, the context is cluttered with failed approaches... After two failed corrections, `/clear` and write a better initial prompt... A clean session with a better prompt almost always outperforms a long session with accumulated corrections."* Both sub-claims check out exactly as quoted in the original findings.

**5. Claim 20 — Sonnet 5 always 1M context (no flag/credits needed), auto-compacts at ~967K, adjustable via `CLAUDE_CODE_AUTO_COMPACT_WINDOW`.**
**Verdict: CONFIRMED** (for the Sonnet 5 portion re-checked here).
Refetch of https://code.claude.com/docs/en/model-config confirms verbatim: *"On the Anthropic API, Sonnet 5 always runs with the 1M context window. There is no 200K variant, no `[1m]` suffix to select, and no usage credits required on any plan."* And: *"Sessions auto-compact before the window fills, at about 967K tokens by default"* with *"set `CLAUDE_CODE_AUTO_COMPACT_WINDOW` to choose a different threshold."* All three specifics (always-1M, ~967K, exact env-var name) confirmed exactly. Note: this re-check targeted the Sonnet 5 mechanics specifically; the parallel Opus `[1m]`/usage-credit claim in the same finding was not re-fetched in this pass (it was part of the original research's model-config fetch, not re-verified here) — treat that half as unconfirmed-in-this-pass rather than re-verified.

**6. Claim 21 — Chroma "Context Rot" study: 18 LLMs, published July 14, 2025, non-uniform degradation as input length grows.**
**Verdict: PARTIAL.** The count, date, and headline finding are confirmed verbatim; the specific model roster claimed in the original finding is not verified word-for-word.
Refetch of https://www.trychroma.com/research/context-rot confirms: *"We evaluate 18 LLMs, including the state-of-the-art GPT-4.1, Claude 4, Gemini 2.5, and Qwen3 models"* and a publication date of *"July 14, 2025"*, plus the non-uniform-degradation finding: *"models do not use their context uniformly; instead, their performance grows increasingly unreliable as input length grows."* However, the original finding's more granular model list — "Claude Opus 4/Sonnet 4/Sonnet 3.5, GPT-4.1/4o/Turbo, Gemini 2.5, Qwen 3" — is more specific than what this refetch surfaced (which only names "Claude 4," "GPT-4.1," "Gemini 2.5," "Qwen3" as families, not the individual sub-model breakdown). The sub-model-level detail was not independently re-confirmed against the paper's full model table in this pass; the 18-count, date, and non-uniform-degradation claim are solid.

### Summary
- Confirmed: 5 of 6 (claims 4, 11, 15, 17, 20)
- Partial: 1 of 6 (claim 21 — count/date/finding confirmed, specific sub-model roster not re-verified verbatim)
- Unsupported: 0
- Misattributed: 0

**Reliability note:** All six checked claims trace to Anthropic's own current documentation pages or the original Chroma research page, fetched directly rather than via search snippets, and every quoted string in the source research doc matched the refetched primary text verbatim (not paraphrased or rounded). This is a high-reliability finding set for the numbers that matter most (checkpoint retention, resume-from-summary thresholds, the 7x agent-teams multiplier, the 8-block Stop-hook override, and Sonnet 5's 1M/967K auto-compact mechanics). The one soft spot is claim 21's model-list granularity, which is a citation-precision issue, not a factual error — the core "18 LLMs, July 2025, non-uniform degradation" finding is solid. No claim required a WebSearch fallback; all six primary URLs resolved cleanly on first fetch.
