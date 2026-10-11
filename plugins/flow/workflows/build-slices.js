// build-slices — implement TASKS.md tasks end to end: brief, developer, review-package, adversary
// lenses, then a bounded fix ladder. Globals: agent, parallel, workflow, log, args (C11,
// WORKFLOW-API.md). The wave schedule is flow-lint's (`--json`, the only TASKS.md parser, which
// proves [P] tasks are disjoint). This file schedules waves, runs the worker pool and keeps the gap,
// parked and discovered lists; each task's whole chain runs in the child workflow
// build-slices-task.js (one workflow() call per task, one level deep). Long prompt prose lives in
// workflows/prompts/build-slices-<step>.md; an agent prompt names the file and carries the values.
export const meta = {
  name: 'build-slices',
  description: 'Implement TASKS.md tasks wave by wave with brief, developer, review-package, adversarial review, and a bounded fix ladder',
  whenToUse: 'Use in Workflow mode when a wave has three or more ready [P] tasks in an approved TASKS.md',
  phases: [
    { title: 'Schedule', detail: 'flow-lint --json validates TASKS.md and returns the dispatch waves' },
    { title: 'Brief', detail: 'task-brief cuts one task (and its design contract) into a brief file' },
    { title: 'Implement', detail: 'a developer agent implements the task from the brief only' },
    { title: 'Review', detail: 'review-package builds the diff; two adversary lenses check it' },
    { title: 'Fix', detail: 'bounded fix ladder on fatal/significant findings, then a recorded ruling' },
  ],
}

// Schemas; objOf and arrOf only shorten the literals.
const STR = { type: 'string' }
const NUM = { type: 'number' }
function arrOf(items) { return { type: 'array', items: items } }
function objOf(required, properties) { return { type: 'object', required: required, properties: properties } }
const STRS = arrOf(STR)
const SCHEDULE_SCHEMA = {
  type: 'object',
  required: ['waves'],
  properties: { ok: { type: 'boolean' }, waves: arrOf(STRS) },
}
// files: the task line's files: list (finds earlier gaps); verify: its verify command or human: text.
const BRIEF_SCHEMA = objOf(['briefPath'], { briefPath: STR, files: STRS, verify: STR })
// toplevel: `git rev-parse --show-toplevel` from repoRoot, compared in code. exit: the integer
// printed by `<verify>; echo $?`. headSha: HEAD at packaging, the next round's FIX_BASE.
const ROOT_SCHEMA = objOf(['toplevel'], { toplevel: STR })
// The same check when scriptsDir is not absolute: scriptsDir is that dir as `pwd -P` prints it.
const ROOT_DIR_SCHEMA = objOf(['toplevel', 'scriptsDir'], { toplevel: STR, scriptsDir: STR })
const VERIFY_RUN_SCHEMA = objOf(['exit'], { exit: NUM, output: STR })
const DIFF_SCHEMA = objOf(['diffPath'], { diffPath: STR, headSha: STR })
// Test ids as the runner lists them (count only for an unknown runner); replaces: (replaces: ...) ids.
const TESTS_SCHEMA = objOf(['ids'], { runner: STR, ids: STRS, count: NUM, replaces: STRS })
const TASK_STATUS = ['DONE', 'DONE_WITH_CONCERNS', 'BLOCKED']
// gaps: surprises later waves would rediscover. rejected: a finding the fixer disputes, with its
// receipt. misreads: a finding showing the task contract was misread (needs a Ruling and --amend).
const TASK_RESULT = objOf(['id', 'redExit', 'greenExit', 'refactorPassCount', 'commits', 'files', 'notes'], {
  id: STR, redExit: NUM, greenExit: NUM, refactorPassCount: NUM, commits: STRS, files: STRS, notes: STR,
  status: { type: 'string', enum: TASK_STATUS }, concerns: STRS, gaps: STRS,
  rejected: arrOf(objOf(['finding', 'receipt'], { finding: STR, receipt: STR })),
  misreads: arrOf(objOf(['finding', 'ruling'], { finding: STR, ruling: STR, amend: STR })),
})
const FINDING_ITEM = objOf(['predicate', 'severity', 'scenario', 'receipt'], { predicate: STR, severity: STR, scenario: STR, receipt: STR, quote: STR })
const RELOOK = objOf(['verdicts'], {
  verdicts: arrOf(objOf(['finding', 'status', 'receipt'], { finding: STR, status: { type: 'string', enum: ['ADDRESSED', 'NOT_ADDRESSED'] }, receipt: STR })),
  newBreakage: arrOf(FINDING_ITEM),
  outOfScope: STRS,
})
const SCORE_SCHEMA = objOf(['score'], { score: NUM, why: STR, how: STR })
const CLASSIFY_SCHEMA = objOf(['classes'], {
  classes: arrOf(objOf(['predicate', 'class'], { predicate: STR, class: { type: 'string', enum: ['known-open', 'load-bearing'] } })),
  oversize: { type: 'boolean' },
  recut: STR,
})
const VERIFY_SCHEMA = objOf(['results'], {
  results: arrOf(objOf(['requirement', 'check', 'status'], { requirement: STR, check: STR, status: { type: 'string', enum: ['pass', 'fail', 'refused'] }, output: STR })),
})
const FINDINGS = objOf(['verdict', 'checked', 'findings'], {
  verdict: STR, checked: STR, findings: arrOf(FINDING_ITEM),
  // What a diff-only reviewer could not judge; each check is a runnable read-only command or grep.
  cannotVerify: { type: 'array', items: objOf(['requirement', 'check'], { requirement: STR, check: STR }) },
})

// selectWaves narrows flow-lint's wave list to the requested ids, keeping its order and dropping
// empty waves. Ids compare as strings (T001, CHK011).
function selectWaves(lintWaves, ids) {
  const want = (ids && ids.length > 0) ? ids.map(String) : null
  const out = []
  for (let i = 0; i < lintWaves.length; i++) {
    const wave = (lintWaves[i] || []).map(String)
    const keep = want === null ? wave : wave.filter(function (id) { return want.indexOf(id) !== -1 })
    if (keep.length > 0) { out.push(keep) }
  }
  return out
}

const tasks = args.tasks || args.plan
const design = args.design
const base = args.base
const testCmd = args.testCmd
const requestedIds = args.ids || args.slices
const scriptsDir = args.scriptsDir || '$HOME/.claude/scripts'
const promptsDir = args.promptsDir || scriptsDir + '/../workflows/prompts'
const MAX_PARALLEL = 4 // skills/next/SKILL.md: "at most 4 in parallel"
// Generated artifacts live in the feature's own review/ (git-ignored as `.specs/*/review/`).
const reviewDir = args.reviewDir || (String(tasks || '').replace(/\/?[^/]*$/, '') || '.') + '/review'
const repoRoot = args.repoRoot
const NEXT_CALL = 'Workflow({ name: "flow:build-slices", args: { tasks: "<absolute path to TASKS.md>", base: "<Base sha>", testCmd: "<the Test: command>", repoRoot: "<absolute path printed by git rev-parse --show-toplevel>", scriptsDir: "<absolute path of the flow plugin\'s scripts/ dir>" } })'
const ABS = /^(\/|[A-Za-z]:[\\/])/
function trimSlash(p) { return String(p || '').replace(/[\\/]+$/, '') }
// The child workflow sits in workflows/, beside scripts/, the way promptsDir does. A trailing
// /scripts becomes /workflows, so no '..' is left for the runtime to normalise through a symlink.
// workflow() expands no shell variables, so a scriptsDir that is not absolute (the '$HOME/...'
// default) is first resolved by the repo-root agent's shell (`pwd -P`, symlinks followed).
function childPath(dir) {
  const d = trimSlash(dir)
  return /\/scripts$/.test(d) ? d.replace(/\/scripts$/, '/workflows/build-slices-task.js') : d + '/../workflows/build-slices-task.js'
}
let taskScript = ABS.test(scriptsDir) ? childPath(scriptsDir) : null
function refusal(reason, missing, extra) { return Object.assign({ started: false, reason: reason, missing: missing }, extra || {}, { next: NEXT_CALL }) }
function haiku(prompt, label, phase, schema) { return agent(prompt, { model: 'haiku', label: label, phase: phase, schema: schema }) }

// Preflight: a missing argument would be pasted into prompts as "undefined" and a relative or wrong
// repo would build in the wrong checkout, so nothing is dispatched until all four are in hand.
function preflight() {
  const given = { tasks: tasks, base: base, testCmd: testCmd, repoRoot: repoRoot }
  const missing = Object.keys(given).filter(function (k) { return !given[k] })
  if (missing.length > 0) { return refusal('missing-arg', missing) }
  if (!ABS.test(String(repoRoot))) { return refusal('not-absolute', []) }
  return /['\n\r]/.test(String(repoRoot)) ? refusal('bad-repo-root', []) : null
}
async function checkRepo() {
  const cmd = 'cd \'' + repoRoot + '\' && git rev-parse --show-toplevel'
  const res = taskScript
    ? await haiku('Run this exact command and return its output as toplevel: ' + cmd, 'repo-root', 'Schedule', ROOT_SCHEMA)
    : await haiku('Run this exact command and return its first output line as toplevel and its second as scriptsDir: ' + cmd + ' && cd "' + scriptsDir + '" && pwd -P', 'repo-root', 'Schedule', ROOT_DIR_SCHEMA)
  const dir = trimSlash(res && res.scriptsDir)
  if (!taskScript && ABS.test(dir) && !/[\n\r]/.test(dir)) { taskScript = childPath(dir) }
  if (res && trimSlash(res.toplevel) === trimSlash(repoRoot)) { return null }
  log('repo check: ' + ((res && res.toplevel) || 'no answer') + ' is not ' + repoRoot + '; nothing dispatched')
  return refusal('wrong-repo', [], { toplevel: (res && res.toplevel) || '' })
}
const refused = preflight() || await checkRepo() || (taskScript ? null : refusal('not-absolute', ['scriptsDir']))
if (refused) { return refused }

// Stage 0: `flow-lint --json` exits 1 on any ERROR, so a plan that races two [P] tasks over one
// file never reaches a developer. Null means the linter refused the plan.
async function scheduleWaves() {
  const scheduleRes = await agent(
    'Run this exact command and return its parsed JSON: ' + scriptsDir + '/flow-lint ' + tasks + ' --json' +
      '. Return an object with "ok" (the JSON\'s ok field) and "waves" (the JSON\'s waves array, ' +
      'an array of arrays of task id strings). If the command exits non-zero, still return the ' +
      'parsed JSON so the caller sees ok:false and an empty schedule.',
    { model: 'haiku', agentType: 'general-purpose', label: 'schedule', phase: 'Schedule', schema: SCHEDULE_SCHEMA }
  )
  if (scheduleRes && scheduleRes.ok === false) {
    log('flow-lint reported ERRORs for ' + tasks + '; refusing to dispatch. Fix TASKS.md and re-run.')
    return null
  }
  return (scheduleRes && scheduleRes.waves) || []
}
let lintWaves = args.waves
if (lintWaves === undefined) {
  lintWaves = await scheduleWaves()
  if (lintWaves === null) { return { tasks: [], parked: [], clean: false, waves: [], discovered: [], lintOk: false } }
}

// Gaps from earlier tasks. knownGaps: { task, wave, files, text } per parked known-open finding; a
// later task whose files: overlap sees them. reportedGaps: TASK_RESULT.gaps, not tied to files.
// Both reach only tasks in LATER waves, so a task never reads a gap a sibling wrote while it ran.
// The child reports its additions when it returns (gapNotes, knownOpen, discovered); runTask merges them.
const knownGaps = []
const reportedGaps = []
// discovered is declared here so a re-look's outOfScope notes can join it as tasks run.
const discovered = []
function noteGaps(task, wave, list) {
  ;(list || []).forEach(function (t) {
    const text = String(t || '').replace(/\s+/g, ' ').trim().slice(0, 300)
    if (text && !reportedGaps.some(function (g) { return g.text === text })) { reportedGaps.push({ task: task, wave: wave, text: text }) }
  })
}
// One block for the brief (reported gaps and F52 known-open findings of earlier waves); the brief
// is cut before the task's files are known, so nothing is filtered by file here.
function gapBlock(wave) {
  const lines = reportedGaps.filter(function (g) { return g.wave < wave }).map(function (g) { return g.task + ': ' + g.text })
  knownGaps.filter(function (g) { return g.wave < wave }).forEach(function (g) {
    const line = g.task + ': ' + String(g.text || '').replace(/\s+/g, ' ')
    if (lines.indexOf(line) === -1) { lines.push(line) }
  })
  return lines.join('\n')
}

// The schemas the child's agents answer in; passed in args so one copy exists.
const TASK_SCHEMAS = { BRIEF_SCHEMA: BRIEF_SCHEMA, VERIFY_RUN_SCHEMA: VERIFY_RUN_SCHEMA, DIFF_SCHEMA: DIFF_SCHEMA, TESTS_SCHEMA: TESTS_SCHEMA, TASK_RESULT: TASK_RESULT, RELOOK: RELOOK, SCORE_SCHEMA: SCORE_SCHEMA, CLASSIFY_SCHEMA: CLASSIFY_SCHEMA, VERIFY_SCHEMA: VERIFY_SCHEMA, FINDINGS: FINDINGS }
// runTask hands one task's whole chain to the child inside a single pool slot, so no task in a wave
// blocks another, then merges what the child added to the gap and discovered lists.
async function runTask(id, wave) {
  const r = await workflow({ scriptPath: taskScript }, {
    id: id, wave: wave, tasks: tasks, design: design, base: base, testCmd: testCmd, scriptsDir: scriptsDir, promptsDir: promptsDir,
    reviewDir: reviewDir, repoRoot: repoRoot, gapText: gapBlock(wave), knownGaps: knownGaps.slice(), schemas: TASK_SCHEMAS,
  })
  if (!r) { log('task ' + id + ': the child workflow returned no result'); return null }
  noteGaps(id, wave, r.gapNotes)
  ;(r.knownOpen || []).forEach(function (g) { knownGaps.push(g) })
  ;(r.discovered || []).forEach(function (d) { discovered.push(d) })
  return r
}

// A worker pool, not fixed chunks: min(MAX_PARALLEL, ready.length) workers pull the next index off
// a shared queue, so a finished task frees its slot at once. Results are stored by index, keeping
// wave order (not finish order) so the PR body and digest do not reshuffle.
async function runWave(ready, w) {
  const waveResults = new Array(ready.length).fill(null)
  let nextIndex = 0
  const workers = []
  for (let k = 0; k < Math.min(MAX_PARALLEL, ready.length); k++) {
    workers.push(async function () {
      while (nextIndex < ready.length) {
        const i = nextIndex++
        try { waveResults[i] = await runTask(ready[i], w) } catch (e) { // a thrown task frees its slot and must not kill the worker
          log('task ' + ready[i] + ' threw: ' + (e && e.message ? e.message : e))
          waveResults[i] = null
        }
      }
    })
  }
  await parallel(workers)
  return waveResults
}

// The schedule is fixed once flow-lint has spoken: log it in full before any wave runs.
const waves = selectWaves(lintWaves, requestedIds)
waves.forEach(function (wave, i) {
  log('wave ' + (i + 1) + ': ' + wave.join(', '))
})

const finalTasks = []
const parked = []
// unfinished: tasks whose child threw or returned nothing (a path or runtime error, not a verdict);
// they count against clean through incomplete, so a run where no task ran is never clean.
const unfinished = []
const unrunWaves = []
const minors = []
let stopReason = null

for (let w = 0; w < waves.length; w++) {
  const ready = waves[w]
  const waveResults = await runWave(ready, w)
  let unparkedInWave = 0
  waveResults.forEach(function (r, i) {
    if (!r) { unfinished.push(ready[i]); return }
    finalTasks.push(r.result)
    r.parked.forEach(function (p) { parked.push(p) })
    ;(r.minors || []).forEach(function (m) { minors.push(m) })
    if (r.parked.length === 0) { unparkedInWave++ }
  })
  if (w >= waves.length - 1) { continue }
  // Wave breaker: fewer than 2/3 of a wave of three or more ended unparked is a pattern, not a
  // one-off, and the next wave would build on it. A thrown task counts as parked.
  if (ready.length >= 3 && unparkedInWave * 3 < ready.length * 2) {
    log('wave breaker: ' + unparkedInWave + ' of ' + ready.length + ' tasks of wave ' + (w + 1) + ' ended unparked; later waves not dispatched')
    stopReason = 'wave breaker'
    unrunWaves.push.apply(unrunWaves, waves.slice(w + 1))
    break
  }
  if (parked.some(function (p) { return p.class === 'load-bearing' })) { // later tasks would build on a known defect
    log('load-bearing finding after wave ' + (w + 1) + '; later waves not dispatched')
    unrunWaves.push.apply(unrunWaves, waves.slice(w + 1))
    break
  }
}

// discovered: out-of-plan work a task's notes flagged (plus re-look outOfScope notes), surfaced so
// the caller can append it to TASKS.md (append-only) or NOTES.md instead of silently dropping it.
finalTasks.forEach(function (t) {
  if (t && typeof t.notes === 'string' && /out-of-plan/i.test(t.notes)) { discovered.push({ task: t.id, note: t.notes }) }
})
const incomplete = finalTasks.filter(function (t) { return t && t.failedLenses && t.failedLenses.length > 0 }).map(function (t) { return t.id }).concat(unfinished)
const blockedBy = parked.filter(function (p) { return p.class === 'load-bearing' }).map(function (p) { return p.task }).filter(function (t, i, a) { return a.indexOf(t) === i })

return { tasks: finalTasks, parked: parked, clean: parked.length === 0 && incomplete.length === 0, waves: waves, discovered: discovered, lintOk: true, incomplete: incomplete, blocked: blockedBy.length > 0, blockedBy: blockedBy, unrunWaves: unrunWaves, stopReason: stopReason, minors: minors }
