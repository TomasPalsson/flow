import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const SCRIPT = fileURLToPath(new URL('./assemble.mjs', import.meta.url));
const LOOKS = JSON.parse(readFileSync(fileURLToPath(new URL('../data/looks.json', import.meta.url)), 'utf8'));

const SVG_A = `<?xml version="1.0"?>
<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "x.dtd">
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 360 220" width="360" height="220">
<title>claim</title><desc>A full sentence.</desc>
<defs><marker id="arrow" markerWidth="6" markerHeight="6"><path d="M0 0L6 3L0 6z"/></marker><clipPath id="i1p1-clip"><rect width="10" height="10"/></clipPath></defs>
<g id="box"><rect id="r" width="50" height="20" fill="var(--card)"/></g>
<use href="#box"/><use xlink:href="#r"/>
<line x1="0" y1="0" x2="9" y2="9" marker-end="url(#arrow)" clip-path="url('#i1p1-clip')"/>
<text x="20" y="40">a &lt; b</text>
</svg>`;

function makeRun(ideas, extra = {}) {
  const dir = mkdtempSync(join(tmpdir(), 'assemble-test-'));
  mkdirSync(join(dir, 'pictures'));
  const data = {
    repo: 'demo',
    key: '00000001abcdef',
    generated_at: '2026-10-11',
    headline: 'A headline.',
    ideas,
    dropped: { obvious: ['Add tests'], dead: [{ title: 'Add --json', why: 'exists: a.rs:1' }], count: 7 },
    ...extra,
  };
  writeFileSync(join(dir, 'final.json'), JSON.stringify(data));
  return dir;
}

function idea(id, slot, over = {}) {
  return {
    id,
    slot,
    title: `Title ${id}`,
    sentence: `Sentence ${id}.`,
    for_whom: 'someone',
    why_here: `Why ${id}`,
    first_test: `Test ${id}`,
    gives_up: 'one branch',
    size: { blocks: 2, words: 'about a day' },
    pictures: [],
    words: [],
    evidence: [{ where: 'src/a.rs:1', what: 'does a thing' }],
    risks: ['it may break'],
    needs: [],
    ...over,
  };
}

function run(args) {
  return spawnSync(process.execPath, [SCRIPT, ...args], { encoding: 'utf8' });
}

function assembleOk(dir, extraArgs = []) {
  const r = run(['--run', dir, ...extraArgs]);
  assert.equal(r.status, 0, r.stderr);
  return readFileSync(join(dir, 'page.html'), 'utf8');
}

test('escapes HTML from JSON text', () => {
  const dir = makeRun([idea('a', 'safe', { title: '<script>alert(1)</script> & "x"', risks: ['<b>bold</b>'] })], { headline: '<img src=x onerror=1>' });
  const html = assembleOk(dir);
  assert.ok(!html.includes('<script'));
  assert.ok(!html.includes('<img'));
  assert.ok(!html.includes('<b>bold</b>'));
  assert.ok(html.includes('&lt;script&gt;alert(1)&lt;/script&gt; &amp; &quot;x&quot;'));
  assert.ok(html.includes('&lt;img src=x onerror=1&gt;'));
});

test('page has no javascript and only Google Fonts links', () => {
  const dir = makeRun([idea('a', 'safe')]);
  for (const look of LOOKS) {
    const html = assembleOk(dir, ['--look', look.id]);
    assert.ok(!/<script/i.test(html), look.id);
    assert.ok(!/\son\w+=/i.test(html), look.id);
    for (const m of html.matchAll(/<link[^>]*href="([^"]+)"/g)) assert.match(m[1], /^https:\/\/fonts\.googleapis\.com\//);
    assert.ok(!/src=/.test(html));
  }
});

test('svg ids are namespaced and references follow; root cleaned', () => {
  const dir = makeRun([idea('i1', 'safe', { pictures: [{ id: 'p1', caption: 'cap <1>', file: 'pictures/a.svg' }] })]);
  writeFileSync(join(dir, 'pictures/a.svg'), SVG_A);
  const html = assembleOk(dir);
  assert.ok(html.includes('id="i1p1-arrow"'));
  assert.ok(html.includes('marker-end="url(#i1p1-arrow)"'));
  assert.ok(html.includes('id="i1p1-box"'));
  assert.ok(html.includes('href="#i1p1-box"'));
  assert.ok(html.includes('xlink:href="#i1p1-r"'));
  assert.ok(html.includes('id="i1p1-clip"'), 'already prefixed id is not doubled');
  assert.ok(!html.includes('i1p1-i1p1-'));
  assert.ok(html.includes("clip-path=\"url('#i1p1-clip')\""));
  assert.ok(!html.includes('<?xml'));
  assert.ok(!html.includes('<!DOCTYPE'));
  const svgTag = html.match(/<svg[^>]*>/)[0];
  assert.ok(!/\swidth=/.test(svgTag) && !/\sheight=/.test(svgTag), svgTag);
  assert.ok(svgTag.includes('role="img"'));
  assert.ok(html.includes('<figcaption>cap &lt;1&gt;</figcaption>'));
});

test('two pictures with the same local id do not collide', () => {
  const dir = makeRun([
    idea('i1', 'safe', { pictures: [{ id: 'p1', caption: 'a', file: 'pictures/a.svg' }, { id: 'p2', caption: 'b', file: 'pictures/a.svg' }] }),
  ]);
  writeFileSync(join(dir, 'pictures/a.svg'), SVG_A);
  const html = assembleOk(dir);
  assert.ok(html.includes('id="i1p1-box"') && html.includes('id="i1p2-box"'));
});

test('slot ordering, stable within slot, numbering and chips', () => {
  const dir = makeRun([
    idea('w1', 'wild'),
    idea('s1', 'safe'),
    idea('t1', 'stretch'),
    idea('r1', 'remove'),
    idea('s2', 'safe'),
    idea('f1', 'fix'),
  ]);
  const html = assembleOk(dir);
  const order = [...html.matchAll(/<article class="idea" id="idea-(\d)" data-slot="(\w+)">/g)].map((m) => `${m[1]}${m[2]}`);
  assert.deepEqual(order, ['1safe', '2safe', '3remove', '4stretch', '5wild', '6fix']);
  const titles = [...html.matchAll(/<h2 class="title">([^<]+)</g)].map((m) => m[1]);
  assert.deepEqual(titles, ['Title s1', 'Title s2', 'Title r1', 'Title t1', 'Title w1', 'Title f1']);
  const chips = [...html.matchAll(/<a href="#idea-(\d)">/g)].map((m) => m[1]);
  assert.deepEqual(chips, ['1', '2', '3', '4', '5', '6']);
  assert.ok(html.includes('<p class="kind">6 · Quick fix</p>'));
  assert.ok(html.includes('<b class="k-fix">Quick fix</b>: a real bug we found, small to fix'));
  assert.ok(html.includes('.idea[data-slot="fix"]{--slot:var(--fix)}'));
  assert.ok(html.includes('<p class="kind">3 · Remove</p>'));
  assert.ok(html.includes('<p class="kind">1 · Safe bet</p>'));
});

test('needs maps idea ids to page numbers; unknown id is a data error', () => {
  const dir = makeRun([idea('w1', 'wild', { needs: ['s1'] }), idea('s1', 'safe'), idea('t1', 'stretch', { needs: ['s1', 'w1'] })]);
  const html = assembleOk(dir);
  assert.ok(html.includes('Needs idea 1 first'));
  assert.ok(html.includes('Needs ideas 1 and 3 first'));
  const bad = makeRun([idea('a', 'safe', { needs: ['nope'] })]);
  const r = run(['--run', bad]);
  assert.equal(r.status, 3);
  assert.match(r.stderr, /nope/);
});

test('words line, size badge, proof, left out, footer', () => {
  const dir = makeRun([
    idea('a', 'safe', { words: [{ term: 'gh', gloss: 'GitHub tool' }, { term: 'PR', gloss: 'code review request' }], size: { blocks: 3, words: 'a few hours' } }),
    idea('b', 'wild', { size: { blocks: 0, words: 'not sure yet' } }),
  ]);
  const html = assembleOk(dir);
  assert.ok(html.includes('<b>gh</b>: GitHub tool · <b>PR</b>: code review request'));
  assert.ok(html.includes('aria-label="3 of 3 blocks"'));
  assert.ok(html.includes('class="blocks unknown"') && html.includes('not sure yet'));
  assert.ok(!html.includes('a few hours'));
  assert.ok(html.includes('<details><summary>Proof from the code</summary>'));
  assert.ok(html.includes('<code>src/a.rs:1</code> — does a thing'));
  assert.ok(html.includes('<b>Gives up:</b> one branch'));
  assert.ok(html.includes('<h2 id="left-out-h">What we left out</h2>'));
  assert.ok(html.includes('7 ideas were left out in all.'));
  assert.ok(html.includes('Run key 00000001abcdef · 2026-10-11'));
  assert.ok(html.includes('<h1>Ideas for demo</h1>'));
  assert.ok(html.includes('Each card shows one idea: what changes, small before-and-after pictures, how big it is, and a first test.'));
  assert.ok(html.includes('<b class="k-safe">Safe bet</b>: most useful, with clear proof'));
  assert.ok(html.includes('<b class="k-wild">Wild card</b>: the boldest idea, a bet'));
  assert.ok(!html.includes('<b class="k-remove">') && !html.includes('<b class="k-stretch">'));
  assert.ok(!html.includes('Show why it failed') && !html.includes('class="sample'));
  assert.ok(html.includes('</span> weeks</span>'));
  assert.equal((html.match(/How to read a card/g) || []).length, 1);
  assert.ok(html.includes("Why it's here:"));
  assert.ok(html.includes('First test:'));
});

test('theme tokens, dark mode blocks, body colours, reduced motion', () => {
  const html = assembleOk(makeRun([idea('a', 'safe')]));
  for (const v of ['--paper', '--card', '--ink', '--muted', '--line', '--accent', '--accent-soft', '--font', '--mono', '--display', '--safe', '--stretch', '--wild', '--remove', '--fix']) {
    assert.ok(html.includes(`${v}:`), v);
  }
  assert.ok(html.includes('@media (prefers-color-scheme: dark){:root:not([data-theme="light"]){'));
  assert.ok(html.includes(':root[data-theme="dark"]{'));
  assert.match(html, /body\{[^}]*background:var\(--paper\);color:var\(--ink\)/);
  assert.ok(html.includes('prefers-reduced-motion'));
  assert.ok(html.includes('minmax(min(100%,320px),1fr)'));
  assert.ok(html.includes('max-width:72rem'));
});

test('--artifact strips the document shell, default keeps it', () => {
  const dir = makeRun([idea('a', 'safe')]);
  const full = assembleOk(dir);
  assert.ok(/^<!doctype html>/i.test(full));
  for (const t of ['<html', '<head>', '<body>', '<meta name="viewport"']) assert.ok(full.includes(t), t);
  const art = assembleOk(dir, ['--artifact']);
  assert.ok(!/<!doctype/i.test(art));
  for (const t of ['<html', '</html>', '<head>', '</head>', '<body', '</body>']) assert.ok(!art.includes(t), t);
  assert.ok(art.includes('<title>Ideas for demo</title>'));
  assert.ok(art.includes('<style>'));
  assert.ok(art.includes('<article class="idea"'));
});

test('--out writes to the given file', () => {
  const dir = makeRun([idea('a', 'safe')]);
  const out = join(dir, 'sub', 'custom.html');
  const r = run(['--run', dir, '--out', out]);
  assert.equal(r.status, 0, r.stderr);
  assert.ok(readFileSync(out, 'utf8').includes('<article'));
});

test('missing picture file exits 3 and names the path', () => {
  const dir = makeRun([idea('a', 'safe', { pictures: [{ id: 'p1', caption: 'c', file: 'pictures/missing.svg' }] })]);
  const r = run(['--run', dir]);
  assert.equal(r.status, 3);
  assert.ok(r.stderr.includes(join(dir, 'pictures/missing.svg')), r.stderr);
});

test('missing final.json and invalid json exit 3', () => {
  const empty = mkdtempSync(join(tmpdir(), 'assemble-test-'));
  assert.equal(run(['--run', empty]).status, 3);
  writeFileSync(join(empty, 'final.json'), '{nope');
  assert.equal(run(['--run', empty]).status, 3);
});

test('bad args exit 2', () => {
  assert.equal(run([]).status, 2);
  assert.equal(run(['--bogus']).status, 2);
  assert.equal(run(['--run']).status, 2);
  const dir = makeRun([idea('a', 'safe')]);
  const r = run(['--run', dir, '--look', 'nope']);
  assert.equal(r.status, 2);
  assert.match(r.stderr, /nope/);
});

test('unsafe SVG is rejected with exit 1', () => {
  const cases = {
    script: '<svg viewBox="0 0 1 1"><script>x()</script></svg>',
    foreign: '<svg viewBox="0 0 1 1"><foreignObject><div/></foreignObject></svg>',
    onclick: '<svg viewBox="0 0 1 1"><rect onclick="x()" width="1" height="1"/></svg>',
    onload: '<svg viewBox="0 0 1 1" onload = "x()"></svg>',
  };
  for (const [name, svg] of Object.entries(cases)) {
    const dir = makeRun([idea('a', 'safe', { pictures: [{ id: 'p1', caption: 'c', file: 'pictures/a.svg' }] })]);
    writeFileSync(join(dir, 'pictures/a.svg'), svg);
    const r = run(['--run', dir]);
    assert.equal(r.status, 1, name);
    assert.ok(r.stderr.length > 0);
  }
});

test('svg text containing the word "on" or "version=" is not rejected', () => {
  const dir = makeRun([idea('a', 'safe', { pictures: [{ id: 'p1', caption: 'c', file: 'pictures/a.svg' }] })]);
  writeFileSync(join(dir, 'pictures/a.svg'), '<svg viewBox="0 0 1 1"><text>turn on version=2 icon=3</text></svg>');
  assert.equal(run(['--run', dir]).status, 0);
});

function lum(hex) {
  const c = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255).map((v) => (v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4));
  return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
}
function ratio(a, b) {
  const [hi, lo] = [lum(a), lum(b)].sort((x, y) => y - x);
  return (hi + 0.05) / (lo + 0.05);
}

test('looks: 8 distinct looks with the full schema', () => {
  assert.equal(LOOKS.length, 8);
  assert.equal(new Set(LOOKS.map((l) => l.id)).size, 8);
  assert.ok(new Set(LOOKS.map((l) => l.card_style)).size >= 4);
  assert.ok(new Set(LOOKS.map((l) => l.light.paper)).size === 8);
  for (const l of LOOKS) {
    for (const theme of ['light', 'dark']) {
      for (const k of ['paper', 'card', 'ink', 'muted', 'line', 'accent', 'accent_soft', 'safe', 'stretch', 'wild', 'remove', 'fix']) {
        assert.match(l[theme][k], /^#[0-9a-f]{6}$/i, `${l.id} ${theme} ${k}`);
      }
      const slots = ['safe', 'stretch', 'wild', 'remove', 'fix'].map((s) => l[theme][s].toLowerCase());
      assert.equal(new Set(slots).size, 5, `${l.id} ${theme} slot colours must be distinct`);
    }
  }
});

test('looks: contrast meets WCAG in both themes', () => {
  for (const l of LOOKS) {
    for (const theme of ['light', 'dark']) {
      const p = l[theme];
      const at = `${l.id}/${theme}`;
      assert.ok(ratio(p.ink, p.paper) >= 4.5, `${at} ink/paper ${ratio(p.ink, p.paper).toFixed(2)}`);
      assert.ok(ratio(p.ink, p.card) >= 4.5, `${at} ink/card ${ratio(p.ink, p.card).toFixed(2)}`);
      assert.ok(ratio(p.muted, p.card) >= 4.5, `${at} muted/card ${ratio(p.muted, p.card).toFixed(2)}`);
      assert.ok(ratio(p.muted, p.paper) >= 4.5, `${at} muted/paper ${ratio(p.muted, p.paper).toFixed(2)}`);
      assert.ok(ratio(p.accent, p.card) >= 3, `${at} accent/card ${ratio(p.accent, p.card).toFixed(2)}`);
      assert.ok(ratio(p.accent, p.paper) >= 3, `${at} accent/paper ${ratio(p.accent, p.paper).toFixed(2)}`);
      assert.ok(ratio(p.ink, p.accent_soft) >= 4.5, `${at} ink/accent_soft ${ratio(p.ink, p.accent_soft).toFixed(2)}`);
      for (const s of ['safe', 'stretch', 'wild', 'remove', 'fix']) assert.ok(ratio(p[s], p.card) >= 3, `${at} ${s}/card ${ratio(p[s], p.card).toFixed(2)}`);
    }
  }
});

test('look is derived deterministically from the key; --look overrides', () => {
  for (let i = 0; i < LOOKS.length * 2; i++) {
    const key = i.toString(16).padStart(8, '0') + 'ffff';
    const dir = makeRun([idea('a', 'safe')], { key });
    const a = assembleOk(dir);
    const b = assembleOk(dir);
    assert.equal(a, b);
    assert.ok(a.includes(`data-look="${LOOKS[i % LOOKS.length].id}"`), `key ${key}`);
  }
  const dir = makeRun([idea('a', 'safe')], { key: '00000000' });
  assert.ok(assembleOk(dir, ['--look', 'blueprint']).includes('data-look="blueprint"'));
  const nonHex = makeRun([idea('a', 'safe')], { key: 'zzzz' });
  assert.equal(run(['--run', nonHex]).status, 3);
});

test('google font looks include a fonts.googleapis.com link, system looks include none', () => {
  const dir = makeRun([idea('a', 'safe')]);
  for (const l of LOOKS) {
    const html = assembleOk(dir, ['--look', l.id]);
    assert.equal(html.includes('<link rel="stylesheet" href="https://fonts.googleapis.com/'), Boolean(l.fonts.google_href), l.id);
  }
});

test('top key shows the size badge three times plus unknown, same markup as cards', () => {
  const dir = makeRun([idea('a', 'safe', { size: { blocks: 2, words: 'x' } })]);
  const html = assembleOk(dir);
  const key = html.slice(html.indexOf('<p class="size-key">'), html.indexOf('</section>'));
  const sq = (n) => [1, 2, 3].map((k) => `<i${k <= n ? ' class="on"' : ''}></i>`).join('');
  assert.ok(key.includes(`<span class="blocks" role="img" aria-label="1 of 3 blocks">${sq(1)}</span> hours</span>`));
  assert.ok(key.includes(`aria-label="2 of 3 blocks">${sq(2)}</span> days</span>`));
  assert.ok(key.includes(`aria-label="3 of 3 blocks">${sq(3)}</span> weeks</span>`));
  assert.ok(key.includes('<span class="blocks unknown" role="img" aria-label="size unknown"><i>?</i></span> not sure yet</span>'));
  assert.ok(html.indexOf('class="k-safe"') < html.indexOf('<p class="size-key">'));
});

test('glosses are unified: first gloss in page order wins, case-insensitive', () => {
  const dir = makeRun([
    idea('w', 'wild', { words: [{ term: 'PR', gloss: 'wild wording' }] }),
    idea('s', 'safe', { words: [{ term: 'pr', gloss: 'safe wording' }, { term: 'cli', gloss: 'command tool' }] }),
    idea('t', 'stretch', { words: [{ term: 'Cli', gloss: 'other wording' }] }),
  ]);
  const html = assembleOk(dir);
  assert.ok(html.includes('<b>pr</b>: safe wording · <b>cli</b>: command tool'));
  assert.ok(html.includes('<b>Cli</b>: command tool'));
  assert.ok(html.includes('<b>PR</b>: safe wording'));
  assert.ok(!html.includes('wild wording') && !html.includes('other wording'));
});

test('about renders under h1 before the headline; absent means no about paragraph', () => {
  const html = assembleOk(makeRun([idea('a', 'safe')], { about: 'Demo is a CLI for <devs>.' }));
  const h1 = html.indexOf('</h1>');
  const about = html.indexOf('<p class="about">Demo is a CLI for &lt;devs&gt;.</p>');
  assert.ok(h1 > -1 && about > h1 && html.indexOf('<p class="headline">') > about);
  assert.ok(!assembleOk(makeRun([idea('a', 'safe')])).includes('<p class="about">'));
});

test('about must be a non-empty string when present', () => {
  assert.equal(run(['--run', makeRun([idea('a', 'safe')], { about: 5 })]).status, 3);
  assert.equal(run(['--run', makeRun([idea('a', 'safe')], { about: '' })]).status, 3);
});

test('chip kind word never breaks inside a word', () => {
  const html = assembleOk(makeRun([idea('a', 'safe')]));
  assert.match(html, /\.chips \.k\{[^}]*white-space:nowrap/);
});
