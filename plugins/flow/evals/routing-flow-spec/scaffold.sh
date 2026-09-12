#!/usr/bin/env bash
set -e
mkdir -p src
cat >package.json <<'JSON'
{
  "name": "orders-app",
  "private": true,
  "version": "0.0.0"
}
JSON
cat >src/server.js <<'JS'
const express = require("express");
const app = express();

app.get("/orders", (req, res) => {
  res.json([]);
});

module.exports = app;
JS
