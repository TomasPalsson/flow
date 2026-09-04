# What Experienced Developers Actually Do Day-to-Day With Claude Code / Codex / Cursor (2026)

## TL;DR

- **Consensus core loop is explore → plan → code → commit**, but by mid-2026 several heavy practitioners (Boris Cherny, Peter Steinberger) report using *less* planning ceremony than a year earlier because newer models need less hand-holding — plan mode is now situational, not mandatory. (PRIMARY: Anthropic docs; SECONDARY-then-PRIMARY-confirmed: Boris Cherny via VentureBeat/Slashdot coverage of his own thread)
- **Verification is the one thing almost everyone calls the highest-leverage lever.** Boris Cherny: giving Claude "a way to verify its work... will 2-3x the quality of the final result." Anthropic's own docs make this the #1 best practice ("Give Claude a way to verify its work... It's the difference between a session you watch and one you walk away from"). (PRIMARY, both)
- **`/clear` and context hygiene is the dominant "hygiene habit"**: Anthropic's official guidance says clear after 2 failed correction attempts on the same issue, and clear between unrelated tasks — "a clean session with a better prompt almost always outperforms a long session with accumulated corrections." (PRIMARY, code.claude.com/docs/en/best-practices)
- **Practitioners are split on how much they interrupt vs. walk away.** Mitchell Hashimoto runs *one* agent at a time, deliberately avoids notifications, and only checks in at natural breaks — aspiring to have agents busy just 10-20% of a workday. Peter Steinberger runs 3-8 agents in parallel in a terminal grid and explicitly tells people not to be afraid to interrupt mid-task since "file changes are atomic." Boris Cherny runs 5 terminal instances + 5-10 cloud sessions simultaneously. (All PRIMARY, one practitioner's opinion each — genuinely contested)
- **Worktrees are contested, not consensus.** Anthropic's docs and Dex Horthy/HumanLayer material recommend git worktrees for parallel isolated sessions; Peter Steinberger explicitly rejects them ("Having a tree/branch per change would make this significantly slower"), running most parallel agents in the same folder instead. (PRIMARY both sides — contested)
- **PR/commit size and review habits diverge sharply by practitioner.** Anthropic's own Code Review product data shows large PRs (>1000 lines) get far more findings (84% of them flag issues, avg 7.5 issues) than small ones (<50 lines: 31%, avg 0.5 issues) — implicit argument for smaller PRs. Boris Cherny reportedly ships 10-30 PRs/day (per Lenny's Podcast teaser, paywalled — could not verify full quote). Peter Steinberger has moved to **not reading most of the code at all** and commits straight to main, skipping PRs/branches for personal projects. (Mixed PRIMARY/SECONDARY — genuinely contested, not consensus)
- **What people explicitly stopped doing**: Armin Ronacher stopped using most of his custom slash commands and largely gave up on hooks ("haven't seen any efficiency gains from them yet") and sub-agent parallelization for anything but well-isolated tasks. Peter Steinberger stopped spec-driven/heavy upfront planning with Codex and stopped doing traditional code review. Boris Cherny reportedly stopped using plan mode by mid-2026 ("the newer models don't actually need a planning step" — per secondary coverage, not independently verified from a primary Boris post). (PRIMARY for Ronacher and Steinberger; SECONDARY/unverified for the Boris plan-mode claim)
- **Nobody credible endorses "just throw a goal at a pipeline and walk away" as a general practice.** Even Thariq Shihipar (Claude Code team), who ships the `/goal` and `/loop` autonomy features, states the precondition explicitly: "use `/goal` only if you have a verifiable finish line." Anthropic's own docs frame unattended runs as requiring an explicit verification gate (tests, Stop hook, or adversarial subagent review) before you can safely "walk away." This is closer to consensus than contested: autonomy is conditional on verifiability, not a default mode. (PRIMARY: Anthropic docs + Thariq via creatoreconomy.so interview)

## Findings

1. **Claim**: Anthropic's official best-practices doc codifies "explore → plan → code → commit" as the recommended default loop, using Shift+Tab plan mode, but explicitly says to skip planning for small/obvious diffs ("If you could describe the diff in one sentence, skip the plan").
   Evidence: "Planning is most useful when you're uncertain about the approach, when the change modifies multiple files, or when you're unfamiliar with the code being modified."
   Source: https://code.claude.com/docs/en/best-practices (fetched Sep 2026, doc undated but current)
   PRIMARY. Standard/consensus (this is the vendor's own canonical guidance, echoed by nearly every secondary write-up found).

2. **Claim**: Giving an agent a verification mechanism (tests, build, screenshot diff, linter) is the single highest-leverage practice across sources.
   Evidence: Anthropic docs: "Give Claude a check it can run: tests, a build, a screenshot to compare. It's the difference between a session you watch and one you walk away from." Boris Cherny (via his own X thread, mirrored at twitter-thread.com/t/2007179832300581177): "Probably the most important thing to get great results out of Claude Code -- give Claude a way to verify its work... it will 2-3x the quality of the final result."
   Source: https://code.claude.com/docs/en/best-practices ; https://twitter-thread.com/t/2007179832300581177 (Boris Cherny's own thread, Sep 2025)
   PRIMARY (both). Consensus — the most repeated claim across every source fetched in this research.

3. **Claim**: Anthropic's guidance on `/clear` cadence: clear between unrelated tasks, and clear after two failed correction attempts on the same issue rather than continuing to correct in place.
   Evidence: "If you've corrected Claude more than twice on the same issue in one session, the context is cluttered with failed approaches. Run `/clear` and start fresh... A clean session with a better prompt almost always outperforms a long session with accumulated corrections."
   Source: https://code.claude.com/docs/en/best-practices
   PRIMARY. Standard/consensus guidance (vendor doc, not contradicted by any practitioner source found).

4. **Claim**: Mitchell Hashimoto deliberately runs a single background agent at a time (not parallel fleets), disables desktop notifications to avoid context-switching, checks in only at natural breaks in his own manual work, and treats ~10-20% of a working day spent on agent-driven work as an aspirational (not yet achieved) target.
   Evidence: His own words per fetched summary: "I'd work on something else...I wasn't going on social media...I was in my own, normal, pre-AI deep thinking mode." He separates "vague planning sessions" from execution sessions, and reviews overnight/triage-agent reports each morning, picking only "slam dunk" tasks he's confident the agent will get right.
   Source: https://mitchellh.com/writing/my-ai-adoption-journey (2026)
   PRIMARY. One practitioner's opinion — directly contested by Steinberger and Cherny's much higher parallelism.

5. **Claim**: Peter Steinberger runs 3-8 agents concurrently in a 3x3 terminal grid, mostly in the *same* folder rather than separate worktrees, and explicitly argues against per-change worktrees for speed reasons.
   Evidence: "Having a tree/branch per change would make this significantly slower." He runs "between 3-8 in parallel," using queued "continue" messages when stepping away, and is comfortable interrupting mid-task: "Don't be afraid of stopping models mid-way, file changes are atomic and they are really good at picking up where they stopped."
   Source: https://steipete.me/posts/just-talk-to-it (Oct 14, 2025)
   PRIMARY. One practitioner's opinion — contested against Anthropic's own worktree recommendation and Dex Horthy's worktree-parallelization patterns.

6. **Claim**: Peter Steinberger has moved to *not reading most code the agent produces*, watching the token stream instead of doing traditional review, and commits directly to `main` rather than using PRs/branches on his personal/solo projects.
   Evidence: "These days I don't read much code anymore. I watch the stream and sometimes look at key parts, but I gotta be honest - most code I don't read." And: "I simply commit to main."
   Source: https://steipete.me/posts/2025/shipping-at-inference-speed (Dec 28, 2025); corroborated by secondary coverage titled "The creator of Clawd: 'I ship code I don't read'" at https://newsletter.pragmaticengineer.com/p/the-creator-of-clawd-i-ship-code
   PRIMARY (steipete.me) + SECONDARY (Pragmatic Engineer, which quotes him directly). One practitioner's opinion, and an outlier/contested one — most other sources (Anthropic docs, Willison, Indragie) still treat review/verification of output as necessary. Note this is explicitly for his own solo/experimental projects, not a claim about how teams should operate.

7. **Claim**: Armin Ronacher tried and abandoned most custom slash commands (`/fix-bug`, `/commit`, `/add-tests`, `/fix-nits`, `/next-todo`) in favor of direct conversation, and separately says hooks haven't shown efficiency gains for him.
   Evidence: "I expected these to be more useful than they ended up being... many of the ones that I added I ended up never using." "I tried hard to make hooks work, but I haven't seen any efficiency gains from them yet." Also on sub-agents: "tasks that don't parallelize well...create chaos," and he often gets "better results by starting new sessions" instead of spawning sub-agents.
   Source: https://lucumr.pocoo.org/2025/7/30/things-that-didnt-work/ (Jul 30, 2025)
   PRIMARY. One practitioner's opinion, but a fairly widely cited "what didn't work" counter-narrative to the general hooks/slash-command enthusiasm in vendor docs.

8. **Claim**: Armin Ronacher's overarching lesson from a year of agentic coding: elaborate pre-written prompting/tooling underperforms just taking the time to talk to the model clearly and consistently.
   Evidence: "without rigorous rules that you consistently follow as a developer, simply taking time to talk to the machine and give clear instructions outperforms elaborate pre-written prompts."
   Source: https://lucumr.pocoo.org/2025/7/30/things-that-didnt-work/
   PRIMARY. One practitioner's opinion, presented as a hard-won conclusion after trying the more elaborate tooling-heavy path first.

9. **Claim**: Armin Ronacher recommends Go over Python for agent-driven backend work because agents navigate its explicit interfaces and simple test execution more reliably; Python's "magic" (e.g., pytest fixture injection) trips agents up.
   Evidence: Go has "explicit context systems that simplify agent reasoning," "structural interfaces requiring no surprise navigation," a "stable ecosystem with minimal churn"; Python poses challenges because agents struggle with "Python's magic (eg: Pytest's fixture injection)."
   Source: https://lucumr.pocoo.org/2025/6/12/agentic-coding/ (Jun 12, 2025)
   PRIMARY. One practitioner's opinion (a contested, language-specific claim not corroborated elsewhere in this research).

10. **Claim**: Anthropic's own internal engineering teams have shifted from ad hoc "design doc → janky code → refactor → give up on tests" to test-driven development guided by Claude, and cut production-incident diagnosis time 3x; the Inference team cut model-documentation research time from ~60 minutes to 10-20 minutes.
    Evidence: Case study language directly attributed to Security Engineering and Inference teams.
    Source: https://claude.com/blog/how-anthropic-teams-use-claude-code (2026)
    PRIMARY (vendor-published, but sourced from internal team accounts — treat numeric claims as company-reported, not independently audited).

11. **Claim**: Anthropic's own Code Review product data: PRs over 1,000 changed lines get findings 84% of the time (avg 7.5 issues); PRs under 50 lines get findings only 31% of the time (avg 0.5 issues); after deploying automated review, substantive-comment rate on PRs rose from 16% to 54% with <1% of findings marked incorrect.
    Evidence: as reported in InfoQ/mlq.ai coverage of the Anthropic Code Review launch (March 9, 2026).
    Source: https://www.infoq.com/news/2026/04/claude-code-review/ ; corroborating https://mlq.ai/news/anthropic-launches-code-review-feature-for-claude-code/
    SECONDARY (press coverage of Anthropic's launch; original Anthropic post on Code Review was not directly fetched in this pass — flag as a gap). Presented as company-reported metrics, not independently verified. This is data-driven support for the "smaller PRs get better review" position but is about *automated* review quality, not human review habits.

12. **Claim**: Industry PR-size research (not Claude-specific) generally converges on <200 changed lines as the point where review quality holds up; review quality and revert-risk degrade materially above that.
    Evidence: "PRs with 200-400 lines changed have 40% fewer defects than larger PRs, small PRs (<200 lines) get approved 3x faster... each additional 100 lines increases review time by 25 minutes." Google is commonly cited as recommending <200 lines.
    Source: aggregated from search results citing cubic.dev, Graphite, Propel Code, em-tools.io blogs (2026) — SECONDARY, general software-engineering research, not agent-specific and not independently fetched/verified page-by-page in this pass.
    SECONDARY. Standard/consensus in general software engineering, predates and is independent of AI coding agents — flag as background context, not a "what AI practitioners say" finding.

13. **Claim**: Simon Willison treats automated tests as now mandatory rather than optional specifically *because* of agentic coding: "if the code has never been executed it's pure luck if it actually works when deployed," and test-first development "helps agents write more succinct and reliable code with minimal extra prompting."
    Source: https://simonw.substack.com/p/agentic-engineering-patterns
    PRIMARY. Consensus-leaning opinion — closely echoes Anthropic's and Boris Cherny's verification-first framing (Finding 2), suggesting genuine convergence across independent practitioners.

14. **Claim**: Simon Willison, describing a large port done with agents (the Ladybird/Rust translation project he covered), emphasizes that the human-directed, "hundreds of small prompts" steering style — not autonomous one-shot generation — is what produced a working result; he frames this as evidence against "just throw a goal at a pipeline."
    Evidence: the work was "human-directed, not autonomous code generation. He decided what to port, in what order, and what the Rust code should look like, using hundreds of small prompts to steer the agents."
    Source: search-result synthesis of https://simonwillison.net content (could not re-fetch the specific Ladybird post directly in this pass; treat as SECONDARY paraphrase of a primary source pending direct verification — gap noted below).
    SECONDARY (paraphrase, not independently re-fetched). Standard/consensus direction among the higher-supervision practitioners (Willison, Hashimoto, Anthropic docs) as against the higher-autonomy practitioners (Steinberger, parts of Boris Cherny's parallel-fleet approach).

15. **Claim**: Anthropic's docs formalize an "adversarial review" pattern — having a *fresh-context subagent* review a diff against a plan before treating work as done — as the recommended way to safely let a session run unattended, explicitly warning that a reviewer told to "find gaps" will over-report minor issues and that chasing every finding causes over-engineering.
    Evidence: "A reviewer prompted to find gaps will usually report some, even when the work is sound... Tell the reviewer to flag only gaps that affect correctness or the stated requirements, and treat the rest as optional."
    Source: https://code.claude.com/docs/en/best-practices
    PRIMARY. Standard/consensus (vendor's canonical unattended-run guidance).

16. **Claim**: Anthropic's docs list explicit named failure patterns worth stopping: "the kitchen sink session" (mixing unrelated tasks in one context — fix: `/clear`), "correcting over and over" (fix: `/clear` after 2 failed corrections), "the over-specified CLAUDE.md" (bloated CLAUDE.md causes Claude to ignore half of it), "the trust-then-verify gap" (plausible-looking code that fails on edge cases — fix: always verify before shipping), and "the infinite exploration" (unscoped "investigate" tasks blow the context budget — fix: scope narrowly or delegate to subagents).
    Source: https://code.claude.com/docs/en/best-practices
    PRIMARY. Standard/consensus (vendor-documented anti-patterns, distilled from internal team usage).

17. **Claim**: Thariq Shihipar (Claude Code team) frames `/goal`-driven autonomy as conditional, not a default: "use `/goal` only if you have a verifiable finish line," and describes using Claude to *find unknowns before building* (e.g., asking it to enumerate ways a Whisper transcription pipeline could fail) rather than jumping straight into an autonomous run.
    Source: https://creatoreconomy.so/p/how-i-plan-build-and-run-loops-with-claude-code-thariq-shihipar (2026, "Behind the Craft" interview); corroborated by tweet excerpt at https://x.com/petergyang/status/2078846124828545179
    PRIMARY (interview transcript excerpt + Thariq's own quoted words). Standard/consensus among Anthropic's own team — directly undercuts the "just throw a goal at a pipeline" framing this research was asked to check.

18. **Claim**: The Claude Code team cut the product's system prompt by roughly 80% as models improved, on the theory that hard-coded rules and examples constrain newer, more capable models rather than help them; the stated heuristic is "when a better model is released, the first thing to try is removing instructions."
    Source: https://creatoreconomy.so/p/how-i-plan-build-and-run-loops-with-claude-code-thariq-shihipar ; https://x.com/petergyang/status/2078846124828545179 (Thariq's own quote)
    PRIMARY. One practitioner/team's stated principle, presented as a general heuristic — worth treating as an opinion (contested by anyone maintaining large fixed CLAUDE.md/skill libraries) rather than settled consensus.

19. **Claim**: Boris Cherny (creator of Claude Code) personally runs 5 parallel terminal sessions via 5 separate git checkouts (numbered tabs 1-5) plus 5-10 additional sessions on claude.ai/code, using system notifications to know when a session needs input; he defaults to Opus 4.5 with extended thinking "for everything," reasoning that despite being slower per-token it needs less steering and so is "almost always faster" end to end.
    Evidence, his own words: "I use Opus 4.5 with thinking for everything...even though it's bigger & slower than Sonnet, since you have to steer it less...it is almost always faster."
    Source: https://twitter-thread.com/t/2007179832300581177 (mirror of Boris Cherny's own X thread, Sep 2025)
    PRIMARY. One practitioner's opinion (his own, but as the product's creator carries outsized weight — still a personal workflow choice, not a universal claim).

20. **Claim**: Boris Cherny's workflow starts most sessions in plan mode ("shift+tab twice"), iterates on the plan conversationally, then switches to auto-accept-edits mode to implement — i.e., the classic explore/plan/code loop, as of his Sep 2025 thread.
    Source: https://twitter-thread.com/t/2007179832300581177
    PRIMARY, dated Sep 2025.
    **Superseded-guidance flag**: multiple secondary sources (VentureBeat, mindwiredai.com, both SECONDARY, not independently re-verified against a primary Boris post) claim that by June 2026 Boris had stopped using plan mode entirely, saying "the newer models don't actually need a planning step." This could not be confirmed against a primary Boris source in this research pass (his fuller June 2026 remarks appear to live behind Lenny's Podcast paywall). Treat the "stopped using plan mode" claim as SECONDARY and unverified, flagged as a claimed but unconfirmed shift from his own Sep 2025 primary statement.

21. **Claim**: Boris Cherny reportedly has not written a line of code himself since November (implicitly ~Nov 2025) and ships 10-30 PRs per day, per a Lenny's Newsletter podcast teaser.
    Source: https://www.lennysnewsletter.com/p/head-of-claude-code-what-happens (Feb 19, 2026) — full transcript is paywalled; this claim reached this research only via a WebSearch snippet describing the episode, and could NOT be confirmed by directly fetching the primary content (paywall blocked it).
    SECONDARY / UNVERIFIED. Flag explicitly: this is a widely repeated number but this research could not confirm it against the actual primary transcript. Treat with caution.

22. **Claim**: Jesse Vincent (obra)'s Superpowers project ships an "opinionated engineering culture as a folder of markdown files" (SKILL.md files) that work across Claude Code, Cursor, Codex, Copilot CLI, Gemini CLI, and OpenCode — explicitly host-agnostic rather than Claude Code-specific.
    Source: search-result synthesis (SECONDARY summaries of the Superpowers GitHub repo / marc nuri blog / mymcpshelf blog) — the Superpowers repo itself was not directly fetched in this pass; the primary blog.fsck.com posts fetched (see #23) describe a different, newer (Sen 2.0) project rather than Superpowers directly.
    SECONDARY. Standard/consensus description of what Superpowers is, but not independently confirmed against the GitHub repo README in this pass — gap noted below.

23. **Claim**: Jesse Vincent, in his July 2026 "Some new agentic patterns" post, describes running multiple named agents concurrently at his company (Prime Radiant) — e.g., "Scribble" for tickets/wiki, "Nora" for go-to-market — plus an "agentic user in the loop" pattern where a persistent agent user ("Ada-sen") reviews and negotiates specs with the implementing coding agent (Claude Code) before changes ship, including iterative back-and-forth: "Ada would review Claude's spec, raising questions or concerns. Claude would update the spec."
    Source: https://blog.fsck.com/2026/07/05/new-patterns/ (Jul 5, 2026)
    PRIMARY. One practitioner's (and his team's) opinion/pattern — a distinctive, less commonly reported pattern (agent-as-reviewer-with-standing, not just human-as-reviewer) worth flagging as a real signal from an experienced practitioner, but not something claimed as consensus.

## Concrete practices / configs (copy-pasteable this week)

- **CLAUDE.md discipline** (PRIMARY, Anthropic docs): keep it short; for every line ask "would removing this cause Claude to make mistakes?" — if not, cut it. Include bash commands Claude can't guess, non-default code-style rules, test-runner preferences, repo etiquette (branch naming, PR conventions), architecture decisions, env-var quirks, and known gotchas. Exclude anything Claude can infer from reading the code, generic API docs (link instead), and "self-evident" advice like "write clean code." Check it into git. Run `/init` to bootstrap one, `/doctor` to get pruning suggestions on an existing one.
- **Verification-first prompting** (PRIMARY, Anthropic + Boris Cherny): instead of "implement a function that validates email addresses," write "write a validateEmail function. example test cases: user@example.com is true, invalid is false, user@.com is false. run the tests after implementing." Give Claude something with a pass/fail signal — tests, build exit code, linter, screenshot diff against a design — every time, not just for big tasks.
- **The `/clear`-after-two-corrections rule** (PRIMARY, Anthropic docs): if you've corrected the same issue more than twice in one session, stop correcting — run `/clear`, and write a better initial prompt incorporating what you learned, rather than continuing to patch a polluted context.
- **Explore → plan → code → commit as the default entry point, but skip planning when you can describe the diff in one sentence** (PRIMARY, Anthropic docs) — small/obvious fixes (typo, log line, variable rename) go straight to code.
- **"Interview me" pattern for larger features** (PRIMARY, Anthropic docs): prompt Claude to use the `AskUserQuestion` tool to interview you about technical implementation, UI/UX, edge cases and tradeoffs before writing a SPEC.md, then start implementation in a *fresh* session with only that spec as context.
- **Writer/Reviewer split-session pattern** (PRIMARY, Anthropic docs): implement in Session A, review the diff in a fresh Session B with no prior context/bias toward the code it wrote, feed the review back into Session A to fix.
- **Adversarial review before calling a task done**, especially for unattended/long runs (PRIMARY, Anthropic docs): a fresh subagent (or the bundled `/code-review` skill) checks the diff against the plan and reports only correctness/requirement gaps, not style nits, to avoid over-engineering churn.
- **Named failure patterns to watch for** (PRIMARY, Anthropic docs, see Finding 16): kitchen-sink sessions, repeated corrections, over-specified CLAUDE.md, trust-then-verify gap, unscoped "investigate" prompts.
- **Fan-out for mechanical migrations** (PRIMARY, Anthropic docs): generate a file list, loop `claude -p "Migrate $file..." --allowedTools "Edit,Bash(git commit *)"` over it, test on 2-3 files first and refine the prompt before running the full batch. Or use the bundled `/batch <instruction>` to auto-split across 5-30 worktree subagents each opening its own PR.
- **When a new model ships, prune before you add** (PRIMARY, Thariq Shihipar / Claude Code team): audit CLAUDE.md and skills for hard-coded rules/examples written for a weaker model and remove them rather than layering on more instructions.
- **Don't be afraid to interrupt mid-run** (PRIMARY, Peter Steinberger): file edits from agents are generally atomic/resumable, so stopping and redirecting is cheap — this is a live disagreement with Hashimoto's low-interruption style, so pick based on your own tolerance for context-switching.

## Disagreements and open questions

- **Parallelism level**: Hashimoto (1 agent) vs. Steinberger (3-8) vs. Boris Cherny (5 terminal + 5-10 cloud = 10-15) is a genuine, unresolved spectrum — no source argues there's a "right" number, and the practitioners' own stated reasons differ (Hashimoto: protect deep-thinking time; Steinberger/Cherny: maximize throughput).
- **Worktrees**: Anthropic docs + Dex Horthy's material push worktrees as the standard way to isolate parallel sessions; Steinberger explicitly argues against them for solo/personal-project speed. Not resolved — looks like a team-scale-vs-solo-scale split rather than one side being simply wrong.
- **Whether to read the code at all**: Steinberger's "I ship code I don't read" is a real outlier position, held for his own solo/experimental output, not endorsed anywhere else in this research; Willison, Hashimoto, and Anthropic's docs all still assume a human (or adversarial subagent) checks output before it's trusted. This is a genuine, live disagreement in the field, not just a framing difference — worth flagging to the reader as high-variance advice.
- **Plan mode's trajectory**: primary evidence (Boris's own Sep 2025 thread) shows heavy plan-mode use; widely repeated secondary claims say he dropped it entirely by mid-2026, but this research could not verify that specific claim against a primary source (paywalled). Treat the "plan mode is dying" narrative as plausible-but-unconfirmed.
- **PR size / Boris's "10-30 PRs/day"**: could not be verified against primary source (paywalled Lenny's podcast). This number circulates widely in secondary coverage; flag it as unverified rather than fact in any downstream use.
- **"Just throw a goal at a pipeline"**: no primary source found that actually recommends this as a default. The people building the autonomy features (Thariq/Anthropic) explicitly gate it on having a verifiable finish line. This appears to be closer to a strawman/marketing framing than something serious practitioners advocate — worth stating plainly rather than hedging.
- **Gaps not resolved in this pass**: (a) Boris Cherny's fuller June 2026 remarks (Lenny's Podcast, paywalled) — could not fetch primary content; (b) Simon Willison's specific Ladybird/Rust-port post was not independently re-fetched, only found via search synthesis; (c) the Jesse Vincent "Superpowers" project details came from secondary sources, not the primary GitHub repo or his original Superpowers blog posts (only his newer, distinct "Sen 2.0" post was fetched); (d) Anthropic's own Code Review launch blog post was not directly fetched — its metrics reached this report via press (InfoQ/mlq.ai) coverage only; (e) Indragie Karunaratne's and Dex Horthy's material here leans on WebFetch-tool summaries of pages rather than full-text extraction, so exact quote wording for those two should be re-verified before quoting them publicly.

## Sources

Primary (author's own words/site, or vendor's own docs):
- https://code.claude.com/docs/en/best-practices — Anthropic, official Claude Code best practices doc (fetched Sep 2026)
- https://claude.com/blog/how-anthropic-teams-use-claude-code — Anthropic, internal team case study (2026)
- https://lucumr.pocoo.org/2025/6/12/agentic-coding/ — Armin Ronacher, "Agentic Coding Recommendations" (Jun 12, 2025)
- https://lucumr.pocoo.org/2025/7/30/things-that-didnt-work/ — Armin Ronacher, "Agentic Coding Things That Didn't Work" (Jul 30, 2025)
- https://mitchellh.com/writing/my-ai-adoption-journey — Mitchell Hashimoto, "My AI Adoption Journey" (2026)
- https://github.com/humanlayer/12-factor-agents — Dex Horthy / HumanLayer, "12-Factor Agents"
- https://simonw.substack.com/p/agentic-engineering-patterns — Simon Willison, "Agentic Engineering Patterns"
- https://simonwillison.net/2026/Jul/21/cat-and-thariq/ — Simon Willison, fireside chat transcript with Cat & Thariq (Claude Code team) (Jul 21, 2026)
- https://www.indragie.com/blog/i-shipped-a-macos-app-built-entirely-by-claude-code — Indragie Karunaratne
- https://blog.fsck.com/2026/07/05/new-patterns/ — Jesse Vincent, "Some new agentic patterns" (Jul 5, 2026)
- https://steipete.me/posts/just-talk-to-it — Peter Steinberger, "Just Talk To It" (Oct 14, 2025)
- https://steipete.me/posts/2025/shipping-at-inference-speed — Peter Steinberger, "Shipping at Inference-Speed" (Dec 28, 2025)
- https://twitter-thread.com/t/2007179832300581177 — Boris Cherny, own X thread on his Claude Code setup (Sep 2025, mirrored)
- https://creatoreconomy.so/p/how-i-plan-build-and-run-loops-with-claude-code-thariq-shihipar — Thariq Shihipar interview/transcript (2026)
- https://x.com/petergyang/status/2078846124828545179 — Peter Yang tweet quoting Thariq Shihipar directly

Secondary (reporting on / summarizing primary sources):
- https://newsletter.pragmaticengineer.com/p/the-creator-of-clawd-i-ship-code — Gergely Orosz interviewing Peter Steinberger
- https://www.lennysnewsletter.com/p/head-of-claude-code-what-happens — Lenny's Podcast episode w/ Boris Cherny (Feb 19, 2026; transcript paywalled, only teaser accessible)
- https://www.infoq.com/news/2026/04/claude-code-review/ — InfoQ coverage of Anthropic Code Review launch metrics
- https://mlq.ai/news/anthropic-launches-code-review-feature-for-claude-code/ — corroborating coverage of same
- General PR-size research (cubic.dev, Graphite, Propel Code, em-tools.io, etc.) — aggregated via search, not agent-specific, background context only

Not independently fetched, reached only via WebSearch snippets (flagged as gaps above):
- Simon Willison's Ladybird/Rust-port post
- Boris Cherny's full June 2026 remarks (Lenny's Podcast)
- Jesse Vincent's original Superpowers posts / GitHub repo
- Anthropic's own Code Review launch blog post

## Source check (independent)

Method: picked the 6 most load-bearing claims (numbers, direct quotes, named attributions) and re-fetched the cited source independently to check whether it actually says what the claim asserts. Verdicts: CONFIRMED / PARTIAL / UNSUPPORTED / MISATTRIBUTED, per instructions. Where a cited URL failed, one WebSearch was run to look for the real source before concluding UNSUPPORTED.

1. **Finding 2 — "verification 2-3x's the quality" (Anthropic docs + Boris Cherny)** — **CONFIRMED** (both).
   - Anthropic docs (https://code.claude.com/docs/en/best-practices, re-fetched): "Give Claude a check it can run: tests, a build, a screenshot to compare. It's the difference between a session you watch and one you walk away from." — matches the report's quote exactly.
   - Boris Cherny (https://twitter-thread.com/t/2007179832300581177, re-fetched): "give Claude a way to verify its work. If Claude has that feedback loop, it will 2-3x the quality of the final result." — matches the report's quote essentially verbatim.
   - Caveat: twitter-thread.com is a third-party mirror of an X thread, not X.com itself. This check confirms the mirror's text matches what the report claims it says; it cannot independently authenticate that the mirror is a faithful, unaltered copy of Boris Cherny's original tweets (that would require fetching x.com directly, which was not attempted here).

2. **Finding 3 — Anthropic's `/clear`-after-two-corrections guidance** — **CONFIRMED**.
   - Re-fetched https://code.claude.com/docs/en/best-practices: "If you've corrected Claude more than twice on the same issue in one session, the context is cluttered with failed approaches. Run `/clear` and start fresh with a more specific prompt that incorporates what you learned. A clean session with a better prompt almost always outperforms a long session with accumulated corrections." — matches the report's quote nearly verbatim (report lightly paraphrases "start fresh" into "start fresh... rather than continuing to correct in place," which is a fair gloss, not a distortion). The doc also independently repeats this as a named failure pattern ("Correcting over and over... Fix: After two failed corrections, `/clear`..."), so the claim is doubly attested within the same primary source.

3. **Finding 6 — Peter Steinberger "I don't read much code" / "I simply commit to main"** — **CONFIRMED**.
   - Re-fetched https://steipete.me/posts/2025/shipping-at-inference-speed: "These days I don't read much code anymore. I watch the stream and sometimes look at key parts, but I gotta be honest - most code I don't read." and "I simply commit to main." — both quotes match the report verbatim. The page adds nuance the report already captures correctly: he says this "only works when developing solo, not in larger teams," and that on rare occasions a coding tool decides to use a worktree/branch itself.

4. **Finding 11 — Anthropic Code Review stats (84%/7.5 issues on >1000-line PRs; 31%/0.5 on <50-line PRs; substantive-comment rate 16%→54%; <1% marked incorrect)** — **CONFIRMED** (as secondary reporting of Anthropic's own figures).
   - Re-fetched https://www.infoq.com/news/2026/04/claude-code-review/: "On pull requests with more than 1,000 lines changed, Anthropic reports that 84% generated findings, with an average of 7.5 issues identified." / "For pull requests under 50 lines, 31% generated findings, averaging 0.5 issues." / "substantive review comments increased from 16% of pull requests to 54% after adoption." / "Fewer than 1% of findings were marked incorrect by engineers during internal use." — all four numbers match the report exactly. Still, as the report itself already flags, this is InfoQ's write-up of Anthropic's self-reported internal metrics, not an independently audited figure, and the original Anthropic launch post was not directly fetched by this check either — that gap stands as noted in the report.

5. **Finding 17 — Thariq Shihipar: "use `/goal` only if you have a verifiable finish line"** — **PARTIAL**.
   - Re-fetched https://creatoreconomy.so/p/how-i-plan-build-and-run-loops-with-claude-code-thariq-shihipar: the page is paywalled beyond a summary section. The short pull-quote "Use /goal only if you have a verifiable finish line" is visible and matches the report exactly — **confirmed for that specific quote**. But per the fetch, this line (and "Plan with Claude to discover and remove unknowns," and "When a better AI model is released, the first thing you should try is to remove instructions") sits in Peter Yang's summary/takeaways framing of the interview, not verified as Thariq's own verbatim words from the paywalled transcript body. The report already attributes it as "Thariq's own quoted words" via the corroborating tweet (x.com/petergyang/status/2078846124828545179), which is plausible but that tweet was not independently re-fetched in this check. Net: the claim's substance and the short quote both check out against available material, but the "own quoted words" framing rests on a summary layer, not the raw transcript.

6. **Finding 21 — Boris Cherny "hasn't written a line of code since November," ships 10-30 PRs/day** — **CONFIRMED** (via secondary corroboration; primary remains inaccessible).
   - Re-fetching the cited primary, https://www.lennysnewsletter.com/p/head-of-claude-code-what-happens, hit the same paywall the report already flagged — no new primary access.
   - Per instructions, ran one WebSearch to look for the real source, which surfaced multiple independent secondary write-ups converging on the same figures. One (https://www.bestblogs.dev/en/explore/topics/boris-cherny-claude-code-profile) reproduces a fuller quote attributed directly to the Lenny's Podcast transcript: "100% of my code is written by Claude Code. I haven't edited a line by hand since November. I ship 10–30 PRs a day, and I had five agents running while we were recording." Other independent hits (teamblind.com thread reporting "30 to 40 PRs per day," ernestchiang.com's write-up) corroborate the same claim with the same general magnitude.
   - This upgrades the report's own "SECONDARY / UNVERIFIED — treat with caution" flag: the number is real and multiply-corroborated across independent secondary sources, even though the primary paywalled transcript still could not be fetched directly. The report's existing caution flag (Findings 21, "Disagreements and open questions") should be read as "unconfirmed against primary" rather than "unconfirmed generally" — it is not an isolated or fabricated number.

**Overall reliability assessment**: All 6 checked claims held up — none were UNSUPPORTED or MISATTRIBUTED, so no inline `[UNVERIFIED: ...]` tags were added to the body of the report. The report's own hedging (PRIMARY vs SECONDARY labels, explicit "could not verify" flags on Findings 10, 21, 22, and the Willison/Superpowers gaps) is accurate and, if anything, slightly conservative — e.g. Finding 21's number turned out to have more independent secondary corroboration than the report credited it with. The report's practice of quoting sources verbatim and citing exact URLs made every check here fast and unambiguous; the main residual risk in the report is not fabrication but a few claims (Findings 17, 22) that lean on secondary summaries or paywalled excerpts of primary interviews rather than full primary text, which the report already discloses. Confidence in this report as a basis for a downstream recommendation: high for the vendor-doc-sourced claims (Findings 1-3, 15, 16), high for the individually-quoted practitioner claims with re-fetchable primary pages (Findings 6, 7, 8, 9, 13, 19, 20), and medium (explicitly flagged, correctly so) for the paywalled-source claims (10, 17, 21, 22).
