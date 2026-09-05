// Fixture: violates rule 6 only (no TypeScript syntax). The banned pattern
// lives in a comment so the file still parses as plain JavaScript.
export const meta = {
  name: 'typescript',
  description: 'Fixture: source text contains a TypeScript-looking annotation.',
  phases: [{ title: 'Only' }],
}

// legacy signature used to read (name: string) before this was ported to JS
const result = await agent('noop', { model: 'sonnet' })
return { result: result }
