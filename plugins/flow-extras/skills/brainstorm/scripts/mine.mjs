#!/usr/bin/env node
// mine.mjs - cut a repository into DISJOINT evidence slices for idea-generator agents.
// Deterministic, no model, node: built-ins only.
//
// Usage:
//   node mine.mjs --repo <dir> --out <run-dir> [--focus <subpath>] [--max-lines 220]
//
// Writes <out>/project.md, <out>/tree.txt, <out>/slices/<id>.md and <out>/slices.json.
// Only slices with >= 3 evidence items are written (whole-source needs just 1 file). Every item starts with a citable
// 'path:line', 'path' or commit hash (a few summary items start with a label instead).
//
// Exit codes: 0 ok, 1 check failed (no slice reached 3 items), 2 bad args,
//             3 data/IO error (repo missing, focus missing, write failure).

import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

// ---------- constants ----------

const EXCLUDED_DIRS = new Set(['.git', 'node_modules', 'dist', 'build', 'target', 'vendor',
  '.venv', 'venv', '__pycache__', '.next', 'coverage', '.brainstorm']);
const LOCKFILES = new Set(['package-lock.json', 'bun.lock', 'bun.lockb', 'yarn.lock',
  'pnpm-lock.yaml', 'Cargo.lock', 'poetry.lock', 'uv.lock']);
const BINARY_EXTS = new Set(['png', 'jpg', 'jpeg', 'gif', 'webp', 'ico', 'bmp', 'tiff', 'avif', 'heic',
  'woff', 'woff2', 'ttf', 'otf', 'eot', 'zip', 'gz', 'tgz', 'bz2', 'xz', '7z', 'rar', 'tar', 'jar',
  'pdf', 'mp3', 'mp4', 'mov', 'wav', 'ogg', 'webm', 'exe', 'dll', 'so', 'dylib', 'class', 'wasm',
  'bin', 'o', 'a', 'pyc', 'sqlite', 'db']);
const CODE_EXTS = new Set(['js', 'mjs', 'cjs', 'ts', 'tsx', 'jsx', 'py', 'rs', 'go', 'java', 'kt',
  'swift', 'rb', 'sh', 'c', 'cc', 'cpp', 'h', 'hpp', 'cs', 'php', 'lua', 'vue', 'svelte']);
const FLAG_EXTS = new Set(['rs', 'ts', 'js', 'py', 'go', 'mjs', 'cjs', 'tsx', 'jsx']);
const PATH_EXTS = new Set([...CODE_EXTS, 'json', 'md', 'toml', 'yaml', 'yml', 'txt', 'lock', 'css',
  'html', 'env', 'cfg', 'ini', 'conf', 'xml', 'sql', 'mdx']);
const MAX_FILE_BYTES = 400 * 1024;
const TREE_MAX = 400;
const TEXT_CAP = 160;

class Fail extends Error {
  constructor(code, msg) { super(msg); this.code = code; }
}

// ---------- small helpers ----------

const ext = (rel) => path.extname(rel).slice(1).toLowerCase();
const isCode = (rel) => CODE_EXTS.has(ext(rel));
const isMd = (rel) => ['md', 'markdown', 'mdx'].includes(ext(rel));
const clip = (s, n = TEXT_CAP) => { const t = s.trim(); return t.length > n ? `${t.slice(0, n)}...` : t; };
const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const item = (file, text) => ({ file, text });
const isTest = (rel) => /(^|\/)(tests?|__tests__|specs?)(\/|$)|\.(test|spec)\.|(^|\/)test_[^/]*\.py$|_test\.(go|py|rs)$/i.test(rel);
const isDoc = (rel) => isMd(rel) && (/(^|\/)README[^/]*$/i.test(rel) || /^docs\//i.test(rel));

function wordRe(word) {
  return new RegExp(`(?<![\\w-])${esc(word)}(?![\\w-])`);
}

function note(msg) { process.stderr.write(`mine: ${msg}\n`); }

// ---------- args ----------

function parseArgs(argv) {
  const opts = { repo: null, out: null, focus: null, maxLines: 220 };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    const val = () => {
      if (i + 1 >= argv.length) throw new Fail(2, `missing value for ${a}`);
      return argv[++i];
    };
    if (a === '--repo') opts.repo = val();
    else if (a === '--out') opts.out = val();
    else if (a === '--focus') opts.focus = val();
    else if (a === '--max-lines') opts.maxLines = Number(val());
    else if (a === '-h' || a === '--help') opts.help = true;
    else throw new Fail(2, `unknown argument: ${a}`);
  }
  if (opts.help) return opts;
  if (!opts.repo || !opts.out) throw new Fail(2, 'usage: mine.mjs --repo <dir> --out <run-dir> [--focus <subpath>] [--max-lines 220]');
  if (!Number.isInteger(opts.maxLines) || opts.maxLines < 5) throw new Fail(2, '--max-lines must be an integer >= 5');
  return opts;
}

// ---------- file collection ----------

function excludedPath(rel) {
  const parts = rel.split('/');
  const name = parts[parts.length - 1];
  if (parts.slice(0, -1).some((p) => EXCLUDED_DIRS.has(p))) return true;
  if (LOCKFILES.has(name)) return true;
  if (/\.min\./.test(name) || name.endsWith('.map')) return true;
  return BINARY_EXTS.has(ext(rel));
}

function looksBinary(abs) {
  const fd = fs.openSync(abs, 'r');
  try {
    const buf = Buffer.alloc(8192);
    const n = fs.readSync(fd, buf, 0, 8192, 0);
    return buf.subarray(0, n).includes(0);
  } finally { fs.closeSync(fd); }
}

function usable(repo, rel) {
  if (excludedPath(rel)) return false;
  let st;
  try { st = fs.statSync(path.join(repo, rel)); } catch { return false; }
  if (!st.isFile() || st.size > MAX_FILE_BYTES) return false;
  return !looksBinary(path.join(repo, rel));
}

function walk(repo, dir = '') {
  const out = [];
  for (const e of fs.readdirSync(path.join(repo, dir), { withFileTypes: true })) {
    const rel = dir ? `${dir}/${e.name}` : e.name;
    if (e.isDirectory()) { if (!EXCLUDED_DIRS.has(e.name)) out.push(...walk(repo, rel)); }
    else if (e.isFile()) out.push(rel);
  }
  return out;
}

function gitRaw(repo, args) {
  return execFileSync('git', ['-C', repo, '-c', 'core.quotepath=off', ...args],
    { encoding: 'utf8', maxBuffer: 1 << 30, stdio: ['ignore', 'pipe', 'pipe'] });
}

function detectGit(repo) {
  if (!fs.existsSync(path.join(repo, '.git'))) return false;
  try { gitRaw(repo, ['rev-parse', '--is-inside-work-tree']); return true; } catch (e) {
    note(`git unavailable, treating as no history: ${String(e.message).split('\n')[0]}`);
    return false;
  }
}

function normalizeFocus(repo, focus) {
  if (!focus) return null;
  const f = focus.replace(/^\.\//, '').replace(/\/+$/, '');
  if (!f || f.startsWith('..') || path.isAbsolute(f) || !fs.existsSync(path.join(repo, f))) {
    throw new Fail(3, `--focus path not found inside repo: ${focus}`);
  }
  return f;
}

function buildContext(opts) {
  const repo = path.resolve(opts.repo);
  if (!fs.existsSync(repo) || !fs.statSync(repo).isDirectory()) throw new Fail(3, `repo is not a directory: ${repo}`);
  const git = detectGit(repo);
  let listed;
  if (git) {
    try { listed = gitRaw(repo, ['ls-files', '-z']).split('\0').filter(Boolean); } catch (e) {
      throw new Fail(3, `git ls-files failed: ${String(e.message).split('\n')[0]}`);
    }
  } else listed = walk(repo);
  const files = [...new Set(listed)].filter((r) => usable(repo, r)).sort();
  const focus = normalizeFocus(repo, opts.focus);
  const scope = focus ? files.filter((f) => f === focus || f.startsWith(`${focus}/`)) : files;
  const cache = new Map();
  const ctx = { repo, git, files, scope, focus, scopeSet: new Set(scope), _cache: cache };
  ctx.text = (rel) => {
    if (!cache.has(rel)) cache.set(rel, fs.readFileSync(path.join(repo, rel), 'utf8'));
    return cache.get(rel);
  };
  ctx.lines = (rel) => ctx.text(rel).replace(/\n$/, '').split('\n');
  return ctx;
}

function safeGit(ctx, args) {
  if (!ctx.git) return null;
  try { return gitRaw(ctx.repo, args); } catch (e) {
    note(`git ${args[0]} failed: ${String(e.message).split('\n')[0]}`);
    return null;
  }
}

function corpus(ctx, pred) {
  return ctx.files.filter(pred).map((f) => ctx.text(f)).join('\n');
}

// ---------- git parsing ----------

function parseCommits(out) {
  const commits = [];
  let cur = null;
  for (const line of out.split('\n')) {
    if (line.startsWith('@@')) {
      const [hash, date, ...s] = line.slice(2).split('\t');
      cur = { hash, date, subject: s.join('\t'), files: [], added: 0, deleted: 0 };
      commits.push(cur);
    } else if (cur && line) {
      const m = /^(\d+|-)\t(\d+|-)\t/.exec(line);
      if (m) { cur.added += Number(m[1]) || 0; cur.deleted += Number(m[2]) || 0; } else cur.files.push(line);
    }
  }
  return commits;
}

function hotspots(ctx) {
  if (ctx._hot !== undefined) return ctx._hot;
  const out = safeGit(ctx, ['log', '--since=12.months', '--name-only', '--relative', '--format=']);
  if (out === null) { ctx._hot = null; return null; }
  const counts = new Map();
  for (const f of out.split('\n')) if (f && ctx.scopeSet.has(f)) counts.set(f, (counts.get(f) || 0) + 1);
  ctx._hot = [...counts].map(([file, commits]) => ({ file, commits, lines: ctx.lines(file).length }))
    .sort((a, b) => b.commits * b.lines - a.commits * a.lines || a.file.localeCompare(b.file)).slice(0, 8);
  return ctx._hot;
}

// ---------- markdown sections ----------

function headings(lines) {
  const hs = [];
  let fence = false;
  lines.forEach((l, i) => {
    if (/^\s*(```|~~~)/.test(l)) fence = !fence;
    const m = !fence && /^(#{1,6})\s+(.*)$/.exec(l);
    if (m) hs.push({ idx: i, level: m[1].length, title: m[2] });
  });
  return hs;
}

function sections(lines, re) {
  const hs = headings(lines);
  return hs.filter((h) => re.test(h.title)).map((h) => {
    const next = hs.find((o) => o.idx > h.idx && o.level <= h.level);
    return { ...h, end: next ? next.idx : lines.length };
  });
}

// ---------- slices ----------

function sliceHotspot(ctx) {
  const hot = hotspots(ctx);
  if (!hot) return null;
  const items = hot.map((h) => {
    const authors = new Set((safeGit(ctx, ['log', '--since=12.months', '--format=%an', '--', h.file]) || '').split('\n').filter(Boolean));
    const subjects = (safeGit(ctx, ['log', '-n4', '--format=%s', '--', h.file]) || '').split('\n').filter(Boolean);
    const head = `${h.file}: ${h.commits} commits in 12 months, ${h.lines} lines, ${authors.size} authors`;
    return item(h.file, [head, ...subjects.map((s) => `  - ${clip(s, 100)}`)].join('\n'));
  });
  return { id: 'hotspot', title: 'Hotspots: most-changed files in the last 12 months', items };
}

function sliceHistoryChain(ctx) {
  const hot = hotspots(ctx);
  if (!hot) return null;
  const items = [];
  for (const h of hot.slice(0, 3)) {
    const out = safeGit(ctx, ['log', '--follow', '--numstat', '--date=short', '-n', '12',
      '--format=@@%h%x09%ad%x09%s', '--', h.file]);
    if (!out) continue;
    for (const c of parseCommits(out)) {
      items.push(item(h.file, `${c.hash} ${c.date} ${clip(c.subject, 100)} (+${c.added} -${c.deleted}) [${h.file}]`));
    }
  }
  return { id: 'history-chain', title: 'History chains: how the top hotspot files changed', items };
}

const FIX_RE = /^(revert|fix|hotfix|bug)|\bfix(es|ed)?\b|\brevert/i;
const REVERT_RE = /^revert|\brevert/i;

function sliceFixChains(ctx) {
  const out = safeGit(ctx, ['log', '-n', '5000', '--name-only', '--relative', '--date=short', '--format=@@%h%x09%ad%x09%s']);
  if (out === null) return null;
  const fixes = parseCommits(out).filter((c) => FIX_RE.test(c.subject));
  const byFile = new Map();
  for (const c of fixes) {
    for (const f of c.files) if (ctx.scopeSet.has(f)) byFile.set(f, [...(byFile.get(f) || []), c]);
  }
  const items = [...byFile].filter(([, cs]) => cs.length >= 2)
    .sort((a, b) => b[1].length - a[1].length || a[0].localeCompare(b[0]))
    .map(([f, cs]) => item(f, [`${f}: ${cs.length} fix commits`,
      ...cs.slice(0, 6).map((c) => `  ${c.hash} ${c.date} ${clip(c.subject, 90)}`)].join('\n')));
  for (const c of fixes.filter((x) => REVERT_RE.test(x.subject))) {
    if (ctx.focus && !c.files.some((f) => ctx.scopeSet.has(f))) continue;
    items.push(item(c.files.find((f) => ctx.scopeSet.has(f)) || null, `${c.hash} ${c.date} ${clip(c.subject, 100)}`));
  }
  return { id: 'fix-chains', title: 'Fix chains: files fixed repeatedly, and reverts', items };
}

const WORKAROUND_RE = new RegExp([
  String.raw`\|\|\s*true`, String.raw`2>\/dev\/null`, String.raw`catch\s*\(\w*\)\s*\{\s*\}`,
  String.raw`except\s*:\s*pass`, String.raw`except Exception:\s*pass`, String.raw`\.unwrap_or_default\(\)`,
  String.raw`\.ok\(\);`, 'workaround', String.raw`\bfor now\b`, 'temporary', String.raw`\bhack\b`,
  String.raw`\blegacy\b`, "don'?t touch", 'do not touch', 'kludge', String.raw`\bXXX\b`].join('|'), 'i');
const GOTCHA_RE = /gotcha|troubleshoot|known issue|caveat|faq/i;

function scanLines(ctx, files, re, fmt) {
  const items = [];
  for (const f of files) {
    ctx.lines(f).forEach((l, i) => {
      if (l.length <= 400 && re.test(l)) items.push(item(f, fmt(f, i + 1, l)));
    });
  }
  return items;
}

function sliceWorkarounds(ctx) {
  const items = scanLines(ctx, ctx.scope.filter((f) => !isMd(f)), WORKAROUND_RE,
    (f, n, l) => `${f}:${n}: ${clip(l)}`);
  for (const f of ctx.scope.filter(isDoc)) {
    const lines = ctx.lines(f);
    for (const s of sections(lines, GOTCHA_RE)) {
      const body = [];
      for (let i = s.idx; i < s.end && body.length < 6; i++) {
        if (lines[i].trim()) body.push(`${f}:${i + 1}: ${clip(lines[i])}`);
      }
      items.push(item(f, body.join('\n  ')));
    }
  }
  return { id: 'workarounds', title: 'Workarounds, swallowed errors and documented gotchas', items };
}

function blameDates(ctx, file) {
  const out = safeGit(ctx, ['blame', '--porcelain', '--', file]);
  if (out === null) return null;
  const times = new Map();
  const lineSha = new Map();
  let sha = null;
  for (const l of out.split('\n')) {
    const h = /^([0-9a-f]{40}) \d+ (\d+)/.exec(l);
    if (h) { sha = h[1]; lineSha.set(Number(h[2]), sha); } else if (sha && l.startsWith('author-time ')) {
      times.set(sha, Number(l.slice(12)));
    }
  }
  const dates = new Map();
  for (const [n, s] of lineSha) {
    if (times.has(s)) dates.set(n, new Date(times.get(s) * 1000).toISOString().slice(0, 10));
  }
  return dates;
}

function sliceTodoAge(ctx) {
  const hits = [];
  for (const f of ctx.scope) {
    ctx.lines(f).forEach((l, i) => {
      if (l.length <= 400 && /\b(TODO|FIXME|HACK|BUG)\b/.test(l)) hits.push({ file: f, n: i + 1, text: clip(l) });
    });
  }
  const dateCache = new Map();
  const dated = hits.map((h) => {
    if (!ctx.git) return { ...h, date: null };
    if (!dateCache.has(h.file)) dateCache.set(h.file, blameDates(ctx, h.file));
    const d = dateCache.get(h.file);
    return { ...h, date: d ? d.get(h.n) || '????-??-??' : '????-??-??' };
  });
  dated.sort((a, b) => (a.date || 'z').localeCompare(b.date || 'z') || a.file.localeCompare(b.file) || a.n - b.n);
  const items = dated.map((h) => item(h.file, `${h.file}:${h.n}: ${h.date ? `[${h.date}] ` : ''}${h.text}`));
  return { id: 'todo-age', title: 'TODO / FIXME / HACK / BUG markers, oldest first', items };
}

const SETUP_RE = /install|setup|usage|quick ?start|getting started|run|develop/i;

function readmeLines(ctx) {
  const items = [];
  for (const f of ctx.scope.filter((x) => /^README[^/]*$/i.test(x) && isMd(x))) {
    const lines = ctx.lines(f);
    for (const s of sections(lines, SETUP_RE)) {
      for (let i = s.idx; i < s.end; i++) if (lines[i].trim()) items.push(item(f, `${f}:${i + 1}: ${clip(lines[i])}`));
    }
  }
  return items.slice(0, 60);
}

function firstRecipeLine(lines, from) {
  for (let i = from; i < lines.length; i++) {
    if (/^[ \t]+\S/.test(lines[i])) return lines[i].trim().replace(/^[@-]+/, '');
    if (/^\S/.test(lines[i])) return null;
  }
  return null;
}

function makeTargets(ctx, f) {
  const lines = ctx.lines(f);
  const out = [];
  lines.forEach((l, i) => {
    const m = /^([A-Za-z_][\w.-]*)[^:=\n]*:(?![=:])/.exec(l);
    if (m) out.push(item(f, `${f}: ${m[1]} -> ${clip(firstRecipeLine(lines, i + 1) || l.split(':').slice(1).join(':') || '(deps only)', 100)}`));
  });
  return out;
}

function taskfileTargets(ctx, f) {
  const lines = ctx.lines(f);
  const out = [];
  let inTasks = false;
  lines.forEach((l, i) => {
    if (/^tasks:\s*$/.test(l)) inTasks = true;
    else if (/^\S/.test(l)) inTasks = false;
    const m = inTasks && /^ {2}([\w:-]+):\s*$/.exec(l);
    if (!m) return;
    const cmd = lines.slice(i + 1).find((x) => /^\s+(- |cmd:)/.test(x));
    out.push(item(f, `${f}: ${m[1]} -> ${clip(cmd ? cmd.replace(/^\s+(- |cmd:\s*)/, '') : '(no cmds)', 100)}`));
  });
  return out;
}

function scriptTargets(ctx) {
  const items = [];
  if (ctx.scopeSet.has('package.json')) {
    try {
      const pkg = JSON.parse(ctx.text('package.json'));
      for (const [k, v] of Object.entries(pkg.scripts || {})) items.push(item('package.json', `package.json: ${k} -> ${clip(String(v), 100)}`));
    } catch (e) { note(`package.json is not valid JSON: ${e.message}`); }
  }
  for (const f of ctx.scope.filter((x) => /^(makefile|gnumakefile|justfile)$/i.test(x))) items.push(...makeTargets(ctx, f));
  for (const f of ctx.scope.filter((x) => /^taskfile\.ya?ml$/i.test(x))) items.push(...taskfileTargets(ctx, f));
  return items;
}

function sliceFirstTen(ctx) {
  return { id: 'first-ten-minutes', title: 'First ten minutes: install, run, scripts',
    items: [...readmeLines(ctx), ...scriptTargets(ctx)] };
}

// docs-vs-code

function docTokens(ctx, f) {
  const toks = [];
  let fence = false;
  ctx.lines(f).forEach((l, i) => {
    if (/^\s*(```|~~~)/.test(l)) { fence = !fence; return; }
    if (fence) return;
    for (const m of l.matchAll(/`([^`\n]+)`/g)) toks.push({ tok: m[1].trim(), n: i + 1 });
  });
  return toks;
}

function pathToken(tok) {
  if (!/^[\w.\-/@]+$/.test(tok) || tok.startsWith('/') || tok.startsWith('..') || tok.includes('://')) return null;
  const clean = tok.replace(/^\.\//, '');
  if (clean.endsWith('/')) return clean.length > 1 ? clean : null;
  const e = path.extname(clean).slice(1).toLowerCase();
  return PATH_EXTS.has(e) ? clean : null;
}

function pathExists(ctx, doc, p) {
  const bare = p.replace(/\/$/, '');
  if (fs.existsSync(path.join(ctx.repo, bare)) || fs.existsSync(path.join(ctx.repo, path.dirname(doc), bare))) return true;
  return ctx.files.some((f) => f === bare || f.endsWith(`/${bare}`));
}

function docIssues(ctx, f, srcCorpus) {
  const out = [];
  const seen = new Set();
  const push = (n, key, text) => { if (!seen.has(key)) { seen.add(key); out.push(item(f, `${f}:${n}: ${text}`)); } };
  for (const { tok, n } of docTokens(ctx, f)) {
    const p = pathToken(tok);
    if (p && !pathExists(ctx, f, p)) push(n, `p${p}`, `mentions path ${p}, not found in repo`);
    for (const m of tok.matchAll(/--[a-z][\w-]+/g)) {
      if (!wordRe(m[0]).test(srcCorpus)) push(n, `f${m[0]}`, `mentions ${m[0]}, not found in source`);
    }
    const env = /^([A-Z][A-Z0-9_]{3,})(?:=.*)?$/.exec(tok);
    if (env && env[1].includes('_') && !wordRe(env[1]).test(srcCorpus)) push(n, `e${env[1]}`, `mentions ${env[1]}, not found in source`);
  }
  return out;
}

function undocumentedFlags(ctx, mdCorpus) {
  const out = [];
  const seen = new Set();
  for (const f of ctx.scope.filter((x) => FLAG_EXTS.has(ext(x)))) {
    ctx.lines(f).forEach((l, i) => {
      for (const m of l.matchAll(/["'`](--[a-z][\w-]+)["'`]/g)) {
        if (seen.has(m[1]) || wordRe(m[1]).test(mdCorpus)) continue;
        seen.add(m[1]);
        out.push(item(f, `${f}:${i + 1}: defines ${m[1]}, no doc mentions it`));
      }
    });
  }
  return out;
}

function sliceDocsVsCode(ctx) {
  const srcCorpus = corpus(ctx, (f) => !isMd(f));
  const mdCorpus = corpus(ctx, isMd);
  const items = [];
  for (const f of ctx.scope.filter(isDoc)) items.push(...docIssues(ctx, f, srcCorpus));
  items.push(...undocumentedFlags(ctx, mdCorpus));
  return { id: 'docs-vs-code', title: 'Docs vs code: claims that do not match', items: items.slice(0, 40) };
}

// env and config

const ENV_RES = [
  /process\.env\.([A-Za-z_]\w*)/g,
  /process\.env\[\s*['"`]([A-Za-z_]\w*)['"`]\s*\]/g,
  /os\.environ(?:\.get)?\s*[[(]\s*['"](\w+)['"]/g,
  /os\.getenv\(\s*['"](\w+)['"]/g,
  /(?:std::)?env::var(?:_os)?\(\s*"(\w+)"/g,
  /Deno\.env\.get\(\s*['"](\w+)['"]/g,
  /import\.meta\.env\.([A-Za-z_]\w*)/g,
];
const MANIFEST_NAMES = new Set(['package.json', 'Cargo.toml', 'pyproject.toml']);

function envReads(ctx) {
  const reads = [];
  for (const f of ctx.scope.filter((x) => !isMd(x))) {
    ctx.lines(f).forEach((l, i) => {
      if (l.length > 400) return;
      for (const re of ENV_RES) for (const m of l.matchAll(re)) reads.push({ f, n: i + 1, name: m[1] });
    });
  }
  return reads;
}

function sliceEnvConfig(ctx) {
  const docs = corpus(ctx, (f) => isMd(f) || /(^|\/)\.env\.example$/.test(f));
  const reads = envReads(ctx).map((r) => ({ ...r, documented: wordRe(r.name).test(docs) }));
  reads.sort((a, b) => Number(a.documented) - Number(b.documented) || a.f.localeCompare(b.f) || a.n - b.n);
  const items = reads.map((r) => item(r.f, `${r.f}:${r.n}: reads ${r.name} (${r.documented ? 'documented' : 'undocumented'})`));
  const cfg = ctx.scope.filter((f) => !f.includes('/') && !MANIFEST_NAMES.has(f)
    && (/\.(toml|ya?ml|json)$/i.test(f) || f.startsWith('.env.example')));
  items.push(...cfg.map((f) => item(f, `${f}: top-level config file`)));
  return { id: 'env-and-config', title: 'Environment variables and config files', items };
}

// test gaps

const SKIP_RE = /\.skip\(|\bit\.only|\.only\(|@pytest\.mark\.skip|xfail|#\[ignore\]|test\.todo/;

function sliceTestGaps(ctx) {
  const tests = ctx.files.filter(isTest);
  const sources = ctx.scope.filter((f) => isCode(f) && !isTest(f) && !/\.config\./.test(f));
  const lineCount = (f) => ctx.lines(f).length;
  if (tests.length === 0) {
    const big = [...sources].sort((a, b) => lineCount(b) - lineCount(a)).slice(0, 5);
    return { id: 'test-gaps', title: 'Test gaps', items: [item(null, 'no test files found'),
      ...big.map((f) => item(f, `${f}: ${lineCount(f)} lines, one of the biggest source files, no tests`))] };
  }
  const names = tests.map((t) => path.basename(t).toLowerCase());
  const uncovered = sources.filter((f) => {
    const stem = path.basename(f, path.extname(f)).toLowerCase();
    return !names.some((n) => n.includes(stem)) && !ctx.text(f).includes('#[cfg(test)]');
  }).sort((a, b) => lineCount(b) - lineCount(a));
  const items = [item(null, `tests: ${tests.length} test files, ${sources.length} source files, ${uncovered.length} without a same-named test`)];
  items.push(...uncovered.map((f) => item(f, `${f}: ${lineCount(f)} lines, no test file named for it`)));
  items.push(...scanLines(ctx, ctx.files.filter(isCode), SKIP_RE, (f, n, l) => `${f}:${n}: ${clip(l)}`));
  return { id: 'test-gaps', title: 'Test gaps: untested files and skipped tests', items };
}

// unused surface

function identIndex(ctx) {
  const idx = new Map();
  for (const f of ctx.files) {
    for (const m of ctx.text(f).matchAll(/[A-Za-z_]\w*/g)) {
      if (!idx.has(m[0])) idx.set(m[0], new Set());
      idx.get(m[0]).add(f);
    }
  }
  return idx;
}

function unusedDeps(ctx) {
  if (!ctx.scopeSet.has('package.json')) return [];
  let pkg;
  try { pkg = JSON.parse(ctx.text('package.json')); } catch (e) { note(`package.json is not valid JSON: ${e.message}`); return []; }
  const code = corpus(ctx, (f) => isCode(f));
  const lines = ctx.lines('package.json');
  return Object.keys(pkg.dependencies || {}).filter((d) => !d.startsWith('@types/') && !code.includes(d)).map((d) => {
    const n = lines.findIndex((l) => l.includes(`"${d}"`)) + 1;
    return item('package.json', `package.json:${n}: dependency ${d} never appears in source`);
  });
}

const EXPORT_RES = {
  js: /^export\s+(?:async\s+)?(?:function\*?|const|let|class)\s+(\w+)/,
  rs: /^pub(?:\([a-z]+\))?\s+(?:async\s+)?fn\s+(\w+)/,
  py: /^(?:async\s+)?def\s+([A-Za-z]\w*)/,
};

function exportRe(rel) {
  const e = ext(rel);
  if (['js', 'mjs', 'cjs', 'ts', 'tsx', 'jsx'].includes(e)) return EXPORT_RES.js;
  return EXPORT_RES[e] || null;
}

function unusedExports(ctx) {
  const idx = identIndex(ctx);
  const out = [];
  for (const f of ctx.scope.filter((x) => isCode(x) && !isTest(x))) {
    const re = exportRe(f);
    if (!re) continue;
    ctx.lines(f).forEach((l, i) => {
      const m = re.exec(l);
      if (!m || m[1] === 'main' || m[1].startsWith('test_')) return;
      if ([...(idx.get(m[1]) || [])].every((o) => o === f)) out.push(item(f, `${f}:${i + 1}: exports ${m[1]}, no other file mentions it`));
    });
  }
  return out;
}

function sliceUnusedSurface(ctx) {
  const items = [...unusedDeps(ctx), ...unusedExports(ctx)].slice(0, 30);
  return { id: 'unused-surface', title: 'Unused surface: dependencies and exports nothing uses', items };
}

// big files

function maxDepth(lines) {
  const widths = lines.filter((l) => l.trim()).map((l) => (/^[ \t]*/.exec(l)[0].replace(/\t/g, '    ')).length);
  const nonzero = widths.filter((w) => w > 0);
  const unit = nonzero.length ? Math.min(...nonzero) : 4;
  return Math.floor(Math.max(0, ...widths) / (unit > 8 ? 4 : unit));
}

function sliceBigFiles(ctx) {
  const src = ctx.scope.filter((f) => isCode(f));
  const items = src.map((f) => ({ f, lines: ctx.lines(f) })).sort((a, b) => b.lines.length - a.lines.length || a.f.localeCompare(b.f))
    .slice(0, 8).map(({ f, lines }) => {
      const fns = (ctx.text(f).match(/function |=>|fn |def |func /g) || []).length;
      return item(f, `${f}: ${lines.length} lines, ${fns} functions, max indent depth ${maxDepth(lines)}`);
    });
  return { id: 'big-files', title: 'Big files: the largest source files', items };
}

// outline and whole-source

const GENERATED_RE = /\.(generated|gen)\.|\.d\.ts$|_pb2?\.py$|\.pb\.go$|(^|\/)generated\//i;
const WHOLE_SOURCE_MAX = 1500;
const WHOLE_SOURCE_CAP = 600;
const WHOLE_MANIFESTS = new Set(['package.json', 'manifest.json', 'Cargo.toml', 'pyproject.toml']);
const JS_EXTS = ['js', 'mjs', 'cjs', 'ts', 'tsx', 'jsx'];
const OUTLINE_RES = {
  js: [/^\s*(?:export\s+)?(?:default\s+)?(?:async\s+)?function\b/,
    /^\s*(?:export\s+)?(?:const|let|var)\s+\w+\s*(?::[^=]+)?=\s*(?:async\s+)?(?:\([^)]*\)|\w+)\s*(?::[^=]+)?=>/,
    /^\s*(?:export\s+)?(?:const|let|var)\s+\w+\s*=\s*(?:async\s+)?function\b/,
    /^\s*(?:export\s+)?(?:default\s+)?(?:abstract\s+)?class\s+\w+/, /^\s*export\s+/],
  rs: [/^\s*(?:pub(?:\([a-z]+\))?\s+)?(?:async\s+)?(?:unsafe\s+)?(?:fn|struct|enum|trait|impl|mod)\b/, /^\s*#\[command/],
  py: [/^\s*(?:async\s+)?def\s+\w+/, /^\s*class\s+\w+/],
  go: [/^func\s/, /^type\s+\w+/],
  sh: [/^\s*(?:function\s+)?[\w:-]+\s*\(\)\s*\{?/, /^\s*function\s+[\w:-]+/],
};

function outlineRes(rel) {
  const e = ext(rel);
  if (JS_EXTS.includes(e)) return OUTLINE_RES.js;
  return OUTLINE_RES[e] || null;
}

function clapVariants(lines, out) {
  // lines of enums deriving clap Subcommand: each variant is a command
  lines.forEach((l, i) => {
    if (!/^\s*#\[derive\([^)]*\bSubcommand\b/.test(l)) return;
    let j = i + 1;
    while (j < lines.length && !/\benum\b/.test(lines[j])) j++;
    const indent = /^\s*/.exec(lines[j] || '')[0].length;
    for (let k = j + 1; k < lines.length; k++) {
      const cur = /^\s*/.exec(lines[k])[0].length;
      if (/^\s*\}/.test(lines[k]) && cur <= indent) break;
      if (cur === indent + 4 && /^\s*[A-Z]\w*\s*[,{(]?/.test(lines[k]) && !/^\s*#/.test(lines[k])) out.set(k, true);
    }
  });
}

function outlineFile(ctx, f) {
  const res = outlineRes(f);
  if (!res) return [];
  const lines = ctx.lines(f);
  const extra = new Map();
  if (ext(f) === 'rs') clapVariants(lines, extra);
  const out = [];
  lines.forEach((l, i) => {
    if (l.length > 400) return;
    if (extra.has(i) || res.some((re) => re.test(l))) out.push(item(f, `${f}:${i + 1}: ${clip(l.replace(/\s*\{\s*$/, ''))}`));
  });
  return out;
}

function sourceFiles(ctx) {
  return ctx.scope.filter((f) => isCode(f) && !isTest(f) && !GENERATED_RE.test(f)
    && !/@generated|DO NOT EDIT/.test(ctx.text(f).slice(0, 400)));
}

function sliceOutline(ctx) {
  const items = sourceFiles(ctx).flatMap((f) => outlineFile(ctx, f));
  return { id: 'outline', title: 'Outline: functions, types and commands declared in the source', items };
}

function sliceWholeSource(ctx) {
  const src = sourceFiles(ctx);
  const total = src.reduce((s, f) => s + ctx.lines(f).length, 0);
  if (!src.length || total > WHOLE_SOURCE_MAX) return null;
  const biggest = [...src].sort((a, b) => ctx.lines(b).length - ctx.lines(a).length || a.localeCompare(b));
  const manifests = ctx.scope.filter((f) => WHOLE_MANIFESTS.has(path.basename(f)));
  const items = [...biggest, ...manifests].map((f) => item(f, ctx.lines(f)
    .map((l, i) => `${f}:${i + 1}| ${l.length > 400 ? `${l.slice(0, 400)}...` : l}`).join('\n')));
  return { id: 'whole-source', title: 'Whole source: every source file in full, biggest first',
    items, minItems: 1, strength: 0.6, lineCap: WHOLE_SOURCE_CAP };
}

const SLICES = [sliceHotspot, sliceHistoryChain, sliceFixChains, sliceWorkarounds, sliceTodoAge,
  sliceFirstTen, sliceDocsVsCode, sliceEnvConfig, sliceTestGaps, sliceUnusedSurface, sliceBigFiles,
  sliceOutline, sliceWholeSource];

// ---------- project card and tree ----------

function readmePara(ctx) {
  const f = ctx.files.find((x) => /^README[^/]*$/i.test(x) && isMd(x));
  if (!f) return [];
  const para = [];
  let fence = false;
  for (const l of ctx.lines(f)) {
    if (/^\s*(```|~~~)/.test(l)) { fence = !fence; continue; }
    const skip = fence || /^#/.test(l) || /^\s*(!?\[!?\[|!\[|<)/.test(l) || /^\s*[-=*_]{3,}\s*$/.test(l);
    if (!l.trim() || skip) { if (para.length) break; continue; }
    para.push(clip(l, 140));
    if (para.length === 3) break;
  }
  return para;
}

function manifestLine(ctx, f) {
  const base = path.basename(f);
  const t = ctx.text(f);
  if (base === 'package.json') {
    try {
      const p = JSON.parse(t);
      return `${f}: name ${p.name || '(none)'}; scripts ${Object.keys(p.scripts || {}).join(', ') || '(none)'}`;
    } catch { return `${f}: invalid JSON`; }
  }
  if (base === 'Cargo.toml') {
    const pkg = /\[package\][^[]*?\bname\s*=\s*"([^"]+)"/.exec(t);
    const bins = [...t.matchAll(/\[\[bin\]\][^[]*?\bname\s*=\s*"([^"]+)"/g)].map((m) => m[1]);
    return `${f}: package ${pkg ? pkg[1] : '(none)'}; bins ${bins.join(', ') || '(default)'}`;
  }
  if (base === 'pyproject.toml') {
    const m = /\[(?:project|tool\.poetry)\][^[]*?\bname\s*=\s*"([^"]+)"/.exec(t);
    return `${f}: name ${m ? m[1] : '(none)'}`;
  }
  const mod = /^module\s+(\S+)/m.exec(t);
  return `${f}: module ${mod ? mod[1] : '(none)'}`;
}

function gitCard(ctx) {
  const out = safeGit(ctx, ['log', '--date=short', '--format=%ad%x09%an']);
  const rows = out ? out.split('\n').filter(Boolean).map((l) => l.split('\t')) : [];
  if (!rows.length) return 'git: no git history';
  const dates = rows.map((r) => r[0]).sort();
  return `git: ${rows.length} commits, ${dates[0]} to ${dates[dates.length - 1]}, ${new Set(rows.map((r) => r[1])).size} authors`;
}

function topCounts(map, n) {
  return [...map].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0])).slice(0, n);
}

function projectCard(ctx) {
  const exts = new Map();
  const dirs = new Map();
  for (const f of ctx.files) {
    const e = path.extname(f);
    if (e) exts.set(e, (exts.get(e) || 0) + 1);
    const top = f.includes('/') ? f.split('/')[0] : '(root)';
    dirs.set(top, (dirs.get(top) || 0) + 1);
  }
  const manifests = ctx.files.filter((f) => f.split('/').length <= 2
    && ['package.json', 'Cargo.toml', 'pyproject.toml', 'go.mod'].includes(path.basename(f)));
  const lines = [`# ${path.basename(ctx.repo)}`, ...readmePara(ctx),
    `Languages: ${topCounts(exts, 4).map(([k, v]) => `${k} ${v}`).join(', ') || '(none)'}`,
    `Top dirs: ${topCounts(dirs, 8).map(([k, v]) => `${k} ${v}`).join(', ') || '(none)'}`,
    'Manifests:', ...(manifests.length ? manifests.slice(0, 6).map((f) => `- ${manifestLine(ctx, f)}`) : ['- none found']),
    gitCard(ctx)];
  return `${lines.slice(0, 20).join('\n')}\n`;
}

function treeText(ctx) {
  const shown = ctx.files.slice(0, TREE_MAX);
  const extra = ctx.files.length - shown.length;
  return `${shown.join('\n')}${extra > 0 ? `\n... ${extra} more files not shown (truncated at ${TREE_MAX})` : ''}\n`;
}

// ---------- packets ----------

function renderLineCapped(slice) {
  const all = slice.items.flatMap((i) => i.text.split('\n'));
  const budget = slice.lineCap - 2 - (all.length > slice.lineCap - 2 ? 1 : 0);
  const body = [`# ${slice.title}`, '', ...all.slice(0, budget)];
  if (all.length > budget) body.push(`... ${all.length - budget} more lines not shown`);
  return `${body.join('\n')}\n`;
}

function renderPacket(slice, maxLines) {
  if (slice.lineCap) return renderLineCapped(slice);
  const blocks = slice.items.map((i) => i.text);
  const total = blocks.reduce((s, b) => s + b.split('\n').length, 0);
  const budget = maxLines - 2 - (total > maxLines - 2 ? 1 : 0);
  const kept = [];
  let used = 0;
  for (const b of blocks) {
    const n = b.split('\n').length;
    if (used + n > budget) break;
    kept.push(b);
    used += n;
  }
  const more = blocks.length - kept.length;
  const body = [`# ${slice.title}`, '', ...kept];
  if (more > 0) body.push(`... ${more} more items not shown`);
  return `${body.join('\n')}\n`;
}

function primaryFiles(items) {
  const counts = new Map();
  for (const i of items) if (i.file) counts.set(i.file, (counts.get(i.file) || 0) + 1);
  return [...counts].sort((a, b) => b[1] - a[1]).slice(0, 8).map(([f]) => f);
}

function writeOutputs(ctx, opts, slices) {
  const out = path.resolve(opts.out);
  const sdir = path.join(out, 'slices');
  fs.mkdirSync(sdir, { recursive: true });
  for (const f of fs.readdirSync(sdir)) if (f.endsWith('.md')) fs.rmSync(path.join(sdir, f));
  fs.writeFileSync(path.join(out, 'project.md'), projectCard(ctx));
  fs.writeFileSync(path.join(out, 'tree.txt'), treeText(ctx));
  const index = slices.map((s) => {
    fs.writeFileSync(path.join(sdir, `${s.id}.md`), renderPacket(s, opts.maxLines));
    return { id: s.id, title: s.title, n_items: s.items.length, strength: s.strength ?? Math.round(Math.min(1, s.items.length / 15) * 100) / 100,
      primary_files: primaryFiles(s.items), packet: `slices/${s.id}.md` };
  }).sort((a, b) => b.strength - a.strength);
  fs.writeFileSync(path.join(out, 'slices.json'), `${JSON.stringify(index, null, 2)}\n`);
  return index;
}

// ---------- main ----------

function main(argv) {
  const opts = parseArgs(argv);
  if (opts.help) { process.stdout.write('usage: mine.mjs --repo <dir> --out <run-dir> [--focus <subpath>] [--max-lines 220]\n'); return 0; }
  const ctx = buildContext(opts);
  const slices = SLICES.map((fn) => fn(ctx)).filter((s) => s && s.items.length >= (s.minItems ?? 3));
  let index;
  try { index = writeOutputs(ctx, opts, slices); } catch (e) { throw new Fail(3, `cannot write output: ${e.message}`); }
  for (const s of index) process.stdout.write(`${s.id}\t${s.n_items}\t${s.strength}\n`);
  if (!index.length) { note('no slice reached 3 evidence items'); return 1; }
  return 0;
}

try {
  process.exitCode = main(process.argv.slice(2));
} catch (e) {
  if (e instanceof Fail) { note(e.message); process.exitCode = e.code; } else { note(`unexpected error: ${e.stack || e}`); process.exitCode = 3; }
}
