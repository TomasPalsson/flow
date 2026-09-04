#!/usr/bin/env node
/**
 * version-audit.mjs — scan a repo for version references and check each
 * against the latest SAFE version (not just the latest).
 *
 * Covers, with ZERO local tooling beyond node18+/bun (uses fetch + optional `gh`):
 *   - GitHub Actions   (.github/workflows/*.yml)  -> GitHub releases/tags API
 *   - npm/bun deps     (package.json)             -> registry.npmjs.org
 *   - Python deps      (pyproject.toml)           -> pypi.org JSON API
 *   - Rust deps        (Cargo.toml)               -> crates.io API
 *   - Go deps          (go.mod)                   -> proxy.golang.org
 *   - EOL runtimes     (.nvmrc, engines.node, go directive, requires-python,
 *                       Dockerfile FROM, .tool-versions) -> endoflife.date
 *
 * Output: a prioritised findings table (markdown) or --json.
 * It NEVER edits files. It recommends; a human decides on majors.
 *
 * Usage:
 *   node version-audit.mjs [path] [--json] [--actions-only] [--deps-only]
 *                          [--runtimes-only] [--no-actions] [--concurrency N]
 *
 * Auth: set GH_TOKEN / GITHUB_TOKEN or be logged into `gh` for the 5000/hr
 * GitHub rate limit (vs 60/hr unauthenticated). The script auto-detects `gh`.
 */

import { readFileSync, readdirSync, statSync, existsSync } from "node:fs";
import { join, relative, basename } from "node:path";
import { execFileSync } from "node:child_process";

const ROOT = process.argv[2] && !process.argv[2].startsWith("-") ? process.argv[2] : ".";
const FLAGS = new Set(process.argv.slice(2).filter((a) => a.startsWith("--")));
const JSON_OUT = FLAGS.has("--json");
const CONC = Number((process.argv.find((a) => a.startsWith("--concurrency=")) || "").split("=")[1]) || 8;
const TODAY = new Date();

const want = {
  actions: !FLAGS.has("--deps-only") && !FLAGS.has("--runtimes-only") && !FLAGS.has("--no-actions"),
  deps: !FLAGS.has("--actions-only") && !FLAGS.has("--runtimes-only"),
  runtimes: !FLAGS.has("--actions-only") && !FLAGS.has("--deps-only"),
};

const SKIP_DIRS = new Set([
  ".git", "node_modules", "vendor", "dist", "build", "target", ".venv", "venv",
  ".next", ".cache", "coverage", "__pycache__", ".tox", "bower_components",
]);

// ---------- small utils ----------------------------------------------------

function* walk(dir, depth = 0) {
  if (depth > 8) return;
  let entries;
  try { entries = readdirSync(dir, { withFileTypes: true }); } catch { return; }
  for (const e of entries) {
    if (e.name.startsWith(".") && e.isDirectory() && !e.name.startsWith(".github")) {
      if (SKIP_DIRS.has(e.name)) continue;
    }
    if (SKIP_DIRS.has(e.name)) continue;
    const full = join(dir, e.name);
    if (e.isDirectory()) yield* walk(full, depth + 1);
    else yield full;
  }
}

const read = (p) => { try { return readFileSync(p, "utf8"); } catch { return null; } };
const rel = (p) => relative(ROOT, p) || basename(p);

// crude semver parse: returns {major,minor,patch,pre} or null
function semver(v) {
  if (!v) return null;
  const m = String(v).trim().replace(/^[v=]+/, "").match(/^(\d+)(?:\.(\d+))?(?:\.(\d+))?(?:[-+](.+))?$/);
  if (!m) return null;
  return { major: +m[1], minor: +(m[2] ?? 0), patch: +(m[3] ?? 0), pre: m[4] || "" };
}
const isPrerelease = (v) => /[-.](alpha|beta|rc|canary|next|dev|nightly|experimental|insiders|pre)\b/i.test(String(v)) || /-/.test(String(v).replace(/^[v=]+/, ""));
function diffLevel(a, b) { // a=current, b=latest
  const x = semver(a), y = semver(b);
  if (!x || !y) return "unknown";
  if (y.major > x.major) return "major";
  if (y.major < x.major) return "ahead";
  if (y.minor > x.minor) return "minor";
  if (y.minor < x.minor) return "ahead";
  if (y.patch > x.patch) return "patch";
  return "current";
}

// strip a range operator to its declared baseline version
const declared = (range) => String(range).replace(/^[\^~>=<\s]*/, "").split(/[\s,|]+/)[0];

// ---------- networking with a concurrency pool -----------------------------

let HAS_GH = false;
try { execFileSync("gh", ["auth", "status"], { stdio: "ignore" }); HAS_GH = true; } catch {}
const GH_TOKEN = process.env.GH_TOKEN || process.env.GITHUB_TOKEN || "";

async function pool(items, fn, n = CONC) {
  const out = new Array(items.length);
  let i = 0;
  await Promise.all(Array.from({ length: Math.min(n, items.length) }, async () => {
    while (i < items.length) { const idx = i++; out[idx] = await fn(items[idx], idx); }
  }));
  return out;
}

async function getJSON(url, headers = {}) {
  try {
    const r = await fetch(url, { headers: { "User-Agent": "version-audit/1.0", ...headers } });
    if (!r.ok) return null;
    return await r.json();
  } catch { return null; }
}

// GitHub API: prefer `gh` (auth, 5000/hr); fall back to fetch.
function ghApi(path) {
  if (HAS_GH) {
    try { return JSON.parse(execFileSync("gh", ["api", path], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] })); }
    catch { return null; }
  }
  return getJSON(`https://api.github.com/${path}`, GH_TOKEN ? { Authorization: `Bearer ${GH_TOKEN}` } : {});
}

// ---------- finding model --------------------------------------------------

const findings = [];
const SEV = { CRITICAL: 0, HIGH: 1, MEDIUM: 2, LOW: 3, INFO: 4, OK: 5 };
function add(f) { findings.push(f); }

// ---------- discovery + checks ---------------------------------------------

const cache = new Map();
const memo = (k, fn) => cache.has(k) ? cache.get(k) : cache.set(k, fn()).get(k);

// ----- GitHub Actions ------------------------------------------------------
async function checkActions(files) {
  const refs = new Map(); // "owner/repo@ref" -> {owner,repo,ref,locations:[]}
  for (const f of files) {
    const txt = read(f);
    if (!txt) continue;
    const re = /uses:\s*["']?([^"'\s#@]+)@([^"'\s#]+)/g;
    let m;
    while ((m = re.exec(txt))) {
      const [path, ref] = [m[1], m[2]];
      if (path.startsWith("./") || path.startsWith("docker://")) continue;
      const [owner, repo] = path.split("/");
      if (!owner || !repo) continue;
      const key = `${owner}/${repo}@${ref}`;
      if (!refs.has(key)) refs.set(key, { owner, repo, ref, path, locs: [] });
      refs.get(key).locs.push(rel(f));
    }
  }
  const breaking = loadData("action-breaking-changes.json") || {};

  await pool([...refs.values()], async (r) => {
    const repoKey = `${r.owner}/${r.repo}`;
    const where = `${repoKey} (${r.locs[0]})`;
    const isSha = /^[0-9a-f]{40}$/i.test(r.ref);
    const isBranch = /^(main|master|develop)$/i.test(r.ref);

    // latest tag for the repo (cached per repo)
    const latest = await memo(`gh:${repoKey}`, async () => {
      let rel = await ghApi(`repos/${repoKey}/releases/latest`);
      let tag = rel && rel.tag_name;
      if (!tag || /bundle/i.test(tag)) {
        const tags = await ghApi(`repos/${repoKey}/tags?per_page=100`);
        if (Array.isArray(tags)) {
          const sv = tags.map((t) => t.name).filter((n) => /^v?\d+\.\d+\.\d+$/.test(n))
            .sort((a, b) => cmp(semver(b), semver(a)));
          tag = sv[0];
        }
      }
      return tag || null;
    });

    if (isBranch) {
      add({ sev: "HIGH", category: "actions", where, current: `@${r.ref}`, latest: latest || "?",
        note: `Branch ref — silent live updates, no audit trail. Pin to a tag or SHA.`, action: "REPLACE" });
      return;
    }
    if (!latest) {
      add({ sev: "INFO", category: "actions", where, current: `@${r.ref}`, latest: "?",
        note: `Could not resolve latest (private/renamed/rate-limited).`, action: "MANUAL" });
      return;
    }
    const lv = semver(latest), cur = semver(r.ref);
    const level = cur ? diffLevel(r.ref, latest) : "unknown";
    const brk = breaking[repoKey];
    if (level === "major" || level === "unknown") {
      const gap = cur ? lv.major - cur.major : "?";
      const brkNote = brk ? ` Breaking history: ${brk.note}` : "";
      add({ sev: gap !== "?" && gap >= 2 ? "MEDIUM" : "LOW", category: "actions", where,
        current: `@${r.ref}`, latest, note: `${gap} major(s) behind (latest ${latest}).${brkNote}`,
        action: "REVIEW_MAJOR" });
    } else if (level === "minor" || level === "patch") {
      add({ sev: "INFO", category: "actions", where, current: `@${r.ref}`, latest,
        note: `Floating major may already cover this; pin or bump to ${latest}.`, action: `UPDATE_${level.toUpperCase()}` });
    } else if (level === "current") {
      add({ sev: "OK", category: "actions", where, current: `@${r.ref}`, latest, note: "current", action: "OK" });
    }
    if (isSha) findings[findings.length - 1].note += " (SHA-pinned ✓ — keep a `# vX.Y.Z` comment + Dependabot).";
  });
}
function cmp(a, b) { // semver desc helper
  if (!a || !b) return 0;
  return (a.major - b.major) || (a.minor - b.minor) || (a.patch - b.patch);
}

// ----- npm / package.json --------------------------------------------------
async function checkNpm(file) {
  let pkg; try { pkg = JSON.parse(read(file)); } catch { return; }
  const deprecatedList = loadData("deprecated-packages.json") || {};
  const buckets = ["dependencies", "devDependencies", "optionalDependencies", "peerDependencies"];
  const deps = [];
  for (const b of buckets) for (const [name, range] of Object.entries(pkg[b] || {})) {
    if (typeof range !== "string" || range.startsWith("workspace:") || range.startsWith("file:")
      || range.startsWith("link:") || range.startsWith("npm:") || /^https?:|^git/.test(range)) continue;
    deps.push({ name, range, bucket: b });
  }
  await pool(deps, async (d) => {
    const where = `${d.name} (${rel(file)})`;
    const pm = await getJSON(`https://registry.npmjs.org/${d.name.replace("/", "%2F")}`,
      { Accept: "application/vnd.npm.install-v1+json" });
    if (!pm || !pm["dist-tags"]) {
      add({ sev: "INFO", category: "npm", where, current: declared(d.range), latest: "?",
        note: "Not found on public registry (private?).", action: "MANUAL" }); return;
    }
    const latest = pm["dist-tags"].latest;
    const dep = pm.versions?.[latest]?.deprecated || (deprecatedList[d.name] ? `replaced by ${deprecatedList[d.name]}` : null);
    const cur = declared(d.range);
    const level = diffLevel(cur, latest);
    if (dep) {
      add({ sev: "LOW", category: "npm", where, current: cur, latest, note: `DEPRECATED: ${String(dep).slice(0, 80)}`, action: "REPLACE" });
    } else if (level === "major") {
      add({ sev: "LOW", category: "npm", where, current: cur, latest, note: `new major (${latest}) — read changelog, check peerDeps/engines.`, action: "REVIEW_MAJOR" });
    } else if (level === "minor" || level === "patch") {
      add({ sev: "INFO", category: "npm", where, current: cur, latest, note: `${level} bump available`, action: `UPDATE_${level.toUpperCase()}` });
    }
  });
}

// ----- Python / pyproject.toml --------------------------------------------
async function checkPyproject(file) {
  const txt = read(file); if (!txt) return;
  const deps = [];
  const block = txt.match(/dependencies\s*=\s*\[([^\]]*)\]/s);
  if (block) for (const line of block[1].split(",")) {
    const m = line.match(/["']\s*([A-Za-z0-9._-]+)\s*([<>=!~]=?[^"']*)?["']/);
    if (m) deps.push({ name: m[1], range: (m[2] || "").trim() });
  }
  await pool(deps, async (d) => {
    const where = `${d.name} (${rel(file)})`;
    const j = await getJSON(`https://pypi.org/pypi/${d.name}/json`);
    if (!j || !j.info) return;
    const latest = j.info.version; // PyPI excludes prereleases here
    const cur = declared(d.range);
    if (!cur) { add({ sev: "INFO", category: "pypi", where, current: "(unpinned)", latest, note: "no version constraint", action: "INFO" }); return; }
    const level = diffLevel(cur, latest);
    if (level === "major") add({ sev: "LOW", category: "pypi", where, current: cur, latest, note: `new major ${latest}`, action: "REVIEW_MAJOR" });
    else if (level === "minor" || level === "patch") add({ sev: "INFO", category: "pypi", where, current: cur, latest, note: `${level} bump`, action: `UPDATE_${level.toUpperCase()}` });
  });
}

// ----- Rust / Cargo.toml ---------------------------------------------------
async function checkCargo(file) {
  const txt = read(file); if (!txt) return;
  const deps = [];
  const sect = txt.split(/^\[/m);
  for (const s of sect) {
    if (!/^dependencies\]|^dev-dependencies\]|^build-dependencies\]|^workspace\.dependencies\]/.test(s)) continue;
    for (const line of s.split("\n")) {
      let m = line.match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']([^"']+)["']/);
      if (!m) m = line.match(/^\s*([A-Za-z0-9_-]+)\s*=\s*\{[^}]*version\s*=\s*["']([^"']+)["']/);
      if (m && m[1] !== "version") deps.push({ name: m[1], range: m[2] });
    }
  }
  await pool(deps, async (d) => {
    const where = `${d.name} (${rel(file)})`;
    const j = await getJSON(`https://crates.io/api/v1/crates/${d.name}`, { "User-Agent": "version-audit/1.0 (audit)" });
    if (!j || !j.crate) return;
    const latest = j.crate.max_stable_version || j.crate.max_version;
    const cur = declared(d.range);
    const level = diffLevel(cur, latest);
    if (level === "major") add({ sev: "LOW", category: "cargo", where, current: cur, latest, note: `new major ${latest}`, action: "REVIEW_MAJOR" });
    else if (level === "minor" || level === "patch") add({ sev: "INFO", category: "cargo", where, current: cur, latest, note: `${level} bump`, action: `UPDATE_${level.toUpperCase()}` });
  });
}

// ----- Go / go.mod ---------------------------------------------------------
async function checkGoMod(file) {
  const txt = read(file); if (!txt) return;
  const deps = [];
  const re = /^\s*([\w.\-/]+)\s+v(\d+\.\d+\.\d+[\w.\-+]*)\s*(\/\/ indirect)?/gm;
  let m;
  while ((m = re.exec(txt))) if (!m[3]) deps.push({ name: m[1], range: "v" + m[2] });
  await pool(deps.slice(0, 60), async (d) => {
    const where = `${d.name} (${rel(file)})`;
    const j = await getJSON(`https://proxy.golang.org/${encodeURI(d.name).replace(/:/g, "%3A")}/@latest`);
    if (!j || !j.Version) return;
    const level = diffLevel(d.range, j.Version);
    if (level === "major") add({ sev: "LOW", category: "go", where, current: d.range, latest: j.Version, note: `new major — note v2+ module path changes`, action: "REVIEW_MAJOR" });
    else if (level === "minor" || level === "patch") add({ sev: "INFO", category: "go", where, current: d.range, latest: j.Version, note: `${level} bump`, action: `UPDATE_${level.toUpperCase()}` });
  });
}

// ----- EOL runtimes --------------------------------------------------------
const eolCache = new Map();
async function eolProduct(product) {
  if (eolCache.has(product)) return eolCache.get(product);
  const p = getJSON(`https://endoflife.date/api/${product}.json`);
  eolCache.set(product, p);
  return p;
}
function past(d) { return d && d !== false && d !== true && new Date(d) < TODAY; }

async function checkRuntime(product, version, where) {
  const cycles = await eolProduct(product);
  if (!Array.isArray(cycles)) return;
  const sv = semver(version);
  if (!sv) return;
  const cyc = cycles.find((c) => String(c.cycle) === `${sv.major}` || String(c.cycle) === `${sv.major}.${sv.minor}`)
    || cycles.find((c) => String(c.cycle) === `${sv.major}`);
  if (!cyc) return;
  if (past(cyc.eol)) add({ sev: "HIGH", category: "runtime", where, current: version, latest: cyc.latest || "?", note: `${product} ${cyc.cycle} is EOL (since ${cyc.eol}) — no security patches.`, action: "REVIEW_MAJOR" });
  else if (past(cyc.support)) add({ sev: "MEDIUM", category: "runtime", where, current: version, latest: cyc.latest || "?", note: `${product} ${cyc.cycle} in security-only phase (active support ended ${cyc.support}).`, action: "PLAN_UPGRADE" });
  else add({ sev: "OK", category: "runtime", where, current: version, latest: cyc.latest || "?", note: `${product} ${cyc.cycle} supported`, action: "OK" });
}

const DOCKER_EOL = { node: "nodejs", python: "python", golang: "go", ruby: "ruby", ubuntu: "ubuntu", debian: "debian", alpine: "alpine", php: "php", openjdk: "java", postgres: "postgresql", redis: "redis", mysql: "mysql", nginx: "nginx" };

async function checkRuntimes(files) {
  const jobs = [];
  for (const f of files) {
    const base = basename(f);
    if (base === ".nvmrc" || base === ".node-version") {
      const v = (read(f) || "").trim().replace(/^v/, "");
      if (/^\d/.test(v)) jobs.push(checkRuntime("nodejs", v, `node ${rel(f)}`));
    } else if (base === "package.json") {
      try { const e = JSON.parse(read(f)).engines?.node; if (e) { const d = declared(e); if (/^\d/.test(d)) jobs.push(checkRuntime("nodejs", d, `engines.node ${rel(f)}`)); } } catch {}
    } else if (base === "go.mod") {
      const m = (read(f) || "").match(/^go\s+(\d+\.\d+)/m); if (m) jobs.push(checkRuntime("go", m[1] + ".0", `go directive ${rel(f)}`));
    } else if (base === "pyproject.toml") {
      const m = (read(f) || "").match(/requires-python\s*=\s*["'][^0-9]*(\d+\.\d+)/); if (m) jobs.push(checkRuntime("python", m[1] + ".0", `requires-python ${rel(f)}`));
    } else if (base === ".python-version") {
      const v = (read(f) || "").trim(); if (/^\d/.test(v)) jobs.push(checkRuntime("python", v, rel(f)));
    } else if (base === ".tool-versions") {
      for (const line of (read(f) || "").split("\n")) {
        const [tool, ver] = line.trim().split(/\s+/);
        const prod = { nodejs: "nodejs", node: "nodejs", python: "python", ruby: "ruby", golang: "go", go: "go" }[tool];
        if (prod && /^\d/.test(ver || "")) jobs.push(checkRuntime(prod, ver, `${tool} ${rel(f)}`));
      }
    } else if (base === "Dockerfile" || base.startsWith("Dockerfile.")) {
      for (const m of (read(f) || "").matchAll(/^FROM\s+([\w.\-/]+):([\w.\-]+)/gim)) {
        const img = m[1].split("/").pop(), tag = m[2];
        const prod = DOCKER_EOL[img];
        const v = (tag.match(/^(\d+(?:\.\d+)?)/) || [])[1];
        if (tag === "latest") add({ sev: "MEDIUM", category: "runtime", where: `FROM ${img}:latest ${rel(f)}`, current: "latest", latest: "—", note: "Floating :latest base image — pin a version + digest.", action: "REPLACE" });
        else if (prod && v) jobs.push(checkRuntime(prod, v.includes(".") ? v + ".0" : v + ".0.0", `FROM ${img}:${tag} ${rel(f)}`));
      }
    }
  }
  await Promise.all(jobs);
}

// ----- data loader ---------------------------------------------------------
function loadData(name) {
  const p = join(import.meta.dirname || ".", "..", "data", name);
  try { return JSON.parse(readFileSync(p, "utf8")); } catch { return null; }
}

// ---------- main -----------------------------------------------------------

async function main() {
  if (!existsSync(ROOT)) { console.error(`path not found: ${ROOT}`); process.exit(2); }
  const all = [...walk(ROOT)];
  const workflows = all.filter((f) => /\.github\/workflows\/[^/]+\.ya?ml$/.test(f));
  const pkgs = all.filter((f) => basename(f) === "package.json");
  const pyprojects = all.filter((f) => basename(f) === "pyproject.toml");
  const cargos = all.filter((f) => basename(f) === "Cargo.toml");
  const gomods = all.filter((f) => basename(f) === "go.mod");

  const tasks = [];
  if (want.actions && workflows.length) tasks.push(checkActions(workflows));
  if (want.deps) {
    for (const f of pkgs) tasks.push(checkNpm(f));
    for (const f of pyprojects) tasks.push(checkPyproject(f));
    for (const f of cargos) tasks.push(checkCargo(f));
    for (const f of gomods) tasks.push(checkGoMod(f));
  }
  if (want.runtimes) tasks.push(checkRuntimes(all));
  await Promise.all(tasks);

  // sort: severity, then category
  findings.sort((a, b) => (SEV[a.sev] - SEV[b.sev]) || a.category.localeCompare(b.category));
  const actionable = findings.filter((f) => f.sev !== "OK");

  if (JSON_OUT) { console.log(JSON.stringify({ scanned: { workflows: workflows.length, pkgs: pkgs.length, pyprojects: pyprojects.length, cargos: cargos.length, gomods: gomods.length }, auth: HAS_GH ? "gh" : GH_TOKEN ? "token" : "anonymous", findings }, null, 2)); return; }

  const counts = actionable.reduce((m, f) => ((m[f.sev] = (m[f.sev] || 0) + 1), m), {});
  console.log(`\n# Version audit — ${rel(ROOT) || "."}\n`);
  console.log(`Scanned: ${workflows.length} workflow(s), ${pkgs.length} package.json, ${pyprojects.length} pyproject, ${cargos.length} Cargo.toml, ${gomods.length} go.mod`);
  console.log(`GitHub auth: ${HAS_GH ? "gh (5000/hr)" : GH_TOKEN ? "token (5000/hr)" : "ANONYMOUS (60/hr — expect gaps)"}`);
  if (!actionable.length) { console.log(`\n✅ No actionable findings. Everything is on a current, safe version.\n`); return; }
  console.log(`\nFindings: ` + ["CRITICAL", "HIGH", "MEDIUM", "LOW", "INFO"].filter((s) => counts[s]).map((s) => `${counts[s]} ${s}`).join(", ") + "\n");
  console.log(`| Sev | Category | Ref | Current | Latest-safe | Action | Note |`);
  console.log(`|-----|----------|-----|---------|-------------|--------|------|`);
  for (const f of actionable) {
    console.log(`| ${f.sev} | ${f.category} | ${f.where} | ${f.current} | ${f.latest} | ${f.action} | ${f.note.replace(/\|/g, "/")} |`);
  }
  console.log(`\nLegend: UPDATE_* = safe to apply (run tests after). REVIEW_MAJOR = breaking, read changelog, never auto-apply. REPLACE = deprecated/branch-ref. PLAN_UPGRADE = EOL soon. MANUAL = could not resolve.`);
  console.log(`\nReminder: match CVEs against the LOCKFILE (resolved) version, not the manifest range. Run \`osv-scanner -r .\` (or npm/cargo/pip audit) for the security axis this script does not cover.\n`);
}

main().catch((e) => { console.error("version-audit failed:", e?.message || e); process.exit(1); });
