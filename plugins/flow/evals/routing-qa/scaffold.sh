#!/usr/bin/env bash
set -e
mkdir -p src
cat >package.json <<'JSON'
{
  "name": "cart-app",
  "private": true,
  "version": "0.0.0"
}
JSON
cat >src/cart.js <<'JS'
function calculateTotal(items) {
  return items.reduce((sum, item) => sum + item.price * item.qty, 0);
}

module.exports = { calculateTotal };
JS
