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
	assert_contains "$OUT" '"dismissed":[]' "wf: no diff path still returns an empty dismissed list"
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

# skills/next/SKILL.md promises "at most 4 in parallel". A wave of 6 ready
# tasks must never hand parallel() more than 4 thunks in flight at once. The
# stub's agent() (the brief step, which runTask calls first) counts how many
# calls are concurrently in flight and logs each count to stderr, then
# returns null so runTask bails out before any further agent()/parallel()
# call (brief failed -> no nested lens parallel() to confuse the count).
t_wf_build_slices_wave_chunking_max_4() {
	local d stub
	d=$(tmp_dir)
	stub="$d/stub.js"
	_wf_parallel_stub >"$stub"
	cat >>"$stub" <<'EOF'
function log() {}
function phase() {}
let inFlight = 0
async function agent(prompt, opts) {
  inFlight++
  process.stderr.write('inflight=' + inFlight + '\n')
  await new Promise(function (resolve) { setTimeout(resolve, 20) })
  inFlight--
  return null
}
const args = { tasks: '/tmp/TASKS.md', base: 'main', testCmd: 'true', waves: [['T1', 'T2', 'T3', 'T4', 'T5', 'T6']], scriptsDir: '/tmp/scripts', reviewDir: '/tmp/review' }
const budget = { total: null, spent: function () { return 0 }, remaining: function () { return Infinity } }
module.exports = { agent: agent, parallel: parallel, pipeline: async function () { return [] }, log: log, phase: phase, args: args, budget: budget }
EOF
	run_cmd node "$WF_RUN" "$WF_DIR/build-slices.js" "$stub"
	assert_rc 0 "wf: build-slices.js runs a 6-task wave under wf-run.js"
	local maxflight verdict
	maxflight=$(printf '%s' "$ERR" | grep -o 'inflight=[0-9]*' | sed 's/inflight=//' | sort -n | tail -1)
	verdict="no"
	if [ -n "$maxflight" ] && [ "$maxflight" -le 4 ]; then verdict="yes"; fi
	assert_eq "$verdict" "yes" "wf: a 6-task wave never has more than 4 agents in flight (max seen: $maxflight)"
	assert_eq "$maxflight" "4" "wf: the wave actually dispatches a full chunk of 4 concurrently (not serialized)"
}

t_wf_review_diff_returns_dismissed_with_reasons() {
	local d stub
	d=$(tmp_dir)
	stub="$d/stub.js"
	_wf_parallel_stub >"$stub"
	cat >>"$stub" <<'EOS'
async function agent(prompt, opts) {
  if (opts.label === 'package') { return { diffPath: '/tmp/fake.diff' } }
  if (opts.label === 'lens:correctness') {
    return { findings: [
      { predicate: 'keepme', severity: 'high', file: 'a.js', line: 1, scenario: 's', receipt: 'r' },
      { predicate: 'dropme', severity: 'low', file: 'b.js', line: 2, scenario: 's', receipt: 'r' }
    ] }
  }
  if (opts.label === 'score:a.js:1:keepme') { return { score: 95, why: 'verified' } }
  if (opts.label === 'score:b.js:2:dropme') { return { score: 20, why: 'style only' } }
  return null
}
function log() {}
function phase() {}
const args = { base: 'main', lenses: ['correctness'], scriptsDir: '/tmp/scripts' }
const budget = { total: null, spent: function () { return 0 }, remaining: function () { return Infinity } }
module.exports = { agent: agent, parallel: parallel, pipeline: async function () { return [] }, log: log, phase: phase, args: args, budget: budget }
EOS
	run_cmd node "$WF_RUN" "$WF_DIR/review-diff.js" "$stub"
	assert_rc 0 "wf: review-diff.js runs with one kept and one dismissed finding"
	assert_contains "$OUT" '"dismissed":[' "wf: review-diff.js returns a dismissed list"
	assert_contains "$OUT" '"predicate":"dropme"' "wf: the below-threshold finding is in dismissed"
	assert_contains "$OUT" '"reason":"style only"' "wf: dismissed carries the scorer's reason"
	assert_contains "$OUT" '"dropped":1' "wf: dropped count is still returned"
}

# Deliberate behaviour change (M04): structure joins review-diff's default lenses,
# but its findings are advisory and never enter the blocking `verified` list.
# The old pin (default list excludes structure) is flipped, not weakened.
t_wf_review_diff_default_lenses_include_structure() {
	local line
	line=$(grep "^const lenses = args.lenses" "$WF_DIR/review-diff.js")
	assert_contains "$line" "['correctness', 'security', 'gaming', 'cross-file', 'slop', 'structure']" "wf: review-diff default lens list ends with structure"
}

t_wf_build_slices_per_task_lenses_exclude_structure() {
	local src
	src=$(cat "$WF_DIR/build-slices.js")
	assert_not_contains "$src" "structure" "wf: build-slices never dispatches structure per task"
	assert_contains "$src" "'correctness'" "wf: build-slices still names correctness"
	assert_contains "$src" "'gaming'" "wf: build-slices still names gaming"
	assert_contains "$src" "'slop'" "wf: build-slices still names slop"
}

# _wf_json_field <json> <js-expr over j> prints the expression's value.
_wf_json_field() {
	printf '%s' "$1" | node -e 'let s="";process.stdin.on("data",function(d){s+=d}).on("end",function(){const j=JSON.parse(s);process.stdout.write(String(eval(process.argv[1])))})' "$2"
}

t_wf_review_diff_structure_finding_is_advisory_not_blocking() {
	local d stub
	d=$(tmp_dir)
	stub="$d/stub.js"
	_wf_parallel_stub >"$stub"
	cat >>"$stub" <<'EOS'
async function agent(prompt, opts) {
  if (opts.label === 'package') { return { diffPath: '/tmp/fake.diff' } }
  if (opts.label === 'lens:structure') {
    return { findings: [
      { predicate: 'movedcomplexity', severity: 'high', file: 'a.js', line: 1, scenario: 's', receipt: 'r' }
    ] }
  }
  if (opts.label === 'lens:correctness') {
    return { findings: [
      { predicate: 'realbug', severity: 'high', file: 'b.js', line: 2, scenario: 's', receipt: 'r' }
    ] }
  }
  if (opts.label === 'score:a.js:1:movedcomplexity') { return { score: 95, why: 'verified' } }
  if (opts.label === 'score:b.js:2:realbug') { return { score: 90, why: 'verified' } }
  return null
}
function log() {}
function phase() {}
const args = { base: 'main', lenses: ['correctness', 'structure'], scriptsDir: '/tmp/scripts' }
const budget = { total: null, spent: function () { return 0 }, remaining: function () { return Infinity } }
module.exports = { agent: agent, parallel: parallel, pipeline: async function () { return [] }, log: log, phase: phase, args: args, budget: budget }
EOS
	run_cmd node "$WF_RUN" "$WF_DIR/review-diff.js" "$stub"
	assert_rc 0 "wf: review-diff.js runs with correctness and structure"
	assert_eq "$(_wf_json_field "$OUT" 'j.verified.map(f=>f.predicate).join(",")')" "realbug" "wf: only the non-structure finding is in the blocking list"
	assert_eq "$(_wf_json_field "$OUT" 'j.advisory.map(f=>f.predicate+":"+f.score).join(",")')" "movedcomplexity:95" "wf: the structure finding scored 95 is advisory"
	assert_eq "$(_wf_json_field "$OUT" 'j.dismissed.length')" "0" "wf: an advisory finding is not reported as dismissed"
	assert_contains "$OUT" '"failedLenses":[]' "wf: structure lens did not fail"
}

t_wf_review_diff_structure_alone_never_blocks() {
	local d stub
	d=$(tmp_dir)
	stub="$d/stub.js"
	_wf_parallel_stub >"$stub"
	cat >>"$stub" <<'EOS'
async function agent(prompt, opts) {
  if (opts.label === 'package') { return { diffPath: '/tmp/fake.diff' } }
  if (opts.label === 'lens:structure') {
    return { findings: [
      { predicate: 'movedcomplexity', severity: 'high', file: 'a.js', line: 1, scenario: 's', receipt: 'r' }
    ] }
  }
  if (opts.label === 'score:a.js:1:movedcomplexity') { return { score: 90, why: 'verified' } }
  return null
}
function log() {}
function phase() {}
const args = { base: 'main', lenses: ['structure'], scriptsDir: '/tmp/scripts' }
const budget = { total: null, spent: function () { return 0 }, remaining: function () { return Infinity } }
module.exports = { agent: agent, parallel: parallel, pipeline: async function () { return [] }, log: log, phase: phase, args: args, budget: budget }
EOS
	run_cmd node "$WF_RUN" "$WF_DIR/review-diff.js" "$stub"
	assert_rc 0 "wf: review-diff.js runs with the structure lens alone"
	assert_eq "$(_wf_json_field "$OUT" 'j.verified.length')" "0" "wf: a structure-only review has an empty blocking list"
	assert_eq "$(_wf_json_field "$OUT" 'j.advisory[0].lens')" "structure" "wf: the structure finding is kept in advisory with its lens"
}

t_wf_review_diff_advisory_empty_when_no_structure_findings() {
	local d stub
	d=$(tmp_dir)
	stub="$d/stub.js"
	_wf_parallel_stub >"$stub"
	cat >>"$stub" <<'EOS'
async function agent(prompt, opts) {
  if (opts.label === 'package') { return { diffPath: '/tmp/fake.diff' } }
  return { findings: [] }
}
function log() {}
function phase() {}
const args = { base: 'main', scriptsDir: '/tmp/scripts' }
const budget = { total: null, spent: function () { return 0 }, remaining: function () { return Infinity } }
module.exports = { agent: agent, parallel: parallel, pipeline: async function () { return [] }, log: log, phase: phase, args: args, budget: budget }
EOS
	run_cmd node "$WF_RUN" "$WF_DIR/review-diff.js" "$stub"
	assert_rc 0 "wf: review-diff.js runs with the default lenses"
	assert_contains "$OUT" '"advisory":[]' "wf: advisory is an empty list when structure finds nothing"
	assert_contains "$OUT" '"failedLenses":[]' "wf: all six default lenses ran"
}

t_wf_review_diff_unscored_findings_are_dismissed() {
	local d stub
	d=$(tmp_dir)
	stub="$d/stub.js"
	_wf_parallel_stub >"$stub"
	cat >>"$stub" <<'EOS'
async function agent(prompt, opts) {
  if (opts.label === 'package') { return { diffPath: '/tmp/fake.diff' } }
  if (opts.label === 'lens:correctness') {
    return { findings: [
      { predicate: 'scorerdied', severity: 'high', file: 'a.js', line: 1, scenario: 's', receipt: 'r' },
      { predicate: 'scorerthrew', severity: 'high', file: 'b.js', line: 2, scenario: 's', receipt: 'r' },
      { predicate: 'keepme', severity: 'high', file: 'c.js', line: 3, scenario: 's', receipt: 'r' }
    ] }
  }
  if (opts.label === 'score:a.js:1:scorerdied') { return null }
  if (opts.label === 'score:b.js:2:scorerthrew') { throw new Error('crash') }
  if (opts.label === 'score:c.js:3:keepme') { return { score: 95, why: 'verified' } }
  return null
}
function log() {}
function phase() {}
const args = { base: 'main', lenses: ['correctness'], scriptsDir: '/tmp/scripts' }
const budget = { total: null, spent: function () { return 0 }, remaining: function () { return Infinity } }
module.exports = { agent: agent, parallel: parallel, pipeline: async function () { return [] }, log: log, phase: phase, args: args, budget: budget }
EOS
	run_cmd node "$WF_RUN" "$WF_DIR/review-diff.js" "$stub"
	assert_rc 0 "wf: review-diff.js runs when scorers return null or throw"
	assert_contains "$OUT" '"predicate":"scorerdied"' "wf: null-scorer finding is in dismissed"
	assert_contains "$OUT" '"predicate":"scorerthrew"' "wf: throwing-scorer finding is in dismissed"
	assert_contains "$OUT" '"reason":"scorer failed; not scored"' "wf: unscored finding carries an honest reason"
	assert_not_contains "$OUT" 'scored 0' "wf: no invented score of 0"
	assert_contains "$OUT" '"dropped":2' "wf: dropped counts the unscored findings"
}

t_wf_research_sweep_synth_prompt_ties_confidence_to_evidence() {
	local d stub
	d=$(tmp_dir)
	stub="$d/stub.js"
	_wf_parallel_stub >"$stub"
	cat >>"$stub" <<'EOS'
async function agent(prompt, opts) {
  if (opts.label === 'synthesize') { process.stderr.write('SYNTH:' + prompt + '\n'); return 'report' }
  if (opts.label === 'angles') { return { angles: [{ key: 'a', query: 'q' }] } }
  if (opts.label === 'research:a') { return { headline: 'h', claims: [] } }
  if (opts.label === 'check:a') { return { confirmed: [], unsupported: [], notes: '' } }
  return null
}
function log() {}
function phase() {}
const args = { question: 'why?' }
const budget = { total: null, spent: function () { return 0 }, remaining: function () { return Infinity } }
module.exports = { agent: agent, parallel: parallel, pipeline: async function (items, a, b) {
  const out = []
  for (const it of items) { const x = await a(null, it); out.push(await b(x)) }
  return out
}, log: log, phase: phase, args: args, budget: budget }
EOS
	run_cmd node "$WF_RUN" "$WF_DIR/research-sweep.js" "$stub"
	assert_rc 0 "wf: research-sweep.js runs under wf-run.js"
	assert_contains "$ERR" '"confirmed" only when a primary source was read this run' "wf: synth prompt names the confirmed tier"
	assert_contains "$ERR" 'primary source' "wf: confirmed needs a primary source read this run"
	assert_contains "$ERR" 'likely' "wf: synth prompt names the likely tier"
	assert_contains "$ERR" 'unknown' "wf: synth prompt names the unknown tier"
	assert_contains "$ERR" 'an empty unknowns list must say why it is empty' "wf: synth prompt explains empty unknowns"
	assert_contains "$ERR" 'contradicts the majority' "wf: synth prompt leads with contradicting data"
	assert_contains "$ERR" 'absence of a mention is not evidence' "wf: synth prompt rejects absence as evidence"
}

t_wf_research_sweep_schema_requires_queries_and_unknowns() {
	local req
	req=$(awk '/^const RESEARCH_SCHEMA/{f=1} f&&/required: \[/{print; exit}' "$WF_DIR/research-sweep.js")
	assert_contains "$req" "'queriesRun'" "wf: RESEARCH_SCHEMA requires queriesRun"
	assert_contains "$req" "'unknowns'" "wf: RESEARCH_SCHEMA requires unknowns"
}

# ---------------------------------------------------------------------------
# build-slices fix-ladder memory, null-fix retry, and the worker pool.
# t_wf_build_slices_fix_* / t_wf_build_slices_pool_* prefix. Stubs log one
# line per call to stderr ("CALL <label> <prompt>", "START/END <id>"),
# which run_cmd captures as $ERR.
# ---------------------------------------------------------------------------

# _wf_bs_tail — the shared end of every stub below: no-op log/phase and the
# one-wave args for the tasks in $1 (a JS array literal).
_wf_bs_tail() {
	cat <<EOT
function log() {}
function phase() {}
const args = { tasks: '/tmp/TASKS.md', base: 'main', testCmd: 'true', waves: [$1], scriptsDir: '/tmp/scripts', reviewDir: '/tmp/review' }
const budget = { total: null, spent: function () { return 0 }, remaining: function () { return Infinity } }
module.exports = { agent: agent, parallel: parallel, pipeline: async function () { return [] }, log: log, phase: phase, args: args, budget: budget }
EOT
}

t_wf_build_slices_fix_history_carried_to_later_rounds() {
	local d stub
	d=$(tmp_dir)
	stub="$d/stub.js"
	_wf_parallel_stub >"$stub"
	cat >>"$stub" <<'EOS'
function finding(n) {
  return { verdict: 'reject', checked: 'full', findings: [{ predicate: 'predicateOf' + n, severity: 'fatal', scenario: 's', receipt: 'x.js:1' }] }
}
const clean = { verdict: 'ok', checked: 'full', findings: [] }
async function agent(prompt, opts) {
  const label = opts.label
  let m
  if (/^fix:/.test(label)) { process.stderr.write('CALL ' + label + ' ' + prompt + '\n') }
  if (label === 'brief:T1') { return { briefPath: '/tmp/T1-brief.md' } }
  if (label === 'implement:T1') {
    return { id: 'T1', redExit: 1, greenExit: 0, refactorPassCount: 3, commits: ['a'], files: ['x.js'], notes: '' }
  }
  if (/^review:T1/.test(label)) { return { diffPath: '/tmp/T1.diff' } }
  if (label === 'adv:correctness:T1') { return finding(1) }
  if (/^adv:(gaming|slop):T1/.test(label)) { return clean }
  if ((m = /^adv:correctness:T1:r(\d)$/.exec(label))) { return finding(Number(m[1]) + 1) }
  if ((m = /^fix:T1:r(\d)$/.exec(label))) {
    return { id: 'T1', redExit: 1, greenExit: 0, refactorPassCount: 3, commits: ['a'], files: ['x.js'], notes: 'notesOfRound' + m[1] }
  }
  throw new Error('unexpected label ' + label)
}
EOS
	_wf_bs_tail "['T1']" >>"$stub"
	run_cmd node "$WF_RUN" "$WF_DIR/build-slices.js" "$stub"
	assert_rc 0 "wf: build-slices.js runs a five-round fix ladder"
	local r1 r2 r3 r4 r5
	r1=$(printf '%s\n' "$ERR" | grep '^CALL fix:T1:r1 ')
	r2=$(printf '%s\n' "$ERR" | grep '^CALL fix:T1:r2 ')
	r3=$(printf '%s\n' "$ERR" | grep '^CALL fix:T1:r3 ')
	r4=$(printf '%s\n' "$ERR" | grep '^CALL fix:T1:r4 ')
	r5=$(printf '%s\n' "$ERR" | grep '^CALL fix:T1:r5 ')
	assert_not_contains "$r1" "notesOfRound" "wf: the round 1 fix prompt has no history"
	assert_contains "$r2" "predicateOf1" "wf: the round 2 fix prompt carries round 1's finding"
	assert_contains "$r2" "notesOfRound1" "wf: the round 2 fix prompt carries round 1's notes"
	assert_contains "$r3" "predicateOf1" "wf: the round 3 fix prompt carries round 1's finding"
	assert_contains "$r3" "predicateOf2" "wf: the round 3 fix prompt carries round 2's finding"
	assert_not_contains "$r3" "tried and failed" "wf: rounds 2-3 do not yet use the 'tried and failed' heading"
	assert_contains "$r4" "tried and failed" "wf: the round 4 fix prompt uses the 'tried and failed' heading"
	assert_contains "$r4" "notesOfRound1" "wf: the round 4 prompt carries round 1's notes"
	assert_contains "$r4" "notesOfRound2" "wf: the round 4 prompt carries round 2's notes"
	assert_contains "$r4" "notesOfRound3" "wf: the round 4 prompt carries round 3's notes"
	assert_contains "$r5" "tried and failed" "wf: the round 5 fix prompt uses the 'tried and failed' heading"
	assert_contains "$r5" "notesOfRound4" "wf: the round 5 prompt carries round 4's notes"
	assert_contains "$OUT" "exhausted after 5 rounds" "wf: the exhausted text is used once round 5 completed"
}

t_wf_build_slices_fix_null_retried_once_then_continues() {
	local d stub
	d=$(tmp_dir)
	stub="$d/stub.js"
	_wf_parallel_stub >"$stub"
	cat >>"$stub" <<'EOS'
let fixCalls = 0
async function agent(prompt, opts) {
  const label = opts.label
  if (label === 'brief:T1') { return { briefPath: '/tmp/T1-brief.md' } }
  if (label === 'implement:T1') {
    return { id: 'T1', redExit: 1, greenExit: 0, refactorPassCount: 3, commits: ['a'], files: ['x.js'], notes: '' }
  }
  if (/^review:T1/.test(label)) { return { diffPath: '/tmp/T1.diff' } }
  if (label === 'adv:correctness:T1') {
    return { verdict: 'reject', checked: 'full', findings: [{ predicate: 'bug', severity: 'fatal', scenario: 's', receipt: 'x.js:1' }] }
  }
  if (/^adv:/.test(label)) { return { verdict: 'ok', checked: 'full', findings: [] } }
  if (label === 'fix:T1:r1') {
    fixCalls++
    process.stderr.write('FIXCALL ' + fixCalls + '\n')
    if (fixCalls === 1) { return null }
    return { id: 'T1', redExit: 1, greenExit: 0, refactorPassCount: 3, commits: ['a', 'b'], files: ['x.js'], notes: 'fixed' }
  }
  throw new Error('unexpected label ' + label)
}
EOS
	_wf_bs_tail "['T1']" >>"$stub"
	run_cmd node "$WF_RUN" "$WF_DIR/build-slices.js" "$stub"
	assert_rc 0 "wf: build-slices.js runs when a fix agent returns nothing once"
	assert_contains "$ERR" "FIXCALL 2" "wf: the null round-1 fix is retried"
	assert_not_contains "$ERR" "FIXCALL 3" "wf: the retry happens once"
	assert_contains "$OUT" '"parked":[]' "wf: nothing is parked after a successful retry"
	assert_contains "$OUT" '"clean":true' "wf: the run continues to clean"
}

t_wf_build_slices_fix_null_twice_parks_with_true_reason() {
	local d stub
	d=$(tmp_dir)
	stub="$d/stub.js"
	_wf_parallel_stub >"$stub"
	cat >>"$stub" <<'EOS'
async function agent(prompt, opts) {
  const label = opts.label
  if (label === 'brief:T1') { return { briefPath: '/tmp/T1-brief.md' } }
  if (label === 'implement:T1') {
    return { id: 'T1', redExit: 1, greenExit: 0, refactorPassCount: 3, commits: ['a'], files: ['x.js'], notes: '' }
  }
  if (/^review:T1/.test(label)) { return { diffPath: '/tmp/T1.diff' } }
  if (label === 'adv:correctness:T1') {
    return { verdict: 'reject', checked: 'full', findings: [{ predicate: 'bug', severity: 'fatal', scenario: 's', receipt: 'x.js:1' }] }
  }
  if (/^adv:/.test(label)) { return { verdict: 'ok', checked: 'full', findings: [] } }
  if (label === 'fix:T1:r1') { return null }
  throw new Error('unexpected label ' + label)
}
EOS
	_wf_bs_tail "['T1']" >>"$stub"
	run_cmd node "$WF_RUN" "$WF_DIR/build-slices.js" "$stub"
	assert_rc 0 "wf: build-slices.js runs when a fix agent returns nothing twice"
	assert_contains "$OUT" "fix agent returned nothing in round 1" "wf: the park reason names round 1"
	assert_not_contains "$OUT" "5 rounds" "wf: the park reason does not claim five rounds"
	assert_contains "$OUT" '"predicate":"bug"' "wf: the finding is parked, not dropped"
}

t_wf_build_slices_pool_refills_slots_in_wave_order() {
	local d stub
	d=$(tmp_dir)
	stub="$d/stub.js"
	_wf_parallel_stub >"$stub"
	cat >>"$stub" <<'EOS'
let inflight = 0, maxInflight = 0
const advDone = {}
function sleep(ms) { return new Promise(function (r) { setTimeout(r, ms) }) }
async function agent(prompt, opts) {
  const label = opts.label
  let m
  if ((m = /^brief:(T\d)$/.exec(label))) {
    inflight++
    if (inflight > maxInflight) { maxInflight = inflight }
    process.stderr.write('START ' + m[1] + ' MAX ' + maxInflight + '\n')
    return { briefPath: '/tmp/' + m[1] + '-brief.md' }
  }
  if ((m = /^implement:(T\d)$/.exec(label))) {
    await sleep(m[1] === 'T1' ? 500 : 20)
    return { id: m[1], redExit: 1, greenExit: 0, refactorPassCount: 3, commits: ['a'], files: ['x.js'], notes: '' }
  }
  if ((m = /^review:(T\d)$/.exec(label))) { return { diffPath: '/tmp/' + m[1] + '.diff' } }
  if ((m = /^adv:\w+:(T\d)$/.exec(label))) {
    advDone[m[1]] = (advDone[m[1]] || 0) + 1
    if (advDone[m[1]] === 3) { inflight--; process.stderr.write('END ' + m[1] + '\n') }
    return { verdict: 'ok', checked: 'full', findings: [] }
  }
  throw new Error('unexpected label ' + label)
}
EOS
	_wf_bs_tail "['T1', 'T2', 'T3', 'T4', 'T5']" >>"$stub"
	run_cmd node "$WF_RUN" "$WF_DIR/build-slices.js" "$stub"
	assert_rc 0 "wf: build-slices.js runs a five-task wave"
	local order t5 t1end
	t5=$(printf '%s\n' "$ERR" | grep -n '^START T5' | cut -d: -f1)
	t1end=$(printf '%s\n' "$ERR" | grep -n '^END T1' | cut -d: -f1)
	if [ -n "$t5" ] && [ -n "$t1end" ] && [ "$t5" -lt "$t1end" ]; then
		assert_eq "yes" "yes" "wf: task 5 starts before slow task 1 finishes"
	else
		assert_eq "t5=$t5 t1end=$t1end" "t5 before t1end" "wf: task 5 starts before slow task 1 finishes"
	fi
	assert_contains "$ERR" "MAX 4" "wf: four tasks were in flight at once"
	assert_not_contains "$ERR" "MAX 5" "wf: never more than four in flight"
	order=$(printf '%s' "$OUT" | grep -o '"id":"T[0-9]"' | tr '\n' ' ')
	assert_eq "$order" '"id":"T1" "id":"T2" "id":"T3" "id":"T4" "id":"T5" ' "wf: results come back in wave order, not finish order"
}

t_wf_build_slices_pool_survives_throwing_tasks() {
	local d stub
	d=$(tmp_dir)
	stub="$d/stub.js"
	_wf_parallel_stub >"$stub"
	cat >>"$stub" <<'EOS'
async function agent(prompt, opts) {
  const label = opts.label
  let m
  if ((m = /^brief:(T\d)$/.exec(label))) {
    if (m[1] !== 'T5') { throw new Error('boom ' + m[1]) }
    return { briefPath: '/tmp/T5-brief.md' }
  }
  if ((m = /^implement:(T\d)$/.exec(label))) {
    return { id: m[1], redExit: 1, greenExit: 0, refactorPassCount: 3, commits: ['a'], files: ['x.js'], notes: '' }
  }
  if ((m = /^review:(T\d)$/.exec(label))) { return { diffPath: '/tmp/' + m[1] + '.diff' } }
  if ((m = /^adv:\w+:(T\d)$/.exec(label))) { return { verdict: 'ok', checked: 'full', findings: [] } }
  throw new Error('unexpected label ' + label)
}
EOS
	_wf_bs_tail "['T1', 'T2', 'T3', 'T4', 'T5']" >>"$stub"
	run_cmd node "$WF_RUN" "$WF_DIR/build-slices.js" "$stub"
	assert_rc 0 "wf: build-slices.js runs when four tasks throw"
	assert_contains "$OUT" '"id":"T5"' "wf: task 5 still runs after tasks 1-4 threw"
}
