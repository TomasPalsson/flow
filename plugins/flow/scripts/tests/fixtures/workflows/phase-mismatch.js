// Fixture: violates rule 4 only (a phase() call title must be in meta.phases).
export const meta = {
  name: 'phase-mismatch',
  description: 'Fixture: a phase() call title is not listed in meta.phases.',
  phases: [{ title: 'Only' }],
}

phase('Different')
const result = await agent('noop', { model: 'sonnet' })
return { result: result }
