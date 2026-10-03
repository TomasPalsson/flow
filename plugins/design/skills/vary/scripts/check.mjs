#!/usr/bin/env node
/**
 * check.mjs — mechanical craft floor for the `vary` design skill.
 *
 * Static analysis over HTML/CSS/JSX/TSX/Vue/Svelte/Astro sources. No browser, no dependencies.
 * Produces JSON the evaluator (and the builder, before hand-off) reads; numbers beat eyes for
 * contrast, presence of states, reduced-motion, image dimensions, font weights, arbitrary Tailwind
 * values, banned marketing phrases and em-dash density. What needs eyes (silhouette, memorable
 * thing, promise-vs-execution) is NOT here — see evaluator-prompt.md.
 *
 * Project-specificity checks (read the printed contract, then the code): concept-contract (CONCEPT /
 * FACTS / SIGNATURE DEVICE / SIGNATURE GRAPHIC filled), facts-in-build (cited facts reach the source),
 * bespoke-graphics (a drawing source exists: inline SVG, SVG-from-code, canvas/webgl, SVG filters, generated
 * masks), seeded-art (art code must not use Math.random), svg-a11y (large SVGs hidden or labelled).
 *
 * HERO TREATMENT (contract line, first word; default scene for persuade/experience, utility otherwise) changes bespoke-graphics:
 * scene/pattern/data-visual need a drawing source; photography/product-ui need an <img>/<picture>/<video> (hero visual source)
 * and get a photo-fidelity WARN for filters/blend modes/grayscale/halftone; typography/utility report INFO. WORLD: system: and
 * WORLD: canon are exempt from the subject-blind warning. Platform ios/android adds .swift .kt .dart and reports fold as N/A.
 *
 * fold: with --fold=<url-or-built-html> runs fold-check.mjs (Playwright) on the built page; otherwise UNKNOWN.
 *
 * Usage:  node check.mjs <file-or-dir> [more paths…] [--json] [--strict] [--fold=<url-or-built-html>]
 * Exit:   0 = no FAIL · 1 = at least one FAIL (with --strict, WARN also fails) · 2 = usage
 */
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, extname, dirname } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const EXT = new Set(['.html', '.htm', '.css', '.scss', '.jsx', '.tsx', '.js', '.ts', '.vue', '.svelte', '.astro', '.mdx']);
const args = process.argv.slice(2);
const json = args.includes('--json'); const strict = args.includes('--strict');
const foldArg = (args.find(a => a.startsWith('--fold=')) || '').slice(7);
const paths = args.filter(a => !a.startsWith('--'));
if (!paths.length) { console.error('usage: node check.mjs <file-or-dir> [...] [--json] [--strict] [--fold=<url-or-built-html>]'); process.exit(2); }

const SKIP_DIRS = ['node_modules', '.git', 'dist', '.next', 'build'];
function walk(p, out = [], exts = EXT, skip = SKIP_DIRS) {
  const st = statSync(p);
  if (st.isDirectory()) { for (const f of readdirSync(p)) { if (skip.includes(f)) continue; walk(join(p, f), out, exts, skip); } }
  else if (exts.has(extname(p).toLowerCase())) out.push(p);
  return out;
}
const load = exts => paths.flatMap(p => walk(p, [], exts)).map(f => ({ file: f, text: readFileSync(f, 'utf8') }));
let files = load(EXT);
let all = files.map(f => f.text).join('\n');
const checks = [];
const ev = (file, idx, text) => ({ file, line: text.slice(0, idx).split('\n').length, snippet: text.slice(Math.max(0, idx - 40), idx + 80).replace(/\s+/g, ' ').trim() });
function find(re, fn) { for (const f of files) { let m; const r = new RegExp(re.source, re.flags.includes('g') ? re.flags : re.flags + 'g'); while ((m = r.exec(f.text))) fn(f, m); } }

// ---- colour math -----------------------------------------------------------------------------------
function parseColor(s) {
  s = s.trim().toLowerCase();
  let m;
  if ((m = s.match(/^#([0-9a-f]{3,8})$/))) {
    let h = m[1]; if (h.length === 3 || h.length === 4) h = h.split('').map(c => c + c).join('');
    return [0, 2, 4].map(i => parseInt(h.slice(i, i + 2), 16) / 255);
  }
  if ((m = s.match(/^rgba?\(\s*([\d.]+)[,\s]+([\d.]+)[,\s]+([\d.]+)/))) return [m[1], m[2], m[3]].map(v => +v / 255);
  if ((m = s.match(/^oklch\(\s*([\d.]+%?)\s+([\d.]+)\s+([\d.]+)/))) {
    let L = parseFloat(m[1]); if (m[1].endsWith('%')) L /= 100; const C = +m[2], H = (+m[3] * Math.PI) / 180;
    const a = C * Math.cos(H), b = C * Math.sin(H);
    const l_ = L + 0.3963377774 * a + 0.2158037573 * b, m_ = L - 0.1055613458 * a - 0.0638541728 * b, s_ = L - 0.0894841775 * a - 1.2914855480 * b;
    const l = l_ ** 3, mm = m_ ** 3, ss = s_ ** 3;
    const R = 4.0767416621 * l - 3.3077115913 * mm + 0.2309699292 * ss, G = -1.2684380046 * l + 2.6097574011 * mm - 0.3413193965 * ss, B = -0.0041960863 * l - 0.7034186147 * mm + 1.7076147010 * ss;
    const g = c => { c = Math.min(1, Math.max(0, c)); return c <= 0.0031308 ? 12.92 * c : 1.055 * c ** (1 / 2.4) - 0.055; };
    return [g(R), g(G), g(B)];
  }
  const named = { white: '#fff', black: '#000', red: '#f00', blue: '#00f', gray: '#808080', grey: '#808080' };
  if (named[s]) return parseColor(named[s]);
  return null;
}
const lum = ([r, g, b]) => { const f = c => (c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4); return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b); };
const contrast = (a, b) => { const [x, y] = [lum(a), lum(b)].sort((p, q) => q - p); return (x + 0.05) / (y + 0.05); };

// ---- 1. seed key present ------------------------------------------------------------------------------
{
  const hits = []; find(/SEED KEY:/, (f, m) => hits.push(ev(f.file, m.index, f.text)));
  checks.push({ id: 'seed-key-present', status: hits.length ? 'PASS' : 'FAIL', evidence: hits.slice(0, 2), detail: hits.length ? 'contract block found' : 'no "SEED KEY:" contract in shipped output — the roll was skipped or the comment was stripped by the build' });
}
// ---- 2. contrast on literal colour pairs in the same rule ----------------------------------------------
{
  const fails = [], passes = []; let pairs = 0;
  find(/\{([^{}]*)\}/s, (f, m) => {
    const body = m[1];
    const fg = body.match(/(?:^|;|\s)color\s*:\s*([^;!]+)/); const bg = body.match(/background(?:-color)?\s*:\s*([^;!]+)/);
    if (!fg || !bg) return; const a = parseColor(fg[1]), b = parseColor(bg[1]); if (!a || !b) return;
    pairs++; const c = contrast(a, b); const fs = body.match(/font-size\s*:\s*([\d.]+)(px|rem)/);
    const large = fs && ((fs[2] === 'px' && +fs[1] >= 24) || (fs[2] === 'rem' && +fs[1] >= 1.5));
    const min = large ? 3 : 4.5;
    (c < min ? fails : passes).push({ ...ev(f.file, m.index, f.text), ratio: +c.toFixed(2), min });
  });
  checks.push({ id: 'contrast', status: fails.length ? 'FAIL' : pairs ? 'PASS' : 'UNKNOWN', evidence: fails.slice(0, 8), detail: `${pairs} literal fg/bg pairs checked, ${fails.length} below WCAG minimum; CSS-variable cascades are not resolved here — verify those from a screenshot` });
}
// ---- 3. focus-visible ---------------------------------------------------------------------------------
{
  const outlineNone = []; find(/outline\s*:\s*(none|0)\b/, (f, m) => outlineNone.push(ev(f.file, m.index, f.text)));
  const fv = /:focus-visible\s*[^{]*\{[^}]*(outline|box-shadow|border)[^}]*\}/.test(all) || /focus-visible:(outline|ring)/.test(all);
  const anyInteractive = /<(button|a |input|select|textarea)|role="button"/i.test(all);
  const status = !anyInteractive ? 'UNKNOWN' : fv ? (outlineNone.length && !/:focus-visible/.test(all) ? 'FAIL' : 'PASS') : outlineNone.length ? 'FAIL' : 'WARN';
  checks.push({ id: 'focus-visible', status, evidence: outlineNone.slice(0, 4), detail: fv ? 'a :focus-visible rule with a visible treatment exists' : outlineNone.length ? 'outline removed with no :focus-visible replacement — keyboard users get nothing' : 'no explicit :focus-visible styling; browser default will show (acceptable only if untouched)' });
}
// ---- 4. states present -------------------------------------------------------------------------------
{
  const states = { hover: /:hover|hover:/, 'focus-visible': /:focus-visible|focus-visible:/, active: /:active|active:|aria-pressed|data-state="?(active|open)/, disabled: /:disabled|disabled:|aria-disabled|\bdisabled\b/, loading: /loading|aria-busy|skeleton|spinner|progress/i, error: /error|invalid|aria-invalid|:invalid/i, success: /success|complete|done|saved/i, empty: /empty|no results|nothing here|get started/i };
  const found = Object.entries(states).filter(([, re]) => re.test(all)).map(([k]) => k);
  const n = found.length + 1; // default state always exists
  checks.push({ id: 'states-present', status: n >= 7 ? 'PASS' : n >= 5 ? 'WARN' : 'FAIL', evidence: [], detail: `${n}/9 states have evidence (default + ${found.join(', ') || 'none'}); missing: ${Object.keys(states).filter(s => !found.includes(s)).join(', ') || 'none'}` });
}
// ---- 5. reduced motion --------------------------------------------------------------------------------
{
  const animates = /@keyframes|transition\s*:|animation\s*:|animate-|transition-|framer-motion|motion\./.test(all);
  const rm = /prefers-reduced-motion/.test(all) || /useReducedMotion|motion-reduce:/.test(all);
  checks.push({ id: 'reduced-motion', status: !animates ? 'PASS' : rm ? 'PASS' : 'FAIL', evidence: [], detail: !animates ? 'no motion declared' : rm ? 'prefers-reduced-motion handled' : 'motion declared but prefers-reduced-motion never consulted' });
}
// ---- 6. image dimensions -----------------------------------------------------------------------------
{
  const bad = []; let n = 0;
  find(/<img\b[^>]*>/i, (f, m) => { n++; const t = m[0]; const ok = /\bwidth\s*=/.test(t) && /\bheight\s*=/.test(t) || /aspect-ratio|aspect-\[|aspect-(video|square)/.test(t) || /\bfill\b/.test(t); if (!ok) bad.push(ev(f.file, m.index, f.text)); });
  checks.push({ id: 'img-dimensions', status: !n ? 'UNKNOWN' : bad.length ? 'FAIL' : 'PASS', evidence: bad.slice(0, 6), detail: `${n} <img>, ${bad.length} without width+height or aspect-ratio (CLS risk)` });
}
// ---- 7. font weights actually loaded -------------------------------------------------------------------
{
  const families = new Map();
  find(/fonts\.googleapis\.com\/css2\?[^"'\s)]+/, (f, m) => {
    for (const fam of m[0].matchAll(/family=([^&:]+)(?::([^&]+))?/g)) {
      const name = decodeURIComponent(fam[1].replace(/\+/g, ' ')); const axes = fam[2] || '';
      let weights = 0; const range = axes.match(/(\d{3})\.\.(\d{3})/); if (range) weights = Math.floor((+range[2] - +range[1]) / 100) + 1; else weights = (axes.match(/\d{3}/g) || []).length || 1;
      families.set(name, Math.max(families.get(name) || 0, weights));
    }
  });
  find(/api\.fontshare\.com\/v2\/css\?[^"'\s)]+/, (f, m) => { for (const fam of m[0].matchAll(/f\[\]=([^@&]+)(?:@([^&]+))?/g)) families.set(fam[1], (fam[2] || '').split(',').length); });
  find(/@font-face\s*\{[^}]*font-family\s*:\s*["']?([^;"']+)["']?[^}]*\}/, (f, m) => { const name = m[1].trim(); const body = m[0]; const range = body.match(/font-weight\s*:\s*(\d{3})\s+(\d{3})/); families.set(name, range ? 9 : (families.get(name) || 0) + 1); });
  const usedAsBoth = [...families.entries()].filter(([name]) => { const re = new RegExp(name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'g'); return (all.match(re) || []).length >= 3; });
  const thin = usedAsBoth.filter(([, w]) => w < 3);
  checks.push({ id: 'font-weights-loaded', status: !families.size ? 'UNKNOWN' : thin.length ? 'WARN' : 'PASS', evidence: thin.map(([n, w]) => ({ family: n, weights: w })), detail: families.size ? `${families.size} webfont families; ${thin.length} widely-used families load <3 weights (hierarchy will fall back to faux bold)` : 'no webfont loading found (system stack, or fonts loaded outside these files)' });
}
// ---- 8. arbitrary Tailwind values ----------------------------------------------------------------------
{
  const hits = []; find(/class(?:Name)?=["'`][^"'`]*?\b[a-z-]+-\[[^\]]+\]/, (f, m) => hits.push(ev(f.file, m.index, f.text)));
  checks.push({ id: 'arbitrary-tailwind-values', status: hits.length > 6 ? 'WARN' : 'PASS', evidence: hits.slice(0, 6), detail: `${hits.length} arbitrary values (e.g. p-[17px], bg-[#1a5276]); each one bypasses the token scale` });
}
// ---- 9. banned phrases + em-dash density ------------------------------------------------------------------
{
  const banned = ['build the future', 'scale without limits', 'empower your', 'revolutioni', 'unlock the power', 'unleash', 'seamless', 'cutting-edge', 'game-changing', 'next-level', 'transform your', 'supercharge', 'streamline your', 'in today\'s fast-paced', 'best-in-class', 'trusted by \\d[\\d,]*\\+? ', 'say goodbye to', 'the future of'];
  const visible = all.replace(/<script[\s\S]*?<\/script>|<style[\s\S]*?<\/style>|<!--[\s\S]*?-->/gi, ' ').replace(/<[^>]+>/g, ' ');
  const hits = []; for (const b of banned) { const re = new RegExp(b, 'gi'); let m; while ((m = re.exec(visible))) hits.push({ phrase: m[0], context: visible.slice(Math.max(0, m.index - 30), m.index + 50).replace(/\s+/g, ' ') }); }
  const words = (visible.match(/\b\w+\b/g) || []).length; const em = (visible.match(/—/g) || []).length; const emPer600 = words ? (em / words) * 600 : 0;
  const status = hits.length >= 3 ? 'FAIL' : hits.length || emPer600 > 7 ? 'WARN' : 'PASS';
  checks.push({ id: 'banned-phrase-scan', status, evidence: hits.slice(0, 8), detail: `${hits.length} AI-vocabulary phrases; ${em} em dashes in ${words} words (${emPer600.toFixed(1)} per 600; >7 reads machine-written)` });
}
// ---- 10. template tells (structural) ------------------------------------------------------------------------
{
  const tells = [];
  const eq3 = (all.match(/grid-cols-3\b|repeat\(3,\s*(1fr|minmax)/g) || []).length; if (eq3) tells.push(`${eq3}× three-equal-column grid`);
  const r2xl = (all.match(/rounded-2xl|border-radius\s*:\s*1(\.\d+)?rem/g) || []).length; if (r2xl >= 6) tells.push(`${r2xl}× rounded-2xl / 1rem radius (uniform rounding)`);
  if (/bg-clip-text|background-clip\s*:\s*text/.test(all)) tells.push('gradient text');
  const glass = (all.match(/backdrop-blur|backdrop-filter\s*:\s*blur/g) || []).length; if (glass > 2) tells.push(`${glass}× backdrop blur (decorative glass)`);
  if (/indigo-[456]00|from-indigo|to-purple|#6366f1|#4f46e5/i.test(all)) tells.push('indigo/purple default accent');
  if (/tracking-(wide|widest)[^"']*uppercase|uppercase[^"']*tracking-(wide|widest)/.test(all) && /text-(xs|sm)/.test(all)) tells.push('possible eyebrow/kicker labels (small tracked uppercase above headings) — confirm they carry information');
  const shadowLg = (all.match(/shadow-lg\b/g) || []).length; if (shadowLg >= 4) tells.push(`${shadowLg}× shadow-lg (uniform elevation)`);
  checks.push({ id: 'template-tells', status: tells.length >= 3 ? 'FAIL' : tells.length ? 'WARN' : 'PASS', evidence: tells.map(t => ({ tell: t })), detail: tells.length ? tells.join('; ') : 'none of the common template tells detected' });
}

// ---- project-specificity checks: contract parsing -----------------------------------------------------------
function contractOf(text) {
  const i = text.indexOf('SEED KEY:'); if (i < 0) return null;
  const s = Math.max(text.lastIndexOf('<!--', i), text.lastIndexOf('/*', i)); const ends = ['-->', '*/'].map(e => text.indexOf(e, i)).filter(x => x >= 0);
  const e = ends.length ? Math.min(...ends) : -1;
  return s >= 0 && e >= 0 && e - s < 8000 ? text.slice(s, e + 3) : text.slice(Math.max(0, i - 200), i + 3000);
}
const contractFile = files.find(f => f.text.includes('SEED KEY:'));
const contract = contractFile ? contractOf(contractFile.text) : null;
const modeM = contract && contract.match(/SEED KEY:[^\n]*?mode\s+(\w+)/);
const mode = modeM ? modeM[1].toLowerCase() : null;
const line = key => { const m = contract && contract.match(new RegExp(`^[ \\t]*${key}:[ \\t]*(.*)$`, 'm')); return m ? m[1].trim() : null; };
const factLines = (() => { if (!contract) return []; const ls = contract.split('\n'); const i = ls.findIndex(l => /^\s*FACTS:/.test(l)); if (i < 0) return []; const out = []; for (const l of ls.slice(i + 1)) { if (/^\s*[-*]\s+/.test(l)) out.push(l.replace(/^\s*[-*]\s+/, '')); else if (l.trim()) break; } return out; })();
const unfilled = v => v === null || v === '' || /<model\b|<what\b|<fill/i.test(v);
const CODE_EXT = new Set(['.js', '.jsx', '.ts', '.tsx', '.vue', '.svelte', '.astro', '.mdx']);
const worldLine = line('WORLD'); const isCanon = !!worldLine && /^(canon\b|system:)/i.test(worldLine);
const platformM = contract && contract.match(/SEED KEY:[^\n]*?platform\s+(\w+)/);
const native = !!platformM && /^(ios|android)$/i.test(platformM[1]);
if (native) { files = load(new Set([...EXT, '.swift', '.kt', '.dart'])); all = files.map(f => f.text).join('\n'); }
// HERO TREATMENT: first word of the contract line; default scene for persuade/experience, utility otherwise (roll.mjs / SKILL Step 3a)
const TREATMENTS = ['scene', 'pattern', 'photography', 'product-ui', 'typography', 'data-visual', 'utility'];
const treatmentWord = (line('HERO TREATMENT') || '').split(/\s/)[0].toLowerCase();
const treatment = TREATMENTS.includes(treatmentWord) ? treatmentWord : (mode === 'persuade' || mode === 'experience' || !mode ? 'scene' : 'utility');

// ---- 11. concept contract ---------------------------------------------------------------------------------------
{
  if (!contract) checks.push({ id: 'concept-contract', status: 'UNKNOWN', evidence: [], detail: 'no contract block to read (see seed-key-present)' });
  else {
    const concept = line('CONCEPT');
    if (concept === null || /^none\b/i.test(concept)) {
      checks.push({ id: 'concept-contract', status: isCanon ? 'PASS' : 'WARN', evidence: [], detail: isCanon ? 'CONCEPT: none under WORLD: canon (exempt from the subject-blind warning)' : 'subject-blind roll: CONCEPT is none; a new project needs a dossier and concepts before the roll' });
    } else {
      const missing = [];
      if (!factLines.length || factLines.some(l => /<model\b/i.test(l))) missing.push('FACTS (no cited fact lines)');
      if (unfilled(line('SIGNATURE DEVICE'))) missing.push('SIGNATURE DEVICE');
      if (unfilled(line('SIGNATURE GRAPHIC'))) missing.push('SIGNATURE GRAPHIC (still the <model: ...> placeholder or absent)');
      checks.push({ id: 'concept-contract', status: missing.length ? 'FAIL' : 'PASS', evidence: missing.map(m => ({ snippet: m })), detail: missing.length ? `CONCEPT ${concept.slice(0, 40)} is set but unfilled: ${missing.join('; ')}` : `CONCEPT, ${factLines.length} FACTS, SIGNATURE DEVICE and SIGNATURE GRAPHIC are filled` });
    }
  }
}
// ---- 12. cited facts reach the build ------------------------------------------------------------------------------
{
  const norm = s => s.toLowerCase().replace(/\s+/g, ' ');
  const dataFiles = paths.flatMap(p => walk(p, [], new Set([...EXT, '.json']), [...SKIP_DIRS, '.vary']))
    .filter(f => !/(^|\/)(dossier|concepts|package-lock|package)\.json$/.test(f)).map(f => ({ file: f, text: readFileSync(f, 'utf8') }));
  const corpus = norm(dataFiles.map(f => f.text.replace(contractOf(f.text) || '\u0000', ' ')).join('\n'));
  const tests = [];
  for (const l of factLines) {
    const q = l.match(/"([^"]+)"/); const text = (q ? q[1] : l).trim(); if (!text) continue;
    const segs = text.split(/\s[—–·|-]\s|[—–·|;()[\]…"“”]|[.,:](?=\s|$)/).map(s => s.trim()).filter(s => s.split(/\s+/).filter(w => /[\p{L}]/u.test(w)).length >= 3);
    const seg = segs.sort((a, b) => b.split(/\s+/).length - a.split(/\s+/).length)[0];
    const nums = (text.match(/\d[\d.,:]*\d/g) || []).filter(n => n.length >= 3);
    const hitSeg = seg ? (() => { const w = norm(seg).split(' '); const n = Math.min(4, w.length); for (let i = 0; i + n <= w.length; i++) if (corpus.includes(w.slice(i, i + n).join(' '))) return true; return false; })() : false;
    const hitNum = nums.some(n => corpus.includes(n));
    if (!seg && !nums.length) continue;
    tests.push({ fact: text.slice(0, 70), found: hitSeg || hitNum });
  }
  const found = tests.filter(t => t.found).length; const need = Math.min(2, tests.length);
  checks.push({ id: 'facts-in-build', status: !contract || !tests.length ? 'UNKNOWN' : found >= need ? 'PASS' : 'FAIL', evidence: tests.filter(t => !t.found).slice(0, 6).map(t => ({ snippet: `not found in source: ${t.fact}` })), detail: !tests.length ? 'no testable FACTS lines in the contract' : found >= need ? `${found}/${tests.length} cited facts found in source or data files (contract comment excluded)` : `${found}/${tests.length} cited facts found: cited facts never reach the build (need ${need})` });
}
// ---- 13. bespoke graphics ------------------------------------------------------------------------------------------
const svgBlocks = []; // large inline SVGs, shared with svg-a11y
find(/<svg\b([^>]*)>([\s\S]*?)<\/svg>/i, (f, m) => { const vb = m[1].match(/viewBox\s*=\s*["']?\{?["']?\s*([-\d.]+)[\s,]+([-\d.]+)[\s,]+([-\d.]+)[\s,]+([-\d.]+)/); const big = !!vb && Math.max(+vb[3], +vb[4]) > 32; svgBlocks.push({ f, m, big, shapes: (m[2].match(/<(path|circle|rect|polygon|line|ellipse)\b/gi) || []).length }); });
{
  const inline = svgBlocks.filter(b => b.big && b.shapes >= 8);
  const fromCode = files.filter(f => CODE_EXT.has(extname(f.file).toLowerCase()) && (/`[^`]*<(svg|path)\b/.test(f.text) || /["']<(svg|path)\b/.test(f.text) || /\bd=\$\{|\bd=\{`/.test(f.text)));
  const canvas = files.filter(f => /getContext\(\s*['"`](2d|webgl2?|experimental-webgl)['"`]/.test(f.text));
  const filters = files.filter(f => /feTurbulence|feDisplacementMap/.test(f.text));
  const masks = files.filter(f => /(mask-image|clip-path\s*:\s*polygon)\s*:?[^;}\n]*(\$\{|var\(|url\()|\.(maskImage|clipPath)\s*=/.test(f.text));
  const total = inline.length + fromCode.length + canvas.length + filters.length + masks.length;
  const strict = mode === 'persuade' || mode === 'experience';
  const ev0 = [...inline.slice(0, 2).map(b => ev(b.f.file, b.m.index, b.f.text)), ...[...fromCode, ...canvas, ...filters, ...masks].slice(0, 3).map(f => ({ file: f.file, line: 1, snippet: 'drawing source' }))];
  const imgSrc = files.filter(f => /<(img|picture|video)\b/i.test(f.text) || /<(Image|NextImage|Picture)\b|\bAsyncImage\(|\bImage\(/.test(f.text));
  if (treatment === 'typography' || treatment === 'utility') {
    checks.push({ id: 'bespoke-graphics', status: 'INFO', evidence: ev0, detail: `treatment ${treatment}: no drawn hero is required (${total} drawing source(s) found); judged by the evaluator's signature-element row` });
  } else if (treatment === 'photography' || treatment === 'product-ui') {
    checks.push({ id: 'bespoke-graphics', status: imgSrc.length ? 'PASS' : 'FAIL', evidence: imgSrc.slice(0, 3).map(f => ({ file: f.file, line: 1, snippet: 'image source' })), detail: `hero visual source (treatment ${treatment}): ${imgSrc.length} file(s) with <img>/<picture>/<video> or an image component${imgSrc.length ? '' : '; no hero image or video found'}` });
  } else {
    checks.push({ id: 'bespoke-graphics', status: total ? 'PASS' : strict ? 'FAIL' : 'WARN', evidence: ev0, detail: `drawing sources: ${inline.length} inline SVG (>=8 shapes, viewBox>32), ${fromCode.length} file(s) returning SVG from code, ${canvas.length} canvas/webgl, ${filters.length} SVG-filter file(s), ${masks.length} generated mask file(s)${total ? '' : `; nothing drawn of the subject (mode ${mode || 'unknown'}${strict ? ', FAIL' : ', WARN'})`}` });
  }
}
// ---- 13b. photo fidelity (photography / product-ui): the client's images ship unaltered ----------------------------------
if (treatment === 'photography' || treatment === 'product-ui') {
  const hits = [];
  const directive = /DIRECTIVES?:[^\n]*(grayscale|greyscale|black and white|halftone|duotone|filter)/i.test(contract || '');
  const bad = /(?<![-\w])filter\s*:\s*(?!none)(?!drop-shadow)[^;}]*|mix-blend-mode\s*:\s*(?!normal)[^;}]*|\bgrayscale\b|\bsepia\b|\bhalftone\b/gi;
  find(bad, (f, m) => hits.push(ev(f.file, m.index, f.text)));
  checks.push({ id: 'photo-fidelity', status: hits.length && !directive ? 'WARN' : 'PASS', evidence: hits.slice(0, 4), detail: hits.length ? (directive ? `${hits.length} filter/blend/grayscale/halftone use(s), allowed by a DIRECTIVES line` : `${hits.length} filter/blend/grayscale/sepia/halftone use(s): confirm none touches the hero or a gallery image (treatment ${treatment} ships client images unaltered)`) : 'no filter, blend mode, grayscale, sepia or halftone found' });
}
// ---- 14. seeded art ------------------------------------------------------------------------------------------------
{
  const bad = files.filter(f => /Math\.random\s*\(/.test(f.text) && (/getContext\(\s*['"`](2d|webgl)/.test(f.text) || (CODE_EXT.has(extname(f.file).toLowerCase()) && (/`[^`]*<(svg|path)\b/.test(f.text) || /["']<(svg|path)\b/.test(f.text) || /\bd=\$\{|\bd=\{`/.test(f.text)))));
  checks.push({ id: 'seeded-art', status: bad.length ? 'WARN' : 'PASS', evidence: bad.slice(0, 4).map(f => ({ file: f.file, line: f.text.slice(0, f.text.search(/Math\.random\s*\(/)).split('\n').length, snippet: 'Math.random in a file that emits SVG or canvas' })), detail: bad.length ? `${bad.length} art file(s) use Math.random: unseeded art re-renders differently each load; use a seeded PRNG keyed per item` : 'no art file uses Math.random' });
}
// ---- 15. svg a11y --------------------------------------------------------------------------------------------------
{
  const big = svgBlocks.filter(b => b.big); const bad = [];
  for (const b of big) {
    const a = b.m[1]; const hidden = /aria-hidden(?!\s*=\s*["'{]\s*false)/.test(a);
    const labelled = /role\s*=\s*["']img["']/.test(a) && (/aria-label(ledby)?\s*=/.test(a) || /<title\b/i.test(b.m[2]));
    if (!hidden && !labelled) bad.push(ev(b.f.file, b.m.index, b.f.text));
  }
  checks.push({ id: 'svg-a11y', status: !big.length ? 'UNKNOWN' : bad.length ? 'WARN' : 'PASS', evidence: bad.slice(0, 5), detail: !big.length ? 'no inline SVG with viewBox > 32' : `${big.length} large inline SVG(s), ${bad.length} neither aria-hidden="true" nor role="img" with <title>/aria-label` });
}

// ---- fold: first-viewport scene measurement (browser; delegated to fold-check.mjs) ---------------------
{
  const how = 'run: node fold-check.mjs <url-or-built-html> [--mode persuade|experience|operate|read], or pass --fold=<url-or-built-html> here';
  if (native) checks.push({ id: 'fold', status: 'N/A', evidence: [], detail: 'N/A (native platform: use device screenshots)' });
  else if (!foldArg) checks.push({ id: 'fold', status: 'UNKNOWN', evidence: [], detail: `no built page given; ${how}` });
  else {
    const r = spawnSync('node', [join(dirname(fileURLToPath(import.meta.url)), 'fold-check.mjs'), foldArg, ...(mode ? ['--mode', mode] : []), '--treatment', treatment], { encoding: 'utf8' });
    const out = (r.stdout || '').trim();
    const lines = out.split('\n').filter(l => /\[(PASS|FAIL|INFO)\]/.test(l)).map(l => ({ snippet: l.trim() }));
    if (/fold-check SKIP/.test(out)) checks.push({ id: 'fold', status: 'UNKNOWN', evidence: [], detail: out });
    else if (r.status === 0 || r.status === 1) checks.push({ id: 'fold', status: r.status ? 'FAIL' : 'PASS', evidence: lines.filter(l => /\[FAIL\]/.test(l.snippet)), detail: `first viewport ${r.status ? 'fails' : 'meets'} the ${treatment} gates (${lines.length} metrics, mode ${mode || 'persuade'})` });
    else checks.push({ id: 'fold', status: 'UNKNOWN', evidence: [], detail: `fold-check could not run: ${(r.stderr || out).trim().split('\n')[0]}; ${how}` });
  }
}

const worst = checks.some(c => c.status === 'FAIL') ? 'FAIL' : checks.some(c => c.status === 'WARN') ? 'WARN' : 'PASS';
const report = { files: files.length, verdict: worst, checks };
if (json) console.log(JSON.stringify(report, null, 1));
else {
  console.log(`vary check — ${files.length} file(s) — ${worst}`);
  for (const c of checks) { console.log(`  [${c.status.padEnd(7)}] ${c.id}: ${c.detail}`); for (const e of (c.evidence || []).slice(0, 3)) console.log(`             ${e.file ? `${e.file}:${e.line} ` : ''}${e.snippet || e.phrase || e.tell || e.family || ''}${e.ratio ? ` (ratio ${e.ratio} < ${e.min})` : ''}`); }
}
process.exit(worst === 'FAIL' || (strict && worst === 'WARN') ? 1 : 0);
