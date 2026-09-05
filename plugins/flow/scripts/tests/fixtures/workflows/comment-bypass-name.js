// Fixture: violates rule 2 (meta-name). A commented-out, correct name: line
// sits above the real (wrong) name: line — an ordinary edit artifact from
// renaming a workflow file. A lint that takes the first source-order match
// for name: (comment-unaware) picks up the commented, correct value and
// wrongly passes this file even though the real meta.name does not equal
// the filename stem.
export const meta = {
  // name: 'comment-bypass-name'
  name: 'totally-wrong-name',
  description: 'Fixture: a commented-out correct name must not shadow the real, wrong one.',
  phases: [{ title: 'Only' }],
}

phase('Only')
const result = await agent('noop', { model: 'sonnet' })
return { result: result }
