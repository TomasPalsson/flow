// node --test whole-page.test.mjs — the whole-page variants section exists and showcase points to it.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const skills = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const live = readFileSync(join(skills, 'impeccable', 'reference', 'live.md'), 'utf8');
const showcase = readFileSync(join(skills, 'showcase', 'SKILL.md'), 'utf8');
const start = live.indexOf('## Whole-page variants');
const next = live.indexOf('\n## ', start + 1);
const section = live.slice(start, next === -1 ? undefined : next);

test('live.md has a Whole-page variants section', () => {
  assert.ok(live.includes('## Whole-page variants'));
});

test('variants are keyed on ?variant= and keep real data and auth', () => {
  assert.match(section, /\?variant=/);
  assert.match(section, /real data fetching and auth/);
});

test('the switcher is dev-only and ignores typing', () => {
  assert.match(section, /process\.env\.NODE_ENV === 'development'/);
  assert.match(section, /input, textarea or contenteditable/);
});

test('the dev gate lives inside the switcher module, not at the render site', () => {
  assert.match(section, /inside the module that holds the switcher code/);
  assert.match(section, /does not work/);
  assert.match(section, /move the check into the switcher module/);
});

test('losers go to proto/<slug>-variants only after the user picks', () => {
  assert.match(section, /proto\/<slug>-variants/);
  assert.match(section, /After the user picks one/);
  assert.match(section, /branch name/);
});

test('showcase points to the section for real-data comparisons', () => {
  assert.match(showcase, /Whole-page variants/);
  assert.match(showcase, /real data/);
});
