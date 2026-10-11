// Tests for check.mjs and shot.mjs. Run: node --test check.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { staticCheck, renderCheck, svgCheck } from './check.mjs';
import { findChrome } from './shot.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const CHECK = path.join(here, 'check.mjs');
const SHOT = path.join(here, 'shot.mjs');
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'bcheck-test-'));
test.after(() => fs.rmSync(tmp, { recursive: true, force: true }));

const svg = (extra = '', texts = '<text x="20" y="60" font-size="14">hello</text>', vb = '0 0 360 220', id = 'a') =>
  `<svg viewBox="${vb}" role="img"><title>claim ${id}</title>${texts}${extra}</svg>`;
const fig = (inner, cap = 'Today it is slow.') => `<figure>${inner}<figcaption>${cap}</figcaption></figure>`;
const article = (n, inner) =>
  `<article class="idea" id="idea-${n}"><h2 class="title">Show the reason</h2><p class="sentence">It says why.</p>${inner}</article>`;
const page = (arts) => `<!doctype html><html><head><title>t</title><style>.x{color:#fff}</style></head><body>${arts}</body></html>`;
const good = (n = 1) => article(n, fig(svg('', undefined, undefined, `s${n}`)));

const has = (list, ...bits) => list.some((l) => bits.every((b) => l.includes(b)));

test('clean page has no fails or warns', () => {
  const r = staticCheck(page(good(1) + good(2)));
  assert.deepEqual(r.fails, []);
  assert.deepEqual(r.warns, []);
  assert.ok(r.oks.length > 0);
});

test('script src and chart library names fail', () => {
  let r = staticCheck(page(good() + '<script src="x.js"></script>'));
  assert.ok(has(r.fails, 'external script'));
  r = staticCheck(page(good() + '<p>we use Mermaid here</p>'));
  assert.ok(has(r.fails, 'chart library'));
});

test('idea count: none fails, twelve fails, eleven ok', () => {
  assert.ok(has(staticCheck(page('<p>x</p>')).fails, 'no <article class="idea">'));
  const twelve = Array.from({ length: 12 }, (_, i) => article(i + 1, '')).join('');
  assert.ok(has(staticCheck(page(twelve)).fails, '12 ideas'));
  const eleven = Array.from({ length: 11 }, (_, i) => good(i + 1)).join('');
  assert.ok(!has(staticCheck(page(eleven)).fails, 'ideas, at most'));
});

test('more than 4 svgs fails, zero svgs warns', () => {
  const five = article(1, Array.from({ length: 5 }, (_, i) => fig(svg('', undefined, undefined, `v${i}`), `cap ${i}`)).join(''));
  assert.ok(has(staticCheck(page(five)).fails, 'idea-1', '5 svgs'));
  const r = staticCheck(page(article(1, '')));
  assert.ok(has(r.warns, 'idea-1', 'no pictures'));
});

test('svg missing role, title, wrong viewBox width', () => {
  const noRole = '<svg viewBox="0 0 360 220"><title>t</title></svg>';
  assert.ok(has(staticCheck(page(article(1, fig(noRole)))).fails, 'idea-1 svg1', 'role="img"'));
  const noTitle = '<svg viewBox="0 0 360 220" role="img"><text font-size="14">a</text></svg>';
  assert.ok(has(staticCheck(page(article(1, fig(noTitle)))).fails, 'idea-1 svg1', '<title>'));
  const wide = svg('', undefined, '0 0 400 220');
  assert.ok(has(staticCheck(page(article(1, fig(wide)))).fails, 'viewBox width must be 360'));
});

test('forbidden svg content fails', () => {
  for (const bad of ['<image href="a.png"/>', '<foreignObject></foreignObject>', '<style>.a{}</style>', '<rect filter="url(#f)"/>', '<linearGradient id="g"/>', '<radialGradient id="h"/>', '<script>1</script>']) {
    const r = staticCheck(page(article(1, fig(svg(bad)))));
    assert.ok(has(r.fails, 'idea-1 svg1', 'forbidden'), bad);
  }
});

test('font size under 13 fails (attribute and style), 13 passes', () => {
  assert.ok(has(staticCheck(page(article(1, fig(svg('', '<text font-size="12">a</text>'))))).fails, 'font-size 12'));
  assert.ok(has(staticCheck(page(article(1, fig(svg('', '<text style="font-size: 10px">a</text>'))))).fails, 'font-size 10'));
  assert.ok(!has(staticCheck(page(article(1, fig(svg('', '<text font-size="13">a</text>'))))).fails, 'font-size'));
});

test('more than 14 text elements fails', () => {
  const many = Array.from({ length: 15 }, (_, i) => `<text x="1" y="${i}" font-size="14">t${i}</text>`).join('');
  assert.ok(has(staticCheck(page(article(1, fig(svg('', many))))).fails, '15 <text>'));
});

test('raw hex in fill warns', () => {
  const r = staticCheck(page(article(1, fig(svg('<rect fill="#ff0000"/>')))));
  assert.ok(has(r.warns, 'idea-1 svg1', 'hex'));
  assert.ok(!has(r.fails, 'hex'));
});

test('duplicate ids fail', () => {
  const r = staticCheck(page(good(1) + article(2, '<p id="x">a</p><p id="x">b</p>')));
  assert.ok(has(r.fails, 'duplicate id "x"'));
});

test('sentence and title word limits', () => {
  const long21 = Array.from({ length: 21 }, () => 'w').join(' ');
  const a = `<article class="idea" id="idea-1"><h2 class="title">${Array.from({ length: 10 }, () => 'w').join(' ')}</h2><p class="sentence">${long21}.</p></article>`;
  const r = staticCheck(page(a));
  assert.ok(has(r.fails, 'idea-1', 'sentence has 21 words'));
  assert.ok(has(r.fails, 'idea-1', 'title has 10 words'));
  assert.ok(has(r.warns, 'sentence over 25') === false);
});

test('prose sentence over 25 words warns', () => {
  const s = Array.from({ length: 26 }, () => 'w').join(' ');
  const a = `<article class="idea" id="idea-1"><p class="why">${s}. Short one.</p></article>`;
  assert.ok(has(staticCheck(page(a)).warns, 'idea-1', 'over 25 words'));
});

test('jargon fails outside code/details, allowed inside', () => {
  const bad = ['passport', 'Foundation tier', 'treemap', 'quadrant', 'DAG', 'linked brushing', 'cited_findings', 'L3', 'synergy', 'leverage', 'holistic', 'robust', 'seamless', 'paradigm'];
  for (const w of bad) {
    const r = staticCheck(page(article(1, `<p>This is ${w} here</p>`)));
    assert.ok(has(r.fails, `jargon word`), w);
  }
  const okPage = page(article(1, '<code>DAG L3</code><details><p>robust synergy</p></details><p>a dagger and L33 and delight</p>'));
  assert.ok(!has(staticCheck(okPage).fails, 'jargon'));
});

test('figure needs a figcaption of at most 16 words; duplicates warn', () => {
  const s = svg('', undefined, undefined, 'q');
  assert.ok(has(staticCheck(page(article(1, `<figure>${s}</figure>`))).fails, 'idea-1 fig1', 'no <figcaption>'));
  const long = Array.from({ length: 17 }, () => 'w').join(' ');
  assert.ok(has(staticCheck(page(article(1, fig(s, long)))).fails, 'figcaption has 17 words'));
  const dup = article(1, fig(svg('', undefined, undefined, 'a'), 'Same.') + fig(svg('', undefined, undefined, 'b'), 'Same.'));
  assert.ok(has(staticCheck(page(dup)).warns, 'idea-1', 'same figcaption'));
});

test('CLI: exit codes, json and bad args', () => {
  const ok = path.join(tmp, 'ok.html');
  const bad = path.join(tmp, 'bad.html');
  fs.writeFileSync(ok, page(good()));
  fs.writeFileSync(bad, page('<p>nothing</p>'));
  let r = spawnSync('node', [CHECK, ok], { encoding: 'utf8' });
  assert.equal(r.status, 0, r.stdout + r.stderr);
  assert.match(r.stdout, /0 fail/);
  r = spawnSync('node', [CHECK, bad, '--json'], { encoding: 'utf8' });
  assert.equal(r.status, 1);
  const j = JSON.parse(r.stdout);
  assert.ok(j.fails.length > 0 && Array.isArray(j.warns) && Array.isArray(j.oks));
  assert.equal(spawnSync('node', [CHECK], { encoding: 'utf8' }).status, 2);
  assert.equal(spawnSync('node', [CHECK, ok, '--nope'], { encoding: 'utf8' }).status, 2);
  assert.equal(spawnSync('node', [CHECK, path.join(tmp, 'missing.html')], { encoding: 'utf8' }).status, 3);
  assert.equal(spawnSync('node', [SHOT, ok], { encoding: 'utf8' }).status, 2);
  assert.equal(spawnSync('node', [SHOT, path.join(tmp, 'missing.html'), path.join(tmp, 'o.png')], { encoding: 'utf8' }).status, 3);
});

let chrome = null;
try {
  chrome = findChrome();
} catch {
  /* treated as no Chrome */
}

test('render: overlapping texts fail, clean passes', { skip: chrome ? false : 'no Chrome found' }, () => {
  const over = svg('', '<text x="20" y="100" font-size="20">first label</text><text x="30" y="104" font-size="20">second label</text>');
  const r1 = renderCheck(page(article(1, fig(over))), chrome);
  assert.ok(has(r1.fails, 'idea-1 svg1', '"first label"', '"second label"', 'overlaps'), r1.fails.join('\n'));
  const clean = svg('', '<text x="20" y="60" font-size="16">first</text><text x="20" y="160" font-size="16">second</text>');
  const r2 = renderCheck(page(article(1, fig(clean))), chrome);
  assert.deepEqual(r2.fails, []);
  assert.equal(r2.oks.length, 2);
});

test('render: text outside the svg and sideways scroll fail', { skip: chrome ? false : 'no Chrome found' }, () => {
  const out = svg('', '<text x="300" y="100" font-size="20">far right edge text</text>');
  const wide = '<div style="width:2000px;height:5px"></div>';
  const r = renderCheck(page(article(1, fig(out)) + wide), chrome);
  assert.ok(has(r.fails, 'idea-1 svg1', 'outside'), r.fails.join('\n'));
  assert.ok(has(r.fails, 'sideways scroll', '390px'), r.fails.join('\n'));
});

test('shot: svg to png', { skip: chrome ? false : 'no Chrome found' }, () => {
  const f = path.join(tmp, 'a.svg');
  const out = path.join(tmp, 'a.png');
  fs.writeFileSync(f, svg());
  const r = spawnSync('node', [SHOT, f, out], { encoding: 'utf8' });
  assert.equal(r.status, 0, r.stderr);
  assert.ok(fs.statSync(out).size > 0);
});

const svgFile = (name, text) => {
  const f = path.join(tmp, name);
  fs.writeFileSync(f, text);
  return f;
};

test('--svg: missing role fails (static, always runs)', () => {
  const f = svgFile('norole.svg', '<svg viewBox="0 0 360 220"><title>t</title><text x="20" y="60" font-size="14">hi</text></svg>');
  const r = spawnSync('node', [CHECK, '--svg', f], { encoding: 'utf8' });
  assert.equal(r.status, 1, r.stdout + r.stderr);
  assert.match(r.stdout, /^norole\.svg: FAIL svg: missing role="img"/m);
  const j = spawnSync('node', [CHECK, '--svg', f, '--json'], { encoding: 'utf8' });
  assert.equal(j.status, 1);
  assert.ok(JSON.parse(j.stdout).fails.some((l) => l.startsWith('norole.svg: FAIL')));
});

test('--svg: bad args exit 2, missing file exits 3', () => {
  assert.equal(spawnSync('node', [CHECK, '--svg'], { encoding: 'utf8' }).status, 2);
  assert.equal(spawnSync('node', [CHECK, '--svg', path.join(tmp, 'x.svg'), 'page.html'], { encoding: 'utf8' }).status, 2);
  assert.equal(spawnSync('node', [CHECK, '--svg', path.join(tmp, 'nope.svg')], { encoding: 'utf8' }).status, 3);
});

test('--svg: without Chrome only static rules run, with a WARN', () => {
  const r = svgCheck(svg(), null);
  assert.deepEqual(r.fails, []);
  assert.ok(has(r.warns, 'no Chrome: render checks skipped'));
});

test('--svg: clean svg exits 0', { skip: chrome ? false : 'no Chrome found' }, () => {
  const f = svgFile('clean.svg', svg('', '<text x="20" y="60" font-size="16">first</text><text x="20" y="160" font-size="16">second</text>'));
  const r = spawnSync('node', [CHECK, '--svg', f], { encoding: 'utf8' });
  assert.equal(r.status, 0, r.stdout + r.stderr);
  assert.match(r.stdout, /clean\.svg: ok render 390px/);
  assert.match(r.stdout, /clean\.svg: ok render 1280px/);
});

test('--svg: overlapping texts fail', { skip: chrome ? false : 'no Chrome found' }, () => {
  const f = svgFile('over.svg', svg('', '<text x="20" y="100" font-size="20">first label</text><text x="30" y="104" font-size="20">second label</text>'));
  const r = spawnSync('node', [CHECK, '--svg', f], { encoding: 'utf8' });
  assert.equal(r.status, 1, r.stdout + r.stderr);
  assert.match(r.stdout, /over\.svg: FAIL idea-1 svg1: text "first label" overlaps "second label"/);
});

test('render: stacked lines at normal spacing pass, tight or same-y lines fail', { skip: chrome ? false : 'no Chrome found' }, () => {
  const run = (texts) => renderCheck(page(article(1, fig(svg('', texts)))), chrome).fails;
  const stacked = run('<text x="20" y="40" font-size="14">Is this a</text><text x="20" y="56" font-size="14">real price?</text>');
  assert.ok(!has(stacked, 'overlaps'), stacked.join('\n'));
  const tight = run('<text x="20" y="40" font-size="14">Is this a</text><text x="20" y="46" font-size="14">real price?</text>');
  assert.ok(has(tight, '"Is this a"', '"real price?"', 'overlaps'), tight.join('\n'));
  const same = run('<text x="20" y="40" font-size="14">Is this a</text><text x="30" y="40" font-size="14">real price?</text>');
  assert.ok(has(same, '"Is this a"', '"real price?"', 'overlaps'), same.join('\n'));
});

test('render: a page with an external Google Fonts link still yields a result', { skip: chrome ? false : 'no Chrome found' }, () => {
  const link = '<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@400;700&amp;display=swap">';
  const html = page(good(1)).replace('</head>', `${link}<style>@import url("https://fonts.googleapis.com/css2?family=Inter");</style></head>`);
  const r = renderCheck(html, chrome);
  assert.deepEqual(r.fails, []);
  assert.ok(has(r.oks, 'ok render 390px'));
});
