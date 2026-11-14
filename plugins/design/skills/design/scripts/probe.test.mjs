// node --test probe.test.mjs — the polished fixture passes every gated row; the slop fixture fails the ones it plants.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const run = (name) => {
  const r = spawnSync('node', [join(here, 'probe.mjs'), join(here, 'fixtures/probe', name), mkdtempSync(join(tmpdir(), 'probe-')), '--json'], { encoding: 'utf8', timeout: 120000 });
  return { code: r.status, rows: Object.fromEntries(JSON.parse(r.stdout).rows.map((x) => [x.id, x.status])) };
};

test('polished fixture passes every gated row', () => {
  const { code, rows } = run('polished.html');
  assert.equal(code, 0);
  for (const [id, s] of Object.entries(rows)) assert.notEqual(s, 'FAIL', id);
});

test('slop fixture fails the planted tells', () => {
  const { code, rows } = run('slop.html');
  assert.equal(code, 1);
  for (const id of ['hover-feedback', 'press-feedback', 'focus-ring', 'no-transition-all', 'reduced-motion', 'no-static-hover', 'slop-copy', 'no-gradient-text', 'no-emoji-icons']) assert.equal(rows[id], 'FAIL', id);
  for (const id of ['eyebrow-pill', 'default-fonts', 'indigo-actions', 'em-dash-density']) assert.equal(rows[id], 'WARN', id);
});
