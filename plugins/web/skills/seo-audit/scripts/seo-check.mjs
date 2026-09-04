#!/usr/bin/env node
// seo-check.mjs — zero-dependency Node.js SEO audit CLI.
// Node 18+, ESM, stdlib only (node:https, node:http, node:zlib, node:url, node:fs, node:dns, node:process).
// No npm packages, no global fetch — redirect hops are captured manually via https.request/http.request.

import https from 'node:https';
import http from 'node:http';
import zlib from 'node:zlib';
import { URL, URLSearchParams } from 'node:url';
import { lookup as dnsLookup } from 'node:dns/promises';
import process from 'node:process';

const TOOL_VERSION = '1.0.0';
const DEFAULT_UA = 'seo-check/1.0 (+SEO audit tool; Node)';
const GOOGLEBOT_UA = 'Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)';
const ROBOTS_MAX_BYTES = 500 * 1024; // RFC 9309: parsers MUST accept at least 500 KiB
const SITEMAP_MAX_BYTES = 52428800; // sitemaps.org protocol limit (50 MB uncompressed)
const SITEMAP_MAX_URLS = 50000;
const SITEMAP_FETCH_BUDGET = 10; // cap on total sitemap files fetched across a recursive sitemapindex walk
const PAGE_BODY_CAP = 5 * 1024 * 1024; // 5 MB cap on generic page fetches

class UsageError extends Error {}

const MANDATORY_LIMITATIONS = [
  'Rendered DOM after JavaScript execution (findings above are raw-HTML only)',
  'Confirmed Google indexation status (requires Search Console access to a verified property)',
  'Real user Core Web Vitals beyond what CrUX reports; no local paint timing',
  'JS-injected JSON-LD, titles, or canonicals',
  'Client-side redirects (router.push / window.location)',
  'Console errors, broken interactivity, visual layout',
];

// ============================================================================
// CLI
// ============================================================================

function printHelp() {
  console.log(`seo-check <url> [options]

Options:
  --json                Output machine-readable JSON instead of human report
  --robots              Only run robots.txt analysis
  --sitemap             Fetch and analyze sitemaps (from robots.txt + /sitemap.xml)
  --ai-bots             Test robots.txt against the AI/search bot roster
  --crux <apikey>       Fetch Core Web Vitals field data from CrUX API
  --psi <apikey>        Fetch PageSpeed Insights lab data
  --ua <string>         Override user-agent (default: identifiable custom UA)
  --compare-googlebot   Second fetch with a Googlebot-like UA, diff for cloaking
  --timeout <ms>        Per-request timeout (default 15000)
  --max-redirects <n>   Default 10
  --check-path <path>   Evaluate the robots.txt verdict for this path (default: the URL's own path)
  --as-ua <token>       Evaluate the robots.txt verdict as this bot token (e.g. Googlebot, GPTBot)
  --help                Show this help

Exit codes: 0 = completed, 1 = target unreachable/fatal, 2 = usage error.`);
}

function parseArgs(argv) {
  const opts = {
    json: false, robotsOnly: false, sitemap: false, aiBots: false,
    cruxKey: null, psiKey: null, ua: DEFAULT_UA, compareGooglebot: false,
    timeout: 15000, maxRedirects: 10, help: false, url: null,
  };
  const rest = [];
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    switch (a) {
      case '--json': opts.json = true; break;
      case '--robots': opts.robotsOnly = true; break;
      case '--sitemap': opts.sitemap = true; break;
      case '--ai-bots': opts.aiBots = true; break;
      case '--compare-googlebot': opts.compareGooglebot = true; break;
      case '--help': case '-h': opts.help = true; break;
      case '--crux': {
        const v = argv[++i];
        if (v === undefined) throw new UsageError('--crux requires an API key argument');
        opts.cruxKey = v; break;
      }
      case '--psi': {
        const v = argv[++i];
        if (v === undefined) throw new UsageError('--psi requires an API key argument');
        opts.psiKey = v; break;
      }
      case '--ua': {
        const v = argv[++i];
        if (v === undefined) throw new UsageError('--ua requires a value');
        opts.ua = v; break;
      }
      case '--timeout': {
        const v = Number(argv[++i]);
        if (!Number.isFinite(v) || v <= 0) throw new UsageError('--timeout requires a positive number (ms)');
        opts.timeout = v; break;
      }
      case '--max-redirects': {
        const v = Number(argv[++i]);
        if (!Number.isFinite(v) || v < 0) throw new UsageError('--max-redirects requires a non-negative integer');
        opts.maxRedirects = v; break;
      }
      // Evaluate the robots.txt verdict for a path other than the target URL's own path,
      // so an auditor can ask "is /admin blocked?" without fetching /admin.
      case '--check-path': {
        const v = argv[++i];
        if (v === undefined) throw new UsageError('--check-path requires a path (e.g. /admin)');
        opts.checkPath = v.startsWith('/') ? v : `/${v}`; break;
      }
      // Evaluate the robots.txt verdict AS a named bot token (e.g. Googlebot, GPTBot).
      // Distinct from --ua, which changes the user-agent actually sent on the wire.
      case '--as-ua': {
        const v = argv[++i];
        if (v === undefined) throw new UsageError('--as-ua requires a user-agent token (e.g. Googlebot)');
        opts.asUa = v; break;
      }
      default:
        if (a.startsWith('--')) throw new UsageError(`Unknown option: ${a}`);
        rest.push(a);
    }
  }
  if (rest.length) opts.url = rest[0];
  return opts;
}

function normalizeTargetUrl(raw) {
  let candidate = raw;
  if (!/^https?:\/\//i.test(candidate)) candidate = 'https://' + candidate;
  return new URL(candidate).href; // WHATWG URL normalizes IDN hosts to punycode automatically
}

// ============================================================================
// UTIL
// ============================================================================

const ENTITY_MAP = {
  amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ',
  copy: '©', reg: '®', trade: '™', mdash: '—', ndash: '–',
  hellip: '…', rsquo: '’', lsquo: '‘', rdquo: '”', ldquo: '“',
};

function decodeEntities(str) {
  if (!str) return str;
  return str.replace(/&(#x?[0-9a-fA-F]+|[a-zA-Z]+);/g, (whole, ent) => {
    if (ent[0] === '#') {
      const isHex = ent[1] === 'x' || ent[1] === 'X';
      const code = parseInt(isHex ? ent.slice(2) : ent.slice(1), isHex ? 16 : 10);
      if (Number.isNaN(code)) return whole;
      try { return String.fromCodePoint(code); } catch { return whole; }
    }
    return Object.prototype.hasOwnProperty.call(ENTITY_MAP, ent) ? ENTITY_MAP[ent] : whole;
  });
}

function stripTagsToText(html) {
  return html.replace(/<[^>]*>/g, ' ');
}

function charsetFromContentType(ct) {
  const m = /charset\s*=\s*"?([\w-]+)"?/i.exec(ct || '');
  if (!m) return 'utf8';
  const c = m[1].toLowerCase();
  if (c === 'utf-8' || c === 'utf8') return 'utf8';
  if (c === 'iso-8859-1' || c === 'latin1') return 'latin1';
  if (c === 'us-ascii' || c === 'ascii') return 'ascii';
  return 'utf8'; // best-effort default; Node's Buffer has no generic iconv
}

function fmtNum(n) { return typeof n === 'number' ? n.toLocaleString('en-US') : String(n); }

async function preflightDns(hostname) {
  try {
    const res = await dnsLookup(hostname);
    return { ok: true, address: res.address, family: res.family };
  } catch (e) {
    return { ok: false, error: e.code || e.message };
  }
}

// ============================================================================
// FETCHER — manual redirect-chain capture. Never auto-follow: every hop must
// be individually recorded (url/status/location/timing/headers) so callers
// can see the exact wire-level truth, including cloaking/redirect games.
// ============================================================================

// Decompress a response body per Content-Encoding, with magic-byte and
// inflateRaw fallbacks because some servers mislabel or use raw-deflate.
function decompressBody(buf, headers) {
  const enc = (headers['content-encoding'] || '').toLowerCase();
  const looksGzipMagic = buf.length >= 2 && buf[0] === 0x1f && buf[1] === 0x8b;
  try {
    if (enc.includes('br')) return { data: zlib.brotliDecompressSync(buf), warning: null };
    if (enc.includes('gzip')) return { data: zlib.gunzipSync(buf), warning: null };
    if (enc.includes('deflate')) {
      try { return { data: zlib.inflateSync(buf), warning: null }; }
      catch { return { data: zlib.inflateRawSync(buf), warning: 'deflate stream required raw-deflate fallback' }; }
    }
    if (!enc && looksGzipMagic) {
      // Some misconfigured servers send gzip bytes without declaring Content-Encoding at all.
      return { data: zlib.gunzipSync(buf), warning: 'body was gzip-magic-byte-sniffed; Content-Encoding header was absent' };
    }
  } catch (e) {
    return { data: buf, warning: `decompression failed (${e.message}); serving raw bytes` };
  }
  return { data: buf, warning: null };
}

// Single HTTP hop, no redirect following. TLS errors are caught and retried
// once insecurely (flagged) so a self-signed cert doesn't just crash the tool.
function fetchOnce(urlObj, opts) {
  return new Promise((resolve) => {
    const lib = urlObj.protocol === 'http:' ? http : https;
    const start = Date.now();
    const reqOptions = {
      method: opts.method || 'GET',
      hostname: urlObj.hostname,
      port: urlObj.port || (urlObj.protocol === 'http:' ? 80 : 443),
      path: urlObj.pathname + urlObj.search,
      headers: opts.headers || {},
      timeout: opts.timeoutMs,
    };
    if (urlObj.protocol === 'https:' && opts.insecure) reqOptions.rejectUnauthorized = false;
    let settled = false;
    const finishOnce = (result) => { if (settled) return; settled = true; resolve(result); };
    let req;
    try {
      req = lib.request(reqOptions, (res) => {
        const chunks = [];
        let received = 0;
        let truncated = false;
        const cap = opts.maxBodyBytes || Infinity;
        res.on('data', (chunk) => {
          if (truncated) return;
          received += chunk.length;
          if (received > cap) {
            const keep = chunk.length - (received - cap);
            if (keep > 0) chunks.push(chunk.subarray(0, keep));
            truncated = true;
            res.destroy();
            return;
          }
          chunks.push(chunk);
        });
        const finish = () => finishOnce({
          status: res.statusCode, headers: res.headers,
          rawBody: Buffer.concat(chunks), timingMs: Date.now() - start,
          truncated, error: null,
        });
        res.on('end', finish);
        res.on('close', finish);
      });
    } catch (e) {
      finishOnce({ status: null, headers: {}, rawBody: Buffer.alloc(0), timingMs: Date.now() - start, truncated: false, error: e.message, errorCode: e.code });
      return;
    }
    req.on('timeout', () => req.destroy(new Error('request timed out')));
    req.on('error', (err) => finishOnce({ status: null, headers: {}, rawBody: Buffer.alloc(0), timingMs: Date.now() - start, truncated: false, error: err.message, errorCode: err.code }));
    if (opts.body) req.write(opts.body);
    req.end();
  });
}

async function fetchOnceWithTlsFallback(urlObj, opts) {
  const result = await fetchOnce(urlObj, opts);
  if (result.error && urlObj.protocol === 'https:' && !opts.insecure &&
      /self.signed|unable to verify|certificate|CERT_/i.test(result.error)) {
    const retry = await fetchOnce(urlObj, { ...opts, insecure: true });
    retry.tlsWarning = `TLS certificate could not be verified (${result.error}); retried with certificate validation disabled to still produce a report.`;
    return retry;
  }
  return result;
}

// Follows redirects manually, recording every hop, detecting loops, and
// respecting maxRedirects. 303 forces the next hop to GET per HTTP semantics.
async function fetchWithRedirects(startUrl, opts) {
  const chain = [];
  const seen = new Set();
  let currentUrl = startUrl;
  let method = opts.method || 'GET';
  for (let i = 0; i <= opts.maxRedirects; i++) {
    let urlObj;
    try { urlObj = new URL(currentUrl); }
    catch (e) {
      return { requestedUrl: startUrl, finalUrl: currentUrl, redirectChain: chain, status: null, headers: {}, body: Buffer.alloc(0), error: `Invalid URL: ${currentUrl}`, timingMs: 0, truncated: false };
    }
    if (seen.has(urlObj.href)) {
      return { requestedUrl: startUrl, finalUrl: urlObj.href, redirectChain: chain, status: null, headers: {}, body: Buffer.alloc(0), error: 'Redirect loop detected', timingMs: 0, truncated: false };
    }
    seen.add(urlObj.href);
    const result = await fetchOnceWithTlsFallback(urlObj, { ...opts, method });
    const locationAbs = result.headers && result.headers.location ? safeResolve(result.headers.location, urlObj) : null;
    chain.push({ url: urlObj.href, status: result.status, location: locationAbs, timing_ms: result.timingMs, headers: result.headers || {}, tlsWarning: result.tlsWarning || null });
    if (result.error) {
      return { requestedUrl: startUrl, finalUrl: urlObj.href, redirectChain: chain, status: result.status, headers: result.headers || {}, body: result.rawBody || Buffer.alloc(0), error: result.error, errorCode: result.errorCode, timingMs: result.timingMs, truncated: false, tlsWarning: result.tlsWarning || null };
    }
    if ([301, 302, 303, 307, 308].includes(result.status) && result.headers.location) {
      if (result.status === 303) method = 'GET';
      currentUrl = locationAbs || currentUrl;
      continue;
    }
    return { requestedUrl: startUrl, finalUrl: urlObj.href, redirectChain: chain, status: result.status, headers: result.headers, body: result.rawBody, error: null, timingMs: result.timingMs, truncated: result.truncated, tlsWarning: result.tlsWarning || null };
  }
  return { requestedUrl: startUrl, finalUrl: currentUrl, redirectChain: chain, status: null, headers: {}, body: Buffer.alloc(0), error: `Exceeded max redirects (${opts.maxRedirects})`, timingMs: 0, truncated: false };
}

function safeResolve(href, base) {
  try { return new URL(href, base).href; } catch { return null; }
}

// ============================================================================
// ROBOTS PARSER — RFC 9309. The part every naive implementation gets wrong:
// precedence is by LONGEST MATCHING PATH, not file order; ties go to Allow;
// no match means allowed; user-agent tokens match case-insensitively but
// paths match case-sensitively; groups for the same agent must be merged.
// ============================================================================

// Converts a robots.txt path pattern to a RegExp. '*' = zero-or-more of any
// char; a trailing '$' anchors the end, otherwise the match is a prefix.
function buildPatternRegex(pattern) {
  const hasEnd = pattern.endsWith('$');
  const body = hasEnd ? pattern.slice(0, -1) : pattern;
  const escaped = body.replace(/[.+^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*');
  return new RegExp('^' + escaped + (hasEnd ? '$' : ''));
}

// Parses raw robots.txt text into "raw groups" as they physically appear.
// Consecutive `User-agent:` lines (no rule between them) belong to one group;
// a `User-agent:` line seen after a rule closes the previous group and opens
// a new one. Malformed/unknown lines are skipped, never fatal.
function parseRobotsTxt(text) {
  const lines = text.split(/\r\n|\r|\n/);
  const rawGroups = [];
  const sitemaps = []; // global directives — collected regardless of which group they appear near
  let current = null;
  let lastWasAgent = false;
  for (const rawLine of lines) {
    const line = rawLine.replace(/#.*$/, '').trim();
    if (!line) continue;
    const idx = line.indexOf(':');
    if (idx === -1) continue; // malformed line: skip, don't abort
    const field = line.slice(0, idx).trim().toLowerCase();
    const value = line.slice(idx + 1).trim();
    if (field === 'user-agent') {
      if (!current || !lastWasAgent) { current = { agents: [], rules: [], crawlDelay: null }; rawGroups.push(current); }
      if (value) current.agents.push(value);
      lastWasAgent = true;
    } else if (field === 'allow' || field === 'disallow') {
      lastWasAgent = false;
      if (!current) continue; // rule with no preceding user-agent: malformed, skip
      if (!value) continue; // empty value is a no-op per Google's spec (not "disallow everything")
      current.rules.push({ type: field, path: value, length: value.length });
    } else if (field === 'crawl-delay') {
      lastWasAgent = false;
      if (!current) continue;
      const n = parseFloat(value);
      if (!Number.isNaN(n)) current.crawlDelay = n; // parsed for completeness; Google ignores this directive entirely
    } else if (field === 'sitemap') {
      lastWasAgent = false;
      if (value) sitemaps.push(value);
    } else {
      lastWasAgent = false; // unrecognized directive: ignore and keep parsing
    }
  }
  return { rawGroups, sitemaps };
}

// Selects the rule set that applies to `userAgent`: the most specific
// (longest) matching product token across ALL groups naming it, merged
// together per RFC 9309 §2.2.1 — this is where cross-file group merging
// actually happens, done at query time rather than as a separate pass.
function selectGroupRules(rawGroups, userAgent) {
  const ua = userAgent.toLowerCase();
  let bestToken = null, bestLen = -1;
  for (const g of rawGroups) {
    for (const tok of g.agents) {
      if (tok === '*') continue;
      const tokLower = tok.toLowerCase();
      if (ua.includes(tokLower) && tokLower.length > bestLen) { bestLen = tokLower.length; bestToken = tokLower; }
    }
  }
  let rules = [];
  let crawlDelay = null;
  if (bestToken) {
    for (const g of rawGroups) {
      if (g.agents.some((a) => a.toLowerCase() === bestToken)) {
        rules = rules.concat(g.rules);
        if (g.crawlDelay != null) crawlDelay = g.crawlDelay;
      }
    }
  } else {
    for (const g of rawGroups) {
      if (g.agents.some((a) => a === '*')) {
        rules = rules.concat(g.rules);
        if (g.crawlDelay != null) crawlDelay = g.crawlDelay;
      }
    }
  }
  return { rules, matchedToken: bestToken || (rules.length ? '*' : null), crawlDelay };
}

// The core precedence decision: among all matching rules, the longest
// pattern wins; on an exact-length tie, Allow beats Disallow (RFC 9309
// §2.2.2: "If an allow rule and a disallow rule are equivalent, ... allow
// SHOULD be used"). No matching rule at all means the path is allowed.
function isAllowed(rawGroups, path, userAgent) {
  const { rules, matchedToken, crawlDelay } = selectGroupRules(rawGroups, userAgent);
  let best = null;
  for (const rule of rules) {
    const re = buildPatternRegex(rule.path);
    if (!re.test(path)) continue;
    if (!best || rule.length > best.length) { best = rule; continue; }
    if (rule.length === best.length && rule.type === 'allow' && best.type === 'disallow') best = rule;
  }
  if (!best) return { allowed: true, matchedRule: null, ruleLength: 0, matchedAgent: matchedToken, crawlDelay };
  return { allowed: best.type === 'allow', matchedRule: `${best.type === 'allow' ? 'Allow' : 'Disallow'}: ${best.path}`, ruleLength: best.length, matchedAgent: matchedToken, crawlDelay };
}

// Fetches and evaluates access-error semantics, which are stricter than a
// naive "treat every non-200 as no rules": 4xx (except 429) => allow-all,
// 5xx/timeout => disallow-all (strict RFC reading), 429 => cautious disallow.
async function fetchRobotsTxt(origin, fetchOpts) {
  const robotsUrl = new URL('/robots.txt', origin).href;
  const result = await fetchWithRedirects(robotsUrl, { ...fetchOpts, maxRedirects: Math.min(fetchOpts.maxRedirects, 5), maxBodyBytes: ROBOTS_MAX_BYTES + 1 });
  const out = {
    url: robotsUrl, fetched: false, status: result.status, sizeBytes: 0, truncated: false,
    rawGroups: [], sitemaps: [], accessError: null, allowAll: false, disallowAll: false,
    crawlDelayNote: 'Crawl-delay is parsed for completeness but is ignored by Google; Bing and some others may honor it.',
  };
  if (result.error && !result.status) {
    out.accessError = `Could not reach robots.txt (${result.error}). Per RFC 9309, an unreachable robots.txt is treated as complete DISALLOW-ALL (the strict/safe interpretation) rather than assumed permissive.`;
    out.disallowAll = true;
    return out;
  }
  if (result.status === 429) {
    out.accessError = '429 Too Many Requests fetching robots.txt. Google explicitly excludes 429 from its "no robots.txt = allow all" bucket; treating cautiously as DISALLOW-ALL until the site can be re-checked.';
    out.disallowAll = true;
    return out;
  }
  if (result.status >= 400 && result.status < 500) {
    out.accessError = `robots.txt returned HTTP ${result.status}. Per RFC 9309/Google, a 4xx (other than 429) means "no robots.txt exists" -> ALLOW-ALL.`;
    out.allowAll = true;
    return out;
  }
  if (!result.status || result.status >= 500) {
    out.accessError = `robots.txt returned HTTP ${result.status || '(none)'}. RFC 9309 requires treating server errors/timeouts as complete DISALLOW-ALL (Google's real crawler is more forgiving operationally — cached-copy retries for up to 30 days — but a from-scratch tool should not silently assume that leniency).`;
    out.disallowAll = true;
    return out;
  }
  out.fetched = true;
  out.sizeBytes = result.body.length;
  out.truncated = result.body.length > ROBOTS_MAX_BYTES;
  const text = result.body.subarray(0, ROBOTS_MAX_BYTES).toString('utf8');
  const parsed = parseRobotsTxt(text);
  out.rawGroups = parsed.rawGroups;
  out.sitemaps = parsed.sitemaps;
  return out;
}

function robotsCheck(robotsResult, path, ua) {
  if (robotsResult.disallowAll) return { allowed: false, matchedRule: null, ruleLength: 0, matchedAgent: null, reason: robotsResult.accessError };
  if (robotsResult.allowAll) return { allowed: true, matchedRule: null, ruleLength: 0, matchedAgent: null, reason: robotsResult.accessError };
  return isAllowed(robotsResult.rawGroups, path, ua);
}

// ============================================================================
// SITEMAP PARSER — hand-rolled scanner, no XML library. Namespace-agnostic
// tag matching (local name only) so `xhtml:link`/other-prefixed extension
// tags are still found. Gzip is sniffed by magic bytes AND .gz extension,
// never trusted to Content-Encoding alone.
// ============================================================================

function looksLikeXml(buf) {
  // CMS misconfiguration commonly serves an HTML error page as 200 with an
  // XML content-type; sniff the actual bytes rather than trusting headers.
  const s = buf.subarray(0, 300).toString('utf8').replace(/^﻿/, '').trimStart();
  return /^<\?xml/i.test(s) || /^<([\w.-]+:)?urlset\b/i.test(s) || /^<([\w.-]+:)?sitemapindex\b/i.test(s);
}

function maybeGunzip(buf, url) {
  const looksGz = (buf.length >= 2 && buf[0] === 0x1f && buf[1] === 0x8b) || /\.gz(\?|#|$)/i.test(url);
  if (!looksGz) return { data: buf, wasGzip: false };
  try { return { data: zlib.gunzipSync(buf), wasGzip: true }; }
  catch (e) { return { data: buf, wasGzip: false, gunzipError: e.message }; }
}

// Namespace-agnostic: matches <foo>, <ns:foo>, </foo>, </ns:foo> alike.
function extractAll(xml, localName) {
  const re = new RegExp(`<(?:[\\w.-]+:)?${localName}\\b[^>]*>([\\s\\S]*?)<\\/(?:[\\w.-]+:)?${localName}>`, 'gi');
  const out = [];
  let m;
  while ((m = re.exec(xml)) !== null) out.push(m[1]);
  return out;
}
function extractFirst(xml, localName) {
  const re = new RegExp(`<(?:[\\w.-]+:)?${localName}\\b[^>]*>([\\s\\S]*?)<\\/(?:[\\w.-]+:)?${localName}>`, 'i');
  const m = re.exec(xml);
  return m ? m[1].trim() : null;
}

// hreflang alternates use a self-closing extension tag: <xhtml:link rel="alternate" hreflang="es" href="..."/>
function extractHreflangAlternates(urlBlock) {
  const re = /<(?:[\w.-]+:)?link\b([^>]*)\/?>/gi;
  const out = [];
  let m;
  while ((m = re.exec(urlBlock)) !== null) {
    const attrs = m[1];
    const relM = /rel\s*=\s*["']([^"']*)["']/i.exec(attrs);
    const hreflangM = /hreflang\s*=\s*["']([^"']*)["']/i.exec(attrs);
    const hrefM = /href\s*=\s*["']([^"']*)["']/i.exec(attrs);
    if (relM && /alternate/i.test(relM[1]) && hreflangM && hrefM) {
      out.push({ lang: decodeEntities(hreflangM[1]), href: decodeEntities(hrefM[1]) });
    }
  }
  return out;
}

// Recursively fetches a sitemap (or sitemap index), capped at a total fetch
// budget of 10 files across the whole recursion so a hostile/huge index
// cannot make the tool fetch unbounded numbers of files.
async function fetchAndParseSitemap(url, fetchOpts, state) {
  if (state.fetchedCount >= SITEMAP_FETCH_BUDGET) { state.budgetExceeded = true; return null; }
  state.fetchedCount++;
  const result = await fetchWithRedirects(url, { ...fetchOpts, maxBodyBytes: SITEMAP_MAX_BYTES + 1024 * 1024 });
  const entry = { url, finalUrl: result.finalUrl, status: result.status, type: null, gzipped: false, byteSize: 0, urlCount: 0, sitemapCount: 0, hreflangAlternateCount: 0, sampleEntries: [], children: [], errors: [], warnings: [] };
  if (result.error) { entry.errors.push(`Fetch failed: ${result.error}`); return entry; }
  if (!result.status || result.status >= 400) { entry.errors.push(`HTTP ${result.status}`); return entry; }
  const gz = maybeGunzip(result.body, result.finalUrl || url);
  entry.gzipped = gz.wasGzip;
  if (gz.gunzipError) entry.errors.push(`Looked gzipped (magic bytes/.gz) but failed to decompress: ${gz.gunzipError}`);
  const data = gz.data;
  entry.byteSize = data.length;
  if (data.length > SITEMAP_MAX_BYTES) entry.warnings.push(`Sitemap is ${fmtNum(data.length)} bytes, exceeding the 50 MB (${fmtNum(SITEMAP_MAX_BYTES)} byte) protocol limit.`);
  if (!looksLikeXml(data)) {
    entry.errors.push('Response does not look like valid XML (first bytes do not match <?xml/<urlset/<sitemapindex) — likely an HTML error page served with a misleading content-type/status.');
    return entry;
  }
  const xml = data.toString('utf8');
  const isIndex = /<(?:[\w.-]+:)?sitemapindex\b/i.test(xml);
  const isUrlset = /<(?:[\w.-]+:)?urlset\b/i.test(xml);
  if (isIndex) {
    entry.type = 'sitemapindex';
    const sitemapBlocks = extractAll(xml, 'sitemap');
    entry.sitemapCount = sitemapBlocks.length;
    if (sitemapBlocks.length > SITEMAP_MAX_URLS) entry.warnings.push(`${fmtNum(sitemapBlocks.length)} <sitemap> entries exceeds the 50,000-entry limit for a sitemap index.`);
    const childUrls = sitemapBlocks.map((b) => extractFirst(b, 'loc')).filter(Boolean).map(decodeEntities);
    for (const childUrl of childUrls) {
      if (state.fetchedCount >= SITEMAP_FETCH_BUDGET) { state.budgetExceeded = true; entry.warnings.push(`Sitemap fetch budget (${SITEMAP_FETCH_BUDGET}) exhausted; not all child sitemaps were fetched.`); break; }
      const child = await fetchAndParseSitemap(childUrl, fetchOpts, state);
      if (child) entry.children.push(child);
    }
  } else if (isUrlset) {
    entry.type = 'urlset';
    const urlBlocks = extractAll(xml, 'url');
    entry.urlCount = urlBlocks.length;
    if (urlBlocks.length > SITEMAP_MAX_URLS) entry.warnings.push(`${fmtNum(urlBlocks.length)} <url> entries exceeds the 50,000-URL protocol limit.`);
    let hreflangTotal = 0;
    for (const block of urlBlocks) {
      const loc = extractFirst(block, 'loc');
      const alts = extractHreflangAlternates(block);
      hreflangTotal += alts.length;
      if (entry.sampleEntries.length < 5 && loc) entry.sampleEntries.push({ loc: decodeEntities(loc), lastmod: extractFirst(block, 'lastmod'), hreflang: alts });
    }
    entry.hreflangAlternateCount = hreflangTotal;
  } else {
    entry.errors.push('XML root is neither <urlset> nor <sitemapindex>.');
  }
  return entry;
}

// Gathers candidate sitemap URLs from robots.txt Sitemap: directives plus
// the conventional /sitemap.xml fallback, de-duplicated.
async function runSitemapAnalysis(origin, robotsResult, fetchOpts) {
  const candidates = [...robotsResult.sitemaps];
  const fallback = new URL('/sitemap.xml', origin).href;
  if (!candidates.some((u) => u === fallback)) candidates.push(fallback);
  const state = { fetchedCount: 0, budgetExceeded: false };
  const results = [];
  for (const url of candidates) {
    if (state.fetchedCount >= SITEMAP_FETCH_BUDGET) { state.budgetExceeded = true; break; }
    const entry = await fetchAndParseSitemap(url, fetchOpts, state);
    if (entry) results.push(entry);
  }
  return { sitemaps: results, truncated: state.budgetExceeded, totalFetched: state.fetchedCount };
}

// ============================================================================
// HTML SIGNALS — regex/string extraction from raw HTML. No DOM engine, so
// this is fundamentally a raw-HTML view (see jsDependency + mandatory
// limitations section for why that matters).
// ============================================================================

// Generic attribute-string parser used for <meta>, <link>, <img>, <a>, <base>.
function parseAttrs(tagAttrString) {
  const attrs = {};
  const re = /([a-zA-Z_:][-a-zA-Z0-9_:.]*)\s*(?:=\s*("([^"]*)"|'([^']*)'|([^\s"'>]+)))?/g;
  let m;
  while ((m = re.exec(tagAttrString)) !== null) {
    const name = m[1].toLowerCase();
    if (!name) continue;
    const val = m[3] !== undefined ? m[3] : m[4] !== undefined ? m[4] : m[5] !== undefined ? m[5] : '';
    attrs[name] = decodeEntities(val);
  }
  return attrs;
}

function findTags(html, tagName) {
  const re = new RegExp(`<${tagName}\\b([^>]*)>`, 'gi');
  const out = [];
  let m;
  while ((m = re.exec(html)) !== null) out.push({ attrs: parseAttrs(m[1]) });
  return out;
}

// Title must ignore <title> nested in inline SVG or inside <noscript> —
// both are common false positives for a naive regex.
function extractTitle(html) {
  const cleaned = html.replace(/<svg[\s\S]*?<\/svg>/gi, '').replace(/<noscript[\s\S]*?<\/noscript>/gi, '');
  const m = /<title\b[^>]*>([\s\S]*?)<\/title>/i.exec(cleaned);
  if (!m) return null;
  return decodeEntities(stripTagsToText(m[1])).replace(/\s+/g, ' ').trim();
}

function extractMetaSignals(html) {
  const metas = findTags(html, 'meta');
  const result = { description: null, robots: null, viewport: null, generator: null, refresh: null, og: {}, twitter: {} };
  for (const { attrs } of metas) {
    const name = attrs.name;
    const property = attrs.property;
    const httpEquiv = attrs['http-equiv'];
    const content = attrs.content;
    if (content === undefined) continue;
    if (name === 'description') result.description = content;
    else if (name === 'robots') result.robots = content;
    else if (name === 'viewport') result.viewport = content;
    else if (name === 'generator') result.generator = content;
    else if (httpEquiv && httpEquiv.toLowerCase() === 'refresh') result.refresh = content;
    else if (name && name.startsWith('twitter:')) result.twitter[name.slice(8)] = content;
    else if (property && property.startsWith('og:')) result.og[property.slice(3)] = content;
  }
  return result;
}

function extractCanonicalTags(html) {
  return findTags(html, 'link')
    .filter((t) => t.attrs.rel && /\bcanonical\b/i.test(t.attrs.rel) && t.attrs.href)
    .map((t) => t.attrs.href);
}

// Canonical can ALSO be declared purely via an HTTP `Link:` response header
// (RFC 8288) with no HTML tag at all — a common miss in naive extractors.
function extractCanonicalHeader(headers) {
  const raw = headers && headers.link;
  if (!raw) return null;
  const joined = Array.isArray(raw) ? raw.join(', ') : raw;
  const parts = joined.split(/,\s*(?=<)/);
  for (const part of parts) {
    const urlM = /<([^>]+)>/.exec(part);
    const relM = /rel\s*=\s*"?([^";]+)"?/i.exec(part);
    if (urlM && relM && /\bcanonical\b/i.test(relM[1])) return urlM[1];
  }
  return null;
}

function extractHreflang(html) {
  return findTags(html, 'link')
    .filter((t) => t.attrs.rel && /\balternate\b/i.test(t.attrs.rel) && t.attrs.hreflang && t.attrs.href)
    .map((t) => ({ lang: t.attrs.hreflang, href: t.attrs.href }));
}

function extractHeadings(html) {
  const result = {};
  for (let lvl = 1; lvl <= 6; lvl++) {
    const re = new RegExp(`<h${lvl}\\b[^>]*>([\\s\\S]*?)<\\/h${lvl}>`, 'gi');
    const arr = [];
    let m;
    while ((m = re.exec(html)) !== null) {
      const text = decodeEntities(stripTagsToText(m[1])).replace(/\s+/g, ' ').trim();
      if (text) arr.push(text);
    }
    result['h' + lvl] = arr;
  }
  return result;
}

// JSON-LD: extraction + JSON.parse validity only. Schema-semantic
// correctness (e.g. is this a valid Article per schema.org) is out of scope.
function extractJsonLd(html) {
  const re = /<script\b[^>]*type\s*=\s*["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi;
  const out = [];
  let m;
  while ((m = re.exec(html)) !== null) {
    const raw = m[1].trim();
    let valid = true, error = null, types = [];
    try {
      const parsed = JSON.parse(raw);
      const items = Array.isArray(parsed) ? parsed : (Array.isArray(parsed['@graph']) ? parsed['@graph'] : [parsed]);
      for (const it of items) {
        if (it && it['@type']) types.push(Array.isArray(it['@type']) ? it['@type'].join(',') : it['@type']);
      }
    } catch (e) { valid = false; error = e.message; }
    out.push({ valid, error, types, excerpt: raw.slice(0, 120) });
  }
  return out;
}

// Distinguishes a missing `alt` attribute (accessibility/SEO problem) from
// `alt=""` (a deliberate, valid decorative-image marker) — conflating the
// two is a common mistake.
function extractImages(html) {
  const imgs = findTags(html, 'img');
  let missingAlt = 0, emptyAlt = 0;
  for (const { attrs } of imgs) {
    if (!('alt' in attrs)) missingAlt++;
    else if (attrs.alt === '') emptyAlt++;
  }
  return { total: imgs.length, missingAlt, emptyAltDecorative: emptyAlt };
}

function extractBaseHref(html) {
  const t = findTags(html, 'base')[0];
  return t && t.attrs.href ? t.attrs.href : null;
}

// Internal/external classification must resolve relative URLs against the
// FINAL post-redirect URL (not the originally requested one), honor
// protocol-relative `//host` links, and respect a page's <base href>.
function extractLinks(html, finalUrl) {
  const baseHref = extractBaseHref(html);
  let baseUrl;
  try { baseUrl = new URL(baseHref || finalUrl, finalUrl); } catch { baseUrl = new URL(finalUrl); }
  const finalHost = new URL(finalUrl).hostname;
  const anchors = findTags(html, 'a');
  let internal = 0, external = 0, nofollow = 0;
  for (const { attrs } of anchors) {
    if (!attrs.href) continue;
    const href = attrs.href.trim();
    if (!href || /^(javascript:|mailto:|tel:|#)/i.test(href)) continue;
    let resolved;
    try { resolved = new URL(href, baseUrl); } catch { continue; }
    if (resolved.hostname === finalHost) internal++; else external++;
    if (attrs.rel && /\bnofollow\b/i.test(attrs.rel)) nofollow++;
  }
  return { internal, external, nofollow };
}

// Approximate only: regex tag-stripping cannot distinguish visible text from
// display:none/aria-hidden content without a real DOM/CSS engine.
function approximateWordCount(html) {
  const stripped = html
    .replace(/<script[\s\S]*?<\/script>/gi, ' ')
    .replace(/<style[\s\S]*?<\/style>/gi, ' ')
    .replace(/<noscript[\s\S]*?<\/noscript>/gi, ' ');
  const text = decodeEntities(stripTagsToText(stripped));
  return text.trim().split(/\s+/).filter(Boolean).length;
}

function extractHtmlSignals(html, finalUrl, responseHeaders) {
  const title = extractTitle(html);
  const meta = extractMetaSignals(html);
  const canonicalTags = extractCanonicalTags(html);
  const canonicalHeader = extractCanonicalHeader(responseHeaders);
  const htmlLangMatch = /<html\b[^>]*\blang\s*=\s*["']([^"']*)["']/i.exec(html);
  const uniqueCanonicals = new Set(canonicalTags);
  return {
    title: title ? { value: title, length: title.length } : null,
    metaDescription: meta.description ? { value: meta.description, length: meta.description.length } : null,
    metaRobots: meta.robots || null,
    xRobotsTag: (responseHeaders && responseHeaders['x-robots-tag']) || null,
    canonical: {
      tags: canonicalTags, header: canonicalHeader,
      conflict: uniqueCanonicals.size > 1 || (!!canonicalHeader && canonicalTags.length > 0 && !uniqueCanonicals.has(canonicalHeader)),
    },
    hreflang: extractHreflang(html),
    headings: extractHeadings(html),
    jsonLd: extractJsonLd(html),
    openGraph: meta.og,
    twitterCard: meta.twitter,
    lang: htmlLangMatch ? htmlLangMatch[1] : null,
    viewport: meta.viewport,
    generator: meta.generator,
    metaRefresh: meta.refresh,
    images: extractImages(html),
    links: extractLinks(html, finalUrl),
    wordCountApprox: approximateWordCount(html),
  };
}

// ============================================================================
// JS DEPENDENCY — heuristic verdict, never a hard claim. CRITICAL INVERSION:
// SSR/hydration markers mean content IS already in the raw HTML — these are
// GOOD signs and must never be flagged as JS-dependency problems themselves.
// ============================================================================

const SSR_MARKERS = ['__NEXT_DATA__', 'self.__next_f', 'window.__NUXT__', 'data-server-rendered', 'astro-island', '___gatsby', '__remixContext', '__sveltekit', 'ng-version'];

function detectJsDependency(html) {
  const signals = [];
  let ssrHit = null;
  // Presence of a framework SSR/hydration marker means the framework already
  // rendered real content into this HTML — this is evidence AGAINST
  // JS-dependency, the opposite of what a naive "found a JS framework" check
  // would conclude.
  for (const marker of SSR_MARKERS) {
    if (html.includes(marker)) {
      signals.push(`SSR/hydration marker found: "${marker}" — content is already server-rendered into this HTML (good sign, NOT a JS-dependency problem).`);
      ssrHit = marker;
    }
  }
  const rootMatch = /<div\b[^>]*\bid\s*=\s*["'](root|app|__next)["'][^>]*>([\s\S]*?)<\/div>/i.exec(html);
  let rootNearEmpty = false;
  if (rootMatch) {
    const innerText = decodeEntities(stripTagsToText(rootMatch[2])).replace(/\s+/g, ' ').trim();
    if (innerText.length < 40) {
      rootNearEmpty = true;
      signals.push(`Root container <div id="${rootMatch[1]}"> has only ${innerText.length} characters of text in the raw HTML.`);
    }
  }
  const scriptSrcCount = (html.match(/<script\b[^>]*\bsrc\s*=/gi) || []).length;
  const hashedBundleCount = (html.match(/<script\b[^>]*\bsrc\s*=\s*["'][^"']*\.[a-f0-9]{6,}\.(?:js|mjs)["']/gi) || []).length;
  const wordCount = approximateWordCount(html);
  if (wordCount < 50 && scriptSrcCount >= 3) {
    signals.push(`Very low text-to-markup content (~${wordCount} words) combined with ${scriptSrcCount} external <script> tags.`);
  }
  // The CONTENT of a <noscript> block is the signal, not its mere presence —
  // a GA/pixel tracking noscript is normal on a fully server-rendered page.
  const noscriptBlocks = html.match(/<noscript\b[^>]*>[\s\S]*?<\/noscript>/gi) || [];
  let noscriptWarning = false;
  for (const block of noscriptBlocks) {
    if (/enable\s+javascript|requires?\s+javascript|turn\s+on\s+javascript|javascript\s+is\s+(?:required|disabled)/i.test(block)) {
      noscriptWarning = true;
      signals.push('A <noscript> block warns "please enable JavaScript" — the app likely depends on JS execution to render content.');
    }
  }
  const metaGenerator = /<meta\b[^>]*name\s*=\s*["']generator["'][^>]*content\s*=\s*["']([^"']*)["']/i.exec(html);
  if (metaGenerator) signals.push(`<meta name="generator"> = "${metaGenerator[1]}" (weak corroborating signal only — most CMS output is server-rendered, this alone does not indicate JS-dependency).`);

  let verdict, confidence;
  if (ssrHit && !(rootNearEmpty && noscriptWarning)) {
    verdict = 'likely-ssr';
    confidence = rootNearEmpty ? 'medium' : 'high';
  } else if (!ssrHit && noscriptWarning && (rootNearEmpty || (wordCount < 50 && scriptSrcCount >= 3))) {
    verdict = 'likely-csr';
    confidence = 'high';
  } else if (!ssrHit && rootNearEmpty && wordCount < 50 && hashedBundleCount > 0) {
    verdict = 'likely-csr';
    confidence = 'high';
  } else if (!ssrHit && (rootNearEmpty || (wordCount < 80 && scriptSrcCount >= 3))) {
    verdict = 'likely-csr';
    confidence = 'medium';
  } else {
    verdict = 'uncertain';
    confidence = 'low';
    if (!signals.length) signals.push('No strong SSR or CSR signals detected in the raw HTML.');
  }
  return { verdict, confidence, signals };
}

// ============================================================================
// AI BOTS ROSTER — evaluates robots.txt against a snapshot roster of
// AI/search crawlers, grouped by role so the high-value misconfiguration
// (blocking a citation/index bot) is impossible to miss.
// ============================================================================

const AI_BOT_ROSTER = [
  { name: 'GPTBot', operator: 'OpenAI', role: 'train' },
  { name: 'OAI-SearchBot', operator: 'OpenAI', role: 'index/citations' },
  { name: 'ChatGPT-User', operator: 'OpenAI', role: 'live-retrieve' },
  { name: 'ClaudeBot', operator: 'Anthropic', role: 'train' },
  { name: 'Claude-SearchBot', operator: 'Anthropic', role: 'index/citations' },
  { name: 'Claude-User', operator: 'Anthropic', role: 'live-retrieve' },
  { name: 'Googlebot', operator: 'Google', role: 'index+AI Overviews base' },
  { name: 'Google-Extended', operator: 'Google', role: 'train-only' },
  { name: 'PerplexityBot', operator: 'Perplexity', role: 'index' },
  { name: 'Bingbot', operator: 'Microsoft', role: 'index+Copilot' },
  { name: 'Applebot', operator: 'Apple', role: 'index' },
  { name: 'Applebot-Extended', operator: 'Apple', role: 'train' },
  { name: 'Meta-ExternalAgent', operator: 'Meta', role: 'train' },
  { name: 'Amazonbot', operator: 'Amazon', role: 'train' },
  { name: 'CCBot', operator: 'CommonCrawl', role: 'corpus' },
  { name: 'Bytespider', operator: 'ByteDance', role: 'train' },
];
const CITATION_INDEX_BOTS = new Set(['OAI-SearchBot', 'Claude-SearchBot', 'PerplexityBot', 'Bingbot', 'Googlebot']);

function evaluateAiBots(robotsResult) {
  return AI_BOT_ROSTER.map((bot) => {
    const verdict = robotsCheck(robotsResult, '/', bot.name);
    return { ...bot, allowedAtRoot: verdict.allowed, matchedRule: verdict.matchedRule, isCitationIndexBot: CITATION_INDEX_BOTS.has(bot.name) };
  });
}

// ============================================================================
// CRUX / PSI CLIENTS — Google-run HTTP APIs, no local browser needed.
// ============================================================================

function httpsGetJson(urlStr, timeoutMs) {
  return new Promise((resolve) => {
    let u;
    try { u = new URL(urlStr); } catch { return resolve({ error: 'invalid URL' }); }
    const req = https.request({ hostname: u.hostname, path: u.pathname + u.search, method: 'GET', timeout: timeoutMs, headers: { accept: 'application/json' } }, (res) => {
      const chunks = [];
      res.on('data', (c) => chunks.push(c));
      res.on('end', () => {
        const raw = Buffer.concat(chunks).toString('utf8');
        let json = null;
        try { json = JSON.parse(raw); } catch { /* non-JSON error body, leave null */ }
        resolve({ status: res.statusCode, json, raw });
      });
    });
    req.on('timeout', () => req.destroy(new Error('request timed out')));
    req.on('error', (e) => resolve({ error: e.message }));
    req.end();
  });
}

function httpsPostJson(urlStr, bodyObj, timeoutMs) {
  return new Promise((resolve) => {
    let u;
    try { u = new URL(urlStr); } catch { return resolve({ error: 'invalid URL' }); }
    const payload = Buffer.from(JSON.stringify(bodyObj));
    const req = https.request({ hostname: u.hostname, path: u.pathname + u.search, method: 'POST', timeout: timeoutMs, headers: { 'content-type': 'application/json', 'content-length': payload.length } }, (res) => {
      const chunks = [];
      res.on('data', (c) => chunks.push(c));
      res.on('end', () => {
        const raw = Buffer.concat(chunks).toString('utf8');
        let json = null;
        try { json = JSON.parse(raw); } catch { /* non-JSON error body, leave null */ }
        resolve({ status: res.statusCode, json, raw });
      });
    });
    req.on('timeout', () => req.destroy(new Error('request timed out')));
    req.on('error', (e) => resolve({ error: e.message }));
    req.write(payload);
    req.end();
  });
}

const CWV_THRESHOLDS = {
  largest_contentful_paint: { good: 2500, ni: 4000 },
  interaction_to_next_paint: { good: 200, ni: 500 },
  cumulative_layout_shift: { good: 0.1, ni: 0.25 },
  experimental_time_to_first_byte: { good: 800, ni: 1800 },
  first_contentful_paint: { good: 1800, ni: 3000 },
};
function rateMetric(name, value) {
  const t = CWV_THRESHOLDS[name];
  if (!t || value == null) return 'unknown';
  if (value <= t.good) return 'good';
  if (value <= t.ni) return 'needs-improvement';
  return 'poor';
}

// Field data from real Chrome users. URL-level records frequently don't
// exist for low-traffic pages — a 404/empty record there is expected, not
// an error, and must fall back to an origin-level query, clearly labeled.
async function fetchCrux(target, apiKey, timeoutMs) {
  if (!apiKey) return { available: false, skipped: true, message: 'No CrUX API key supplied. Get a free key at https://developer.chrome.com/docs/crux/how-to-access (enable the "Chrome UX Report API" in Google Cloud Console). Pass it with --crux <key>.' };
  const endpoint = `https://chromeuxreport.googleapis.com/v1/records:queryRecord?key=${encodeURIComponent(apiKey)}`;
  let originUrl;
  try { originUrl = new URL(target).origin; } catch { return { available: false, error: 'invalid target URL' }; }
  let level = 'url';
  let resp = await httpsPostJson(endpoint, { url: target, formFactor: 'PHONE' }, timeoutMs);
  if (resp.error) return { available: false, error: resp.error };
  if (resp.status === 404) {
    level = 'origin';
    resp = await httpsPostJson(endpoint, { origin: originUrl, formFactor: 'PHONE' }, timeoutMs);
    if (resp.error) return { available: false, error: resp.error };
  }
  if (resp.status !== 200 || !resp.json || !resp.json.record) {
    const msg = resp.json && resp.json.error ? resp.json.error.message : `HTTP ${resp.status}`;
    return { available: false, error: msg, note: resp.status === 404 ? 'No CrUX data at URL or origin level — insufficient real-user traffic sample; this is common for low-traffic pages, not necessarily a bug.' : undefined };
  }
  const metrics = {};
  for (const [name, m] of Object.entries(resp.json.record.metrics || {})) {
    const p75 = m.percentiles && m.percentiles.p75;
    metrics[name] = { p75, rating: rateMetric(name, p75) };
  }
  return { available: true, level, fellBackToOrigin: level === 'origin', collectionPeriod: resp.json.record.collectionPeriod, metrics };
}

// PSI runs Lighthouse server-side, so it needs no local Chrome install — but
// that server-side run can take well over the tool's default timeout.
async function fetchPsi(target, apiKey, timeoutMs, strategy = 'mobile') {
  if (!apiKey) return { available: false, skipped: true, message: 'No PageSpeed Insights API key supplied. Get a free key at https://developers.google.com/speed/docs/insights/v5/get-started. Pass it with --psi <key>.' };
  const params = new URLSearchParams();
  params.append('url', target);
  params.append('strategy', strategy);
  for (const c of ['performance', 'seo', 'accessibility', 'best-practices']) params.append('category', c);
  params.append('key', apiKey);
  const endpoint = `https://www.googleapis.com/pagespeedonline/v5/runPagespeed?${params.toString()}`;
  const psiTimeout = Math.max(timeoutMs, 60000); // Lighthouse runs server-side and routinely takes 20-50s
  const resp = await httpsGetJson(endpoint, psiTimeout);
  if (resp.error) return { available: false, error: resp.error };
  if (resp.status !== 200 || !resp.json) {
    const msg = resp.json && resp.json.error ? resp.json.error.message : `HTTP ${resp.status}`;
    return { available: false, error: msg };
  }
  const lh = resp.json.lighthouseResult;
  const scores = {};
  if (lh && lh.categories) for (const [k, v] of Object.entries(lh.categories)) scores[k] = v.score;
  const le = resp.json.loadingExperience || resp.json.originLoadingExperience;
  const fieldMetrics = {};
  if (le && le.metrics) {
    for (const [name, m] of Object.entries(le.metrics)) {
      fieldMetrics[name] = { percentile: m.percentile, category: m.category };
    }
  }
  return { available: true, strategy, scores, lighthouseVersion: lh && lh.lighthouseVersion, fieldData: Object.keys(fieldMetrics).length ? fieldMetrics : null };
}

// ============================================================================
// REPORT — plain-ASCII human report (pipe-safe, no emoji/color) + JSON.
// The "what this tool cannot see" section is mandatory and unconditional.
// ============================================================================

function mk(kind) { return { ok: '[OK]', warn: '[WARN]', fail: '[FAIL]', info: '[INFO]' }[kind] || '[INFO]'; }

function buildLimitationsBlock() {
  const lines = [];
  lines.push('WHAT THIS TOOL CANNOT SEE');
  for (const l of MANDATORY_LIMITATIONS) lines.push(`  - ${l}`);
  lines.push('Escalate to a headless browser or Rich Results Test before reporting any of the above as "missing".');
  return lines.join('\n');
}

function section(title) { return `\n${title}\n${'='.repeat(title.length)}`; }

function buildHumanReport(r) {
  const out = [];
  out.push(`seo-check v${TOOL_VERSION} — audit of ${r.meta.target}`);
  out.push(`Started: ${r.meta.startedAt}  Duration: ${r.meta.durationMs}ms  User-Agent: ${r.meta.flags.userAgent}`);

  if (r.fetch) {
    out.push(section('FETCH'));
    if (r.fetch.error) {
      out.push(`${mk('fail')} Could not fetch ${r.fetch.requestedUrl}: ${r.fetch.error}`);
    } else {
      out.push(`${mk(r.fetch.status && r.fetch.status < 400 ? 'ok' : 'warn')} ${r.fetch.requestedUrl} -> HTTP ${r.fetch.status} (final: ${r.fetch.finalUrl})`);
      if (r.fetch.redirectChain.length > 1) {
        out.push(`  Redirect chain (${r.fetch.redirectChain.length} hops):`);
        for (const hop of r.fetch.redirectChain) out.push(`    ${hop.status || '(error)'}  ${hop.url}${hop.location ? ' -> ' + hop.location : ''}  (${hop.timing_ms}ms)`);
      }
      out.push(`  Content-Type: ${r.fetch.contentType || '(none)'}  Bytes: ${fmtNum(r.fetch.bytesDownloaded)}  Time: ${r.fetch.timingMs}ms${r.fetch.truncated ? '  [TRUNCATED at 5MB cap]' : ''}`);
      if (r.fetch.tlsWarning) out.push(`  ${mk('warn')} ${r.fetch.tlsWarning}`);
      if (r.fetch.decompressWarning) out.push(`  ${mk('warn')} ${r.fetch.decompressWarning}`);
    }
  }

  if (r.robotsTxt) {
    out.push(section('ROBOTS.TXT'));
    const rt = r.robotsTxt;
    if (rt.accessError) {
      out.push(`${mk(rt.disallowAll ? 'fail' : 'warn')} ${rt.accessError}`);
    } else {
      out.push(`${mk('ok')} Fetched ${rt.url} (HTTP ${rt.status}, ${fmtNum(rt.sizeBytes)} bytes${rt.truncated ? ', TRUNCATED at 500KiB parse cap' : ''})`);
      out.push(`  Groups defined: ${rt.groups.length}   Sitemap directives: ${rt.sitemaps.length}`);
      for (const s of rt.sitemaps) out.push(`    Sitemap: ${s}`);
    }
    const v = rt.verdictForTarget;
    out.push(`${mk(v.allowed ? 'ok' : 'fail')} Path "${v.path}" evaluated as UA "${v.userAgent}": ${v.allowed ? 'ALLOWED' : 'DISALLOWED'}${v.matchedRule ? ` (matched: ${v.matchedRule})` : ' (no matching rule)'}`);
    if (v.crawlDelay != null) out.push(`  ${mk('info')} Crawl-delay: ${v.crawlDelay}s — ${rt.crawlDelayNote}`);
  }

  if (r.aiBots) {
    out.push(section('AI / SEARCH BOT ROSTER'));
    out.push(`${mk('info')} Roster snapshot dated 2026-08 — re-verify bot names/behavior against each operator's current documentation before relying on this long-term.`);
    const roles = [
      ['index/citations', 'CITATION / INDEX BOTS (feed AI answers, search results, citations)'],
      ['index', 'CITATION / INDEX BOTS (feed AI answers, search results, citations)'],
      ['index+AI Overviews base', 'CITATION / INDEX BOTS (feed AI answers, search results, citations)'],
      ['index+Copilot', 'CITATION / INDEX BOTS (feed AI answers, search results, citations)'],
      ['live-retrieve', 'LIVE-RETRIEVAL BOTS (fetch on-demand for a user\'s live query)'],
      ['train', 'TRAINING-DATA BOTS (crawl for model training corpora)'],
      ['train-only', 'TRAINING-DATA BOTS (crawl for model training corpora)'],
      ['corpus', 'CORPUS-COLLECTION BOTS (general web archive, e.g. Common Crawl)'],
    ];
    const seenGroups = new Set();
    let anyCitationBlocked = false, anyTrainBlocked = false;
    for (const [, label] of roles) {
      if (seenGroups.has(label)) continue;
      seenGroups.add(label);
      const bots = r.aiBots.filter((b) => roles.find(([role, l]) => l === label && role === b.role));
      if (!bots.length) continue;
      out.push(`  ${label}`);
      for (const b of bots) {
        out.push(`    ${mk(b.allowedAtRoot ? 'ok' : 'fail')} ${b.name} (${b.operator}, ${b.role}): ${b.allowedAtRoot ? 'allowed' : 'DISALLOWED'} at /`);
        if (!b.allowedAtRoot && b.isCitationIndexBot) anyCitationBlocked = true;
        if (!b.allowedAtRoot && !b.isCitationIndexBot) anyTrainBlocked = true;
      }
    }
    if (anyCitationBlocked) out.push(`  ${mk('warn')} WARNING: at least one citation/index bot is disallowed at "/" — this removes the site from that platform's answers/citations/search results, not just training.`);
    else if (anyTrainBlocked) out.push(`  ${mk('info')} Only training-data bots are blocked — citation/index/live-retrieval behavior is unaffected.`);
    else out.push(`  ${mk('ok')} No bots in the roster are disallowed at "/".`);
  }

  if (r.sitemaps) {
    out.push(section('SITEMAPS'));
    if (r.sitemaps.truncated) out.push(`${mk('warn')} Sitemap fetch budget (${SITEMAP_FETCH_BUDGET}) was reached; not every referenced sitemap was fetched.`);
    const printSitemap = (sm, depth) => {
      const indent = '  '.repeat(depth + 1);
      if (sm.errors.length) {
        out.push(`${indent}${mk('fail')} ${sm.url}: ${sm.errors.join('; ')}`);
        return;
      }
      out.push(`${indent}${mk('ok')} ${sm.url} [${sm.type || 'unknown'}]${sm.gzipped ? ' (gzip)' : ''} — ${sm.type === 'sitemapindex' ? `${fmtNum(sm.sitemapCount)} child sitemaps` : `${fmtNum(sm.urlCount)} URLs`}${sm.hreflangAlternateCount ? `, ${fmtNum(sm.hreflangAlternateCount)} hreflang alternates` : ''}`);
      for (const w of sm.warnings) out.push(`${indent}  ${mk('warn')} ${w}`);
      for (const c of sm.children) printSitemap(c, depth + 1);
    };
    for (const sm of r.sitemaps.sitemaps) printSitemap(sm, 0);
  }

  if (r.pageSignals) {
    const ps = r.pageSignals;
    out.push(section('PAGE SIGNALS'));
    out.push(`${mk(ps.title ? 'ok' : 'fail')} Title: ${ps.title ? `"${ps.title.value}" (${ps.title.length} chars)` : 'MISSING'}`);
    out.push(`${mk(ps.metaDescription ? 'ok' : 'warn')} Meta description: ${ps.metaDescription ? `"${ps.metaDescription.value.slice(0, 160)}" (${ps.metaDescription.length} chars)` : 'MISSING'}`);
    out.push(`${mk('info')} Meta robots: ${ps.metaRobots || '(none — defaults to index,follow)'}    X-Robots-Tag: ${ps.xRobotsTag || '(none)'}`);
    out.push(`${mk(ps.canonical.conflict ? 'warn' : 'ok')} Canonical: tag(s)=[${ps.canonical.tags.join(', ') || 'none'}]  header=${ps.canonical.header || 'none'}${ps.canonical.conflict ? '  MULTIPLE/CONFLICTING CANONICALS' : ''}`);
    out.push(`${mk('info')} hreflang alternates: ${ps.hreflang.length}`);
    out.push(`${mk(ps.headings.h1.length === 1 ? 'ok' : 'warn')} H1 count: ${ps.headings.h1.length}${ps.headings.h1.length ? ` — "${ps.headings.h1[0]}"` : ''}   H2: ${ps.headings.h2.length}  H3: ${ps.headings.h3.length}`);
    const invalidJsonLd = ps.jsonLd.filter((j) => !j.valid).length;
    out.push(`${mk(invalidJsonLd ? 'warn' : 'info')} JSON-LD blocks: ${ps.jsonLd.length}${invalidJsonLd ? ` (${invalidJsonLd} FAILED JSON.parse)` : ''}`);
    out.push(`${mk('info')} lang="${ps.lang || '(none)'}"   viewport="${ps.viewport || '(none)'}"   generator="${ps.generator || '(none)'}"`);
    out.push(`${mk(ps.images.missingAlt ? 'warn' : 'ok')} Images: ${ps.images.total} total, ${ps.images.missingAlt} missing alt, ${ps.images.emptyAltDecorative} alt="" (decorative, OK)`);
    out.push(`${mk('info')} Links: ${ps.links.internal} internal, ${ps.links.external} external, ${ps.links.nofollow} nofollow`);
    out.push(`${mk('info')} Approximate word count: ${fmtNum(ps.wordCountApprox)} (raw-HTML text, approximate — see limitations)`);
  }

  if (r.jsDependency) {
    out.push(section('JS DEPENDENCY HEURISTIC'));
    const jd = r.jsDependency;
    out.push(`${mk(jd.verdict === 'likely-ssr' ? 'ok' : jd.verdict === 'likely-csr' ? 'warn' : 'info')} Verdict: ${jd.verdict}   Confidence: ${jd.confidence}`);
    for (const s of jd.signals) out.push(`  - ${s}`);
    if (jd.verdict !== 'likely-ssr') {
      out.push(`  ${mk('warn')} WARNING: this page may be JavaScript-dependent. Any "missing" finding in PAGE SIGNALS above (title, meta, canonical, content, JSON-LD, etc.) could be a FALSE NEGATIVE — the real content may only exist after client-side rendering. Re-verify with a headless browser before treating anything above as a confirmed defect.`);
    }
  }

  if (r.cloakingComparison) {
    out.push(section('GOOGLEBOT COMPARISON (CLOAKING HEURISTIC)'));
    const c = r.cloakingComparison;
    if (c.error) out.push(`${mk('warn')} Comparison fetch failed: ${c.error}`);
    else {
      out.push(`${mk('info')} Normal UA: HTTP ${c.normalStatus}, ${fmtNum(c.normalWordCount)} words, title="${c.normalTitle || ''}"`);
      out.push(`${mk('info')} Googlebot UA: HTTP ${c.googlebotStatus}, ${fmtNum(c.googlebotWordCount)} words, title="${c.googlebotTitle || ''}"`);
      out.push(`${mk(c.statusDiffers || c.titleDiffers || c.significantWordCountDelta ? 'warn' : 'ok')} ${c.statusDiffers || c.titleDiffers || c.significantWordCountDelta ? 'DIFFERENCES DETECTED between UAs — possible cloaking, or simply A/B testing/CDN variance. This is a heuristic, not proof.' : 'No significant differences detected between UAs.'}`);
    }
  }

  if (r.coreWebVitals && (r.coreWebVitals.crux || r.coreWebVitals.psi)) {
    out.push(section('CORE WEB VITALS'));
    const cx = r.coreWebVitals.crux;
    if (cx) {
      if (cx.skipped) out.push(`${mk('info')} CrUX: ${cx.message}`);
      else if (!cx.available) out.push(`${mk('warn')} CrUX: unavailable — ${cx.error}${cx.note ? ' (' + cx.note + ')' : ''}`);
      else {
        out.push(`${mk('ok')} CrUX field data (${cx.level}-level${cx.fellBackToOrigin ? ', fell back from URL to origin — site-wide average, not page-specific' : ''}), window ${cx.collectionPeriod ? `${cx.collectionPeriod.firstDate.year}-${cx.collectionPeriod.firstDate.month}-${cx.collectionPeriod.firstDate.day} to ${cx.collectionPeriod.lastDate.year}-${cx.collectionPeriod.lastDate.month}-${cx.collectionPeriod.lastDate.day}` : 'unknown'}:`);
        for (const [name, m] of Object.entries(cx.metrics)) out.push(`    ${mk(m.rating === 'good' ? 'ok' : m.rating === 'poor' ? 'fail' : 'warn')} ${name}: p75=${m.p75} (${m.rating})`);
      }
    }
    const psi = r.coreWebVitals.psi;
    if (psi) {
      if (psi.skipped) out.push(`${mk('info')} PSI: ${psi.message}`);
      else if (!psi.available) out.push(`${mk('warn')} PSI: unavailable — ${psi.error}`);
      else {
        out.push(`${mk('ok')} PSI lab scores (${psi.strategy}, Lighthouse ${psi.lighthouseVersion || '?'}):`);
        for (const [k, v] of Object.entries(psi.scores)) out.push(`    ${k}: ${v == null ? 'n/a' : Math.round(v * 100)}/100`);
      }
    }
  }

  if (r.indexability) {
    out.push(section('INDEXABILITY'));
    const ix = r.indexability;
    out.push(`${mk(ix.overallIndexableSignal === true ? 'ok' : ix.overallIndexableSignal === false ? 'fail' : 'info')} robots.txt allows: ${ix.robotsTxtAllows}   meta-robots allows: ${ix.metaRobotsAllows}   X-Robots-Tag allows: ${ix.xRobotsTagAllows}`);
    out.push(`${mk('info')} Overall indexable signal: ${ix.overallIndexableSignal}`);
    out.push(`${mk('info')} Confirmed indexation status: ${ix.confirmedIndexationStatus}`);
  }

  if (r.errors.length) {
    out.push(section('CHECK ERRORS'));
    for (const e of r.errors) out.push(`${mk('warn')} [${e.check}] ${e.message}`);
  }

  out.push('\n' + buildLimitationsBlock());
  return out.join('\n');
}

// ============================================================================
// MAIN — orchestration.
//
// Scope rules (interpreting the CLI surface literally):
//   --robots  is EXCLUSIVE: "only run robots.txt analysis" — skips page
//             fetch/html signals/jsDependency entirely.
//   --sitemap and --ai-bots are ADDITIVE: they layer extra sections onto
//             whatever else is running (full audit by default, or onto
//             --robots mode, since both operate on robots.txt data).
//   --crux/--psi are opt-in and degrade to "skipped: no API key", never fatal.
// ============================================================================

async function main() {
  const argv = process.argv.slice(2);
  let opts;
  try { opts = parseArgs(argv); }
  catch (e) {
    if (e instanceof UsageError) { console.error(`Usage error: ${e.message}`); printHelp(); process.exit(2); }
    throw e;
  }
  if (opts.help) { printHelp(); process.exit(0); }
  if (!opts.url) { console.error('Usage error: missing <url> argument.'); printHelp(); process.exit(2); }

  let targetUrl;
  try { targetUrl = normalizeTargetUrl(opts.url); }
  catch (e) { console.error(`Usage error: invalid URL "${opts.url}": ${e.message}`); process.exit(2); }

  const startedAt = new Date();
  const report = {
    meta: {
      tool: 'seo-check', version: TOOL_VERSION,
      startedAt: startedAt.toISOString(), durationMs: 0,
      target: targetUrl,
      flags: { userAgent: opts.ua, timeoutMs: opts.timeout, maxRedirects: opts.maxRedirects, robotsOnly: opts.robotsOnly, sitemap: opts.sitemap, aiBots: opts.aiBots, compareGooglebot: opts.compareGooglebot },
    },
    fetch: null, robotsTxt: null, aiBots: null, sitemaps: null, pageSignals: null,
    jsDependency: null, cloakingComparison: null,
    coreWebVitals: { crux: null, psi: null },
    indexability: null, limitations: MANDATORY_LIMITATIONS, errors: [],
  };

  const targetUrlObj = new URL(targetUrl);
  const origin = targetUrlObj.origin;
  const targetPath = targetUrlObj.pathname + targetUrlObj.search;

  const fetchOpts = { timeoutMs: opts.timeout, maxRedirects: opts.maxRedirects, headers: { 'user-agent': opts.ua, accept: 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8' }, maxBodyBytes: PAGE_BODY_CAP };

  let fatal = false;

  // DNS preflight up front: gives a clean, specific fatal message instead of
  // a generic connection error buried inside the fetch machinery.
  const dnsCheck = await preflightDns(targetUrlObj.hostname);
  if (!dnsCheck.ok) {
    fatal = true;
    report.fetch = { requestedUrl: targetUrl, finalUrl: targetUrl, redirectChain: [], status: null, error: `DNS resolution failed for ${targetUrlObj.hostname}: ${dnsCheck.error}` };
    report.errors.push({ check: 'dns', message: report.fetch.error });
  }

  // robots.txt is always fetched (needed for indexability, --robots, --ai-bots).
  let robotsResult = null;
  if (!fatal) {
    robotsResult = await fetchRobotsTxt(origin, fetchOpts);
    // --check-path / --as-ua let the auditor ask about a different path or bot token than
    // the one actually fetched; both default back to the target URL and the wire user-agent.
    const verdictPath = opts.checkPath || targetPath;
    const verdictUa = opts.asUa || opts.ua;
    const verdict = robotsCheck(robotsResult, verdictPath, verdictUa);
    report.robotsTxt = {
      url: robotsResult.url, fetched: robotsResult.fetched, status: robotsResult.status,
      sizeBytes: robotsResult.sizeBytes, truncated: robotsResult.truncated,
      groups: robotsResult.rawGroups.map((g) => ({ userAgents: g.agents, rules: g.rules, crawlDelay: g.crawlDelay })),
      sitemaps: robotsResult.sitemaps, accessError: robotsResult.accessError,
      allowAll: robotsResult.allowAll, disallowAll: robotsResult.disallowAll,
      crawlDelayNote: robotsResult.crawlDelayNote,
      verdictForTarget: { path: verdictPath, userAgent: verdictUa, allowed: verdict.allowed, matchedRule: verdict.matchedRule, ruleLength: verdict.ruleLength, crawlDelay: verdict.crawlDelay },
    };
    if (robotsResult.disallowAll && robotsResult.accessError && !robotsResult.fetched) {
      report.errors.push({ check: 'robots', message: robotsResult.accessError });
    }

    if (opts.aiBots) report.aiBots = evaluateAiBots(robotsResult);

    if (opts.sitemap) {
      try { report.sitemaps = await runSitemapAnalysis(origin, robotsResult, fetchOpts); }
      catch (e) { report.errors.push({ check: 'sitemap', message: e.message }); }
    }
  }

  let pageResult = null;
  if (!fatal && !opts.robotsOnly) {
    pageResult = await fetchWithRedirects(targetUrl, fetchOpts);
    if (pageResult.error && !pageResult.status) {
      fatal = true;
      report.fetch = { requestedUrl: targetUrl, finalUrl: pageResult.finalUrl, redirectChain: pageResult.redirectChain, status: null, error: pageResult.error };
      report.errors.push({ check: 'fetch', message: pageResult.error });
    } else {
      const ct = (pageResult.headers['content-type'] || '').toLowerCase();
      const { data: decompressed, warning: decompressWarning } = decompressBody(pageResult.body, pageResult.headers);
      const isHtml = ct.includes('html') || (!ct && /^\s*</.test(decompressed.subarray(0, 100).toString('utf8')));
      report.fetch = {
        requestedUrl: targetUrl, finalUrl: pageResult.finalUrl, redirectChain: pageResult.redirectChain,
        status: pageResult.status, headers: pageResult.headers, contentType: pageResult.headers['content-type'] || null,
        contentEncoding: pageResult.headers['content-encoding'] || null, bytesDownloaded: pageResult.body.length,
        timingMs: pageResult.timingMs, truncated: pageResult.truncated, tlsWarning: pageResult.tlsWarning || null,
        decompressWarning, error: null,
      };
      if (pageResult.status >= 400) {
        report.errors.push({ check: 'fetch', message: `Target URL returned HTTP ${pageResult.status}.` });
      }
      if (isHtml && decompressed.length > 0) {
        const html = decompressed.toString(charsetFromContentType(ct));
        report.pageSignals = extractHtmlSignals(html, pageResult.finalUrl, pageResult.headers);
        report.jsDependency = detectJsDependency(html);
      } else if (!isHtml) {
        report.errors.push({ check: 'html-signals', message: `Content-Type "${ct || '(none)'}" is not HTML; page-signal extraction skipped.` });
      } else {
        report.errors.push({ check: 'html-signals', message: 'Response body is empty; page-signal extraction skipped.' });
      }

      if (opts.compareGooglebot) {
        const gbResult = await fetchWithRedirects(targetUrl, { ...fetchOpts, headers: { ...fetchOpts.headers, 'user-agent': GOOGLEBOT_UA } });
        if (gbResult.error && !gbResult.status) {
          report.cloakingComparison = { error: gbResult.error };
        } else {
          const { data: gbData } = decompressBody(gbResult.body, gbResult.headers);
          const gbHtml = gbData.toString(charsetFromContentType(gbResult.headers['content-type'] || ''));
          const gbTitle = extractTitle(gbHtml);
          const gbWordCount = approximateWordCount(gbHtml);
          const normalTitle = report.pageSignals && report.pageSignals.title ? report.pageSignals.title.value : null;
          const normalWordCount = report.pageSignals ? report.pageSignals.wordCountApprox : 0;
          const statusDiffers = pageResult.status !== gbResult.status;
          const titleDiffers = (normalTitle || '') !== (gbTitle || '');
          const significantWordCountDelta = Math.abs(normalWordCount - gbWordCount) > Math.max(50, normalWordCount * 0.25);
          report.cloakingComparison = {
            normalStatus: pageResult.status, googlebotStatus: gbResult.status,
            normalTitle, googlebotTitle: gbTitle,
            normalWordCount, googlebotWordCount: gbWordCount,
            statusDiffers, titleDiffers, significantWordCountDelta,
          };
        }
      }
    }
  }

  if (!fatal) {
    if (opts.cruxKey) report.coreWebVitals.crux = await fetchCrux(targetUrl, opts.cruxKey, opts.timeout);
    else report.coreWebVitals.crux = await fetchCrux(targetUrl, null, opts.timeout);
    if (opts.psiKey) report.coreWebVitals.psi = await fetchPsi(targetUrl, opts.psiKey, opts.timeout);
    else report.coreWebVitals.psi = await fetchPsi(targetUrl, null, opts.timeout);

    const robotsTxtAllows = report.robotsTxt ? report.robotsTxt.verdictForTarget.allowed : null;
    const metaRobots = report.pageSignals ? report.pageSignals.metaRobots : null;
    const xRobotsTag = report.pageSignals ? report.pageSignals.xRobotsTag : null;
    const metaRobotsAllows = metaRobots ? !/noindex/i.test(metaRobots) : true;
    const xRobotsTagAllows = xRobotsTag ? !/noindex/i.test(xRobotsTag) : true;
    const overall = report.pageSignals ? (robotsTxtAllows && metaRobotsAllows && xRobotsTagAllows) : robotsTxtAllows;
    report.indexability = {
      robotsTxtAllows, metaRobotsAllows, xRobotsTagAllows,
      overallIndexableSignal: overall,
      confirmedIndexationStatus: 'unknown — requires Search Console API access with verified property ownership; not attempted by this tool',
    };
  }

  report.meta.durationMs = Date.now() - startedAt.getTime();

  if (opts.json) {
    console.log(JSON.stringify(report, null, 2));
  } else {
    console.log(buildHumanReport(report));
  }

  process.exit(fatal ? 1 : 0);
}

main().catch((e) => {
  console.error(`Fatal internal error: ${e && e.stack ? e.stack : e}`);
  process.exit(1);
});
