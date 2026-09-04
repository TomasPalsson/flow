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
| `/btw`, `/wrap`, `/ship`, `/memory-audit`; 13 commands deleted | Commands merged into skills; same-named skill wins resolution; `/btw` typed 13 times with no file behind it | `allowed-tools` grants clear on the next message | Human-timed commands only (`disable-model-invocation`) |
| Auto-memory kept; agent memory only on `explorer` | Memory is an index of where to look, never a cache of what will be found | Stale facts recalled with no freshness signal; nothing validates memory against the filesystem | verify-before-report rule in the agent body; monthly `/memory-audit`; four line types only, dated |
| `outputStyle: Concise` | Built-in styles get a tailored per-turn reminder; custom ones do not | Trained-in closing behaviour survives triple-stacked steering | Two-line persona, one style, no third layer |
| `skillListingBudgetFraction: 0.02` | 39 of 66 descriptions were being dropped | Keeps paying ~12K tokens per session | Real fix (per-project marketplace for domain skills) still open |
| Codebase map (opt-in, `codebaseMap: true`) | Cheap regenerated map as leads for explorers | Anthropic's `/doctor` trims exactly this from CLAUDE.md; stale mid-refactor | dirty-tree hash in the stamp; one-week measurement decides |
| Beads ideas only: `## Discovered` section, `slice-overlap --waves`, `/wrap` drain and decay, doctor checks on PROGRESS.md | The one gap Beads exposed: "log follow-ups" had no destination | — | — |

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

## Open items, in priority order

1. Move ~20 domain skills into a private local marketplace enabled per project (the largest remaining context win).
2. Re-run `size_guard.py` over the changed set at Stop (closes the heredoc bypass) once the false-positive fixes prove out.
3. Baseline-aware gating: a per-repo record of pre-existing failures so a known-red repo blocks on regressions only.
4. `harness doctor` probe for the PATH a hook subprocess actually sees (macOS GUI launch).
5. Frozen-intent hash over the approved Behavior Inventory.
6. Measure: `/insights` monthly, `/usage` weekly, `skills-lint --usage` monthly; nobody has measured this for a solo developer.
