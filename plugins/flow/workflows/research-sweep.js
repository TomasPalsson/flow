// research-sweep — decompose a question into angles, research and check each,
// then synthesize a cited report. See C11 and WORKFLOW-API.md for the globals
// used below.
export const meta = {
  name: 'research-sweep',
  description: 'Decompose a question into angles, research and check each, then synthesize a cited report',
  whenToUse: 'Use for open research questions needing verified, cited claims',
  phases: [
    { title: 'Angles', detail: 'decompose the question into distinct angles' },
    { title: 'Search', detail: 'one researcher agent per angle gathers claims' },
    { title: 'Check', detail: 'one checker agent per angle refetches load-bearing claims' },
    { title: 'Synthesize', detail: 'one agent writes the cited report' },
  ],
}

const ANGLES_SCHEMA = {
  type: 'object',
  required: ['angles'],
  properties: {
    angles: {
      type: 'array',
      items: {
        type: 'object',
        required: ['key', 'query'],
        properties: { key: { type: 'string' }, query: { type: 'string' } },
      },
    },
  },
}

const RESEARCH_SCHEMA = {
  type: 'object',
  required: ['headline', 'claims'],
  properties: {
    headline: { type: 'string' },
    claims: {
      type: 'array',
      items: {
        type: 'object',
        required: ['claim', 'url', 'date', 'kind'],
        properties: {
          claim: { type: 'string' },
          url: { type: 'string' },
          date: { type: 'string' },
          kind: { type: 'string' },
        },
      },
    },
  },
}

const CHECK_SCHEMA = {
  type: 'object',
  required: ['confirmed', 'unsupported', 'notes'],
  properties: {
    confirmed: { type: 'array', items: { type: 'string' } },
    unsupported: { type: 'array', items: { type: 'string' } },
    notes: { type: 'string' },
  },
}

const question = args.question
const angleCount = (args.angles !== undefined) ? args.angles : 5
const sourcesPerAngle = (args.sourcesPerAngle !== undefined) ? args.sourcesPerAngle : 8

const decomposition = await agent(
  'Decompose this research question into ' + angleCount + ' distinct, non-overlapping angles: ' + question +
  '. Return a short key and a search query for each.',
  { model: 'sonnet', label: 'angles', phase: 'Angles', schema: ANGLES_SCHEMA }
)

const angles = decomposition ? decomposition.angles : []

const results = await pipeline(
  angles,
  function (_prev, a) {
    const prompt = 'Research angle "' + a.key + '" of the question: ' + question +
      '. Query: ' + a.query + '. Use WebSearch/WebFetch to gather up to ' + sourcesPerAngle +
      ' sources. Return a headline and a list of claims, each with claim, url, date, and kind (PRIMARY or SECONDARY).'
    return agent(prompt, { model: 'sonnet', agentType: 'general-purpose', label: 'research:' + a.key, phase: 'Search', schema: RESEARCH_SCHEMA })
      .then(function (r) { return { angle: a, research: r } })
  },
  function (prev) {
    if (!prev || !prev.research) { return prev }
    const claims = prev.research.claims || []
    const prompt = 'Refetch and verify the 4 most load-bearing claims below; report which are confirmed, ' +
      'which are unsupported, and notes. Claims: ' + JSON.stringify(claims)
    return agent(prompt, { model: 'sonnet', label: 'check:' + prev.angle.key, phase: 'Check', schema: CHECK_SCHEMA })
      .then(function (c) { return Object.assign({}, prev, { check: c }) })
  }
)

const usable = results.filter(Boolean)
let confirmedTotal = 0
let unsupportedTotal = 0
usable.forEach(function (r) {
  if (r.check) {
    confirmedTotal += (r.check.confirmed || []).length
    unsupportedTotal += (r.check.unsupported || []).length
  }
})

log('researched ' + usable.length + ' of ' + angles.length + ' angles')

const synthPrompt = 'Synthesize a cited report answering: ' + question +
  '. Every angle\'s claims and check results follow as JSON: ' + JSON.stringify(usable) +
  '. Write a cited report as text with a per-claim confidence note.'

const synthesis = await agent(synthPrompt, { model: 'opus', label: 'synthesize', phase: 'Synthesize' })

return { report: synthesis || '', angles: angles.length, confirmed: confirmedTotal, unsupported: unsupportedTotal }
