'use strict';

// lesson/propose.js — D-6 `flow lesson propose`: decide the rung, draft the
// guardrail, write NOTHING permanent. The draft lands in $TMPDIR so the one
// question the skill asks is about a file that already exists.

const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { detectRunner, rungFor, slugify, writeFor } = require('./decide.js');
const { noteDraft, ruleSpec, testDraft } = require('./draft.js');
const store = require('./store.js');

function draftPath(env, id) {
  return path.join(env.TMPDIR || os.tmpdir(), `flow-lesson-${id}.json`);
}

function oneLine(s) {
  return String(s || '').replace(/\s+/g, ' ').trim();
}

// What `lock --choice block` will actually write for THIS draft — the
// artefact, the file it lands in, and what it does once it is there. The skill
// puts this on the option label verbatim (D-2c), so a draft that can only be
// recorded never offers to enforce anything: `block` on a note or script rung
// writes a note, and says a note.
// `promoted` is D-3's recurrence gate, and it is disclosed here rather than
// sprung at lock time: the user is told a rule will be installed while the
// question is still open, and can still answer "Just note it".
function blockLabel(sc, draft, promoted) {
  const wrote = writeFor(draft.rung, 'block');
  if (wrote === 'rule') {
    const rule = `${draft.rule.preview} — the rule ${store.display(sc, store.ruleFile(sc, draft.slug))}`;
    return promoted ? `this is the second time — a rule will be installed: ${rule}` : rule;
  }
  if (wrote === 'test') return `${draft.preview} — a failing test to finish, not a hook`;
  const where = store.display(sc, draft.note.file);
  return draft.rung === 'script'
    ? `a script-wanted note in ${where} — names the bookkeeping to automate, not enforced`
    : `a note in ${where} — recorded, not enforced`;
}

function build(sc, root, flags, lines, promoted) {
  const { did, should, input } = lines;
  const slug = slugify(should);
  const runner = detectRunner(root);
  // D-3's recurrence gate: a slug that was only noted last time comes back as
  // a rule. Deciding it here — not in lock — is what keeps the promotion
  // visible on the block label instead of overriding the user's answer.
  const rung = promoted ? 'rule' : rungFor(`${did} ${should} ${input}`, input, runner);
  const created = store.today();
  const draft = {
    id: crypto.randomBytes(4).toString('hex'),
    slug,
    rung,
    global: !!flags.global,
    root,
    did,
    should,
    input,
    what: should,
    created,
    rule: ruleSpec(input, did, should, slug, created),
    note: noteDraft(sc, input, did, should, slug, rung),
    test: rung === 'test' ? testDraft(root, runner, slug, did, should, input) : null,
  };
  if (rung === 'rule') {
    draft.files = [store.display(sc, store.ruleFile(sc, slug))];
    draft.preview = draft.rule.preview;
    draft.tests = [];
  } else if (rung === 'test') {
    draft.files = [path.relative(root, draft.test.file)];
    draft.preview = `a red ${runner.kind} test at ${draft.files[0]}`;
    draft.tests = draft.files.slice();
  } else {
    draft.files = [store.display(sc, draft.note.file)];
    draft.preview = draft.note.preview;
    draft.tests = [];
  }
  draft.block = blockLabel(sc, draft, promoted);
  return draft;
}

function run(flags, root, io, env) {
  const { stdout, stderr } = io;
  const lines = { did: oneLine(flags.did), should: oneLine(flags.should), input: oneLine(flags.input) };
  if (!lines.did || !lines.should || !lines.input) {
    stderr.write(
      'flow lesson propose: --did, --should and --input are all required\n' +
        '  fix: flow lesson propose --did "<what I did>" --should "<what I should have done>" --input "<the command, path or observation>"\n'
    );
    return 1;
  }
  const sc = store.scope(root, flags.global, env);
  const slug = slugify(lines.should);
  const prior = store.readIndex(sc).find((e) => e.slug === slug);
  if ((prior && prior.wrote !== 'note') || store.exists(store.ruleFile(sc, slug))) {
    stderr.write(`flow lesson propose: '${slug}' is already locked; undo first\n  fix: flow lesson undo ${slug}\n`);
    return 1;
  }

  const draft = build(sc, root, flags, lines, !!prior);
  fs.writeFileSync(draftPath(env, draft.id), `${JSON.stringify(draft, null, 2)}\n`);
  const summary = { id: draft.id, rung: draft.rung, slug, files: draft.files, preview: draft.preview, block: draft.block, tests: draft.tests };
  if (flags.json) {
    stdout.write(`${JSON.stringify(summary, null, 2)}\n`);
  } else {
    stdout.write(
      `flow lesson: rung ${draft.rung} — ${slug}\n` +
        `  block    ${draft.block}\n` +
        `  note     ${draft.note.preview}\n` +
        `  discard  nothing is written\n` +
        `  next: flow lesson lock ${draft.id} --choice block|note|discard\n`
    );
  }
  return 0;
}

module.exports = { run, draftPath };
