#!/usr/bin/env bash
set -euo pipefail
mkdir -p src/api src/db
cat >package.json <<'JSON'
{
  "name": "legacy-app",
  "private": true,
  "version": "0.0.0"
}
JSON
cat >src/api/routes.js <<'JS'
function handle(req, res) {
  res.end("ok");
}

module.exports = { handle };
JS
cat >src/db/connection.js <<'JS'
function connect() {
  return { connected: true };
}

module.exports = { connect };
JS
