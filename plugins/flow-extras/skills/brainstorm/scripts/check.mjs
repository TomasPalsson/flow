#!/usr/bin/env node
// check.mjs - check a brainstorm page against the page contract (references/page.md).
//
// Usage:  node check.mjs <page.html> [--render] [--json]
//         node check.mjs --svg <file.svg> [--json]
//   --render  also open the page in headless Chrome at 390 and 1280 px wide and check
//             text overlap, text outside its svg, tiny rendered text, sideways scroll
//   --svg F   check ONE picture before it goes on a page: the per-svg static rules, then
//             (if Chrome is found) a render inside a card-shaped page (<article class="idea">
//             <figure>, figure max 420px, so 358px wide at 390 and 420px at 1280) with the
//             same overlap / outside / tiny-text checks. Lines are prefixed with the file
//             name. Without Chrome it prints "WARN no Chrome: render checks skipped".
//   --json    print {fails:[], warns:[], oks:[]} instead of lines
// Output lines: "FAIL idea-3 svg2: ...", "WARN ...", "ok ...", then a summary line.
//
// Exit codes: 0 no FAIL, 1 at least one FAIL, 2 bad args, 3 data/IO error
// (unreadable page, no Chrome for --render, Chrome output unparseable).

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';
import { findChrome, TOKENS } from './shot.mjs';

const JARGON = [
  'passport', 'foundation tier', 'growth tier', 'delight tier', 'treemap', 'quadrant', 'DAG',
  'linked brushing', 'cited_findings', 'synergy', 'leverage', 'holistic', 'robust', 'seamless', 'paradigm',
];
const LIB_RE = /echarts|chart\.js|d3@|d3\.min|mermaid|cytoscape/i;

const decode = (s) =>
  s.replace(/&nbsp;/g, ' ').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&amp;/g, '&');
const textOf = (html) => decode(html.replace(/<[^>]*>/g, ' ')).replace(/\s+/g, ' ').trim();
const words = (s) => s.split(/\s+/).filter(Boolean).length;
const attr = (tag, name) => {
  const m = new RegExp(`(?:^|\\s)${name}\\s*=\\s*(?:"([^"]*)"|'([^']*)')`, 'i').exec(tag);
  return m ? (m[1] ?? m[2]) : null;
};

function classed(html, tagRe, cls) {
  // elements whose class list has cls; returns inner html (non-nested assumption)
  const re = new RegExp(`<(${tagRe})\\b([^>]*)>([\\s\\S]*?)<\\/\\1>`, 'gi');
  const out = [];
  for (const m of html.matchAll(re)) {
    const c = attr(`x ${m[2]}`, 'class');
    if (c && c.split(/\s+/).includes(cls)) out.push(m[3]);
  }
  return out;
}

// Per-svg static rules shared by the page check and --svg. Pushes into fails and warns.
function svgRules(svg, w, fails, warns) {
  const F = (where, msg) => fails.push(`FAIL ${where}: ${msg}`);
  const W = (where, msg) => warns.push(`WARN ${where}: ${msg}`);
  const open = /<svg\b[^>]*>/i.exec(svg)[0];
  if (attr(open, 'role') !== 'img') F(w, 'missing role="img"');
  if (!/<title\b[^>]*>[\s\S]*?\S[\s\S]*?<\/title>/i.test(svg)) F(w, 'missing <title>');
  const vb = attr(open, 'viewBox');
  const vbn = vb ? vb.trim().split(/[\s,]+/).map(Number) : null;
  if (!vbn || vbn.length !== 4 || vbn[2] !== 360) F(w, `viewBox width must be 360, got "${vb}"`);
  const forb = /<image\b|<foreignObject\b|<script\b|<style\b|\bfilter\s*=|<linearGradient\b|<radialGradient\b/i.exec(svg);
  if (forb) F(w, `forbidden element or attribute "${forb[0]}"`);
  for (const m of svg.matchAll(/font-size\s*[=:]\s*["']?\s*([\d.]+)/gi)) {
    if (Number(m[1]) < 13) {
      F(w, `font-size ${m[1]} is under 13`);
      break;
    }
  }
  const nText = (svg.match(/<text\b/gi) || []).length;
  if (nText > 14) F(w, `${nText} <text> elements, at most 14 allowed`);
  if (/(?:fill|stroke)\s*[:=]\s*["']?\s*#[0-9a-f]{3,8}\b/i.test(svg)) W(w, 'raw hex colour in fill or stroke');
}

export function staticCheck(html) {
  const fails = [];
  const warns = [];
  const oks = [];
  const F = (where, msg) => fails.push(`FAIL ${where}: ${msg}`);
  const W = (where, msg) => warns.push(`WARN ${where}: ${msg}`);

  const noStyle = html.replace(/<style\b[\s\S]*?<\/style>/gi, '');
  const noComments = noStyle.replace(/<!--[\s\S]*?-->/g, '');

  // chart libraries
  let libs = 0;
  for (const m of noComments.matchAll(/<script\b[^>]*\bsrc\s*=[^>]*>/gi)) {
    F('page', `external script ${m[0].slice(0, 80)}`);
    libs++;
  }
  const lib = LIB_RE.exec(noComments);
  if (lib) {
    F('page', `chart library mentioned: "${lib[0]}"`);
    libs++;
  }
  if (!libs) oks.push('ok page: no chart libraries');

  // ideas
  const articles = [];
  for (const m of html.matchAll(/<article\b([^>]*)>([\s\S]*?)<\/article>/gi)) {
    const c = attr(`x ${m[1]}`, 'class');
    if (c && c.split(/\s+/).includes('idea')) articles.push({ tag: m[1], body: m[2] });
  }
  if (articles.length === 0) F('page', 'no <article class="idea"> found');
  else if (articles.length > 11) F("page", `${articles.length} ideas, at most 11 allowed`);
  else oks.push(`ok page: ${articles.length} ideas`);

  // duplicate ids
  const seen = new Map();
  for (const m of noComments.matchAll(/\sid\s*=\s*(?:"([^"]*)"|'([^']*)')/gi)) {
    const id = m[1] ?? m[2];
    seen.set(id, (seen.get(id) || 0) + 1);
  }
  const dups = [...seen].filter(([, n]) => n > 1);
  for (const [id, n] of dups) F('page', `duplicate id "${id}" (${n} times)`);
  if (!dups.length) oks.push('ok page: no duplicate ids');

  // per article
  articles.forEach((a, i) => {
    const name = attr(`x ${a.tag}`, 'id') || `idea-${i + 1}`;
    const svgs = [...a.body.matchAll(/<svg\b[^>]*>[\s\S]*?<\/svg>/gi)].map((m) => m[0]);
    if (svgs.length > 4) F(name, `${svgs.length} svgs, at most 4 allowed`);
    if (svgs.length === 0) W(name, 'no pictures');
    svgs.forEach((svg, j) => {
      const w = `${name} svg${j + 1}`;
      const before = fails.length;
      svgRules(svg, w, fails, warns);
      if (fails.length === before) oks.push(`ok ${w}`);
    });

    // figures
    const caps = [];
    for (const m of a.body.matchAll(/<figure\b[\s\S]*?<\/figure>/gi)) {
      const cap = /<figcaption\b[^>]*>([\s\S]*?)<\/figcaption>/i.exec(m[0]);
      const idx = caps.length + 1;
      if (!cap) {
        F(`${name} fig${idx}`, 'figure has no <figcaption>');
        caps.push(null);
      } else {
        const t = textOf(cap[1]);
        if (words(t) > 16) F(`${name} fig${idx}`, `figcaption has ${words(t)} words, at most 16`);
        caps.push(t);
      }
    }
    const real = caps.filter(Boolean);
    if (new Set(real).size < real.length) W(name, 'two figures have the same figcaption');

    // words
    for (const s of classed(a.body, '\\w+', 'sentence')) {
      const n = words(textOf(s));
      if (n > 20) F(name, `sentence has ${n} words, at most 20`);
    }
    for (const s of classed(a.body, 'h2', 'title')) {
      const n = words(textOf(s));
      if (n > 9) F(name, `title has ${n} words, at most 9`);
    }
    const prose = [
      ...classed(a.body, '\\w+', 'sentence'),
      ...classed(a.body, '\\w+', 'why'),
      ...classed(a.body, '\\w+', 'test'),
      ...[...a.body.matchAll(/<figcaption\b[^>]*>([\s\S]*?)<\/figcaption>/gi)].map((m) => m[1]),
    ];
    for (const p of prose) {
      for (const sent of textOf(p).split(/[.!?]+(?=\s|$)/)) {
        if (words(sent) > 25) W(name, `sentence over 25 words: "${sent.trim().slice(0, 50)}..."`);
      }
    }
  });

  // jargon in visible text outside <code> and <details>
  const body = /<body\b[^>]*>([\s\S]*)<\/body>/i.exec(noComments);
  const visible = textOf(
    (body ? body[1] : noComments)
      .replace(/<script\b[\s\S]*?<\/script>/gi, '')
      .replace(/<details\b[\s\S]*?<\/details>/gi, '')
      .replace(/<code\b[\s\S]*?<\/code>/gi, '')
      .replace(/<title\b[\s\S]*?<\/title>/gi, ' '),
  );
  let jarg = 0;
  for (const j of JARGON) {
    const re = new RegExp(`(?<![\\w])${j.replace(/ /g, '\\s+')}(?![\\w])`, 'i');
    if (re.test(visible)) {
      F('page', `jargon word "${j}"`);
      jarg++;
    }
  }
  const lm = /(?<![\w])L[1-5](?![\w])/.exec(visible);
  if (lm) {
    F('page', `jargon word "${lm[0]}"`);
    jarg++;
  }
  if (!jarg) oks.push('ok page: no jargon');
  return { fails, warns, oks };
}

// Runs in the page. Returns plain strings of the form "FAIL <where>: <msg>".
function pageScript() {
  return `<script>
window.addEventListener('load', function () {
  var out = [];
  var arts = document.querySelectorAll('article.idea');
  arts.forEach(function (a, ai) {
    var name = a.id || ('idea-' + (ai + 1));
    a.querySelectorAll('svg').forEach(function (svg, si) {
      var where = name + ' svg' + (si + 1);
      var sr = svg.getBoundingClientRect();
      var vb = svg.viewBox && svg.viewBox.baseVal && svg.viewBox.baseVal.width ? svg.viewBox.baseVal.width : 360;
      var scale = sr.width / vb;
      var items = [];
      svg.querySelectorAll('text').forEach(function (t) {
        var r = t.getBoundingClientRect();
        var s = (t.textContent || '').replace(/\\s+/g, ' ').trim();
        if (!s || (r.width === 0 && r.height === 0)) return;
        // SVG text boxes cover the full glyph cell, so stacked lines touch. Test only the ink-ish core.
        var core = { left: r.left, right: r.right, top: r.top + r.height * 0.22, bottom: r.bottom - r.height * 0.18 };
        items.push({ t: s, r: r, c: core, fs: parseFloat(getComputedStyle(t).fontSize) });
      });
      for (var i = 0; i < items.length; i++) {
        var x = items[i];
        if (x.r.left < sr.left - 2 || x.r.right > sr.right + 2 || x.r.top < sr.top - 2 || x.r.bottom > sr.bottom + 2)
          out.push('FAIL ' + where + ': text "' + x.t + '" extends outside its picture');
        var px = x.fs * scale;
        if (px < 11) out.push('FAIL ' + where + ': text "' + x.t + '" renders at ' + px.toFixed(1) + 'px, under 11px');
        for (var j = i + 1; j < items.length; j++) {
          var y = items[j];
          var w = Math.min(x.c.right, y.c.right) - Math.max(x.c.left, y.c.left);
          var h = Math.min(x.c.bottom, y.c.bottom) - Math.max(x.c.top, y.c.top);
          if (w > 0 && h > 0 && w * h > 6) out.push('FAIL ' + where + ': text "' + x.t + '" overlaps "' + y.t + '"');
        }
      }
    });
  });
  if (document.documentElement.scrollWidth > window.innerWidth + 1)
    out.push('FAIL page: sideways scroll, scrollWidth ' + document.documentElement.scrollWidth + ' > width ' + window.innerWidth);
  var pre = document.createElement('pre');
  pre.id = '__brainstorm_check';
  pre.textContent = JSON.stringify({ width: window.innerWidth, out: out });
  document.body.appendChild(pre);
});
</script>`;
}

export function renderCheck(html, chrome) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'bcheck-'));
  // Measuring needs no web fonts. An unreachable Google Fonts <link> or @import keeps Chrome's virtual
  // time from finishing, so the load event never fires and no result is written. Strip them from the temp copy.
  html = html
    .replace(/<link\b[^>]*\bhref\s*=\s*["']?(?:https?:)?\/\/[^>]*>/gi, '')
    .replace(/@import\s+(?:url\()?\s*["']?(?:https?:)?\/\/[^;]*;/gi, '');
  const injected = /<\/body>/i.test(html) ? html.replace(/<\/body>/i, () => `${pageScript()}</body>`) : html + pageScript();
  const file = path.join(tmp, 'page.html');
  fs.writeFileSync(file, injected);
  const fails = [];
  const oks = [];
  try {
    for (const [w, h] of [[390, 3000], [1280, 3000]]) {
      const r = spawnSync(
        chrome,
        [
          '--headless=new', '--no-sandbox', '--disable-gpu', `--user-data-dir=${path.join(tmp, `p${w}`)}`,
          '--virtual-time-budget=6000', `--window-size=${w},${h}`, '--dump-dom', pathToFileURL(file).href,
        ],
        { encoding: 'utf8', timeout: 90000, maxBuffer: 64 * 1024 * 1024 },
      );
      const m = /<pre id="__brainstorm_check">([\s\S]*?)<\/pre>/.exec(r.stdout || '');
      if (!m) {
        const e = new Error(`render check at ${w}px: no result in Chrome output (exit ${r.status}): ${(r.stderr || '').slice(0, 500)}`);
        e.exitCode = 3;
        throw e;
      }
      let data;
      try {
        data = JSON.parse(decode(m[1]));
      } catch (err) {
        const e = new Error(`render check at ${w}px: result is not JSON: ${err.message}`);
        e.exitCode = 3;
        throw e;
      }
      for (const line of data.out) fails.push(`${line} (at ${w}px)`);
      if (!data.out.length) oks.push(`ok render ${w}px (viewport ${data.width})`);
    }
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
  return { fails, oks };
}

function die(code, msg) {
  process.stderr.write(`check.mjs: ${msg}\n`);
  process.exit(code);
}

// A temp page shaped like a real card, so the render rules see the real figure width.
export function cardPage(svgText) {
  const svg = svgText.replace(/^\s*<\?xml[\s\S]*?\?>/, '');
  return `<!doctype html><html><head><meta charset="utf-8"><style>
:root{${TOKENS}}
html,body{margin:0}
body{background:var(--paper);color:var(--ink);font-family:var(--font);padding:16px;box-sizing:border-box}
figure{max-width:420px;margin:0}
figure svg{width:100%;height:auto;display:block}
</style></head><body><article class="idea" id="idea-1"><figure>${svg}</figure></article></body></html>`;
}

export function svgCheck(svgText, chrome) {
  const res = { fails: [], warns: [], oks: [] };
  if (!/<svg\b[^>]*>[\s\S]*<\/svg>/i.test(svgText)) {
    res.fails.push('FAIL svg: no <svg> element found');
    return res;
  }
  svgRules(svgText, 'svg', res.fails, res.warns);
  if (!res.fails.length) res.oks.push('ok svg: static rules');
  if (!chrome) {
    res.warns.push('WARN no Chrome: render checks skipped');
    return res;
  }
  const r = renderCheck(cardPage(svgText), chrome);
  res.fails.push(...r.fails);
  res.oks.push(...r.oks);
  return res;
}

function parseArgs(args) {
  const flags = new Set();
  const pos = [];
  let svgFile = null;
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === '--svg') {
      svgFile = args[++i];
      if (!svgFile || svgFile.startsWith('--')) die(2, '--svg needs a file');
    } else if (a === '--render' || a === '--json') flags.add(a);
    else if (a.startsWith('--')) die(2, `unknown flag ${a}`);
    else pos.push(a);
  }
  if (svgFile ? pos.length || flags.has('--render') : pos.length !== 1) {
    die(2, 'usage: node check.mjs <page.html> [--render] [--json] | node check.mjs --svg <file.svg> [--json]');
  }
  return { flags, pos, svgFile };
}

function chromeOrDie() {
  let chrome;
  try {
    chrome = findChrome();
  } catch (e) {
    die(3, e.message);
  }
  if (!chrome) die(3, 'no Chrome found; set CHROME');
  return chrome;
}

function readOrDie(file) {
  try {
    return fs.readFileSync(file, 'utf8');
  } catch (e) {
    return die(3, `cannot read ${file}: ${e.message}`);
  }
}

function report(res, flags, prefix = '') {
  if (flags.has('--json')) {
    const p = (l) => prefix + l;
    const out = { fails: res.fails.map(p), warns: res.warns.map(p), oks: res.oks.map(p) };
    process.stdout.write(`${JSON.stringify(out, null, 2)}\n`);
  } else {
    for (const l of [...res.fails, ...res.warns, ...res.oks]) process.stdout.write(`${prefix}${l}\n`);
    process.stdout.write(`${prefix}${res.fails.length} fail, ${res.warns.length} warn, ${res.oks.length} ok\n`);
  }
  process.exit(res.fails.length ? 1 : 0);
}

function main() {
  const { flags, pos, svgFile } = parseArgs(process.argv.slice(2));
  if (svgFile) {
    const file = path.resolve(svgFile);
    const text = readOrDie(file);
    let chrome = null;
    try {
      chrome = findChrome();
    } catch {
      /* treated as no Chrome */
    }
    let res;
    try {
      res = svgCheck(text, chrome);
    } catch (e) {
      die(e.exitCode || 3, e.message);
    }
    report(res, flags, `${path.basename(file)}: `);
  }
  const html = readOrDie(path.resolve(pos[0]));
  const res = staticCheck(html);
  if (flags.has('--render')) {
    try {
      const r = renderCheck(html, chromeOrDie());
      res.fails.push(...r.fails);
      res.oks.push(...r.oks);
    } catch (e) {
      die(e.exitCode || 3, e.message);
    }
  }
  report(res, flags);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main();
