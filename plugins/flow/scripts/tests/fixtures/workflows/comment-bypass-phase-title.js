// Fixture: violates rule 4 (phase-title). meta.phases declares only "Real",
// but a commented-out decoy phase entry ("Decoy") sits in the same array. A
// live phase('Decoy') call should fail as undeclared — a lint that extracts
// phase titles from the raw (comment-unaware) phases array text picks up the
// commented decoy title and wrongly passes this file.
export const meta = {
  name: 'comment-bypass-phase-title',
  description: 'Fixture: a commented-out decoy phase title must not satisfy rule 4.',
  phases: [
    { title: 'Real' },
    // { title: 'Decoy' },
  ],
}

phase('Decoy')
const result = await agent('noop', { model: 'sonnet' })
return { result: result }
