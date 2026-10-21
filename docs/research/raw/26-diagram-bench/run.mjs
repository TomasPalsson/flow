// node run.mjs <outdir> [--arms new,upstream,old] [--cases id,id] [-j 4]
import { spawn, spawnSync } from 'node:child_process';
import { mkdirSync, copyFileSync, readFileSync, writeFileSync, existsSync, readdirSync, statSync, createWriteStream } from 'node:fs';
import { join } from 'node:path';

const EVAL = '/home/tomas/.claude/jobs/d3b140b3/tmp/bench';
const WT = '/home/tomas/Desktop/Projects/flow/.claude/worktrees/design-diagram';
const ARMS = {
  new: { plugin: `${WT}/plugins/design`, cmd: '/design:diagram' },
  upstream: { plugin: `${EVAL}/upstream-plugin`, cmd: '/diagram-design:diagram-design' },
  old: { plugin: '/home/tomas/Desktop/Projects/flow/plugins/design', cmd: '/design:graphics' },
};
const argv = process.argv.slice(2);
const out = argv[0];
const opt = (k, d) => { const i = argv.indexOf(k); return i > 0 ? argv[i + 1] : d; };
const arms = opt('--arms', 'new,upstream,old').split(',');
const cases = JSON.parse(readFileSync(`${EVAL}/cases.json`, 'utf8')).filter(c => !opt('--cases') || opt('--cases').split(',').includes(c.id));
const J = +opt('-j', 4);
const status = join(out, 'status.log');
mkdirSync(out, { recursive: true });
const log = m => { writeFileSync(status, `${new Date().toISOString()} ${m}\n`, { flag: 'a' }); };

function buildOne(arm, c) {
  return new Promise(resolve => {
    const dir = join(out, arm, c.id); const work = join(dir, 'work');
    mkdirSync(work, { recursive: true });
    if (c.fixture) copyFileSync(join(EVAL, 'fixtures', c.fixture), join(work, c.fixture));
    const prompt = `${ARMS[arm].cmd} ${c.prompt}\n\nSave the finished diagram as diagram.html in the current directory. Keep every scratch file (scripts, renders) inside the current directory, never in /tmp. I am not available for questions: make reasonable assumptions and list them at the end.`;
    const args = ['-p', prompt, '--model', 'claude-opus-5-5', '--setting-sources', 'project,local', '--strict-mcp-config',
      '--plugin-dir', ARMS[arm].plugin, '--output-format', 'stream-json', '--verbose', '--max-budget-usd', '8',
      '--permission-mode', 'acceptEdits', '--allowedTools', 'Bash Read Write Edit Glob Grep Skill Agent WebFetch'];
    const t0 = Date.now();
    const p = spawn('claude', args, { cwd: work, detached: true, env: { ...process.env, CLAUDE_CODE_DISABLE_CLAUDE_MDS: '1', CLAUDE_CODE_DISABLE_AUTO_MEMORY: '1' } });
    const trace = createWriteStream(join(dir, 'trace.jsonl'));
    p.stdout.pipe(trace); p.stderr.pipe(createWriteStream(join(dir, 'stderr.txt')));
    const kill = setTimeout(() => { try { process.kill(-p.pid, 'SIGKILL'); } catch {} }, 30 * 60e3);
    p.on('close', code => {
      clearTimeout(kill);
      let cost = null, turns = null, err = null;
      try {
        const lines = readFileSync(join(dir, 'trace.jsonl'), 'utf8').trim().split('\n');
        const res = lines.map(l => { try { return JSON.parse(l); } catch { return {}; } }).filter(e => e.type === 'result').pop();
        if (res) { cost = res.total_cost_usd; turns = res.num_turns; if (res.is_error) err = res.subtype || 'error'; }
        else err = 'no result event';
      } catch (e) { err = e.message; }
      const meta = { arm, case: c.id, code, secs: Math.round((Date.now() - t0) / 1000), cost, turns, err, html: findHtml(work) };
      writeFileSync(join(dir, 'meta.json'), JSON.stringify(meta, null, 2));
      log(`DONE ${arm}/${c.id} code=${code} cost=${cost} turns=${turns} err=${err} html=${meta.html}`);
      resolve(meta);
    });
  });
}

function findHtml(work) {
  if (existsSync(join(work, 'diagram.html'))) return 'diagram.html';
  const all = [];
  const walk = d => { for (const f of readdirSync(d)) { const p = join(d, f); const s = statSync(p); if (s.isDirectory()) walk(p); else if (f.endsWith('.html')) all.push([s.mtimeMs, p.slice(work.length + 1)]); } };
  walk(work); all.sort((a, b) => b[0] - a[0]);
  return all[0]?.[1] ?? null;
}

const queue = cases.flatMap(c => arms.map(a => [a, c]));
let i = 0;
log(`START ${queue.length} builds, j=${J}`);
await Promise.all(Array.from({ length: J }, async () => { while (i < queue.length) { const [a, c] = queue[i++]; log(`BEGIN ${a}/${c.id}`); await buildOne(a, c); } }));
log('ALL DONE');
