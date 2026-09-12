// statusline.js — the badge table, tones, elision, cache read/write, and the
// render functions for `flow statusline` (spec 008-flow-statusline).
//
// Layer 1: node built-ins only. Never imports lib/router.js or
// child_process — this module is handed a cache entry, it never fetches
// one, and it never spawns anything. Every function here is synchronous
// and, per the render/cache boundary contracts, never throws.

const fs = require('fs');
const path = require('path');
const os = require('os');
const crypto = require('crypto');

// ── Tones ────────────────────────────────────────────────────────────────
// Four-entry palette (muted, warn, error, ok) plus `info`, plus `reset` to
// close an escape sequence. Deliberately duplicated from bin/flow's `C` —
// see design.md §6; do not hoist or import that constant here.
const TONES = {
  muted: '\x1b[2m',
  info: '\x1b[36m',
  warn: '\x1b[33m',
  error: '\x1b[31m',
  ok: '\x1b[32m',
  reset: '\x1b[0m',
};

function withTone(text, toneName, opts) {
  if (!opts || !opts.color) return text;
  const on = TONES[toneName] || '';
  return on ? on + text + TONES.reset : text;
}

// ── Badge table — spec §4.2, literal, all 21 rows ──────────────────────────
const BADGES = {
  'scan-failed': { glyph: '⚠', label: 'scan failed', tone: 'error' },
  blocked: { glyph: '⛔', label: 'blocked', tone: 'error' },
  disagreement: { glyph: '⛔', label: 'disagreement', tone: 'error' },
  looping: { glyph: '⛔', label: 'looping', tone: 'error' },
  invalid: { glyph: '⛔', label: 'invalid tasks', tone: 'error' },
  lying: { glyph: '⛔', label: 'unreachable done', tone: 'error' },
  'loop-active': { glyph: '◍', label: 'loop running', tone: 'info' },
  'no-project': { glyph: '○', label: 'no project', tone: 'muted' },
  'prep-interviewing': { glyph: '✎', label: 'prep', tone: 'muted' },
  'prep-ready': { glyph: '✎', label: 'prep ready', tone: 'info' },
  ambiguous: { glyph: '?', label: 'pick a feature', tone: 'warn' },
  drafting: { glyph: '✎', label: 'drafting', tone: 'info' },
  unapproved: { glyph: '✋', label: 'approve', tone: 'warn' },
  building: { glyph: '▸', label: 'building', tone: 'info' },
  checkpoint: { glyph: '✋', label: 'checkpoint', tone: 'warn' },
  gating: { glyph: '⚙', label: 'gates', tone: 'info' },
  unverified: { glyph: '✋', label: 'verify', tone: 'warn' },
  'stale-pass': { glyph: '⚠', label: 'stale pass', tone: 'warn' },
  shippable: { glyph: '⇧', label: 'ship', tone: 'ok' },
  shipped: { glyph: '✓', label: 'shipped', tone: 'ok' },
  idle: { glyph: '○', label: 'idle', tone: 'muted' },
};

// Fallback for a state name absent from BADGES — a router that grows a
// 22nd state renders this, verbatim state name as the label, never a
// blank line. `label: null` signals "use the state name verbatim".
const UNKNOWN_BADGE = { glyph: '●', label: null, tone: 'muted' };

function badgeFor(state) {
  const found = BADGES[state];
  if (found) return found;
  return { glyph: UNKNOWN_BADGE.glyph, label: state, tone: UNKNOWN_BADGE.tone };
}

// ── Elision ─────────────────────────────────────────────────────────────
function elide(slug, max) {
  if (typeof slug !== 'string') return '';
  if (max <= 0) return '';
  if (slug.length <= max) return slug;
  if (max === 1) return '…';
  const keep = max - 1;
  const head = Math.ceil(keep / 2);
  const tail = Math.floor(keep / 2);
  return slug.slice(0, head) + '…' + (tail ? slug.slice(slug.length - tail) : '');
}

// ── Model segment (FR-01) ──────────────────────────────────────────────────
function modelSegment(input, opts) {
  try {
    const i = input || {};
    const parts = [];
    if (i.model && typeof i.model.display_name === 'string' && i.model.display_name) {
      parts.push(i.model.display_name);
    }
    const hasRateLimits = Object.prototype.hasOwnProperty.call(i, 'rate_limits');
    parts.push(hasRateLimits ? '✨ MAX' : '⚡ API');
    if (i.context_window && typeof i.context_window.used_percentage === 'number') {
      parts.push('📊 ctx ' + i.context_window.used_percentage + '%');
    }
    return parts.join(' | ');
  } catch (e) {
    return '';
  }
}

// ── Flow segment (FR-02, FR-03, FR-04, FR-12, FR-16) ───────────────────────
const FLOW_MARKER = '🌊 ';
const SEPARATOR = ' | ';
const FLOW_SEGMENT_MAX_WIDTH = 40;

function flowSegment(entry, opts) {
  try {
    if (!entry || !entry.result || !entry.result.state) return '';
    const o = opts || {};
    const result = entry.result;
    const badge = badgeFor(result.state);
    let label = badge.label;
    // The router publishes the wave's task ids but no wave ordinal, so the
    // badge names what is running rather than inventing an index (NOTES.md).
    if (result.state === 'building' && result.wave && Array.isArray(result.wave.ids) && result.wave.ids.length) {
      const ids = result.wave.ids;
      label = ids.length > 1 ? ids[0] + ' +' + (ids.length - 1) : ids[0];
    }
    const stale = typeof entry.at === 'number' && (Date.now() - entry.at) > CACHE_STALE_MS ? '~' : '';
    const badgeText = badge.glyph + ' ' + label;
    const slug = result.feature && result.feature.slug ? result.feature.slug : '';

    let slugPart = '';
    if (slug) {
      const fixedWidth = FLOW_MARKER.length + SEPARATOR.length + badgeText.length + stale.length;
      const budget = FLOW_SEGMENT_MAX_WIDTH - fixedWidth;
      slugPart = budget > 0 ? elide(slug, budget) : '';
    }

    return FLOW_MARKER + (slugPart ? slugPart + SEPARATOR : '') + withTone(badgeText, badge.tone, o) + stale;
  } catch (e) {
    return '';
  }
}

// ── The whole line ──────────────────────────────────────────────────────
function renderLine(input, entry, opts) {
  const model = modelSegment(input, opts);
  let flow = '';
  try {
    flow = flowSegment(entry, opts);
  } catch (e) {
    flow = '';
  }
  return flow ? model + SEPARATOR + flow : model;
}

// ── The cache (spec §5, design.md §5) ──────────────────────────────────────
const CACHE_FRESH_MS = 5000;
const CACHE_STALE_MS = 60000;

function cachePath(repoRoot) {
  const hash = crypto.createHash('sha1').update(String(repoRoot)).digest('hex');
  return path.join(os.tmpdir(), 'flow-statusline', hash + '.json');
}

function readCache(repoRoot) {
  try {
    const raw = fs.readFileSync(cachePath(repoRoot), 'utf8');
    const entry = JSON.parse(raw);
    if (!entry || typeof entry !== 'object' || !entry.result || typeof entry.at !== 'number') return null;
    return entry;
  } catch (e) {
    return null;
  }
}

function writeCache(repoRoot, result) {
  try {
    const target = cachePath(repoRoot);
    fs.mkdirSync(path.dirname(target), { recursive: true });
    const tmp = target + '.' + process.pid + '.tmp';
    fs.writeFileSync(tmp, JSON.stringify({ result: result, at: Date.now() }));
    fs.renameSync(tmp, target);
  } catch (e) {
    // writeCache never throws — a failed write leaves the previous entry in place.
  }
}

// ── Installer snippet (used by bin/flow's --install / --print) ────────────
const SETTINGS_SNIPPET = { type: 'command', command: 'flow statusline' };

module.exports = {
  BADGES,
  UNKNOWN_BADGE,
  TONES,
  renderLine,
  modelSegment,
  flowSegment,
  elide,
  cachePath,
  readCache,
  writeCache,
  CACHE_FRESH_MS,
  CACHE_STALE_MS,
  SETTINGS_SNIPPET,
};
