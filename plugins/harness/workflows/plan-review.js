// plan-review — attack a spec and plan with adversarial lenses, then adjudicate
// the findings into decisions. See C11 and WORKFLOW-API.md for the globals used
// below.
export const meta = {
  name: 'plan-review',
  description: 'Attack a spec and plan with adversarial lenses, then adjudicate the findings into decisions',
  whenToUse: 'Use before implementation starts to pressure-test a frozen spec and plan',
  phases: [
    { title: 'Attack', detail: 'independent lenses attack the spec and plan' },
    { title: 'Adjudicate', detail: 'one agent merges findings into decisions' },
  ],
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

const DECISIONS = {
  type: 'object',
  required: ['decisions', 'verdict'],
  properties: {
    verdict: { type: 'string' },
    decisions: {
      type: 'array',
      items: {
        type: 'object',
        required: ['finding', 'lenses', 'severity', 'decision'],
        properties: {
          finding: { type: 'string' },
          lenses: { type: 'array', items: { type: 'string' } },
          severity: { type: 'string' },
          decision: { type: 'string' },
          edit: { type: 'string' },
        },
      },
    },
  },
}

const LENSES = ['spec', 'daily-usefulness', 'model-compliance', 'ownership-overlap']

const spec = args.spec
const plan = args.plan
const design = args.design

function lensPrompt(lens) {
  let prompt = 'Adversarial review, lens=' + lens + '. Read ONLY these paths: ' + spec
  if (plan) { prompt += ', ' + plan }
  if (design) { prompt += ', ' + design }
  prompt += '. Attack the spec and plan from this lens only. Return FINDINGS with predicate, severity, scenario, receipt.'
  return prompt
}

const lensResults = await parallel(LENSES.map(function (lens) {
  return function () {
    return agent(lensPrompt(lens), { agentType: 'adversary', label: 'lens:' + lens, phase: 'Attack', schema: FINDINGS })
      .then(function (r) { return { lens: lens, result: r } })
  }
}))

const allFindings = []
lensResults.filter(Boolean).forEach(function (lr) {
  if (!lr.result) { return }
  ;(lr.result.findings || []).forEach(function (f) {
    allFindings.push(Object.assign({}, f, { lens: lr.lens }))
  })
})

log('collected ' + allFindings.length + ' findings across ' + LENSES.length + ' lenses')

const adjPrompt = 'Adjudicate these adversarial findings against the spec' + (plan ? ' and plan' : '') +
  '. Findings follow as JSON: ' + JSON.stringify(allFindings) +
  '. For each, decide KEEP, CHANGE, DROP, or DEFER, listing which lenses raised it, its severity, ' +
  'and (for CHANGE) the edit. Return a verdict summary.'

const adjudication = await agent(adjPrompt, { model: 'opus', label: 'adjudicate', phase: 'Adjudicate', schema: DECISIONS })

return adjudication || { decisions: [], verdict: 'adjudicator returned nothing' }
