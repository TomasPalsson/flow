'use strict';

// eval/contract.js — Slice 5 (.claude/slices/5-brief.md), code-design.md
// section 1: names, locations and shapes shared across the eval-suite
// slices. Owner: orchestrator; import, never edit (THE FIVE #1/#3).

const TAGS = ['quality', 'routing', 'invariant', 'needs-bash']; // every case tag ⊂ TAGS
const EVALS_ROOT = 'plugins/flow/evals'; // relative to repo toplevel
const LEDGER_PATH = 'plugins/flow/evals/ledger.jsonl';
const CONFIG_KEYS = { model: 'evalModel', judgeModel: 'evalJudgeModel' }; // .claude/flow.config.json
const DEFAULT_MODELS = { model: 'claude-sonnet-5', judgeModel: 'claude-haiku-4-5' };
const MIN_CLAUDE_VERSION = '2.1.269';

// ledgerLine(fields) -> one JSON object, the literal shape every writer and
// reader of evals/ledger.jsonl shares: {ts, sha, model, judgeModel,
// tags:{<tag>:{score, delta, cases}}, meanDelta, costUsd, partial, reason}.
function ledgerLine(fields) {
  return JSON.stringify({
    ts: fields.ts,
    sha: fields.sha,
    model: fields.model,
    judgeModel: fields.judgeModel,
    tags: fields.tags,
    meanDelta: fields.meanDelta,
    costUsd: fields.costUsd,
    partial: fields.partial,
    reason: fields.reason,
  });
}

module.exports = { TAGS, EVALS_ROOT, LEDGER_PATH, CONFIG_KEYS, DEFAULT_MODELS, MIN_CLAUDE_VERSION, ledgerLine };
