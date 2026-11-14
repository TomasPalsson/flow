---
name: design-spec
description: Template and rules for the design spec written in Phase 3b, before any page code. Tokens, every piece of chrome (top bar, footer, actions, section heads, cards, fields, feedback) designed from the concept with its template default named and departed from, the section plan and the interaction inventory. The build follows the spec; changes go into the spec first.
---

# Design spec

Generated pages differ in palette and font and then share everything else: the same top bar (wordmark left, links right, a bordered button at the far right, a hairline under it), the same section head (big tight h2 left, lede right), the same centred container, the same footer. The theme changes the skin and the chrome stays the template, because nothing ever decided the chrome. The spec decides it, in writing, before code.

Write `.vary/design-spec.md` (in a repo that will keep it, `DESIGN.md` at the root; a repo that already has one is in extend mode and that file IS the spec). Keep it short: one line per decision, values not prose. Every later phase builds from it and checks against it.

## 1. Concept

- Concept in one sentence; the signature idea and its three placements; the three dossier facts it rests on.
- Mode (persuade, operate, read, experience) and the primary task.

## 2. Voice

- How headlines work for this client (a concrete claim with a number, a place, a time; not a maxim).
- The client's own words to use (trade terms, place names, product names) and the phrases this page will not use.
- Button verbs for each action, matched to their result state (Add → Added, Book → Booked).

## 3. Tokens

The `:root` block, written here first and copied into the build verbatim. The build uses no colour, size, radius, shadow, duration or curve that is not a token.

- **Colour roles (OKLCH):** ground, surface tiers, ink, ink-muted, line, accent, accent-strong, on-accent, focus, selection, success, warn, danger; dark-mode values if the page has a dark mode.
- **Type:** faces from `scripts/font-draw.mjs` with the reason for the pick; one row per role (display, h2, h3, body, small, label, numeric) with size, line-height, tracking and weight.
- **Space:** the scale; **container widths by content type** (at least two: reading measure and wide), and which sections use which.
- **Radius and elevation:** tiers, or "none" with the reason.
- **Motion:** the `--ease-*`/`--dur-*` tokens from `references/microinteractions.md` §1, tuned to the concept within the ladder's ranges (a calm clinic sits at the slow end, a dev tool at the crisp end), and one line on its motion character ("paper: nothing lifts, things are stamped and slid").

## 4. Chrome

For each item, three lines: **Default** (what the template version would be, named concretely), **This build** (what it is instead, and the dossier fact or concept artefact it comes from), **States and motion** (its rows from the interaction inventory). Add **Phone** where it changes.

Usability decides what must stay conventional; the concept decides everything else. Placement conventions (brand top-left linking home, nav findable at the top, menu button on phone, primary action reachable) are kept. What the chrome carries, its material, its geometry and its behaviour are this client's.

| Item | What to decide |
|---|---|
| **Top bar** | What live or useful fact it carries besides links (next roast day, open now until 18:00, last restore test passed 03:12); its material (a ticket stub, a ledger rule, a recorder strip, a card header, a sign); its geometry (one row or two, a tab strip in the trade's form, docked to the hero, a left rail); its scroll state; its phone form. "Wordmark left, three links right, outlined button far right, hairline under" is the template: it is never the answer by default. |
| **Footer** | What a visitor actually looks for at the bottom of this site (hours, address and map, the next date, the install command, support) set in the page's material; not brand-left plus link columns. |
| **Actions** | Primary, secondary and text link: shape, fill, label style, icon use, and press, loading and success states, drawn from the material (a stamp, a tab, a key, a tag), not the default solid rounded rectangle unless that is a deliberate choice with a reason. |
| **Section heads** | At least two different head treatments, assigned to sections by job (a head that is a number, a head that is a date, a head inside the content, a running head). Never one layout repeated on every section; never the h2-left-lede-right pair by default. |
| **Containers** | Which sections run at the reading measure, which run wide, which run full bleed, and where the grid breaks on purpose. Not one centred column for everything. |
| **Cards, rows, list items** | The unit of content in the trade's own form (a bag label, a log line, an appointment slot), with its hover and selected states; whether it is clickable (only clickable units react to hover). |
| **Fields and controls** | Inputs, selects, segmented controls, toggles: their material and states; conventional behaviour, skinned through tokens. |
| **Feedback** | How the page says yes, no and wait: the confirmation, the cart or count, errors, empty states, loading. In the page's voice and material. |
| **Signature interaction** | The one rare action and what happens (microinteractions.md §5). |

## 5. Layout and sections

One row per section, top to bottom: (1) its job for the user, (2) whether the concept's idea helps that job and how, or "not here", (3) the content that lives there (each piece in exactly one section), (4) its skeleton, different from its neighbours, (5) its container width and head treatment from §4.

## 6. Interaction inventory

Every control type and every value that changes → its states (default, hover, focus-visible, active, disabled, loading, error, success, empty, as they apply) → what moves or changes, with which token. Built from `references/microinteractions.md` §3.

## 7. Sameness check

Name the five things a page you would build today for a different client in a different trade would share with this one (top bar geometry, section-head layout, container, button shape, footer, card, the type pairing, the accent's role). For each, say how this spec differs, or why sharing it serves this client's user. Then name the one thing a visitor will remember from this page; if it is not in §1, the spec has drifted.

## Following the spec

- Build from it: tokens first, then chrome, then sections in §5 order.
- When the build needs something the spec does not say, add it to the spec first, then build it.
- Phase 5b checks the build against it: every chrome item matches its "This build" line, every changing value has its inventory row, and no literal value bypasses the tokens (`probe.mjs` reports `token-discipline`).
