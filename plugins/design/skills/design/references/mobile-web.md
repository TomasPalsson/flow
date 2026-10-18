---
name: mobile-web
description: The platform-layer fixes that make a web page feel native on a phone (sticky hover, tap flash, 100vh, input zoom, tap delay, overscroll, notch, long-press selection, carousel axes, theme-color). Load in Phase 5 for any page people will open on a phone. For React Native and Expo apps use design:mobile-design instead.
---

# Web On A Phone

Most "it feels janky on my phone" reports are not animation problems. They are a tap delay, a grey flash on tap, or a hover state that will not let go, and almost every fix is one CSS declaration or a meta tag. None of these bugs reproduce in Chrome's device emulation, so a desktop check ships all of them.

Rules that hold throughout:

- **Gate by capability, not device.** Use `(hover: hover)`, `(pointer: fine)`, `env()` and `dvh`; never user-agent sniffing or screen width to guess at touch. iPads with trackpads and touchscreen laptops exist, so write for touch and mouse at once.
- **Never disable zoom.** `user-scalable=no` and `maximum-scale=1` are accessibility failures. Input zoom is fixed by font size, below.
- **Apply each fix where its reason applies.** `user-select: none` on a button is right; on body text it is a defect.

## Symptom table

| Problem | Fix |
|---|---|
| Hover state stuck after a tap | Put every `:hover` rule inside `@media (hover: hover) and (pointer: fine)` |
| Grey or blue flash on tap | `html { -webkit-tap-highlight-color: transparent; }`, then give every tappable its own `:active` state |
| Layout has the wrong height, bottom button under the URL bar | `100dvh` for an app shell or bottom-pinned UI; `min-height: 100svh` for a hero |
| Page zooms into a focused input | Inputs, textareas and selects at `font-size: 16px` minimum |
| Tap feels laggy | `touch-action: manipulation` on controls; feedback on `:active` or `pointerdown`, not `click` |
| Pull-to-refresh or page bounce hijacks an inner scroller | `overscroll-behavior: none` on `html, body` (app-like pages); `contain` on inner scrollers |
| Content stops at the notch, or `env()` is always 0 | `viewport-fit=cover` in the viewport meta, then pad with `env(safe-area-inset-*)` |
| Long-press selects a button's label | `user-select: none` and `-webkit-touch-callout: none` on controls only |
| Swiping a carousel scrolls the page | `touch-action: pan-y` on the horizontal gesture surface, or native `scroll-snap` |
| Status bar colour clashes in one theme | One `theme-color` meta per `prefers-color-scheme` |

## Why each one

- **Sticky hover.** Touch has no hover, so the browser fakes one on the first tap and leaves it until the user taps elsewhere: a button that scales on hover stays scaled. `(pointer: fine)` also rules out styluses and Android devices that claim hover. Tailwind v4's `hover:` variant already compiles to `@media (hover: hover)`; in v3 set `future.hoverOnlyWhenSupported`.
- **Tap flash.** The translucent highlight is the loudest "this is a website" signal, and it fights the press feedback you designed. Removing it removes the only feedback the browser gave, so `:active` is required afterwards.
- **`100vh`.** On mobile `vh` is the largest viewport, with the browser chrome collapsed; on load the URL bar is visible, so a `100vh` element overflows and a bottom-pinned button hides under it. `dvh` tracks the visible area, which suits an app shell but shifts layout on marketing pages mid-scroll; `svh` is stable and never overflows, which suits a hero.
- **Input zoom.** iOS Safari zooms when focus lands in an input under 16px and does not zoom back. If the design wants smaller inputs on desktop, raise them only under `@media (pointer: coarse)`. While in the inputs, set the keyboard: `inputmode="numeric"` or `"decimal"`, `type="email"`/`"tel"`, `autocapitalize="none"` and `autocorrect="off"` on usernames and codes, and `enterkeyhint="send"`/`"search"`/`"done"`.
- **Tap delay.** Browsers can still wait after a tap to see whether a double-tap zoom is coming. And feedback that changes on `click` responds when the finger lifts, which reads as lag even at 0ms; native buttons respond the instant the finger lands. Press feedback: 100-160ms, ease-out, `scale(0.97)`.
- **Overscroll.** Use `none` on the root and `contain` on sheets, chat lists and sidebars, which keeps their own bounce but stops the page behind them moving. Never `touchmove` + `preventDefault()`: it blocks scrolling and makes the listener non-passive. Leave the root alone on a plain scrolling document where pull-to-refresh is welcome.
- **Safe areas.** Without `viewport-fit=cover` every `env(safe-area-inset-*)` is `0px`. Fixed headers, bottom bars, toasts and sheets need the padding: `padding-bottom: calc(1rem + env(safe-area-inset-bottom, 0px))`.
- **Touch axes.** `touch-action` names what the browser may still do: `pan-y` on a horizontal carousel keeps vertical page scroll; `none` only on an element that truly owns every axis (a drag-to-dismiss sheet), or the user cannot scroll past it.
- **theme-color.** Match the colour at the very top of the page (the header background), not the brand colour. In Next.js set it through the `viewport` export (`themeColor: [{ media, color }]`); if the theme switches by class, update the tag on toggle.

## Baseline

For any page people open on a phone, ship this before the first component:

```html
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover, interactive-widget=resizes-content" />
<meta name="theme-color" media="(prefers-color-scheme: light)" content="#ffffff" />
<meta name="theme-color" media="(prefers-color-scheme: dark)" content="#0a0a0a" />
```

```css
html {
  -webkit-tap-highlight-color: transparent;
  -webkit-text-size-adjust: 100%; /* no font inflation in landscape */
}
input, textarea, select { font-size: 16px; }
button, a, [role="button"] { touch-action: manipulation; }
button, [role="button"] { user-select: none; -webkit-user-select: none; }
@media (hover: hover) and (pointer: fine) {
  /* every :hover rule lives here */
}
```

Replace the two `theme-color` values with the page's own header colours. `interactive-widget=resizes-content` makes the Android keyboard shrink the layout viewport, so `100dvh` and bottom-pinned inputs react to it the way they do on iOS.

## Verify on hardware

Bind the dev server to `0.0.0.0`, open it on the phone by the machine's LAN address, and inspect with Safari's Web Inspector (iOS) or `chrome://inspect` (Android). Use a phone a few years old, test once with the keyboard open and once in landscape, and say which fixes were verified on a device and which only from code.

Credit: adapted from emilkowalski/skills skills/mobile-native/SKILL.md @ 2d22863 (MIT).
