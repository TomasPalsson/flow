// build-slices — implement plan slices end to end: brief, developer, review-package,
// two adversary lenses, then a bounded fix ladder. See C11 in the harness spec and
// WORKFLOW-API.md for the globals used below (agent, pipeline, parallel, log, args).
//
// C13 (parallelism): independent slices run in waves, not strictly in order.
// A slice may start once every slice in its Depends-on list has finished and
// none of its Files paths overlap a slice already selected for the current
// wave. Each wave runs concurrently via parallel(); each slice's full chain
// (brief -> implement -> package -> review -> fix ladder) runs inside its own
// thunk, so a slow slice never blocks a fast one in the same wave.
export const meta = {
  name: 'build-slices',
  description: 'Implement plan slices with brief, developer, review-package, adversarial review, and a bounded fix ladder',
  whenToUse: 'Use in Workflow mode to implement one or more slices from a frozen plan end to end',
  phases: [
    { title: 'Brief', detail: 'slice-brief extracts the slice section (and design contract) into a brief file' },
    { title: 'Implement', detail: 'a developer agent implements the slice from the brief only' },
    { title: 'Review', detail: 'review-package builds the diff; two adversary lenses check it' },
    { title: 'Fix', detail: 'bounded fix ladder on fatal/significant findings, then a recorded ruling' },
  ],
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

// Stage 0 (C13): when the caller does not already know slice dependencies
// and file ownership, one haiku agent reads the plan (and design, if given)
// per the C7 grammar and returns them. The workflow never assumes
// independence silently.
const STAGE0_SCHEMA = {
  type: 'object',
  required: ['deps', 'files'],
  properties: {
    deps: { type: 'object' },
    files: { type: 'object' },
  },
}

const SLICE_RESULT = {
  type: 'object',
  required: ['id', 'redExit', 'greenExit', 'refactorPassCount', 'commits', 'files', 'notes'],
  properties: {
    id: { type: 'number' },
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

function filesOverlap(a, b) {
  for (let i = 0; i < a.length; i++) {
    if (b.indexOf(a[i]) !== -1) { return true }
  }
  return false
}

// computeWave picks the next batch of slices that may run concurrently: every
// Depends-on id is already done, and no two picks in this batch share a Files
// path with each other (a slice whose files overlap an already-picked slice
// waits for the next wave instead).
function computeWave(pending, done, depsMap, filesMap) {
  const ready = []
  const readyFiles = []
  for (let i = 0; i < pending.length; i++) {
    const id = pending[i]
    // Stage 0 (haiku, schema-enforced only down to {type:'object'}) may
    // return dependency ids as strings (JSON object keys are always
    // strings, and models often mirror that in adjacent array values,
    // e.g. {"deps":{"2":["1"]}}). `pending`/`done` always hold the numeric
    // slice ids from args.slices, so normalise each dependency id to a
    // number before comparing against `done` — otherwise done.has(d)
    // never matches and every downstream slice gets forced into its own
    // wave by the cycle-detection safety valve below (C13).
    const need = (depsMap[id] || []).map(function (d) { return Number(d) })
    const depsOk = need.every(function (d) { return done.has(d) })
    if (!depsOk) { continue }
    const myFiles = filesMap[id] || []
    let overlap = false
    for (let j = 0; j < readyFiles.length; j++) {
      if (filesOverlap(myFiles, readyFiles[j])) { overlap = true; break }
    }
    if (overlap) { continue }
    ready.push(id)
    readyFiles.push(myFiles)
  }
  return ready
}

// computeAllWaves simulates the whole run (depsMap/filesMap are static, so no
// agent output can change the outcome) to produce every wave up front, so the
// caller can log() the full schedule before starting any agent in it.
function computeAllWaves(sliceNumbers, depsMap, filesMap) {
  const pending = sliceNumbers.slice()
  const done = new Set()
  const waves = []
  while (pending.length > 0) {
    let ready = computeWave(pending, done, depsMap, filesMap)
    if (ready.length === 0) {
      // Safety valve only: malformed deps (e.g. a cycle, or a Depends-on that
      // never resolves) must never hang the workflow. Force the first pending
      // slice into its own wave and record why.
      ready = [pending[0]]
      log('warning: no slice became ready for wave ' + (waves.length + 1) + '; forcing slice ' + pending[0] + ' (check Depends-on for a cycle or missing id)')
    }
    waves.push(ready.slice())
    ready.forEach(function (id) {
      done.add(id)
      const i = pending.indexOf(id)
      if (i !== -1) { pending.splice(i, 1) }
    })
  }
  return waves
}

const plan = args.plan
const design = args.design
const base = args.base
const testCmd = args.testCmd
const sliceNumbers = args.slices
const scriptsDir = args.scriptsDir || '$HOME/.claude/scripts'

// Stage 0 (C13): the workflow receives deps/files when the caller already
// knows them; when either is absent it never assumes independence silently
// — one haiku agent reads the plan (and design, if given) per the C7 grammar
// and returns them instead.
let depsMap = args.deps
let filesMap = args.files
if (depsMap === undefined || filesMap === undefined) {
  let stage0Prompt = 'Read the plan file at ' + plan
  if (design) { stage0Prompt += ' and the design file at ' + design }
  stage0Prompt += '. Per the C7 plan grammar, for slices ' + JSON.stringify(sliceNumbers) +
    ' extract each slice\'s "- **Depends-on**:" ids and "- **Files**:" paths. Return an object ' +
    'with "deps" and "files", each keyed by slice id (as a string): deps.<id> is the array of ' +
    'slice ids that slice depends on (empty array when Depends-on is absent); files.<id> is the ' +
    'array of file paths that slice owns (empty array when Files is absent).'
  const stage0Res = await agent(stage0Prompt, {
    model: 'haiku',
    agentType: 'general-purpose',
    label: 'discover-deps-files',
    phase: 'Brief',
    schema: STAGE0_SCHEMA,
  })
  if (depsMap === undefined) { depsMap = (stage0Res && stage0Res.deps) || {} }
  if (filesMap === undefined) { filesMap = (stage0Res && stage0Res.files) || {} }
}
depsMap = depsMap || {}
filesMap = filesMap || {}

// runSlice carries one slice through its full chain (brief -> implement ->
// package -> review -> fix ladder) inside a single thunk, so it can be handed
// to parallel() alongside every other slice in its wave without any of them
// blocking on each other.
async function runSlice(id) {
  let briefCmd = scriptsDir + '/slice-brief ' + plan + ' ' + id
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

  const implementPrompt = 'Implement slice ' + id + ' by reading ONLY the brief at ' + briefPath +
    ' and the files it names. Follow RED/GREEN/REFACTOR from the brief. Run the test command: ' +
    testCmd + '. Return the SLICE_RESULT.'
  const implRes = await agent(implementPrompt, { agentType: 'developer', label: 'implement:' + id, phase: 'Implement', schema: SLICE_RESULT })
  if (!implRes) {
    return {
      result: { id: id, redExit: null, greenExit: null, refactorPassCount: 0, commits: [], files: [], notes: 'implement failed' },
      parked: [],
    }
  }
  let ctx = Object.assign({}, implRes, { briefPath: briefPath })

  const reviewCmd = scriptsDir + '/review-package ' + base + ' HEAD --out .claude/review/slice-' + id + '.diff'
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
    ])
    findings = lenses.filter(Boolean).reduce(function (acc, f) { return acc.concat(f.findings || []) }, [])
  }

  const localParked = []
  let current = findings.filter(isBlocking)

  for (let round = 1; round <= 5 && current.length > 0; round++) {
    const stronger = round >= 4
    const prompt = 'Slice ' + ctx.id + '. Brief: ' + ctx.briefPath + '. Diff: ' + ctx.diffPath +
      '. Fix these adversarial findings: ' + JSON.stringify(current) +
      '. Run the test command: ' + testCmd + '. Return the updated SLICE_RESULT.'
    let fixed
    if (stronger) {
      fixed = await agent(prompt, { agentType: 'developer', model: 'opus', label: 'fix:' + ctx.id + ':r' + round, phase: 'Fix', schema: SLICE_RESULT })
    } else {
      fixed = await agent(prompt, { agentType: 'developer', label: 'fix:' + ctx.id + ':r' + round, phase: 'Fix', schema: SLICE_RESULT })
    }
    if (!fixed) { break }
    ctx = Object.assign({}, ctx, fixed, { briefPath: ctx.briefPath })
    log('fix round ' + round + ' for slice ' + ctx.id + (stronger ? ' (fresh implementer, opus)' : ' (same implementer)'))

    const reReviewCmd = scriptsDir + '/review-package ' + base + ' HEAD --out .claude/review/slice-' + ctx.id + '.diff'
    const reReview = await agent(
      'Run this exact command and return its output path: ' + reReviewCmd,
      { model: 'haiku', label: 'review:' + ctx.id + ':r' + round, phase: 'Review', schema: DIFF_SCHEMA }
    )
    const diffPath = reReview ? reReview.diffPath : ctx.diffPath
    ctx = Object.assign({}, ctx, { diffPath: diffPath })

    const relook = await parallel([
      function () { return agent(adversaryPrompt('correctness', ctx.briefPath, diffPath), { agentType: 'adversary', label: 'adv:correctness:' + ctx.id + ':r' + round, phase: 'Review', schema: FINDINGS }) },
      function () { return agent(adversaryPrompt('gaming', ctx.briefPath, diffPath), { agentType: 'adversary', label: 'adv:gaming:' + ctx.id + ':r' + round, phase: 'Review', schema: FINDINGS }) },
    ])
    current = relook.filter(Boolean).reduce(function (acc, f) { return acc.concat(f.findings || []) }, []).filter(isBlocking)
  }

  for (const finding of current) {
    const ruling = { slice: ctx.id, finding: finding, ruling: 'parked', why: 'fix ladder exhausted after 5 rounds without resolving this finding' }
    localParked.push(ruling)
    log('parked: slice ' + ctx.id + ' - ' + finding.predicate)
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

// The full wave schedule is deterministic once depsMap/filesMap are known
// (stage 0 above, or the caller's args), so it is computed and logged in
// full BEFORE any wave starts running — one line per wave, formatted exactly
// "wave <k>: Slice A, Slice B" (C13/C17).
const waves = computeAllWaves(sliceNumbers, depsMap, filesMap)
waves.forEach(function (wave, i) {
  log('wave ' + (i + 1) + ': ' + wave.map(function (id) { return 'Slice ' + id }).join(', '))
})

const finalSlices = []
const parked = []

for (let w = 0; w < waves.length; w++) {
  const ready = waves[w]
  const waveResults = await parallel(ready.map(function (id) {
    return function () { return runSlice(id) }
  }))
  waveResults.forEach(function (r) {
    if (!r) { return }
    finalSlices.push(r.result)
    r.parked.forEach(function (p) { parked.push(p) })
  })
}

// discovered (C17): out-of-plan work a slice's notes flagged along the way,
// surfaced here rather than silently dropped so the caller can route it into
// the plan's Discovered section.
const discovered = []
finalSlices.forEach(function (s) {
  if (s && typeof s.notes === 'string' && /out-of-plan/i.test(s.notes)) {
    discovered.push({ slice: s.id, note: s.notes })
  }
})

return { slices: finalSlices, parked: parked, clean: parked.length === 0, waves: waves, discovered: discovered }
