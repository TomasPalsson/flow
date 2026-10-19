// node judge.mjs <outdir> [-j 4] [--runs 1] : blind judge per case over every arm's renders
import { spawn } from 'node:child_process';
import { readFileSync, writeFileSync, existsSync, readdirSync, mkdirSync, copyFileSync } from 'node:fs';
import { join } from 'node:path';

const out = process.argv[2];
const J = +(process.argv[process.argv.indexOf('-j') + 1] || 4);
const BENCH = '/home/tomas/.claude/jobs/d3b140b3/tmp/bench';
const cases = JSON.parse(readFileSync(`${BENCH}/cases.json`, 'utf8'));
const arms = readdirSync(out).filter(d => !d.includes('.') && d !== 'judge');
const LETTERS = 'ABCDE';

function shuffle(a, seed) { const r = [...a]; let s = seed; for (let i = r.length - 1; i > 0; i--) { s = (s * 9301 + 49297) % 233280; const j = Math.floor(s / 233280 * (i + 1)); [r[i], r[j]] = [r[j], r[i]]; } return r; }

const RUBRIC = (c) => `You are judging diagrams made by different tools for the same request. Judge strictly and independently; the letters are random.

REQUEST GIVEN TO EACH TOOL:
"""${c.prompt}"""
${c.fixture ? `\nThe source file it had to redraw is ${c.fixture} in this folder.\n` : ''}
For each entry X in {${'%LETTERS%'}} there is X-desktop.png (1440px wide), X-phone.png (390px wide, 2x) and X.html (the source). Read EVERY png (they are the main evidence) and skim each html for the exact labels. An entry with no files produced nothing: score it 0.

Score each entry 0-10 (decimals allowed) on:
- fidelity: every component, step, actor and relation in the request is present and correct; nothing invented that the request did not imply; a reader could rebuild the request from the picture.
- clarity: a reader gets the main point in one look; sensible flow direction and grouping; the right diagram type; not overloaded.
- hygiene: no overlapping or clipped text, no lines running through labels or boxes, no tangled crossings, arrows clearly attach to the right things, readable at phone width (sideways scroll inside the figure is fine; squashed unreadable text is not).
- polish: looks like a professional, designed figure (consistent type, spacing, restrained colour), not generic AI output.
${c.aws ? '- aws: uses the official AWS Architecture Icons (not hand-drawn boxes or fake logos), AWS group boxes (AWS Cloud, Region, VPC, AZ, subnets) in AWS colours where relevant, and services placed in the correct network scope (e.g. managed services like S3/DynamoDB/Lambda/SQS NOT inside subnets; ALB/ECS/RDS inside the VPC).\n' : ''}
Then write the single most important flaw of each entry.

Reply with ONLY this JSON, no prose before or after:
{"scores": {"A": {"fidelity": n, "clarity": n, "hygiene": n, "polish": n${c.aws ? ', "aws": n' : ''}, "flaw": "..."}, ...}, "best": "letter", "why_best": "one sentence"}`;

const jobs = [];
for (const c of cases) {
  const present = arms.filter(a => existsSync(join(out, a, c.id, 'meta.json')));
  if (!present.length) continue;
  const order = shuffle(present, c.id.length * 7919 + present.length);
  const dir = join(out, 'judge', c.id); mkdirSync(dir, { recursive: true });
  const map = {};
  order.forEach((a, i) => {
    const L = LETTERS[i]; map[L] = a; const src = join(out, a, c.id);
    for (const v of ['desktop', 'phone']) if (existsSync(join(src, `${v}.png`))) copyFileSync(join(src, `${v}.png`), join(dir, `${L}-${v}.png`));
    const meta = JSON.parse(readFileSync(join(src, 'meta.json'), 'utf8'));
    if (meta.html) copyFileSync(join(src, 'work', meta.html), join(dir, `${L}.html`));
  });
  if (c.fixture) copyFileSync(join(BENCH, 'fixtures', c.fixture), join(dir, c.fixture));
  writeFileSync(join(dir, 'map.json'), JSON.stringify(map));
  jobs.push({ c, dir, map, prompt: RUBRIC(c).replace('%LETTERS%', Object.keys(map).join(', ')) });
}

function runJudge(j) {
  return new Promise(resolve => {
    const p = spawn('claude', ['-p', j.prompt, '--model', 'claude-opus-5-5', '--setting-sources', 'project,local', '--strict-mcp-config',
      '--output-format', 'json', '--allowedTools', 'Read Glob', '--max-budget-usd', '4'],
      { cwd: j.dir, env: { ...process.env, CLAUDE_CODE_DISABLE_CLAUDE_MDS: '1', CLAUDE_CODE_DISABLE_AUTO_MEMORY: '1' } });
    let buf = ''; p.stdout.on('data', d => buf += d);
    p.on('close', () => {
      writeFileSync(join(j.dir, 'judge-raw.json'), buf);
      let parsed = null;
      try { const r = JSON.parse(buf).result; parsed = JSON.parse(r.slice(r.indexOf('{'), r.lastIndexOf('}') + 1)); } catch (e) { parsed = { error: e.message }; }
      writeFileSync(join(j.dir, 'verdict.json'), JSON.stringify({ map: j.map, ...parsed }, null, 2));
      resolve({ case: j.c.id, map: j.map, ...parsed });
    });
  });
}

let i = 0; const results = [];
await Promise.all(Array.from({ length: J }, async () => { while (i < jobs.length) { const j = jobs[i++]; results.push(await runJudge(j)); } }));
writeFileSync(join(out, 'verdicts.json'), JSON.stringify(results, null, 2));

const table = {};
for (const r of results) {
  if (!r.scores) { console.log(`${r.case}: judge error ${r.error}`); continue; }
  for (const [L, s] of Object.entries(r.scores)) {
    const arm = r.map[L]; const dims = Object.entries(s).filter(([k, v]) => typeof v === 'number');
    const mean = dims.reduce((a, [, v]) => a + v, 0) / dims.length;
    (table[arm] ??= []).push(mean);
    console.log(`${r.case.padEnd(15)} ${arm.padEnd(9)} ${mean.toFixed(2)}  ${dims.map(([k, v]) => `${k}=${v}`).join(' ')}${r.map[r.best] === arm ? '  <- best' : ''}\n${' '.repeat(26)}flaw: ${s.flaw}`);
  }
}
for (const [arm, v] of Object.entries(table)) console.log(`MEAN ${arm.padEnd(9)} ${(v.reduce((a, b) => a + b, 0) / v.length).toFixed(2)} over ${v.length} cases, min ${Math.min(...v).toFixed(2)}`);
