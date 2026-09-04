// Fixture: violates rule 9 only (C13: a build-slices.js must schedule
// independent slices via parallel()). This file is otherwise C11-clean
// (meta.name matches its own filename stem, "build-slices") but it never
// calls parallel() anywhere, so it cannot express wave-based concurrent
// slice scheduling.
export const meta = {
  name: 'build-slices',
  description: 'Fixture: a build-slices.js with no parallel() call must fail rule 9.',
  phases: [{ title: 'Only' }],
}

phase('Only')
const result = await agent('noop', { model: 'sonnet' })
return { result: result }
