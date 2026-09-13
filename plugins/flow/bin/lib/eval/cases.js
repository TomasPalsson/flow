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

module.exports = { GATED, readCaseTags, caseTags, anyCaseNeedsBash, readAllowedTools, selectCases };
