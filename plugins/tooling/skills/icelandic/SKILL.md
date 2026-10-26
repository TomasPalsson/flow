---
name: icelandic
description: >
  Write, translate, fix or proofread Icelandic that reads like a native wrote it, and keep the
  English words Icelanders actually say (product names, UI labels, IT terms like API, deploy,
  prompt, token) instead of translating them. Use whenever writing or translating into
  Icelandic, when the user writes in Icelandic, or asks to check, fix, laga, yfirfara or
  proofread Icelandic text, or asks about Icelandic grammar or spelling. Keywords: Icelandic,
  íslenska, translate to Icelandic, Icelandic email, correct my Icelandic, proofread Icelandic.
---

# Icelandic

You already write good Icelandic. This skill does not teach grammar. It stops the one habit that
makes the text sound machine-made: translating words no Icelander would translate. It also lists
the few slips worth a last look.

## 1. Keep the words people actually say

Ask of every English word: **would an Icelander say this word in English, in this sentence, to
this reader?** If yes, keep it. Translate only when the Icelandic word is what people say.

Keep exactly as written:

- **Names**: products, companies, tools, features, people, repos. SharePoint, Slack, Teams,
  Jira, AWS, GitHub, Claude Code.
- **Anything the reader must find or type**: UI labels, buttons, menu items, error messages,
  commands, file names, code. Quote labels as they appear: smelltu á „Save“.
- **IT words with no settled Icelandic word**: API, token, prompt, URL, cache, framework, pull
  request, backend, frontend.
- **IT words said in English between colleagues**: deploy, agent, admin, site, bug, branch,
  commit, merge, dashboard, sprint, ticket, login, setup. Keep these in chat and internal
  notes. In a formal or customer-facing text, use the normal Icelandic word if one is in
  written use (kerfisstjóri, stjórnborð, innskráning, notendur); otherwise keep the English.

Translate, because these are what people say: tölva, sími, tölvupóstur (or póstur), vefsíða,
aðgangur, lykilorð, notandi, skjár, uppfærsla, gagnagrunnur, hugbúnaður.

Rules that follow from the test:

- **Never coin a word.** If no Icelandic word is in everyday use, keep the English.
- **Never half-translate.** Write "SharePoint site", not "SharePoint-vefsvæði".
- **An English word that needs an ending** takes it after a hyphen (API-ið, token-inn,
  deploy-ið), or reword so it needs none.
- **Formal is not purist.** A formal email to an IT customer still says API and Jira. Never
  coin or revive a rare word (forritaskil, auðkenni, kvaðning, umboðsmaður) unless the venue
  demands it (academic linguistics, official government text) or the user asks.
- **Place names**: use the Icelandic name when it is the normal one (Bandaríkin, Danmörk,
  Kaupmannahöfn, Þýskaland). Otherwise keep the name as is.
- **When unsure, keep the English.** A kept English word reads fine. An unneeded translation
  reads like a machine.

## 2. Match the reader

- **Chat (Slack, Teams, SMS)**: short and casual. kannski, núna, loanwords all fine.
- **Work email or doc**: neutral and clear. Names and IT words with no Icelandic word stay.
- **Customer email, proposal, formal text**: careful register (ef til vill, þar af leiðandi).
  Names, UI labels and IT words with no Icelandic word stay; colleague slang (admin, dashboard,
  deploy-aði) does not.
- Address everyone with þú; never the polite plural þér (þérun).
- When fixing someone's text, keep their register and the English words they chose.

## 3. Slips worth a last look

You usually get these right. Check anyway:

- Oblique subjects: mig langar, mig vantar, mér finnst, mér líður; but ég hlakka til.
- Names decline: með Gunnari, ég sá Sigríði, til Helga.
- ég vil, hann vill.
- "whether" is hvort, not ef: Ég veit ekki hvort hún kemur.
- geta takes the supine (sagnbót): Ég get gert þetta.
- Agreement with plural-only nouns: öll gögn eru komin, not allt gögn.
- Compounds are one word: tölvupóstur, notendaviðmót.
- Lowercase days, months, languages, nationalities: mánudagur, janúar, íslenska, íslenskur.
- Icelandic quotation marks „…“, never "…".
- Numbers: 3,5 and 1.000.000; dates 3. apríl 2026; time kl. 14.30.
- No z in Icelandic words (names keep theirs: Mozart, Zürich; and pizza). fólk is singular: fólk er.

## Modes

- **Write or translate**: give the text. No commentary unless asked.
- **Fix**: smallest edits that make it correct. Keep their tone, order and English words,
  spelled the way they spelled them (mergea stays mergea, not merge-a). Print
  the whole fixed text in a plain code block so it can be copied, never a fragment. Below it, at
  most one line of changes (`gamalt → nýtt, ...`).
- **Proofread or explain**: list each real error, the fix and a one-line reason. A kept English
  IT word is not an error.

## Before you send

Look at every Icelandic word you made from an English one. Would this reader have said the
English? Then put the English back.

## References

Open only when needed:

- `references/grammar-tables.md`: declensions, verb classes, preposition and verb cases. Open
  when unsure of a form.
- `references/vocabulary-reference.md`: idioms, formal register markers, place names, academic
  section names. Open for formal or academic text, or an idiom. Its word tables show what
  people say; they are not a list of words to swap in.
