#!/usr/bin/env node
/**
 * analyze-sessions.mjs — token spend and cache breaks across Claude Code
 * transcripts (~/.claude/projects/**.jsonl). Read-only; prints to stdout and
 * writes no file anywhere, so a report can never land inside a repo.
 *
 *   node analyze-sessions.mjs [--dir <projects-dir>] [--since 7d|24h|<ISO>]
 *                             [--top N] [--cache-break N] [--json]
 *
 * A cache break is one API call whose uncached input (input_tokens +
 * cache_creation_input_tokens) is above --cache-break (default 100000): the
 * prompt prefix stopped matching and the whole context was billed again.
 *
 * Transcript facts this relies on: one API response is split across several
 * `assistant` entries sharing a requestId, and only the last carries the final
 * output_tokens, so calls are deduped by requestId keeping the max output.
 * Resumed sessions replay history, so entries are also deduped by uuid.
 * Prompt text is cut to 80 characters because transcripts from client repos
 * pass through here.
 *
 * Credit: adapted from anthropics/claude-plugins-official plugins/session-report/skills/session-report/analyze-sessions.mjs @ a9fd216 (Apache-2.0).
 * Licensed under the Apache License, Version 2.0; the upstream notice is at
 * https://www.apache.org/licenses/LICENSE-2.0. This file is a reduced rewrite
 * of the upstream analyzer (no HTML report, no skill or day breakdowns).
 */
import fs from 'fs'
import os from 'os'
import path from 'path'
import readline from 'readline'

const argv = process.argv.slice(2)
function flag(name, dflt) {
  const i = argv.indexOf(name)
  if (i === -1) return dflt
  const v = argv[i + 1]
  return v === undefined || v.startsWith('--') ? dflt : v
}
const ROOT = flag('--dir', path.join(os.homedir(), '.claude', 'projects'))
const AS_JSON = argv.includes('--json')
const TOP_N = parseInt(flag('--top', '15'), 10)
const BREAK_AT = parseInt(flag('--cache-break', '100000'), 10)
const SINCE_RAW = flag('--since', '7d')
const PREVIEW_MAX = 80

function parseSince(s) {
  const m = /^(\d+)([dh])$/.exec(s)
  if (m) return Date.now() - parseInt(m[1], 10) * (m[2] === 'd' ? 86400000 : 3600000)
  const t = Date.parse(s)
  return Number.isNaN(t) ? null : t
}
const SINCE = parseSince(SINCE_RAW)
if (SINCE === null) {
  process.stderr.write(`analyze-sessions: cannot read --since ${SINCE_RAW} (use 7d, 24h or an ISO date)\n`)
  process.exit(2)
}

function* walk(dir) {
  let ents
  try {
    ents = fs.readdirSync(dir, { withFileTypes: true })
  } catch {
    return
  }
  for (const e of ents) {
    const p = path.join(dir, e.name)
    if (e.isDirectory()) yield* walk(p)
    else if (e.isFile() && e.name.endsWith('.jsonl')) yield p
  }
}

function preview(text) {
  const t = String(text).replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim()
  return t.length > PREVIEW_MAX ? t.slice(0, PREVIEW_MAX - 1) + '…' : t
}

// A human prompt is a plain string or first text block, not a tool_result.
function humanText(e) {
  if (e.isMeta || e.isCompactSummary || e.isSidechain) return null
  const c = e.message && e.message.content
  if (typeof c === 'string') return c
  if (Array.isArray(c) && c[0] && c[0].type === 'text') return c[0].text || ''
  return null
}

const zero = () => ({ apiCalls: 0, input: 0, cacheCreate: 0, cacheRead: 0, output: 0 })
function add(t, u) {
  t.apiCalls++
  t.input += u.input_tokens || 0
  t.cacheCreate += u.cache_creation_input_tokens || 0
  t.cacheRead += u.cache_read_input_tokens || 0
  t.output += u.output_tokens || 0
}
const grand = (t) => t.input + t.cacheCreate + t.cacheRead + t.output

const totals = zero()
const byProject = new Map()
const sessions = new Set()
const cacheBreaks = []
const seenUuid = new Set()
const seenCall = new Set()
let subagentTokens = 0

async function scan(file) {
  const rel = path.relative(ROOT, file).split(path.sep)
  const project = rel[0]
  const isSub = rel.includes('subagents')
  const sessionId = isSub ? rel[rel.indexOf('subagents') - 1] : path.basename(file, '.jsonl')
  const calls = new Map()
  let prompt = null
  const rl = readline.createInterface({ input: fs.createReadStream(file), crlfDelay: Infinity })
  for await (const line of rl) {
    if (!line) continue
    let e
    try {
      e = JSON.parse(line)
    } catch {
      continue
    }
    if (e.uuid) {
      if (seenUuid.has(e.uuid)) continue
      seenUuid.add(e.uuid)
    }
    const ts = e.timestamp ? Date.parse(e.timestamp) : NaN
    if (!Number.isNaN(ts) && ts < SINCE) continue
    if (e.type === 'user') {
      const text = humanText(e)
      if (text !== null && !isSub) prompt = preview(text) || null
    } else if (e.type === 'assistant' && e.message && e.message.usage) {
      const key = e.requestId || (e.message.id ? e.message.id : `${file}:${e.uuid || calls.size}`)
      const prev = calls.get(key)
      if (!prev || (e.message.usage.output_tokens || 0) >= (prev.usage.output_tokens || 0)) {
        calls.set(key, { usage: e.message.usage, ts: e.timestamp || null, prompt })
      }
    }
  }
  for (const [key, c] of calls) {
    if (seenCall.has(key)) continue
    seenCall.add(key)
    sessions.add(sessionId)
    add(totals, c.usage)
    if (!byProject.has(project)) byProject.set(project, zero())
    add(byProject.get(project), c.usage)
    if (isSub) subagentTokens += (c.usage.input_tokens || 0) + (c.usage.cache_creation_input_tokens || 0) +
      (c.usage.cache_read_input_tokens || 0) + (c.usage.output_tokens || 0)
    const uncached = (c.usage.input_tokens || 0) + (c.usage.cache_creation_input_tokens || 0)
    if (uncached > BREAK_AT) {
      cacheBreaks.push({
        ts: c.ts, project, session: sessionId, kind: isSub ? 'subagent' : 'main',
        uncached, total: uncached + (c.usage.cache_read_input_tokens || 0), prompt: c.prompt,
      })
    }
  }
}

for (const f of walk(ROOT)) await scan(f)

cacheBreaks.sort((a, b) => b.uncached - a.uncached)
const projects = [...byProject.entries()]
  .map(([project, t]) => ({ project, ...t, tokens: grand(t) }))
  .sort((a, b) => b.tokens - a.tokens)
  .slice(0, TOP_N)

const report = {
  dir: ROOT,
  since: new Date(SINCE).toISOString(),
  cache_break_threshold: BREAK_AT,
  totals: { sessions: sessions.size, ...totals, tokens: grand(totals), subagent_tokens: subagentTokens },
  by_project: projects,
  cache_breaks: cacheBreaks.slice(0, Math.max(TOP_N, 0) || undefined),
}

if (AS_JSON) {
  process.stdout.write(JSON.stringify(report, null, 2) + '\n')
} else {
  const n = (x) => x.toLocaleString('en-US')
  const out = []
  out.push(`Sessions since ${report.since}: ${n(report.totals.sessions)}, API calls ${n(totals.apiCalls)}`)
  out.push(`Tokens: input ${n(totals.input)}, cache write ${n(totals.cacheCreate)}, cache read ${n(totals.cacheRead)}, output ${n(totals.output)}, total ${n(grand(totals))}`)
  out.push(`Inside subagent transcripts: ${n(subagentTokens)}`)
  out.push('', `Top projects (${projects.length}):`)
  for (const p of projects) out.push(`  ${n(p.tokens).padStart(14)}  ${p.project}`)
  out.push('', `Cache breaks (uncached input > ${n(BREAK_AT)}): ${cacheBreaks.length}`)
  for (const b of report.cache_breaks) {
    out.push(`  ${b.ts || '?'}  ${n(b.uncached).padStart(10)} uncached  ${b.project}  ${b.kind}${b.prompt ? '  "' + b.prompt + '"' : ''}`)
  }
  process.stdout.write(out.join('\n') + '\n')
}
