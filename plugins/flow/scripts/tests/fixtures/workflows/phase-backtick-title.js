// Fixture: violates rule 4 (phase-title). The phase() call's title is
// written as a template literal (backtick) instead of a plain quoted string,
// and that title is not declared in meta.phases. A linter that only matches
// plain-quoted phase() titles (skipping backtick-quoted ones) would silently
// pass this file instead of failing closed on a title it cannot verify.
export const meta = {
  name: 'phase-backtick-title',
  description: 'Fixture: a phase() call title written as a template literal must not skip rule 4.',
  phases: [{ title: 'Declared' }],
}

phase(`NotDeclared`)
const result = await agent('noop', { model: 'sonnet', phase: 'Declared' })
return { result: result }
