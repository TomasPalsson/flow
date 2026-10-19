import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const DATA = JSON.parse(readFileSync(join(here, '..', 'data', 'skins.json'), 'utf8'));
const SKINS = DATA.styles;

const lum = hex => {
  const [r, g, b] = [1, 3, 5].map(i => parseInt(hex.slice(i, i + 2), 16) / 255).map(c => (c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4));
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
};
const contrast = (a, b) => { const [x, y] = [lum(a), lum(b)].sort((p, q) => q - p); return (x + 0.05) / (y + 0.05); };

test('catalog shape: 8+ skins, unique ids, every field pick-style needs, light and dark both present', () => {
  assert.ok(SKINS.length >= 8);
  assert.equal(new Set(SKINS.map(s => s.id)).size, SKINS.length);
  for (const s of SKINS) {
    for (const f of ['id', 'name', 'look', 'traits', 'suits', 'avoid', 'best_for', 'banned', 'tokens']) assert.ok(s[f] !== undefined, `${s.id} missing ${f}`);
    for (const k of s.best_for) assert.ok(DATA.kinds.includes(k), `${s.id}: unknown kind ${k}`);
  }
  assert.ok(SKINS.filter(s => s.tokens.mode === 'dark').length >= 2);
  assert.ok(SKINS.filter(s => s.tokens.mode === 'light').length >= 6);
});

test('clarity: text roles reach 4.5:1 on paper and paper-2, accent-ink 4.5:1 on accent, lines thick enough, type big enough', () => {
  for (const { id, tokens: t } of SKINS) {
    for (const role of ['ink', 'muted', 'soft', 'link', 'accent']) {
      assert.ok(contrast(t[role], t.paper) >= 4.5, `${id}: ${role} on paper ${contrast(t[role], t.paper).toFixed(2)}`);
      if (role !== 'accent') assert.ok(contrast(t[role], t['paper-2']) >= 4.5, `${id}: ${role} on paper-2 ${contrast(t[role], t['paper-2']).toFixed(2)}`);
    }
    assert.ok(contrast(t['accent-ink'], t.accent) >= 4.5, `${id}: accent-ink on accent ${contrast(t['accent-ink'], t.accent).toFixed(2)}`);
    assert.ok(contrast(t.ink, t['accent-tint']) >= 4.5, `${id}: ink on accent-tint`);
    assert.ok(t['stroke-width'] >= 1.25, `${id}: stroke ${t['stroke-width']}`);
    assert.ok(t['name-size'] >= 15 && t['label-size'] >= 13 && t['sub-size'] >= 12, `${id}: type ramp too small`);
  }
});

test('not the upstream house look: no Instrument Serif, Geist, Inter or the burnt-tangerine accent; fonts only from Google Fonts', () => {
  for (const { id, tokens: t } of SKINS) {
    const fonts = `${t['font-title']} ${t['font-ui']} ${t['font-mono']} ${t['fonts-href']}`;
    assert.doesNotMatch(fonts, /Instrument|Geist|\bInter\b|JetBrains/, id);
    assert.match(t['fonts-href'], /^https:\/\/fonts\.googleapis\.com\/css2\?/, id);
    assert.notEqual(t.accent.toLowerCase(), '#bf4520', id);
    for (const fam of [t['font-title'], t['font-ui'], t['font-mono']]) {
      const name = fam.match(/'([^']+)'/)[1].replace(/ /g, '+');
      assert.ok(t['fonts-href'].includes(`family=${name}`) || t['fonts-href'].includes(`family=${name}:`), `${id}: ${name} not in fonts-href`);
    }
  }
  const looks = new Set(SKINS.map(s => `${s.tokens['font-ui']}|${s.tokens.accent}`));
  assert.equal(looks.size, SKINS.length, 'two skins share a font and accent');
});
