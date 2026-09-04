#!/usr/bin/env bun
/**
 * Icelandic normalisation helpers. These exist because each one is a rule an LLM
 * reliably gets wrong by applying a plausible general-purpose heuristic.
 *
 *   bun run ${CLAUDE_PLUGIN_ROOT}/skills/hubspot-prospect/scripts/icelandic.ts kennitala 5501692919
 *   bun run ${CLAUDE_PLUGIN_ROOT}/skills/hubspot-prospect/scripts/icelandic.ts phone "564 4100"
 *   bun run ${CLAUDE_PLUGIN_ROOT}/skills/hubspot-prospect/scripts/icelandic.ts name "Rósa Steinunn Solveigar Sturludóttir"
 *   bun run ${CLAUDE_PLUGIN_ROOT}/skills/hubspot-prospect/scripts/icelandic.ts matchkey "Þórdís Æsa Guðmundsdóttir"
 *   bun run ${CLAUDE_PLUGIN_ROOT}/skills/hubspot-prospect/scripts/icelandic.ts title "Forstöðumaður upplýsingatæknisviðs"
 *   bun run ${CLAUDE_PLUGIN_ROOT}/skills/hubspot-prospect/scripts/icelandic.ts postcode 201
 */

// ───────────────────────────────────────────────────────────── kennitala

export function kennitala(input: string) {
  const d = input.replace(/\D/g, "");
  if (d.length !== 10) return { valid: false, reason: `expected 10 digits, got ${d.length}` };

  // Company/legal-entity kennitölur add 40 to the day field, so day lands 41-71.
  // A person's is 01-31. This is the cheap entity-vs-person discriminator.
  const day = Number(d.slice(0, 2));
  const kind = day >= 41 && day <= 71 ? "entity" : day >= 1 && day <= 31 ? "person" : "invalid-day";

  const weights = [3, 2, 7, 6, 5, 4, 3, 2];
  const sum = weights.reduce((a, w, i) => a + w * Number(d[i]), 0);
  const rem = sum % 11;
  // Two special cases naive validators miss: rem 0 → check digit 0, and rem 1 is
  // never issued (it would need a two-digit check).
  if (rem === 1) return { valid: false, kind, reason: "remainder 1 is never issued" };
  const expected = rem === 0 ? 0 : 11 - rem;
  const valid = expected === Number(d[8]);

  return {
    valid, kind, formatted: `${d.slice(0, 6)}-${d.slice(6)}`,
    note: kind === "person"
      ? "PERSON kennitala — national-ID-grade personal data. If this is a sole proprietorship, treat as personal data, not company data."
      : "Company kennitala — ordinary public-register data, fine as a Company property.",
  };
}

// ───────────────────────────────────────────────────────────────── phone

export function phone(input: string) {
  const raw = input.replace(/[^\d+]/g, "");
  let d = raw.replace(/^\+?354/, "").replace(/^\+/, "");
  // NOTE: Icelandic numbers are 7 digits with NO trunk prefix. Do not strip a leading
  // zero — a generic European normaliser would delete a real digit here.
  if (d.length !== 7) return { valid: false, e164: null, reason: `expected 7 national digits, got ${d.length}` };
  return {
    valid: true,
    e164: `+354${d}`,
    hint: /^[6-8]/.test(d) ? "likely mobile" : /^[4-5]/.test(d) ? "likely landline" : "unknown range",
    caveat: "prefix ranges are a heuristic only — number portability breaks the guarantee",
  };
}

// ────────────────────────────────────────────────────────────────── name

export function parseName(full: string) {
  const parts = full.trim().split(/\s+/);
  if (parts.length === 1) return { firstname: parts[0], lastname: "", note: "mononym — leave lastname empty rather than duplicating" };

  // The ONLY safe rule: the surname is the LAST token. A millinafn (middle name) is
  // often a relative's given name in the genitive and looks structurally identical to
  // a patronymic — a right-to-left scan for "first genitive-shaped token" grabs it
  // wrongly. Position, not morphology.
  const lastname = parts[parts.length - 1];
  const firstname = parts.slice(0, -1).join(" ");
  const isPatronymic = /(son|dóttir|bur)$/i.test(lastname);

  return {
    firstname, lastname,
    surnameType: isPatronymic ? "patronymic/matronymic" : "family name (ættarnafn) or foreign",
    callingName: parts[0],
    warnings: [
      "Address by FIRST name only. 'Dear Mr {{lastname}}' is a hard error in Icelandic.",
      isPatronymic
        ? "Patronymic — NOT a family name. Never use for dedupe, household grouping, or fuzzy person-matching; siblings differ."
        : "Non-patronymic surname — likely an inherited ættarnafn, behaves like a Western surname.",
      parts.length > 2 ? `'${parts[parts.length - 2]}' is a middle name (millinafn) and belongs in firstname, not lastname.` : null,
    ].filter(Boolean),
  };
}

/** Fuzzy cross-source matching key. NEVER store this — write the accented native form. */
export function matchKey(s: string) {
  return s
    .normalize("NFD").replace(/[\u0300-\u036f]/g, "")  // folds á é í ó ú ý and ö
    // þ, ð and æ are atomic code points with NO combining-mark decomposition, so NFD
    // leaves them untouched. They need an explicit table — and they are exactly the
    // letters a non-Icelandic source is most likely to have substituted.
    .replace(/Þ/g, "Th").replace(/þ/g, "th")
    .replace(/Ð/g, "D").replace(/ð/g, "d")
    .replace(/Æ/g, "Ae").replace(/æ/g, "ae")
    .toLowerCase().replace(/\s+/g, " ").trim();
}

// ───────────────────────────────────────────────────────────────── title

const RANK_WORDS: Record<string, number> = {
  "framkvæmdastjóri": 1, "forstöðumaður": 2, "sviðsstjóri": 2, "forstjóri": 1,
};
const IT_DOMAIN = /(upplýsingatækni|tækni|kerfis|net|gagna|tölvu)/i;

export function title(t: string) {
  const low = t.toLowerCase();

  // False friend: "upplýsingafulltrúi" is a PR/communications spokesperson. An English
  // keyword match on "upplýsinga-" (information-) hits this exactly. Check it FIRST.
  if (/upplýsingafulltrú/i.test(low)) {
    return { rank: null, runsIT: false, verdict: "NOT IT — this is a PR/communications spokesperson. Do not target." };
  }
  // "tölvunarfræðingur" is a legally protected academic credential (a CS degree), not a
  // rank. The -fræðingur ending reads senior and isn't.
  if (/tölvunarfræðing/i.test(low)) {
    return { rank: 7, runsIT: false, verdict: "Works in IT — academic credential, individual contributor. Not a decision-maker." };
  }
  if (/^(kerfisstjóri|netstjóri)/i.test(low)) {
    return { rank: 6, runsIT: false, verdict: "Works in IT — technical operator, not the budget-holder." };
  }
  if (/þróunarstjóri/i.test(low)) {
    return { rank: null, runsIT: null, verdict: "AMBIGUOUS — 'development' may be software, business or real-estate. Needs company context before use." };
  }
  if (/(upplýsingatæknistjóri|it-?stjóri)/i.test(low)) {
    return { rank: 3, runsIT: true, verdict: "Runs IT — best default SMB target." };
  }
  if (/^tæknistjóri/i.test(low)) {
    return { rank: 3.5, runsIT: true, verdict: "Likely CTO — VERIFY: in a non-tech company can mean head of technical facilities." };
  }
  if (/gagnastjóri/i.test(low)) {
    return { rank: 5, runsIT: false, verdict: "Data manager — adjacent to IT, does not run it." };
  }

  // Titles compose productively: [rank word] + [domain word] + inflected suffix. Match
  // both axes rather than a closed set of whole strings, or valid combinations are missed.
  const rankWord = Object.keys(RANK_WORDS).find((w) => low.includes(w));
  if (rankWord && IT_DOMAIN.test(low)) {
    return { rank: RANK_WORDS[rankWord], runsIT: true, verdict: `Runs IT — compositional match (${rankWord} + IT domain word).` };
  }
  if (rankWord) {
    const general: Record<string, string> = {
      "framkvæmdastjóri": "Managing Director — legally mandatory for every hf./ehf. Highest-hit-rate fallback rung.",
      "forstjóri": "CEO — larger/listed companies and state institutions.",
      "forstöðumaður": "Department head — check which department.",
      "sviðsstjóri": "Division head — check which division.",
    };
    return { rank: null, runsIT: false, verdict: `Fallback ladder: ${general[rankWord]}` };
  }
  return { rank: null, runsIT: null, verdict: "Unrecognised — do not assume IT. Quote the title verbatim and let the reviewer judge." };
}

// ─────────────────────────────────────────────────────────────── postcode

export function postcode(p: string) {
  const d = p.replace(/\D/g, "");
  if (d.length !== 3) return { valid: false, reason: "Icelandic postcodes are 3 digits" };
  const n = Number(d);

  // The "last digit = delivery type" convention (base = town, +1 = rural, +2 = PO box)
  // holds only WITHIN a single town's allocation block — 300/301/302 Akranes,
  // 600/601/602 Akureyri. It does NOT generalise to an absolute last digit.
  // Counter-examples that disprove the general form: 201 Kópavogur (dense urban, would
  // read as "rural") and 112 Reykjavík (large residential district, would read as
  // "PO box only"). Reykjavík's 101-116 are district codes, not a delivery-type series.
  // So: do not classify. Report the region and let a human judge.
  const regions: [number, number, string][] = [
    [101, 116, "Reykjavík"], [170, 172, "Seltjarnarnes"], [200, 203, "Kópavogur"],
    [210, 212, "Garðabær"], [220, 225, "Hafnarfjörður"], [230, 262, "Reykjanesbær / Suðurnes"],
    [270, 276, "Mosfellsbær"], [300, 301, "Akranes"], [310, 311, "Borgarnes"],
    [400, 401, "Ísafjörður"], [600, 603, "Akureyri"], [700, 701, "Egilsstaðir"],
    [800, 801, "Selfoss"], [900, 902, "Vestmannaeyjar"],
  ];
  const region = regions.find(([lo, hi]) => n >= lo && n <= hi)?.[2];
  const inMultiCodeTown = n >= 101 && n <= 116;

  return {
    valid: true,
    code: d,
    region: region ?? "unknown — verify against a postcode list",
    deliveryType: "not classified",
    note: inMultiCodeTown
      ? "Reykjavík 101-116 are district codes; no delivery-type meaning in the last digit."
      : "Within a town's own block the base code is town delivery, +1 rural, +2 PO box — but only relative to that town's base, which this function does not assume. Verify before treating an address as a mailbox.",
  };
}

// ──────────────────────────────────────────────────────────────────── cli

const [cmd, ...rest] = process.argv.slice(2);
const arg = rest.join(" ");
const table: Record<string, (s: string) => unknown> = {
  kennitala, phone, name: parseName, matchkey: matchKey, title, postcode,
};
if (!cmd || !table[cmd] || !arg) {
  console.error("usage: kennitala|phone|name|matchkey|title|postcode <value>");
  process.exit(1);
}
console.log(JSON.stringify(table[cmd](arg), null, 2));
