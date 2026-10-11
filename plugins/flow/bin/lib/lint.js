'use strict';

// lint.js — `flow lint [<TASKS.md>] [--json] [--waves]`, a pass-through to
// scripts/flow-lint so the grammar has exactly one implementation, plus one
// check that needs the feature's verify/ directory: an unattended
// `Verified: <date> ... (pre-approved: /flow:next --finish)` line dated on or
// after CLAIM_CHECK_FROM must be backed by verify/claim-check.md with no
// unsupported claims (next/SKILL.md §Finish rule 5). Older lines stay clean so
// features finished before this check existed do not turn into errors.
//
// A second check of the same kind covers the newest PASS-<sha>.md: dated on or
// after PASS_EXECUTED_FROM it must carry the Executed column and a `Not
// checked:` line, and no test row may show Executed 0 (next/SKILL.md §Gates).
// Older PASS files stay clean for the same reason.
//
// A third check reads the Command cell of verify/acceptance.md and of that same
// PASS file: a command that pipes without `set -o pipefail` or PIPESTATUS
// reports the last stage's exit code, so the recorded Exit column proves
// nothing (next/SKILL.md §Gates). Files dated before PIPE_FROM stay clean.

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const { pluginScript } = require('./router.js');

const CLAIM_CHECK_FROM = '2026-10-09';
const RULE = 'claim-check-missing';
const PASS_EXECUTED_FROM = '2026-10-12';
const PIPE_FROM = '2026-10-13';

// The feature dir is the directory of the TASKS.md flow-lint resolved, so a
// stealth store (.specs symlinked elsewhere) needs no special case: verify/
// sits beside TASKS.md wherever that physically is.
function claimCheckProblem(header, tasksFile, root) {
  const v = (header && header.verified) || '';
  if (!/\(pre-approved: \/flow:next --finish\)/.test(v)) return null;
  const m = /^(\d{4}-\d{2}-\d{2})/.exec(v);
  if (!m || m[1] < CLAIM_CHECK_FROM) return null;
  const file = path.join(path.dirname(path.resolve(root, tasksFile)), 'verify', 'claim-check.md');
  let text;
  try {
    text = fs.readFileSync(file, 'utf8');
  } catch {
    return {
      message: `Verified: is pre-approved but ${file} is missing`,
      fix: 'spawn the claim-check agent on the acceptance rows, have it write verify/claim-check.md, then re-run flow lint',
    };
  }
  // Only the summary line counts; CLAIM/OUTPUT lines above it may quote any number.
  const sums = [...text.matchAll(/\d+ confirmed, (\d+) unsupported/g)];
  const u = sums.length ? sums[sums.length - 1] : null;
  if (u && Number(u[1]) > 0) {
    return {
      message: `${file} reports ${u[1]} unsupported claim(s) behind a pre-approved Verified:`,
      fix: 'an unsupported acceptance row is unmet: append a task per the converge rule and clear Verified: until it is re-checked',
    };
  }
  return null;
}

// The date a PASS file counts as written: its last commit when tracked, else
// the file's mtime (a PASS that is written but not yet committed is new).
function passDate(file, root) {
  const g = spawnSync('git', ['-C', path.dirname(file), 'log', '-1', '--format=%cs', '--', path.basename(file)], { encoding: 'utf8', timeout: 15000 });
  const committed = g.status === 0 ? (g.stdout || '').trim() : '';
  if (/^\d{4}-\d{2}-\d{2}$/.test(committed)) return committed;
  try { return fs.statSync(file).mtime.toISOString().slice(0, 10); } catch { return ''; }
}

// Rows of a markdown table as arrays of cells. `\|` is a literal pipe inside a
// cell. A row with more cells than the header (a pipe that was not escaped)
// folds the surplus into the Command column, so the other columns stay aligned.
function passTableRows(text) {
  const rows = text.split('\n').map((l) => l.trim()).filter((l) => l.startsWith('|'))
    .map((l) => l.replace(/^\||\|$/g, '').split(/(?<!\\)\|/).map((c) => c.trim()))
    .filter((cells) => !cells.every((c) => /^:?-+:?$/.test(c)));
  const cmd = rows.length ? rows[0].findIndex((c) => /^command$/i.test(c)) : -1;
  return rows.map((cells, n) => {
    let out = cells;
    if (n > 0 && cmd >= 0 && cells.length > rows[0].length) {
      const extra = cells.length - rows[0].length;
      out = cells.slice(0, cmd).concat([cells.slice(cmd, cmd + extra + 1).join('|')], cells.slice(cmd + extra + 1));
    }
    return out.map((c) => c.replace(/\\\|/g, '|'));
  });
}

// The PASS file the router reads: the one that covers HEAD (passCovers), else
// the most recently dated (ties by name), so a freshly written PASS is checked.
function pickPass(dir, root, names) {
  let pick = null;
  try { const c = require('./router.js').passCovers(root, dir); pick = c.ok ? c.pass : null; } catch { pick = null; }
  if (!pick || !names.includes(pick)) {
    pick = names.map((n) => ({ n, d: passDate(path.join(dir, n), root) }))
      .sort((a, b) => (a.d < b.d ? -1 : a.d > b.d ? 1 : a.n < b.n ? -1 : 1)).pop().n;
  }
  return pick;
}

// True when a shell command pipes (outside quotes, and not `||`) without
// pipefail or PIPESTATUS, so its exit code is the last stage's.
function pipesWithoutPipefail(cmd) {
  if (/pipefail|PIPESTATUS/.test(cmd)) return false;
  const bare = cmd.replace(/`/g, '').replace(/'[^']*'|"(?:[^"\\]|\\.)*"/g, '').replace(/\|\|/g, '');
  return bare.includes('|');
}

function commandPipeProblems(file, text) {
  const rows = passTableRows(text);
  const col = rows.length ? rows[0].findIndex((c) => /^command\b/i.test(c)) : -1;
  if (col < 0) return [];
  return rows.slice(1).filter((cells) => pipesWithoutPipefail(cells[col] || '')).map((cells) => ({
    rule: 'exit-after-pipe',
    message: `${file}: the command "${(cells[col] || '').replace(/`/g, '')}" pipes without pipefail, so its recorded exit code is the last stage's`,
    fix: 'run `<cmd> > log 2>&1; echo $?` and read the log, or start the command with `set -o pipefail;` (bash) or read `${PIPESTATUS[0]}`, then re-record the row',
  }));
}

// pipeProblems(tasksFile, root) -> [problem] for verify/acceptance.md and the
// PASS file passProblems reads, each only when dated on or after PIPE_FROM.
function pipeProblems(tasksFile, root) {
  const dir = path.dirname(path.resolve(root, tasksFile));
  const files = [path.join(dir, 'verify', 'acceptance.md')];
  try {
    const names = fs.readdirSync(dir).filter((f) => /^PASS-[0-9a-f]{4,40}\.md$/.test(f)).sort();
    if (names.length) files.push(path.join(dir, pickPass(dir, root, names)));
  } catch { /* no PASS file */ }
  const out = [];
  for (const file of files) {
    let text;
    try { text = fs.readFileSync(file, 'utf8'); } catch { continue; }
    const date = passDate(file, root);
    if (!date || date < PIPE_FROM) continue;
    out.push(...commandPipeProblems(file, text));
  }
  return out;
}

// passProblems(tasksFile, root) -> [problem]. Looks at the PASS file the router
// reads: the one that covers HEAD (passCovers), else the most recently dated
// (ties by name) so a freshly written, uncommitted-sha PASS is still checked.
function passProblems(tasksFile, root) {
  const dir = path.dirname(path.resolve(root, tasksFile));
  let names;
  try { names = fs.readdirSync(dir).filter((f) => /^PASS-[0-9a-f]{4,40}\.md$/.test(f)).sort(); } catch { return []; }
  if (!names.length) return [];
  const file = path.join(dir, pickPass(dir, root, names));
  const date = passDate(file, root);
  if (!date || date < PASS_EXECUTED_FROM) return [];
  let text;
  try { text = fs.readFileSync(file, 'utf8'); } catch { return []; }
  const rows = passTableRows(text);
  const head = rows.length ? rows[0].map((c) => c.toLowerCase()) : [];
  const col = head.indexOf('executed');
  const out = [];
  if (col === -1) {
    out.push({
      rule: 'pass-executed-missing',
      message: `${file} has no Executed column`,
      fix: 'rewrite the table as `| Gate | Command | Exit | Executed |`: the runner\'s executed count for a test gate (check-all --json: executed), n/a for any other gate',
    });
  } else {
    for (const cells of rows.slice(1)) {
      const val = (cells[col] || '').toLowerCase();
      const isTest = /\b(tests?|pytest|jest|vitest|unittest|mocha)\b/i.test(`${cells[0] || ''} ${cells[1] || ''}`);
      if (/^\d+$/.test(val) && Number(val) === 0 && isTest) {
        out.push({
          rule: 'pass-executed-zero',
          message: `${file}: test row "${cells[0]}" shows Executed 0, so nothing was proven`,
          fix: 'a test gate that ran no tests is not green: register the test (missing fixture or oracle is a failure), re-run the gate and write the real count',
        });
      } else if (!/^\d+$/.test(val) && !(val === 'n/a' && !isTest)) {
        out.push({
          rule: 'pass-executed-missing',
          message: `${file}: row "${cells[0] || '?'}" has Executed "${cells[col] || ''}", expected an integer (n/a only for a non-test gate)`,
          fix: 'write the executed count from the runner summary; n/a is for lint, format and other gates that run no tests',
        });
      }
    }
  }
  if (!/^Not checked:\s*\S/m.test(text)) {
    out.push({
      rule: 'pass-not-checked-missing',
      message: `${file} has no "Not checked:" line`,
      fix: 'add one line under the table: `Not checked: <gate: reason>` for anything the gates did not cover, or `Not checked: none`',
    });
  }
  return out;
}

// problems(json, root) -> every extra ERROR flow lint adds on top of flow-lint.
function problems(json, root) {
  if (!json || !json.file) return [];
  const out = [];
  const claim = claimCheckProblem(json.header, json.file, root);
  if (claim) out.push(Object.assign({ rule: RULE }, claim));
  return out.concat(passProblems(json.file, root), pipeProblems(json.file, root));
}

function run(argv, root, io, env) {
  const script = pluginScript('flow-lint', env);
  if (!script) {
    io.stderr.write('flow lint: flow-lint is not installed beside this CLI\n  fix: reinstall the flow plugin (flow install), or run scripts/flow-lint directly\n');
    return 2;
  }
  const wantJson = argv.includes('--json');
  const probeArgs = argv.filter((a) => a !== '--waves' && a !== '--json').concat('--json');
  const probe = spawnSync('bash', [script].concat(probeArgs), { cwd: root, encoding: 'utf8' });
  let parsed = null;
  try {
    parsed = JSON.parse(probe.stdout || '');
  } catch {
    parsed = null;
  }
  const found = problems(parsed, root);
  if (!found.length) {
    const r = spawnSync('bash', [script].concat(argv), { cwd: root, stdio: 'inherit' });
    return r.status === null ? 2 : r.status;
  }
  if (wantJson) {
    for (const p of found) parsed.errors.push({ line: 0, id: '', rule: p.rule, message: p.message, fix: p.fix });
    parsed.ok = false;
    io.stdout.write(`${JSON.stringify(parsed)}\n`);
    return 1;
  }
  const r = spawnSync('bash', [script].concat(argv), { cwd: root, encoding: 'utf8', stdio: ['inherit', 'pipe', 'inherit'] });
  const kept = (r.stdout || '').split('\n').filter((l) => !/^OK /.test(l)).join('\n').replace(/\n+$/, '');
  if (kept) io.stdout.write(`${kept}\n`);
  for (const p of found) io.stdout.write(`ERROR 0: [${p.rule}] ${p.message}\n  fix: ${p.fix}\n`);
  return r.status === null ? 2 : 1;
}

// withClaimCheck(json, root) -> json with the claim-check and PASS ERRORs
// added. The router calls it so `flow next` routes a pre-approved Verified:
// with no claim-check (or a new PASS file with no Executed column) to invalid,
// not only a hand-run `flow lint`.
function withClaimCheck(json, root) {
  const found = problems(json, root);
  if (!found.length) return json;
  json.errors = (json.errors || []).concat(found.map((p) => ({ line: 0, id: '', rule: p.rule, message: p.message, fix: p.fix })));
  json.ok = false;
  return json;
}

module.exports = { run, withClaimCheck };
