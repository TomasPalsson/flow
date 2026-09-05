// Fixture: violates rule 1 (meta-description). The only description: field
// in this file is commented out; there is no real description: key
// anywhere. A lint whose string-stripping pass blanks quoted string
// interiors but never blanks comment text would still see the commented
// "description:" token and wrongly pass this file.
export const meta = {
  name: 'comment-bypass-description',
  // description: 'this is commented out and not a real field'
  phases: [{ title: 'Only' }],
}

phase('Only')
const result = await agent('noop', { model: 'sonnet' })
return { result: result }
