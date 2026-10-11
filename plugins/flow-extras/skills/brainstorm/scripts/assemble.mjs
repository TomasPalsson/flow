#!/usr/bin/env node
// assemble.mjs - build the brainstorm HTML page from <run>/final.json plus SVG picture files.
// The model never writes page HTML; this script does, the same way every time.
//
// Usage:
//   node assemble.mjs --run <run-dir> [--out <file.html>] [--look <id>] [--artifact]
//
//   --run       directory holding final.json; picture "file" paths are relative to it
//   --out       output file (default <run>/page.html)
//   --look      look id from data/looks.json (default: looks[parseInt(key.slice(0,8),16) % looks.length])
//   --artifact  omit <!doctype>, <html>, <head>, <body> tags (claude.ai Artifact adds its own shell)
//
// Exit codes: 0 ok, 1 check failed (unsafe SVG), 2 bad args, 3 data/IO error (missing or invalid file).
// Node >= 18, no dependencies. The page contains no JavaScript.

import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const SLOT_ORDER = ['safe', 'remove', 'stretch', 'wild', 'fix'];
const SLOT_WORD = { safe: 'Safe bet', stretch: 'Stretch', wild: 'Wild card', remove: 'Remove', fix: 'Quick fix' };
const COLOR_KEYS = ['paper', 'card', 'ink', 'muted', 'line', 'accent', 'accent_soft', 'safe', 'stretch', 'wild', 'remove', 'fix'];
const CARD_STYLES = ['flat', 'outlined', 'raised-paper', 'tabbed'];
const STROKES = ['1px', '1.5px', '2px'];
const LOOKS_PATH = fileURLToPath(new URL('../data/looks.json', import.meta.url));

class Fail extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}
const die = (code, msg) => {
  throw new Fail(code, msg);
};

export function esc(value) {
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function parseArgs(argv) {
  const opts = { run: null, out: null, look: null, artifact: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    const need = () => {
      if (i + 1 >= argv.length || argv[i + 1].startsWith('--')) die(2, `assemble: ${a} needs a value`);
      return argv[++i];
    };
    if (a === '--run') opts.run = need();
    else if (a === '--out') opts.out = need();
    else if (a === '--look') opts.look = need();
    else if (a === '--artifact') opts.artifact = true;
    else if (a === '--help' || a === '-h') opts.help = true;
    else die(2, `assemble: unknown argument ${a}`);
  }
  if (opts.help) return opts;
  if (!opts.run) die(2, 'assemble: --run <run-dir> is required');
  return opts;
}

function readJson(path, what) {
  let text;
  try {
    text = readFileSync(path, 'utf8');
  } catch (e) {
    die(3, `assemble: cannot read ${what} at ${path}: ${e.message}`);
  }
  try {
    return JSON.parse(text);
  } catch (e) {
    die(3, `assemble: ${what} at ${path} is not valid JSON: ${e.message}`);
  }
}

// ---- looks ---------------------------------------------------------------

const HEX = /^#[0-9a-fA-F]{6}$/;
const SAFE_CSS_TEXT = /^[^<>{};@\\]*$/;

function loadLooks() {
  const looks = readJson(LOOKS_PATH, 'looks.json');
  if (!Array.isArray(looks) || looks.length === 0) die(3, `assemble: ${LOOKS_PATH} must be a non-empty array`);
  for (const l of looks) {
    const where = `assemble: look "${l && l.id}" in ${LOOKS_PATH}`;
    if (!l || typeof l.id !== 'string' || !/^[a-z0-9-]+$/.test(l.id)) die(3, `${where}: bad id`);
    for (const theme of ['light', 'dark']) {
      for (const k of COLOR_KEYS) if (!l[theme] || !HEX.test(l[theme][k])) die(3, `${where}: ${theme}.${k} must be #rrggbb`);
    }
    for (const k of ['body', 'mono', 'display']) {
      if (!l.fonts || typeof l.fonts[k] !== 'string' || !SAFE_CSS_TEXT.test(l.fonts[k])) die(3, `${where}: fonts.${k} invalid`);
    }
    const href = l.fonts.google_href;
    if (href != null && !/^https:\/\/fonts\.googleapis\.com\/css2\?[A-Za-z0-9+:;=&@.,_-]+$/.test(href)) {
      die(3, `${where}: fonts.google_href must be a fonts.googleapis.com css2 URL or null`);
    }
    if (typeof l.corner !== 'number' || l.corner < 0) die(3, `${where}: corner must be a number`);
    if (!STROKES.includes(l.stroke)) die(3, `${where}: stroke must be one of ${STROKES.join(', ')}`);
    if (!CARD_STYLES.includes(l.card_style)) die(3, `${where}: card_style must be one of ${CARD_STYLES.join(', ')}`);
  }
  return looks;
}

export function pickLook(looks, key, forcedId) {
  if (forcedId) {
    const found = looks.find((l) => l.id === forcedId);
    if (!found) die(2, `assemble: unknown look "${forcedId}"; available: ${looks.map((l) => l.id).join(', ')}`);
    return found;
  }
  const n = parseInt(String(key).slice(0, 8), 16);
  if (!Number.isFinite(n)) die(3, `assemble: final.json key "${key}" does not start with hex digits, cannot derive a look (pass --look)`);
  return looks[n % looks.length];
}

// ---- final.json validation -------------------------------------------------

function validate(data, path) {
  const bad = (m) => die(3, `assemble: ${path}: ${m}`);
  const isStr = (v) => typeof v === 'string' && v.length > 0;
  const isObj = (v) => v && typeof v === 'object' && !Array.isArray(v);
  if (!isObj(data)) bad('top level must be an object');
  for (const k of ['repo', 'key', 'generated_at', 'headline']) if (!isStr(data[k])) bad(`"${k}" must be a non-empty string`);
  if (data.about !== undefined && !isStr(data.about)) bad('"about" must be a non-empty string when present');
  if (!Array.isArray(data.ideas) || data.ideas.length === 0) bad('"ideas" must be a non-empty array');
  const seen = new Set();
  data.ideas.forEach((idea, i) => {
    const at = `ideas[${i}]`;
    if (!isObj(idea)) bad(`${at} must be an object`);
    for (const k of ['id', 'title', 'sentence', 'why_here', 'first_test']) if (!isStr(idea[k])) bad(`${at}.${k} must be a non-empty string`);
    if (seen.has(idea.id)) bad(`${at}.id "${idea.id}" is duplicated`);
    seen.add(idea.id);
    if (!SLOT_ORDER.includes(idea.slot)) bad(`${at}.slot must be one of ${SLOT_ORDER.join(', ')}`);
    if (!isObj(idea.size) || !Number.isInteger(idea.size.blocks) || idea.size.blocks < 0 || idea.size.blocks > 3 || !isStr(idea.size.words)) {
      bad(`${at}.size must be {blocks: 0-3, words: string}`);
    }
    for (const [k, shape] of [['pictures', ['id', 'caption', 'file']], ['words', ['term', 'gloss']], ['evidence', ['where', 'what']]]) {
      const arr = idea[k] ?? [];
      if (!Array.isArray(arr)) bad(`${at}.${k} must be an array`);
      arr.forEach((o, j) => {
        if (!isObj(o)) bad(`${at}.${k}[${j}] must be an object`);
        for (const f of shape) if (!isStr(o[f])) bad(`${at}.${k}[${j}].${f} must be a non-empty string`);
      });
    }
    const ids = new Set();
    for (const p of idea.pictures ?? []) {
      if (ids.has(p.id)) bad(`${at}.pictures has duplicate id "${p.id}"`);
      ids.add(p.id);
    }
    for (const k of ['risks', 'needs']) {
      const arr = idea[k] ?? [];
      if (!Array.isArray(arr) || arr.some((s) => !isStr(s))) bad(`${at}.${k} must be an array of non-empty strings`);
    }
    if (idea.gives_up != null && typeof idea.gives_up !== 'string') bad(`${at}.gives_up must be a string`);
  });
  const d = data.dropped;
  if (!isObj(d)) bad('"dropped" must be an object');
  if (!Array.isArray(d.obvious) || d.obvious.some((s) => !isStr(s))) bad('dropped.obvious must be an array of strings');
  if (!Array.isArray(d.dead) || d.dead.some((o) => !isObj(o) || !isStr(o.title) || !isStr(o.why))) bad('dropped.dead must be an array of {title, why}');
  if (!Number.isInteger(d.count) || d.count < 0) bad('dropped.count must be a non-negative integer');
}

// ---- SVG ---------------------------------------------------------------------

export function prepareSvg(raw, prefix, label) {
  if (/<script/i.test(raw)) die(1, `assemble: ${label}: SVG contains <script`);
  if (/<foreignObject/i.test(raw)) die(1, `assemble: ${label}: SVG contains <foreignObject`);
  if (/[\s"'/]on\w+\s*=/i.test(raw)) die(1, `assemble: ${label}: SVG contains an on*= event attribute`);
  if (/javascript:/i.test(raw)) die(1, `assemble: ${label}: SVG contains a javascript: URL`);
  let svg = raw
    .replace(/^﻿/, '')
    .replace(/<\?xml[\s\S]*?\?>/gi, '')
    .replace(/<!DOCTYPE[\s\S]*?>/gi, '')
    .replace(/<!--[\s\S]*?-->/g, '')
    .trim();
  const open = svg.match(/<svg\b[^>]*>/i);
  if (!open || svg.indexOf(open[0]) !== 0) die(3, `assemble: ${label}: file does not start with an <svg> element`);
  if (!/<\/svg>\s*$/i.test(svg)) die(3, `assemble: ${label}: file does not end with </svg>`);
  let tag = open[0].replace(/\s(?:width|height)\s*=\s*("[^"]*"|'[^']*')/gi, '');
  if (/\srole\s*=/i.test(tag)) tag = tag.replace(/\srole\s*=\s*("[^"]*"|'[^']*')/i, ' role="img"');
  else tag = tag.replace(/<svg\b/i, '<svg role="img"');
  svg = tag + svg.slice(open[0].length);

  const ids = new Map();
  for (const m of svg.matchAll(/[\s]id\s*=\s*(["'])([^"']+)\1/g)) {
    const old = m[2];
    ids.set(old, old.startsWith(prefix) ? old : prefix + old);
  }
  if (ids.size === 0) return svg;
  svg = svg.replace(/(\sid\s*=\s*)(["'])([^"']+)\2/g, (all, pre, q, id) => `${pre}${q}${ids.get(id)}${q}`);
  svg = svg.replace(/url\(\s*(['"]?)#([^)'"\s]+)\1\s*\)/g, (all, q, id) => (ids.has(id) ? `url(${q}#${ids.get(id)}${q})` : all));
  svg = svg.replace(/(\s(?:xlink:)?href\s*=\s*)(["'])#([^"']+)\2/g, (all, pre, q, id) => (ids.has(id) ? `${pre}${q}#${ids.get(id)}${q}` : all));
  return svg;
}

// ---- CSS ---------------------------------------------------------------------

function tokenBlock(palette) {
  return COLOR_KEYS.map((k) => `--${k.replace('_', '-')}:${palette[k]};`).join('');
}

function css(look) {
  return `
:root{--font:${look.fonts.body};--mono:${look.fonts.mono};--display:${look.fonts.display};--corner:${look.corner}px;--stroke:${look.stroke};color-scheme:light dark;${tokenBlock(look.light)}}
@media (prefers-color-scheme: dark){:root:not([data-theme="light"]){${tokenBlock(look.dark)}}}
:root[data-theme="dark"]{${tokenBlock(look.dark)}}
:root[data-theme="light"]{color-scheme:light}
*,*::before,*::after{box-sizing:border-box}
html{-webkit-text-size-adjust:100%}
body{margin:0;background:var(--paper);color:var(--ink);font-family:var(--font);font-size:1rem;line-height:1.55}
main{max-width:72rem;margin:0 auto;padding:24px 16px 48px;overflow-wrap:anywhere}
h1,h2,h3{font-family:var(--display);line-height:1.2;margin:0}
h1{font-size:clamp(1.9rem,5vw,3rem);margin-bottom:12px}
.headline{font-family:var(--display);font-size:clamp(1.25rem,3.4vw,1.9rem);line-height:1.3;margin:0 0 24px;max-width:46rem}
a{color:var(--accent)}
a:focus-visible,summary:focus-visible{outline:3px solid var(--accent);outline-offset:2px}
.howto{background:var(--card);border:var(--stroke) dashed var(--line);border-radius:var(--corner);padding:14px 16px;margin:0 0 20px}
.howto p{margin:0 0 6px}
.howto p:last-child{margin:0}
.size-key .size{white-space:nowrap}
.howto b{color:var(--slot)}
.howto .k-safe{--slot:var(--safe)}
.howto .k-stretch{--slot:var(--stretch)}
.howto .k-wild{--slot:var(--wild)}
.howto .k-remove{--slot:var(--remove)}
.howto .k-fix{--slot:var(--fix)}
.chips{display:flex;flex-wrap:wrap;gap:8px;margin:0 0 28px;padding:0;list-style:none}
.chips a{display:inline-flex;flex-wrap:wrap;gap:2px 6px;align-items:baseline;text-decoration:none;color:var(--ink);background:var(--card);border:var(--stroke) solid var(--line);border-radius:999px;padding:6px 12px;min-height:2.25rem;font-size:.9rem}
.chips a:hover{border-color:var(--accent)}
.chips .n{font-weight:700;color:var(--accent)}
.chips .k{color:var(--muted);white-space:nowrap}
.chips .t{min-width:0;overflow-wrap:break-word}
.about{color:var(--muted);margin:0 0 12px;max-width:46rem}
.idea{background:var(--card);border-radius:var(--corner);padding:18px 16px;margin:0 0 24px;--slot:var(--muted);scroll-margin-top:12px}
.idea[data-slot="safe"]{--slot:var(--safe)}
.idea[data-slot="stretch"]{--slot:var(--stretch)}
.idea[data-slot="wild"]{--slot:var(--wild)}
.idea[data-slot="remove"]{--slot:var(--remove)}
.idea[data-slot="fix"]{--slot:var(--fix)}
.style-outlined .idea{border:var(--stroke) solid var(--line)}
.style-raised-paper .idea{border:var(--stroke) solid var(--line);box-shadow:5px 5px 0 var(--line)}
.style-tabbed .idea{border:var(--stroke) solid var(--line);border-top:6px solid var(--slot);padding-top:14px}
.kind{margin:0 0 6px;font-size:.9rem;font-weight:700;letter-spacing:.02em;display:flex;align-items:center;gap:8px}
.kind::before{content:"";width:12px;height:12px;background:var(--slot);border-radius:2px;flex:none}
.style-tabbed .kind{display:inline-flex;background:var(--accent-soft);padding:2px 10px;border-radius:calc(var(--corner) / 2)}
.title{font-size:clamp(1.3rem,3.2vw,1.8rem);margin:0 0 8px}
.words{margin:0 0 8px;font-size:.9rem;color:var(--muted)}
.words b{color:var(--ink)}
.sentence{font-size:1.1rem;margin:0 0 16px;max-width:46rem}
.pictures{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,320px),1fr));gap:16px;margin:0 0 16px}
.pictures figure{margin:0;max-width:420px;width:100%}
.pictures svg{display:block;width:100%;height:auto;background:var(--paper);border:var(--stroke) solid var(--line);border-radius:calc(var(--corner) / 2)}
.pictures figcaption{font-size:.9rem;color:var(--muted);margin-top:6px}
.meta{display:flex;flex-wrap:wrap;align-items:center;gap:10px;margin:0 0 14px;font-size:.95rem}
.blocks{display:inline-flex;gap:4px}
.blocks i{display:block;width:16px;height:16px;border:2px solid var(--ink);border-radius:2px}
.blocks i.on{background:var(--ink)}
.blocks.unknown i{border-style:dashed;width:auto;min-width:16px;text-align:center;font-style:normal;font-weight:700;font-size:12px;line-height:12px;color:var(--ink)}
.why,.test,.needs{margin:0 0 10px;max-width:46rem}
.needs{font-weight:700}
details{border-top:var(--stroke) solid var(--line);margin-top:14px;padding-top:10px}
summary{cursor:pointer;font-weight:700;min-height:2.25rem;display:flex;align-items:center;color:var(--accent)}
details ul{margin:6px 0 10px;padding-left:1.2rem}
details p{margin:8px 0}
code{font-family:var(--mono);font-size:.88em;background:var(--paper);border-radius:3px;padding:1px 5px;overflow-wrap:anywhere}
.left-out{margin-top:40px;border-top:var(--stroke) solid var(--line);padding-top:24px}
.left-out h2{font-size:1.5rem;margin-bottom:8px}
.left-out h3{font-size:1.05rem;margin:18px 0 6px}
.left-out ul{margin:0;padding-left:1.2rem}
.left-out .count{color:var(--muted);margin-top:16px}
footer{margin-top:32px;font-size:.85rem;color:var(--muted);font-family:var(--mono)}
@media (max-width:480px){main{padding-top:16px}.idea{padding:14px 12px}}
@media (prefers-reduced-motion: reduce){*,*::before,*::after{animation:none!important;transition:none!important;scroll-behavior:auto!important}}
`.trim();
}

// ---- page ------------------------------------------------------------------

function orderIdeas(ideas) {
  const ordered = [];
  for (const slot of SLOT_ORDER) for (const idea of ideas) if (idea.slot === slot) ordered.push(idea);
  return ordered;
}

const SIZE_WORD = { 0: 'not sure yet', 1: 'hours', 2: 'days', 3: 'weeks' };
const SLOT_MEANING = {
  safe: 'most useful, with clear proof',
  remove: 'makes things simpler by taking something away',
  stretch: 'surprising and useful',
  wild: 'the boldest idea, a bet',
  fix: 'a real bug we found, small to fix',
};

function sizeBadge(size) {
  const words = SIZE_WORD[size.blocks];
  if (size.blocks === 0) {
    return `<span class="size"><span class="blocks unknown" role="img" aria-label="size unknown"><i>?</i></span> ${words}</span>`;
  }
  const squares = [1, 2, 3].map((n) => `<i${n <= size.blocks ? ' class="on"' : ''}></i>`).join('');
  return `<span class="size"><span class="blocks" role="img" aria-label="${size.blocks} of 3 blocks">${squares}</span> ${words}</span>`;
}

// One gloss per term across the page: the first in page order wins (case-insensitive term),
// and the term is shown only on the first card where it appears.
function unifyGlosses(ordered) {
  const seen = new Set();
  return ordered.map((idea) => {
    if (!(idea.words ?? []).length) return idea;
    const words = idea.words.filter((w) => {
      const k = w.term.toLowerCase();
      if (seen.has(k)) return false;
      seen.add(k);
      return true;
    });
    return { ...idea, words };
  });
}

function howTo(slots) {
  const key = SLOT_ORDER.filter((s) => slots.has(s))
    .map((s) => `<b class="k-${s}">${SLOT_WORD[s]}</b>: ${SLOT_MEANING[s]}`)
    .join(' · ');
  return `<section class="howto" aria-labelledby="howto-h">
<h2 id="howto-h">How to read a card</h2>
<p>Each card shows one idea: what changes, small before-and-after pictures, how big it is, and a first test.</p>
<p>${key}</p>
<p class="size-key">${[1, 2, 3, 0].map((n) => sizeBadge({ blocks: n })).join(' · ')}</p>
</section>`;
}

function cardHtml(idea, num, numberOf, runDir) {
  const lines = [];
  lines.push(`<article class="idea" id="idea-${num}" data-slot="${idea.slot}">`);
  lines.push(`<p class="kind">${num} · ${esc(SLOT_WORD[idea.slot])}</p>`);
  lines.push(`<h2 class="title">${esc(idea.title)}</h2>`);
  if ((idea.words ?? []).length) {
    lines.push(`<p class="words">${idea.words.map((w) => `<b>${esc(w.term)}</b>: ${esc(w.gloss)}`).join(' · ')}</p>`);
  }
  lines.push(`<p class="sentence">${esc(idea.sentence)}</p>`);
  const pics = idea.pictures ?? [];
  if (pics.length) {
    lines.push('<div class="pictures">');
    for (const p of pics) {
      const file = resolve(runDir, p.file);
      let raw;
      try {
        raw = readFileSync(file, 'utf8');
      } catch (e) {
        die(3, `assemble: picture file not found or unreadable for ${idea.id}/${p.id}: ${file} (${e.code || e.message})`);
      }
      const svg = prepareSvg(raw, `${idea.id}${p.id}-`, `${idea.id}/${p.id} (${file})`);
      lines.push(`<figure>${svg}<figcaption>${esc(p.caption)}</figcaption></figure>`);
    }
    lines.push('</div>');
  }
  lines.push(`<p class="meta">${sizeBadge(idea.size)}</p>`);
  lines.push(`<p class="why"><b>Why it's here:</b> ${esc(idea.why_here)}</p>`);
  lines.push(`<p class="test"><b>First test:</b> ${esc(idea.first_test)}</p>`);
  const needs = idea.needs ?? [];
  if (needs.length) {
    const nums = needs.map((id) => {
      if (!numberOf.has(id)) die(3, `assemble: ${idea.id} needs "${id}", which is not an idea id in final.json`);
      return numberOf.get(id);
    });
    const text = nums.length === 1 ? `Needs idea ${nums[0]} first` : `Needs ideas ${nums.slice(0, -1).join(', ')} and ${nums[nums.length - 1]} first`;
    lines.push(`<p class="needs">${text}</p>`);
  }
  const proof = [];
  if ((idea.evidence ?? []).length) {
    proof.push(`<ul class="evidence">${idea.evidence.map((e) => `<li><code>${esc(e.where)}</code> — ${esc(e.what)}</li>`).join('')}</ul>`);
  }
  if (idea.gives_up) proof.push(`<p class="gives-up"><b>Gives up:</b> ${esc(idea.gives_up)}</p>`);
  if ((idea.risks ?? []).length) {
    proof.push(`<p class="risks-head"><b>Risks:</b></p><ul class="risks">${idea.risks.map((r) => `<li>${esc(r)}</li>`).join('')}</ul>`);
  }
  lines.push(`<details><summary>Proof from the code</summary>${proof.join('') || '<p>No proof recorded.</p>'}</details>`);
  lines.push('</article>');
  return lines.join('\n');
}

function leftOut(d) {
  const obvious = d.obvious.length ? `<ul>${d.obvious.map((t) => `<li>${esc(t)}</li>`).join('')}</ul>` : '<p>None this time.</p>';
  const dead = d.dead.length
    ? `<ul>${d.dead.map((o) => `<li><b>${esc(o.title)}</b> — ${esc(o.why)}</li>`).join('')}</ul>`
    : '<p>None this time.</p>';
  return `<section class="left-out" aria-labelledby="left-out-h">
<h2 id="left-out-h">What we left out</h2>
<p>These came up and did not make the page. Most are the first things anyone would think of, or turned out to exist already.</p>
<p class="count">${d.count} ideas were left out in all.</p>
<details><summary>See the ideas we left out</summary>
<h3>Obvious ideas we skipped on purpose</h3>
${obvious}
<h3>Ideas that already exist or were wrong</h3>
${dead}
</details>
</section>`;
}

export function buildPage(data, look, { artifact = false, runDir }) {
  const ordered = unifyGlosses(orderIdeas(data.ideas));
  const numberOf = new Map(ordered.map((idea, i) => [idea.id, i + 1]));
  const chips = ordered
    .map((idea, i) => `<li><a href="#idea-${i + 1}"><span class="n">${i + 1}</span> <span class="k">${esc(SLOT_WORD[idea.slot])}</span> <span class="t">${esc(idea.title)}</span></a></li>`)
    .join('\n');
  const cards = ordered.map((idea, i) => cardHtml(idea, i + 1, numberOf, runDir)).join('\n');
  const title = `Ideas for ${data.repo}`;
  const fontLink = look.fonts.google_href ? `<link rel="stylesheet" href="${esc(look.fonts.google_href)}">\n` : '';
  const body = `<main class="style-${look.card_style}" data-look="${look.id}">
<header>
<h1>${esc(title)}</h1>
${data.about ? `<p class="about">${esc(data.about)}</p>\n` : ''}<p class="headline">${esc(data.headline)}</p>
${howTo(new Set(ordered.map((i) => i.slot)))}
<nav aria-label="Ideas"><ul class="chips">
${chips}
</ul></nav>
</header>
${cards}
${leftOut(data.dropped)}
<footer>Run key ${esc(data.key)} · ${esc(data.generated_at)}</footer>
</main>`;
  if (artifact) {
    return `<title>${esc(title)}</title>\n${fontLink}<style>\n${css(look)}\n</style>\n${body}\n`;
  }
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(title)}</title>
${fontLink}<style>
${css(look)}
</style>
</head>
<body>
${body}
</body>
</html>
`;
}

// ---- main --------------------------------------------------------------------

function main(argv) {
  const opts = parseArgs(argv);
  if (opts.help) {
    process.stdout.write('usage: node assemble.mjs --run <run-dir> [--out <file.html>] [--look <id>] [--artifact]\n');
    return;
  }
  const runDir = resolve(opts.run);
  const finalPath = join(runDir, 'final.json');
  const data = readJson(finalPath, 'final.json');
  validate(data, finalPath);
  const looks = loadLooks();
  const look = pickLook(looks, data.key, opts.look);
  const html = buildPage(data, look, { artifact: opts.artifact, runDir });
  const out = resolve(opts.out ?? join(runDir, 'page.html'));
  try {
    mkdirSync(dirname(out), { recursive: true });
    writeFileSync(out, html);
  } catch (e) {
    die(3, `assemble: cannot write ${out}: ${e.message}`);
  }
  process.stdout.write(`assemble: wrote ${out} (look ${look.id}, ${data.ideas.length} ideas${opts.artifact ? ', artifact' : ''})\n`);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === resolve(process.argv[1])) {
  try {
    main(process.argv.slice(2));
  } catch (e) {
    if (e instanceof Fail) {
      process.stderr.write(`${e.message}\n`);
      process.exit(e.code);
    }
    process.stderr.write(`assemble: unexpected error: ${e.stack || e}\n`);
    process.exit(3);
  }
}
