#!/usr/bin/env bash
set -euo pipefail
# This script ends in `git add -A; git commit`. Run by hand from a checkout
# instead of the eval runner's scratch copy, that would sweep the invoking
# repo's whole working tree into one commit under a fake author identity.
# `claude plugin eval --scaffold` nests this case's cwd inside its own
# throwaway HOME, which is itself an empty `git init` (no commits, user.email
# eval@example.invalid) so `--is-inside-work-tree` alone is true there too.
# Only refuse when that work tree already has a commit, which the real
# invoking checkout always does and the eval sandbox's placeholder never does.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1 &&
	git rev-parse --verify -q HEAD >/dev/null 2>&1; then
	echo "scaffold.sh: refusing to scaffold inside an existing git work tree: $PWD" >&2
	exit 1
fi
git init -q
git config user.email "dev@example.com"
git config user.name "Dev"
git config commit.gpgsign false

mkdir -p src/lib src/models src/services test .claude

# --- commit 1: package, README, shared helpers ---------------------------------
cat >package.json <<'JSON'
{
  "name": "ledgerline",
  "version": "0.4.0",
  "private": true,
  "type": "module"
}
JSON
cat >.claude/flow.config.json <<'JSON'
{
  "requireSpec": true
}
JSON
cat >README.md <<'MD'
# ledgerline

Tiny invoicing library. Every function that talks to the outside world takes a
`transport(path)` function that resolves to the parsed JSON body, so nothing
here opens a socket.

- Run tests: `node --test`
- No dependencies: Node's standard library only.
- Layout: `src/models` (parsers that validate), `src/lib` (shared helpers),
  `src/services` (the public functions).
MD
cat >src/lib/attempt.js <<'JS'
export async function keepTrying(task, attempts) {
  let lastError
  for (let turn = 0; turn < attempts; turn++) {
    try {
      return await task()
    } catch (err) {
      lastError = err
    }
  }
  throw lastError
}
JS
cat >src/lib/money.js <<'JS'
const usd = new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' })

export function renderAmount(cents) {
  return usd.format(cents / 100)
}
JS
cat >src/lib/ids.js <<'JS'
export function nextId(prefix, count) {
  return `${prefix}-${count + 1}`
}
JS
cat >test/attempt.test.js <<'JS'
import { test } from 'node:test'
import assert from 'node:assert/strict'

import { keepTrying } from '../src/lib/attempt.js'

test('keepTrying returns the first success', async () => {
  assert.equal(await keepTrying(async () => 'ok', 3), 'ok')
})

test('keepTrying rethrows the last error itself once attempts run out', async () => {
  const boom = new Error('boom')
  let calls = 0
  await assert.rejects(
    keepTrying(async () => {
      calls++
      throw boom
    }, 2),
    (err) => err === boom,
  )
  assert.equal(calls, 2)
})
JS
cat >test/money.test.js <<'JS'
import { test } from 'node:test'
import assert from 'node:assert/strict'

import { renderAmount } from '../src/lib/money.js'

test('renderAmount groups thousands and pads cents', () => {
  assert.equal(renderAmount(123450), '$1,234.50')
  assert.equal(renderAmount(5), '$0.05')
})
JS
git add -A
git commit -q -m "lib: attempt, money and ids helpers"

# --- commit 2: the validating parser --------------------------------------------
cat >src/models/invoice.js <<'JS'
export function parseInvoice(raw) {
  if (typeof raw?.id !== 'string' || raw.id === '') {
    throw new TypeError('invoice: id must be a non-empty string')
  }
  if (typeof raw.customer !== 'string' || raw.customer === '') {
    throw new TypeError('invoice: customer must be a non-empty string')
  }
  if (!Number.isInteger(raw.totalCents) || raw.totalCents < 0) {
    throw new TypeError('invoice: totalCents must be a non-negative integer')
  }
  return Object.freeze({ id: raw.id, customer: raw.customer, totalCents: raw.totalCents })
}
JS
cat >test/invoice.test.js <<'JS'
import { test } from 'node:test'
import assert from 'node:assert/strict'

import { parseInvoice } from '../src/models/invoice.js'

test('parseInvoice keeps the three fields', () => {
  assert.deepEqual(parseInvoice({ id: 'a', customer: 'Acme', totalCents: 10, extra: 1 }), {
    id: 'a',
    customer: 'Acme',
    totalCents: 10,
  })
})

test('parseInvoice rejects a negative total with a TypeError', () => {
  assert.throws(() => parseInvoice({ id: 'a', customer: 'Acme', totalCents: -1 }), TypeError)
})
JS
git add -A
git commit -q -m "models: parseInvoice validates raw invoices"

# --- commit 3: the service module the feature extends ---------------------------
cat >src/services/invoices.js <<'JS'
export function overdueIds(rows, today) {
  return rows.filter((row) => row.dueDate < today && !row.paid).map((row) => row.id)
}
JS
cat >src/services/customers.js <<'JS'
export function customerLabel(customer) {
  return `${customer.name} <${customer.email}>`
}
JS
cat >test/invoices.test.js <<'JS'
import { test } from 'node:test'
import assert from 'node:assert/strict'

import { overdueIds } from '../src/services/invoices.js'

test('overdueIds lists unpaid invoices due before today', () => {
  const rows = [
    { id: 'a', dueDate: '2026-08-01', paid: false },
    { id: 'b', dueDate: '2026-08-01', paid: true },
    { id: 'c', dueDate: '2026-10-01', paid: false },
  ]
  assert.deepEqual(overdueIds(rows, '2026-09-01'), ['a'])
})
JS
git add -A
git commit -q -m "services: overdue invoices and customer labels"
