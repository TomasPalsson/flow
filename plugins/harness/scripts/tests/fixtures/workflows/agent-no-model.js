// Fixture: violates rule 7 only (every agent call must set agentType or model).
export const meta = {
  name: 'agent-no-model',
  description: 'Fixture: an agent() call sets neither agentType nor model.',
  phases: [{ title: 'Only' }],
}

const result = await agent('noop', { label: 'noop' })
return { result: result }
