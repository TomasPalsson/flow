import { test } from 'node:test'
import assert from 'node:assert/strict'

import { getInvoiceSummary, listInvoiceSummaries, overdueIds } from '../src/services/invoices.js'

const raw = (id, cents = 123450) => ({ id, customer: 'Acme Ltd', totalCents: cents })
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms))

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

test('getInvoiceSummary formats a small total with padded cents', async () => {
  const summary = await getInvoiceSummary(async () => raw('inv-8', 5), 'inv-8')
  assert.equal(summary.total, '$0.05')
})

test('a transport that fails twice then succeeds is retried into a result', async () => {
  let calls = 0
  const transport = async () => {
    calls++
    if (calls < 3) throw new Error(`flaky ${calls}`)
    return raw('inv-9')
  }
  assert.equal((await getInvoiceSummary(transport, 'inv-9')).id, 'inv-9')
  assert.equal(calls, 3)
})

test('three failures reject with the last error object itself', async () => {
  const errors = [new Error('one'), new Error('two'), new Error('three')]
  let calls = 0
  const transport = async () => {
    throw errors[calls++]
  }
  await assert.rejects(getInvoiceSummary(transport, 'inv-1'), (err) => err === errors[2])
  assert.equal(calls, 3)
})

test('a transport that throws synchronously is retried and its error propagates', async () => {
  const boom = new RangeError('sync boom')
  let calls = 0
  const transport = () => {
    calls++
    throw boom
  }
  await assert.rejects(getInvoiceSummary(transport, 'inv-1'), (err) => err === boom)
  assert.equal(calls, 3)
})

test('a malformed response is not retried and the parser error surfaces', async () => {
  let calls = 0
  const transport = async () => {
    calls++
    return { id: 'inv-2', customer: 'Acme Ltd', totalCents: -5 }
  }
  await assert.rejects(getInvoiceSummary(transport, 'inv-2'), (err) => {
    assert.ok(err instanceof TypeError)
    assert.match(err.message, /totalCents/)
    return true
  })
  assert.equal(calls, 1)
})

test('listInvoiceSummaries looks ids up one at a time and keeps id order', async () => {
  const delays = { a: 30, b: 1, c: 15 }
  const seen = []
  let inFlight = 0
  let maxInFlight = 0
  const transport = async (path) => {
    const id = path.split('/').pop()
    inFlight++
    maxInFlight = Math.max(maxInFlight, inFlight)
    seen.push(id)
    await sleep(delays[id])
    inFlight--
    return raw(id, 100)
  }
  const summaries = await listInvoiceSummaries(transport, ['a', 'b', 'c'])
  assert.deepEqual(
    summaries.map((summary) => summary.id),
    ['a', 'b', 'c'],
  )
  assert.equal(summaries[0].total, '$1.00')
  assert.deepEqual(seen, ['a', 'b', 'c'])
  assert.equal(maxInFlight, 1)
})

test("listInvoiceSummaries rejects with the failing lookup's original error", async () => {
  const boom = new Error('b is down')
  const transport = async (path) => {
    if (path.endsWith('/b')) throw boom
    return raw(path.split('/').pop())
  }
  await assert.rejects(listInvoiceSummaries(transport, ['a', 'b', 'c']), (err) => err === boom)
})

test('listInvoiceSummaries starts no lookup after a failure', async () => {
  const seen = []
  const transport = async (path) => {
    seen.push(path.split('/').pop())
    if (path.endsWith('/b')) throw new Error('b is down')
    return raw('a')
  }
  await assert.rejects(listInvoiceSummaries(transport, ['a', 'b', 'c', 'd']))
  assert.equal(seen.includes('c'), false)
  assert.equal(seen.includes('d'), false)
})

test('listInvoiceSummaries of no ids resolves to an empty list without calling the transport', async () => {
  let calls = 0
  const transport = async () => {
    calls++
    return raw('x')
  }
  assert.deepEqual(await listInvoiceSummaries(transport, []), [])
  assert.equal(calls, 0)
})

test('overdueIds is unchanged', () => {
  const rows = [{ id: 'a', dueDate: '2026-08-01', paid: false }]
  assert.deepEqual(overdueIds(rows, '2026-09-01'), ['a'])
})
