---
name: icelandic
description: Icelandic personal-name parsing (patronymics, millinafn), the IT job-title ladder with false friends, kennitala validation, phone and postcode conventions, and the Unicode NFD trap that breaks name matching on þ/ð/æ.
---

# Icelandic names, titles and identifiers

Getting these wrong produces a **technically populated, plausible-looking, factually
wrong** CRM record — the worst kind, because nothing about it looks wrong.

## Names

### The patronymic system

`Dögg Pálsdóttir` = "Dögg, daughter of Páll". Formed from a parent's first name in the
genitive + `-son` / `-dóttir` / `-bur` (gender-neutral, legal since 2021). Governed by
**Lög um mannanöfn nr. 45/1996** as amended — still the current law; a claim that a
wholly new act replaced it in 2021 is false.

Consequences that break Western CRM assumptions:

- **Siblings routinely have different surnames.** One may carry the father's name,
  another the mother's (matronymics are legal and not rare). Combined patro+matronymic
  surnames are legal since 2019 — two `-son`/`-dóttir` tokens is not a parsing bug.
- **Never treat a shared surname as a family or household signal**, and never treat
  differing surnames as evidence people are unrelated. Both inferences are invalid.
- **Never use surname for dedupe or fuzzy person-matching.** `Jónsson` / `Jónsdóttir` are
  among the most common surnames in the country and carry near-zero identifying signal.
  The minimum reliable unique anchor is the **full name string**.
- A surname may be a **bare genitive with no suffix** (gender-neutral registration, Art. 8
  §3). That is valid, not a truncated scrape.

### Family names (ættarnöfn) — the minority case

New family names have been illegal to adopt since 1925/26. Only pre-cutoff holders and
their descendants carry one: Blöndal, Briem, Thorlacius, Thors, Zoëga. These behave like
Western surnames — inherited, shared by siblings. A `Z` in a surname is a historical
family-name marker (Z was dropped from Icelandic orthography in 1973), not a typo.

Distinguishing rule: ends in `-son`/`-dóttir`/`-bur`/bare-genitive → patronymic.
Otherwise → likely a family name.

### Parsing a multi-part name

Statutory cap: given names **and** middle name combined may never exceed three (Art. 1).

A **millinafn** (middle name) can be a relative's given name in the genitive, used alone
with no suffix — structurally identical to how a patronymic is built.

Worked example — `Rósa Steinunn Solveigar Sturludóttir`:

| Token | Role |
|---|---|
| Rósa, Steinunn | two eiginnöfn (given names) |
| Solveigar | millinafn — genitive of Solveig. **Not** a matronymic; no `-dóttir` |
| Sturludóttir | the actual patronymic surname |

→ `firstname = "Rósa Steinunn Solveigar"`, `lastname = "Sturludóttir"`.

**The only reliable rule: the surname is the LAST token, full stop.** Anything
genitive-shaped before it is a millinafn. A right-to-left scan for "first genitive-shaped
token" wrongly grabs `Solveigar`.

The field mapping (patronymic → `lastname`) is **correct** and matches passports and
Iceland's own national systems. Don't "fix" it. Fix the downstream logic that assumes
Western semantics.

### Address and display

- **Icelanders are addressed by first name. Always.** A former Prime Minister is
  "Jóhanna", never "Ms. Sigurðardóttir". There is no surname-based formal register.
  `Dear Mr {{lastname}}` is a hard error, not a style preference — and will usually be
  gender-wrong too.
- When using `firstname` in a greeting, use only the **first word** of that field.
- Icelandic directories alphabetise by **first name**. So: **list position on a staff page
  encodes nothing about seniority.** Use the adjacent title text, never the ordering.
- Any HubSpot view for Icelandic contacts should sort by First Name; a Last Name sort
  looks arbitrary to an Icelandic user even though the data is stored correctly.

### The Unicode trap

The alphabet: `A Á B D Ð E É F G H I Í J K L M N O Ó P R S T U Ú V X Y Ý Þ Æ Ö`
(no C, Q, W, Z natively).

**`þ`, `ð` and `æ` do NOT decompose under NFD.** They are atomic code points with no
combining-mark representation. The six acute vowels (`á é í ó ú ý`) and `ö` **do**
decompose. So a standard "NFD-normalise then strip combining marks" accent-stripper
silently leaves `þ`, `ð`, `æ` untouched — and those are exactly the letters a
non-Icelandic-aware source is most likely to have substituted. `Þórdís` will not match
`Thordis` even after "accent stripping".

Requires an explicit transliteration table on top: `þ→th, ð→d, æ→ae` (and uppercase).
`scripts/icelandic.ts matchkey` implements this.

**Mojibake risk is elevated for Icelandic specifically.** Latin-1 natively includes
`þ ð æ ö`, so UTF-8 misread as Latin-1 produces plausible-looking character soup
(`Ã¾`, `Ã°`, `Ã¶`) rather than obvious replacement characters. A "is this readable text"
check will not catch it. Percent-encode as **UTF-8** bytes (`þ` → `%C3%BE`), never Latin-1.

**Always write the correctly-accented native form to HubSpot.** The transliteration is a
matching aid, never a storage format. Writing `Thordis` is a data-quality regression.

## IT job titles — the ladder

Rank 1 = clearest single decision-maker. See `data/it-titles.csv` for the machine-readable
form.

| Icelandic | English | Runs IT? | Rank |
|---|---|---|---|
| Framkvæmdastjóri upplýsingatæknisviðs | CIO, exec-board level | Runs | 1 |
| Forstöðumaður upplýsingatæknisviðs / -deildar | Head of IT Division | Runs | 2 |
| Sviðsstjóri upplýsingatæknisviðs | Division Head, IT | Runs | 2 |
| Upplýsingatæknistjóri | IT Manager | Runs | 3 — best default SMB target |
| IT-stjóri | IT Manager (informal) | Runs | 3 |
| Tæknistjóri | CTO | Runs — **verify**: in a non-tech company can mean head of technical *facilities* | 3–4 |
| Þróunarstjóri | Head of Development | **Ambiguous** — may be real-estate or business development | unranked, needs context |
| Gagnastjóri | Data Manager | Adjacent, not "runs IT" | 5 |
| Kerfisstjóri | Systems Administrator | Works in IT | 6 |
| Netstjóri | Network Administrator | Works in IT | 6 |
| Tölvunarfræðingur | Computer Scientist | Works in IT | 7 |

### Two false friends — both will misfire

- **`Upplýsingafulltrúi` is a PR / communications spokesperson.** Media relations, public
  messaging. Zero IT scope. An English keyword match on `upplýsinga-` ("information-")
  hits this exactly. **Never target it.**
- **`Tölvunarfræðingur` is a legally protected academic credential** (Law nr. 8/1996)
  meaning "holds a CS degree" — not a rank. A junior developer and a principal engineer
  both hold it correctly. The `-fræðingur` ("scientist") ending reads as senior and isn't.

### Match compositionally, not as a fixed list

Icelandic titles compose productively: `[rank word] + [domain word] + case-inflected
suffix`. Match `rank ∈ {framkvæmdastjóri, forstöðumaður, sviðsstjóri, …}` **AND**
`domain ∈ {upplýsingatækni-, tækni-, kerfis-, net-, gagna-, …}`. A fixed enum of whole
titles will miss valid real combinations.

### Fallback ladder — general titles

| Icelandic | Meaning | Note |
|---|---|---|
| Framkvæmdastjóri | Managing Director | **Legally mandatory** for every hf./ehf. — highest-hit-rate fallback, registered in fyrirtækjaskrá |
| Forstjóri | CEO | Larger/listed companies and state institutions. Banks use *bankastjóri* |
| Rekstrarstjóri | Operations Manager | One rung below framkvæmdastjóri |
| Skrifstofustjóri | Office Manager | At small offices, frequently the de facto IT/purchasing contact |
| Fjármálastjóri | CFO | Often the actual IT budget-holder at small firms — a legitimate rung, not a last resort |
| Formaður | Chair | For félög (unions, associations). Such entities often have no framkvæmdastjóri at all |

## Kennitala

Format `DDMMYY-NNCP`. Validate with `scripts/icelandic.ts kennitala`.

- **Entity vs person:** a company kennitala adds **40** to the day field, so the first
  digit lands in 4–7 (range 41–71). First digit 0–3 → a *person's* national ID.
- **Checksum:** weights `3,2,7,6,5,4,3,2` over the first 8 digits;
  `check = 11 − (sum mod 11)`, except `sum mod 11 == 0` → check digit `0`, and
  `sum mod 11 == 1` is never issued. Validators missing both special cases misvalidate.
- A **company** kennitala is ordinary public-register data and fine as a Company property.
- A **sole proprietorship** (einstaklingsrekstur) is registered under the owner's
  *personal* kennitala — national-ID-grade personal data. The day-range heuristic flags
  this; treat it as personal data, not company data.
- VSK (VAT) number is the same digits as the kennitala. Not every entity is VAT-registered
  — a missing VSK number is not a scraping failure.

## Phone numbers

**7 digits, no trunk prefix zero.** Generic European normalisers that "strip the leading 0
then add the country code" **delete a real digit** from an already-correct Icelandic
number. E.164 form is `+354` + the 7 digits.

Landline prefixes 4–5, mobile 6–8, is a reasonable heuristic but not guaranteed given
number portability. Don't assert it.

## Addresses and postcodes

- Street name and house number are **one token, no comma**: `Hlíðasmári 8`.
- Postcode comes **before** the city: `201 Kópavogur`, `105 Reykjavík`.
- **Do not populate `state`.** Icelandic municipalities are not part of the postal address.
- Floor/apartment is appended as free text (`Skúlagata 20, 3. hæð`) — no structured unit
  field to parse out. Keep it in the single address line.
- Three-digit codes assigned from 101 in Reykjavík, increasing roughly clockwise:
  Reykjavík 101–116, Seltjarnarnes 170, Kópavogur 200–203, Garðabær 210/212,
  Hafnarfjörður 220–225, Mosfellsbær 270–271, Reykjanesbær 230–262, Akranes 300–301,
  Borgarnes 310–311, Ísafjörður ~400, Akureyri 600–603, Egilsstaðir 700–701,
  Selfoss 800–801, Vestmannaeyjar 900/902.

> **Correction to a widely-repeated claim.** You will see it asserted that the last digit
> encodes delivery type (`0`/`5` town, `1`/`6` rural, `2` PO-box-only). **That does not
> generalise and must not be applied as an absolute rule.** It holds only *within one
> town's own allocation block* — 300/301/302 Akranes, 600/601/602 Akureyri. Two
> counter-examples kill the general form: **201 Kópavogur** is dense urban office
> territory (it would read as "rural"), and **112 Reykjavík** is a large residential
> district (it would read as "PO box only"). Reykjavík's 101–116 are *district* codes with
> no delivery-type meaning at all. `scripts/icelandic.ts postcode` deliberately reports
> the region and refuses to classify.

## Registries

**There is no free, self-serve, programmatic API for Icelandic company data.** This is an
architectural fact, not a detail — the strategy is free web lookups, not an integration.

- **Fyrirtækjaskrá (Skatturinn)** — the authoritative register.
  `skatturinn.is/fyrirtaekjaskra/leit/`. Search by name, kennitala, VSK number, or address
  — **address search requires the dative case** (`Laugavegi`, not `Laugavegur`). Only one
  field need be filled. Free hit returns name, kennitala, status, registered address.
  **Board members and prókúruhafar are available as a free "yfirlit" (overview)** through
  the site's own lookup flow. A notarised vottorð costs 1,500 ISK and is a manual 1–2 day
  process — never needed here.
- **Já Gagnatorg** (`api.ja.is`) — the only real API. Endpoints like
  `GET /v1/businesses/{kennitala}` return director and board kennitölur, ISAT class, share
  capital, VSK numbers. Requires a negotiated contract; **pricing is never published**, and
  ID-adjacent "starred" fields are excluded from the basic tier. Not a viable dependency
  unless APRÓ contracts separately.
- **ja.is** and **1819.is** — free consumer front-ends onto the same RSK register data.
  Good secondary cross-check for a company's public contact email.
- **Creditinfo** / **Keldan** — commercial, contract-led, no public API. Keldan's PEP
  database drew a Persónuvernd ruling in December 2025 — this space is actively regulated.

## Phone: one more trap

There is **no extension convention** in Iceland. A number printed next to a named staff
member is either their genuine 7-digit direct dial, or simply a repeat of the switchboard.
**If it matches the company's general number, treat it as low-confidence for that
individual** — do not write it to `phone` as if it were personal.

## Which Icelandic organisations publish IT staff

Banks (Landsbankinn, Arion) consistently name a senior, board-adjacent IT head, often on
an annual-report microsite. Unions, insurers, universities and municipalities sometimes.
Most other organisations surface nobody above kerfisstjóri — which makes the fallback
ladder the realistic **primary** path, not an edge case.
