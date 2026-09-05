# Decision register

Every component that was considered, with the verdict and the downside that was weighed. Dates are 4 September 2026. Sources are the research docs in `research/`.

## Adopted

| Component | Why | Downside accepted | Mitigation |
|---|---|---|---|
| Lifecycle hooks (command type only) | "An instruction is a request; a hook is enforcement" (Anthropic); issue #40117 shows six `--no-verify` commits past CLAUDE.md rules | Regex over strings, evadable by `bash -c`/`eval`; only `Edit|Write` seen by PostToolUse | CI remains the backstop; Stop gate runs the real suite; heredoc bypass closed at Stop (wave 2 item) |
| Scoped Stop gate (`test-changed`, full sweep every 15 min) | Unscoped full suites on every turn would get the gate disabled in a week (panel finding 4) | A failing unrelated test still blocks until the wedge valve (3 identical blocks) | `stopGate: false` per repo; `CC_NO_STOP_GATE=1` per session; valve degrades to advisory |
| Size guard 400/60 | Consensus band 250–300 / 20–50 is practitioner opinion; no controlled study | False positives on data tables and JSX | control-flow keywords excluded from the function regex; `ignore` defaults for locales/migrations/generated |
| Tamper notice on tests and gate configs | The most load-bearing prose rule ("never edit a test to go green") had no detector | Detector, not prohibition; can be argued past | Puts the loosening on the record in the transcript |
| Saved workflows (build-slices, review-diff, research-sweep, plan-review) | Deterministic orchestration; script holds the loop, context holds the answer; resumable | No mid-run user input; a failed agent forces later agents to rerun on resume | Human gates stay outside; waves keep fan-outs small |
| Wave scheduling from Depends-on + file ownership | Multi-agent failures cluster at unowned interfaces; independent slices should not serialise | Two implementations (script and workflow) must agree | Same log format; stage 0 computes maps from the plan when omitted |
| `claim-check`, `triage`, `explorer` agents; 8 agents deleted | Usage audit: all 10 custom agents effectively unused; fabrication clusters after compaction and failed tool calls; error triage is the top keyword | Every agent description loads every session | Roster kept at 5 |
| `/aside`, `/wrap`, `/ship`, `/memory-audit`; 13 commands deleted | Commands merged into skills; same-named skill wins resolution; `/aside` typed 13 times with no file behind it | `allowed-tools` grants clear on the next message | Human-timed commands only (`disable-model-invocation`) |
| Auto-memory kept; agent memory only on `explorer` | Memory is an index of where to look, never a cache of what will be found | Stale facts recalled with no freshness signal; nothing validates memory against the filesystem | verify-before-report rule in the agent body; monthly `/memory-audit`; four line types only, dated |
| `outputStyle: Concise` | Built-in styles get a tailored per-turn reminder; custom ones do not | Trained-in closing behaviour survives triple-stacked steering | Two-line persona, one style, no third layer |
| `skillListingBudgetFraction: 0.02` | 39 of 66 descriptions were being dropped | Keeps paying ~12K tokens per session | Real fix (per-project marketplace for domain skills) still open |
| Codebase map (opt-in, `codebaseMap: true`) | Cheap regenerated map as leads for explorers | Anthropic's `/doctor` trims exactly this from CLAUDE.md; stale mid-refactor | dirty-tree hash in the stamp; one-week measurement decides |
| Marketplace packaging (this repo): core plugin + domain bundles, loaded in place via `~/.claude/skills -> plugins/` | The developer asked for a marketplace; skills-dir plugins keep edits live while `plugin marketplace add` serves other machines | Cross-references had to move to `${CLAUDE_PLUGIN_ROOT}`; installs from the marketplace are copies, not links | `skills-lint` understands plugin roots; `flow install` links; the doctor flags double-registered hooks |
| Beads ideas only: `## Discovered` section, `slice-overlap --waves`, `/wrap` drain and decay, doctor checks on PROGRESS.md | The one gap Beads exposed: "log follow-ups" had no destination | — | — |
| Lesson provenance marker, silent fire counting, a CLAUDE.md budget writer, and a `permissions.deny` rung | Closes gaps 1–4 of `docs/research/raw/lesson-guardrails-2026.md`: rationale must travel with the rule and not live only in PROGRESS.md; nothing measured whether a lesson held; no budget/duplicate check at CLAUDE.md write time; no rung above hooks for the "agent routed around the hook" class | One more script and rung to keep in sync; a deny rung is JSON, so its provenance is the ruling text, never an inline comment | `lesson-record` prints `marker: lesson(<date>): <what>` to paste on the rung; `hookout.sh` appends a marked fire to `.claude/lesson-fires.log` silently; `lesson-stats` reads both; `lesson-claude-md` refuses duplicates and at-budget writes |

## Not adopted

| Component | Verdict | Reason |
|---|---|---|
| Beads (bd) as the work graph | Skip, revisit if work outliving its branch ≥ 5 per week | Dolt storage rewrite with documented silent write loss on concurrent closes; models dependencies but not file ownership; competes with PROGRESS.md, not the plan |
| graphify / GitNexus / code-graph MCPs | Skip | Vendor-only benchmarks (71.5× measured on documents, not code); marketing site with wrong install command; adds a third staleness axis; its PreToolUse hook fights receipt discipline |
| Agent teams | Skip | ~7× tokens in plan mode; no worktree isolation; not restored by `/resume`; split-pane unsupported in Ghostty |
| LLM-judged hooks (`prompt`/`agent`) | Later | Deterministic scripts cover the cases; agent hooks are marked experimental |
| `PermissionRequest` hooks | Later, test first | Reported ignored in a released version; `permissions.deny` is the documented hard gate |
| Community memory systems (claude-mem, mem0) | Skip | Same index-plus-details shape as native memory; no published accuracy numbers |
| Routines with connector access | Skip | Run with zero approval prompts; connector set satisfies the "lethal trifecta" |
| Serena in the explorer wave | Keep Serena, not in fan-outs | Concurrent language servers on one workspace: open issues on CPU/RAM and outright failure |
| LSP plugin for the primary language | Try one week, `diagnostics: false` | Clean typed TS: +0.000 F1 at +16% tokens; noisy TS: +0.246 F1 at −12% |
| `feature-dev`, `code-review`, `commit-commands` plugins | Skip | Duplicate flow / adversary / `/ship` |
| OpenTelemetry export | Skip for now | Needs a collector; the one useful metric conflates six rejection sources |
| Third-person persona at 21 lines | Cut to 2 lines | Instruction count degrades compliance independently of tokens |
| `cleanupPeriodDays: 14` | Left to the developer | Would delete resumable sessions |
| Renaming the harness | Keep "harness" | Developer's call |
| A mistake-to-guardrail command | `/lesson` skill (test → hook/lint → script → skill → CLAUDE.md) with `lesson-sites` and `lesson-record`; stop gate nudges from the second identical block; CLAUDE.md names the trigger | `/aside` only filed notes; the ladder now runs every time, and the ruling lands in PROGRESS.md |

## Open items, in priority order

0. Guard against command names that collide with Claude Code built-ins (`/btw` did; renamed to `/aside`). A deterministic check needs the built-in list, which the CLI does not expose; until then `flow doctor` cannot catch it.
0. Split `plugins/flow/bin/flow` (1,500+ lines; `cmdInit`/`cmdInstall` ~95 lines each) into modules — the harness's own size guard flags it on every edit.

1. Move ~20 domain skills into a private local marketplace enabled per project (the largest remaining context win).
2. Re-run `size_guard.py` over the changed set at Stop (closes the heredoc bypass) once the false-positive fixes prove out.
3. Baseline-aware gating: a per-repo record of pre-existing failures so a known-red repo blocks on regressions only.
4. `flow doctor` probe for the PATH a hook subprocess actually sees (macOS GUI launch).
5. Frozen-intent hash over the approved Behavior Inventory.
6. Measure: `/insights` monthly, `/usage` weekly, `skills-lint --usage` monthly; nobody has measured this for a solo developer.
| post-bash-write on gitignored runtime state | Drop `git check-ignore`d files from the changed list, except `.claude/`; skip the filter when the command touched an ignore file; `core.quotePath=false` | Container logs blocked every read-only command with size-guard noise; the fail-closed clause keeps a same-command `.gitignore` append from hiding a write |
