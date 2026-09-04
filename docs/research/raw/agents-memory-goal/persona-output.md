# Output styles, personas, and system-prompt customisation in Claude Code (2026)

## TL;DR

- Claude Code has five layers for shaping behavior, in order of scope: **managed CLAUDE.md** (org) → **output style** (replaces/extends system prompt) → **user/project CLAUDE.md** (delivered as a *user message* after the system prompt, not part of it) → **`--append-system-prompt`** (one-off CLI addition) → **`--system-prompt`/`--system-prompt-file`** (full replacement). Anthropic's own comparison table frames output styles as "modify the system prompt... every response" vs. CLAUDE.md as "adds a user message... project conventions." (PRIMARY, code.claude.com/docs/en/output-styles, 2026)
- `/output-style` as a standalone command is **deprecated** (v2.1.73) and **removed** (v2.1.91); style is now set via `/config` or the `outputStyle` key in a settings file, and only takes effect after `/clear` or a new session because it's baked into the system prompt at session start. (PRIMARY, code.claude.com/docs/en/output-styles)
- The built-in **Concise** style (v2.1.237+) is the closest match to "terse, no preamble": it leads with the result and skips narration but still does full engineering work; error reports, security warnings, and destructive-action confirmations are explicitly exempted from the trim. (PRIMARY, code.claude.com/docs/en/output-styles)
- CLAUDE.md is explicitly **not enforced configuration** — Anthropic's own docs say "Claude treats them as context, not enforced configuration... there's no guarantee of strict compliance, especially for vague or conflicting instructions," and recommend keeping files under ~200 lines because "longer files consume more context and reduce adherence." (PRIMARY, code.claude.com/docs/en/memory)
- Real-world evidence that a persona/anti-verbosity directive gets crowded out: a filed Claude Code bug (#89939, Sept 2026) documents a user running **three simultaneous layers** of "don't add unrequested trailing commentary" steering — a ~20-line global CLAUDE.md rule, `outputStyle: "Concise"`, and a `UserPromptSubmit` hook — and the trained-in "closing paragraph" behavior still leaked through repeatedly. A linked bug (#88189) gives a plausible mechanism: **custom output styles never get Claude Code's per-turn `turnReminder` re-injection that built-in styles get**, so a custom style's steering is asserted once at session start and never refreshed, while Concise/Proactive re-assert every turn. (PRIMARY, github.com/anthropics/claude-code issues #89939, #88189, both 2026)
- Academic instruction-following benchmarks (not Claude-Code-specific, but directly on-point for "does instruction count degrade compliance") consistently find that compliance drops as the number of simultaneous constraints/turns rises — e.g. Multi-IF finds instruction-following accuracy falling turn-over-turn within a single multi-constraint conversation. This is general LLM behavior, not proof about CLAUDE.md specifically, but it's the closest primary research to the question. (PRIMARY, arxiv 2410.15553; arxiv 2310.20410)
- Practitioner-favorite CLAUDE.md/output-style patterns that people report keeping long-term skew toward **narrow, verifiable, single-purpose rules** ("Use 2-space indentation," "Run `npm test` before committing") over broad tone/persona directives — this matches Anthropic's own "specificity" guidance, though direct large-sample practitioner survey data was not found (see Gaps). (PRIMARY guidance / SECONDARY anecdote)
- Keybindings, notifications, and concise/verbose settings are all first-class, well-documented settings-file keys (`keybindings.json`, `preferredNotifChannel`, `outputStyle`) — cheap to change and orthogonal to the persona-crowding question, but relevant to a solo developer's full customization surface.
- Recommendation for a developer running a 21-line third-person persona directive: **collapse it into the built-in Concise style plus a short (≤5 line) tone rule**, because a custom persona block in CLAUDE.md pays real context/adherence cost every session and — per #88189 — gets weaker per-turn reinforcement than simply selecting Concise.

## Findings

1. **Output styles directly rewrite the system prompt; CLAUDE.md does not.** Output styles "modify the system prompt directly," applying to every response. CLAUDE.md content, by contrast, "is delivered as a user message after the system prompt, not as part of the system prompt itself." `--append-system-prompt` sits between these: it appends to the system prompt without removing anything, but "must be passed every invocation," making it suited to scripts/automation, not interactive personas. **Consensus / PRIMARY.** (code.claude.com/docs/en/output-styles; code.claude.com/docs/en/memory, 2026)

2. **`/output-style` is dead; use `/config` or the `outputStyle` setting key.** The standalone slash command was deprecated in v2.1.73 and removed in v2.1.91. Style selection is saved to `.claude/settings.local.json` by default. **Consensus / PRIMARY** (superseded guidance: any 2025-era tutorial referencing `/output-style` directly is stale). (code.claude.com/docs/en/output-styles, 2026)

3. **Custom output styles are a Markdown file with two frontmatter fields that matter most:** `keep-coding-instructions` (default `false` — set `true` to keep Claude Code's built-in SWE behavior while changing tone) and `description` (shown in the `/config` picker). Files can live at `~/.claude/output-styles/` (user), `.claude/output-styles/` (project, nearest-wins across nested dirs), or a managed policy directory. **Consensus / PRIMARY.** (code.claude.com/docs/en/output-styles, 2026)

4. **Built-in styles**: Default (existing SWE system prompt), **Proactive** (executes immediately, stronger autonomy than auto mode, doesn't require permission-mode changes), **Concise** (leads with result, skips preamble, "always keeps the complete content of error reports, security warnings, and confirmations for destructive actions"; requires v2.1.237+), **Explanatory** (adds "Insights" between actions), **Learning** (adds `TODO(human)` markers for collaborative coding). **Consensus / PRIMARY.** (code.claude.com/docs/en/output-styles, 2026)

5. **CLAUDE.md is explicitly framed by Anthropic as unenforced, adherence-degrading-with-length context, not configuration.** Direct quote: "Claude treats them as context, not enforced configuration. To block an action regardless of what Claude decides, use a PreToolUse hook instead. The more specific and concise your instructions, the more consistently Claude follows them." And under sizing guidance: "target under 200 lines per CLAUDE.md file. Longer files consume more context and reduce adherence." This is the single most load-bearing primary claim for the "cost of persona rules" question: Anthropic itself states length reduces adherence, independent of any specific instruction-count study. **Consensus / PRIMARY.** (code.claude.com/docs/en/memory, 2026)

6. **A managed-policy CLAUDE.md is the one channel with real enforcement-adjacent teeth** (org-wide, cannot be excluded by users), but Anthropic still classifies it as "behavioral guidance," distinct from `permissions.deny` / hooks, which are "enforced by the client regardless of what Claude decides to do." **Consensus / PRIMARY.** (code.claude.com/docs/en/memory, 2026)

7. **`--append-system-prompt` / `--append-system-prompt-file` add without removing; `--system-prompt` / `--system-prompt-file` replace the entire system prompt.** A related flag, `--append-subagent-system-prompt`, appends text to every subagent's system prompt (requires `-p` non-interactive mode, v2.1.205+). `--system-prompt`/`--system-prompt-file` also override `--exclude-dynamic-system-prompt-sections`. **Consensus / PRIMARY.** (code.claude.com/docs/en/cli-reference, via WebFetch synthesis, 2026 — note: this exact page returned a rendered-widget page on first fetch; the flag table was reconstructed from a WebFetch summarization pass over the live docs page and cross-checked against the Settings and Memory pages, which independently confirm `--append-system-prompt`'s existence and semantics. Treat exact flag names for the `-file` variants as PRIMARY-sourced but not independently re-verified against raw markdown.)

8. **Direct mechanism for why a custom persona/output-style may lose to trained defaults: `turnReminder` is a built-in-only privilege.** Filed bug #88189 (Claude Code v2.1.237) shows built-in styles carry two payloads — a `prompt` injected once at session start, and a `turnReminder` re-injected after every user turn and every tool-result batch (Concise's is literally "Be concise: lead with the result, skip preamble and narration, keep only what the user needs."). Custom file-based styles' loader builds `{name, description, prompt, source, baseDir, keepCodingInstructions}` — **no `turnReminder` key exists on that path**, so a custom style is asserted once and never re-fires, while Concise/Proactive reassert every turn. A follow-up comment (danrichman, v2.1.247) [UNVERIFIED: mislabeled "maintainer" — GitHub's `authorAssociation` for this commenter is `NONE`, i.e. no maintainer/collaborator relationship to anthropics/claude-code; treat as another external commenter's claim, not a maintainer confirmation] partially disputes the severity: custom styles do get *some* reminder via a generic fallback ("Remember to follow the specific guidelines for this style"), just weaker/less specific text, same frequency. **CONTESTED on severity, but the core asymmetry (custom styles get a generic vs. built-in a tailored per-turn reminder) is confirmed by the maintainer.** (PRIMARY, github.com/anthropics/claude-code#88189, filed 2026, comment dated to v2.1.247 build ~Sept 2026)

9. **Direct evidence of a persona/anti-verbosity rule being crowded out by trained-in model behavior, even when stacked three ways.** Bug #89939 ("Trailing unsolicited blocks... survive CLAUDE.md rules, a Concise output style, and per-turn hook injection," filed against Claude Code 2.1.246, Opus 5): the reporter ran (1) a ~20-line global CLAUDE.md rule titled "ANSWER THE QUESTION. ADD NOTHING," with an explicit pre-send deletion check, (2) `outputStyle: "Concise"`, and (3) a `UserPromptSubmit` hook injecting the same rule every turn — and the model still appended unrequested trailing summary blocks "several times per session." The reporter also documents **synonym drift** defeating a banned-phrase-style rule (a rule banning "something worth knowing" was followed by "Two things worth recording" — same construction, new wording — in the very session that had just written the rule) and notes this pattern as evidence of "trained-in closing behavior that user-level steering cannot reach," citing #88189 as the likely mechanism. **This is ONE practitioner's detailed, reproducible bug report, not a controlled study — treat as PLAUSIBLE/opinion, not consensus** — but it is a first-party, timestamped, reproducible artifact rather than a vague complaint. (PRIMARY as a data point / SECONDARY as an explanation, github.com/anthropics/claude-code#89939, 2026)

10. **A second independent report of output-style instructions losing to trained defaults**: #89083 ("[Bug] Claude ignores output style instructions and uses prohibited terminology (AI slop terms)," v2.1.241) — reporter says Claude "fails to follow instructions not to use AI slop terms like 'load-bearing'... fails to follow a concise output style as is defined in the output style and global rules." Sparse detail (no repro steps given), but it's a second, independently filed instance of the same symptom class as #89939. **One practitioner's opinion, sparse; corroborating rather than proving.** (PRIMARY, github.com/anthropics/claude-code#89083, 2026)

11. **General academic evidence that instruction-following degrades as constraint/turn count rises (not Claude-Code-specific).** IFEval (Zhou et al., arXiv 2311.07911, Nov 2023) established the "verifiable instructions" benchmark methodology (word counts, keyword mentions, etc.) but its own abstract doesn't isolate a constraint-count-vs-compliance curve. FollowBench (arXiv 2310.20410, camera-ready ACL 2024) is purpose-built around this exact question: it "progressively adds individual constraints to assess performance across varying difficulty levels" and reports LLM weaknesses that grow with constraint count. Multi-IF (arXiv 2410.15553, Oct 2024) directly measured multi-turn decay: e.g., o1-preview's average instruction-following accuracy "drops from 0.877 at the first turn to 0.707 at the third turn." **Consensus in the instruction-following literature that adding constraints/turns degrades compliance — but none of these papers test "a persona directive specifically crowds out task instructions" as a distinct mechanism; that inference is an analogy, not a direct finding.** (PRIMARY, arXiv 2311.07911 / 2310.20410 / 2410.15553)

12. **Anthropic's own prompt-engineering guidance treats persona/role framing as cheap and effective when short, but explicitly separates "give a role" (one sentence) from long behavioral blocks, and repeatedly warns against over-specifying/over-triggering with aggressive language** — e.g., "The fix is to dial back any aggressive language. Where you might have said 'CRITICAL: You MUST use this tool when...', you can use more normal prompting like 'Use this tool when...'." This is general system-prompt guidance (API-level, not CLAUDE.md-specific) but directly informs how a heavy persona block should be trimmed. **Consensus / PRIMARY.** (platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices, 2026)

13. **Concise output style is the closest built-in match to "terse output"; there is no separate "verbose" boolean setting documented in the current settings reference** — the `/config` menu references "verbose output" as a personal option (and `/config verbose=true` is used as a syntax example in the Settings docs), and `--verbose` exists as a CLI flag primarily for `stream-json`/debug output (shows tool-call/streaming detail), not as a prose-length control. Genuine terseness of prose is controlled via `outputStyle`, not a `verbose` toggle. **Some ambiguity here — the settings-reference fetch did not surface a documented `verbose` key even though `/config` and CLI examples reference one; treat this as an open documentation gap rather than a confirmed absence.** (PRIMARY with a gap, code.claude.com/docs/en/settings, code.claude.com/docs/en/cli-reference, 2026)

14. **Notifications/sounds**: `preferredNotifChannel` (enum, e.g. `"terminal_bell"`) picks terminal bell vs. desktop notification; `agentPushNotifEnabled` and `inputNeededNotifEnabled` control phone push notifications. Desktop notifications work out-of-the-box only in Ghostty, Kitty, and iTerm2 (iTerm2 needs "Notification Center Alerts" + "Send escape sequence-generated alerts" enabled manually); other terminals need `preferredNotifChannel: "terminal_bell"` or a `Notification` hook running a sound command (example given: `afplay /System/Library/Sounds/Glass.aiff` on macOS). **Consensus / PRIMARY.** (code.claude.com/docs/en/terminal-config, code.claude.com/docs/en/settings-reference, 2026)

15. **Keybindings are fully remappable via `~/.claude/keybindings.json`**, an object with a `bindings` array of `{context, bindings: {keystroke: action|null}}` blocks. Contexts include `Global`, `Chat`, `Autocomplete`, `Confirmation`, `Transcript`, `HistorySearch`, `Task`, and ~15 others; actions follow `namespace:action` syntax (e.g. `chat:submit`, `app:toggleTodos`). Chords use space-separated keystrokes (`ctrl+x ctrl+k`). Several shortcuts are hard-reserved and cannot be rebound (Ctrl+C, Ctrl+D, Ctrl+M, Ctrl+[, Ctrl+I, Ctrl+H, Caps Lock). Changes are hot-reloaded without restart. **Consensus / PRIMARY.** (code.claude.com/docs/en/keybindings, 2026)

16. **Practitioner style catalogs skew toward novelty/roleplay over terseness, and there's no strong evidence of a converged "best practice" set of kept tweaks.** A GitHub collection of six community output styles (Technical Evangelist, Tabloid Journalist, Zen Master, Haiku Helper, Existentialist Poet, Door-to-Door Vim Salesman) is explicitly "a repo I kind of just made for fun," with the author noting no style is designed around brevity and offering no data on retention. A second secondary source (eesel.ai) names a "Direct Objective" community style ("clear, professional communication without excessive deference or sycophantic language") as one popular pattern, alongside the three built-ins (Default/speed, Explanatory, Learning) as what it calls practitioner favorites — but this is a single blog's characterization, not a survey. **One practitioner's opinion / thin secondary evidence, not consensus** — direct large-N practitioner data on "which output-style tweaks people keep" was not located (see Gaps). (SECONDARY, github.com/hesreallyhim/awesome-claude-code-output-styles-that-i-really-like; eesel.ai/blog/output-styles-claude-code, dated Sept 29 2025 per the article's own byline, so pre-2026 but still current per the site)

## Downsides and failure modes

- **CLAUDE.md instructions are not enforced** — Anthropic's own troubleshooting section for "Claude isn't following my CLAUDE.md" starts from the premise that non-compliance is expected for "vague or conflicting instructions," and its fix path is entirely about making instructions *more specific and shorter*, not about the persona layer itself. (PRIMARY, code.claude.com/docs/en/memory)
- **Longer CLAUDE.md files measurably reduce adherence** per Anthropic's own guidance (200-line target, "Longer files consume more context and reduce adherence" — stated as fact, no external study cited). A 21-line third-person persona block is well under that ceiling in isolation, but it competes with every other rule in the same file for the "specific and concise" adherence budget.
- **Custom output styles get weaker per-turn reinforcement than built-ins by construction** (#88189) — a real, filed, version-numbered defect (still open as of the fetch date), not a hypothetical. If the developer's persona directive lives in a *custom* output style rather than CLAUDE.md, it inherits this weaker-steering problem on top of the general CLAUDE.md-adherence issue.
- **Trained-in closing/hedging behavior can survive triple-redundant steering** (#89939) — CLAUDE.md rule + Concise output style + per-turn hook injection, stacked, still leaked the exact behavior all three were written to suppress. This is the strongest available evidence for "a persona/tone rule doesn't just fail to help — it can coexist with total non-compliance on the very dimension it targets," at least for narrow stylistic behaviors like trailing commentary blocks.
- **Instruction-following literature shows general degradation as constraint/turn count rises** (Multi-IF, FollowBench) — not proof of CLAUDE.md-specific crowding-out, but consistent with the mechanism the user is asking about: more simultaneous constraints (persona rules + task rules + tone rules) statistically correlates with lower per-constraint compliance across the models these benchmarks tested. Caveat: these benchmarks test general-purpose LLM API calls, not Claude Code's specific system-prompt/CLAUDE.md architecture, so the mapping is an analogy.
- **Aggressive/CRITICAL-style persona language can *overtrigger*, not just underdeliver** — Anthropic's own migration guidance for Opus 4.5/4.6 explicitly warns that aggressive imperative language ("CRITICAL: You MUST...") that used to compensate for weaker instruction-following on older models now causes *overtriggering* on newer models, and recommends dialing language back to normal register. A heavy-handed 21-line third-person directive risks this failure mode in the opposite direction from crowding-out: it can overfire on the wrong triggers.
- **Output-style switches require `/clear` or a new session** — a persona baked into an output style isn't "live editable" mid-conversation the way a CLAUDE.md edit effectively is (project-root CLAUDE.md is re-read after `/compact`); this is a workflow cost, not a compliance cost, but relevant to a solo dev iterating on tone.

## Concrete practices / configs

**1. Minimal custom output style (keeps SWE behavior, adds tone only) — `~/.claude/output-styles/direct.md`:**
```markdown
---
name: Direct
description: Terse, third-person-free, answer-first tone for solo dev work
keep-coding-instructions: true
---

Lead with the result. No preamble, no "Let me..." or "I'll...", no restating the request.
Do not add a trailing summary, caveat, or "worth noting" block unless the user asked a
question that block directly answers. If nothing more needs saying, stop.

Keep full detail for: error reports, security warnings, and confirmations before any
destructive action (deleting files, force-push, dropping tables, etc.) — never trim these.
```
Select it with `/config` → Output style, or directly in a settings file:
```json
{ "outputStyle": "Direct" }
```
(PRIMARY structure per code.claude.com/docs/en/output-styles frontmatter table.)

**2. Or just use the built-in Concise style** (requires Claude Code v2.1.237+) — zero authoring cost, and per finding #8 it gets the tailored per-turn `turnReminder` a custom style currently cannot:
```json
{ "outputStyle": "Concise" }
```

**3. Trim CLAUDE.md to verifiable, narrow rules; move tone to the output style.** Per Anthropic's own specificity examples:
```markdown
- Use 2-space indentation.
- Run `npm test` before committing.
- API handlers live in `src/api/handlers/`.
```
rather than open-ended tone prose. Keep the whole file under ~200 lines; run `/doctor` for an automated trim proposal (v2.1.206+, "cuts content Claude can derive from the codebase... keeps pitfalls, rationale, and conventions that differ from tool defaults").

**4. If the persona must be enforced (not just requested), it belongs in a hook, not CLAUDE.md.** Per the docs: "If the instruction is something that must run at a specific point... write it as a hook instead. Hooks execute as shell commands at fixed lifecycle events and apply regardless of what Claude decides to do." A `PreToolUse` hook can block, but cannot itself rewrite prose tone — hooks are for *enforced actions*, not phrasing.

**5. One-off persona for a script/automation (not the interactive persona) — CLI:**
```bash
claude --append-system-prompt "Respond in second person only, imperative mood, no meta-commentary about what you are about to do." "your task here"
```
Must be passed every invocation (not persisted), per the docs — appropriate for CI/scripted use, not for a standing interactive persona.

**6. Notification setup for a solo dev (terminal bell everywhere, custom sound on macOS):**
```json
{
  "preferredNotifChannel": "terminal_bell",
  "hooks": {
    "Notification": [
      { "hooks": [{ "type": "command", "command": "afplay /System/Library/Sounds/Glass.aiff" }] }
    ]
  }
}
```

**7. Minimal keybindings tweak example (rebind an external editor key, unbind a default):**
```json
{
  "$schema": "https://www.schemastore.org/claude-code-keybindings.json",
  "bindings": [
    { "context": "Chat", "bindings": { "ctrl+e": "chat:externalEditor", "ctrl+u": null } }
  ]
}
```

## Disagreements and open questions

- **Severity of the custom-style `turnReminder` gap is contested even within the same GitHub thread**: the original reporter frames it as "custom styles never get a reminder," a comment from user danrichman [UNVERIFIED: this commenter is not a maintainer — GitHub reports `authorAssociation: NONE` for both this comment and the original report] corrects this to "custom styles get a weaker generic fallback reminder, same frequency" — so the asymmetry is confirmed but its practical impact is smaller than the original report implies, though the correction itself carries no more authority than the original filing. Not fully resolved as of the fetch date.
- **Whether "instruction count degrades compliance" (the academic literature) actually explains the specific CLAUDE.md/output-style crowding-out practitioners report is an inference, not a demonstrated causal link.** No paper or Anthropic doc directly tests "does adding a persona block to a system prompt reduce compliance with an unrelated task instruction in the same prompt" as an isolated variable. This report treats the analogy as plausible but flags it explicitly as unverified.
- **No documented `verbose` settings-reference key was found**, despite `/config` and CLI-flag examples referencing "verbose output" and `verbose=true` — this may be a docs gap, a renamed/legacy key, or a key intentionally excluded from the reference index. Not resolved.
- **No large-sample practitioner survey on "which output-style tweaks people actually keep long-term" was located.** The two secondary sources found (a for-fun GitHub style collection, one blog post) are thin and not representative; this is flagged as a real gap rather than papered over.

## Sources

- Output styles — Claude Code Docs. PRIMARY. https://code.claude.com/docs/en/output-styles (fetched 2026-09-04; page undated but describes current v2.1.257 behavior)
- Claude Code CLI reference (system-prompt flags, `--verbose`, `--output-format`, full flag list) — Claude Code Docs. PRIMARY. https://code.claude.com/docs/en/cli-reference (fetched 2026-09-04)
- Claude Code settings (precedence, `/config`, `outputStyle` mid-session behavior) — Claude Code Docs. PRIMARY. https://code.claude.com/docs/en/settings (fetched 2026-09-04)
- Claude Code settings reference (notifications, keybindings settings, outputStyle key) — Claude Code Docs. PRIMARY. https://code.claude.com/docs/en/settings-reference (fetched 2026-09-04)
- How Claude remembers your project (CLAUDE.md, auto memory, adherence guidance, troubleshooting) — Claude Code Docs. PRIMARY. https://code.claude.com/docs/en/memory (fetched 2026-09-04)
- Configure your terminal for Claude Code (notifications, sounds, bell, tmux, vim mode) — Claude Code Docs. PRIMARY. https://code.claude.com/docs/en/terminal-config (fetched 2026-09-04)
- Customize keyboard shortcuts (keybindings.json full reference) — Claude Code Docs. PRIMARY. https://code.claude.com/docs/en/keybindings (fetched 2026-09-04)
- Prompting best practices — Claude Docs (Anthropic API prompt engineering). PRIMARY. https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices (fetched 2026-09-04; redirected from docs.claude.com)
- GitHub issue #88189, "Custom output styles cannot set `turnReminder`, so they steer weaker than built-ins by construction," anthropics/claude-code. PRIMARY (first-party bug tracker). https://github.com/anthropics/claude-code/issues/88189 (filed against v2.1.237; comment dated to v2.1.247; fetched 2026-09-04)
- GitHub issue #89939, "Trailing unsolicited blocks... survive CLAUDE.md rules, a Concise output style, and per-turn hook injection," anthropics/claude-code. PRIMARY (practitioner bug report, one opinion). https://github.com/anthropics/claude-code/issues/89939 (filed against v2.1.246; fetched 2026-09-04)
- GitHub issue #89083, "Claude ignores output style instructions and uses prohibited terminology (AI slop terms)," anthropics/claude-code. PRIMARY (practitioner bug report, one opinion). https://github.com/anthropics/claude-code/issues/89083 (filed against v2.1.241; fetched 2026-09-04)
- GitHub issue #84769, "Agent using exclusive language and third-person references in responses," anthropics/claude-code. PRIMARY, tangential (about Claude referring to the *user* in third person, not a self-reference persona rule). https://github.com/anthropics/claude-code/issues/84769 (fetched 2026-09-04)
- IFEval: "Instruction-Following Evaluation for Large Language Models," Zhou et al. PRIMARY (academic paper, abstract only). https://arxiv.org/abs/2311.07911 (submitted Nov 14, 2023; fetched 2026-09-04)
- FollowBench: "A Multi-level Fine-grained Constraints Following Benchmark for Large Language Models." PRIMARY (academic paper, abstract only). https://arxiv.org/abs/2310.20410 (v3 camera-ready June 5, 2024; fetched 2026-09-04)
- Multi-IF: "Benchmarking LLMs on Multi-Turn and Multilingual Instructions Following." PRIMARY (academic paper, abstract + reported result). https://arxiv.org/abs/2410.15553 (submitted Oct 21, 2024, v2 Nov 13, 2024; fetched 2026-09-04)
- "Claude Code Output Styles Collection" (six community styles: Technical Evangelist, Tabloid Journalist, Zen Master, Haiku Helper, Existentialist Poet, Door-to-Door Vim Salesman). SECONDARY. https://github.com/hesreallyhim/awesome-claude-code-output-styles-that-i-really-like (fetched 2026-09-04; author-stated as a for-fun project, no date given)
- "A practical guide to output styles in Claude Code," eesel.ai. SECONDARY. https://www.eesel.ai/blog/output-styles-claude-code (byline dated September 29, 2025, per the article; fetched 2026-09-04)
- "Claude Code Output Styles: All 5, Including Concise," getclaudeskills.com. SECONDARY, listed by initial WebSearch but not independently fetched/verified this session — not used as a cited claim, listed here for completeness. https://www.getclaudeskills.com/blog/claude-code-output-styles-explained

## Source check (independent)

Six of the most load-bearing claims in this report were independently re-fetched from their cited sources and checked verbatim. Verdicts below.

**1. CLAUDE.md quote: "context, not enforced configuration" / 200-line adherence guidance (Finding #5).**
Source: https://code.claude.com/docs/en/memory (WebFetch, live page, 2026-09-04)
Verdict: **CONFIRMED.** The live page reads verbatim: "Claude treats them as context, not enforced configuration. To block an action regardless of what Claude decides, use a PreToolUse hook instead. The more specific and concise your instructions, the more consistently Claude follows them." And separately: "**Size**: target under 200 lines per CLAUDE.md file. Longer files consume more context and reduce adherence." Both quotes in the report match the live source exactly.

**2. `/output-style` deprecated in v2.1.73, removed in v2.1.91 (Finding #2).**
Source: https://code.claude.com/docs/en/output-styles (WebFetch, live page, 2026-09-04)
Verdict: **CONFIRMED.** Live page states verbatim: "The standalone `/output-style` command was deprecated in v2.1.73 and removed in v2.1.91. Use `/config` or edit the `outputStyle` setting directly."

**3. Concise style requires v2.1.237+; keeps full detail for error reports/security warnings/destructive-action confirmations (Finding #4).**
Source: https://code.claude.com/docs/en/output-styles (WebFetch, live page, 2026-09-04)
Verdict: **CONFIRMED.** Live page: "**Concise**: Claude leads with the result, skips preamble and narration, and keeps responses short by default, while doing the engineering work as thoroughly as in the Default style. ... Claude always keeps the complete content of error reports, security warnings, and confirmations for destructive actions. Requires Claude Code v2.1.237 or later." Matches the report's quote and version number exactly.

**4. GitHub #88189 — `turnReminder` mechanism and the "maintainer comment (danrichman)" attribution (Finding #8, and Disagreements section).**
Source: `gh issue view 88189 --repo anthropics/claude-code --json title,body,author,state,comments` (raw GitHub API data via gh CLI, 2026-09-04)
Verdict: **PARTIAL / MISATTRIBUTED on the "maintainer" label.** The technical mechanism claim is CONFIRMED verbatim from the raw issue body: "Built-in output styles carry two payloads: a `prompt` injected once into the system prompt, and a `turnReminder` re-injected after every user turn and every tool-result batch... Custom file-based output styles get only the first," with the loader object shape `{name, description, prompt, source, baseDir, keepCodingInstructions}` matching exactly. The danrichman comment is also CONFIRMED verbatim: "I think Step 4 of the repro isn't entirely accurate. As best as I can tell, custom styles do get a reminder, they just fall through to the `turnReminder ?? \"Remember to follow the specific guidelines for this style.\"` default. Same frequency as Concise, but weaker text. Ask still stands, just less severe than filed. (2.1.247)" — but the report's framing of this as **"a maintainer comment"** is **not supported**: the raw GitHub API data shows `"authorAssociation": "NONE"` for danrichman (identical to the original reporter, viktorius007, also `NONE`). Neither commenter has any collaborator/member/owner relationship to anthropics/claude-code. This changes the epistemic weight of the "confirmed by the maintainer" framing used in Finding #8 and the Disagreements section — it is one more external user's opinion, not an Anthropic-authoritative correction. **Both inline instances have been edited with `[UNVERIFIED: ...]` tags.**

**5. GitHub #89939 — three-layer steering setup, "Two things worth recording" synonym-drift example, v2.1.246/Opus 5 (Finding #9).**
Source: `gh issue view 89939 --repo anthropics/claude-code --json title,body,author,state` (raw GitHub API data via gh CLI, 2026-09-04)
Verdict: **CONFIRMED.** Raw issue body matches the report point-for-point: the rule titled "ANSWER THE QUESTION. ADD NOTHING." (~20 lines), `outputStyle: "Concise"`, and a `UserPromptSubmit` hook, all "enforced three ways simultaneously." The synonym-drift example is verbatim: "The rule banned *'something worth knowing'*. A later reply closed with **'Two things worth recording'** — same construction, one adjective changed." Filed against Claude Code 2.1.246; the WebFetch summary corroborates model Opus 5 and platform darwin/iTerm2 (not independently re-checked against raw JSON, since `--json` did not include environment fields, but no contradiction found).

**6. Multi-IF: o1-preview accuracy "drops from 0.877 at the first turn to 0.707 at the third turn" (Finding #11).**
Source: https://arxiv.org/abs/2410.15553 (WebFetch, abstract, 2026-09-04)
Verdict: **CONFIRMED.** The abstract contains the exact figure: "o1-preview drops from 0.877 at the first turn to 0.707 at the third turn in terms of average accuracy over all languages."

### Summary
- CONFIRMED: 5 of 6 (claims #1, #2, #3, #5, #6 above)
- PARTIAL/MISATTRIBUTED: 1 of 6 (claim #4 — the technical `turnReminder` mechanism itself is confirmed, but the "maintainer comment" attribution is unsupported by GitHub's own author-association data)
- UNSUPPORTED: 0 of 6
- No cited URL failed to resolve; no WebSearch fallback was needed.

### Reliability note
The report's PRIMARY-sourced factual claims (docs quotes, version numbers, GitHub issue content/quotes, and the academic figure) all check out verbatim against live sources — this is a well-sourced report on its core factual layer. The one real defect found is an **attribution error**, not a fabrication: the report twice describes a GitHub commenter as "a maintainer" when GitHub's own `authorAssociation` field says `NONE` for that account, identical to the original (non-maintainer) bug reporter. Because this attribution was used to lend the "custom styles are less severe than filed" correction more authority than it has earned, and because the report's own recommendation section leans on the #88189/#89939 mechanism as key evidence, readers should treat the severity-dispute resolution in Finding #8 as **two anonymous external users disagreeing**, not as an Anthropic engineer's authoritative correction — the underlying technical asymmetry (custom styles lack a tailored per-turn reminder) is still independently confirmed from the raw issue body regardless of who's arguing about its severity.

**Not fetchable / dead ends noted for transparency:** `https://www.claude.com/blog/claude-code-best-practices` and `https://www.claude.com/blog/best-practices-for-agentic-coding` both returned HTTP 404 and are not cited. DuckDuckGo HTML search was blocked by a CAPTCHA on every attempt. Bing web search via WebFetch returned only generic Claude.ai homepage/login results regardless of query specificity and could not be used to discover new practitioner URLs (Reddit/HN threads on this exact topic were sought but not located through available tools). WebSearch tool itself was unavailable for this entire session (budget exhausted before the first substantive query returned), so all URL discovery beyond the first search and GitHub's own search (`gh search issues`) came from WebFetch guesses against known doc/paper URL patterns.

## Notes on method / data provenance

Per-turn steering data for GitHub issue bodies and comments (findings 8-10) is user-submitted bug-report text, treated here as primary evidence of practitioner experience with the product, not as verified ground truth about model internals — the *mechanism* claims in #88189/#89939 (e.g., the exact shape of the `turnReminder ?? "Remember to follow..."` fallback) are the reporters' own code-reading/inference, not confirmed by an Anthropic engineer in the thread as fetched.
