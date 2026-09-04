// Fixture: violates rule 2 only (meta.name must equal the filename stem).
export const meta = {
  name: 'wrong-name',
  description: 'Fixture: meta.name does not equal the filename stem.',
  phases: [{ title: 'Only' }],
}

const result = await agent('noop', { model: 'sonnet', phase: 'Only' })
return { result: result }
