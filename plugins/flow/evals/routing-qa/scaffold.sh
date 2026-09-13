#!/usr/bin/env bash
set -euo pipefail
# Ends in git commits: refuse inside a real checkout (one with a commit), as
# the pipeline scaffolds do; the eval sandbox's placeholder repo has none.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1 &&
	git rev-parse --verify -q HEAD >/dev/null 2>&1; then
	echo "scaffold.sh: refusing to scaffold inside an existing git work tree: $PWD" >&2
	exit 1
fi
git init -q
git config user.email "eval@example.com"
git config user.name "eval-scaffold"
git config commit.gpgsign false
mkdir -p src
cat >package.json <<'JSON'
{
  "name": "cart-app",
  "private": true,
  "version": "0.0.0",
  "scripts": { "test": "node --test" }
}
JSON
cat >src/cart.js <<'JS'
function calculateTotal(items) {
  return items.reduce((sum, item) => sum + item.price * item.qty, 0);
}

module.exports = { calculateTotal };
JS
git add -A
git commit -q -m "base: cart app"
git checkout -q -b feature/cart-discounts
cat >src/discount.js <<'JS'
function applyDiscount(total, code) {
  if (code === "SAVE10") return total * 0.9;
  if (code === "SAVE20") return total * 0.8;
  return total;
}

module.exports = { applyDiscount };
JS
git add -A
git commit -q -m "feat: discount codes"
