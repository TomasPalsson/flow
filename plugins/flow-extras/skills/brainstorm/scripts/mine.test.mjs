// Tests for mine.mjs. Run: node --test mine.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync, execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const MINE = path.join(path.dirname(fileURLToPath(import.meta.url)), 'mine.mjs');

function tmp(label) { return fs.mkdtempSync(path.join(os.tmpdir(), `mine-${label}-`)); }
function put(root, rel, body) {
  const p = path.join(root, rel);
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p, body);
}
function run(args) { return spawnSync('node', [MINE, ...args], { encoding: 'utf8' }); }
function readJson(p) { return JSON.parse(fs.readFileSync(p, 'utf8')); }
function git(repo, ...args) {
  return execFileSync('git', ['-C', repo, '-c', 'user.name=T', '-c', 'user.email=t@t', ...args], { encoding: 'utf8' });
}

function makeRepo() {
  const r = tmp('repo');
  put(r, 'README.md', [
    '# Demo', 'A demo tool that does things.', 'Second line.', '',
    '## Install', 'run `npm i`', 'Use `--verbose` and `--missing-flag`; see `docs/nope.md` and `src/app.js`;',
    'set `DEMO_TOKEN_X` or `DEMO_TOKEN`.', '', '## Troubleshooting', '- if it hangs, retry', '- clear the cache', ''].join('\n'));
  put(r, 'package.json', JSON.stringify({ name: 'demo', scripts: { start: 'node src/app.js', test: 'node --test' },
    dependencies: { leftpad: '1', usedlib: '1' } }, null, 2));
  put(r, 'src/app.js', [
    "import usedlib from 'usedlib';", 'const a = process.env.DEMO_TOKEN;', 'const b = process.env.SECRET_THING;',
    '// TODO fix this', '// FIXME and that', '// TODO third', '// hack for now', "run('x') || true; // temporary", '// legacy path',
    "const flag = '--hidden-flag'; // --verbose", 'export function orphanFn() { return usedlib; }',
    'export function orphan2() { return 1; }', 'export const orphan3 = () => 2;', ''].join('\n'));
  put(r, 'src/a.js', 'export function aa() {\n  if (1) {\n    return 2;\n  }\n}\n');
  put(r, 'src/b.js', 'function bb() { return 3; }\n');
  put(r, 'config.yaml', 'a: 1\n');
  put(r, '.env.example', 'DEMO_TOKEN=\n');
  put(r, 'yarn.lock', 'lock');
  put(r, 'bun.lock', 'lock');
  put(r, 'node_modules/x/index.js', 'x');
  put(r, 'dist/out.js', 'x');
  put(r, 'app.min.js', 'x');
  put(r, 'app.js.map', 'x');
  put(r, 'blob.dat', Buffer.from([1, 0, 2, 3]));
  put(r, 'big.txt', 'x'.repeat(500 * 1024));
  return r;
}

function mine(repo, extra = []) {
  const out = tmp('out');
  const res = run(['--repo', repo, '--out', out, ...extra]);
  return { out, res };
}

test('non-git repo: exclusions, project card, tree, slice set', () => {
  const repo = makeRepo();
  const { out, res } = mine(repo);
  assert.equal(res.status, 0, res.stderr);
  const tree = fs.readFileSync(path.join(out, 'tree.txt'), 'utf8').split('\n').filter(Boolean);
  for (const bad of ['yarn.lock', 'bun.lock', 'node_modules/x/index.js', 'dist/out.js', 'app.min.js', 'app.js.map', 'blob.dat', 'big.txt']) {
    assert.ok(!tree.includes(bad), `${bad} must be excluded`);
  }
  assert.ok(tree.includes('src/app.js') && tree.includes('README.md'));
  const card = fs.readFileSync(path.join(out, 'project.md'), 'utf8');
  assert.ok(card.split('\n').filter((l) => l.length).length <= 20);
  assert.match(card, /A demo tool that does things\./);
  assert.match(card, /package\.json: name demo; scripts start, test/);
  assert.match(card, /no git history/);
  const ids = readJson(path.join(out, 'slices.json')).map((s) => s.id);
  for (const id of ['workarounds', 'todo-age', 'first-ten-minutes', 'docs-vs-code', 'env-and-config', 'test-gaps', 'unused-surface', 'big-files']) {
    assert.ok(ids.includes(id), `missing slice ${id}: ${ids}`);
  }
  for (const id of ['hotspot', 'history-chain', 'fix-chains']) assert.ok(!ids.includes(id));
});

test('slice contents are citable and correct', () => {
  const { out } = mine(makeRepo());
  const read = (id) => fs.readFileSync(path.join(out, 'slices', `${id}.md`), 'utf8');
  assert.match(read('workarounds'), /src\/app\.js:7: \/\/ hack for now/);
  assert.match(read('workarounds'), /README\.md:\d+: ## Troubleshooting/);
  assert.match(read('todo-age'), /src\/app\.js:4: \/\/ TODO fix this/);
  const docs = read('docs-vs-code');
  assert.match(docs, /mentions --missing-flag, not found in source/);
  assert.match(docs, /mentions path docs\/nope\.md, not found in repo/);
  assert.match(docs, /mentions DEMO_TOKEN_X, not found in source/);
  assert.match(docs, /src\/app\.js:\d+: defines --hidden-flag, no doc mentions it/);
  assert.doesNotMatch(docs, /mentions --verbose/);
  assert.doesNotMatch(docs, /mentions path src\/app\.js/);
  const env = read('env-and-config');
  assert.match(env, /src\/app\.js:2: reads DEMO_TOKEN \(documented\)/);
  assert.match(env, /src\/app\.js:3: reads SECRET_THING \(undocumented\)/);
  assert.match(env, /config\.yaml: top-level config file/);
  assert.match(read('test-gaps'), /no test files found/);
  const unused = read('unused-surface');
  assert.match(unused, /dependency leftpad never appears/);
  assert.doesNotMatch(unused, /dependency usedlib/);
  assert.match(unused, /exports orphanFn/);
  assert.match(read('first-ten-minutes'), /package\.json: start -> node src\/app\.js/);
  assert.match(read('big-files'), /src\/app\.js: 13 lines/);
});

test('slices.json schema, ordering, threshold', () => {
  const { out } = mine(makeRepo());
  const idx = readJson(path.join(out, 'slices.json'));
  for (const s of idx) {
    assert.deepEqual(Object.keys(s).sort(), ['id', 'n_items', 'packet', 'primary_files', 'strength', 'title']);
    assert.ok(s.n_items >= 3);
    assert.ok(s.strength > 0 && s.strength <= 1);
    assert.ok(s.primary_files.length <= 8);
    assert.equal(s.packet, `slices/${s.id}.md`);
    assert.ok(fs.existsSync(path.join(out, s.packet)));
  }
  const strengths = idx.map((s) => s.strength);
  assert.deepEqual(strengths, [...strengths].sort((a, b) => b - a));
});

test('git repo: hotspot, history-chain, fix-chains, todo dates', () => {
  const repo = makeRepo();
  git(repo, 'init', '-q');
  git(repo, 'add', '-A');
  git(repo, 'commit', '-qm', 'initial');
  for (const msg of ['fix crash in app', 'fix again in app', 'Revert "fix again in app"', 'tweak app']) {
    fs.appendFileSync(path.join(repo, 'src/app.js'), `// ${msg}\n`);
    fs.appendFileSync(path.join(repo, 'src/a.js'), `// ${msg}\n`);
    git(repo, 'commit', '-qam', msg);
  }
  const { out, res } = mine(repo);
  assert.equal(res.status, 0, res.stderr);
  const ids = readJson(path.join(out, 'slices.json')).map((s) => s.id);
  for (const id of ['hotspot', 'history-chain', 'fix-chains']) assert.ok(ids.includes(id), `${id} in ${ids}`);
  const read = (id) => fs.readFileSync(path.join(out, 'slices', `${id}.md`), 'utf8');
  assert.match(read('hotspot'), /src\/app\.js: 5 commits in 12 months, \d+ lines, 1 authors/);
  assert.match(read('hotspot'), /  - tweak app/);
  assert.match(read('history-chain'), /^[0-9a-f]{7,} \d{4}-\d\d-\d\d tweak app \(\+1 -0\) \[src\/app\.js\]/m);
  const fc = read('fix-chains');
  assert.match(fc, /src\/app\.js: 3 fix commits/);
  assert.match(fc, /^[0-9a-f]{7,} \d{4}-\d\d-\d\d Revert "fix again in app"/m);
  assert.match(read('todo-age'), /src\/app\.js:4: \[\d{4}-\d\d-\d\d\]/);
  assert.match(fs.readFileSync(path.join(out, 'project.md'), 'utf8'), /git: 5 commits, .* 1 authors/);
});

test('--max-lines caps the packet and notes truncation', () => {
  const { out, res } = mine(makeRepo(), ['--max-lines', '5']);
  assert.equal(res.status, 0, res.stderr);
  const md = fs.readFileSync(path.join(out, 'slices', 'workarounds.md'), 'utf8').trimEnd().split('\n');
  assert.ok(md.length <= 5, `got ${md.length} lines`);
  assert.match(md[md.length - 1], /^\.\.\. \d+ more items not shown$/);
});

test('--focus limits file-based slices', () => {
  const repo = makeRepo();
  put(repo, 'lib/z.js', '// TODO z1\n// TODO z2\n// TODO z3\n// TODO z4\n');
  const { out, res } = mine(repo, ['--focus', 'lib']);
  assert.equal(res.status, 0, res.stderr);
  const todo = fs.readFileSync(path.join(out, 'slices', 'todo-age.md'), 'utf8');
  assert.match(todo, /lib\/z\.js:1:/);
  assert.doesNotMatch(todo, /src\/app\.js/);
});

test('exit codes: bad args 2, missing repo 3, missing focus 3', () => {
  const out = tmp('out');
  assert.equal(run([]).status, 2);
  assert.equal(run(['--repo', out, '--out', out, '--bogus']).status, 2);
  assert.equal(run(['--repo', out, '--out', out, '--max-lines', 'x']).status, 2);
  const missing = run(['--repo', path.join(out, 'nope'), '--out', out]);
  assert.equal(missing.status, 3);
  assert.match(missing.stderr, /not a directory/);
  assert.equal(run(['--repo', makeRepo(), '--out', out, '--focus', 'nope']).status, 3);
});

test('tiny repo with no slice reaching 3 items exits 1', () => {
  const r = tmp('tiny');
  put(r, 'x.txt', 'hello\n');
  const { res } = mine(r);
  assert.equal(res.status, 1);
  assert.match(res.stderr, /no slice reached 3/);
});

test('outline slice lists declarations per language, path order', () => {
  const r = tmp('outline');
  put(r, 'a.js', 'export function one() {}\nconst two = (x) => x;\nclass Three {}\nlet y = 1;\n');
  put(r, 'b.rs', [
    'use std::io;', 'pub fn run() {', '}', 'struct S;', '#[derive(Subcommand)]', 'enum Cmd {', '    Add,', '    Remove { id: u32 },', '}',
    'impl S {', '}', ''].join('\n'));
  put(r, 'c.py', 'def f():\n    pass\nclass K:\n    pass\n');
  put(r, 'd.go', 'package x\nfunc Do() {}\ntype T struct {}\n');
  put(r, 'e.sh', 'build() {\n  true\n}\n');
  const { out, res } = mine(r);
  assert.equal(res.status, 0, res.stderr);
  const md = fs.readFileSync(path.join(out, 'slices', 'outline.md'), 'utf8');
  for (const re of [/a\.js:1: export function one\(\)/, /a\.js:2: const two = \(x\) => x;/, /a\.js:3: class Three/,
    /b\.rs:2: pub fn run\(\)/, /b\.rs:4: struct S;/, /b\.rs:6: enum Cmd/, /b\.rs:7: Add,/, /b\.rs:8: Remove/, /b\.rs:10: impl S/,
    /c\.py:1: def f\(\):/, /c\.py:3: class K:/, /d\.go:2: func Do\(\)/, /d\.go:3: type T struct/, /e\.sh:1: build\(\)/]) {
    assert.match(md, re);
  }
  assert.doesNotMatch(md, /let y = 1/);
  assert.ok(md.indexOf('a.js:1') < md.indexOf('b.rs:2') && md.indexOf('b.rs:2') < md.indexOf('c.py:1'));
  const o = readJson(path.join(out, 'slices.json')).find((s) => s.id === 'outline');
  assert.ok(o.n_items >= 3 && o.primary_files.length <= 8);
  assert.equal(o.primary_files[0], 'b.rs');
});

test('whole-source: full text with prefixes, exempt from 3-item rule, exit 0', () => {
  const r = tmp('whole');
  put(r, 'small.js', 'const a = 1;\n');
  put(r, 'big.js', 'line1\nline2\nline3\n');
  put(r, 'manifest.json', '{"name":"x"}\n');
  put(r, 'big.test.js', 'test();\n');
  put(r, 'types.d.ts', 'declare const q: 1;\n');
  const { out, res } = mine(r);
  assert.equal(res.status, 0, res.stderr);
  const w = readJson(path.join(out, 'slices.json')).find((s) => s.id === 'whole-source');
  assert.equal(w.n_items, 3);
  assert.equal(w.strength, 0.6);
  const md = fs.readFileSync(path.join(out, 'slices', 'whole-source.md'), 'utf8');
  assert.match(md, /big\.js:2\| line2/);
  assert.match(md, /manifest\.json:1\| \{"name":"x"\}/);
  assert.ok(md.indexOf('big.js:1|') < md.indexOf('small.js:1|'));
  assert.doesNotMatch(md, /big\.test\.js|types\.d\.ts/);
});

test('whole-source: tiny repo with one file exits 0; capped at 600 lines; skipped above 1500', () => {
  const one = tmp('whole-one');
  put(one, 'only.js', 'const a = 1;\n');
  assert.equal(mine(one).res.status, 0);
  const r = tmp('whole-big');
  put(r, 'm.js', `${Array.from({ length: 800 }, (_, i) => `// l${i}`).join('\n')}\n`);
  const { out } = mine(r, ['--max-lines', '5']);
  const md = fs.readFileSync(path.join(out, 'slices', 'whole-source.md'), 'utf8').trimEnd().split('\n');
  assert.ok(md.length <= 600, `got ${md.length}`);
  assert.match(md[md.length - 1], /^\.\.\. \d+ more lines not shown$/);
  put(r, 'n.js', `${Array.from({ length: 800 }, (_, i) => `// n${i}`).join('\n')}\n`);
  const second = mine(r);
  const ids = readJson(path.join(second.out, 'slices.json')).map((s) => s.id);
  assert.ok(!ids.includes('whole-source'));
});
