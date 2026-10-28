#!/usr/bin/env node
// recon.mjs - read-only evidence for "which layer or dependency has everyone stopped questioning".
// Prints evidence only; the agent reading it nominates the target. Node >= 20, stdlib only, no network,
// never writes into the repo.
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const MB = 1024 * 1024;
const FIX = /\b(fix(e[sd])?|bug|workaround|revert|again|still|retry|hack|hotfix|patch(ed)?|flaky|timeout|broken)\b/i;
const BOT = /dependabot|renovate|github-actions|\[bot\]/i;
const WORKAROUND = /\b(HACK|FIXME|XXX|KLUDGE)\b|workaround|for now|temporary|\|\| true|sleep\(|time\.sleep|setTimeout\([^)]*\d{4,}|\bretr(y|ies)\b/i;
const CODE_EXT = new Set('js,mjs,cjs,ts,tsx,jsx,py,rs,go,rb,java,kt,swift,c,cc,cpp,h,hpp,cs,php,sh,bash,zsh,lua,ex,exs,scala,dart,vue,svelte'.split(','));
const ECO = { js: 'npm', mjs: 'npm', cjs: 'npm', ts: 'npm', tsx: 'npm', jsx: 'npm', vue: 'npm', svelte: 'npm', py: 'python', rs: 'rust', go: 'go' };
const TEST_DIRS = new Set(['test', 'tests', '__tests__', 'spec', 'e2e']);
const HELP = `usage: node recon.mjs [--repo <path>] [--focus <subpath>] [--months <n>] [--json] [--help]
  --repo <path>      repository to inspect (default: cwd, resolved to the git toplevel)
  --focus <subpath>  restrict every section to paths under this subpath
  --months <n>       history window for churn and fix signals (default 12)
  --json             print one JSON object with the same data instead of text
  --help             print this help and exit 0
sections (evidence only; this tool never decides):
  preflight     shallow clone, commit count, months of history; WARN when thin
  directories   two-segment rollup: commits, fix_commits, fix_share, fix_months, added/deleted/net, loc. STALL = fix commits in
                >= 4 months while |net|/added < 0.2. Excludes lockfiles, docs, generated, data; tests -> test_commits; bots skipped
  files         top files by fix_commits       workarounds  HACK/FIXME/sleep/retry lines, per directory, oldest via blame
  dependencies  import_sites and node_modules size; HEAVY-NARROW = >= 10 MB, <= 3 sites (python import name = package name)
  large-files   tracked files over 5 MB; vendor/third_party/*.patch counts
`;

class Fail extends Error {}
const git = (top, args) => execFileSync('git', ['-C', top, '-c', 'core.quotepath=false', ...args], { encoding: 'utf8', maxBuffer: 1 << 30, stdio: ['ignore', 'pipe', 'pipe'] });

function parseArgs(argv) {
  const o = { repo: process.cwd(), focus: null, months: 12, json: false, help: false };
  const bare = { '--json': () => (o.json = true), '--help': () => (o.help = true) };
  const valued = { '--repo': (v) => (o.repo = path.resolve(v)), '--focus': (v) => (o.focus = v), '--months': (v) => (o.months = Number.parseInt(v, 10)) };
  for (let i = 0; i < argv.length; i++) {
    if (bare[argv[i]]) bare[argv[i]]();
    else if (valued[argv[i]] && i + 1 < argv.length) valued[argv[i]](argv[++i]);
    else throw new Fail(`recon: bad or incomplete argument ${argv[i]}. Run: node recon.mjs --help`);
  }
  if (!(o.months > 0)) throw new Fail('recon: --months must be a positive integer. Example: --months 12');
  return o;
}

function makeCtx(opts) {
  let top;
  try {
    top = git(opts.repo, ['rev-parse', '--show-toplevel']).trim();
  } catch (e) {
    if (e.code === 'ENOENT') throw new Fail('recon: git was not found on PATH. Install git, or name the target yourself.');
    throw new Fail(`recon: ${opts.repo} is not a git repository. Name the target yourself, or run recon inside a git checkout.`);
  }
  const focus = opts.focus ? path.relative(top, path.resolve(top, opts.focus)).split(path.sep).join('/') || null : null;
  return { top, focus, months: opts.months };
}

const inFocus = (ctx, p) => !ctx.focus || p === ctx.focus || p.startsWith(`${ctx.focus}/`);
const ext = (p) => path.extname(p).slice(1).toLowerCase();
const rollup = (p) => path.posix.dirname(p).split('/').filter((s) => s !== '.').slice(0, 2).join('/') || '.';
const get = (map, key, make) => { if (!map.has(key)) map.set(key, make()); return map.get(key); };
const round = (n, places) => Math.round(n * 10 ** places) / 10 ** places;
function isExcluded(p) {
  const base = path.posix.basename(p);
  return /\.lock$|^(package-lock\.json|pnpm-lock\.yaml|bun\.lockb|go\.sum)$/.test(base)
    || /\.(md|mdx|txt)$/.test(base) || /(^|\/)docs\//.test(p)
    || /(^|\/)(dist|build|out|node_modules|vendor|third_party)\//.test(p) || /\.(min\.js|snap|map)$/.test(base)
    || /\.(csv|tsv|parquet)$/.test(base) || /(^|\/)(data|fixtures)\/.*\.json$/.test(p);
}
function isTest(p) {
  const segs = p.split('/'), base = segs.pop();
  return segs.some((s) => TEST_DIRS.has(s)) || /\.test\.|_test\./.test(base) || /^test_.*\.py$/.test(base);
}
const resolveRename = (p) => p.replace(/^(.*)\{(.*) => (.*)\}(.*)$/, '$1$3$4').replace(/\/\//g, '/').replace(/^.* => /, '');

function preflight(ctx) {
  const shallow = git(ctx.top, ['rev-parse', '--is-shallow-repository']).trim() === 'true';
  const commits = Number.parseInt(git(ctx.top, ['rev-list', '--count', 'HEAD']).trim(), 10);
  const first = Math.min(...git(ctx.top, ['log', '--max-parents=0', '--format=%at']).trim().split('\n').map(Number));
  const months = round((Date.now() / 1000 - first) / (30.44 * 86400), 1);
  const why = [shallow && 'shallow clone', commits < 100 && `${commits} commits`, months < 6 && `${months} months`].filter(Boolean);
  return {
    shallow, commits, first_commit: new Date(first * 1000).toISOString().slice(0, 10), history_months: months,
    warning: why.length ? `WARN: thin history (${why.join(', ')}); churn and stall signals are weak` : null,
  };
}

function readHistory(ctx) {
  const out = git(ctx.top, ['log', `--since=${ctx.months}.months`, '--no-merges', '--numstat',
    '--format=%x1e%H%x1f%an%x1f%ae%x1f%ad%x1f%s', '--date=format:%Y-%m']);
  return out.split('\x1e').slice(1).map((rec) => {
    const [header, ...rest] = rec.split('\n');
    const h = header.split('\x1f');
    const files = rest.map((l) => l.match(/^(-|\d+)\t(-|\d+)\t(.+)$/)).filter(Boolean)
      .map((m) => ({ add: m[1] === '-' ? 0 : +m[1], del: m[2] === '-' ? 0 : +m[2], path: resolveRename(m[3]) }));
    return { name: h[1], email: h[2], month: h[3], subject: h.slice(4).join('\x1f'), files };
  });
}

const blank = () => ({ commits: 0, commits_3m: 0, fix_commits: 0, test_commits: 0, added: 0, deleted: 0, months: new Set() });

function aggregate(ctx, commits) {
  const dirs = new Map(), files = new Map(), last = new Map(), skipped = { bots: 0, mechanical: 0 };
  const n = new Date(), cut3 = new Date(Date.UTC(n.getUTCFullYear(), n.getUTCMonth() - 2, 1)).toISOString().slice(0, 7);
  for (const c of commits) {
    if (BOT.test(`${c.name} ${c.email}`)) { skipped.bots++; continue; }
    if (c.files.length > 50) { skipped.mechanical++; continue; }
    const fix = FIX.test(c.subject), main = new Set(), tests = new Set(), touched = new Set();
    for (const f of c.files) {
      if (!inFocus(ctx, f.path) || isExcluded(f.path)) continue;
      if (!(last.get(f.path) >= c.month)) last.set(f.path, c.month);
      const d = rollup(f.path);
      const e = get(dirs, d, blank);
      if (isTest(f.path)) { tests.add(d); continue; }
      e.added += f.add; e.deleted += f.del; main.add(d);
      touched.add(get(files, f.path, blank));
    }
    for (const e of [...[...main].map((d) => dirs.get(d)), ...touched]) {
      e.commits++;
      if (c.month >= cut3) e.commits_3m++;
      if (fix) { e.fix_commits++; e.months.add(c.month); }
    }
    for (const d of tests) dirs.get(d).test_commits++;
  }
  return { dirs, files, last, skipped };
}

function loadStore(ctx) {
  const store = new Map();
  for (const p of git(ctx.top, ['ls-files', '-z']).split('\0').filter((x) => x && inFocus(ctx, x))) {
    try {
      const abs = path.join(ctx.top, p), st = fs.lstatSync(abs);
      if (!st.isFile()) continue;
      const rec = { size: st.size, lines: null, text: null };
      store.set(p, rec);
      if (isExcluded(p) || st.size > 5 * MB) continue;
      const buf = fs.readFileSync(abs);
      if (buf.subarray(0, 8000).includes(0)) continue;
      const t = buf.toString('utf8');
      rec.lines = t === '' ? 0 : t.split('\n').length - (t.endsWith('\n') ? 1 : 0);
      if (CODE_EXT.has(ext(p)) && st.size <= MB) rec.text = t;
    } catch { /* unreadable or vanished file: leave unmeasured */ }
  }
  return store;
}

const byFix = (a, b) => b.fix_commits - a.fix_commits || b.commits - a.commits;

function directories(agg, store) {
  const loc = new Map();
  for (const [p, r] of store) if (r.lines) loc.set(rollup(p), (loc.get(rollup(p)) ?? 0) + r.lines);
  const rows = [...agg.dirs].map(([dir, e]) => {
    const net = e.added - e.deleted;
    return {
      dir, commits: e.commits, commits_3m: e.commits_3m, fix_commits: e.fix_commits, test_commits: e.test_commits,
      fix_share: e.commits ? round(e.fix_commits / e.commits, 2) : 0, fix_months: e.months.size,
      added: e.added, deleted: e.deleted, net, loc: loc.get(dir) ?? 0,
      stall: e.months.size >= 4 && e.added > 0 && Math.abs(net) / e.added < 0.2,
    };
  }).sort(byFix);
  return { skipped: { total: agg.skipped.bots + agg.skipped.mechanical, ...agg.skipped }, total_directories: rows.length, rows: rows.slice(0, 15) };
}

function blameTime(top, file, line) {
  try { return Number(git(top, ['blame', '--porcelain', '-L', `${line},${line}`, '--', file]).match(/^author-time (\d+)$/m)?.[1]) || null; } catch { return null; }
}

function workarounds(ctx, store, last) {
  const CAP = 400, hits = [];
  let capped = false;
  scan: for (const [p, r] of [...store].sort((a, b) => (a[0] < b[0] ? -1 : 1))) {
    if (!r.text) continue;
    const lines = r.text.split('\n');
    for (let i = 0; i < lines.length; i++) {
      if (lines[i].length > 2000 || !WORKAROUND.test(lines[i])) continue;
      if (hits.length >= CAP) { capped = true; break scan; }
      hits.push({ path: p, line: i + 1, text: lines[i].trim().slice(0, 120) });
    }
  }
  const perDir = new Map();
  for (const h of hits) perDir.set(rollup(h.path), (perDir.get(rollup(h.path)) ?? 0) + 1);
  const age = (h) => last.get(h.path) ?? '';
  const candidates = [...hits].sort((a, b) => age(a).localeCompare(age(b)) || a.path.localeCompare(b.path) || a.line - b.line).slice(0, 60);
  const now = Date.now() / 1000;
  const aged = candidates.map((h) => ({ h, t: blameTime(ctx.top, h.path, h.line) })).filter((x) => x.t !== null)
    .map(({ h, t }) => ({ age_days: Math.floor((now - t) / 86400), ...h })).sort((a, b) => b.age_days - a.age_days);
  return {
    total: hits.length, capped, cap: CAP, distinct_directories: perDir.size, blamed: candidates.length,
    by_directory: [...perDir].map(([dir, n]) => ({ dir, hits: n })).sort((a, b) => b.hits - a.hits).slice(0, 10),
    oldest: aged.slice(0, 15),
  };
}

const names = (eco, list, dev = false) => list.map((name) => ({ name, eco, dev }));
const section = (t, h) => t.match(new RegExp(`^\\[${h.replace(/\./g, '\\.')}\\][ \\t]*\\n([\\s\\S]*?)(?=^\\[|(?![\\s\\S]))`, 'm'))?.[1] ?? '';
const keys = (t, header) => [...section(t, header).matchAll(/^\s*([A-Za-z0-9_.-]+)\s*=/gm)].map((k) => k[1]);
const pyName = (s) => s.match(/^\s*([A-Za-z0-9][A-Za-z0-9._-]*)/)?.[1];

const PARSERS = {
  'package.json': (t) => {
    const j = JSON.parse(t);
    return [...names('npm', Object.keys(j.dependencies ?? {})), ...names('npm', Object.keys(j.devDependencies ?? {}), true)];
  },
  'pyproject.toml': (t) => {
    const arr = section(t, 'project').match(/^\s*dependencies\s*=\s*\[((?:\s*(?:"[^"]*"|'[^']*')\s*,?|\s*#[^\n]*)*)\s*\]/m);
    const listed = arr ? [...arr[1].matchAll(/"([^"]*)"|'([^']*)'/g)].map((m) => pyName(m[1] ?? m[2])) : [];
    return names('python', [...listed, ...keys(t, 'tool.poetry.dependencies')].filter((n) => n && n !== 'python'));
  },
  'requirements.txt': (t) => names('python', t.split('\n').map((l) => l.replace(/#.*$/, '').trim()).filter((l) => l && !l.startsWith('-')).map(pyName).filter(Boolean)),
  'Cargo.toml': (t) => names('rust', keys(t, 'dependencies')),
  'go.mod': (t) => names('go', [...t.matchAll(/^\s*(?:require\s+)?([^\s(]+)\s+v\d\S*(.*)$/gm)]
    .filter((m) => m[1] !== 'retract' && !m[2].includes('indirect')).map((m) => m[1])),
};

function readManifests(ctx) {
  const deps = new Map(), manifests = [];
  for (const dir of ctx.focus ? ['', ctx.focus] : ['']) {
    for (const [file, parse] of Object.entries(PARSERS)) {
      const rel = path.posix.join(dir, file);
      let text;
      try { text = fs.readFileSync(path.join(ctx.top, rel), 'utf8'); } catch { continue; }
      manifests.push(rel);
      for (const d of parse(text)) get(deps, `${d.eco}:${d.name}`, () => ({ ...d, dir }));
    }
  }
  return { deps: [...deps.values()], manifests };
}

const JS_IMPORT = /(?:\bfrom\s*|\brequire\(\s*|\bimport\(\s*|\bimport\s*)(['"])([^'"\n]+)\1/g;
const PY_IMPORT = /^[ \t]*(?:from[ \t]+([A-Za-z_][\w.]*)[ \t]+import\b|import[ \t]+([^\n#]+))/gm;
const depKey = (d) => (d.eco === 'python' ? d.name.toLowerCase().replace(/-/g, '_') : d.eco === 'rust' ? d.name.replace(/-/g, '_') : d.name);
const IMPORTERS = {
  npm: (t) => [...t.matchAll(JS_IMPORT)].filter((m) => !/^[./]/.test(m[2])).map((m) => m[2].split('/').slice(0, m[2].startsWith('@') ? 2 : 1).join('/')),
  python: (t) => [...t.matchAll(PY_IMPORT)].flatMap((m) => (m[1] ? [m[1]] : m[2].split(','))).map((x) => x.trim().split(/\s+as\s+/)[0].split('.')[0].toLowerCase()),
  rust: (t) => [...t.matchAll(/\b([A-Za-z_]\w*)::|\buse\s+([A-Za-z_]\w*)/g)].map((m) => m[1] ?? m[2]),
  go: (t, mods) => [...t.matchAll(/"([^"\s]+)"/g)].flatMap((m) => mods.filter((x) => m[1] === x || m[1].startsWith(`${x}/`))),
};

function measureNpm(ctx, dep) {
  const root = [dep.dir, ''].map((d) => path.join(ctx.top, d, 'node_modules', dep.name)).find((p) => fs.existsSync(p));
  if (!root) return { size_mb: null, size_capped: false };
  let bytes = 0, n = 0;
  for (const stack = [root]; stack.length && n < 20000;) {
    const d = stack.pop();
    let ents = [];
    try { ents = fs.readdirSync(d, { withFileTypes: true }); } catch { /* unreadable dir */ }
    for (const e of ents) {
      if (e.isDirectory()) { stack.push(path.join(d, e.name)); continue; }
      n++;
      try { bytes += fs.lstatSync(path.join(d, e.name)).size; } catch { /* vanished file */ }
    }
  }
  return { size_mb: round(bytes / MB, 2), size_capped: n >= 20000 };
}

function dependencies(ctx, store) {
  const { deps, manifests } = readManifests(ctx);
  if (!manifests.length) throw new Error('no supported manifest (package.json, pyproject.toml, requirements.txt, Cargo.toml, go.mod) at the repo root or focus dir');
  const goMods = deps.filter((d) => d.eco === 'go').map((d) => d.name), sites = new Map();
  for (const [p, r] of store) {
    if (!r.text || !ECO[ext(p)]) continue;
    const eco = ECO[ext(p)];
    for (const k of new Set(IMPORTERS[eco](r.text, goMods))) sites.set(`${eco}:${k}`, (sites.get(`${eco}:${k}`) ?? 0) + 1);
  }
  const rows = deps.map((d) => {
    const import_sites = sites.get(`${d.eco}:${depKey(d)}`) ?? 0;
    const m = d.eco === 'npm' ? measureNpm(ctx, d) : { size_mb: null, size_capped: false };
    return { name: d.name, ecosystem: d.eco, dev: d.dev, import_sites, ...m, flag: m.size_mb >= 10 && import_sites <= 3 ? 'HEAVY-NARROW' : null };
  }).sort((a, b) => (b.flag ? 1 : 0) - (a.flag ? 1 : 0) || (b.size_mb ?? -1) - (a.size_mb ?? -1) || a.import_sites - b.import_sites);
  return { manifests, total: rows.length, rows: rows.slice(0, 20), unused: rows.filter((r) => r.import_sites === 0).map((r) => r.name).slice(0, 20) };
}

function largeFiles(store) {
  const paths = [...store.keys()], big = [...store].filter(([, r]) => r.size > 5 * MB).map(([p, r]) => ({ path: p, mb: round(r.size / MB, 1) }));
  return {
    large: big.sort((a, b) => b.mb - a.mb).slice(0, 20),
    vendor_files: paths.filter((p) => /(^|\/)(vendor|third_party)\//.test(p)).length, patch_files: paths.filter((p) => p.endsWith('.patch')).length,
  };
}

const fmt = (rows, cols) => {
  const w = cols.map((k) => Math.max(k.length, ...rows.map((r) => String(r[k] ?? '').length)));
  const row = (cells) => cells.map((c, i) => String(c).padEnd(w[i])).join('  ').trimEnd();
  return [row(cols), ...rows.map((r) => row(cols.map((k) => r[k] ?? '')))];
};
const RENDER = {
  preflight: (d) => [`shallow: ${d.shallow ? 'yes' : 'no'}`, `commits: ${d.commits}`, `first_commit: ${d.first_commit}`, `history_months: ${d.history_months}`,
    ...(d.warning ? [d.warning] : [])],
  directories: (d) => [`skipped: ${d.skipped.total} commits (bots ${d.skipped.bots}, mechanical ${d.skipped.mechanical})`,
    ...fmt(d.rows.map((r) => ({ ...r, flag: r.stall ? 'STALL' : '' })),
      'dir commits commits_3m fix_commits fix_share fix_months added deleted net loc test_commits flag'.split(' '))],
  files: (d) => fmt(d.rows, ['path', 'commits', 'fix_commits', 'loc']),
  workarounds: (d) => [`total hits: ${d.total}${d.capped ? ` (capped at ${d.cap}; more exist)` : ''}`, `distinct directories: ${d.distinct_directories}`,
    'hits per directory:', ...fmt(d.by_directory, ['dir', 'hits']).map((l) => `  ${l}`),
    `oldest (git blame on ${d.blamed} candidates):`, ...d.oldest.map((h) => `${h.age_days}d  ${h.path}:${h.line}  ${h.text}`)],
  dependencies: (d) => [`manifests: ${d.manifests.join(', ')} (${d.total} deps)`,
    ...fmt(d.rows.map((r) => ({ ...r, size: r.size_mb === null ? 'not measured' : `${r.size_capped ? '>=' : ''}${r.size_mb}MB`, dev: r.dev ? 'dev' : '', flag: r.flag ?? '' })),
      ['name', 'ecosystem', 'dev', 'import_sites', 'size', 'flag']),
    `unused: ${d.unused.join(', ') || '(none)'}`],
  'large-files': (d) => [`vendor/third_party files: ${d.vendor_files}`, `*.patch files: ${d.patch_files}`,
    ...(d.large.length ? d.large.map((f) => `${f.mb} MB  ${f.path}`) : ['no tracked file over 5 MB'])],
};

const attempt = (fn) => { try { return { v: fn() }; } catch (e) { return { e }; } };
const need = (r) => { if (r.e) throw r.e; return r.v; };

function collect(ctx) {
  const store = attempt(() => loadStore(ctx)), agg = attempt(() => aggregate(ctx, readHistory(ctx)));
  const sections = {
    preflight: () => preflight(ctx),
    directories: () => directories(need(agg), need(store)),
    files: () => ({ rows: [...need(agg).files].map(([p, e]) => ({ path: p, commits: e.commits, fix_commits: e.fix_commits, loc: need(store).get(p)?.lines ?? 0 })).sort(byFix).slice(0, 15) }),
    workarounds: () => workarounds(ctx, need(store), agg.v?.last ?? new Map()),
    dependencies: () => dependencies(ctx, need(store)),
    'large-files': () => largeFiles(need(store)),
  };
  const out = {};
  for (const [name, fn] of Object.entries(sections)) {
    const r = attempt(fn);
    out[name] = r.e ? { not_measured: r.e.stderr ? String(r.e.stderr).trim().split('\n')[0] : r.e.message } : r.v;
  }
  return out;
}

function renderText(ctx, sections) {
  const lines = [`recon: ${ctx.top}${ctx.focus ? ` (focus ${ctx.focus})` : ''}, last ${ctx.months} months`];
  for (const [name, data] of Object.entries(sections)) {
    lines.push('', `## ${name}`, ...(data.not_measured ? [`not measured: ${data.not_measured}`] : RENDER[name](data)));
  }
  return `${lines.join('\n')}\n`;
}

function main() {
  try {
    const opts = parseArgs(process.argv.slice(2));
    if (opts.help) { process.stdout.write(HELP); return; }
    const ctx = makeCtx(opts), sections = collect(ctx);
    process.stdout.write(opts.json
      ? `${JSON.stringify({ repo: ctx.top, focus: ctx.focus, months: ctx.months, ...sections }, null, 2)}\n`
      : renderText(ctx, sections));
  } catch (e) {
    if (!(e instanceof Fail)) throw e;
    process.stderr.write(`${e.message}\n`);
    process.exitCode = 2;
  }
}

main();
