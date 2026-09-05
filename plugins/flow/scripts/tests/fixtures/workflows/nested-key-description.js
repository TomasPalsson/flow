// Fixture: violates rule 1 (meta-description). meta has no top-level
// description: key, but a nested phases[].detail object carries a property
// literally named "description" two levels deep. A depth-unaware scan over
// the whole balanced meta object text would wrongly pass this file by
// matching the nested decoy key instead of a real top-level field.
export const meta = {
  name: 'nested-key-description',
  phases: [
    { title: 'Only', detail: { description: 'nested decoy, not the real meta.description' } },
  ],
}

const result = await agent('noop', { model: 'sonnet', phase: 'Only' })
return { result: result }
