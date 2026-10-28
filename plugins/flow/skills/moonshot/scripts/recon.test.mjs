import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const RECON = path.join(path.dirname(fileURLToPath(import.meta.url)), 'recon.mjs');
const tmpDirs = [];
let repo;

function git(args, env = {}) {
  return execFileSync('git', args, {
    cwd: repo, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'],
    env: { ...process.env, GIT_CONFIG_GLOBAL: '/dev/null', GIT_CONFIG_NOSYSTEM: '1', ...env },
  });
}

function write(rel, content) {
  const abs = path.join(repo, rel);
  fs.mkdirSync(path.dirname(abs), { recursive: true });
  fs.writeFileSync(abs, content);
}

function commit(message, daysAgo, who = { name: 'Dev', email: 'dev@example.com' }) {
  const stamp = `${Math.floor((Date.now() - daysAgo * 86400000) / 1000)} +0000`;
  git(['add', '-A']);
  git(['commit', '-q', '-m', message], {
    GIT_AUTHOR_DATE: stamp, GIT_COMMITTER_DATE: stamp, GIT_AUTHOR_NAME: who.name, GIT_AUTHOR_EMAIL: who.email,
    GIT_COMMITTER_NAME: who.name, GIT_COMMITTER_EMAIL: who.email,
  });
}

const block = (round) => Array.from({ length: 30 }, (_, i) => `export const v${round}_${i} = ${i};`).join('\n') + '\n';
const HACK = '// HACK: for now\n';

function buildRepo() {
  repo = fs.mkdtempSync(path.join(os.tmpdir(), 'recon-test-repo-'));
  tmpDirs.push(repo);
  git(['init', '-q', '-b', 'main']);
  git(['config', 'user.name', 'Dev']);
  git(['config', 'user.email', 'dev@example.com']);
  git(['config', 'commit.gpgsign', 'false']);
  write('.gitignore', 'node_modules\n');
  write('package.json', JSON.stringify({ name: 'fx', dependencies: { 'heavy-lib': '^1.0.0', 'used-lib': '^1.0.0' } }));
  write('package-lock.json', '{"v":1}\n');
  write('README.md', '# fixture\n');
  write('src/engine/core.js', block(0));
  write('src/ui/view.js', '');
  fs.writeFileSync(path.join(repo, 'src/ui/view.js'), 'export const view = 0;\n');
  fs.mkdirSync(path.join(repo, 'node_modules/heavy-lib'), { recursive: true });
  fs.writeFileSync(path.join(repo, 'node_modules/heavy-lib/blob.bin'), '');
  fs.truncateSync(path.join(repo, 'node_modules/heavy-lib/blob.bin'), 12 * 1024 * 1024);
  write('node_modules/used-lib/index.js', 'module.exports = 1;\n');
  commit('add engine and ui', 345);

  let ui = 'export const view = 0;\n';
  const addUi = (n, days) => {
    ui += Array.from({ length: 5 }, (_, i) => `export const part${n}_${i} = ${i};`).join('\n') + '\n';
    write('src/ui/view.js', ui);
    commit(`add view part ${n}`, days);
  };
  const fixCore = (round, message, days) => { write('src/engine/core.js', block(round) + HACK); commit(message, days); };

  addUi(1, 330);
  write('src/engine/core.js', block(0) + HACK);
  commit('add engine note', 300);
  addUi(2, 280);
  fixCore(1, 'fix timeout again', 270);
  addUi(3, 250);
  fixCore(2, 'workaround retry bug', 210);
  for (let i = 1; i <= 5; i++) {
    write(`src/lib/use${i}.js`, `import x from 'used-lib';\n${i === 1 ? "import h from 'heavy-lib/sub';\n" : ''}export default x;\n`);
  }
  commit('add consumers', 200);
  addUi(4, 180);
  fixCore(3, 'hotfix flaky parser', 150);
  addUi(5, 130);
  for (let i = 0; i < 60; i++) write(`bulk/f${i}.js`, `export const f${i} = ${i};\n`);
  commit('fix bulk rename', 120);
  ui += 'export const bumped = 1;\n';
  write('src/ui/view.js', ui);
  commit('fix deps bump', 100, { name: 'dependabot[bot]', email: 'bot@example.com' });
  fixCore(4, 'revert still broken thing', 90);
  addUi(6, 80);
  write('README.md', '# fixture\nmore docs\n');
  commit('fix readme again', 50);
  write('package-lock.json', '{"v":2}\n');
  commit('fix lock', 40);
  fixCore(5, 'fix broken retry again', 30);
}

function run(args) {
  return spawnSync('node', [RECON, ...args], { encoding: 'utf8' });
}

function runJson(args = []) {
  const r = run(['--repo', repo, '--json', ...args]);
  assert.equal(r.status, 0, r.stderr);
  return JSON.parse(r.stdout);
}

describe('recon', () => {
  before(buildRepo);
  after(() => { for (const d of tmpDirs) fs.rmSync(d, { recursive: true, force: true }); });

  it('flags a flat-net, repeatedly fixed directory as STALL', () => {
    const rows = runJson().directories.rows;
    const engine = rows.find((r) => r.dir === 'src/engine');
    assert.equal(engine.stall, true);
    assert.equal(engine.fix_commits, 5);
    assert.equal(engine.fix_months, 5);
    assert.ok(Math.abs(engine.net) / engine.added < 0.2);
  });

  it('does not stall a growing directory with no fix commits', () => {
    const ui = runJson().directories.rows.find((r) => r.dir === 'src/ui');
    assert.equal(ui.stall, false);
    assert.equal(ui.fix_commits, 0);
    assert.equal(ui.commits, 7);
    assert.ok(ui.net > 0);
  });

  it('skips bot and mechanical commits and counts them', () => {
    const d = runJson().directories;
    assert.deepEqual(d.skipped, { total: 2, bots: 1, mechanical: 1 });
    assert.ok(!d.rows.some((r) => r.dir === 'bulk'));
  });

  it('keeps docs and lockfiles out of directories and files', () => {
    const out = runJson();
    const root = out.directories.rows.find((r) => r.dir === '.');
    assert.equal(root.commits, 1, 'only the initial commit counts for root files');
    assert.equal(root.fix_commits, 0);
    const paths = out.files.rows.map((r) => r.path);
    assert.ok(!paths.includes('README.md') && !paths.includes('package-lock.json'));
    assert.ok(paths.includes('src/engine/core.js'));
  });

  it('ages the HACK line via git blame', () => {
    const w = runJson().workarounds;
    const hit = w.oldest.find((h) => h.path === 'src/engine/core.js' && /HACK/.test(h.text));
    assert.ok(hit, 'HACK line listed');
    assert.ok(hit.age_days >= 290, `age_days ${hit.age_days}`);
    assert.equal(w.capped, false);
  });

  it('flags the heavy, narrowly used dependency', () => {
    const rows = runJson().dependencies.rows;
    const heavy = rows.find((r) => r.name === 'heavy-lib');
    const used = rows.find((r) => r.name === 'used-lib');
    assert.equal(heavy.flag, 'HEAVY-NARROW');
    assert.equal(heavy.import_sites, 1);
    assert.ok(heavy.size_mb >= 11.9);
    assert.equal(used.import_sites, 5);
    assert.equal(used.flag, null);
    assert.equal(rows[0].name, 'heavy-lib');
  });

  it('warns about thin history in preflight', () => {
    const p = runJson().preflight;
    assert.equal(p.shallow, false);
    assert.match(p.warning, /^WARN: thin history \(.*\); churn and stall signals are weak$/);
  });

  it('--focus restricts every section', () => {
    const out = runJson(['--focus', 'src/ui']);
    assert.deepEqual(out.directories.rows.map((r) => r.dir), ['src/ui']);
    assert.ok(out.files.rows.every((r) => r.path.startsWith('src/ui/')));
    assert.equal(out.workarounds.total, 0);
  });

  it('prints text with section headers and STALL', () => {
    const r = run(['--repo', repo]);
    assert.equal(r.status, 0, r.stderr);
    for (const h of ['preflight', 'directories', 'files', 'workarounds', 'dependencies', 'large-files']) {
      assert.ok(r.stdout.includes(`## ${h}`), `missing ## ${h}`);
    }
    assert.match(r.stdout, /src\/engine.*STALL/);
    assert.match(r.stdout, /HEAVY-NARROW/);
  });

  it('--help exits 0 and mentions every flag', () => {
    const r = run(['--help']);
    assert.equal(r.status, 0);
    for (const f of ['--repo', '--focus', '--months', '--json', '--help']) assert.ok(r.stdout.includes(f), f);
  });

  it('exits 2 with the documented message outside a git repo', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'recon-test-nogit-'));
    tmpDirs.push(dir);
    const r = run(['--repo', dir]);
    assert.equal(r.status, 2);
    assert.equal(r.stderr.trim(), `recon: ${dir} is not a git repository. Name the target yourself, or run recon inside a git checkout.`);
  });
});
