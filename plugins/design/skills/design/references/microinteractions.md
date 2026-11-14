---
name: microinteractions
description: The feel layer. Motion tokens, the interaction floor (every control type with its states and a working CSS/JS recipe), browser-surface finishing, the one signature interaction, page-load and scroll rules, the motion tells that read as AI-made, and how to verify feel in a real browser. Load in Phase 4 for every build that has interactive elements; Phase 5b verifies it.
---

# Microinteractions — the feel layer

A page that looks designed in a screenshot can still feel assembled the moment someone touches it: buttons that do nothing on press, a price that snaps from monthly to yearly, a cart count that changes without anyone noticing, a focus ring that is the browser's blue. People cannot name these gaps, but they feel them as "cheap" or "template". Polish is the sum of small, correct answers to touch.

Three rules sit under everything in this file:

1. **Every input answers within 100ms.** Hover, press, focus, type, toggle: something visible changes, in place, at once. Silence reads as broken.
2. **Motion explains.** It says where a thing came from, where it went, or what changed. Motion that explains nothing is decoration, and decoration is where AI-made pages give themselves away.
3. **Frequency sets intensity.** The more often an interaction happens, the quieter it must be. Delight goes on rare moments, never on hover.

## 1. Tokens

Put these on `:root` (extend existing tokens in extend mode; never add a parallel set). Every transition on the page uses them; one duration and one curve for everything is itself a tell.

```css
:root {
  --ease-out: cubic-bezier(.22, 1, .36, 1);      /* enters, hover, press release */
  --ease-in-out: cubic-bezier(.65, 0, .35, 1);   /* something already on screen moving A to B */
  --ease-drawer: cubic-bezier(.32, .72, 0, 1);   /* sheets, drawers, large panels */
  --dur-press: 90ms;    /* :active */
  --dur-hover: 150ms;   /* colour, underline, border */
  --dur-small: 200ms;   /* popover, tooltip, toast, inline message */
  --dur-medium: 280ms;  /* accordion, step change, modal */
  --dur-large: 380ms;   /* drawer, full-screen menu, the one signature moment */
}
```

Exit runs at about 70% of enter. `ease-in` never starts a UI motion. No bounce or elastic overshoot outside a physical drag release.

## 2. The frequency ladder

| How often | Examples | Budget |
|---|---|---|
| Constantly | hover, focus, typing, scrolling | 100-150ms; colour, border, underline, opacity; movement ≤ 2px |
| Per task | press, toggle, open a menu, add to cart, validate a field | 150-280ms; transform allowed; one small accent (a badge bump, a check drawing in) |
| Once per visit | confirmation, first paint of the hero, the signature moment | up to 400-600ms; the one place with personality |

## 3. The interaction floor

Every control type on the page gets every row that applies. Write it as an inventory in `.vary/section-plan.md` (element → states → motion) before building, then build from it. Hover rules sit inside `@media (hover: hover) and (pointer: fine)` so phones do not get sticky hover; phones get the `:active` state instead.

### Buttons

```css
.btn {
  transition: background-color var(--dur-hover) var(--ease-out), color var(--dur-hover) var(--ease-out),
              border-color var(--dur-hover) var(--ease-out), box-shadow var(--dur-hover) var(--ease-out),
              transform var(--dur-press) var(--ease-out), outline-offset var(--dur-hover) var(--ease-out);
  -webkit-tap-highlight-color: transparent; touch-action: manipulation; user-select: none;
}
@media (hover: hover) and (pointer: fine) { .btn:hover { background: var(--accent-strong); } }
.btn:active { transform: scale(.97); }
.btn:focus-visible { outline: 2px solid var(--focus); outline-offset: 3px; }
.btn:disabled, .btn[aria-disabled="true"] { opacity: .45; cursor: not-allowed; transform: none; }
/* loading: keep the width, swap the label for a spinner, announce it */
.btn[aria-busy="true"] { color: transparent; pointer-events: none; position: relative; }
.btn[aria-busy="true"]::after { content: ""; position: absolute; inset: 0; margin: auto; width: 1em; height: 1em;
  border: 2px solid var(--on-accent); border-right-color: transparent; border-radius: 50%; animation: spin .6s linear infinite; }
@keyframes spin { to { transform: rotate(360deg); } }
```

Press scale is .96-.98: smaller is mushy, larger is cartoon. Declare `:active` after `:hover` (same specificity, later wins) or the hover transform silently cancels the press. An action button ignores further clicks while it is busy or showing its success state, and its confirmation is built from what actually happened (the quantity really added), not from what was requested. A success state replaces the label in place ("Added", "Copied", "Booked") for ~1.5s, then returns. Show the spinner only if the action takes over ~150ms, so fast actions do not flicker.

### Links

Prose links keep an underline (it is the affordance); style it rather than delete it.

```css
a { text-decoration-line: underline; text-decoration-thickness: 1px; text-underline-offset: .22em;
    text-decoration-color: color-mix(in oklch, currentColor 35%, transparent);
    transition: text-decoration-color var(--dur-hover) var(--ease-out), text-underline-offset var(--dur-hover) var(--ease-out); }
@media (hover: hover) { a:hover { text-decoration-color: currentColor; text-underline-offset: .3em; } }
```

Nav links: an indicator that draws in from the left on hover and leaves to the right.

```css
.nav a { position: relative; text-decoration: none; }
.nav a::after { content: ""; position: absolute; left: 0; right: 0; bottom: -4px; height: 2px; background: currentColor;
  transform: scaleX(0); transform-origin: right; transition: transform var(--dur-small) var(--ease-out); }
@media (hover: hover) { .nav a:hover::after { transform: scaleX(1); transform-origin: left; } }
.nav a[aria-current="page"]::after { transform: scaleX(1); }
```

### Clickable cards and rows

The whole card is one target (stretched link: `.card a::after { content: ""; position: absolute; inset: 0; }` on a `position: relative` card). Hover changes the surface or border and may lift 1-2px; a product or photo inside may scale to 1.03 in an `overflow: hidden` frame. **A card that is not clickable does not react to hover.** Hover lift on static content is a tell.

### Inputs

```css
.field input { border: 1px solid var(--line); transition: border-color var(--dur-hover) var(--ease-out), box-shadow var(--dur-hover) var(--ease-out); }
.field input:hover { border-color: var(--line-strong); }
.field input:focus-visible { outline: none; border-color: var(--accent);
  box-shadow: 0 0 0 3px color-mix(in oklch, var(--accent) 28%, transparent); }   /* replacement ring, ≥3:1 */
.field:focus-within label { color: var(--ink); }
.field .msg { display: grid; grid-template-rows: 0fr; opacity: 0; transition: grid-template-rows var(--dur-small) var(--ease-out), opacity var(--dur-small) var(--ease-out); }
.field .msg > span { overflow: hidden; }
.field[data-state="error"] .msg, .field[data-state="valid"] .msg { grid-template-rows: 1fr; opacity: 1; }
```

Validate on blur, then live while the user corrects (errors clear as soon as the value is fixed). A valid field may show a small check that draws in; the error carries text and an icon, linked by `aria-describedby`, with `aria-invalid="true"`. Formatting masks (kennitala, card, phone) insert separators as the user types without moving the caret. Never shake a field: it reads as scolding and moves the text the user is reading.

### Checkbox, radio, switch

Use real inputs, visually restyled; `accent-color: var(--accent)` is the minimum. Custom switch: the thumb moves with `transform: translateX()` on `--ease-out` over `--dur-small`, the track colour crossfades. Custom checkbox: the tick is an SVG path drawn with `stroke-dasharray`/`stroke-dashoffset` over ~180ms. Radio cards (plan, grind, treatment) show selection by border and fill, with the check appearing in the corner.

### Segmented controls and tabs

A single indicator slides between options; it never teleports.

```css
.seg { display: grid; grid-auto-flow: column; grid-auto-columns: 1fr; position: relative; }
.seg::before { content: ""; position: absolute; inset: 3px auto 3px 3px; width: calc((100% - 6px) / var(--n));
  border-radius: inherit; background: var(--surface-raised); transform: translateX(calc(100% * var(--i, 0)));
  transition: transform var(--dur-medium) var(--ease-in-out); }
```

Set `--n` to the count and `--i` to the selected index from JS. Unequal widths: measure the active button and set `--x`/`--w`, animate `transform` and `scale` rather than `left`/`width`. The content behind the tabs crossfades (opacity 120ms out, 200ms in).

### Disclosure and accordion

```css
.acc-panel { display: grid; grid-template-rows: 0fr; transition: grid-template-rows var(--dur-medium) var(--ease-out); }
.acc-panel > div { overflow: hidden; }
.acc[aria-expanded="true"] + .acc-panel { grid-template-rows: 1fr; }
.acc svg { transition: transform var(--dur-medium) var(--ease-out); }
.acc[aria-expanded="true"] svg { transform: rotate(180deg); }
```

This `grid-template-rows` pattern is the sanctioned exception to "never animate layout": it is the only robust way to open to `auto` height. With native `<details>`, `:root { interpolate-size: allow-keywords }` plus `::details-content { block-size: 0; overflow: clip; transition: block-size var(--dur-medium) var(--ease-out), content-visibility var(--dur-medium) allow-discrete; } details[open]::details-content { block-size: auto; }` does the same in Chromium and degrades to an instant open elsewhere.

### Popovers, menus, tooltips, dialogs, drawers

They grow from their trigger (`transform-origin` at the trigger edge), start at `scale(.96)` and a few px offset, never `scale(0)`. Enter `--dur-small`, exit faster. With the platform `popover` or `<dialog>`:

```css
[popover], dialog { opacity: 0; transform: translateY(-4px) scale(.98);
  transition: opacity var(--dur-small) var(--ease-out), transform var(--dur-small) var(--ease-out),
              overlay var(--dur-small) allow-discrete, display var(--dur-small) allow-discrete; }
[popover]:popover-open, dialog[open] { opacity: 1; transform: none; }
@starting-style { [popover]:popover-open, dialog[open] { opacity: 0; transform: translateY(-4px) scale(.98); } }
dialog::backdrop { background: oklch(0.2 0.02 var(--hue) / .4); transition: opacity var(--dur-small); }
```

Drawers and sheets slide from their edge with `--ease-drawer` over `--dur-large`; modals stay centred. Focus moves in on open and back to the trigger on close; Escape closes. Tooltips wait ~400ms before the first show, then show instantly while the pointer moves between neighbours.

### Feedback for actions

- **Toast / inline confirmation**: an `aria-live="polite"` region; enters with `translateY(8px)` → 0 and opacity over `--dur-small`, leaves faster, auto-dismisses after ~4s, pauses on hover, and has a close button. Prefer inline confirmation next to the thing changed when there is room.
- **Count badges** (cart, notifications): when the number changes, bump it: `el.animate([{transform:'scale(1)'},{transform:'scale(1.2)'},{transform:'scale(1)'}], {duration: 260, easing: 'cubic-bezier(.22,1,.36,1)'})`.
- **Copy to clipboard**: the icon crossfades to a check (opacity plus `scale(.8)` → 1), the label reads "Copied" (announced via `aria-live`), and both revert after ~1.6s.
- **Changing values** (monthly/yearly price, quantity, totals): `font-variant-numeric: tabular-nums` so digits do not jitter; the old value leaves upward and the new one enters from below:

```js
const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
function swapText(el, next) {
  if (reduce || el.textContent === next) { el.textContent = next; return; }
  el.animate([{ opacity: 1, transform: 'none' }, { opacity: 0, transform: 'translateY(-.35em)' }], { duration: 110, easing: 'ease-in' })
    .onfinish = () => { el.textContent = next;
      el.animate([{ opacity: 0, transform: 'translateY(.35em)' }, { opacity: 1, transform: 'none' }], { duration: 200, easing: 'cubic-bezier(.22,1,.36,1)' }); };
}
```

- **Multi-step flows**: the next step enters from the direction of travel (forward from the right, back from the left, ~16-24px plus opacity, `--dur-medium`); use `document.startViewTransition` when present, with a plain swap as fallback. Move focus to the new step's heading (`tabindex="-1"`). A progress bar fills with `scaleX`, origin left.
- **Loading content**: skeletons in the final layout's shape (no layout shift when content lands), with a slow opacity pulse (`.55` ↔ `1`, ~1.2s) that stops once loaded. A late conflict ("this slot was just taken") shows in place, with the next nearest option offered.

### Choreography: one change, one motion

The rough edges that survive a first pass are almost always coordination failures, not missing animations. Check each of these by stepping the transition at 0.1x:

- **One object moves as one.** A sliding indicator animates its position and its width together (`transform` plus `scale`, or a measured `--x`/`--w` pair on the same duration and curve); the label colour flips when the indicator arrives (same duration, or a delay of about half), never before it, so no label is ever ink-on-ink.
- **Everything tied to a change changes together.** When a toggle changes the price, the period ("/ month" → "/ year"), the savings line and the button label all swap in the same beat with the same treatment. Half a change animated and half snapped reads as a glitch.
- **Content follows its control.** When tabs change, the panel content crossfades (out ~110ms, in ~200ms); the code, command or note under a tab never snaps while the indicator is still travelling.
- **Out is as designed as in.** Anything that animates open animates closed (faster). Setting `hidden` or `display: none` on close kills the exit; use the `grid-template-rows` pattern, `transition-behavior: allow-discrete`, or set `hidden` on `transitionend`.
- **State is clean on return.** A dialog, drawer or form reopened after success starts fresh (fields cleared, errors gone, focus on the first field); a toggled-back control restores exactly its earlier look.
- **Reveals move, they do not pop.** Options that appear because of a choice (subscription frequency, a referral note, an extra field) open with the `grid-template-rows` pattern, not by flipping `hidden`, so nothing below jumps.
- **Feedback never covers its control.** A toast or note sits where it hides nothing the user is about to touch, stays one line on a phone, and is never wider than its content needs.
- **Acknowledge, then advance.** When choosing an option moves the flow on (pick a treatment → next step), show the selection land first (the radio fills, the row takes its selected state, ~150-250ms), then advance. Ignore pointer input on the incoming panel for ~300ms so the second click of a double-click cannot choose something on the next step.
- **Notices do not shove.** An inline error or notice that appears right after a click must not push the thing the user is aiming at: reserve its space, overlay it, or place it where nothing moves under the pointer.
- **The object travels.** When the concept says one thing becomes another (the summary card becomes the confirmation, the bag goes into the cart), move that element with View Transitions (`view-transition-name` on it, `document.startViewTransition`) or FLIP (measure first and last box, animate the `transform` between them), with a plain swap as fallback. A hard layout cut followed by a delayed flourish is the opposite of the idea.
- **Indicators keep pace.** A stepper, progress bar or tab underline moves on the same beat and curve as the content it labels.
- **Loading never contradicts.** Do not show "Finding free times…" over data already on screen; a skeleton appears only where content is genuinely unknown.
- **Programmatic focus is quiet.** Headings that receive focus after a step change (`tabindex="-1"`) take `outline: none` or a subtle text underline, not a heavy box: they are not controls. Check that no `all: unset` or reset on a control removed its `:focus-visible` ring.
- **No snaps hidden by speed.** A `0s` on one property in a transition list, or a property missing from the list, shows up as a jump at 0.1x. List every property that changes.

### Sticky header

Starts flush with the page; once scrolled past ~8px it gains a surface and a hairline border via a `data-scrolled` attribute and a `--dur-small` transition. An `IntersectionObserver` on a sentinel at the top is cheaper than a scroll listener. No hide-on-scroll for short pages.

## 4. Browser surfaces and small details

These ship with browser defaults that belong to no design. Theming them is the cheapest signal that the page was built, not assembled:

- `::selection { background: …; color: … }` in the palette; `caret-color: var(--accent)`; `accent-color: var(--accent)`; `scrollbar-color` on the root and any scroll container; `color-scheme` set.
- `:focus-visible` ring designed for the palette (≥3:1, offset 2-3px, distinct from hover), never the default blue, never removed.
- `text-wrap: balance` on headings, `text-wrap: pretty` on paragraphs; `hanging-punctuation: first` where supported; `font-variant-numeric: tabular-nums` on prices, times, tables and counters.
- `scroll-margin-top` on anchor targets equal to the sticky header height; `scroll-behavior: smooth` only inside `@media (prefers-reduced-motion: no-preference)`.
- `cursor: pointer` on every clickable element that is not a native link or button; `cursor: not-allowed` on disabled.
- `-webkit-tap-highlight-color: transparent` only where an `:active` state replaces it; `touch-action: manipulation` on controls.
- Images and art reserve their box (`width`/`height` or `aspect-ratio`) and show a tinted placeholder surface, not white, until loaded.

## 5. The signature interaction

One rare action gets a small, authored moment tied to the concept, inside the once-per-visit budget. It belongs to this client: the shape of their trade's own artefact or gesture. Examples of the shape (do not reuse them): adding a coffee to the cart prints the roast date onto a small bag label; copying an install command echoes a line of terminal output beneath it; confirming a booking settles the appointment card into place with the time set large. It runs once per action, under 600ms, never on hover or scroll, and has a reduced-motion version that keeps the state change without the movement.

## 6. Page load and scroll

- At most **one** load moment, on the first screen, CSS only, finished by ~700ms (for example the headline and primary action rising 8px and fading in, staggered ≤60ms). Body content never waits on JS to become visible, and nothing is left at opacity 0 if a script fails.
- **No scroll-reveal of body content.** No fade-up per section, no staggered cards on scroll. Scroll-linked motion is allowed only when it carries information (a reading progress bar, a step indicator, the sticky header state) or is the concept's one moment, implemented with `animation-timeline: view()` inside `@supports`, starting from a visible state.
- No loop runs forever in view. A loop that carries meaning (a live status dot) is slow, small, and stops under reduced motion.

## 7. Motion that reads as AI-made

Each of these is now as recognisable as indigo and Inter. Do not ship them; the replacement is in the right column.

| Tell | Instead |
|---|---|
| Fade-up on every section, staggered card reveals on scroll (the AOS look) | Content is simply there; one load moment on the first screen |
| `transition: all .3s ease` everywhere; one duration for everything | Named properties, tiered tokens (§1) |
| Hover lift + bigger shadow on every card, including ones that do nothing | Hover only on clickable things; surface or border change first |
| `scale(1.05)` hover on every button | Press scale on `:active`; hover changes colour |
| Floating or pulsing blobs, animated gradient backgrounds, spinning gradient borders, glow pulse on the CTA, shimmer sweeping across buttons | A still, considered surface; if the concept needs atmosphere, it is static |
| Typewriter or rotating-word headlines | A headline that makes one concrete claim and stays still |
| Count-up numbers on scroll, marquee strips of logos | Static numbers set in tabular figures; real logos only, static |
| Custom cursor, cursor glow or spotlight, magnetic buttons, 3D tilt cards, parallax layers | The native cursor and honest hover states |
| Bouncy or elastic easing on UI | `--ease-out`; springs only for drag release |
| Smooth-scroll libraries, scroll-jacking, snap on a marketing page | Native scrolling |
| A spinner for something that takes 50ms; loading states that flash | Delay the spinner ~150ms; optimistic updates where safe |

## 8. Reduced motion

Ship it with the animation, not after. Reduced means fewer and gentler, not none: keep opacity and colour changes that explain state, drop translation, scale, parallax and loops.

```css
@media (prefers-reduced-motion: reduce) {
  html { scroll-behavior: auto; }
  .rise, .step-enter, .toast { animation-name: fade-only; transform: none; }  /* keep the opacity fade */
  .decor-loop { animation: none; }                                             /* loops stop */
  .btn[aria-busy="true"]::after { animation-duration: 1.4s; }                  /* a loading indicator stays: it is information */
}
@keyframes fade-only { from { opacity: 0; } }
```

In JS, read `matchMedia('(prefers-reduced-motion: reduce)')` and branch (see `swapText` above).

## 9. Verify the feel in a real browser

Code review cannot tell whether an interaction feels right. Phase 5b of SKILL.md drives the page; the checks it runs are:

1. `node <this skill>/scripts/probe.mjs <page> <outdir>` and read every FAIL (hover, press, focus coverage; `transition: all`; layout-property transitions; infinite loops under reduced motion; content invisible after load; slop copy and type; overflow at 390px).
2. Drive the primary task by hand with Playwright at desktop and at 390px: hover each control, press and hold, release outside, tab through the page, run the task end to end, trigger each error and the success.
3. Watch the motion slowed: `const cdp = await page.context().newCDPSession(page); await cdp.send('Animation.enable'); await cdp.send('Animation.setPlaybackRate', { playbackRate: 0.1 });` then screenshot mid-transition. Look for a jump at the start or end, two things moving on different curves, and an element moving from the wrong origin.
4. Interrupt: hover in and out quickly, toggle twice fast, double-click the main action. Transitions must retarget from where they are, not restart; double actions must not double-submit.
6. Choreography (§3): at 0.1x, every segmented control, toggle and tab moves as one object, everything tied to a change swaps in the same beat, and every opened thing closes with motion.
5. Emulate `reducedMotion: 'reduce'` and repeat step 2: every state change still visible, nothing moving.

Credit: recipes adapted from this plugin's `ui-animation` skill (itself from emilkowalski/skills @ 2d22863, MIT) and the platform docs for `@starting-style`, `popover`, `interpolate-size` and the View Transitions API.
