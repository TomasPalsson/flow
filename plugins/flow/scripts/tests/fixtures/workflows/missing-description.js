// Fixture: violates rule 1 only (meta must have a real description: key).
// whenToUse mentions the word "description" but there is no description: key
// — a naive substring search over the meta text would wrongly pass this.
export const meta = {
  name: 'missing-description',
  whenToUse: 'this text mentions description word but has no real description key',
  phases: [{ title: 'Only' }],
}

const result = await agent('noop', { model: 'sonnet', phase: 'Only' })
return { result: result }
