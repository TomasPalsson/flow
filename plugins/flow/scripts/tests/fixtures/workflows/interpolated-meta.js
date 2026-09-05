// Fixture: violates rule 3 only (meta must be a pure literal, no ${...}).
export const meta = {
  name: 'interpolated-meta',
  description: `Fixture: meta uses template interpolation ${1 + 1}, which is banned.`,
  phases: [{ title: 'Only' }],
}

const result = await agent('noop', { model: 'sonnet', phase: 'Only' })
return { result: result }
