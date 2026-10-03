import assert from "node:assert/strict";
import { test } from "node:test";
import { DatabaseSync } from "node:sqlite";

import { findOrdersByCustomer, listOrders } from "../src/orders.js";
import { createSchema } from "../src/schema.js";

const plain = (rows) => rows.map((row) => ({ ...row }));

function db() {
  const conn = new DatabaseSync(":memory:");
  createSchema(conn);
  conn.exec(
    "INSERT INTO customers (id, name) VALUES (1, 'Ada Lovelace'), (2, 'Grace Hopper'), (3, 'Mary O''Brien'), (4, 'Ada');" +
      "INSERT INTO orders (id, customer_id, status, total_cents, placed_at) VALUES" +
      " (30, 1, 'open', 100, '2026-09-05')," +
      " (31, 2, 'paid', 200, '2026-09-02')," +
      " (32, 1, 'paid', 300, '2026-09-01')," +
      " (33, 3, 'open', 400, '2026-09-03')," +
      " (34, 1, 'open', 500, '2026-09-05')," +
      " (35, 4, 'open', 600, '2026-09-04');",
  );
  return conn;
}

test("returns only that customer's orders, oldest first, with ties broken by id", () => {
  const rows = plain(findOrdersByCustomer(db(), "Ada Lovelace"));
  assert.deepEqual(
    rows.map((row) => row.id),
    [32, 30, 34],
  );
  assert.deepEqual(rows[0], { id: 32, customer: "Ada Lovelace", total_cents: 300, placed_at: "2026-09-01" });
});

test("has the same row shape as listOrders", () => {
  const conn = db();
  const listed = plain(listOrders(conn)).filter((row) => row.customer === "Grace Hopper");
  assert.deepEqual(plain(findOrdersByCustomer(conn, "Grace Hopper")), listed);
});

test("matches the name exactly, not as a prefix or a pattern", () => {
  const conn = db();
  assert.deepEqual(
    plain(findOrdersByCustomer(conn, "Ada")).map((row) => row.id),
    [35],
  );
  assert.deepEqual(findOrdersByCustomer(conn, "%"), []);
  assert.deepEqual(findOrdersByCustomer(conn, "Ada%"), []);
  assert.deepEqual(findOrdersByCustomer(conn, "ada lovelace"), []);
});

test("an SQL fragment in the name never widens the match", () => {
  const conn = db();
  assert.deepEqual(findOrdersByCustomer(conn, "' OR '1'='1"), []);
  assert.deepEqual(findOrdersByCustomer(conn, "x' OR 1=1 --"), []);
  assert.deepEqual(findOrdersByCustomer(conn, "'; DROP TABLE orders; --"), []);
  assert.equal(listOrders(conn).length, 6);
});

test("a name with an apostrophe finds that customer's orders", () => {
  const rows = plain(findOrdersByCustomer(db(), "Mary O'Brien"));
  assert.deepEqual(
    rows.map((row) => row.id),
    [33],
  );
});

test("an unknown name returns an empty array", () => {
  assert.deepEqual(findOrdersByCustomer(db(), "Nobody"), []);
  assert.deepEqual(findOrdersByCustomer(db(), ""), []);
});
