---
name: legal-and-fonts
description: The legal/ethical guardrails for demo cloning (what's protected, prospect-own-brand rule, never-deploy-public, disclaimer, auth-wall abort, robots/anti-bot) plus font licensing and the commercial→OFL substitution map. Load before capturing or shipping any clone to confirm the work is in-bounds.
---

# Legal, Ethics & Fonts — staying in bounds

Cloning a site's *look* for a **non-public sales demo** is defensible — the idea/expression
dichotomy makes layout, color, spacing, and type unprotectable *ideas*. The risk is never the
layout; it's the embedded **stock images**, **commercial fonts**, **verbatim copy/logos**,
**public deployment**, and **impersonating a third party**. Each has a concrete rule below. These
are operational guidelines, not legal advice.

## The non-negotiable rules (state these to the user when relevant)

1. **Prospect's own brand only.** Cloning Site A to show Prospect B is fine when A *is* B's own current site (analogous to nominative fair use — showing them *their* site). Cloning a **competitor's** site to show a prospect is a different, higher-risk category (false designation of origin, trademark) — don't, without explicit legal sign-off. A one-line written "please clone our site for the demo" from the prospect is worth getting.
2. **No original image survives.** Replace **every** `<img>` and CSS `background-image`. Stock licenses (Getty/Shutterstock/iStock) are non-transferable; the `hiQ` ruling protects *data* scraping, not copyright on creative works. This is a **mandatory pipeline step**, not optional.
3. **No verbatim copy.** Headlines/body text are the most clearly copyrightable element. Replace with prospect-tailored or placeholder text. (`#0052CC` is not protectable; "Move fast with confidence" is.)
4. **Substitute commercial fonts** (next section). Never re-serve captured commercial woff2.
5. **Never deploy to a public URL** — not even a random one. It can be indexed, found by brand monitoring, and collapses every trade-dress/trademark defense by creating real likelihood-of-confusion. Local file / localhost / password-protected internal preview / screen-share only.
6. **Inject the demo disclaimer banner** (rebuild-and-reskin.md). It makes "likelihood of confusion" and misrepresentation claims much harder to establish.
7. **Abort on auth/paywall.** Never capture logged-in or paywalled content (CFAA + ToS risk is materially higher). The script hard-stops on a password field or `/login` redirect.
8. **Respect robots.txt; never evade anti-bot.** If a path is `Disallow`ed or the site throws a Cloudflare/Imperva challenge, that's a **stop signal** — fall back to a manual reference screenshot + rebuild from scratch. Using stealth plugins or bypass services to defeat an active block crosses into "exceeding authorized access." Be polite: one capture per demo, genuine UA, a couple seconds between asset fetches, honor `Crawl-delay`. Stop immediately on any cease request.

## Font licensing — the highest day-to-day risk

| Source | Detect | Demo handling |
|--------|--------|---------------|
| **Google Fonts (OFL/Apache)** | `fonts.googleapis.com` / `gstatic.com` | ✅ Embed freely — self-host the woff2, inline base64, or link. |
| **Fontshare / Fontsource (OFL)** | `api.fontshare.com` / `@fontsource/*` | ✅ Embed freely (Satoshi, Clash Display, Cabinet Grotesk…). |
| **Adobe Fonts / TypeKit** | `use.typekit.net` / `p.typekit.net` | ⛔ woff2 = short-lived signed URLs (403 on replay) **and** non-redistributable. The prospect **cannot** sublicense their Creative Cloud font to you. **Substitute.** |
| **Monotype / Fonts.com / MyFonts** | `fast.fonts.net` | ⛔ EULA is domain + pageview-tier locked; serving to a prospect's browser is out of compliance. **Substitute.** |

Identify the **actually-rendered** font with CDP `CSS.getPlatformFontsForNode` (capture-pipeline.md)
— `fontFamily` lies. Then map via `data/font-substitutes.json` (the script auto-suggests this in
`font-report.json`). Match **x-height and weight** over geometry. The visual delta of a good OFL
substitute is typically 1–3px at body sizes — invisible to a non-type-specialist audience. Only
escalate to the exact font if the audience is a design team **and** an OFL version exists to source
legitimately.

## What's protected vs not (quick reference)

**Not protected (safe to reproduce as tokens/structure):** page layout & grid, color palette,
spacing/type scale, standard nav patterns, functional components (dropdowns, carousels, tabs),
machine-generated class names. *Source: U.S. Copyright Office Circular 33 — "the general layout or
format of a web page is uncopyrightable."*

**Protected (must replace):** custom illustrations & photography, icon sets with artistic content,
original copy, logos/wordmarks (trademark), and — for iconic sites with established secondary
meaning — the total trade dress *if the clone is ever publicly visible*.

## Quick legal gate (before you start)

```
Is it the PROSPECT's own site?            no → stop, get sign-off (or pick a generic reference)
Does it require login / is it paywalled?  yes → ABORT
Does robots.txt disallow the path?        yes → manual screenshot + rebuild, don't scrape
Does the site actively block bots?        yes → stop signal, do not evade
                                          else → proceed; replace all images + commercial fonts;
                                                 add disclaimer; serve locally only.
```
