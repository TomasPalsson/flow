'use strict';

// router.js — flow v2's state machine (spec 004 K-C, research 11 §3.4).
//
// Every predicate is a file test. Nothing is remembered between calls: the
// position is recomputed from disk on every invocation, which is what makes
// /clear, a crash, a compaction and a git checkout self-healing.
//
// route() returns
//   { state, state_no, command, why, after, human_gate,
//     gates: { blocked, lint_error, unreachable_done, scan_failed, consecutive_calls },
//     feature: { dir, slug, route, base } | null,
//     wave:    { ids: [...], parallel: bool } | null }
//
// `command` is always one runnable token — a subcommand this plugin ships, a
// slash command it ships, or a git/gh command — EXCEPT on the two human
// gates (5, 9) and the checkpoint (7), where `human_gate` is true and the
// line is the instruction the user has to act on. test_next.sh asserts that
// split, so a prose "command" can never leak into a machine state.

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

// state_no is the row in research 11 §3.4. The 1x family shares row 1; the
// two sibling states that are not in the table borrow the row they preempt
// (loop-active preempts the 1x stops, prep preempts row 2's "here is the door").
const STATE_NO = {
  'scan-failed': 0,
  blocked: 1,
  disagreement: 1,
  looping: 1,
  invalid: 1,
  lying: 1,
  'loop-active': 1,
  'no-project': 2,
  'prep-interviewing': 2,
  'prep-ready': 2,
  ambiguous: 3,
  drafting: 4,
  unapproved: 5,
  building: 6,
  checkpoint: 7,
  gating: 8,
  unverified: 9,
  'stale-pass': 10,
  shippable: 11,
  shipped: 12,
  idle: 13,
};

// The states that end in more work by this session, so the turn should end
// with a /clear before the next one (spec 004 requirement 3).
const CLEAR_AFTER = ['drafting', 'building', 'checkpoint', 'gating', 'stale-pass', 'shippable'];

function safeRead(p) {
  try {
    return fs.readFileSync(p, 'utf8');
  } catch {
    return null;
  }
}

function isDir(p) {
  try {
    return fs.statSync(p).isDirectory();
  } catch {
    return false;
  }
}

function git(root, args) {
  const r = spawnSync('git', ['-C', root].concat(args), { encoding: 'utf8', timeout: 15000 });
  return { ok: r.status === 0, out: (r.stdout || '').trim(), err: (r.stderr || '').trim() };
}

// pluginScript(name) — <plugin>/scripts/<name>, or the deployed copy under
// ~/.claude/scripts. Returns null when neither exists (→ scan-failed).
function pluginScript(name, env) {
  const e = env || process.env;
  if (e.FLOW_SCRIPTS_DIR) {
    const only = path.join(e.FLOW_SCRIPTS_DIR, name);
    return fs.existsSync(only) ? only : null;
  }
  const home = e.HOME || '';
  const candidates = [
    path.resolve(__dirname, '..', '..', 'scripts', name),
    home ? path.join(home, '.claude', 'scripts', name) : null,
  ].filter(Boolean);
  for (const c of candidates) if (fs.existsSync(c)) return c;
  return null;
}

// runLint(root, tasksPath) -> { json } | { crash: <reason> }
function runLint(root, tasksPath, env) {
  const script = pluginScript('flow-lint', env);
  if (!script) return { crash: 'flow-lint is not installed beside this CLI' };
  const r = spawnSync('bash', [script, tasksPath, '--json'], {
    cwd: root,
    encoding: 'utf8',
    timeout: 60000,
  });
  const out = (r.stdout || '').trim();
  if (!out) {
    // Name the actual failure. A bare "produced no output" sent one debugging
    // session hunting a parse bug in flow-lint when the real answer was
    // ETIMEDOUT on a machine with very slow process spawning.
    const why = r.error
      ? `${r.error.code || r.error.message}${r.error.code === 'ETIMEDOUT' ? ` after 60s — run \`bash ${script} ${tasksPath} --json\` by hand to see where it stalls` : ''}`
      : (r.stderr || '').split('\n')[0] || `exit ${r.status}${r.signal ? ` (${r.signal})` : ''}`;
    return { crash: `flow-lint produced no output: ${why}` };
  }
  try {
    return { json: JSON.parse(out) };
  } catch {
    return { crash: `flow-lint emitted unparseable JSON (${out.slice(0, 120)})` };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Feature resolution: $FLOW_SPEC → .specs/.current → branch flow/<slug>
// ─────────────────────────────────────────────────────────────────────────────

function featureDirs(specsDir) {
  let entries;
  try {
    entries = fs.readdirSync(specsDir);
  } catch (e) {
    if (e.code === 'ENOENT') return { dirs: [] };
    return { error: e.code || 'EIO' };
  }
  return {
    dirs: entries.filter((e) => /^\d{3}-/.test(e) && isDir(path.join(specsDir, e))).sort(),
  };
}

function matchSlug(dirs, slug) {
  if (!slug) return null;
  return dirs.find((d) => d === slug) || dirs.find((d) => d.slice(4) === slug) || null;
}

function resolveFeature(root, branch, env) {
  const specsDir = path.join(root, '.specs');
  const found = featureDirs(specsDir);
  if (found.error) return { error: found.error };
  const dirs = found.dirs;
  const e = env || process.env;
  if (e.FLOW_SPEC) {
    const hit = matchSlug(dirs, e.FLOW_SPEC.trim());
    if (hit) return { dirs, slug: hit, via: '$FLOW_SPEC' };
    return { dirs, slug: null, via: '$FLOW_SPEC', miss: e.FLOW_SPEC.trim() };
  }
  // Stealth: .specs/.current lives in the store and is shared by every
  // worktree through the link, so a worktree on flow/<slug> would otherwise
  // route to whatever feature another worktree last made current. The
  // branch wins here only when it names a real feature dir.
  if (/^flow\//.test(branch || '') && require('./stealth.js').detect(root).active) {
    const hit = matchSlug(dirs, branch.replace(/^flow\//, ''));
    if (hit) return { dirs, slug: hit, via: `branch ${branch} (stealth)` };
  }
  const cur = safeRead(path.join(specsDir, '.current'));
  if (cur !== null) {
    const want = cur.split('\n')[0].trim();
    const hit = matchSlug(dirs, want);
    if (hit) return { dirs, slug: hit, via: '.specs/.current' };
    if (want) return { dirs, slug: null, via: '.specs/.current', miss: want };
  }
  if (/^flow\//.test(branch || '')) {
    const hit = matchSlug(dirs, branch.replace(/^flow\//, ''));
    if (hit) return { dirs, slug: hit, via: `branch ${branch}` };
  }
  return { dirs, slug: null, via: null };
}

// ─────────────────────────────────────────────────────────────────────────────
// .next-call-count — consecutive calls that computed the same state
// ─────────────────────────────────────────────────────────────────────────────

const COUNT_FILE = '.next-call-count';

function readCount(specsDir) {
  const raw = safeRead(path.join(specsDir, COUNT_FILE));
  if (raw === null) return { count: 0, hash: '' };
  const parts = raw.trim().split(/\s+/);
  const n = parseInt(parts[0], 10);
  return { count: Number.isFinite(n) && n >= 0 ? n : 0, hash: parts[1] || '' };
}

function writeCount(specsDir, count, hash) {
  try {
    fs.mkdirSync(specsDir, { recursive: true });
    fs.writeFileSync(path.join(specsDir, COUNT_FILE), `${count} ${hash}\n`);
  } catch { /* a read-only tree still routes; the loop guard just stops counting */ }
}

// resetCount is the receipt every state change writes — flow tick calls it too.
function resetCount(root) {
  writeCount(path.join(root, '.specs'), 0, '');
}

// ─────────────────────────────────────────────────────────────────────────────
// Sibling states: a prep waiting on its spec (docs/research/13 §5)
// ─────────────────────────────────────────────────────────────────────────────

// prepState(root, slug) -> a prep-* result for ONE feature dir, or null.
// K-C puts the prep states between rows 2 and 4, which means they must be
// reachable for the ACTIVE feature — not only when the whole repo is empty.
function prepState(root, slug, note) {
  const dir = path.join(root, '.specs', slug);
  if (!fs.existsSync(path.join(dir, 'PREP.md'))) return null;
  if (fs.existsSync(path.join(dir, 'spec.md'))) return null;
  const raw = safeRead(path.join(dir, 'PREP.md')) || '';
  const statusMatch = raw.match(/Status:\s*([^·\n]+)/);
  const qMatch = raw.match(/Questions:\s*(\d+)\s+of\s+(\d+)/);
  const status = statusMatch ? statusMatch[1].replace(/\s+-\s.*$/, '').trim() : '';
  const rel = path.join('.specs', slug);
  const feature = { dir: rel, slug, route: null, base: null };
  const more = note || '';
  if (/^interviewing/.test(status)) {
    return mk('prep-interviewing', '/flow:prep',
      `${rel}/PREP.md: interview ${qMatch ? qMatch[1] : '?'} of ${qMatch ? qMatch[2] : '?'} answered${more}`,
      { feature });
  }
  // "ready for spec", or a PREP.md with no Status: at all — either way the
  // next step is the spec, and saying the folder "is empty" would be a lie.
  return mk('prep-ready', '/flow:spec',
    `${rel}/PREP.md is written, no spec.md yet${status ? ` (status: ${status})` : ''}${more}`,
    { feature });
}

function findPrepWithoutSpec(root, branch, dirs) {
  const specsDir = path.join(root, '.specs');
  const hits = dirs.filter((e) => fs.existsSync(path.join(specsDir, e, 'PREP.md'))
    && !fs.existsSync(path.join(specsDir, e, 'spec.md')));
  if (hits.length === 0) return null;
  const slug = (branch || '').replace(/^flow\//, '');
  const pick = hits.find((e) => e.slice(4) === slug) || hits[hits.length - 1];
  const raw = safeRead(path.join(specsDir, pick, 'PREP.md')) || '';
  const statusMatch = raw.match(/Status:\s*([^·\n]+)/);
  const qMatch = raw.match(/Questions:\s*(\d+)\s+of\s+(\d+)/);
  return {
    dir: path.join('.specs', pick),
    status: statusMatch ? statusMatch[1].replace(/\s+-\s.*$/, '').trim() : '',
    asked: qMatch ? qMatch[1] : null,
    budget: qMatch ? qMatch[2] : null,
    count: hits.length,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// The completeness scan (state 1b): report, never switch.
// ─────────────────────────────────────────────────────────────────────────────

const APPROVED_RE = /^Approved:\s*\d{4}-\d{2}-\d{2}/m;
const UNCHECKED_RE = /^- \[ \] (?:T|CHK)\d{3}\b/m;

function otherApprovedInFlight(root, dirs, activeSlug) {
  const out = [];
  for (const d of dirs) {
    if (d === activeSlug) continue;
    const raw = safeRead(path.join(root, '.specs', d, 'TASKS.md'));
    if (raw === null) continue;
    if (APPROVED_RE.test(raw) && UNCHECKED_RE.test(raw)) {
      const open = (raw.match(/^- \[ \] (?:T|CHK)\d{3}\b/gm) || []).length;
      out.push({ slug: d, open });
    }
  }
  return out;
}

// ─────────────────────────────────────────────────────────────────────────────
// PASS-<sha>.md — the machine half of done, self-invalidating by design
// ─────────────────────────────────────────────────────────────────────────────

function passFiles(featureDir) {
  try {
    return fs.readdirSync(featureDir).filter((f) => /^PASS-[0-9a-f]{4,40}\.md$/.test(f)).sort();
  } catch {
    return [];
  }
}

// prNumber(root, branch) -> "41" | null. gh is optional: no gh, no network,
// or any failure all mean "no PR", which routes to 11 (open one) not 12.
function prNumber(root, branch) {
  if (!branch || branch === 'HEAD') return null;
  const r = spawnSync('gh', ['pr', 'view', branch, '--json', 'number', '-q', '.number'], {
    cwd: root,
    encoding: 'utf8',
    timeout: 15000,
  });
  if (r.status !== 0) return null;
  const n = (r.stdout || '').trim();
  return /^\d+$/.test(n) ? n : null;
}

// ─────────────────────────────────────────────────────────────────────────────
// route(root, ctx, opts) — the state machine
// ─────────────────────────────────────────────────────────────────────────────

// danglingStealthLink(st, specsDir) -> a scan-failed result when a stealth
// link's store is gone (featureDirs maps that ENOENT to `[]`, which would
// otherwise silently route no-project), else null.
function danglingStealthLink(st, specsDir) {
  if (!st.active || fs.existsSync(specsDir)) return null;
  return mk('scan-failed', 'flow doctor',
    `STOP: .specs links to ${st.store}/.specs, which does not exist — restore the store or re-run flow stealth ${st.store}`);
}

// withStealthHint(r, st, root) -> r, with the no-project stealth suggestion
// appended when this repo looks public and is not already stealth.
function withStealthHint(r, st, root) {
  if (st.active) return r;
  const reasons = require('./stealth.js').publicSignals(root);
  if (!reasons.length) return r;
  r.stealth.suggest = true;
  r.stealth.reasons = reasons;
  r.why += ` · this repo looks public (${reasons.join(', ')}) — /flow:spec --stealth keeps the specs out of it`;
  return r;
}

function mk(state, command, why, extra) {
  return Object.assign({
    state,
    state_no: STATE_NO[state],
    command,
    why,
    after: CLEAR_AFTER.indexOf(state) !== -1 ? '/clear' : null,
    human_gate: false,
    feature: null,
    wave: null,
  }, extra || {});
}

function route(root, ctx, opts) {
  const o = opts || {};
  const env = o.env || process.env;
  const branch = ctx.branch || '';
  const specsDir = path.join(root, '.specs');
  const st = require('./stealth.js').detect(root);
  const gates = {
    blocked: false,
    lint_error: false,
    unreachable_done: false,
    scan_failed: false,
    consecutive_calls: 0,
  };
  const done = (r) => {
    r.gates = gates;
    r.stealth = { active: st.active, store: st.store, suggest: false, reasons: [] };
    return r;
  };

  // ── 0 · scan-failed. Refusing to report clean is the whole point of row 0:
  // today `terraform` reports clean-no-flow while spec-gate denies every edit.
  const found = featureDirs(specsDir);
  if (found.error) {
    gates.scan_failed = true;
    return done(mk('scan-failed', 'flow doctor',
      `STOP: cannot read ${specsDir} (${found.error}) — refusing to report clean`));
  }
  const dangling = danglingStealthLink(st, specsDir);
  if (dangling) { gates.scan_failed = true; return done(dangling); }
  const dirs = found.dirs;

  // ── 1a · blocked. A presence test no fenced example or quoted Ruling: can fake.
  const blockedPath = path.join(specsDir, 'BLOCKED.md');
  if (fs.existsSync(blockedPath)) {
    gates.blocked = true;
    if (!o.force) {
      const first = (safeRead(blockedPath) || '').split('\n').find((l) => l.trim()) || '';
      return done(mk('blocked', '/flow:next --force',
        `STOP: .specs/BLOCKED.md exists${first ? ` — ${first.trim()}` : ''}. Read it, fix it, delete it; the command shown bypasses it`));
    }
  }

  const resolved = resolveFeature(root, branch, env);
  const activeSlug = resolved.slug;
  const hasAnyWork = dirs.some((d) => fs.existsSync(path.join(specsDir, d, 'TASKS.md'))
    || fs.existsSync(path.join(specsDir, d, 'spec.md')));

  // ── prep sibling · a PREP.md with no spec.md sits between rows 2 and 4.
  if (!hasAnyWork) {
    const prep = findPrepWithoutSpec(root, branch, dirs);
    if (prep) {
      const more = prep.count > 1 ? ` (${prep.count} preps without a spec; newest shown)` : '';
      const r = prepState(root, path.basename(prep.dir), more);
      if (r) return done(r);
    }
    // ── 2 · no project. A dir new-spec just made is empty, not idle — say so
    // rather than reporting "nothing unchecked anywhere" at someone who is
    // three seconds into a feature.
    if (dirs.length === 0) {
      return withStealthHint(done(mk('no-project', '/flow:spec', 'nothing in flight — no .specs/NNN-slug/ on disk')), st, root);
    }
    if (activeSlug) {
      return done(mk('no-project', '/flow:spec',
        `.specs/${activeSlug}/ is empty — no spec.md and no TASKS.md yet`,
        { feature: { dir: path.join('.specs', activeSlug), slug: activeSlug, route: null, base: null } }));
    }
    // ── 13 · idle: features on disk, none of them holding any work
    return done(mk('idle', '/flow:spec',
      `nothing unchecked anywhere (${dirs.length} feature ${dirs.length === 1 ? 'dir' : 'dirs'} on disk, none with a spec or tasks)`));
  }

  // ── 3 · ambiguous. The pointer is authoritative and the router never guesses.
  if (!activeSlug) {
    const miss = resolved.miss ? ` (${resolved.via} names "${resolved.miss}", which is not on disk)` : '';
    const pick = dirs[dirs.length - 1];
    return done(mk('ambiguous', `flow use ${pick}`,
      `${dirs.length} feature ${dirs.length === 1 ? 'dir' : 'dirs'} on disk, no .specs/.current and no matching flow/<slug> branch${miss} — pick one`));
  }

  const featureDir = path.join(specsDir, activeSlug);
  const tasksPath = path.join(featureDir, 'TASKS.md');
  const feature = { dir: path.join('.specs', activeSlug), slug: activeSlug, route: null, base: null };

  // ── 1b · the completeness scan. gsd reports and halts; it never switches.
  const others = otherApprovedInFlight(root, dirs, activeSlug);
  if (others.length && !o.force) {
    const list = others.map((x) => `${x.slug} (${x.open} open)`).join(', ');
    return done(mk('disagreement', `flow use ${others[0].slug}`,
      `${others.length} other approved ${others.length === 1 ? 'feature has' : 'features have'} unchecked tasks: ${list}. Active is ${activeSlug} (${resolved.via}). Finish or archive them, switch with the command shown, or re-run with --force to carry on here`,
      { feature }));
  }

  // ── 4 · drafting
  if (!fs.existsSync(tasksPath)) {
    if (!fs.existsSync(path.join(featureDir, 'spec.md'))) {
      // A PREP.md is work: /flow:prep wrote it and /flow:spec consumes it.
      // This used to be gated on the WHOLE repo having no spec anywhere, so
      // in a repo with more than one feature the prep states could never fire
      // and the router called a folder holding a finished interview "empty".
      const prep = prepState(root, activeSlug, '');
      if (prep) return done(prep);
      return done(mk('no-project', '/flow:spec',
        `${feature.dir} is empty — no PREP.md, no spec.md and no TASKS.md`, { feature }));
    }
    const notes = safeRead(path.join(featureDir, 'NOTES.md'));
    const answered = notes ? (notes.match(/^- /gm) || []).length : 0;
    return done(mk('drafting', '/flow:next',
      `resuming ${activeSlug}; spec.md written, TASKS.md not yet${answered ? ` (${answered} discovery notes in NOTES.md)` : ''}`,
      { feature }));
  }

  // ── 1d/1e · the lint. A crash is row 0, not a clean report.
  const lint = runLint(root, tasksPath, env);
  if (lint.crash) {
    gates.scan_failed = true;
    return done(mk('scan-failed', 'flow doctor',
      `STOP: ${lint.crash} — refusing to report clean`, { feature }));
  }
  const L = lint.json;
  feature.route = L.header.route || null;
  feature.base = L.header.base || null;

  if (L.errors && L.errors.length) {
    gates.lint_error = true;
    const lying = L.errors.filter((e) => /^(done-|id-vanished)/.test(e.rule));
    const first = (lying.length ? lying : L.errors)[0];
    if (lying.length) {
      gates.unreachable_done = true;
      return done(mk('lying', 'flow lint',
        `STOP: ${first.message}. fix: ${first.fix}`, { feature }));
    }
    return done(mk('invalid', 'flow lint',
      `${feature.dir}/TASKS.md:${first.line} ${first.message}. fix: ${first.fix}`, { feature }));
  }

  // ── 5 · unapproved. HARD GATE — the first of the only two stored human facts.
  if (!L.header.approved) {
    const n = (L.tasks || []).filter((t) => t.kind === 'task').length;
    return done(mk('unapproved', `reply "approved" — full plan: ${feature.dir}/TASKS.md`,
      `${n} tasks planned on route ${feature.route || 'unset'}; nothing runs until you approve`,
      { feature, human_gate: true }));
  }

  const tasks = L.tasks || [];
  const open = tasks.filter((t) => t.state === 'open');
  const openWork = open.filter((t) => t.kind !== 'gate');
  const openGates = open.filter((t) => t.kind === 'gate');
  const totalWork = tasks.filter((t) => t.kind !== 'gate').length;
  const doneWork = totalWork - openWork.length;

  // ── 7 · checkpoint. The router prints the CHK line's own text, verbatim.
  if (openWork.length && openWork[0].kind === 'checkpoint') {
    const c = openWork[0];
    return done(mk('checkpoint', c.description,
      `${c.id} — ${c.verify} (${doneWork} of ${totalWork} done)`,
      { feature, human_gate: true }));
  }

  // ── 6 · building. One wave at a time; wave N+1 never starts before N reports.
  if (openWork.length) {
    const waves = L.waves || [];
    const openIds = {};
    for (const t of openWork) openIds[t.id] = true;
    const nextWave = waves.map((w) => w.filter((id) => openIds[id])).find((w) => w.length) || [openWork[0].id];
    const inWave = openWork.filter((t) => nextWave.indexOf(t.id) !== -1);
    const parallelWave = inWave.length > 1 && inWave.every((t) => t.parallel);
    const verify = inWave[0] ? inWave[0].verify : '';
    return done(mk('building', '/flow:next',
      `wave ${nextWave.join(', ')} — verify: ${verify} (${doneWork} of ${totalWork} done)`,
      { feature, wave: { ids: nextWave, parallel: parallelWave } }));
  }

  // ── 8/9/10 · the gates and the two halves of done
  const head = git(root, ['rev-parse', '--short', 'HEAD']);
  const headSha = head.ok ? head.out : '';
  const passes = passFiles(featureDir);
  const passForHead = headSha ? passes.indexOf(`PASS-${headSha}.md`) !== -1 : false;
  const verified = !!L.header.verified;

  if (!passForHead) {
    const newest = passes.length ? passes[passes.length - 1] : null;
    if (verified && newest) {
      const since = git(root, ['rev-list', '--count', `${newest.replace(/^PASS-|\.md$/g, '')}..HEAD`]);
      return done(mk('stale-pass', '/flow:next',
        `${newest} is not HEAD (${since.ok ? since.out : 'some'} commits since) — the gates have to run again`,
        { feature }));
    }
    const gateList = openGates.length ? openGates.map((g) => g.id).join(', ') : 'none unchecked';
    return done(mk('gating', '/flow:next',
      `${doneWork} of ${totalWork} tasks done, gates open: ${gateList} — run them, then write PASS-${headSha || '<sha>'}.md`,
      { feature }));
  }

  // ── 9 · unverified. HARD GATE — the second stored human fact.
  if (!verified) {
    return done(mk('unverified', `read ${feature.dir}/verify/, reply "approved"`,
      `PASS-${headSha}.md is green for this tree; a human has not looked yet`,
      { feature, human_gate: true }));
  }

  // ── 11/12 · ship, then archive
  const pr = prNumber(root, branch);
  if (!pr) {
    return done(mk('shippable', '/flow:next',
      `verified at ${headSha}, no PR on ${branch || 'this branch'} — opening it`, { feature }));
  }
  return done(mk('shipped', 'gh pr view --web',
    `PR #${pr}; merge it, then /flow:next archives ${feature.dir}`, { feature }));
}

// routeWithCount(root, ctx, opts) — route(), then row 1c. The counter is
// updated AFTER the state is computed, so the hash it compares is the state
// the router would have printed with no loop guard at all.
function routeWithCount(root, ctx, opts) {
  const o = opts || {};
  const r = route(root, ctx, o);
  const specsDir = path.join(root, '.specs');
  const hash = [r.state, r.feature ? r.feature.slug : '', r.wave ? r.wave.ids.join('+') : '', r.command].join('|')
    .replace(/[^A-Za-z0-9|+:/._-]/g, '').slice(0, 200);
  const prev = readCount(specsDir);
  // count:false — a hook, the status line or flow doctor READS the counter as
  // data without moving it. Only a real `flow next` turn counts as a call.
  if (o.count === false) {
    r.gates.consecutive_calls = prev.hash === hash ? prev.count : 0;
    return r;
  }
  const count = prev.hash === hash ? prev.count + 1 : 1;
  writeCount(specsDir, count, hash);
  r.gates.consecutive_calls = count;
  if (count >= 5 && !o.force && !r.human_gate) {
    return Object.assign({}, r, {
      state: 'looping',
      state_no: STATE_NO.looping,
      command: '/flow:next --force',
      why: `STOP: ${count} consecutive flow next calls with no state change (still ${r.state}: ${r.why}). Something is stuck — the command shown bypasses this`,
      after: null,
    });
  }
  return r;
}

module.exports = {
  route,
  routeWithCount,
  resolveFeature,
  resetCount,
  featureDirs,
  runLint,
  pluginScript,
  STATE_NO,
  CLEAR_AFTER,
};
