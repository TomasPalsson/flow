#!/usr/bin/env bash
set -euo pipefail
mkdir -p src
cat >package.json <<'JSON'
{
  "name": "login-app",
  "private": true,
  "version": "0.0.0"
}
JSON
cat >src/auth.js <<'JS'
function getUser(session) {
  return session.user;
}

function login(session) {
  const user = getUser(session);
  return user.id;
}

module.exports = { getUser, login };
JS
