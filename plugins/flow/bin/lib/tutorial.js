#!/usr/bin/env node
'use strict';

// tutorial.js — flow tutorial: an interactive, disposable-sandbox walkthrough
// of lessons 1..N (see lib/lessons/*.js). See .claude/slices/2-brief.md for
// the behaviors this file is judged by (test_tutorial.sh, B9-B18/B27/B28).
//
// Invocation: `node tutorial.js [--list] [--reset] [--lesson N] [--sandbox <dir>]`
// bin/flow's own `tutorial` dispatch (a later slice) requires this file and
// calls its `run(argv, home)` export instead of spawning a subprocess.

const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const readline = require('node:readline');
const { spawnSync } = require('node:child_process');

const LESSON_FILE_PATTERN = /^(\d{2})-.+\.js$/;
const LESSONS_DIR = path.join(__dirname, 'lessons');
const CLI_PATH = path.join(__dirname, '..', 'flow');
const PROGRESS_VERSION = 1;
const STATUS = { NOT_STARTED: 'not-started', DONE: 'done', SKIPPED: 'skipped' };

class TutorialError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Lesson discovery — sorted by number, contiguous from 1.
// ─────────────────────────────────────────────────────────────────────────────

function discoverLessons() {
  const entries = fs.readdirSync(LESSONS_DIR).filter((f) => LESSON_FILE_PATTERN.test(f));
  const numbered = entries
    .map((f) => ({ file: f, number: parseInt(f.match(LESSON_FILE_PATTERN)[1], 10) }))
    .sort((a, b) => a.number - b.number);
  numbered.forEach((entry, i) => {
    if (entry.number !== i + 1) {
      throw new Error(`lesson files are not contiguous from 1: ${entry.file} is out of sequence`);
    }
  });
  return numbered.map((entry) => require(path.join(LESSONS_DIR, entry.file)));
}

// ─────────────────────────────────────────────────────────────────────────────
// Progress persistence — one JSON file under HOME, so a fake HOME in tests
// makes it deterministic and isolated from the caller's real machine.
// ─────────────────────────────────────────────────────────────────────────────

function progressPath(home) {
  return path.join(home, '.claude', 'flow-tutorial-progress.json');
}

function defaultProgress(lessonCount) {
  const statuses = {};
  for (let i = 1; i <= lessonCount; i++) statuses[i] = STATUS.NOT_STARTED;
  return { version: PROGRESS_VERSION, cursor: 1, sandboxDir: null, statuses };
}

function validProgressShape(parsed, lessonCount) {
  if (!parsed || typeof parsed !== 'object') return false;
  if (!Number.isInteger(parsed.cursor) || parsed.cursor < 1 || parsed.cursor > lessonCount) return false;
  if (!parsed.statuses || typeof parsed.statuses !== 'object') return false;
  for (let i = 1; i <= lessonCount; i++) {
    const s = parsed.statuses[i];
    if (s !== STATUS.NOT_STARTED && s !== STATUS.DONE && s !== STATUS.SKIPPED) return false;
  }
  return true;
}

function loadProgress(home, lessonCount) {
  const p = progressPath(home);
  let raw;
  try {
    raw = fs.readFileSync(p, 'utf8');
  } catch {
    return defaultProgress(lessonCount);
  }
  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch (e) {
    throw new TutorialError('INVALID_PROGRESS_FILE', `${p} is not valid JSON: ${e.message}`);
  }
  if (!validProgressShape(parsed, lessonCount)) {
    throw new TutorialError('INVALID_PROGRESS_FILE', `${p} does not match the expected shape`);
  }
  return { version: PROGRESS_VERSION, cursor: parsed.cursor, sandboxDir: parsed.sandboxDir || null, statuses: Object.assign({}, parsed.statuses) };
}

function saveProgress(home, state) {
  const p = progressPath(home);
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p, JSON.stringify(state, null, 2) + '\n');
}

function resetProgress(home) {
  try {
    fs.unlinkSync(progressPath(home));
  } catch {
    // nothing to reset — fine
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sandbox — a disposable git repo plus a `flow` shim on `<sandbox>-bin`, so
// every typed command can call `flow` without touching the real PATH.
// ─────────────────────────────────────────────────────────────────────────────

function runGit(cwd, args) {
  const r = spawnSync('git', args, { cwd, encoding: 'utf8' });
  if (r.error || r.status !== 0) {
    const detail = r.error ? r.error.message : (r.stderr || '').trim();
    throw new TutorialError('SANDBOX_CREATE_FAILED', `git ${args.join(' ')} failed: ${detail}`);
  }
}

function writeShim(sandboxDir) {
  const binDir = `${sandboxDir}-bin`;
  fs.mkdirSync(binDir, { recursive: true });
  const shimPath = path.join(binDir, 'flow');
  const cliReal = fs.realpathSync(CLI_PATH);
  fs.writeFileSync(shimPath, `#!/bin/sh\nexec "${process.execPath}" "${cliReal}" "$@"\n`);
  fs.chmodSync(shimPath, 0o755);
  return binDir;
}

function initSandboxRepo(sandboxDir) {
  runGit(sandboxDir, ['init', '-q']);
  runGit(sandboxDir, ['config', 'user.email', 'tutorial@flow.local']);
  runGit(sandboxDir, ['config', 'user.name', 'flow tutorial']);
  runGit(sandboxDir, ['config', 'commit.gpgsign', 'false']);
  try {
    fs.writeFileSync(path.join(sandboxDir, 'README.md'), '# flow tutorial sandbox\n');
  } catch (e) {
    throw new TutorialError('SANDBOX_CREATE_FAILED', `could not write README.md: ${e.message}`);
  }
  runGit(sandboxDir, ['add', 'README.md']);
  runGit(sandboxDir, ['commit', '-q', '-m', 'init']);
}

function createSandbox(explicitDir) {
  let sandboxDir;
  try {
    if (explicitDir) {
      fs.mkdirSync(explicitDir, { recursive: true });
      sandboxDir = explicitDir;
    } else {
      sandboxDir = fs.mkdtempSync(path.join(os.tmpdir(), 'flow-tutorial-'));
    }
  } catch (e) {
    throw new TutorialError('SANDBOX_CREATE_FAILED', `could not create ${explicitDir || '(tmp dir)'}: ${e.message}`);
  }
  if (!fs.existsSync(path.join(sandboxDir, '.git'))) initSandboxRepo(sandboxDir);
  return { sandboxDir, binDir: writeShim(sandboxDir) };
}

// ─────────────────────────────────────────────────────────────────────────────
// Running a typed command inside the sandbox.
// ─────────────────────────────────────────────────────────────────────────────

function runInSandbox(sandbox, commandLine) {
  const env = Object.assign({}, process.env, {
    PATH: sandbox.binDir + path.delimiter + (process.env.PATH || ''),
  });
  const r = spawnSync('/bin/sh', ['-c', commandLine], { cwd: sandbox.sandboxDir, env, encoding: 'utf8' });
  return { command: commandLine, stdout: r.stdout || '', stderr: r.stderr || '', exitCode: r.status === null ? 1 : r.status };
}

// ─────────────────────────────────────────────────────────────────────────────
// Rendering.
// ─────────────────────────────────────────────────────────────────────────────

function statusTag(status) {
  return status === STATUS.NOT_STARTED ? '' : ` [${status}]`;
}

function renderLesson(lesson, total, sandboxDir, status) {
  return [
    '',
    `Lesson ${lesson.number}/${total}: ${lesson.title}${statusTag(status)}`,
    lesson.intro,
    '',
    `try it: ${lesson.tryIt}`,
    '',
    `${sandboxDir} $ `,
  ].join('\n');
}

function renderList(lessons, statuses) {
  return lessons.map((l) => `${l.number}. ${l.title} [${statuses[l.number]}]`).join('\n') + '\n';
}

// ─────────────────────────────────────────────────────────────────────────────
// Interactive session — every status change goes through this file's own
// `state.statuses[idx] = ...` assignments below; `b` and a blank Enter only
// ever touch `state.cursor`.
// ─────────────────────────────────────────────────────────────────────────────

function isNavCommand(line) {
  return line === 'b' || line === 's' || line === '';
}

function applyNav(line, idx, lessons, state) {
  if (line === 'b') {
    if (idx > 1) state.cursor = idx - 1;
  } else if (line === 's') {
    state.statuses[idx] = STATUS.SKIPPED;
    if (idx < lessons.length) state.cursor = idx + 1;
  } else if (state.statuses[idx] !== STATUS.NOT_STARTED && idx < lessons.length) {
    state.cursor = idx + 1;
  }
}

function applyCommand(line, idx, lessons, sandbox, state) {
  const result = runInSandbox(sandbox, line);
  process.stdout.write(result.stdout);
  if (result.stderr) process.stderr.write(result.stderr);
  const lesson = lessons[idx - 1];
  if (!lesson.check(result, { sandboxDir: sandbox.sandboxDir })) return;
  state.statuses[idx] = STATUS.DONE;
  if (idx < lessons.length) {
    state.cursor = idx + 1;
    process.stdout.write(`\n> lesson ${idx} passed — on to lesson ${idx + 1}\n`);
  } else {
    process.stdout.write(`\n> lesson ${idx} passed — that's every lesson; q to leave, or b to look back\n`);
  }
}

async function interactiveSession(lessons, state, home, sandbox) {
  const rl = readline.createInterface({ input: process.stdin, terminal: false });
  const lines = rl[Symbol.asyncIterator]();
  for (;;) {
    const idx = state.cursor;
    process.stdout.write(renderLesson(lessons[idx - 1], lessons.length, sandbox.sandboxDir, state.statuses[idx]));
    const step = await lines.next();
    if (step.done) break; // stdin closed: behave like `q`
    const line = step.value.trim();
    if (line === 'q') {
      process.stdout.write('\n(progress saved — run `flow tutorial` again to resume)\n');
      break;
    }
    if (isNavCommand(line)) applyNav(line, idx, lessons, state);
    else applyCommand(line, idx, lessons, sandbox, state);
    saveProgress(home, state);
  }
  rl.close();
  saveProgress(home, state);
}

// ─────────────────────────────────────────────────────────────────────────────
// CLI.
// ─────────────────────────────────────────────────────────────────────────────

function parseArgs(argv) {
  const out = { list: false, reset: false, lesson: null, sandbox: null };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--list') out.list = true;
    else if (a === '--reset') out.reset = true;
    else if (a === '--lesson') out.lesson = argv[++i];
    else if (a === '--sandbox') out.sandbox = argv[++i];
  }
  return out;
}

function resolveLessonArg(lessonArg, lessonCount) {
  const n = Number(lessonArg);
  if (!Number.isInteger(n) || n < 1 || n > lessonCount) {
    throw new TutorialError('LESSON_OUT_OF_RANGE', `lesson ${lessonArg} is out of range (1-${lessonCount})`);
  }
  return n;
}

async function run(argv, home) {
  const lessons = discoverLessons();
  const args = parseArgs(argv);

  if (args.reset) {
    resetProgress(home);
    process.stdout.write('flow tutorial: progress reset\n');
    return 0;
  }
  if (args.list) {
    const progress = loadProgress(home, lessons.length);
    process.stdout.write(renderList(lessons, progress.statuses));
    return 0;
  }

  const state = loadProgress(home, lessons.length);
  if (args.lesson !== null) state.cursor = resolveLessonArg(args.lesson, lessons.length);

  const sandbox = createSandbox(args.sandbox || state.sandboxDir);
  state.sandboxDir = sandbox.sandboxDir;
  saveProgress(home, state);

  await interactiveSession(lessons, state, home, sandbox);
  return 0;
}

function main() {
  const home = process.env.HOME || os.homedir() || '';
  run(process.argv.slice(2), home)
    .then((code) => process.exit(code))
    .catch((err) => {
      const code = err && err.code ? err.code : 'ERROR';
      process.stderr.write(`flow tutorial: ${code}: ${err.message}\n`);
      process.exit(1);
    });
}

if (require.main === module) main();

module.exports = { run };
