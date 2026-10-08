// node --test check.test.mjs — one passing page, then one failing page per check.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const SCRIPT = join(dirname(fileURLToPath(import.meta.url)), 'check.mjs');
const dir = mkdtempSync(join(tmpdir(), 'smoothbrain-'));

const part = n => `<article class="part"><svg></svg><h3>queue ${n}</h3><p>It holds jobs.</p></article>`;
const PARTS = [1, 2, 3].map(part).join('');
const STEPS = '<li data-step>A job arrives.</li><li data-step>The worker takes it.</li><li data-step>The worker finishes.</li>';
const SECTIONS = {
  big: `<section data-zoom="big-picture"><h1>Queues</h1><p class="one-line">A queue holds jobs until a worker is free.</p><svg role="img"><title>q</title></svg></section>`,
  parts: `<section data-zoom="parts">${PARTS}</section>`,
  moves: `<section data-zoom="moves"><ol>${STEPS}</ol></section>`,
  detail: `<section data-zoom="detail"><details><summary>Why</summary><p>The API (application programming interface) is small.</p></details></section>`,
  words: `<section data-zoom="words"><dl><dt>queue</dt><dd>A line of jobs.</dd><dt>worker</dt><dd>A process that does a job.</dd></dl></section>`,
};
const page = (s = SECTIONS) => `<!doctype html><html><body>${Object.values(s).join('\n')}<script>const NOPE = "IGNORED SCRIPT";</script></body></html>`;

function check(html) {
  const f = join(dir, `p${Math.random().toString(36).slice(2)}.html`);
  writeFileSync(f, html);
  const r = spawnSync('node', [SCRIPT, f], { encoding: 'utf8' });
  return { code: r.status, out: r.stdout + r.stderr };
}
const fails = (s, pattern) => {
  const r = check(page({ ...SECTIONS, ...s }));
  assert.equal(r.code, 1, r.out);
  assert.match(r.out, pattern);
};

test('a good page passes', () => {
  const r = check(page());
  assert.equal(r.code, 0, r.out);
  assert.doesNotMatch(r.out, /FAIL/);
});

test('missing rung fails', () => fails({ detail: '' }, /FAIL.*detail/));

test('rungs out of order fail', () => {
  const { big, parts, moves, detail, words } = SECTIONS;
  const r = check(page({ parts, big, moves, detail, words }));
  assert.equal(r.code, 1);
  assert.match(r.out, /FAIL.*order/);
});

test('big picture without a picture fails', () =>
  fails({ big: SECTIONS.big.replace(/<svg[\s\S]*<\/svg>/, '') }, /FAIL.*big-picture.*picture/));

test('two parts fail', () => fails({ parts: `<section data-zoom="parts">${part(1)}${part(2)}</section>` }, /FAIL.*parts/));

test('two steps fail', () =>
  fails({ moves: '<section data-zoom="moves"><li data-step>A.</li><li data-step>B.</li></section>' }, /FAIL.*steps/));

test('detail without details fails', () => fails({ detail: '<section data-zoom="detail"><p>Hi.</p></section>' }, /FAIL.*details/));

test('a sentence over 25 words fails', () => {
  const long = Array.from({ length: 27 }, (_, i) => `word${i}`).join(' ') + '.';
  fails({ moves: SECTIONS.moves.replace('A job arrives.', long) }, /FAIL.*27 words/);
});

test('an acronym with no meaning fails', () =>
  fails({ detail: SECTIONS.detail.replace(' (application programming interface)', '') }, /FAIL.*API/));

test('an acronym in parentheses after its meaning passes', () => {
  const r = check(page({ ...SECTIONS, detail: SECTIONS.detail.replace('The API (application programming interface)', 'The application programming interface (API)') }));
  assert.equal(r.code, 0, r.out);
});

test('a words-card term not used on the page fails', () =>
  fails({ words: SECTIONS.words.replace('</dl>', '<dt>scheduler</dt><dd>Picks the order.</dd></dl>') }, /FAIL.*scheduler/));

test('more than five terms warns', () => {
  const dts = ['queue', 'worker', 'job', 'jobs', 'arrives', 'finishes'].map(t => `<dt>${t}</dt><dd>x.</dd>`).join('');
  const r = check(page({ ...SECTIONS, words: `<section data-zoom="words"><dl>${dts}</dl></section>` }));
  assert.equal(r.code, 0, r.out);
  assert.match(r.out, /WARN.*6 terms/);
});

test('script text is ignored', () => assert.doesNotMatch(check(page()).out, /IGNORED|NOPE/));

test('file names and IDs are not acronyms, and code counts as a use', () => {
  const r = check(page({ ...SECTIONS,
    words: SECTIONS.words.replace('</dl>', '<dt>TASKS.md</dt><dd>The task list.</dd></dl>'),
    moves: SECTIONS.moves.replace('A job arrives.', 'A job lands in <code>TASKS.md</code> as CHK011.') }));
  assert.equal(r.code, 0, r.out);
});

test('a step caption over 20 words fails', () => {
  const s = Array.from({ length: 22 }, (_, i) => `w${i}`).join(' ') + '.';
  fails({ moves: SECTIONS.moves.replace('A job arrives.', s) }, /FAIL.*step.*22 words/);
});

test('a plural on the page counts as a use of the term', () => {
  const r = check(page({ ...SECTIONS, words: SECTIONS.words.replace('</dl>', '<dt>arrival</dt><dd>A job coming in.</dd></dl>'), moves: SECTIONS.moves.replace('A job arrives.', 'Two arrivals come.') }));
  assert.equal(r.code, 0, r.out);
});
