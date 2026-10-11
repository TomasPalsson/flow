// node --test check.test.mjs — one passing page, then one failing page per check.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
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

// Text rules in SKILL.md: the grounding ledger (section 3) and its check bullet.
const SKILL = readFileSync(join(dirname(SCRIPT), '..', 'SKILL.md'), 'utf8');

test('SKILL.md section 3 carries the grounding rule', () => {
  const s3 = SKILL.slice(SKILL.indexOf('## 3. The zoom ladder'), SKILL.indexOf('## 4. Pictures'));
  assert.match(s3, /Before writing, list the concepts the reader brings/);
  assert.match(s3, /only those concepts and the ones earlier rungs showed/);
});

test('SKILL.md "It is working if" has the grounding bullet', () => {
  const w = SKILL.slice(SKILL.indexOf('## It is working if'));
  assert.match(w, /No card or step needs an idea the page has not shown above it\./);
});

// Inline scripts must parse: a raw </script> inside a string ends the script early.
const withScript = body => page().replace(/<script>[\s\S]*<\/script>/, body);

test('a raw </script> inside a JS string fails with the script line', () => {
  const r = check(withScript('<script>\nconst s = "</script>";\n</script>'));
  assert.equal(r.code, 1, r.out);
  assert.match(r.out, /FAIL.*inline script.*line \d+/);
});

test('the same string with the closing tag escaped passes', () => {
  const r = check(withScript('<script>\nconst s = "<\\/script>";\n</script>'));
  assert.equal(r.code, 0, r.out);
  assert.match(r.out, /ok .*inline scripts? parse/);
});

test('invalid JSON in a type=application/json script fails, valid JSON passes', () => {
  const bad = check(withScript('<script type="application/json" id="d">{"a": </script>'));
  assert.equal(bad.code, 1, bad.out);
  assert.match(bad.out, /FAIL.*JSON/);
  const good = check(withScript('<script type="application/json" id="d">{"a": "\\u003c/script>"}</script>'));
  assert.equal(good.code, 0, good.out);
});

test('a script with src is not parsed', () => {
  const r = check(withScript('<script src="x.js"></script>'));
  assert.equal(r.code, 0, r.out);
});

// Know/Fuzzy/Lost marking: toggles need a visible request box.
const MARK = '<button data-mark="fuzzy">fuzzy</button>';
const GAP = '<textarea readonly data-gap-request>Explain deeper:</textarea>';
const marked = extra => page({ ...SECTIONS, parts: SECTIONS.parts.replace('</section>', `${MARK}${extra}</section>`) });

test('[data-mark] toggles without a [data-gap-request] textarea warn', () => {
  const r = check(marked(''));
  assert.equal(r.code, 0, r.out);
  assert.match(r.out, /WARN.*data-gap-request/);
});

test('toggles with the request textarea are clean', () => {
  const r = check(marked(GAP));
  assert.equal(r.code, 0, r.out);
  assert.doesNotMatch(r.out, /WARN/);
});

test('page.md and SKILL.md carry the gap-marking snippet and the script-escape rule', () => {
  const pageMd = readFileSync(join(dirname(SCRIPT), '..', 'references', 'page.md'), 'utf8');
  assert.match(pageMd, /data-gap-request/);
  assert.match(pageMd, /select\(\)/);
  assert.match(pageMd, /escape `<` as `\\u003c`/);
  const s5 = SKILL.slice(SKILL.indexOf('## 5. Build and ship'), SKILL.indexOf('## It is working if'));
  assert.match(s5, /3 or more part cards/);
  assert.match(s5, /Ask about the gaps/);
});

test('a plural on the page counts as a use of the term', () => {
  const r = check(page({ ...SECTIONS, words: SECTIONS.words.replace('</dl>', '<dt>arrival</dt><dd>A job coming in.</dd></dl>'), moves: SECTIONS.moves.replace('A job arrives.', 'Two arrivals come.') }));
  assert.equal(r.code, 0, r.out);
});

// --repo: code names on the page must exist in the repo that was read.
// Credit: adapted from anthropics/claude-plugins-official plugins/code-modernization/commands/modernize-map.md @ a9fd216 (Apache-2.0).
const repoWith = files => {
  const d = mkdtempSync(join(tmpdir(), 'sb-repo-'));
  for (const [name, body] of Object.entries(files)) {
    mkdirSync(dirname(join(d, name)), { recursive: true });
    writeFileSync(join(d, name), body);
  }
  return d;
};
const withCode = code => page({ ...SECTIONS, detail: SECTIONS.detail.replace('</details>', `${code}</details>`) });
const checkRepo = (html, repo) => {
  const f = join(dir, `r${Math.random().toString(36).slice(2)}.html`);
  writeFileSync(f, html);
  const r = spawnSync('node', [SCRIPT, f, '--repo', repo], { encoding: 'utf8' });
  return { code: r.status, out: r.stdout + r.stderr };
};

test('--repo: a call the repo lacks fails', () => {
  const r = checkRepo(withCode('<p>It calls <code>parseInvoice()</code>.</p>'), repoWith({ 'a.js': 'function other() {}' }));
  assert.equal(r.code, 1, r.out);
  assert.match(r.out, /FAIL.*parseInvoice\(\)/);
});

test('--repo: the same page passes when the repo has the call', () => {
  const r = checkRepo(withCode('<p>It calls <code>parseInvoice()</code>.</p>'), repoWith({ 'a.js': 'function parseInvoice() {}' }));
  assert.equal(r.code, 0, r.out);
  assert.match(r.out, /ok.*1 repo name found/);
});

test('--repo: a missing path fails, an existing path passes', () => {
  const html = withCode('<p>See <code>src/billing/pay.ts</code>.</p>');
  assert.equal(checkRepo(html, repoWith({ 'a.js': 'x' })).code, 1);
  assert.equal(checkRepo(html, repoWith({ 'src/billing/pay.ts': 'x' })).code, 0);
});

test('--repo: a missing plain identifier warns only', () => {
  const r = checkRepo(withCode('<p>The <code>retryCount</code> field.</p>'), repoWith({ 'a.js': 'x' }));
  assert.equal(r.code, 0, r.out);
  assert.match(r.out, /WARN.*retryCount/);
});

test('--repo: commands, status codes, library APIs and external blocks stay clean', () => {
  const html = withCode('<p>Run <code>npm test</code>; a <code>404</code> comes back; <code>Promise.all()</code> waits.</p><pre data-external><code>fakeThing()</code></pre>');
  const r = checkRepo(html, repoWith({ 'a.js': 'x' }));
  assert.equal(r.code, 0, r.out);
  assert.doesNotMatch(r.out, /WARN|FAIL/);
});

test('--repo: a bad directory is a usage error, and no --repo checks nothing', () => {
  assert.equal(checkRepo(withCode(''), join(dir, 'nope')).code, 2);
  const r = check(withCode('<p><code>parseInvoice()</code></p>'));
  assert.equal(r.code, 0, r.out);
});

test('--repo: a page saved inside the repo is not evidence for its own names', () => {
  const d = repoWith({ 'a.js': 'function other() {}' });
  const f = join(d, 'explain.html');
  writeFileSync(f, withCode('<p><code>parseInvoice()</code> <code>src/billing/pay.ts</code></p>'));
  const r = spawnSync('node', [SCRIPT, f, '--repo', d], { encoding: 'utf8' });
  assert.equal(r.status, 1, r.stdout);
  assert.match(r.stdout, /FAIL.*parseInvoice\(\)/);
});

test('--repo: the git branch finds tracked and ignored names, and fails missing ones', () => {
  const d = repoWith({ 'a.js': 'function tracked() {}', 'gen/b.js': 'function generated() {}', '.gitignore': 'gen/\n' });
  spawnSync('git', ['-C', d, 'init', '-q']);
  spawnSync('git', ['-C', d, 'add', 'a.js', '.gitignore']);
  assert.equal(checkRepo(withCode('<p><code>tracked()</code> <code>generated()</code></p>'), d).code, 0);
  assert.equal(checkRepo(withCode('<p><code>nopeFnZZ()</code></p>'), d).code, 1);
});

test('--repo: slash tokens that are not file paths are not checked', () => {
  const r = checkRepo(withCode('<p><code>application/json</code> <code>upstream/dev</code> <code>24/7</code></p>'), repoWith({ 'a.js': 'x' }));
  assert.equal(r.code, 0, r.out);
});

test('SKILL.md step 5 passes --repo when explaining a path or repo', () => {
  const s5 = SKILL.slice(SKILL.indexOf('## 5. Build and ship'), SKILL.indexOf('## It is working if'));
  assert.match(s5, /--repo/);
});
