#!/usr/bin/env bash
# What a perfect run leaves on disk: spec + TASKS drafted, approved at the gate,
# two committed tasks ticked through `flow tick`, gates green, PASS for HEAD,
# and NO Verified: line (that fact is the human's).
set -euo pipefail
FLOW="node $EVAL_PLUGIN_ROOT/bin/flow"
TODAY=$(date +%F)
BASE=$(git rev-parse --short HEAD)

bash "$EVAL_PLUGIN_ROOT/scripts/new-spec" "Invoice summaries" --dir .specs --current --no-branch >/dev/null
SPEC=.specs/001-invoice-summaries
mkdir -p "$SPEC"

cat >"$SPEC/spec.md" <<'MD'
# Spec: Invoice summaries

**Created**: 2026-09-29 · **Route**: dispatch

## TL;DR

**Problem**: Callers hand-assemble invoice summaries from the transport and each one handles flaky transports differently.
**Solution**: Two service functions return display-ready summaries and retry transport failures the same way everywhere.
**Who it's for**: Developers building on ledgerline.
**Key decision**: Only the transport call is retried; a malformed response is a caller-visible parse error, never retried.

## 2. Scope

### 2.1 In scope
- `getInvoiceSummary(transport, id)` and `listInvoiceSummaries(transport, ids)` in `src/services/invoices.js`.

### 2.2 Non-goals
- No change to `parseInvoice`, `overdueIds` or the shared helpers. No new dependencies.

## 4. Requirements

| ID | Priority | Requirement | Acceptance |
|----|----------|-------------|------------|
| FR-01 | MUST | A developer MUST get `{ id, customer, total }` for `/invoices/<id>`, total formatted for display | test with 123450 and 5 cents |
| FR-02 | MUST | Transport failures MUST be retried, 3 attempts in total; the last error is rejected as is | test counting calls and comparing the error object |
| FR-03 | MUST | A malformed response MUST reject with the parser's error after one call | test asserting one call and a TypeError |
| FR-04 | MUST | `listInvoiceSummaries` MUST look ids up one at a time in order, keep id order, and on a failure reject with that lookup's original error without starting later lookups | test recording transport calls |

## 7. Assumptions

| # | Assumption | Confidence | Blast radius if wrong |
|---|------------|-----------|-----------------------|
| A1 | The existing attempt, money and parser helpers are the house behaviour | High | Callers see two retry policies |
MD

cat >"$SPEC/TASKS.md" <<MD
# Tasks — Invoice summaries
Spec: spec.md · Design: none · Base: $BASE · Route: dispatch · Test: \`node --test\`

## Behaviors
| ID | Given / When / Then | Task | Proven by |
|----|---------------------|------|-----------|
| B1 (P0) | Given a transport, when I ask for one invoice, then I get id, customer and a display total | T001 | summary shape |
| B2 (P0) | Given a flaky transport, when it fails 3 times, then the last error object is rejected | T001 | retry count |
| B3 (P0) | Given a malformed body, when I ask, then one call and the parser error | T001 | malformed |
| B4 (P0) | Given several ids, when one lookup fails, then its original error is rejected and order is kept | T002 | list order and failure |

## Phase 1 — One summary
Goal: one invoice can be summarised reliably over a flaky transport.
Independent test: \`node --test test/invoices.test.js\` — green with the list function absent.
- [ ] T001 getInvoiceSummary with retry and parsing (B1, B2, B3) — files: src/services/invoices.js, test/invoices.test.js — verify: \`node --test test/invoices.test.js\`

## Phase 2 — Many summaries
Goal: several invoices can be summarised in order, failing loudly.
Independent test: \`node --test\` — whole suite green.
- [ ] T002 listInvoiceSummaries (B4) — files: src/services/invoices.js, test/invoices.test.js — verify: \`node --test test/invoices.test.js\` — after: T001

## Gates
- [ ] G001 project gates clean — files: . — verify: \`node --test\`
- [ ] G002 branch review clean — files: . — verify: \`flow pass\`
MD

{ head -2 "$SPEC/TASKS.md"; echo "Approved: $TODAY by user"; tail -n +3 "$SPEC/TASKS.md"; } >"$SPEC/TASKS.new"
mv "$SPEC/TASKS.new" "$SPEC/TASKS.md"

# ---- T001
cat >src/services/invoices.js <<'JS'
import { keepTrying } from '../lib/attempt.js'
import { renderAmount } from '../lib/money.js'
import { parseInvoice } from '../models/invoice.js'

export function overdueIds(rows, today) {
  return rows.filter((row) => row.dueDate < today && !row.paid).map((row) => row.id)
}

export async function getInvoiceSummary(transport, id) {
  const raw = await keepTrying(() => transport(`/invoices/${id}`), 3)
  const invoice = parseInvoice(raw)
  return { id: invoice.id, customer: invoice.customer, total: renderAmount(invoice.totalCents) }
}
JS
python3 - <<'PY'
p = "test/invoices.test.js"
s = open(p).read()
s = s.replace("import { overdueIds } from", "import { getInvoiceSummary, overdueIds } from")
s += """
const raw = (id, cents = 123450) => ({ id, customer: 'Acme Ltd', totalCents: cents })

test('getInvoiceSummary reads /invoices/<id> and formats the total', async () => {
  const paths = []
  const transport = async (path) => {
    paths.push(path)
    return raw('inv-7')
  }
  assert.deepEqual(await getInvoiceSummary(transport, 'inv-7'), {
    id: 'inv-7',
    customer: 'Acme Ltd',
    total: '$1,234.50',
  })
  assert.deepEqual(paths, ['/invoices/inv-7'])
})

test('getInvoiceSummary retries into a result after two failures', async () => {
  let calls = 0
  const transport = async () => {
    calls++
    if (calls < 3) throw new Error('flaky')
    return raw('inv-9')
  }
  assert.equal((await getInvoiceSummary(transport, 'inv-9')).id, 'inv-9')
  assert.equal(calls, 3)
})

test('getInvoiceSummary rejects with the last error itself after three attempts', async () => {
  const errors = [new Error('one'), new Error('two'), new Error('three')]
  let calls = 0
  const transport = async () => {
    throw errors[calls++]
  }
  await assert.rejects(getInvoiceSummary(transport, 'inv-1'), (err) => err === errors[2])
  assert.equal(calls, 3)
})

test('getInvoiceSummary does not retry a malformed response', async () => {
  let calls = 0
  const transport = async () => {
    calls++
    return raw('inv-2', -5)
  }
  await assert.rejects(getInvoiceSummary(transport, 'inv-2'), TypeError)
  assert.equal(calls, 1)
})
"""
open(p, "w").write(s)
PY
node --test test/invoices.test.js >/dev/null 2>&1
git add src/services/invoices.js test/invoices.test.js
git commit -q -m "invoices: getInvoiceSummary with shared retry, parser and money helpers"
$FLOW tick T001

# ---- T002
python3 - <<'PY'
p = "src/services/invoices.js"
s = open(p).read()
s += """
export async function listInvoiceSummaries(transport, ids) {
  const summaries = []
  for (const id of ids) {
    summaries.push(await getInvoiceSummary(transport, id))
  }
  return summaries
}
"""
open(p, "w").write(s)
p = "test/invoices.test.js"
s = open(p).read()
s = s.replace("import { getInvoiceSummary, overdueIds } from", "import { listInvoiceSummaries, getInvoiceSummary, overdueIds } from")
s += """
test('listInvoiceSummaries looks ids up one at a time, in order', async () => {
  const seen = []
  let inFlight = 0
  let maxInFlight = 0
  const transport = async (path) => {
    inFlight++
    maxInFlight = Math.max(maxInFlight, inFlight)
    seen.push(path)
    await new Promise((resolve) => setTimeout(resolve, 5))
    inFlight--
    return raw(path.split('/').pop(), 100)
  }
  const summaries = await listInvoiceSummaries(transport, ['a', 'b'])
  assert.deepEqual(summaries.map((summary) => summary.id), ['a', 'b'])
  assert.deepEqual(seen, ['/invoices/a', '/invoices/b'])
  assert.equal(maxInFlight, 1)
})

test('listInvoiceSummaries starts no lookup after a failure', async () => {
  const boom = new Error('b is down')
  const seen = []
  const transport = async (path) => {
    seen.push(path)
    if (path.endsWith('/b')) throw boom
    return raw('a')
  }
  await assert.rejects(listInvoiceSummaries(transport, ['a', 'b', 'c']), (err) => err === boom)
  assert.equal(seen.includes('/invoices/c'), false)
})

test('listInvoiceSummaries rejects with the failing lookup original error', async () => {
  const boom = new Error('b is down')
  const transport = async (path) => {
    if (path.endsWith('/b')) throw boom
    return raw('a')
  }
  await assert.rejects(listInvoiceSummaries(transport, ['a', 'b']), (err) => err === boom)
})

test('listInvoiceSummaries of no ids resolves to an empty list', async () => {
  assert.deepEqual(await listInvoiceSummaries(async () => raw('x'), []), [])
})
"""
open(p, "w").write(s)
PY
node --test test/invoices.test.js >/dev/null 2>&1
git add src/services/invoices.js test/invoices.test.js
git commit -q -m "invoices: listInvoiceSummaries in id order"
$FLOW tick T002

# ---- gates
node --test >/dev/null 2>&1
HEAD_SHA=$(git rev-parse --short HEAD)
cat >"$SPEC/PASS-$HEAD_SHA.md" <<MD
# PASS $HEAD_SHA
- G001 \`node --test\` — exit 0
- G002 branch review — no findings above threshold
MD
$FLOW tick G001
$FLOW tick G002
git add "$SPEC"
git commit -q -m "specs: invoice summaries plan, tasks ticked, PASS"
