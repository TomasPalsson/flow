#!/usr/bin/env node
// node check.mjs <page.html> [--repo <dir>] — checks a smoothbrain page against references/page.md.
// Prints FAIL / WARN / ok lines. Exit 1 on any FAIL.
import { existsSync, readFileSync, realpathSync, statSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { basename, isAbsolute, join, relative } from 'node:path';
import { Script } from 'node:vm';

const RUNGS = ['big-picture', 'parts', 'moves', 'detail', 'words'];
const MAX_WORDS = 25;
const MAX_STEP_WORDS = 20;
const MAX_TERMS = 5;

const args = process.argv.slice(2);
const repoAt = args.indexOf('--repo');
const repo = repoAt === -1 ? null : args[repoAt + 1];
if (repoAt !== -1) args.splice(repoAt, 2);
const file = args[0];
if (!file || (repoAt !== -1 && !(repo && existsSync(repo) && statSync(repo).isDirectory()))) {
  console.error('usage: node check.mjs <page.html> [--repo <dir>]');
  process.exit(2);
}
// Read the raw file first: scripts are stripped below, and a script cut short by a raw </script> must still be seen.
const raw = readFileSync(file, 'utf8');
const html = raw.replace(/<(script|style)\b[\s\S]*?<\/\1>/gi, '');

const results = [];
const fail = msg => results.push(`FAIL ${msg}`);
const warn = msg => results.push(`WARN ${msg}`);
const ok = msg => results.push(`ok   ${msg}`);

const decode = s => s.replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;/g, "'");
// Visible prose: no SVG text, no code.
const prose = s => decode(s.replace(/<(svg|pre|code)\b[\s\S]*?<\/\1>/gi, ' ').replace(/<[^>]+>/g, ' ')).replace(/\s+/g, ' ').trim();
// Visible text including code, for matching words-card terms.
const visible = s => decode(s.replace(/<svg\b[\s\S]*?<\/svg>/gi, ' ').replace(/<[^>]+>/g, ' ')).replace(/\s+/g, ' ').trim();
const count = (s, re) => (s.match(re) || []).length;

const sections = {};
const order = [];
for (const m of html.matchAll(/<section\b[^>]*data-zoom="([^"]+)"[^>]*>([\s\S]*?)<\/section>/gi)) {
  sections[m[1]] = m[2];
  order.push(m[1]);
}

// 0. Inline scripts parse. The HTML parser ends a script at the first </script>, even inside a string,
// so a truncated body fails to parse. Credit: adapted from anthropics/claude-plugins-official plugins/project-artifact/SKILL.md @ a9fd216 (Apache-2.0).
{
  let scripts = 0, broken = 0;
  for (const m of raw.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/gi)) {
    if (/\bsrc\s*=/i.test(m[1])) continue;
    const type = (m[1].match(/\btype\s*=\s*["']?([^"'\s>]+)/i) || [, ''])[1].toLowerCase();
    const isJson = type.includes('json');
    if (!isJson && type && !/^(text|application)\/(javascript|ecmascript)$/.test(type)) continue;
    scripts++;
    const line = raw.slice(0, m.index).split('\n').length;
    try { if (isJson) JSON.parse(m[2]); else new Script(m[2]); }
    catch (e) { broken++; fail(`inline script at line ${line} does not parse${isJson ? ' as JSON' : ''} (${e.message}); escape \`<\` as \`\\u003c\` in embedded strings`); }
  }
  if (scripts && !broken) ok(`${scripts} inline script${scripts === 1 ? '' : 's'} parse`);
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

// 2b. Optional gap marking: know/fuzzy/lost toggles need the visible request box, since a copy button can be blocked in a sandboxed frame.
// Credit: adapted from anthropics/claude-plugins-official plugins/playground/skills/playground/templates/concept-map.md @ a9fd216 (Apache-2.0).
if (/\bdata-mark\b/i.test(html) && !/<textarea\b[^>]*\bdata-gap-request\b/i.test(html)) {
  warn('[data-mark] toggles with no <textarea data-gap-request> showing the generated request');
}

// 3. Words card: every term is used on the page.
const terms = sections.words === undefined ? [] :
  [...sections.words.matchAll(/<dt\b[^>]*>([\s\S]*?)<\/dt>/gi)].map(m => visible(m[1])).filter(Boolean);
const restText = visible(Object.entries(sections).filter(([k]) => k !== 'words').map(([, v]) => v).join(' ')).toLowerCase();
const hasWord = (text, w) => new RegExp(`(^|[^\\p{L}\\p{N}])${w.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}(?:e?s)?($|[^\\p{L}\\p{N}])`, 'iu').test(text);
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
for (const m of html.matchAll(/<(\w+)\b[^>]*\bdata-step\b[^>]*>([\s\S]*?)<\/\1>/gi)) {
  for (const s of prose(m[2]).split(/(?<=[.!?])\s+/)) {
    const words = s.split(/\s+/).filter(w => /[\p{L}\p{N}]/u.test(w)).length;
    if (words > MAX_STEP_WORDS && words <= MAX_WORDS) {
      long++;
      fail(`step sentence of ${words} words (max ${MAX_STEP_WORDS} in a step): "${s.slice(0, 80)}…"`);
    }
  }
}
if (!long) ok(`every sentence ${MAX_WORDS} words or fewer, steps ${MAX_STEP_WORDS}`);

// 5. Acronyms: the first use sits next to its meaning in parentheses, or the words card has it.
const text = prose(html);
const termSet = new Set(terms.map(t => t.toLowerCase()));
const done = new Set();
const bad = [];
for (const m of text.matchAll(/(?<![\p{L}\p{N}-])[A-Z][A-Z0-9]+(?:-[A-Z0-9]+)*s?(?![\p{L}\p{N}])/gu)) {
  const word = m[0].replace(/s$/, '');
  if (done.has(word) || !/[A-Z].*[A-Z]/.test(word)) continue;
  // File names (TASKS.md) and IDs (CHK011) are names, not acronyms.
  if (/^\.[a-z]/.test(text.slice(m.index + m[0].length)) || /^[A-Z]{2,}\d+$/.test(word)) continue;
  done.add(word);
  const before = text.slice(0, m.index).trimEnd();
  const after = text.slice(m.index + m[0].length).trimStart();
  if (before.endsWith('(') || after.startsWith('(') || termSet.has(word.toLowerCase())) continue;
  bad.push(word);
}
if (bad.length) fail(`acronyms with no meaning beside the first use: ${bad.join(', ')}`);
else ok('every acronym explained');

// 6. With --repo: code names on the page exist in the repo that was read.
// A missing call or path is a FAIL; a missing plain identifier is a WARN. Commands, numbers, library
// APIs and <pre data-external> blocks are not repo names and are skipped.
// Credit: adapted from anthropics/claude-plugins-official plugins/code-modernization/commands/modernize-map.md @ a9fd216 (Apache-2.0).
if (repo) {
  const LIB = /^(Promise|Object|Array|JSON|Math|Date|Map|Set|Number|String|Error|Buffer|Intl|Reflect|Symbol|console|process|window|document|navigator|localStorage|fs|path|os)\./;
  // The page itself holds every token it shows, so it must not count as evidence.
  const pageAbs = realpathSync(file);
  const rel = relative(realpathSync(repo), pageAbs);
  const pageInRepo = !rel.startsWith('..') && !isAbsolute(rel);
  const inRepo = needle => {
    const gitArgs = ['-C', repo, 'grep', '-qF', '--untracked', '-e', needle];
    if (pageInRepo) gitArgs.push('--', '.', `:(exclude)${rel}`);
    if (spawnSync('git', gitArgs, { stdio: 'ignore' }).status === 0) return true;
    // Also reached when git says no: git grep skips ignored files (generated code) and non-repos.
    const grepArgs = ['-rqF', '--exclude-dir=node_modules', '--exclude-dir=.git'];
    if (pageInRepo) grepArgs.push(`--exclude=${basename(pageAbs)}`);
    return spawnSync('grep', [...grepArgs, '-e', needle, repo], { stdio: 'ignore' }).status === 0;
  };
  const external = html.replace(/<pre\b[^>]*\bdata-external\b[^>]*>[\s\S]*?<\/pre>/gi, ' ');
  const tokens = new Set(
    [...external.matchAll(/<code\b[^>]*>([\s\S]*?)<\/code>/gi)].map(m => decode(m[1].replace(/<[^>]+>/g, '')).trim()));
  let checked = 0, missingNames = 0;
  for (const t of tokens) {
    if (!t || /\s/.test(t) || /^[a-z]+:\/\//i.test(t) || t.startsWith('/') || LIB.test(t)) continue;
    const call = /^[A-Za-z_$][\w$.]*\(\)$/.test(t);
    const path = /^[\w.@-]+(\/[\w.@-]+)+\.[A-Za-z][A-Za-z0-9]*$/.test(t);
    const ident = /^[a-z][a-z0-9]*[A-Z]\w*$/.test(t) || /^[a-z0-9]+(_[a-z0-9]+)+$/.test(t) || /^[A-Z][a-z0-9]+([A-Z][a-z0-9]*)+$/.test(t);
    if (!call && !path && !ident) continue;
    checked++;
    const needle = call ? t.slice(0, -2).split('.').pop() : t;
    if (inRepo(needle) || (path && existsSync(join(repo, t)))) continue;
    missingNames++;
    if (call || path) fail(`\`${t}\` is not in the repo (${repo}); explain only code you read`);
    else warn(`\`${t}\` is not in the repo (${repo}); check the spelling against the code`);
  }
  if (!missingNames) ok(`${checked} repo name${checked === 1 ? '' : 's'} found in the repo`);
}

console.log(results.join('\n'));
process.exit(results.some(r => r.startsWith('FAIL')) ? 1 : 0);
