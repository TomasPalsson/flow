#!/usr/bin/env bash
set -euo pipefail
mkdir -p src
cat >package.json <<'JSON'
{
  "name": "orders-app",
  "private": true,
  "version": "0.0.0",
  "dependencies": { "express": "^4.19.0", "puppeteer": "^22.0.0" }
}
JSON
cat >src/server.js <<'JS'
const express = require("express");
const { renderInvoice } = require("./invoice");
const app = express();

app.get("/orders/:id/invoice.pdf", async (req, res) => {
  res.type("application/pdf").send(await renderInvoice(req.params.id));
});

module.exports = app;
JS
cat >src/invoice.js <<'JS'
const puppeteer = require("puppeteer");

// HACK: a fresh browser per invoice; reusing one leaked memory. Retry because launch times out on cold start.
async function renderInvoice(id) {
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      const browser = await puppeteer.launch({ timeout: 60000 });
      const page = await browser.newPage();
      await page.setContent(`<h1>Invoice ${id}</h1>`);
      const pdf = await page.pdf();
      await browser.close();
      return pdf;
    } catch (e) {
      if (attempt === 2) throw e;
    }
  }
}

module.exports = { renderInvoice };
JS
