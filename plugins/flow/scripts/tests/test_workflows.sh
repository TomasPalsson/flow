#!/usr/bin/env bash
# tests/test_workflows.sh — U6 saved workflows (build-slices, review-diff,
# research-sweep, plan-review) and scripts/workflow-lint.
# Sourced by run.sh; HERE and SCAN_DIR come from there. Test names: t_wf_*.

WF_LINT="$SCAN_DIR/workflow-lint"
WF_DIR="$SCAN_DIR/../workflows"
WF_FIXTURES="$HERE/fixtures/workflows"
WF_RUN="$HERE/fixtures/wf-run.js"

t_wf_build_slices_ok() {
	run_cmd bash "$WF_LINT" "$WF_DIR/build-slices.js"
	assert_rc 0 "wf: build-slices.js lints clean"
	assert_contains "$OUT" "OK " "wf: build-slices.js prints OK"
}

t_wf_review_diff_ok() {
	run_cmd bash "$WF_LINT" "$WF_DIR/review-diff.js"
	assert_rc 0 "wf: review-diff.js lints clean"
	assert_contains "$OUT" "OK " "wf: review-diff.js prints OK"
}

t_wf_research_sweep_ok() {
	run_cmd bash "$WF_LINT" "$WF_DIR/research-sweep.js"
	assert_rc 0 "wf: research-sweep.js lints clean"
	assert_contains "$OUT" "OK " "wf: research-sweep.js prints OK"
}

t_wf_plan_review_ok() {
	run_cmd bash "$WF_LINT" "$WF_DIR/plan-review.js"
	assert_rc 0 "wf: plan-review.js lints clean"
	assert_contains "$OUT" "OK " "wf: plan-review.js prints OK"
}

t_wf_directory_scan_all_ok() {
	run_cmd bash "$WF_LINT" "$WF_DIR"
	assert_rc 0 "wf: directory scan of all four workflows is rc 0"
	local ok_count
	ok_count=$(printf '%s\n' "$OUT" | grep -c '^OK ')
	assert_eq "$ok_count" "4" "wf: directory scan prints 4 OK lines"
}

t_wf_default_dir_uses_claude_plugin_root() {
	local d fixdir
	d=$(tmp_dir)
	fixdir="$d/workflows"
	mkdir -p "$fixdir"
	cat >"$fixdir/plugin-root-sample.js" <<'EOF'
export const meta = {
  name: 'plugin-root-sample',
  description: 'test workflow used only to verify default-dir resolution',
};
EOF
	run_cmd env CLAUDE_PLUGIN_ROOT="$d" bash "$WF_LINT"
	assert_rc 0 "wf: default dir honors CLAUDE_PLUGIN_ROOT rc0"
	assert_contains "$OUT" "OK $fixdir/plugin-root-sample.js" "wf: default dir scans \${CLAUDE_PLUGIN_ROOT}/workflows"
}

t_wf_default_dir_fallback_skills_flow_workflows() {
	local d copydir fakehome fixdir
	d=$(tmp_dir)
	copydir="$d/scriptcopy"
	mkdir -p "$copydir"
	cp "$WF_LINT" "$copydir/workflow-lint"
	chmod +x "$copydir/workflow-lint"
	fakehome="$d/home"
	fixdir="$fakehome/.claude/skills/flow/workflows"
	mkdir -p "$fixdir"
	cat >"$fixdir/skills-flow-sample.js" <<'EOF'
export const meta = {
  name: 'skills-flow-sample',
  description: 'test workflow used only to verify default-dir fallback',
};
EOF
	run_cmd env CLAUDE_PLUGIN_ROOT= HOME="$fakehome" bash "$copydir/workflow-lint"
	assert_rc 0 "wf: default dir falls back to ~/.claude/skills/flow/workflows rc0"
	assert_contains "$OUT" "OK $fixdir/skills-flow-sample.js" "wf: default dir found the skills/flow/workflows fixture"
}

t_wf_default_dir_fallback_home_claude_workflows() {
	local d copydir fakehome fixdir
	d=$(tmp_dir)
	copydir="$d/scriptcopy2"
	mkdir -p "$copydir"
	cp "$WF_LINT" "$copydir/workflow-lint"
	chmod +x "$copydir/workflow-lint"
	fakehome="$d/home2"
	fixdir="$fakehome/.claude/workflows"
	mkdir -p "$fixdir"
	cat >"$fixdir/home-claude-sample.js" <<'EOF'
export const meta = {
  name: 'home-claude-sample',
  description: 'test workflow used only to verify the final default-dir fallback',
};
EOF
	run_cmd env CLAUDE_PLUGIN_ROOT= HOME="$fakehome" bash "$copydir/workflow-lint"
	assert_rc 0 "wf: default dir falls back to ~/.claude/workflows rc0"
	assert_contains "$OUT" "OK $fixdir/home-claude-sample.js" "wf: default dir found the ~/.claude/workflows fixture"
}

t_wf_help() {
	run_cmd bash "$WF_LINT" --help
	assert_rc 0 "wf: --help exits 0"
	assert_contains "$OUT" "Usage" "wf: --help prints usage"
}

t_wf_fixture_bad_name() {
	run_cmd bash "$WF_LINT" "$WF_FIXTURES/bad-name.js"
	assert_rc 1 "wf fixture: bad-name.js fails lint"
	assert_contains "$OUT" "meta-name" "wf fixture: bad-name.js reports meta-name"
}

t_wf_fixture_interpolated_meta() {
	run_cmd bash "$WF_LINT" "$WF_FIXTURES/interpolated-meta.js"
	assert_rc 1 "wf fixture: interpolated-meta.js fails lint"
	assert_contains "$OUT" "meta-pure" "wf fixture: interpolated-meta.js reports meta-pure"
}

t_wf_fixture_phase_mismatch() {
	run_cmd bash "$WF_LINT" "$WF_FIXTURES/phase-mismatch.js"
	assert_rc 1 "wf fixture: phase-mismatch.js fails lint"
	assert_contains "$OUT" "phase-title" "wf fixture: phase-mismatch.js reports phase-title"
}

t_wf_fixture_date_now() {
	run_cmd bash "$WF_LINT" "$WF_FIXTURES/date-now.js"
	assert_rc 1 "wf fixture: date-now.js fails lint"
	assert_contains "$OUT" "no-nondeterminism" "wf fixture: date-now.js reports no-nondeterminism"
}

t_wf_fixture_typescript() {
	run_cmd bash "$WF_LINT" "$WF_FIXTURES/typescript.js"
	assert_rc 1 "wf fixture: typescript.js fails lint"
	assert_contains "$OUT" "typescript" "wf fixture: typescript.js reports typescript"
}

t_wf_fixture_agent_no_model() {
	run_cmd bash "$WF_LINT" "$WF_FIXTURES/agent-no-model.js"
	assert_rc 1 "wf fixture: agent-no-model.js fails lint"
	assert_contains "$OUT" "agent-model" "wf fixture: agent-no-model.js reports agent-model"
}

t_wf_fixture_missing_description() {
	run_cmd bash "$WF_LINT" "$WF_FIXTURES/missing-description.js"
	assert_rc 1 "wf fixture: missing-description.js fails lint"
	assert_contains "$OUT" "meta-description" "wf fixture: missing-description.js reports meta-description"
}

t_wf_fixture_syntax_error() {
	run_cmd bash "$WF_LINT" "$WF_FIXTURES/syntax-error.js"
	assert_rc 1 "wf fixture: syntax-error.js fails lint"
	assert_contains "$OUT" "parse" "wf fixture: syntax-error.js reports parse"
}

# Comment-bypass regression coverage: a decoy value/brace placed inside a
# comment must never satisfy (or evade) a text-matching rule while the real,
# non-compliant code ships. Each fixture is the compliant twin of an existing
# rule fixture above, plus one commented-out decoy engineered to fool a
# comment-unaware substring/regex match.

t_wf_fixture_comment_bypass_agent_model() {
	run_cmd bash "$WF_LINT" "$WF_FIXTURES/comment-bypass-agent-model.js"
	assert_rc 1 "wf fixture: comment-bypass-agent-model.js fails lint"
	assert_contains "$OUT" "agent-model" "wf fixture: comment-bypass-agent-model.js reports agent-model"
}

t_wf_fixture_comment_bypass_name() {
	run_cmd bash "$WF_LINT" "$WF_FIXTURES/comment-bypass-name.js"
	assert_rc 1 "wf fixture: comment-bypass-name.js fails lint"
	assert_contains "$OUT" "meta-name" "wf fixture: comment-bypass-name.js reports meta-name"
}

t_wf_fixture_comment_bypass_phase_title() {
	run_cmd bash "$WF_LINT" "$WF_FIXTURES/comment-bypass-phase-title.js"
	assert_rc 1 "wf fixture: comment-bypass-phase-title.js fails lint"
	assert_contains "$OUT" "phase-title" "wf fixture: comment-bypass-phase-title.js reports phase-title"
}

t_wf_fixture_comment_bypass_description() {
	run_cmd bash "$WF_LINT" "$WF_FIXTURES/comment-bypass-description.js"
	assert_rc 1 "wf fixture: comment-bypass-description.js fails lint"
	assert_contains "$OUT" "meta-description" "wf fixture: comment-bypass-description.js reports meta-description"
}

# Nested-decoy-key regression coverage: rules 1 and 7 must scan only the
# literal's OWN top-level (depth-1) keys, never a same-named key buried
# inside a nested object/array (a schema property, a phases[].detail field).

t_wf_fixture_nested_key_agent_model() {
	run_cmd bash "$WF_LINT" "$WF_FIXTURES/nested-key-agent-model.js"
	assert_rc 1 "wf fixture: nested-key-agent-model.js fails lint"
	assert_contains "$OUT" "agent-model" "wf fixture: nested-key-agent-model.js reports agent-model"
}

t_wf_fixture_nested_key_description() {
	run_cmd bash "$WF_LINT" "$WF_FIXTURES/nested-key-description.js"
	assert_rc 1 "wf fixture: nested-key-description.js fails lint"
	assert_contains "$OUT" "meta-description" "wf fixture: nested-key-description.js reports meta-description"
}

# Backtick phase-title regression coverage: rule 4 must not silently skip a
# phase() call whose title is written as a template literal.

t_wf_fixture_phase_backtick_title() {
	run_cmd bash "$WF_LINT" "$WF_FIXTURES/phase-backtick-title.js"
	assert_rc 1 "wf fixture: phase-backtick-title.js fails lint"
	assert_contains "$OUT" "phase-title" "wf fixture: phase-backtick-title.js reports phase-title"
}

# C13 wave-scheduling regression coverage: build-slices.js must actually use
# parallel() to run independent slices concurrently, and workflow-lint (rule
# 9) must catch a build-slices.js that doesn't.

t_wf_fixture_no_parallelism() {
	run_cmd bash "$WF_LINT" "$WF_FIXTURES/build-slices.js"
	assert_rc 1 "wf fixture: build-slices.js (no parallel call) fails lint"
	assert_contains "$OUT" "no-parallelism" "wf fixture: build-slices.js reports no-parallelism"
}

t_wf_build_slices_uses_parallel_for_waves() {
	# The shipped build-slices.js must contain more than the two known
	# per-slice adversary-pair parallel() call sites — it must also use
	# parallel() to run independent slices' full chains concurrently in waves.
	run_cmd grep -c 'parallel(' "$WF_DIR/build-slices.js"
	local count verdict
	count="$OUT"
	verdict="no"
	if [ "$count" -gt 2 ]; then verdict="yes"; fi
	assert_eq "$verdict" "yes" "wf: build-slices.js uses parallel() for wave scheduling beyond the two adversary-pair sites (found $count call sites)"
}

t_wf_build_slices_returns_waves() {
	run_cmd grep -c 'waves:' "$WF_DIR/build-slices.js"
	local count verdict
	count="$OUT"
	verdict="no"
	if [ "$count" -gt 0 ]; then verdict="yes"; fi
	assert_eq "$verdict" "yes" "wf: build-slices.js returns { waves: string[][] } per K-B"
}

# Spec 004 stage 0: the wave schedule is flow-lint's, not the workflow's. One
# haiku general-purpose agent runs `flow-lint --json` on the TASKS.md and the
# workflow uses the returned waves array verbatim — it never re-derives file
# overlap, because flow-lint is the only parser of the K-B grammar and the only
# thing that has proved [P] disjointness.

t_wf_build_slices_stage0_runs_flow_lint_json() {
	run_cmd grep -c "flow-lint ' + tasks + ' --json" "$WF_DIR/build-slices.js"
	assert_rc 0 "wf: build-slices.js stage 0 runs flow-lint --json on the TASKS.md"
	assert_eq "$OUT" "1" "wf: exactly one flow-lint --json stage-0 call"
}

t_wf_build_slices_stage0_absent_check() {
	run_cmd grep -c 'lintWaves === undefined' "$WF_DIR/build-slices.js"
	assert_rc 0 "wf: build-slices.js runs stage 0 only when args.waves is absent"
	assert_eq "$OUT" "1" "wf: exactly one stage-0 absence check"
}

t_wf_build_slices_no_local_overlap_computation() {
	# flow-lint owns [P] disjointness; a second implementation here could
	# disagree with the linter that already gated the plan.
	run_cmd grep -c 'filesOverlap\|computeAllWaves' "$WF_DIR/build-slices.js"
	assert_eq "$OUT" "0" "wf: build-slices.js does not re-implement wave/overlap computation"
}

t_wf_build_slices_stage0_model_haiku() {
	run_cmd grep -c "model: 'haiku'" "$WF_DIR/build-slices.js"
	local count
	count="$OUT"
	assert_rc 0 "wf: build-slices.js contains model:'haiku' agent calls"
	if [ "$count" -lt 1 ]; then
		assert_eq "found" "at least one model:'haiku' call" "wf: at least one model:'haiku' call present"
	fi
}

t_wf_build_slices_stage0_agent_type_general_purpose() {
	run_cmd grep -c "agentType: 'general-purpose'" "$WF_DIR/build-slices.js"
	assert_rc 0 "wf: build-slices.js contains an agentType:'general-purpose' stage-0 agent"
	assert_eq "$OUT" "1" "wf: exactly one agentType:'general-purpose' call (stage 0)"
}

t_wf_build_slices_brief_uses_task_brief() {
	run_cmd grep -c "/task-brief ' + tasks + ' ' + id" "$WF_DIR/build-slices.js"
	assert_rc 0 "wf: build-slices.js briefs each task with scripts/task-brief"
	assert_eq "$OUT" "1" "wf: exactly one task-brief call site"
	run_cmd grep -c 'slice-brief' "$WF_DIR/build-slices.js"
	assert_eq "$OUT" "0" "wf: build-slices.js no longer calls the deleted slice-brief"
}

t_wf_build_slices_passes_design_to_task_brief() {
	run_cmd grep -c "args.design" "$WF_DIR/build-slices.js"
	local count verdict
	count="$OUT"
	verdict="no"
	if [ "$count" -gt 0 ]; then verdict="yes"; fi
	assert_eq "$verdict" "yes" "wf: task-brief gets --design when the caller passes one"
}

t_wf_build_slices_stage0_schema_waves() {
	run_cmd grep -c 'SCHEDULE_SCHEMA' "$WF_DIR/build-slices.js"
	local count verdict
	count="$OUT"
	verdict="no"
	if [ "$count" -gt 0 ]; then verdict="yes"; fi
	assert_eq "$verdict" "yes" "wf: a schema constant is used for the stage-0 schedule return"
	run_cmd grep -c "required: \['waves'\]" "$WF_DIR/build-slices.js"
	count="$OUT"
	verdict="no"
	if [ "$count" -gt 0 ]; then verdict="yes"; fi
	assert_eq "$verdict" "yes" "wf: stage-0 schema requires waves"
}

t_wf_build_slices_halts_on_lint_error() {
	run_cmd grep -c 'scheduleRes.ok === false' "$WF_DIR/build-slices.js"
	local count verdict
	count="$OUT"
	verdict="no"
	if [ "$count" -gt 0 ]; then verdict="yes"; fi
	assert_eq "$verdict" "yes" "wf: a flow-lint ERROR stops the run before any developer agent"
	run_cmd grep -c 'lintOk: false' "$WF_DIR/build-slices.js"
	count="$OUT"
	verdict="no"
	if [ "$count" -gt 0 ]; then verdict="yes"; fi
	assert_eq "$verdict" "yes" "wf: the halted run reports lintOk:false"
}

t_wf_build_slices_log_format_string() {
	run_cmd grep -c "'wave ' + (i + 1) + ': ' + wave.join" "$WF_DIR/build-slices.js"
	local count verdict
	count="$OUT"
	verdict="no"
	if [ "$count" -gt 0 ]; then verdict="yes"; fi
	assert_eq "$verdict" "yes" "wf: wave log format string present"
}

t_wf_build_slices_logs_waves_before_starting() {
	# The selectWaves()+log() block (before the exec loop) must appear before
	# the first parallel(ready.map(...)) execution call in the file.
	run_cmd grep -n 'const waves = selectWaves(' "$WF_DIR/build-slices.js"
	local log_line exec_line
	log_line=$(printf '%s\n' "$OUT" | head -1 | cut -d: -f1)
	run_cmd grep -n 'for (let w = 0; w < waves.length; w++)' "$WF_DIR/build-slices.js"
	exec_line=$(printf '%s\n' "$OUT" | head -1 | cut -d: -f1)
	local before="no"
	if [ "$log_line" -lt "$exec_line" ]; then before="yes"; fi
	assert_eq "$before" "yes" "wf: waves are selected (and logged) before the execution loop starts"
}

t_wf_build_slices_returns_discovered() {
	run_cmd grep -c 'discovered:' "$WF_DIR/build-slices.js"
	local count verdict
	count="$OUT"
	verdict="no"
	if [ "$count" -gt 0 ]; then verdict="yes"; fi
	assert_eq "$verdict" "yes" "wf: build-slices.js return includes discovered"
	run_cmd grep -c 'const discovered = \[\]' "$WF_DIR/build-slices.js"
	count="$OUT"
	verdict="no"
	if [ "$count" -gt 0 ]; then verdict="yes"; fi
	assert_eq "$verdict" "yes" "wf: discovered starts as an array populated from task results"
}

t_wf_build_slices_still_lints_ok() {
	run_cmd bash "$WF_LINT" "$WF_DIR/build-slices.js"
	assert_rc 0 "wf: build-slices.js with stage 0 still lints clean"
	assert_contains "$OUT" "OK " "wf: build-slices.js with stage 0 prints OK"
}

# Behavioral regression coverage: the one piece of scheduling logic this
# workflow still owns is selectWaves() — narrowing flow-lint's wave list to the
# ids the caller asked for. It must preserve the linter's wave ORDER (wave N+1
# never starts before wave N reports), drop waves that empty out after the
# filter instead of scheduling an empty parallel() batch, and compare ids as
# strings (TASKS.md ids are T001/CHK011, never numbers). Extracted verbatim
# from the shipped file (brace-matching, no rewrite of the source) and run
# under node, so this is exercised rather than merely grepped for.
t_wf_build_slices_select_waves_behavior() {
	local d script
	d=$(tmp_dir)
	script="$d/select-waves-check.js"
	cat >"$script" <<'NODEEOF'
const fs = require('fs')
const src = fs.readFileSync(process.argv[2], 'utf8')

function extractFn(name) {
  const marker = 'function ' + name + '('
  const start = src.indexOf(marker)
  if (start === -1) { throw new Error('extractFn: not found ' + name) }
  const openBrace = src.indexOf('{', start)
  let depth = 0
  let j = openBrace
  for (; j < src.length; j++) {
    if (src[j] === '{') { depth++ }
    else if (src[j] === '}') { depth--; if (depth === 0) { j++; break } }
  }
  return src.slice(start, j)
}

eval(extractFn('selectWaves'))

// No ids requested -> the linter's schedule passes through untouched.
const all = selectWaves([['T001'], ['T002', 'T003']], undefined)

// A subset -> wave order is preserved and the wave that empties out is
// dropped, never scheduled as an empty parallel() batch.
const subset = selectWaves([['T001'], ['T002', 'T003'], ['T004']], ['T003', 'T004'])

// Ids arriving as numbers (a caller that JSON-round-tripped them) still match
// the linter's string ids instead of silently scheduling nothing.
const coerced = selectWaves([['1'], ['2']], [2])

console.log(JSON.stringify({ all: all, subset: subset, coerced: coerced }))
NODEEOF
	run_cmd node "$script" "$WF_DIR/build-slices.js"
	assert_rc 0 "wf: selectWaves behavioral extraction runs cleanly"
	assert_contains "$OUT" '"all":[["T001"],["T002","T003"]]' "wf: no requested ids passes flow-lint's schedule through verbatim"
	assert_contains "$OUT" '"subset":[["T003"],["T004"]]' "wf: a subset keeps wave order and drops the wave that emptied out"
	assert_contains "$OUT" '"coerced":[["2"]]' "wf: numeric ids are compared as strings against the linter's ids"
}

# ---------------------------------------------------------------------------
# B2/B3 — review lenses fail closed. wf-run.js (fixtures/) evaluates a
# workflow's body under node, an async function with agent/parallel/
# pipeline/log/phase/args/budget bound to a stub CommonJS module's exports of
# the same names. Each test below writes its own stub into a fresh tmp dir.
# t_wf_review_diff_failed_lens_* / t_wf_build_slices_failed_relook_* prefix.
# ---------------------------------------------------------------------------

# _wf_parallel_stub — the real runtime's parallel(thunks): a thunk that
# throws or resolves null yields null at that index, and parallel() itself
# never rejects. Every stub module below starts from this verbatim.
_wf_parallel_stub() {
	cat <<'EOF'
async function parallel(thunks) {
  return Promise.all(thunks.map(function (thunk) {
    return Promise.resolve().then(thunk).then(
      function (v) { return v === undefined ? null : v },
      function () { return null }
    )
  }))
}
EOF
}

t_wf_review_diff_failed_lens_names_and_incomplete() {
	local d stub
	d=$(tmp_dir)
	stub="$d/stub.js"
	_wf_parallel_stub >"$stub"
	cat >>"$stub" <<'EOF'
async function agent(prompt, opts) {
  if (opts.label === 'package') { return { diffPath: '/tmp/fake.diff' } }
  if (opts.label === 'lens:security') { return null }
  return { findings: [] }
}
function log(msg) { process.stderr.write('failed: ' + msg + '\n') }
function phase() {}
const args = { base: 'main', lenses: ['correctness', 'security'], scriptsDir: '/tmp/scripts' }
const budget = { total: null, spent: function () { return 0 }, remaining: function () { return Infinity } }
module.exports = { agent: agent, parallel: parallel, pipeline: async function () { return [] }, log: log, phase: phase, args: args, budget: budget }
EOF
	run_cmd node "$WF_RUN" "$WF_DIR/review-diff.js" "$stub"
	assert_rc 0 "wf: review-diff.js runs under wf-run.js with one dead lens"
	assert_contains "$OUT" '"failedLenses":["security"]' "wf: review-diff.js names the dead lens in failedLenses"
	assert_contains "$OUT" '"incomplete":true' "wf: review-diff.js sets incomplete true when a lens died"
	assert_contains "$ERR" 'security' "wf: review-diff.js logs the dead lens name"
}

t_wf_review_diff_failed_lens_preserves_lens_order() {
	local d stub
	d=$(tmp_dir)
	stub="$d/stub.js"
	_wf_parallel_stub >"$stub"
	cat >>"$stub" <<'EOF'
async function agent(prompt, opts) {
  if (opts.label === 'package') { return { diffPath: '/tmp/fake.diff' } }
  if (opts.label === 'lens:a') { throw new Error('lens a crashed') }
  if (opts.label === 'lens:c') { return null }
  return { findings: [] }
}
function log() {}
function phase() {}
const args = { base: 'main', lenses: ['a', 'b', 'c'], scriptsDir: '/tmp/scripts' }
const budget = { total: null, spent: function () { return 0 }, remaining: function () { return Infinity } }
module.exports = { agent: agent, parallel: parallel, pipeline: async function () { return [] }, log: log, phase: phase, args: args, budget: budget }
EOF
	run_cmd node "$WF_RUN" "$WF_DIR/review-diff.js" "$stub"
	assert_rc 0 "wf: review-diff.js runs with a thrown lens and a null lens"
	assert_contains "$OUT" '"failedLenses":["a","c"]' "wf: failedLenses keeps lens order (not b, which survived)"
}

t_wf_review_diff_failed_lens_no_diff_path_still_incomplete() {
	local d stub
	d=$(tmp_dir)
	stub="$d/stub.js"
	_wf_parallel_stub >"$stub"
	cat >>"$stub" <<'EOF'
async function agent(prompt, opts) {
  if (opts.label === 'package') { return null }
  return { findings: [] }
}
function log() {}
function phase() {}
const args = { base: 'main', lenses: ['correctness'], scriptsDir: '/tmp/scripts' }
const budget = { total: null, spent: function () { return 0 }, remaining: function () { return Infinity } }
module.exports = { agent: agent, parallel: parallel, pipeline: async function () { return [] }, log: log, phase: phase, args: args, budget: budget }
EOF
	run_cmd node "$WF_RUN" "$WF_DIR/review-diff.js" "$stub"
	assert_rc 0 "wf: review-diff.js runs when review-package returns no diff path"
	assert_contains "$OUT" '"diffPath":null' "wf: no diff path leaves diffPath null"
	assert_contains "$OUT" '"failedLenses":[]' "wf: no diff path means no lens ran, failedLenses stays empty"
	assert_contains "$OUT" '"incomplete":true' "wf: incomplete is true on this return path too"
}

t_wf_build_slices_failed_relook_all_null_keeps_blocking_finding() {
	local d stub
	d=$(tmp_dir)
	stub="$d/stub.js"
	_wf_parallel_stub >"$stub"
	cat >>"$stub" <<'EOF'
async function agent(prompt, opts) {
  const label = opts.label
  if (label === 'brief:T1') { return { briefPath: '/tmp/T1-brief.md' } }
  if (label === 'implement:T1') {
    return { id: 'T1', redExit: 1, greenExit: 0, refactorPassCount: 3, commits: ['a'], files: ['x.js'], notes: '' }
  }
  if (label === 'review:T1') { return { diffPath: '/tmp/T1.diff' } }
  if (label === 'adv:correctness:T1') {
    return { verdict: 'reject', checked: 'full', findings: [{ predicate: 'bug', severity: 'fatal', scenario: 's', receipt: 'x.js:1' }] }
  }
  if (label === 'adv:gaming:T1') { return { verdict: 'ok', checked: 'full', findings: [] } }
  if (label === 'adv:slop:T1') { return { verdict: 'ok', checked: 'full', findings: [] } }
  if (label === 'fix:T1:r1') {
    return { id: 'T1', redExit: 1, greenExit: 0, refactorPassCount: 3, commits: ['a', 'b'], files: ['x.js'], notes: '' }
  }
  if (label === 'review:T1:r1') { return { diffPath: '/tmp/T1-r1.diff' } }
  if (label === 'adv:correctness:T1:r1') { return null }
  if (label === 'adv:gaming:T1:r1') { return null }
  if (label === 'adv:slop:T1:r1') { return null }
  if (label === 'fix:T1:r2') { return null }
  throw new Error('unexpected label ' + label)
}
function log() {}
function phase() {}
const args = { tasks: '/tmp/TASKS.md', base: 'main', testCmd: 'true', waves: [['T1']], scriptsDir: '/tmp/scripts', reviewDir: '/tmp/review' }
const budget = { total: null, spent: function () { return 0 }, remaining: function () { return Infinity } }
module.exports = { agent: agent, parallel: parallel, pipeline: async function () { return [] }, log: log, phase: phase, args: args, budget: budget }
EOF
	run_cmd node "$WF_RUN" "$WF_DIR/build-slices.js" "$stub"
	assert_rc 0 "wf: build-slices.js runs when every re-look lens dies in round 1"
	assert_contains "$OUT" '"failedLenses":["correctness:r1","gaming:r1","slop:r1"]' "wf: the dead re-look lenses are recorded tagged :r1"
	assert_contains "$OUT" '"predicate":"bug"' "wf: the original blocking finding is still parked, never cleared"
	assert_contains "$OUT" '"clean":false' "wf: clean is false"
	assert_contains "$OUT" '"incomplete":["T1"]' "wf: incomplete names the task"
}

t_wf_build_slices_failed_relook_unions_survivor_findings() {
	local d stub
	d=$(tmp_dir)
	stub="$d/stub.js"
	_wf_parallel_stub >"$stub"
	cat >>"$stub" <<'EOF'
async function agent(prompt, opts) {
  const label = opts.label
  if (label === 'brief:T1') { return { briefPath: '/tmp/T1-brief.md' } }
  if (label === 'implement:T1') {
    return { id: 'T1', redExit: 1, greenExit: 0, refactorPassCount: 3, commits: ['a'], files: ['x.js'], notes: '' }
  }
  if (label === 'review:T1') { return { diffPath: '/tmp/T1.diff' } }
  if (label === 'adv:correctness:T1') {
    return { verdict: 'reject', checked: 'full', findings: [{ predicate: 'findingA', severity: 'fatal', scenario: 's', receipt: 'x.js:1' }] }
  }
  if (label === 'adv:gaming:T1') { return { verdict: 'ok', checked: 'full', findings: [] } }
  if (label === 'adv:slop:T1') { return { verdict: 'ok', checked: 'full', findings: [] } }
  if (label === 'fix:T1:r1') {
    return { id: 'T1', redExit: 1, greenExit: 0, refactorPassCount: 3, commits: ['a', 'b'], files: ['x.js'], notes: '' }
  }
  if (label === 'review:T1:r1') { return { diffPath: '/tmp/T1-r1.diff' } }
  if (label === 'adv:correctness:T1:r1') { return null }
  if (label === 'adv:gaming:T1:r1') {
    return { verdict: 'reject', checked: 'full', findings: [{ predicate: 'findingB', severity: 'significant', scenario: 's2', receipt: 'y.js:2' }] }
  }
  if (label === 'adv:slop:T1:r1') { return { verdict: 'ok', checked: 'full', findings: [] } }
  if (label === 'fix:T1:r2') { return null }
  throw new Error('unexpected label ' + label)
}
function log() {}
function phase() {}
const args = { tasks: '/tmp/TASKS.md', base: 'main', testCmd: 'true', waves: [['T1']], scriptsDir: '/tmp/scripts', reviewDir: '/tmp/review' }
const budget = { total: null, spent: function () { return 0 }, remaining: function () { return Infinity } }
module.exports = { agent: agent, parallel: parallel, pipeline: async function () { return [] }, log: log, phase: phase, args: args, budget: budget }
EOF
	run_cmd node "$WF_RUN" "$WF_DIR/build-slices.js" "$stub"
	assert_rc 0 "wf: build-slices.js runs when only one of three re-look lenses dies"
	local out="$OUT" parked_count
	assert_contains "$out" '"failedLenses":["correctness:r1"]' "wf: only the dead lens is recorded, tagged :r1"
	assert_contains "$out" '"predicate":"findingA"' "wf: the previous round's blocking finding is kept"
	assert_contains "$out" '"predicate":"findingB"' "wf: the surviving lens's new finding is also kept"
	parked_count=$(printf '%s' "$out" | grep -o '"ruling":"parked"' | wc -l | tr -d ' ')
	assert_eq "$parked_count" "2" "wf: both findings are parked, never silently cleared"
}

t_wf_build_slices_failed_relook_first_review_lens_has_no_round_suffix() {
	local d stub
	d=$(tmp_dir)
	stub="$d/stub.js"
	_wf_parallel_stub >"$stub"
	cat >>"$stub" <<'EOF'
async function agent(prompt, opts) {
  const label = opts.label
  if (label === 'brief:T1') { return { briefPath: '/tmp/T1-brief.md' } }
  if (label === 'implement:T1') {
    return { id: 'T1', redExit: 1, greenExit: 0, refactorPassCount: 3, commits: ['a'], files: ['x.js'], notes: '' }
  }
  if (label === 'review:T1') { return { diffPath: '/tmp/T1.diff' } }
  if (label === 'adv:correctness:T1') { return null }
  if (label === 'adv:gaming:T1') {
    return { verdict: 'reject', checked: 'full', findings: [{ predicate: 'findingA', severity: 'fatal', scenario: 's', receipt: 'x.js:1' }] }
  }
  if (label === 'adv:slop:T1') { return { verdict: 'ok', checked: 'full', findings: [] } }
  if (label === 'fix:T1:r1') {
    return { id: 'T1', redExit: 1, greenExit: 0, refactorPassCount: 3, commits: ['a', 'b'], files: ['x.js'], notes: '' }
  }
  if (label === 'review:T1:r1') { return { diffPath: '/tmp/T1-r1.diff' } }
  if (label === 'adv:correctness:T1:r1') { return { verdict: 'ok', checked: 'full', findings: [] } }
  if (label === 'adv:gaming:T1:r1') { return { verdict: 'ok', checked: 'full', findings: [] } }
  if (label === 'adv:slop:T1:r1') { return { verdict: 'ok', checked: 'full', findings: [] } }
  throw new Error('unexpected label ' + label)
}
function log() {}
function phase() {}
const args = { tasks: '/tmp/TASKS.md', base: 'main', testCmd: 'true', waves: [['T1']], scriptsDir: '/tmp/scripts', reviewDir: '/tmp/review' }
const budget = { total: null, spent: function () { return 0 }, remaining: function () { return Infinity } }
module.exports = { agent: agent, parallel: parallel, pipeline: async function () { return [] }, log: log, phase: phase, args: args, budget: budget }
EOF
	run_cmd node "$WF_RUN" "$WF_DIR/build-slices.js" "$stub"
	assert_rc 0 "wf: build-slices.js runs when a first-review lens dies but the fix round clears the rest"
	assert_contains "$OUT" '"failedLenses":["correctness"]' "wf: a first-review failure is recorded with no :rN suffix"
	assert_contains "$OUT" '"parked":[]' "wf: nothing is parked once the surviving finding is fixed"
	assert_contains "$OUT" '"clean":false' "wf: clean stays false: the task is incomplete even though nothing parked"
	assert_contains "$OUT" '"incomplete":["T1"]' "wf: incomplete names the task independent of parked"
}
