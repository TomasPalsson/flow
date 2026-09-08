'use strict';

// lesson/lock.js — D-6 `flow lesson lock <draft-id> --choice block|note|discard`:
// the only writer of a guardrail. One ruling to .specs/LEDGER.md, one receipt
// line out, and the draft is consumed either way.

const fs = require('node:fs');
const path = require('node:path');
const { draftPath } = require('./propose.js');
const { writeFor } = require('./decide.js');
const store = require('./store.js');

const CHOICES = ['block', 'note', 'discard'];

// Every branch also returns how to take the write back off disk: lock stages
// its writes, and the LEDGER append at the end of the sequence is the one that
// can fail on a file the user owns.
function writeGuardrail(sc, draft, wrote) {
  if (wrote === 'rule') {
    const target = store.ruleFile(sc, draft.slug);
    fs.mkdirSync(sc.rulesDir, { recursive: true });
    fs.writeFileSync(target, store.ruleText(draft.rule));
    return { target, action: draft.rule.action, tests: [], restore: () => fs.unlinkSync(target) };
  }
  if (wrote === 'test') {
    const target = draft.test.file;
    if (store.exists(target)) throw new Error(`${path.relative(draft.root, target)} already exists — move it aside or pick another --should`);
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.writeFileSync(target, draft.test.body);
    return { target, action: 'test', tests: [path.relative(draft.root, target)], restore: () => fs.unlinkSync(target) };
  }
  // A script rung lands a note too, but never reports as one: the action, the
  // ruling and the receipt all say `script`, so `list` and the LEDGER keep the
  // rung propose decided instead of flattening it into an ordinary note.
  const script = draft.rung === 'script';
  const target = draft.note.file;
  const fresh = store.read(target) === null;
  store.appendLine(target, draft.note.line, draft.note.header);
  const restore = () => {
    store.removeLines(target, (l) => l === draft.note.line);
    // Only a file this run created, and only while nothing but the header is
    // left in it — a notes file someone else has written to stays.
    if (fresh && store.read(target) === draft.note.header) fs.unlinkSync(target);
  };
  return { target, action: script ? 'script' : 'note', tests: [], restore, kind: script ? 'script-wanted note in' : 'note in' };
}

// The guardrail, the index row and the ruling are three writes, not one
// transaction, so they are staged: if the LEDGER refuses the ruling (read-only,
// or ending inside an open fence) everything already on disk comes back off.
// A guardrail left live behind a command that printed a failure is the worse
// bug — the user retries, and the leftover index row reads as a second
// occurrence, so the recurrence gate promotes a note nobody asked to promote.
function commit(sc, draft, wrote, prior, root, created) {
  const undo = [];
  try {
    const written = writeGuardrail(sc, draft, wrote);
    undo.push(written.restore);
    const shown = wrote === 'test' ? written.tests[0] : store.display(sc, written.target);
    const entry = { slug: draft.slug, rung: draft.rung, wrote, action: written.action, created, file: written.target, tests: written.tests, what: draft.what };
    store.updateIndex(sc, (idx) => idx.filter((e) => e.slug !== draft.slug).concat([entry]));
    undo.push(() => store.updateIndex(sc, (idx) => idx.filter((e) => e.slug !== draft.slug).concat(prior ? [prior] : [])));
    const receipt = written.kind ? `${written.kind} ${shown}` : shown;
    store.appendLedger(root, `Ruling: ${created} ${draft.slug} — ${draft.what} — ${shown} (${written.action})`);
    // Last, and only once the ruling is recorded: the note this lock replaces
    // goes with it — a promoted note's line advertises an undo that now owns
    // the rule, and a re-noted lesson would otherwise stack a near-duplicate
    // line beside the one it restates. The line just written is kept.
    if (prior && prior.wrote === 'note') store.dropNote(sc, prior.file, draft.slug, wrote === 'note' ? draft.note.line : null);
    return { receipt, tests: written.tests };
  } catch (e) {
    while (undo.length) {
      try {
        undo.pop()();
      } catch {
        /* a rollback that fails must not replace the failure being reported */
      }
    }
    throw e;
  }
}

function run(args, flags, root, io, env) {
  const { stdout, stderr } = io;
  const id = args[0];
  if (!id || CHOICES.indexOf(flags.choice) < 0) {
    stderr.write('flow lesson lock: need a draft id and --choice block|note|discard\n  fix: flow lesson lock <draft-id> --choice block\n');
    return 1;
  }
  const file = draftPath(env, id);
  const raw = store.read(file);
  if (raw === null) {
    stderr.write(`flow lesson lock: no draft '${id}'\n  fix: it was locked, discarded or cleared with $TMPDIR — run flow lesson propose again\n`);
    return 1;
  }
  const draft = JSON.parse(raw);
  if (flags.choice === 'discard') {
    fs.unlinkSync(file);
    stdout.write(`flow: lesson discarded — ${draft.what}\n`);
    return 0;
  }

  const sc = store.scope(draft.root || root, draft.global, env);
  const index = store.readIndex(sc);
  const prior = index.find((e) => e.slug === draft.slug);
  if ((prior && prior.wrote !== 'note') || store.exists(store.ruleFile(sc, draft.slug))) {
    stderr.write(`flow lesson lock: '${draft.slug}' is already locked; undo first\n  fix: flow lesson undo ${draft.slug}\n`);
    return 1;
  }

  const wrote = writeFor(draft.rung, flags.choice);
  const created = draft.created || store.today();
  // The receipt names the artefact that landed, not the choice that was made:
  // a note locked with --choice block reports as a note.
  const { receipt, tests } = commit(sc, draft, wrote, prior, draft.root || root, created);
  fs.unlinkSync(file);
  stdout.write(`flow: lesson locked — ${draft.what} (${receipt}, ${tests.length} tests). Undo: flow lesson undo ${draft.slug}\n`);
  return 0;
}

module.exports = { run };
