'use strict';

// eval/cases.js — case discovery, tag matching, and per-case gated-tool
// grants for `flow eval` (plugins/flow/bin/lib/eval.js). Split out of
// eval.js to keep it under the repo's size guard (see eval.js's header
// comment). `claude plugin eval --allow-tools` is an operator grant that
// applies to every case in one invocation and OVERRIDES that case's own
// `execution.allowed_tools` — so `flow eval` must run one `claude plugin
// eval` per case and grant only the gated tools that case's own
// `allowed_tools` names (measured on routing-loop, 2026-09-13: the tier-wide
// grant let a routing case run the suite itself with Bash and pass 3/3
// without the loop skill firing).

const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { EVALS_ROOT } = require('./contract.js');

const GATED = ['Write', 'Edit', 'Bash'];

// readCaseTags(yamlText) -> string[]. A minimal reader for the one shape
// case.yaml uses: `tags: [a, b]` or a `tags:` block list. No YAML library
// (code-design.md decision 2 — cases are plain files, checked at test time).
function readCaseTags(yamlText) {
  const inline = yamlText.match(/^tags:\s*\[([^\]]*)\]/m);
  if (inline) {
    return inline[1]
      .split(',')
      .map((s) => s.trim().replace(/^['"]|['"]$/g, ''))
      .filter(Boolean);
  }
  const block = yamlText.match(/^tags:\s*\n((?:[ \t]*-[ \t]*.+\n?)+)/m);
  if (!block) return [];
  return block[1]
    .split('\n')
    .map((l) => l.match(/-\s*(.+)/))
    .filter(Boolean)
    .map((m) => m[1].trim().replace(/^['"]|['"]$/g, ''));
}

function caseTags(toplevel, caseName) {
  let raw;
  try {
    raw = fs.readFileSync(path.join(toplevel, EVALS_ROOT, caseName, 'case.yaml'), 'utf8');
  } catch {
    return [];
  }
  return readCaseTags(raw);
}

// anyCaseNeedsBash(toplevel, selectedTags) -> true if a case dir under
// EVALS_ROOT carries both `needs-bash` and at least one tag in selectedTags.
// Cases can carry two tags (e.g. `[pipeline, needs-bash]`), so a plain
// `selectedTags.includes('needs-bash')` check misses them whenever the
// caller selects by the *other* tag (`--tag pipeline`) — evals/README.md's
// own `--allow-tools Write Edit (and Bash for needs-bash cases)` contract
// depends on this, not on the literal tag name in the selection.
function anyCaseNeedsBash(toplevel, selectedTags) {
  let entries;
  try {
    entries = fs.readdirSync(path.join(toplevel, EVALS_ROOT), { withFileTypes: true });
  } catch {
    return false;
  }
  return entries.some((e) => {
    if (!e.isDirectory()) return false;
    const tags = caseTags(toplevel, e.name);
    return tags.includes('needs-bash') && tags.some((t) => selectedTags.includes(t));
  });
}

// readAllowedTools(yamlText) -> string[]. Same hand-regex approach as
// readCaseTags, for the one shape case.yaml's `execution:` block uses: a
// single line `allowed_tools: [A, B, C]`, at any indentation. No YAML
// library.
function readAllowedTools(yamlText) {
  const m = yamlText.match(/^[ \t]*allowed_tools:\s*\[([^\]]*)\]/m);
  if (!m) return [];
  return m[1]
    .split(',')
    .map((s) => s.trim().replace(/^['"]|['"]$/g, ''))
    .filter(Boolean);
}

// selectCases(toplevel, evalsRoot, selectedTags, allowBash) -> [{name, tags,
// allowedTools, grant, needsBash}], sorted by name. Every dir under
// <toplevel>/<evalsRoot> with a case.yaml whose tags intersect selectedTags.
// `grant` is allowedTools ∩ GATED, in GATED order (Write, Edit, Bash) — the
// exact set `claude plugin eval --allow-tools` must be given for THIS case,
// since that flag overrides rather than narrows the case's own
// allowed_tools. A needsBash case (tags include `needs-bash`) is dropped
// entirely when allowBash is false: the existing "skipping needs-bash
// cases" behaviour (selectTagsForRun's notice still covers it).
function selectCases(toplevel, evalsRoot, selectedTags, allowBash) {
  let entries;
  try {
    entries = fs.readdirSync(path.join(toplevel, evalsRoot), { withFileTypes: true });
  } catch {
    return [];
  }
  const out = [];
  for (const e of entries) {
    if (!e.isDirectory()) continue;
    let raw;
    try {
      raw = fs.readFileSync(path.join(toplevel, evalsRoot, e.name, 'case.yaml'), 'utf8');
    } catch {
      continue;
    }
    const tags = readCaseTags(raw);
    if (!tags.some((t) => selectedTags.includes(t))) continue;
    const needsBash = tags.includes('needs-bash');
    if (needsBash && !allowBash) continue;
    const allowedTools = readAllowedTools(raw);
    const grant = GATED.filter((t) => allowedTools.includes(t));
    out.push({ name: e.name, tags, allowedTools, grant, needsBash });
  }
  out.sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
  return out;
}

// ---------------------------------------------------------------------------
// `flow eval --changed` — which cases a diff touches.
//   plugins/<p>/skills/<s>/**            -> skill s, through select-cases
//   plugins/<p>/skills/shared/<f>        -> every skill whose SKILL.md or references link shared/<f>
//   plugins/<p>/evals/<case>/**          -> that case
//   plugins/flow/(bin|hooks|scripts)/**  -> unmapped (no skill owns it; run --tag pipeline/xhard)
// The skill -> case map is flow-extras' select-cases, so there is one copy of it.
// ---------------------------------------------------------------------------

const SELECT_CASES = path.resolve(__dirname, '../../../../flow-extras/skills/skill-improver/scripts/select-cases');

function gitOut(toplevel, args) {
  const r = spawnSync('git', args, { cwd: toplevel, encoding: 'utf8' });
  return { ok: r.status === 0, out: r.stdout || '', err: `${r.stderr || ''}`.trim() };
}

// changedPaths(toplevel, base) -> {paths} | {error}. Committed since base, plus
// uncommitted and untracked files, so a skill edited in the working tree counts.
function changedPaths(toplevel, base) {
  const committed = gitOut(toplevel, ['diff', '--name-only', `${base}...HEAD`]);
  if (!committed.ok) return { error: `cannot diff against ${base}: ${committed.err.split('\n')[0]}` };
  const dirty = gitOut(toplevel, ['diff', '--name-only', 'HEAD']);
  const untracked = gitOut(toplevel, ['ls-files', '--others', '--exclude-standard']);
  const all = [committed.out, dirty.out, untracked.out].join('\n').split('\n').filter(Boolean);
  return { paths: [...new Set(all)].sort() };
}

function skillDirs(toplevel) {
  const out = [];
  let plugins;
  try {
    plugins = fs.readdirSync(path.join(toplevel, 'plugins'), { withFileTypes: true });
  } catch {
    return out;
  }
  for (const p of plugins) {
    if (!p.isDirectory()) continue;
    const root = path.join(toplevel, 'plugins', p.name, 'skills');
    let skills;
    try {
      skills = fs.readdirSync(root, { withFileTypes: true });
    } catch {
      continue;
    }
    for (const s of skills) if (s.isDirectory() && s.name !== 'shared') out.push({ name: s.name, dir: path.join(root, s.name) });
  }
  return out;
}

function markdownIn(dir) {
  const out = [];
  let entries;
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
  } catch {
    return out;
  }
  for (const e of entries) {
    const full = path.join(dir, e.name);
    if (e.isDirectory()) out.push(...markdownIn(full));
    else if (e.name.endsWith('.md')) out.push(full);
  }
  return out;
}

// linkingSkills(toplevel, rel) -> skill names whose SKILL.md or references/ mention shared/<rel>.
function linkingSkills(toplevel, rel) {
  const needle = `shared/${rel}`;
  const names = [];
  for (const s of skillDirs(toplevel)) {
    const files = [path.join(s.dir, 'SKILL.md'), ...markdownIn(path.join(s.dir, 'references'))];
    const linked = files.some((f) => {
      try {
        return fs.readFileSync(f, 'utf8').includes(needle);
      } catch {
        return false;
      }
    });
    if (linked) names.push(s.name);
  }
  return names;
}

function casesOfSkill(toplevel, skill) {
  const r = spawnSync('bash', [SELECT_CASES, skill, toplevel], { encoding: 'utf8' });
  const names = [];
  for (const line of (r.stdout || '').split('\n')) {
    if (line.endsWith('/case.yaml')) names.push(path.basename(path.dirname(line)));
  }
  return [...new Set(names)].sort();
}

// changedCases(toplevel, base) -> {rows: [{key, cases, note?}], cases: string[], unmapped: string[]} | {error}
function changedCases(toplevel, base) {
  if (!fs.existsSync(SELECT_CASES)) return { error: 'select-cases not found beside flow (plugins/flow-extras/skills/skill-improver/scripts); use --tag instead' };
  const diff = changedPaths(toplevel, base);
  if (diff.error) return { error: diff.error };
  const skills = new Set();
  const sharedRows = [];
  const caseDirs = new Set();
  const unmapped = [];
  for (const p of diff.paths) {
    let m = p.match(/^plugins\/[^/]+\/skills\/shared\/(.+)$/);
    if (m) {
      const linked = linkingSkills(toplevel, m[1]);
      linked.forEach((n) => skills.add(n));
      sharedRows.push({ key: `shared/${m[1]}`, skills: linked });
      continue;
    }
    m = p.match(/^plugins\/[^/]+\/skills\/([^/]+)\//);
    if (m) {
      skills.add(m[1]);
      continue;
    }
    m = p.match(/^plugins\/[^/]+\/evals\/([^/]+)\/./);
    if (m) {
      caseDirs.add(m[1]);
      continue;
    }
    if (/^plugins\/flow\/(bin|hooks|scripts)\//.test(p) && !/^plugins\/flow\/scripts\/tests\//.test(p)) unmapped.push(p);
  }
  const rows = [];
  const cases = new Set();
  for (const s of [...skills].sort()) {
    const found = casesOfSkill(toplevel, s);
    found.forEach((c) => cases.add(c));
    rows.push({ key: s, cases: found });
  }
  for (const r of sharedRows) {
    if (!r.skills.length) rows.push({ key: r.key, cases: [], note: 'no skill links it' });
  }
  for (const c of [...caseDirs].sort()) {
    const exists = fs.existsSync(path.join(toplevel, EVALS_ROOT, c, 'case.yaml'));
    if (exists) cases.add(c);
    rows.push({ key: `case ${c}`, cases: exists ? [c] : [], note: exists ? '' : 'case.yaml gone' });
  }
  return { rows, cases: [...cases].sort(), unmapped };
}

// formatChanged(result) -> lines for the skill -> cases table and the unmapped paths.
function formatChanged(result) {
  const lines = result.rows.map((r) => `${r.key} -> ${r.cases.length ? r.cases.join(', ') : `(no cases${r.note ? `: ${r.note}` : ''})`}`);
  for (const p of result.unmapped) lines.push(`unmapped: ${p} (no skill owns it; run --tag pipeline --tag xhard)`);
  return lines;
}

module.exports = { changedCases, formatChanged, GATED, readCaseTags, caseTags, anyCaseNeedsBash, readAllowedTools, selectCases };
