// build-slices — implement TASKS.md tasks end to end: brief, developer,
// review-package, two adversary lenses, then a bounded fix ladder. See C11 in
// the harness spec and WORKFLOW-API.md for the globals used below (agent,
// pipeline, parallel, log, args).
//
// The plan is a TASKS.md (spec 004 K-B grammar) and the schedule is not this
// workflow's to invent: `flow-lint --json` already proves `[P]` disjointness
// per wave and returns the wave list, so stage 0 runs the linter and uses its
// `waves` array verbatim. Each wave runs concurrently via parallel(); a task's
// full chain (brief -> implement -> package -> review -> fix ladder) runs
// inside its own thunk, so a slow task never blocks a fast one in the same
// wave, and wave N+1 never starts before wave N reports.
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

// Stage 0: the wave schedule comes from `flow-lint --json`, never from this
// workflow's own guess about file overlap. The linter is the only parser of
// the TASKS.md grammar and the only thing that has proved `[P]` disjointness.
const SCHEDULE_SCHEMA = {
  type: 'object',
  required: ['waves'],
  properties: {
    ok: { type: 'boolean' },
    waves: { type: 'array', items: { type: 'array', items: { type: 'string' } } },
  },
}

const BRIEF_SCHEMA = {
  type: 'object',
  required: ['briefPath'],
  properties: { briefPath: { type: 'string' } },
}

const DIFF_SCHEMA = {
  type: 'object',
  required: ['diffPath'],
  properties: { diffPath: { type: 'string' } },
}

const TASK_RESULT = {
  type: 'object',
  required: ['id', 'redExit', 'greenExit', 'refactorPassCount', 'commits', 'files', 'notes'],
  properties: {
    id: { type: 'string' },
    redExit: { type: 'number' },
    greenExit: { type: 'number' },
    refactorPassCount: { type: 'number' },
    commits: { type: 'array', items: { type: 'string' } },
    files: { type: 'array', items: { type: 'string' } },
    notes: { type: 'string' },
  },
}

const FINDINGS = {
  type: 'object',
  required: ['verdict', 'checked', 'findings'],
  properties: {
    verdict: { type: 'string' },
    checked: { type: 'string' },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        required: ['predicate', 'severity', 'scenario', 'receipt'],
        properties: {
          predicate: { type: 'string' },
          severity: { type: 'string' },
          scenario: { type: 'string' },
          receipt: { type: 'string' },
        },
      },
    },
  },
}

function isBlocking(finding) {
  return !!finding && (finding.severity === 'fatal' || finding.severity === 'significant')
}

function adversaryPrompt(lens, briefPath, diffPath) {
  return 'Adversarial review, lens=' + lens + '. Read ONLY the brief at ' + briefPath +
    ' and the diff at ' + diffPath + '. Report findings as FINDINGS JSON with predicate, severity ' +
    '(fatal|significant|minor|none), scenario, and receipt (file:line or command output).'
}

// selectWaves narrows flow-lint's wave list to the ids this run was asked to
// build, preserving the linter's wave order and dropping waves that end up
// empty. An empty/absent `ids` means "every task the linter scheduled".
// Ids are compared as strings because TASKS.md ids are strings (T001, CHK011).
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
// Generated artifacts live in the feature's own review/ — the per-feature dir
// `.gitignore` matches as `.specs/*/review/`, and the same one task-brief
// writes into. A repo-level `.specs/review/` is neither.
const reviewDir = args.reviewDir || (String(tasks || '').replace(/\/?[^/]*$/, '') || '.') + '/review'

// Stage 0: run the linter and take its waves. `flow-lint --json` exits 1 on any
// ERROR, so a plan that would race two [P] tasks over one file never reaches a
// developer agent — the schedule and the validation are the same call.
let lintWaves = args.waves
if (lintWaves === undefined) {
  const scheduleRes = await agent(
    'Run this exact command and return its parsed JSON: ' + scriptsDir + '/flow-lint ' + tasks + ' --json' +
      '. Return an object with "ok" (the JSON\'s ok field) and "waves" (the JSON\'s waves array, ' +
      'an array of arrays of task id strings). If the command exits non-zero, still return the ' +
      'parsed JSON so the caller sees ok:false and an empty schedule.',
    {
      model: 'haiku',
      agentType: 'general-purpose',
      label: 'schedule',
      phase: 'Schedule',
      schema: SCHEDULE_SCHEMA,
    }
  )
  if (scheduleRes && scheduleRes.ok === false) {
    log('flow-lint reported ERRORs for ' + tasks + '; refusing to dispatch. Fix TASKS.md and re-run.')
    return { tasks: [], parked: [], clean: false, waves: [], discovered: [], lintOk: false }
  }
  lintWaves = (scheduleRes && scheduleRes.waves) || []
}

// runTask carries one task through its full chain (brief -> implement ->
// package -> review -> fix ladder) inside a single thunk, so it can be handed
// to parallel() alongside every other task in its wave without any of them
// blocking on each other.
async function runTask(id) {
  let briefCmd = scriptsDir + '/task-brief ' + tasks + ' ' + id
  if (design) { briefCmd += ' --design ' + design }
  const briefRes = await agent(
    'Run this exact command and return its stdout output path: ' + briefCmd,
    { model: 'haiku', label: 'brief:' + id, phase: 'Brief', schema: BRIEF_SCHEMA }
  )
  const briefPath = briefRes ? briefRes.briefPath : null
  if (!briefPath) {
    return {
      result: { id: id, redExit: null, greenExit: null, refactorPassCount: 0, commits: [], files: [], notes: 'brief failed' },
      parked: [],
    }
  }

  const implementPrompt = 'Implement task ' + id + ' by reading ONLY the brief at ' + briefPath +
    ' and the files it names. Follow RED/GREEN/REFACTOR from the brief, and touch no file outside ' +
    'the brief\'s files: list. Run the test command: ' + testCmd + '. State the search receipt before ' +
    'your first edit and run scripts/slop-check before reporting done. Return the TASK_RESULT.'
  const implRes = await agent(implementPrompt, { agentType: 'developer', label: 'implement:' + id, phase: 'Implement', schema: TASK_RESULT })
  if (!implRes) {
    return {
      result: { id: id, redExit: null, greenExit: null, refactorPassCount: 0, commits: [], files: [], notes: 'implement failed' },
      parked: [],
    }
  }
  let ctx = Object.assign({}, implRes, { id: id, briefPath: briefPath })

  const reviewCmd = scriptsDir + '/review-package ' + base + ' HEAD --out ' + reviewDir + '/' + id + '.diff'
  const diffRes = await agent(
    'Run this exact command and return its output path: ' + reviewCmd,
    { model: 'haiku', label: 'review:' + id, phase: 'Review', schema: DIFF_SCHEMA }
  )
  ctx = Object.assign({}, ctx, { diffPath: diffRes ? diffRes.diffPath : null })

  let findings = []
  if (ctx.diffPath) {
    const lenses = await parallel([
      function () { return agent(adversaryPrompt('correctness', ctx.briefPath, ctx.diffPath), { agentType: 'adversary', label: 'adv:correctness:' + id, phase: 'Review', schema: FINDINGS }) },
      function () { return agent(adversaryPrompt('gaming', ctx.briefPath, ctx.diffPath), { agentType: 'adversary', label: 'adv:gaming:' + id, phase: 'Review', schema: FINDINGS }) },
      function () { return agent(adversaryPrompt('slop', ctx.briefPath, ctx.diffPath), { agentType: 'adversary', label: 'adv:slop:' + id, phase: 'Review', schema: FINDINGS }) },
    ])
    findings = lenses.filter(Boolean).reduce(function (acc, f) { return acc.concat(f.findings || []) }, [])
  }

  const localParked = []
  let current = findings.filter(isBlocking)

  for (let round = 1; round <= 5 && current.length > 0; round++) {
    const stronger = round >= 4
    const prompt = 'Task ' + ctx.id + '. Brief: ' + ctx.briefPath + '. Diff: ' + ctx.diffPath +
      '. Fix these adversarial findings: ' + JSON.stringify(current) +
      '. Run the test command: ' + testCmd + '. Return the updated TASK_RESULT.'
    let fixed
    if (stronger) {
      fixed = await agent(prompt, { agentType: 'developer', model: 'opus', label: 'fix:' + ctx.id + ':r' + round, phase: 'Fix', schema: TASK_RESULT })
    } else {
      fixed = await agent(prompt, { agentType: 'developer', label: 'fix:' + ctx.id + ':r' + round, phase: 'Fix', schema: TASK_RESULT })
    }
    if (!fixed) { break }
    ctx = Object.assign({}, ctx, fixed, { id: id, briefPath: ctx.briefPath })
    log('fix round ' + round + ' for task ' + ctx.id + (stronger ? ' (fresh implementer, opus)' : ' (same implementer)'))

    const reReviewCmd = scriptsDir + '/review-package ' + base + ' HEAD --out ' + reviewDir + '/' + ctx.id + '.diff'
    const reReview = await agent(
      'Run this exact command and return its output path: ' + reReviewCmd,
      { model: 'haiku', label: 'review:' + ctx.id + ':r' + round, phase: 'Review', schema: DIFF_SCHEMA }
    )
    const diffPath = reReview ? reReview.diffPath : ctx.diffPath
    ctx = Object.assign({}, ctx, { diffPath: diffPath })

    const relook = await parallel([
      function () { return agent(adversaryPrompt('correctness', ctx.briefPath, diffPath), { agentType: 'adversary', label: 'adv:correctness:' + ctx.id + ':r' + round, phase: 'Review', schema: FINDINGS }) },
      function () { return agent(adversaryPrompt('gaming', ctx.briefPath, diffPath), { agentType: 'adversary', label: 'adv:gaming:' + ctx.id + ':r' + round, phase: 'Review', schema: FINDINGS }) },
      function () { return agent(adversaryPrompt('slop', ctx.briefPath, diffPath), { agentType: 'adversary', label: 'adv:slop:' + ctx.id + ':r' + round, phase: 'Review', schema: FINDINGS }) },
    ])
    current = relook.filter(Boolean).reduce(function (acc, f) { return acc.concat(f.findings || []) }, []).filter(isBlocking)
  }

  for (const finding of current) {
    const ruling = { task: ctx.id, finding: finding, ruling: 'parked', why: 'fix ladder exhausted after 5 rounds without resolving this finding' }
    localParked.push(ruling)
    log('parked: task ' + ctx.id + ' - ' + finding.predicate)
  }

  return {
    result: {
      id: ctx.id,
      redExit: ctx.redExit,
      greenExit: ctx.greenExit,
      refactorPassCount: ctx.refactorPassCount,
      commits: ctx.commits || [],
      files: ctx.files || [],
      notes: ctx.notes || '',
    },
    parked: localParked,
  }
}

// The schedule is fixed once flow-lint has spoken, so it is logged in full
// BEFORE any wave starts running — one line per wave, formatted exactly
// "wave <k>: T002, T003".
const waves = selectWaves(lintWaves, requestedIds)
waves.forEach(function (wave, i) {
  log('wave ' + (i + 1) + ': ' + wave.join(', '))
})

const finalTasks = []
const parked = []

for (let w = 0; w < waves.length; w++) {
  const ready = waves[w]
  const waveResults = await parallel(ready.map(function (id) {
    return function () { return runTask(id) }
  }))
  waveResults.forEach(function (r) {
    if (!r) { return }
    finalTasks.push(r.result)
    r.parked.forEach(function (p) { parked.push(p) })
  })
}

// discovered: out-of-plan work a task's notes flagged along the way, surfaced
// here rather than silently dropped so the caller can append it to TASKS.md as
// new tasks (append-only) or record it in NOTES.md.
const discovered = []
finalTasks.forEach(function (t) {
  if (t && typeof t.notes === 'string' && /out-of-plan/i.test(t.notes)) {
    discovered.push({ task: t.id, note: t.notes })
  }
})

return { tasks: finalTasks, parked: parked, clean: parked.length === 0, waves: waves, discovered: discovered, lintOk: true }
