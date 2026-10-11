#!/usr/bin/env node
// shot.mjs - screenshot an HTML page or an SVG to a PNG with headless Chrome.
//
// Usage:  node shot.mjs <file.html|file.svg> <out.png> [--width 390] [--height <px>] [--full]
//   --width N    window width in px (default 390)
//   --height N   window height in px (default 844, the first screen)
//   --full       tall window (9000 px at width 390, 6000 otherwise) unless --height is given;
//                Chrome cannot auto-size, so the bottom may be blank space
// Chrome lookup: env CHROME, then google-chrome-stable, google-chrome, chromium,
// chromium-browser on PATH, the macOS app, then ~/.cache/ms-playwright/chromium-*.
// An .svg input is wrapped in a page with neutral light tokens (the CSS variables
// the SVG drawing rules use) so var(--ink) etc. resolve.
// Also importable: export findChrome().
//
// Exit codes: 0 ok, 1 unused, 2 bad args, 3 data/IO error (no Chrome, missing input, Chrome failed).

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';

const MAC_CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

function isExec(p) {
  try {
    fs.accessSync(p, fs.constants.X_OK);
    return fs.statSync(p).isFile();
  } catch {
    return false;
  }
}

/** Returns the absolute path of a Chrome binary, or null if none is found.
 *  Throws if CHROME is set but is not an executable file (no silent fallback). */
export function findChrome() {
  if (process.env.CHROME) {
    if (!isExec(process.env.CHROME)) {
      throw new Error(`CHROME is set to "${process.env.CHROME}" but that is not an executable file`);
    }
    return process.env.CHROME;
  }
  const dirs = (process.env.PATH || '').split(path.delimiter).filter(Boolean);
  for (const name of ['google-chrome-stable', 'google-chrome', 'chromium', 'chromium-browser']) {
    for (const d of dirs) {
      const p = path.join(d, name);
      if (isExec(p)) return p;
    }
  }
  if (isExec(MAC_CHROME)) return MAC_CHROME;
  const pw = path.join(os.homedir(), '.cache', 'ms-playwright');
  let entries = [];
  try {
    entries = fs.readdirSync(pw).filter((e) => e.startsWith('chromium-')).sort().reverse();
  } catch {
    /* no playwright cache */
  }
  for (const e of entries) {
    for (const sub of ['chrome-linux', 'chrome-linux64']) {
      const p = path.join(pw, e, sub, 'chrome');
      if (isExec(p)) return p;
    }
  }
  return null;
}

export const TOKENS = '--paper:#fbfaf7;--card:#ffffff;--ink:#1d1b18;--muted:#5f5a52;--line:#d9d4ca;--accent:#c2410c;--accent-soft:#fde6d8;--font:system-ui,sans-serif;--mono:ui-monospace,monospace;';

function wrapSvg(svgText, width) {
  const svg = svgText.replace(/^\s*<\?xml[\s\S]*?\?>/, '');
  return `<!doctype html><html><head><meta charset="utf-8"><style>
:root{${TOKENS}}
html,body{margin:0;padding:0}
body{background:var(--paper);color:var(--ink);font-family:var(--font)}
.wrap{width:${width}px}
.wrap svg{width:100%;height:auto;display:block}
</style></head><body><div class="wrap">${svg}</div></body></html>`;
}

function die(code, msg) {
  process.stderr.write(`shot.mjs: ${msg}\n`);
  process.exit(code);
}

function parseArgs(argv) {
  const pos = [];
  const o = { width: 390, height: null, full: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--full') o.full = true;
    else if (a === '--width' || a === '--height') {
      const v = Number(argv[++i]);
      if (!Number.isInteger(v) || v <= 0) die(2, `${a} needs a positive integer`);
      o[a.slice(2)] = v;
    } else if (a.startsWith('--')) die(2, `unknown flag ${a}`);
    else pos.push(a);
  }
  if (pos.length !== 2) die(2, 'usage: node shot.mjs <file.html|file.svg> <out.png> [--width 390] [--height <px>] [--full]');
  return { ...o, input: path.resolve(pos[0]), out: path.resolve(pos[1]) };
}

function main() {
  const o = parseArgs(process.argv.slice(2));
  if (!fs.existsSync(o.input)) die(3, `input not found: ${o.input}`);
  let chrome;
  try {
    chrome = findChrome();
  } catch (e) {
    die(3, e.message);
  }
  if (!chrome) die(3, 'no Chrome found; set CHROME');

  const height = o.height ?? (o.full ? (o.width <= 600 ? 9000 : 6000) : 844);
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'bshot-'));
  let page = o.input;
  if (/\.svg$/i.test(o.input)) {
    page = path.join(tmp, 'wrap.html');
    fs.writeFileSync(page, wrapSvg(fs.readFileSync(o.input, 'utf8'), o.width));
  } else {
    // A web-font <link> can stall headless Chrome until the timeout (seen with Google Fonts);
    // shoot a copy without external stylesheets. The page inlines its SVGs, so nothing else is lost.
    page = path.join(tmp, 'page.html');
    fs.writeFileSync(page, fs.readFileSync(o.input, 'utf8')
      .replace(/<link\b[^>]*href=["']https?:[^>]*>/gi, '').replace(/@import\s+url\(["']?https?:[^)]*\)\s*;?/gi, ''));
  }
  fs.mkdirSync(path.dirname(o.out), { recursive: true });
  fs.rmSync(o.out, { force: true });
  const r = spawnSync(
    chrome,
    [
      '--headless=new', '--disable-gpu', '--no-sandbox', '--hide-scrollbars',
      `--user-data-dir=${path.join(tmp, 'profile')}`,
      '--virtual-time-budget=8000', `--window-size=${o.width},${height}`,
      `--screenshot=${o.out}`, pathToFileURL(page).href,
    ],
    { encoding: 'utf8', timeout: 90000 },
  );
  fs.rmSync(tmp, { recursive: true, force: true });
  let size = 0;
  try {
    size = fs.statSync(o.out).size;
  } catch {
    /* missing */
  }
  if (size <= 0) die(3, `Chrome produced no PNG (exit ${r.status}${r.error ? `, ${r.error.message}` : ''}):\n${r.stderr}`);
  process.stdout.write(`${o.out} (${size} bytes, ${o.width}x${height})\n`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main();
