export const meta = {
  name: 'harness-idiot-proof-build',
  description: 'Build spec 003: fix the audited harness bugs and add fail-loud invariants across 12 owned slices with adversarial review and a fix ladder',
  phases: [
    { title: 'G1 hookout', detail: 'shared helpers every other slice calls' },
    { title: 'Wave 2', detail: 'G2 G3 G4 G6 G9 G10 G11 G12 in parallel, each: develop → adversary → fix (≤2 rounds)' },
    { title: 'G8 stop-gate', detail: 'depends on G1, G4, G9' },
    { title: 'Integration', detail: 'suites, doctor, field re-probe on 3 repos' },
  ],
}

const ROOT = '/home/tomas/Desktop/Projects/flow/.claude/worktrees/bridge-cse_01UeHtGEcYPu5vTrSPb3uNPp'
const SPEC = `${ROOT}/.specs/003-harness-idiot-proof/spec.md`

const DEV_SCHEMA = {
  type: 'object',
  properties: {
    slice: { type: 'string' },
    files_changed: { type: 'array', items: { type: 'string' } },
    tests_added: { type: 'array', items: { type: 'string' } },
    hooks_suite: { type: 'string', description: 'the exact "N passed, M failed" line from hooks/tests/run.sh' },
    scripts_suite: { type: 'string', description: 'the exact "N passed, M failed" line from scripts/tests/run.sh' },
    failures_outside_my_files: { type: 'array', items: { type: 'string' } },
    not_done: { type: 'array', items: { type: 'string' } },
    notes: { type: 'string' },
  },
  required: ['slice', 'files_changed', 'tests_added', 'hooks_suite', 'scripts_suite', 'failures_outside_my_files', 'not_done'],
}
const REVIEW_SCHEMA = {
  type: 'object',
  properties: {
    verdict: { type: 'string', enum: ['PASS', 'FIX'] },
    findings: { type: 'array', items: { type: 'object', properties: {
      severity: { type: 'string', enum: ['fatal', 'significant', 'improvable'] },
      file_line: { type: 'string' }, summary: { type: 'string' }, receipt: { type: 'string' }, required_fix: { type: 'string' } },
      required: ['severity', 'file_line', 'summary', 'receipt', 'required_fix'] } },
    suites_rerun: { type: 'string' },
  },
  required: ['verdict', 'findings', 'suites_rerun'],
}

const SLICES = [
  { id: 'G2', title: 'git-guard', model: 'opus' },
  { id: 'G3', title: 'post-bash-write', model: 'sonnet' },
  { id: 'G4', title: 'post-edit hooks (format-lint, size-guard, tamper-notice)', model: 'opus' },
  { id: 'G6', title: 'session-context', model: 'sonnet' },
  { id: 'G9', title: 'shared gate scripts (check-all, test-changed, detect-project, diff-scope)', model: 'opus' },
  { id: 'G10', title: 'flow CLI (next, init, doctor, install, off/on, tutorial)', model: 'opus' },
  { id: 'G11', title: 'scripts (new-spec, slice-overlap, workflow-lint)', model: 'sonnet' },
  { id: 'G12', title: 'registrations and dead hooks', model: 'sonnet' },
]

const devPrompt = (s, prior) => `You are the developer for slice ${s.id} — ${s.title}. Read ${SPEC} in full: the "Rules for every slice", the "Shared contracts", and your slice's section. Implement your slice completely: every bullet, every listed test, red-then-green. You may ONLY edit the files your slice owns. ${prior ? `Slice G1 (hookout) has already landed; its helpers are available in plugins/flow/hooks/lib/hookout.sh — read that file first and use the C-A helpers instead of re-implementing them.` : ''}${s.id === 'G8' ? ' Slices G1, G4 and G9 have landed: read hookout.sh, the new check-all/test-changed --json contracts (run them with --help and on a fixture), and the current test_quality.sh before you start.' : ''} Work in ${ROOT} only. Run both suites before you report and paste the summary lines verbatim; do not report green if anything in your files is red. Return the structured report.`

const reviewPrompt = (s, report) => `Adversarial review of slice ${s.id} — ${s.title}. Spec: ${SPEC} (the slice section + Shared contracts + Rules). Developer report: ${JSON.stringify(report)}. In ${ROOT}: run \`git diff --stat\` and \`git status --short\` to see every change; confirm the developer touched ONLY the files the slice owns (any other file changed is a FIX finding unless a parallel slice owns it — check the ownership lists). Re-run \`bash plugins/flow/hooks/tests/run.sh\` and \`bash plugins/flow/scripts/tests/run.sh\` yourself and report the summary lines. Then attack the implementation: run the hooks/scripts with synthesized payloads against the exact scenarios the spec lists and at least 5 adversarial variants of your own (quoting, spaces in paths, symlinks, worktree .git file, missing tools, empty input). Check for test weakening (deleted/loosened assertions), banned bash constructs, and any message that blocks without naming its escape hatch. Verdict PASS only if every spec bullet is implemented and every probe behaves per contract; otherwise FIX with concrete required_fix per finding. Do not edit files.`

const fixPrompt = (s, review, round) => `Fix round ${round} for slice ${s.id} — ${s.title}. Spec: ${SPEC}. The adversary returned FIX with these findings: ${JSON.stringify(review.findings)}. Address every finding (or explain in not_done why a finding is wrong, with a receipt). Only your slice's files. Re-run both suites; paste summary lines. Return the structured report.`

async function buildSlice(s, prior) {
  let report = await agent(devPrompt(s, prior), { label: `dev:${s.id}`, phase: s.id === 'G8' ? 'G8 stop-gate' : (s.id === 'G1' ? 'G1 hookout' : 'Wave 2'), schema: DEV_SCHEMA, agentType: 'developer', model: s.model, effort: 'high' })
  if (!report) return { slice: s.id, status: 'dev-failed' }
  let review = null
  for (let round = 1; round <= 2; round++) {
    review = await agent(reviewPrompt(s, report), { label: `review:${s.id}#${round}`, phase: s.id === 'G8' ? 'G8 stop-gate' : (s.id === 'G1' ? 'G1 hookout' : 'Wave 2'), schema: REVIEW_SCHEMA, agentType: 'adversary', model: 'opus', effort: 'high' })
    if (!review || review.verdict === 'PASS') break
    const fixModel = round === 1 ? s.model : 'opus'
    report = await agent(fixPrompt(s, review, round), { label: `fix:${s.id}#${round}`, phase: s.id === 'G8' ? 'G8 stop-gate' : (s.id === 'G1' ? 'G1 hookout' : 'Wave 2'), schema: DEV_SCHEMA, agentType: 'developer', model: fixModel, effort: 'high' }) || report
  }
  return { slice: s.id, status: review ? review.verdict : 'no-review', report, review }
}

phase('G1 hookout')
const g1 = await buildSlice({ id: 'G1', title: 'hookout core', model: 'opus' }, false)
log(`G1 ${g1.status}: ${g1.report?.hooks_suite} / ${g1.report?.scripts_suite}`)

phase('Wave 2')
const wave2 = await parallel(SLICES.map(s => () => buildSlice(s, true)))
for (const r of wave2.filter(Boolean)) log(`${r.slice} ${r.status}: ${r.report?.hooks_suite} / ${r.report?.scripts_suite}; not_done=${(r.report?.not_done || []).length}`)

phase('G8 stop-gate')
const g8 = await buildSlice({ id: 'G8', title: 'stop-gate + spec-gate', model: 'opus' }, true)
log(`G8 ${g8.status}: ${g8.report?.hooks_suite} / ${g8.report?.scripts_suite}`)

phase('Integration')
const all = [g1, ...wave2.filter(Boolean), g8]
const integration = await agent(`You are slice G13 — integration — for spec ${SPEC} (read the Rules, contracts, and the G13 section). Every other slice has landed in ${ROOT}. Their reports: ${JSON.stringify(all.map(r => ({ slice: r.slice, status: r.status, not_done: r.report?.not_done, failures_outside: r.report?.failures_outside_my_files, open_findings: r.review?.verdict === 'FIX' ? r.review.findings : [] })))}. Do everything G13 lists: make both suites fully green (fix cross-slice breakage and any open findings above; never weaken a test), run shellcheck/portability, flow doctor, flow --help, then the three field re-probes with throwaway worktrees (remove them after and verify \`git worktree list\` in each real repo shows none). Also run \`git diff --stat\` at the end. Return: the two final suite summary lines, the doctor summary line, the re-probe receipts (command + output per check per repo), a list of everything still open, and the diff stat.`, { label: 'integration:G13', phase: 'Integration', agentType: 'developer', model: 'opus', effort: 'high' })

return { slices: all.map(r => ({ slice: r.slice, status: r.status, not_done: r.report?.not_done || [] })), integration }