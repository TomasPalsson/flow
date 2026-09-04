// Fixture: violates rule 5 only (no non-deterministic time or random calls).
export const meta = {
  name: 'date-now',
  description: 'Fixture: uses Date.now(), which is banned in saved workflows.',
  phases: [{ title: 'Only' }],
}

const stamp = Date.now()
const result = await agent('noop ' + stamp, { model: 'sonnet' })
return { result: result }
