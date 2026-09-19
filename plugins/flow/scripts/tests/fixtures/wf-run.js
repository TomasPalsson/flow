#!/usr/bin/env node
// wf-run.js — test harness for the saved Workflow-tool scripts under
// workflows/*.js. Node cannot run those files directly: `export const meta`
// is followed by top-level `await` and `return`, which are only legal inside
// a function body. This evaluates everything AFTER the meta object literal
// as the body of an async function, with agent/parallel/pipeline/log/phase/
// args/budget bound to the same-named exports of a stub CommonJS module —
// the workflow's only free identifiers besides its own declarations.
//
// Usage: node wf-run.js <workflow.js> <stub.js>
// Prints the workflow's returned value as JSON on stdout.
'use strict'
const fs = require('fs')
const path = require('path')

const [, , workflowPath, stubPath] = process.argv
if (!workflowPath || !stubPath) {
  console.error('Usage: node wf-run.js <workflow.js> <stub.js>')
  process.exit(1)
}

const src = fs.readFileSync(workflowPath, 'utf8')

// scanBalanced returns the index of the char matching s[startIdx] (openCh),
// respecting string/template literals — same helper as workflow-lint's.
function scanBalanced(s, startIdx, openCh, closeCh) {
  let depth = 0
  let inStr = null
  for (let i = startIdx; i < s.length; i++) {
    const c = s[i]
    if (inStr) {
      if (c === '\\') { i++; continue }
      if (c === inStr) { inStr = null }
      continue
    }
    if (c === '"' || c === "'" || c === '`') { inStr = c; continue }
    if (c === openCh) { depth++ }
    else if (c === closeCh) {
      depth--
      if (depth === 0) { return i }
    }
  }
  return -1
}

const metaDeclMatch = src.match(/export\s+const\s+meta\s*=\s*\{/)
if (!metaDeclMatch) {
  console.error(workflowPath + ': no "export const meta = {" found')
  process.exit(1)
}
const openIdx = metaDeclMatch.index + metaDeclMatch[0].length - 1
const metaObjEnd = scanBalanced(src, openIdx, '{', '}')
if (metaObjEnd === -1) {
  console.error(workflowPath + ': unbalanced meta object literal')
  process.exit(1)
}
let afterIdx = metaObjEnd + 1
if (src[afterIdx] === ';') { afterIdx++ }
const bodySrc = src.slice(afterIdx)

const stub = require(path.resolve(stubPath))
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor
const runWorkflow = new AsyncFunction('agent', 'parallel', 'pipeline', 'log', 'phase', 'args', 'budget', bodySrc)

runWorkflow(stub.agent, stub.parallel, stub.pipeline, stub.log, stub.phase, stub.args, stub.budget).then(
  function (result) {
    process.stdout.write(JSON.stringify(result === undefined ? null : result) + '\n')
  },
  function (e) {
    console.error(e && e.stack ? e.stack : String(e))
    process.exitCode = 1
  }
)
