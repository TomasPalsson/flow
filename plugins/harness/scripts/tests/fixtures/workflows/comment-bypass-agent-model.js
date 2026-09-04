// Fixture: violates rule 7 (agent-model). A block comment placed inside the
// agent() call's argument list holds a decoy options object that DOES set
// agentType, but it is only a comment — the real (uncommented) options
// object sets neither agentType nor model. A lint that scans the raw
// (comment-unaware) argument text for "the first {...}" picks up the decoy
// and wrongly passes this file.
export const meta = {
  name: 'comment-bypass-agent-model',
  description: 'Fixture: a commented-out decoy options object must not satisfy rule 7.',
  phases: [{ title: 'Only' }],
}

phase('Only')
const result = await agent('noop', /* { agentType: 'developer' } */ { label: 'no-model-here' })
return { result: result }
