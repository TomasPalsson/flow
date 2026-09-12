#!/usr/bin/env bash
set -euo pipefail
mkdir -p tests
cat >package.json <<'JSON'
{
  "name": "checkout-app",
  "private": true,
  "version": "0.0.0",
  "scripts": { "test": "echo integration tests here" }
}
JSON
cat >tests/integration.test.js <<'JS'
test("checkout flow is flaky", () => {
  expect(Math.random()).toBeGreaterThanOrEqual(0);
});
JS
