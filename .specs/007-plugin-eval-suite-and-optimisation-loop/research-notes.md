# Research notes (explorers, 2026-09-12)

## Spike (claude plugin eval, CLI v2.1.269)
- Case format: plugins/flow/evals/<case>/prompt.md (+ graders/*.md) or case.yaml schema_version "1.1"
- Grader types: regex, tool_used (tool, input_match, min, max), tool_order, file_exists, llm (3 Haiku votes), baseline; `arm: with-only` excluded from ablation score
- Two-arm 8-turn routing run: ~$0.35, ~50 s. Session default model was claude-opus-5[1m]; pin --model/--judge-model
- Child gets only the flow plugin + EMPTY workspace; hooks fire (session-context etc. in trace)
- Gotchas: max_turns 3 too low; tool_used max:0 needs min:0; fix skill did NOT fire on a plain bug report in an empty workspace (Claude explored, bailed) → routing cases need fixtures (context.add_dirs read-only, or scaffold_script with --scaffold)
- Bash/Write/Edit need --allow-tools and OS sandbox: bwrap 0.12 present, socat MISSING → code-editing cases blocked until `socat` installed
- evals/results/ gitignored. --json schemaVersion 1: aggregates.overallScore, meanDelta, cases[].arms.with/without[].graders[]

## Hooks in the eval child (explore-hooks-loop)
- stop-gate.sh:34, loop-gate.sh:16-19, session-context.sh:20-21 all exit silently without .git; none refuses to end a turn in an empty repo
- session-context.sh:48 runs `flow next` → can print `Next: /flow` (routing steer!) when .git exists

## Loop verifier (explore-hooks-loop)
- `flow loop check` (bin/lib/loop/check.js:16-42): exit 0 pass / 1 fail / 2 suspect; --json {verdict, verify_rc, tamper[], tail}
- verify.js:20-40 runs `sh -c "<verify>"` at toplevel, CI=true FLOW_LOOP=1, verify_timeout 600s
- init.js:64-65 caps: session 8 iterations; fresh 30 iterations / 480 min / stall 3
- driver.js:57-63: `claude -p <prompt> --output-format json --permission-mode <mode> [--model] [--max-turns] [--max-budget-usd]`
- Custom verifier: any shell command via --verify, so `claude plugin eval plugins/flow --json --threshold 0.9` works as the loop's oracle

## CLI wiring (explore-wiring)
- bin/flow:3327-3335 dispatch chain; lib modules export run() (bin/lib/loop.js:14-20, tutorial.js:1-11)
- doctor checks: buildDoctorChecks() bin/flow:1311-1346, push(id, 'PASS'|'WARN'|'FAIL', detail, fix?)
- cmdNext() bin/flow:2485-2665 reads PROGRESS.md, .claude/flow.json, plan.md slices, git state
- tests: scripts/tests/run.sh + lib.sh (run_cmd, assert_rc, tmp_repo); test_cli.sh:18-39 cli_in(dir, home, ...args); no test shells out to `claude`
- skills-lint checks dead path refs only, no frontmatter validation
- No `flow eval` subcommand exists

## Skill inventory (explore-skills)
- 29 skills; 10 with human gates; 24 need Bash/Write/Edit/git; only grill-me, grill-with-docs, scrutinize-idea, prompt-engineer are Read-only-cheap
- Routing edges: audit→feature/fix/pr-reviewer; claude-improver→fix; flow→flow-spec/flow-to-issues; flow-deepen→audit/feature; flow-spec→flow; prep→flow/grill-me; pr-reviewer→feature
- Descriptions >1024 chars: flow (1304), better-plan (1045), flow-deepen (1034), flow-to-issues (1027)
