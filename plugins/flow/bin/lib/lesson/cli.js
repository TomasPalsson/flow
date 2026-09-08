'use strict';

// lesson/cli.js — `flow lesson` dispatcher (D-6). Every subcommand returns a
// numeric exit code; nothing here throws at the user.

const propose = require('./propose.js');
const lock = require('./lock.js');
const manage = require('./manage.js');

const HELP = `
flow lesson — turn one mistake into a guardrail (spec 005 D-3/D-6)

Usage:
  flow lesson <subcommand> [options]

Subcommands:
  propose --did <t> --should <t> --input <t> [--json] [--global]
                            Decide the rung (rule | test | script | note) and
                            draft the guardrail. Writes only the draft, under
                            $TMPDIR, and prints its id.
  lock <draft-id> --choice block|note|discard
                            block: write what propose's block field names — the
                            rule, the test, or (note and script rungs, where
                            there is nothing a hook can match) the note.
                            note: write the path-scoped note instead.
                            discard: write nothing and drop the draft.
                            block and note append one Ruling to .specs/LEDGER.md
                            and print the receipt.
  list [--global]           One row per lesson: slug, rung, action, created,
                            hits, enabled.
  undo <slug> [--global]    Delete the rule file, or the note line. For a test
                            lesson: print the file to delete, and stop — flow
                            never deletes code.
  off <slug> [--global]     Set enabled: false in the rule file.
  on <slug> [--global]      Set enabled: true.
  stale [--days 30] [--global]
                            Rules with zero hits that old, or whose pattern
                            matches nothing in the repo.

Options:
  --global   read and write ~/.claude/flow.rules/ instead of this project's
  --json     propose only: print {id, rung, slug, files, preview, block, tests}
             block is what --choice block writes, spelled out for the question

Exit codes:
  0  done
  1  refused (missing argument, unknown draft or lesson, slug already locked)
`;

const BOOLS = ['json', 'global', 'help'];

function parse(argv) {
  const flags = {};
  const args = [];
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a.slice(0, 2) === '--' && BOOLS.indexOf(a.slice(2)) >= 0) flags[a.slice(2)] = true;
    else if (a === '-h') flags.help = true;
    else if (a.slice(0, 2) === '--') flags[a.slice(2)] = argv[++i];
    else args.push(a);
  }
  return { flags, args };
}

function run(argv, root, io, env) {
  const sub = argv[0];
  if (!sub || sub === '--help' || sub === '-h') {
    (sub ? io.stdout : io.stderr).write(HELP);
    return sub ? 0 : 1;
  }
  const { flags, args } = parse(argv.slice(1));
  if (flags.help) {
    io.stdout.write(HELP);
    return 0;
  }
  try {
    if (sub === 'propose') return propose.run(flags, root, io, env);
    if (sub === 'lock') return lock.run(args, flags, root, io, env);
    if (sub === 'list') return manage.list(flags, root, io, env);
    if (sub === 'undo') return manage.undo(args, flags, root, io, env);
    if (sub === 'off') return manage.toggle(false, args, flags, root, io, env);
    if (sub === 'on') return manage.toggle(true, args, flags, root, io, env);
    if (sub === 'stale') return manage.stale(flags, root, io, env);
  } catch (e) {
    io.stderr.write(`flow lesson ${sub}: ${e.message}\n`);
    return 1;
  }
  io.stderr.write(`flow lesson: unknown subcommand '${sub}'\n  fix: flow lesson --help\n`);
  return 1;
}

module.exports = { run };
