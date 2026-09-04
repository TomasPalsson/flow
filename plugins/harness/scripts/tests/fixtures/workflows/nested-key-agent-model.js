// Fixture: violates rule 7 (agent-model). The agent() call's options object
// sets no top-level agentType:/model:, but its schema object nests a property
// literally named "model" two levels deep. A depth-unaware scan over the
// whole balanced options object text would wrongly pass this file by
// matching the nested decoy key instead of a real top-level field.
export const meta = {
  name: 'nested-key-agent-model',
  description: 'Fixture: a nested schema property named model must not satisfy rule 7.',
  phases: [{ title: 'Only' }],
}

const result = await agent('noop', {
  label: 'noop',
  schema: { type: 'object', required: ['result'], properties: { model: { type: 'string' } } },
})
return { result: result }
