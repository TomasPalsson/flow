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
  required: ['headline', 'claims', 'queriesRun', 'unknowns'],
  properties: {
    headline: { type: 'string' },
    queriesRun: { type: 'array', items: { type: 'string' } },
    unknowns: { type: 'array', items: { type: 'string' } },
    claims: {
      type: 'array',
      items: {
        type: 'object',
        required: ['claim', 'url', 'date', 'kind'],
        properties: {
          claim: { type: 'string' },
          url: { type: 'string' }, // a URL, or path:line for a claim read from a local file
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
    // paraphrase-only answers: neither confirmed nor unsupported
    unverified: { type: 'array', items: { type: 'string' } },
    upgraded: {
      type: 'array',
      items: {
        type: 'object',
        required: ['claim', 'from', 'to'],
        properties: { claim: { type: 'string' }, from: { type: 'string' }, to: { type: 'string' } },
      },
    },
  },
}

// Queries leave the machine, so they carry the question, not the local context around it.
const SANITIZE_RULE = 'Queries never contain hostnames, IPs, internal file paths, repo or client names, ticket IDs or secrets taken from the local context. ' +
  'Search the error class or the generic concept instead.'
const VERBATIM_RULE = 'Each WebFetch prompt asks for the exact sentences on the page that bear on the claim, quoted verbatim.'

const question = args.question
const angleCount = (args.angles !== undefined) ? args.angles : 5
const sourcesPerAngle = (args.sourcesPerAngle !== undefined) ? args.sourcesPerAngle : 8

// Preflight: without a question the decompose agent would be asked about the text "undefined".
if (!question) {
  return { started: false, reason: 'missing-arg', missing: ['question'], next: 'Workflow({ name: "flow:research-sweep", args: { question: "<the question to research>" } })' }
}

const decomposition = await agent(
  'Decompose this research question into ' + angleCount + ' distinct, non-overlapping angles: ' + question +
  '. Exactly one of those angles has a key starting "against-" and a query that looks for evidence the premise is wrong; the total stays ' + angleCount +
  '. Return a short key and a search query for each. ' + SANITIZE_RULE,
  { model: 'sonnet', label: 'angles', phase: 'Angles', schema: ANGLES_SCHEMA }
)

const angles = decomposition ? (decomposition.angles || []).slice() : []
// A disconfirming angle always runs, even when decompose forgot it or failed.
if (!angles.some(function (a) { return a && String(a.key).indexOf('against-') === 0 })) {
  angles.push({ key: 'against-premise', query: 'evidence that the premise is wrong or the opposite holds: ' + question })
}

const results = await pipeline(
  angles,
  function (_prev, a) {
    const prompt = 'Research angle "' + a.key + '" of the question: ' + question +
      '. Query: ' + a.query + '. Use WebSearch/WebFetch to gather up to ' + sourcesPerAngle +
      ' sources. ' + SANITIZE_RULE + ' ' + VERBATIM_RULE + ' Use Read/Grep/Glob over the repo, node_modules, site-packages and local docs too: these are ' +
      'PRIMARY when they own the claim (the package source over a blog post about it). Each claim names the source that owns it. ' +
      'Return a headline, a list of claims (each with claim, url, date, and kind PRIMARY or SECONDARY; url is a URL, or path:line for a local file), ' +
      'queriesRun (the searches you actually ran, including ones that found nothing), and unknowns (what you looked for and could not find).'
    return agent(prompt, { model: 'sonnet', agentType: 'general-purpose', label: 'research:' + a.key, phase: 'Search', schema: RESEARCH_SCHEMA })
      .then(function (r) { return { angle: a, research: r } })
  },
  function (prev) {
    if (!prev || !prev.research) { return prev }
    const claims = prev.research.claims || []
    const prompt = 'Refetch and verify the 4 most load-bearing claims below (re-read a path:line claim from the file instead of fetching it). ' + VERBATIM_RULE +
      ' A claim is confirmed only when a verbatim sentence or a local path:line read supports it. A WebFetch answer that only paraphrases the page does not confirm the claim ' +
      'and does not refute it: list it under unverified, not unsupported. When a SECONDARY claim has a primary source you find, list it under upgraded as {claim, from, to}. ' +
      'Report confirmed, unsupported, unverified, upgraded, and notes. ' + SANITIZE_RULE + ' Claims: ' + JSON.stringify(claims)
    return agent(prompt, { model: 'sonnet', label: 'check:' + prev.angle.key, phase: 'Check', schema: CHECK_SCHEMA })
      .then(function (c) { return Object.assign({}, prev, { check: c }) })
  }
)

const usable = results.filter(Boolean)
let confirmedTotal = 0
let unsupportedTotal = 0
let unverifiedTotal = 0
usable.forEach(function (r) {
  if (r.check) {
    confirmedTotal += (r.check.confirmed || []).length
    unsupportedTotal += (r.check.unsupported || []).length
    unverifiedTotal += (r.check.unverified || []).length
  }
})

// A null Search result still arrives wrapped as {angle, research: null}, so it counts as researched
// only when research is set. The lists below keep a dead search or check from reading as coverage.
const researchedKeys = usable.filter(function (r) { return r.research }).map(function (r) { return r.angle.key })
const notCovered = angles.map(function (a) { return a.key }).filter(function (k) { return researchedKeys.indexOf(k) < 0 })
const checkFailed = usable.filter(function (r) { return r.research && !r.check }).map(function (r) { return r.angle.key })
const researched = usable.filter(function (r) { return r.research })

log('researched ' + researched.length + ' of ' + angles.length + ' angles (not covered: ' + notCovered.join(',') +
  '; check failed: ' + checkFailed.join(',') + ')')

const synthPrompt = 'Synthesize a cited report answering: ' + question +
  '. Every angle\'s claims and check results follow as JSON: ' + JSON.stringify(researched) +
  '. Write a cited report as text with a per-claim confidence note. Tie each note to the evidence: ' +
  '"confirmed" only when a primary source was read this run; "likely" when the support is secondary or inferred; ' +
  '"unknown" when neither holds. Say which tier each claim reached and why. Claims listed as unverified are at most "likely". ' +
  'End with a gaps section built from the unknowns and queriesRun lists; an empty unknowns list must say why it is empty. ' +
  'The gaps section also lists NOT COVERED angles (their search returned nothing; say the question is unanswered for them): ' + JSON.stringify(notCovered) +
  ' and UNCHECKED angles (searched, but the check returned nothing, so every claim there is at most "likely"): ' + JSON.stringify(checkFailed) + '. ' +
  'When a datum contradicts the majority of sources, report it first. The absence of a mention is not evidence. ' +
  'Include a section "## Evidence against" built from the against- angle; when it found nothing write "none found (searched: <queries>)" naming the queries run.'

const synthesis = await agent(synthPrompt, { model: 'opus', label: 'synthesize', phase: 'Synthesize' })

return { report: synthesis || '', angles: angles.length, confirmed: confirmedTotal, unsupported: unsupportedTotal, unverified: unverifiedTotal, notCovered: notCovered, checkFailed: checkFailed }
