#!/usr/bin/env node
// node check.mjs <page.html> — checks a smoothbrain page against references/page.md.
// Prints FAIL / WARN / ok lines. Exit 1 on any FAIL.
import { readFileSync } from 'node:fs';

const RUNGS = ['big-picture', 'parts', 'moves', 'detail', 'words'];
const MAX_WORDS = 25;
const MAX_TERMS = 5;

const file = process.argv[2];
if (!file) {
  console.error('usage: node check.mjs <page.html>');
  process.exit(2);
}
const html = readFileSync(file, 'utf8').replace(/<(script|style)\b[\s\S]*?<\/\1>/gi, '');

const results = [];
const fail = msg => results.push(`FAIL ${msg}`);
const warn = msg => results.push(`WARN ${msg}`);
const ok = msg => results.push(`ok   ${msg}`);

const decode = s => s.replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;/g, "'");
// Visible prose: no SVG text, no code.
const prose = s => decode(s.replace(/<(svg|pre|code)\b[\s\S]*?<\/\1>/gi, ' ').replace(/<[^>]+>/g, ' ')).replace(/\s+/g, ' ').trim();
const count = (s, re) => (s.match(re) || []).length;

const sections = {};
const order = [];
for (const m of html.matchAll(/<section\b[^>]*data-zoom="([^"]+)"[^>]*>([\s\S]*?)<\/section>/gi)) {
  sections[m[1]] = m[2];
  order.push(m[1]);
}

// 1. Rungs present and in order.
const missing = RUNGS.filter(r => !(r in sections));
if (missing.length) fail(`missing rung: ${missing.join(', ')}`);
const seen = order.filter(r => RUNGS.includes(r));
if (!missing.length) {
  if (seen.join() === RUNGS.join()) ok('five rungs in order');
  else fail(`rungs out of order: ${seen.join(' > ')} (want ${RUNGS.join(' > ')})`);
}

// 2. Each rung holds what it must.
const big = sections['big-picture'];
if (big !== undefined) {
  if (/<svg\b|<img\b|<canvas\b/i.test(big)) ok('big-picture has a picture');
  else fail('big-picture has no picture (svg, img or canvas)');
  if (/<svg\b/i.test(big) && !/<svg\b[^>]*(role="img"|aria-label)/i.test(big)) warn('big-picture svg has no role="img" or aria-label');
}
if (sections.parts !== undefined) {
  const n = count(sections.parts, /<article\b[^>]*class="[^"]*\bpart\b/gi);
  if (n >= 3 && n <= 5) ok(`${n} parts`);
  else fail(`parts: ${n} cards (want 3 to 5 article.part)`);
}
if (sections.moves !== undefined) {
  const n = count(sections.moves, /\bdata-step\b/gi);
  if (n >= 3) ok(`${n} steps`);
  else fail(`moves: ${n} steps (want 3 or more [data-step])`);
}
if (sections.detail !== undefined) {
  if (/<details\b/i.test(sections.detail)) ok('detail has details');
  else fail('detail has no <details> section');
}

// 3. Words card: every term is used on the page.
const terms = sections.words === undefined ? [] :
  [...sections.words.matchAll(/<dt\b[^>]*>([\s\S]*?)<\/dt>/gi)].map(m => prose(m[1])).filter(Boolean);
const restText = prose(Object.entries(sections).filter(([k]) => k !== 'words').map(([, v]) => v).join(' ')).toLowerCase();
const hasWord = (text, w) => new RegExp(`(^|[^\\p{L}\\p{N}])${w.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}($|[^\\p{L}\\p{N}])`, 'iu').test(text);
if (sections.words !== undefined) {
  if (!terms.length) fail('words card has no <dt> terms');
  const unused = terms.filter(t => !hasWord(restText, t.toLowerCase()));
  if (unused.length) fail(`words card terms not used on the page: ${unused.join(', ')}`);
  else if (terms.length) ok(`${terms.length} terms, all used`);
  if (terms.length > MAX_TERMS) warn(`${terms.length} terms (aim for ${MAX_TERMS} or fewer new terms)`);
}

// 4. Sentences: 25 words max in visible prose.
const blocks = [...html.matchAll(/<(p|li|dd|figcaption|h1|h2|h3|summary|td)\b[^>]*>([\s\S]*?)<\/\1>/gi)].map(m => prose(m[2]));
let long = 0;
for (const b of blocks) {
  for (const s of b.split(/(?<=[.!?])\s+/)) {
    const words = s.split(/\s+/).filter(w => /[\p{L}\p{N}]/u.test(w)).length;
    if (words > MAX_WORDS) {
      long++;
      fail(`sentence of ${words} words (max ${MAX_WORDS}): "${s.slice(0, 80)}…"`);
    }
  }
}
if (!long) ok(`every sentence ${MAX_WORDS} words or fewer`);

// 5. Acronyms: the first use sits next to its meaning in parentheses, or the words card has it.
const text = prose(html);
const termSet = new Set(terms.map(t => t.toLowerCase()));
const done = new Set();
const bad = [];
for (const m of text.matchAll(/(?<![\p{L}\p{N}-])[A-Z][A-Z0-9]+(?:-[A-Z0-9]+)*s?(?![\p{L}\p{N}])/gu)) {
  const word = m[0].replace(/s$/, '');
  if (done.has(word) || !/[A-Z].*[A-Z]/.test(word)) continue;
  done.add(word);
  const before = text.slice(0, m.index).trimEnd();
  const after = text.slice(m.index + m[0].length).trimStart();
  if (before.endsWith('(') || after.startsWith('(') || termSet.has(word.toLowerCase())) continue;
  bad.push(word);
}
if (bad.length) fail(`acronyms with no meaning beside the first use: ${bad.join(', ')}`);
else ok('every acronym explained');

console.log(results.join('\n'));
process.exit(results.some(r => r.startsWith('FAIL')) ? 1 : 0);
