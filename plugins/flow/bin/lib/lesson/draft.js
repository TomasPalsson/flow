'use strict';

// lesson/draft.js — the guardrail is written before the question is asked
// (research §9.2c). This module turns the decided rung into the concrete file
// contents `lock` will land: the D-4 rule, the red test, or the note line.

const fs = require('node:fs');
const path = require('node:path');
const { commandPattern, ereEscape, isCommand, noteArea, pathPattern, pathToken } = require('./decide.js');

const IMPORTS = {
  vitest: "import { test } from 'vitest';",
  'bun:test': "import { test } from 'bun:test';",
  'node:test': "const { test } = require('node:test');",
};

// Every draft carries a rule spec, even when the rung is `note`: the
// recurrence gate promotes the second lock of a note to a rule, and it may not
// invent a pattern at that point.
function ruleSpec(input, did, should, slug, created) {
  const token = pathToken(input);
  let spec;
  if (isCommand(input)) {
    const pattern = commandPattern(input);
    spec = { event: 'PreToolUse', tool: 'Bash', pattern, action: 'deny', preview: `Bash commands matching /${pattern}/ are blocked` };
  } else if (token) {
    const pattern = pathPattern(token);
    spec = { event: 'PreToolUse', tool: '*', pattern, action: 'deny', preview: `Edit and Write under ${pattern} are blocked` };
  } else {
    // Nothing to match on but the words themselves: warn after the fact
    // rather than deny a tool call this pattern cannot honestly identify.
    const pattern = input.trim().split(/\s+/).map(ereEscape).join('[[:space:]]+');
    spec = { event: 'PostToolUse', tool: '*', pattern, action: 'warn', preview: `a warning whenever /${pattern}/ shows up again` };
  }
  spec.created = created;
  spec.source = did;
  spec.message = `/lesson rule ${slug}: ${should}.\n${spec.preview}. Undo: flow lesson undo ${slug}`;
  return spec;
}

function camel(slug) {
  return slug.split('-').map((w) => w.charAt(0).toUpperCase() + w.slice(1)).join('');
}

function goPackage(root) {
  try {
    for (const f of fs.readdirSync(root)) {
      if (!f.endsWith('.go')) continue;
      const m = fs.readFileSync(path.join(root, f), 'utf8').match(/^package\s+(\w+)/m);
      if (m) return m[1];
    }
  } catch {
    /* no readable go source: main is the safe default */
  }
  return 'main';
}

function firstDir(root, names, fallback) {
  for (const n of names) {
    try {
      if (fs.statSync(path.join(root, n)).isDirectory()) return n;
    } catch {
      /* not this one */
    }
  }
  return fallback;
}

function header(slug, did, should, input, comment) {
  return [
    `${comment} flow lesson: ${slug} — drafted red by \`flow lesson propose\`. Finish the`,
    `${comment} reproduction, watch it fail, then fix the code.`,
    `${comment} Did:    ${did}`,
    `${comment} Should: ${should}`,
    `${comment} Input:  ${input}`,
  ].join('\n');
}

// The draft is red on purpose: it names the reproduction and refuses to pass
// until someone writes it. A green placeholder would be a lie.
function testDraft(root, runner, slug, did, should, input) {
  const snake = slug.replace(/-/g, '_');
  const why = `flow lesson ${slug}: reproduce the input above, then delete this line`;
  if (runner.kind === 'pytest') {
    const dir = firstDir(root, ['tests', 'test'], 'tests');
    const body = `${header(slug, did, should, input, '#')}\n\n\ndef test_${snake}():\n    raise AssertionError(${JSON.stringify(why)})\n`;
    return { file: path.join(root, dir, `test_${snake}.py`), body };
  }
  if (runner.kind === 'cargo') {
    const body = `${header(slug, did, should, input, '//')}\n\n#[test]\nfn ${snake}() {\n    panic!(${JSON.stringify(why)});\n}\n`;
    return { file: path.join(root, 'tests', `${snake}.rs`), body };
  }
  if (runner.kind === 'go') {
    const body = `${header(slug, did, should, input, '//')}\n\npackage ${goPackage(root)}\n\nimport "testing"\n\nfunc Test${camel(slug)}(t *testing.T) {\n\tt.Fatal(${JSON.stringify(why)})\n}\n`;
    return { file: path.join(root, `${snake}_test.go`), body };
  }
  const dir = firstDir(root, ['tests', 'test', '__tests__', 'src/__tests__'], 'tests');
  const imp = IMPORTS[runner.framework] || '';
  const body = `${header(slug, did, should, input, '//')}\n${imp ? `${imp}\n` : ''}\ntest(${JSON.stringify(should)}, () => {\n  throw new Error(${JSON.stringify(why)});\n});\n`;
  return { file: path.join(root, dir, `${slug}.test.js`), body };
}

// D-3: a note is path-scoped when the input names a path, and only falls back
// to CLAUDE.md when no path scope applies.
//
// The `script` rung lands here too — there is no bookkeeping script flow can
// write for you — but it says so: a "script wanted" line naming the
// bookkeeping to automate, not an ordinary note that hides which rung decided
// it. The rung stays visible in the receipt, in `list` and in the line itself.
function noteDraft(sc, input, did, should, slug, rung) {
  const token = pathToken(input);
  const area = token ? noteArea(token) : null;
  const file = area ? path.join(sc.notesDir, `${area}.md`) : sc.claudeMd;
  const where = area ? path.basename(file) : 'CLAUDE.md';
  const script = rung === 'script';
  return {
    file,
    line: script
      ? `- script wanted: ${should} — automate the bookkeeping in "${did}" (undo: flow lesson undo ${slug})`
      : `- ${should} — ${did} (undo: flow lesson undo ${slug})`,
    header: area
      ? `# ${area}\n\nRules for this area, recorded by /lesson.\n\n`
      : '# Project notes\n\nRecorded by /lesson when no path scope applied.\n\n',
    preview: script ? `a script-wanted note in ${where}` : `one line in ${where}`,
  };
}

module.exports = { ruleSpec, testDraft, noteDraft };
