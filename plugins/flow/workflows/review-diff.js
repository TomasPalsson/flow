// review-diff — package a diff, review it through independent lenses, and re-score
// every finding blind against fixed anchors before keeping it. See C11 and
// WORKFLOW-API.md for the globals used below.
export const meta = {
  name: 'review-diff',
  description: 'Package a diff, review it through independent lenses, and re-score every finding blind',
  whenToUse: 'Use to review a range of commits before merge with independently re-scored findings',
  phases: [
    { title: 'Package', detail: 'review-package builds the diff for base..head' },
    { title: 'Find', detail: 'independent lenses read the diff for real issues' },
    { title: 'Score', detail: 'each unique finding is re-scored 0-100 against fixed anchors' },
  ],
}

const DIFF_SCHEMA = {
  type: 'object',
  required: ['diffPath'],
  properties: { diffPath: { type: 'string' } },
}

const LENS_FINDINGS = {
  type: 'object',
  required: ['findings'],
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object',
        required: ['predicate', 'severity', 'file', 'line', 'scenario', 'receipt'],
        properties: {
          predicate: { type: 'string' },
          severity: { type: 'string' },
          file: { type: 'string' },
          line: { type: 'number' },
          scenario: { type: 'string' },
          receipt: { type: 'string' },
        },
      },
    },
  },
}

const SCORE_SCHEMA = {
  type: 'object',
  required: ['score'],
  properties: { score: { type: 'number' }, why: { type: 'string' } },
}

function dedupeKey(f) {
  const pred = (f.predicate || '').slice(0, 40)
  return (f.file || '') + ':' + (f.line || '') + ':' + pred
}

const base = args.base
const head = args.head || 'HEAD'
const lenses = args.lenses || ['correctness', 'security', 'gaming', 'cross-file', 'slop']
const threshold = (args.threshold !== undefined) ? args.threshold : 80
const reviewMd = args.reviewMd
const scriptsDir = args.scriptsDir || '$HOME/.claude/scripts'

const packageCmd = scriptsDir + '/review-package ' + base + ' ' + head
const packaged = await agent(
  'Run this exact command and return its output path: ' + packageCmd,
  { model: 'haiku', label: 'package', phase: 'Package', schema: DIFF_SCHEMA }
)
const diffPath = packaged ? packaged.diffPath : null

if (!diffPath) {
  log('review-package produced no diff path; stopping')
  return { verified: [], dropped: 0, diffPath: null }
}

const lensResults = await parallel(lenses.map(function (lens) {
  return function () {
    let prompt = 'Lens=' + lens + '. Read the diff at ' + diffPath + '. Find real issues from this lens only.'
    if (reviewMd) { prompt += ' Also read the review guide at ' + reviewMd + '.' }
    prompt += ' Return findings with predicate, severity, file, line, scenario, receipt for each.'
    return agent(prompt, { agentType: 'adversary', label: 'lens:' + lens, phase: 'Find', schema: LENS_FINDINGS })
  }
}))

const rawFindings = []
lensResults.forEach(function (r, i) {
  if (!r) { return }
  ;(r.findings || []).forEach(function (f) {
    rawFindings.push(Object.assign({}, f, { lens: lenses[i] }))
  })
})

const seen = {}
const unique = []
rawFindings.forEach(function (f) {
  const key = dedupeKey(f)
  if (seen[key]) { return }
  seen[key] = true
  unique.push(f)
})

log('found ' + rawFindings.length + ' raw findings, ' + unique.length + ' unique after dedupe')

const anchors = '0 = not a real issue; 25 = style or preference; 50 = plausible, unverified; ' +
  '75 = verified real, low impact; 100 = verified real, correctness or security impact.'

const scored = await parallel(unique.map(function (f) {
  return function () {
    const prompt = 'Re-score this finding from 0-100 against these fixed anchors: ' + anchors +
      ' Re-open and read the diff yourself at ' + diffPath + '. Finding: ' + JSON.stringify(f) + '.'
    return agent(prompt, { model: 'sonnet', label: 'score:' + dedupeKey(f), phase: 'Score', schema: SCORE_SCHEMA })
      .then(function (s) { return Object.assign({}, f, { score: s ? s.score : 0 }) })
  }
}))

const verified = scored.filter(Boolean).filter(function (f) { return f.score >= threshold })
const dropped = unique.length - verified.length

log(dropped + ' of ' + unique.length + ' unique findings dropped below threshold ' + threshold)

return { verified: verified, dropped: dropped, diffPath: diffPath }
