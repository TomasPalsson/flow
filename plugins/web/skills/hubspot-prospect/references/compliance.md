---
name: compliance
description: Concrete GDPR Article 14, Icelandic bannskrá, legitimate-interest, provenance and retention behaviours the skill must perform when scraping a named individual into a CRM. Behaviours, not warnings.
---

# Compliance behaviours

Not a lecture. These are rules the skill executes.

Scraping a named person into a CRM is **two legally separate acts** that sales tooling
routinely collapses: (1) *obtaining* personal data from a source other than the person —
governed by **GDPR Article 14**; and (2) *using* it to contact them — governed in Iceland
by a **second statute with a different regulator** (Fjarskiptastofa, not Persónuvernd).
Legitimate interest can cover (1). It does not cover (2), and it does not touch Article 14
at all — Article 14 applies regardless of which lawful basis you used.

## The two counterintuitive findings

**"It's public" is not an exemption.** Publicity affects *how* you obtained data, not
whether it's personal data or whether you need a lawful basis. The Clearview AI
enforcement wave (Italy €20M, Netherlands €30.5M) was built entirely on publicly
accessible data.

**The "disproportionate effort" exemption (Art. 14(5)(b)) collapses on this exact fact
pattern.** It exists for archiving and research at scale where individual notice is
genuinely infeasible. The whole deliverable of this skill is *a working email address* —
so notifying costs nothing, and the "disproportionate" premise fails on its own facts.
Regulators construe it narrowly and have said so.

## Article 14 — verified against the statute

Three independent deadline triggers; the earliest that applies governs:

| Trigger | Deadline |
|---|---|
| (a) Backstop | Within a reasonable period, **at the latest one month** after obtaining |
| (b) First communication with the person | At the latest **at that first communication** |
| (c) First disclosure to another recipient | At the latest **at that first disclosure** |

**(a) is a hard backstop that runs even if you never contact them.** Merely holding the
data starts a one-month clock.

Exactly four exemptions in Art. 14(5): (a) they already have the information;
(b) impossible or disproportionate effort; (c) required by law; (d) professional secrecy.
Only (b) is remotely relevant, and see above.

**Article 21(2)-(3):** the right to object to direct marketing is **unconditional** — no
balancing test once exercised — and must be presented *explicitly, clearly and separately*
from other information. A line in a privacy-policy footer does not satisfy it.

## Iceland

- **Act 90/2018** implements GDPR; **Persónuvernd** is the DPA. No published Persónuvernd
  guidance on scraping or AI-driven CRM enrichment was found — Iceland-specific behaviour
  here is extrapolation, not a citation to a scraping-specific ruling.
- **Bannskrá** — Þjóðskrá keeps a registry of people objecting to direct marketing. Anyone
  marketing from a list of names/emails/phones must compare against it and delete matches
  **before use**. Persónuvernd enforced this against **Síminn** even for an *existing
  customer* whose message already carried an opt-out link — the regulator explicitly
  rejected an in-message unsubscribe as a substitute for the pre-send registry check.
- **Electronic marketing lives in a different statute** — the Electronic Communications
  Act (Act 70/2022), enforced by **Fjarskiptastofa**. Prior consent (opt-in) is required
  for automated calls, SMS and email marketing; a soft opt-in exists for existing
  customers, which **cold prospecting can never claim**.
- "Direct marketing" is defined broadly in Icelandic practice: *all processing directed at
  a defined group with intent to influence them* — not limited to paid promotion.

> **Two statutory citations are deliberately withheld.** The bannskrá article number is
> uncertain — two automated fetches of the same Alþingi page disagreed on whether it is
> Art. 28 or Art. 21. And whether Act 70/2022 preserves the EU ePrivacy natural-person /
> legal-person carve-out (which would soften the B2B position) could not be confirmed.
> **Do not cite a specific article number in user-facing copy, and do not ship a default
> "always cold-email" behaviour, without Icelandic counsel.** Ship conservative.

## Required behaviours

1. **Stamp `captured_at` at scrape time, not approval time.** The Article 14 clock starts
   when you scrape. If a human sits on the approval table for three weeks, three weeks are
   already gone.
2. **Every field carries three sidecars: `source_url`, `captured_at`, `method`**
   (`verbatim` | `inferred-pattern` | `ladder-fallback`). Never write a field with no
   source. Art. 15(1)(g) and 14(2)(f) require producing the source on request — "the
   internet" is not compliant.
3. **Do not invoke "disproportionate effort" to skip the notice.** Default: an Article 14
   notice within 30 days of *scraping*, or delete the record.
4. **Keep the Article 14 notice separate from the sales pitch.** A bare transparency notice
   is not direct marketing; one that also pitches is. Bundling them drags in the bannskrá
   check and the opt-in regime unnecessarily.
5. **Check bannskrá before any marketing send to a named person.** Every ladder rung that
   resolves to an individual. Not required for a generic `info@` mailbox — no personal data
   there. This is a manual step outside HubSpot; surface it as a checklist item in the
   review table, don't assume someone else does it.
6. **Field allow-list.** Refuse, or require explicit override, for anything outside
   work-context data: home address, personal ID number, date of birth, personal
   social-media-sourced mobile, and any health/family/financial data.
7. **Retention: 3 years from capture or last contact, whichever is later** — but flag for
   re-verification or purge at **12 months with no contact at all**. No Icelandic-specific
   number exists; 3 years is the widely-adopted EU practitioner benchmark.
8. **An Art. 21 objection is permanent suppression, never deletion.** Keep a minimal
   suppression record (name + email + objection date) forever, so a future run cannot
   re-scrape and re-contact them. Delete the enrichment fields, not the objection.
9. **Log the legitimate-interest assessment per run.** Purpose, necessity (why this field,
   why this rung), balancing conclusion. Art. 5(2) accountability requires *demonstrating*
   compliance, and automating what was a human judgement call raises that bar, not lowers
   it.
10. **Justify ladder escalation rung by rung.** Jumping to the CEO when an IT manager
    plausibly exists is a *weaker* necessity argument. Only escalate after a documented
    "confirmed absent at this rung" check — which the review table already records.

## Where legitimate interest holds, and where it breaks

The three-part test: **purpose** (real, present, lawful — "we sell IT services and want to
reach IT decision-makers" qualifies) → **necessity** (could a generic inbox achieve the
same?) → **balancing** (does the person's reasonable expectation outweigh the business
interest?). Recital 47 says direct marketing *may* be a legitimate interest — a starting
presumption, not an exemption from balancing.

It is realistically satisfiable inside a narrow envelope: work-context data only,
published by the company or the person in a professional capacity, outreach relevant to
their actual role, proportionate volume, frictionless honoured opt-out.

It breaks the moment any of those fail. The sharpest example: a mobile number the company
publishes on its own staff page as "IT stjóri, sími: …" was disclosed *by the company, in
a professional capacity, for exactly this kind of contact* — defensible. The same person's
mobile pulled from a personal Instagram bio or a leaked-data aggregator was disclosed in a
different context for a different purpose — that fails the balancing test and is a
purpose-limitation violation on top.

## Edge cases with real consequences

- **Sole proprietor whose business email is their only email.** The B2B framing collapses
  — treat as a natural-person/consumer case for both the LIA and marketing analysis. The
  kennitala day-range check flags these.
- **A stale title.** Contacting someone no longer in the role serves no legitimate purpose
  and retroactively undermines the necessity argument. Confidence must include a
  *how-recently-verified* signal distinct from *how-confident-this-is-the-right-person*.
- **Batch mode multiplies the burden, not just the workload.** Each of N companies starts
  an independent one-month clock and an independent bannskrá obligation. A human cannot
  track 50 separate 30-day deadlines from memory — the checkpoint file needs a due-date
  queue. The legal rule directly implies an engineering requirement.
- **Group/holding structures.** The entity whose site you scraped may not employ the
  person. Name the correct employing entity in the notice if discoverable.
- **A source that looks anomalous** — not an official page, not a professional directory,
  possibly a leaked internal document indexed by a search engine — does not inherit a
  lawful basis from whoever published it unlawfully. Lower confidence and flag it.

## Never-overwrite vs the accuracy principle

Not overwriting a human-corrected value is the right product default, but it can leave a
demonstrably stale value in place. This is a business-risk trade-off, not a legal
requirement. Mitigation: **log the delta** — what the scrape found vs what is stored —
even when not writing it, so a human can reconcile. Silent enrichment with no diff record
is worse for accountability even though it is the safer write.
