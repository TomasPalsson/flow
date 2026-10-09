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
git init -q -b flow/orders-by-customer
git config user.email "dev@example.com"
git config user.name "Dev"
git config commit.gpgsign false

# Fixed commit dates make every sha reproducible, so a postcheck can rebuild the
# pristine tree and compare files against it.
_n=0
commit() {
	_n=$((_n + 1))
	local t=$((1790000000 + _n * 3600))
	git add -A
	GIT_AUTHOR_DATE="@$t +0000" GIT_COMMITTER_DATE="@$t +0000" git commit -q -m "$1"
}

mkdir -p src test/support
cat >.gitignore <<'TXT'
node_modules/
.specs/.next-call-count
TXT
cat >package.json <<'JSON'
{
  "name": "orderdesk",
  "version": "0.0.0",
  "private": true,
  "type": "module",
  "scripts": {
    "test": "node --test"
  }
}
JSON
cat >src/schema.js <<'JS'
export function createSchema(db) {
  db.exec(
    "CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT NOT NULL);" +
      "CREATE TABLE orders (id INTEGER PRIMARY KEY, customer_id INTEGER NOT NULL REFERENCES customers(id)," +
      " status TEXT NOT NULL, total_cents INTEGER NOT NULL, placed_at TEXT NOT NULL);",
  );
}
JS
cat >src/query.js <<'JS'
export function query(db, sql, params = []) {
  return db.prepare(sql).all(...params);
}
JS
cat >src/format.js <<'JS'
export function formatTotal(cents) {
  const dollars = Math.floor(cents / 100);
  const rest = String(cents % 100).padStart(2, "0");
  return "$" + dollars + "." + rest;
}
JS
cat >src/orders.js <<'JS'
import { query } from "./query.js";

const ORDER_SELECT =
  "SELECT o.id, c.name AS customer, o.total_cents, o.placed_at" +
  " FROM orders o JOIN customers c ON c.id = o.customer_id";
const ORDER_BY = " ORDER BY o.placed_at, o.id";

export function listOrders(db) {
  return query(db, ORDER_SELECT + ORDER_BY);
}

export function findOrdersByStatus(db, status) {
  return query(db, ORDER_SELECT + " WHERE o.status = ?" + ORDER_BY, [status]);
}

// Kept for the old admin search box until it is retired.
export function searchOrdersLegacy(db, term) {
  return db.prepare(`${ORDER_SELECT} WHERE c.name LIKE '%${term}%'${ORDER_BY}`).all();
}
JS
cat >src/index.js <<'JS'
export { createSchema } from "./schema.js";
export { formatTotal } from "./format.js";
export { findOrdersByStatus, listOrders, searchOrdersLegacy } from "./orders.js";
JS
cat >test/support/db.js <<'JS'
import { DatabaseSync } from "node:sqlite";

import { createSchema } from "../../src/schema.js";

export function seededDb() {
  const db = new DatabaseSync(":memory:");
  createSchema(db);
  db.exec(
    "INSERT INTO customers (id, name) VALUES (1, 'Ada Lovelace'), (2, 'Grace Hopper');" +
      "INSERT INTO orders (id, customer_id, status, total_cents, placed_at) VALUES" +
      " (10, 1, 'paid', 1250, '2026-09-01')," +
      " (11, 2, 'open', 990, '2026-09-02')," +
      " (12, 1, 'open', 305, '2026-09-03');",
  );
  return db;
}
JS
cat >test/orders.test.js <<'JS'
import assert from "node:assert/strict";
import { test } from "node:test";

import { findOrdersByStatus, listOrders } from "../src/orders.js";
import { seededDb } from "./support/db.js";

const plain = (rows) => rows.map((row) => ({ ...row }));

test("listOrders returns every order oldest first", () => {
  const rows = plain(listOrders(seededDb()));
  assert.deepEqual(
    rows.map((row) => row.id),
    [10, 11, 12],
  );
  assert.deepEqual(rows[0], { id: 10, customer: "Ada Lovelace", total_cents: 1250, placed_at: "2026-09-01" });
});

test("findOrdersByStatus keeps only that status", () => {
  const rows = plain(findOrdersByStatus(seededDb(), "open"));
  assert.deepEqual(
    rows.map((row) => row.id),
    [11, 12],
  );
});
JS
cat >test/format.test.js <<'JS'
import assert from "node:assert/strict";
import { test } from "node:test";

import { formatTotal } from "../src/format.js";

test("formatTotal pads the cents", () => {
  assert.equal(formatTotal(305), "$3.05");
});
JS
cat >README.md <<'MD'
# orderdesk

Order lookups for the support desk, on the built-in `node:sqlite`.

Run tests: `node --test`
MD
commit "base: orderdesk schema, query helper, order lookups"
BASE=$(git rev-parse --short HEAD)

mkdir -p .specs/001-orders-by-customer
printf '001-orders-by-customer\n' >.specs/.current
cat >.specs/001-orders-by-customer/spec.md <<'MD'
# Spec — Orders by customer

Support agents look a customer's orders up by typing the customer's name into a search box.

## Requirements
- R1: `findOrdersByCustomer(db, name)` in `src/orders.js` returns the orders of the customer
  whose name equals `name` exactly, in the same row shape and order as `listOrders`.
- R2: `name` is whatever the agent typed. Quotes, percent signs and SQL fragments in it are
  just characters: they must never change which rows match, and a name with an apostrophe
  (Mary O'Brien) must find her orders.
- R3: A name no customer has returns an empty array.

## Acceptance
- A1: Ada Lovelace's orders come back oldest first and nobody else's do.
- A2: `' OR '1'='1` returns no orders; `Mary O'Brien` returns Mary's.
- A3: an unknown name returns `[]`.
MD
cat >.specs/001-orders-by-customer/NOTES.md <<'MD'
- Assumption: names match exactly and case-sensitively; fuzzy search is a later feature — confidence 0.8
MD
cat >.specs/001-orders-by-customer/TASKS.md <<TASKS
# Tasks — Orders by customer
Spec: spec.md · Design: none · Base: $BASE · Route: bounded · Test: \`node --test\`
Approved: 2026-09-28 by user

## Behaviors
| ID | Given / When / Then | Task | Proven by |
|----|---------------------|------|-----------|
| B1 (P0) | Given a customer name, when I look their orders up, then I get exactly their orders oldest first | T001 | findOrdersByCustomer returns only that customer's orders |
| B2 (P0) | Given a name holding quotes or SQL, when I look it up, then it never widens the match | T001 | findOrdersByCustomer treats SQL in a name as text |

## Phase 1 — Orders by customer
Goal: support agents can find a customer's orders by the name they typed.
Independent test: \`node --test\` — green.
- [ ] T001 findOrdersByCustomer (B1, B2) — files: src/orders.js, test/orders.test.js — verify: \`node --test test/orders.test.js\`

## Gates
- [ ] G001 project gates clean — files: . — verify: \`flow check --fix\`
TASKS
commit "plan: orders by customer, approved"
