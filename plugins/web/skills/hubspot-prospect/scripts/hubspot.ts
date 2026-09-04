#!/usr/bin/env bun
/**
 * HubSpot prospecting writer — the deterministic half of the skill.
 *
 *   bun run scripts/hubspot.ts preflight
 *   bun run scripts/hubspot.ts lookup --domain vr.is [--name "VR"] [--email a@vr.is]
 *   bun run scripts/hubspot.ts write --plan plan.json [--apply]
 *
 * Never improvise these calls in prose. A guessed property name is a silent 400 and a
 * bad enum value fails the entire record create.
 *
 * The token is read from HUBSPOT_SERVICE_KEY and is never printed, logged, or written
 * to any artifact this script produces.
 */

const TOKEN = process.env.HUBSPOT_SERVICE_KEY;
if (!TOKEN) {
  console.error("HUBSPOT_SERVICE_KEY is not set. Export it or put it in .env; never paste it into chat.");
  process.exit(1);
}

const BASE = "https://api.hubapi.com";
const REQUIRED_SCOPES = [
  "crm.objects.companies.read",
  "crm.objects.companies.write",
  "crm.objects.contacts.read",
  "crm.objects.contacts.write",
];

// Search is capped near 5 req/s with no paid increase, and — unlike every other
// endpoint — its responses omit the rate-limit headers, so there is nothing to read
// back. Self-throttle instead of reacting.
let lastSearch = 0;
async function searchGate() {
  const gap = Date.now() - lastSearch;
  if (gap < 250) await new Promise((r) => setTimeout(r, 250 - gap));
  lastSearch = Date.now();
}

class HubError extends Error {
  constructor(readonly status: number, readonly body: any, path: string) {
    super(`${status} ${path}: ${JSON.stringify(body).slice(0, 300)}`);
  }
}

async function hub(path: string, init: { method?: string; body?: unknown } = {}): Promise<any> {
  const isSearch = path.includes("/search");
  for (let attempt = 0; ; attempt++) {
    if (isSearch) await searchGate();
    const res = await fetch(BASE + path, {
      method: init.method ?? "GET",
      headers: { Authorization: `Bearer ${TOKEN}`, "Content-Type": "application/json" },
      body: init.body ? JSON.stringify(init.body) : undefined,
    });
    const text = await res.text();
    const json = text ? safeParse(text) : null;

    if (res.status === 429 && attempt < 5) {
      // Retry-After is SECONDS for direct REST calls. The milliseconds claim belongs to
      // the Workflows retry subsystem. Sanity-check the magnitude regardless.
      const raw = Number(res.headers.get("Retry-After") ?? 0);
      const ms = raw > 3600 ? raw : raw * 1000;
      await new Promise((r) => setTimeout(r, (ms || 1000 * 2 ** attempt) + Math.random() * 250));
      continue;
    }
    if (!res.ok) throw new HubError(res.status, json ?? text, path);
    return json;
  }
}

function safeParse(t: string) { try { return JSON.parse(t); } catch { return t; } }

/** Bare root domain: no scheme, no www., no path, lowercased. */
export function normalizeDomain(input: string): string {
  return input.trim().toLowerCase()
    .replace(/^[a-z]+:\/\//, "")
    .replace(/^www\./, "")
    .replace(/[/?#].*$/, "")
    .replace(/\.$/, "");
}

const log = (s = "") => console.log(s);

// ─────────────────────────────────────────────────────────────── preflight

async function preflight() {
  log("PREFLIGHT");

  let scopes: string[] | null = null;
  let portalId: string | number | undefined;

  // Private-app tokens do NOT work against GET /oauth/v1/access-tokens/{token} — that
  // endpoint is for OAuth tokens and returns "must have the correct format". Verified.
  try {
    const info = await hub("/oauth/v2/private-apps/get/access-token-info", {
      method: "POST", body: { tokenKey: TOKEN },
    });
    scopes = info.scopes ?? [];
    portalId = info.hubId ?? info.hub_id;
  } catch (e) {
    log(`  scope introspection failed: ${(e as Error).message}`);
  }

  // Belt and braces: one cheap real read. 401/403 here is definitive and relies only on
  // confirmed error behaviour, so it works even when introspection doesn't.
  let industryOptions: string[] = [];
  try {
    const prop = await hub("/crm/v3/properties/companies/industry");
    industryOptions = (prop.options ?? []).map((o: any) => o.value);
  } catch (e) {
    const err = e as HubError;
    if (err.status === 401) { log("  401 — token missing, invalid or revoked. Stop."); process.exit(1); }
    if (err.status === 403) {
      const need = err.body?.errors?.[0]?.context?.requiredScopes ?? [];
      log(`  403 MISSING_SCOPES — needs: ${need.join(", ") || "(unnamed)"}`); process.exit(1);
    }
    throw e;
  }

  log(`  portal: ${portalId ?? "unknown"}`);
  if (scopes) {
    const missing = REQUIRED_SCOPES.filter((s) => !scopes!.includes(s));
    for (const s of REQUIRED_SCOPES) log(`  ${scopes.includes(s) ? "OK    " : "MISSING"}  ${s}`);
    if (missing.length) {
      log(`\n  Add these to the private app, then re-run: ${missing.join(", ")}`);
      process.exit(1);
    }
  } else {
    log("  scopes: unknown — the read above succeeded, so reads work; a write will 403 if not permitted");
  }

  // country is a plain string in some portals and an enumeration in others. Read it.
  let countryOptions: string[] = [];
  try {
    const c = await hub("/crm/v3/properties/companies/country");
    countryOptions = (c.options ?? []).map((o: any) => o.value);
    log(`  company.country type: ${c.type}/${c.fieldType}${countryOptions.length ? ` (${countryOptions.length} options)` : " (free text)"}`);
  } catch { log("  company.country: could not read schema"); }

  log(`  industry options: ${industryOptions.length} (leave blank unless an exact match)`);
  log("\nPreflight OK.");
}

// ───────────────────────────────────────────────────────────────── lookup

const COMPANY_PROPS = ["name","domain","hs_additional_domains","website","phone","address",
  "address2","city","state","zip","country","industry","numberofemployees","description",
  "lifecyclestage","hubspot_owner_id"];
const CONTACT_PROPS = ["firstname","lastname","email","jobtitle","phone","mobilephone",
  "hs_linkedin_url","hs_marketable_status","hubspot_owner_id","lifecyclestage"];

async function lookup(args: Record<string, string>) {
  const domain = args.domain ? normalizeDomain(args.domain) : undefined;
  const out: any = { company: { matches: [] }, contact: { matches: [] } };

  if (domain) {
    // EQ, never CONTAINS_TOKEN: the tokeniser splits on the dot, so "vr.is" becomes
    // vr OR is — and every Icelandic domain ends in .is.
    const groups: any[] = [
      { filters: [{ propertyName: "domain", operator: "EQ", value: domain }] },
      { filters: [{ propertyName: "hs_additional_domains", operator: "CONTAINS_TOKEN", value: domain }] },
    ];
    if (args.name) groups.push({ filters: [{ propertyName: "name", operator: "EQ", value: args.name }] });

    const r = await hub("/crm/v3/objects/companies/search", {
      method: "POST",
      body: { filterGroups: groups, properties: COMPANY_PROPS, limit: 50 },
    });
    out.company.total = r.total;
    out.company.matches = (r.results ?? []).map((c: any) => ({
      id: c.id,
      matchedOn: c.properties.domain === domain ? "domain (high)"
        : (c.properties.hs_additional_domains ?? "").includes(domain) ? "additional_domains (medium)"
        : "name (medium — confirm)",
      properties: c.properties,
    }));
  }

  if (args.email) {
    const r = await hub("/crm/v3/objects/contacts/search", {
      method: "POST",
      body: {
        filterGroups: [{ filters: [{ propertyName: "email", operator: "EQ", value: args.email.toLowerCase() }] }],
        properties: CONTACT_PROPS, limit: 10,
      },
    });
    out.contact.total = r.total;
    out.contact.matches = (r.results ?? []).map((c: any) => ({ id: c.id, properties: c.properties }));
  }

  // Multiple companies per domain is legal — domain is not unique-constrained.
  if (out.company.total > 1) out.company.note = "MULTIPLE matches — human must pick, not a binary";
  console.log(JSON.stringify(out, null, 2));
}

// ────────────────────────────────────────────────────────────────── write

/** Fill only empty fields. Both null and "" count as empty — HubSpot gives no signal
 *  distinguishing never-set from explicitly-cleared, and neither has a value to clobber. */
function diffFill(existing: Record<string, any>, proposed: Record<string, any>) {
  const fill: Record<string, string> = {};
  const report: any[] = [];
  for (const [k, v] of Object.entries(proposed)) {
    if (v === undefined || v === null || v === "") continue;
    const cur = existing?.[k];
    if (cur === null || cur === undefined || cur === "") {
      fill[k] = String(v);
      report.push({ field: k, action: "fill", previous: cur ?? null, value: v });
    } else if (String(cur) !== String(v)) {
      report.push({ field: k, action: "kept", existing: cur, scraped: v });
    }
  }
  return { fill, report };
}

const METHODS = ["verbatim", "inferred-pattern", "ladder-fallback"];

/**
 * The provenance gate. This is what makes "never invent a person" a mechanical rule
 * instead of a promise — every property must carry a source before it can be written,
 * and --apply must carry a human approval stamp. Enforced BEFORE any HTTP call.
 * There is deliberately no override flag: an escape hatch defeats the entire point.
 */
function validatePlan(plan: any, apply: boolean): string[] {
  const errs: string[] = [];

  if (apply) {
    if (!plan.approved_by) errs.push("--apply requires `approved_by` (who saw the review table)");
    if (!plan.approved_at) errs.push("--apply requires `approved_at` (ISO timestamp of approval)");
    else if (Number.isNaN(Date.parse(plan.approved_at))) errs.push(`approved_at is not a parseable date: ${plan.approved_at}`);
  }

  for (const obj of ["company", "contact"]) {
    const node = plan[obj];
    if (!node?.properties) continue;
    const sources = node.sources ?? {};
    for (const [field, value] of Object.entries(node.properties)) {
      if (value === undefined || value === null || value === "") continue;
      const s = sources[field];
      if (!s) { errs.push(`${obj}.${field}: no source. Every written field needs sources.${field} = {url, quote, method, captured_at}`); continue; }
      if (!s.url) errs.push(`${obj}.${field}: source has no url`);
      if (!s.quote || String(s.quote).trim().length < 3) errs.push(`${obj}.${field}: source has no verbatim quote`);
      if (!METHODS.includes(s.method)) errs.push(`${obj}.${field}: method must be one of ${METHODS.join(" | ")}, got ${JSON.stringify(s.method)}`);
      if (!s.captured_at || Number.isNaN(Date.parse(s.captured_at))) errs.push(`${obj}.${field}: captured_at must be an ISO timestamp taken at SCRAPE time (the GDPR Art. 14 clock starts there, not at approval)`);
    }
  }
  return errs;
}

async function write(args: Record<string, string>) {
  const plan = JSON.parse(await Bun.file(args.plan).text());
  const apply = "apply" in args;

  // Strip the read-only property BEFORE validating, so it never demands a source for a
  // field that is going to be discarded anyway.
  delete plan.contact?.properties?.hs_marketable_status;
  delete plan.company?.properties?.hs_marketable_status;

  const errs = validatePlan(plan, apply);
  if (errs.length) {
    console.error("PLAN REJECTED — nothing was sent to HubSpot.\n");
    for (const e of errs) console.error(`  - ${e}`);
    console.error("\nThis gate is not bypassable. A field with no source is a field that may have been invented.");
    process.exit(1);
  }

  const audit: any = {
    at: new Date().toISOString(), apply, plan: args.plan,
    approved_by: plan.approved_by ?? null, approved_at: plan.approved_at ?? null,
    sources: { company: plan.company?.sources ?? {}, contact: plan.contact?.sources ?? {} },
    steps: [],
  };

  if (plan.company?.properties?.domain) {
    plan.company.properties.domain = normalizeDomain(plan.company.properties.domain);
  }
  if (plan.contact?.properties?.email) {
    plan.contact.properties.email = plan.contact.properties.email.toLowerCase();
  }

  const say = (s: string) => { log(s); audit.steps.push(s); };

  // ---- company: PATCH existing (fill-empty only) or create
  let companyId: string | undefined = plan.company?.existingId;
  if (companyId) {
    const cur = await hub(`/crm/v3/objects/companies/${companyId}?properties=${COMPANY_PROPS.join(",")}`);
    const { fill, report } = diffFill(cur.properties, plan.company.properties);
    audit.companyDiff = report;
    console.log(JSON.stringify(report, null, 2));
    if (Object.keys(fill).length && apply) {
      await hub(`/crm/v3/objects/companies/${companyId}`, { method: "PATCH", body: { properties: fill } });
      say(`company #${companyId}: filled ${Object.keys(fill).join(", ")}`);
    } else say(`company #${companyId}: ${Object.keys(fill).length} field(s) would be filled`);
  } else if (apply) {
    const c = await hub("/crm/v3/objects/companies", { method: "POST", body: { properties: plan.company.properties } });
    companyId = c.id;
    say(`company created #${companyId}`);
  } else if (plan.company) {
    // Dry run, new company. Print the full property set — for a brand-new record this IS
    // the diff, and it is the only thing a human has to review before --apply.
    say("company WOULD BE CREATED with:");
    console.log(JSON.stringify(plan.company.properties, null, 2));
  }

  // ---- contact: create, and on 409 take the existing ID from the error body and PATCH.
  // Cheaper and race-free versus search-then-create.
  let contactId: string | undefined = plan.contact?.existingId;
  if (plan.contact && apply && !contactId) {
    try {
      const c = await hub("/crm/v3/objects/contacts", { method: "POST", body: { properties: plan.contact.properties } });
      contactId = c.id;
      say(`contact created #${contactId}`);
    } catch (e) {
      const err = e as HubError;
      if (err.status !== 409) throw e;
      contactId = String(err.body?.message ?? "").match(/\b(\d{4,})\b/)?.[1]
        ?? err.body?.errors?.[0]?.context?.ids?.[0];
      if (!contactId) throw e;
      say(`contact exists #${contactId} (409) — switching to fill-empty`);
    }
  }
  if (plan.contact && !apply && !contactId) {
    say("contact WOULD BE CREATED with:");
    console.log(JSON.stringify(plan.contact.properties, null, 2));
  }
  if (plan.contact && contactId) {
    const cur = await hub(`/crm/v3/objects/contacts/${contactId}?properties=${CONTACT_PROPS.join(",")}`);
    const { fill, report } = diffFill(cur.properties, plan.contact.properties);
    audit.contactDiff = report;
    console.log(JSON.stringify(report, null, 2));
    if (Object.keys(fill).length && apply) {
      await hub(`/crm/v3/objects/contacts/${contactId}`, { method: "PATCH", body: { properties: fill } });
      say(`contact #${contactId}: filled ${Object.keys(fill).join(", ")}`);
    }
    say(`contact marketing status (read-only, informational): ${cur.properties.hs_marketable_status ?? "unset"}`);
  }

  // ---- association: read first. A v4 PUT REPLACES the label set on an edge, so
  // blindly writing 279 can strip an existing Primary label.
  if (companyId && contactId) {
    const existing = await hub(`/crm/v4/objects/contacts/${contactId}/associations/companies`);
    const linked = (existing.results ?? []).map((r: any) => String(r.toObjectId));
    if (linked.includes(String(companyId))) {
      say("association already exists — skipped (never re-PUT an existing edge)");
    } else if (apply) {
      await hub(`/crm/v4/objects/contacts/${contactId}/associations/companies/${companyId}`, {
        method: "PUT",
        body: [{ associationCategory: "HUBSPOT_DEFINED", associationTypeId: 1 }], // 1 = primary
      });
      say("association written (typeId 1, primary)");
    } else say("association would be written (typeId 1, primary)");
  } else if (plan.company && plan.contact) {
    // Both records are new, so neither ID exists yet in a dry run — say so explicitly
    // rather than silently printing nothing about the association step.
    say("association would be written after both records exist (contact -> company, typeId 1, primary)");
  }

  audit.companyId = companyId;
  audit.contactId = contactId;
  if (apply) {
    await Bun.write("hubspot-prospect-audit.jsonl",
      (await Bun.file("hubspot-prospect-audit.jsonl").exists()
        ? await Bun.file("hubspot-prospect-audit.jsonl").text() : "") + JSON.stringify(audit) + "\n");
    log("\naudit appended to hubspot-prospect-audit.jsonl");
  } else {
    log("\nDRY RUN — nothing written. Re-run with --apply after approval.");
  }
}

// ─────────────────────────────────────────────────────────────────── main

const [cmd, ...rest] = process.argv.slice(2);
const args: Record<string, string> = {};
for (let i = 0; i < rest.length; i++) {
  if (rest[i].startsWith("--")) {
    const k = rest[i].slice(2);
    args[k] = rest[i + 1]?.startsWith("--") || rest[i + 1] === undefined ? "true" : rest[++i];
  }
}

try {
  if (cmd === "preflight") await preflight();
  else if (cmd === "lookup") await lookup(args);
  else if (cmd === "write") await write(args);
  else { console.error("usage: preflight | lookup --domain X [--name Y] [--email Z] | write --plan p.json [--apply]"); process.exit(1); }
} catch (e) {
  const err = e as HubError;
  console.error(`\nFAILED: ${err.message}`);
  if (err.status === 403) console.error("403 = missing scope. Body names the required scope. Nothing was written by this call.");
  if (err.status === 400) console.error("400 = bad property name or enum value. A bad enum fails the WHOLE create — leave it blank.");
  process.exit(1);
}
