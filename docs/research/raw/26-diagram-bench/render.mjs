// node render.mjs <outdir> : screenshots + mechanical checks for every built diagram
import { chromium } from 'playwright-core';
import { readFileSync, writeFileSync, existsSync, readdirSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';

const out = resolve(process.argv[2]);
const SK = '/home/tomas/Desktop/Projects/flow/.claude/worktrees/design-diagram/plugins/design/skills/diagram/scripts';
const browser = await chromium.launch({ executablePath: '/bin/google-chrome-stable' });

const overlapJs = () => {
  const texts = [...document.querySelectorAll('svg text')].filter(t => t.textContent.trim() && t.getClientRects().length);
  const boxes = texts.map(t => { const r = t.getBoundingClientRect(); return { r, s: t.textContent.trim().slice(0, 30) }; });
  const hits = [];
  for (let i = 0; i < boxes.length; i++) for (let j = i + 1; j < boxes.length; j++) {
    const a = boxes[i].r, b = boxes[j].r;
    const w = Math.min(a.right, b.right) - Math.max(a.left, b.left), h = Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top);
    if (w > 2 && h > 2) hits.push(`${boxes[i].s} | ${boxes[j].s}`);
  }
  const clipped = [];
  for (const t of texts) { const svg = t.ownerSVGElement; if (!svg) continue; const s = svg.getBoundingClientRect(), r = t.getBoundingClientRect();
    if (r.left < s.left - 1 || r.right > s.right + 1 || r.top < s.top - 1 || r.bottom > s.bottom + 1) clipped.push(t.textContent.trim().slice(0, 30)); }
  const nested = document.querySelectorAll('svg svg').length;
  const hscroll = document.documentElement.scrollWidth > window.innerWidth + 1;
  return { texts: texts.length, overlaps: hits, clipped, nested, hscroll };
};

const rows = [];
for (const arm of readdirSync(out).filter(d => !d.includes('.'))) for (const c of readdirSync(join(out, arm))) {
  const dir = join(out, arm, c); const mp = join(dir, 'meta.json');
  if (!existsSync(mp)) continue;
  const meta = JSON.parse(readFileSync(mp, 'utf8'));
  if (!meta.html) { rows.push({ arm, c, missing: true }); continue; }
  const file = join(dir, 'work', meta.html);
  const res = { arm, case: c };
  for (const [name, w] of [['desktop', 1440], ['phone', 390]]) {
    const page = await browser.newPage({ viewport: { width: w, height: 900 }, deviceScaleFactor: name === 'phone' ? 2 : 1 });
    await page.goto('file://' + file, { waitUntil: 'networkidle', timeout: 30000 }).catch(() => {});
    await page.waitForTimeout(800);
    await page.screenshot({ path: join(dir, `${name}.png`), fullPage: true });
    res[name] = await page.evaluate(overlapJs);
    await page.close();
  }
  const sc = spawnSync('python3', [join(SK, 'self_check.py'), file], { encoding: 'utf8' });
  const vg = spawnSync('python3', [join(SK, 'verify-geometry.py'), file], { encoding: 'utf8' });
  res.self_check = sc.status === 0 ? 'ok' : (sc.stdout + sc.stderr).trim().split('\n').slice(0, 6).join(' / ');
  res.geometry = (vg.stdout.match(/(\d+) finding/) || [])[1] ?? 'err';
  res.bytes = readFileSync(file).length;
  writeFileSync(join(dir, 'checks.json'), JSON.stringify(res, null, 2));
  rows.push(res);
  console.log(`${arm.padEnd(9)} ${c.padEnd(15)} overlaps=${res.desktop.overlaps.length} clipped=${res.desktop.clipped.length} nested=${res.desktop.nested} phoneHscroll=${res.phone.hscroll} self_check=${res.self_check === 'ok' ? 'ok' : 'FAIL'} geom=${res.geometry}`);
}
await browser.close();
writeFileSync(join(out, 'checks.json'), JSON.stringify(rows, null, 2));
