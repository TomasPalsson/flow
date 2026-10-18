# Worst-Case Data Stress Test

UI is nearly always built against kind demo data: names that fit on one line, counts that never need a separator, every optional field filled in. This test undoes that choice one field at a time, puts the result behind a toggle, and reports what broke.

Two failure modes, the first worse:

1. **Nonsense data.** `"aaaaaaaaaaaa..."` and 5,000-character names prove nothing, and the designer rightly stops listening. Every value must be something a real user could produce, or the longest value the backend actually accepts.
2. **Stopping at long text.** The breaks that ship are the short name that leaves an orphaned dash, the missing avatar, "1 members", the empty list, the translated badge.

## Rules

- **Plausible or schema-backed.** Take limits from the validation schema (Zod, Yup, Valibot), migrations, API types or `maxLength`. No limit found is itself a finding: say "unbounded" and test something long but believable. A 50-character input saving to a 255-character column means something longer will arrive through an import or the API.
- **Change the data, not the component.** The worst case enters through the same boundary as the demo data (fixture, mock, props, API stub). Hand-editing markup or CSS tests your edit, not the component.
- **One dataset, many failures.** Spread the failures across the first rows, as real data does: row 1 the long name, row 2 the long email, row 3 the one-letter name.
- **The toggle is dev-only.** It never ships.
- **Report before fixing.** Some breaks are design decisions (truncate or wrap?). List them all with a fix each, then fix what the user picks.

## Steps

1. **Map the surface.** List every value the component renders with source, type, limit and whether it is optional. Include the ones people forget: counts in headers, relative timestamps, badge and status text, labels from data, tooltips, avatar images, and the list length itself. Done when every rendered value has a source and a limit or "unbounded".
2. **Build the worst case** from the catalog below, as a fixture next to the demo data in the same shape and file conventions. Also cover the cases one dataset cannot: **Empty** (zero items, no results), **One** (a single item, every count at exactly 1), **Huge** (1,000+ rows if the list is unpaginated, which is a performance break too).
3. **Wire the toggle.** A segmented control, **Demo / Worst case / Empty / One / 1,000 rows**, fixed bottom-centre, plain grey chrome, switching instantly with no animation. In a project with a dev server, read `?data=worst` where the fixture is chosen so a reload keeps it; with no project, a single self-contained HTML file with every dataset inline.
4. **Break it.** View each state at the component's real container width (a sidebar list is not a full-page list), at 320px and at the widest layout; at 200% browser zoom; in dark mode and RTL (`dir="rtl"` on a wrapper) if the product supports them. Screenshot both states when a browser tool is available; otherwise reason from the CSS and say which findings were seen and which inferred.
5. **Report, then fix on request.** After fixing, flip through every state again, Demo included, since a worst-case fix must not regress the demo. Keep the worst-case fixture as the regression test for the next change.

## Failure signatures

| What you see | Cause | Fix |
|---|---|---|
| Avatar or icon squished into an oval | Flex child shrinking | `flex-shrink: 0` on avatars, icons and fixed-size boxes |
| Text overflows its box instead of wrapping or truncating | Flex/grid child has `min-width: auto` | `min-width: 0` on the text column (`minmax(0, 1fr)` in grid) |
| Email or URL runs past the edge | No break opportunity in the string | `overflow-wrap: anywhere` on that element |
| Trailing action (menu, button) pushed off-screen | Middle content took all the space | `min-width: 0` on the middle, `flex-shrink: 0` on the action |
| Badge wraps onto two lines | Badge allowed to shrink | `white-space: nowrap; flex-shrink: 0`, and decide what yields instead |
| Avatar centred against a three-line name looks adrift | `align-items: center` on rows of varying height | `align-items: flex-start` once text can wrap |
| Last row cut mid-glyph at a hard edge | Fixed-height container with no affordance | Visible scrollbar or a fade mask |
| Heading breaks mid-word | `word-break: break-all` | `overflow-wrap: anywhere`, which breaks only when it must |
| Wrong initials (`J` for "Jo", `CI` for "... Montgomery III", `�` for an emoji-first name) | `.split(' ')[0][0]`-style code | Initials from grapheme clusters (`Intl.Segmenter`), first + last word, fallback icon |
| Orphaned `—` or empty line where an optional field was | Placeholder rendered for a missing field | Omit the line, or reserve its height on purpose |
| "1 members", "0 member" | Hard-coded plural | `Intl.PluralRules` or separate strings per count |
| Numbers jitter as they update; columns misalign | Proportional figures | `font-variant-numeric: tabular-nums` |
| `1284`, `0.30000000000000004`, `NaN`, `undefined` | Raw number rendered | `Intl.NumberFormat` in the user's locale; guard null |
| Translated button label overflows | Fixed-width button | Width from content with `min-width`, never a fixed `width` |
| Diacritics or tall scripts clipped | Tight `line-height` with `overflow: hidden` | Looser `line-height`, or no clipping on text boxes |
| Broken-image icon in the avatar | No `onError` fallback | Fall back to initials; `object-fit: cover` |
| Truncated text with no way to read it | Ellipsis and nothing else | `title` or a tooltip, and the full value somewhere |
| 1,000 rows stutter on scroll | Every row rendered | Virtualize or paginate, and say which |
| Raw `<b>`, `&amp;` or `**text**` on screen | Wrong escaping layer | Escape once at render; never `dangerouslySetInnerHTML` user data |
| Hover-only actions unreachable on a phone | Action revealed only on `:hover` | Keep it visible on touch |

## Truncate, wrap or clamp

Decide per field, not globally:

- **Wrap** what the user needs in full to identify something: names, titles in a detail view. Two lines is fine; four means the column is too narrow.
- **Truncate at the end** for secondary metadata where the start carries the meaning: role, description, message preview. Always pair it with a way to see the full value.
- **Truncate in the middle** when items differ at the end: file names, emails sharing a long domain, paths, hashes. End-truncation makes them identical.
- **Clamp** (`line-clamp: 2`) multi-line previews in cards, so card heights stay predictable.
- **Never truncate** numbers, amounts, dates, or anything the user compares.

## Catalog

Use `example.com`, `example.org` or `.test` domains so a fixture never points at a real inbox.

**Names**

| Value | Breaks |
|---|---|
| `Aleksandra Wiśniewska-Kowalczyk` | Long, hyphenated, diacritics; wraps, and the hyphen is a break point |
| `Christopher Alexander Montgomery III` | Suffix; naive first + last initials give `CI` |
| `Jo` / `J` | Name column mostly empty; one-letter initials; tiny click target when the name is the link |
| `Ólafur Darri Ólafsson` | Accented capital; sort and uppercase logic, initials `ÓÓ` |
| `Đặng Thị Ngọc Hân` | Stacked diacritics clipped by tight `line-height` |
| `王秀英` | No spaces; word-based initials find one word |
| `نور الهدى عبد الرحمن` | RTL; punctuation and icons land on the wrong side without `dir="auto"` |
| `María José de la Cruz y Fernández` | Lowercase particles; initials and last-name sorting |
| `dana` | All lowercase; initials should still be uppercase |
| `🦊 Fox` / `👩🏽‍💻 Priya` | Emoji first: `.charAt(0)` returns half a surrogate pair; ZWJ sequences break when sliced |
| `  Sam   Lee ` | Leading, trailing and repeated spaces |
| *(missing)* | Only an email exists; the UI needs a fallback |

**Emails, URLs, identifiers** (no spaces, so the browser has nowhere to wrap)

| Value | Breaks |
|---|---|
| `bartholomew.fitzgerald@northwind-industries-holdings.example.com` | Pushes every sibling off the row |
| `a@b.co` | Layout that assumed a long email looks empty |
| `first.last+billing-notifications@example.com` | Validation that rejects `+`; truncation hides the meaningful part |
| A 100-character URL with query string | Overflow; end-truncation hides the part that differs |
| `Q3 Board Deck — FINAL (revised) v12 [approved by legal].pdf` | End-truncation hides version and extension |

**Labels and copy from data**

| Value | Breaks |
|---|---|
| `Senior Product Design Engineer, Platform Infrastructure` | Wraps to three lines in a secondary slot |
| `Invitation expired 12 days ago` | Long status badge squeezes the name column |
| `Benachrichtigungseinstellungen` / `Persónuverndarstillingar` | Long compound word, no spaces; label overflow |
| `Paramètres de confidentialité et de sécurité` | Translated copy runs about 30% longer |
| Twelve tags on one item | Tag rows wrap into a wall; needs a `+8` overflow |
| `Untitled` / empty / `   ` | Collapsed heading, zero-height row |
| `<script>alert(1)</script>` / `&amp;` / `**bold**` | Must render as literal text |
| A newline in a single-line field | Doubles row height or is silently dropped |
| A 2,000-character pasted description | Clamp, "show more", textarea growth |

**Numbers and money**

| Value | Breaks |
|---|---|
| `0` | Zero states, empty progress bar, division by zero in percentages |
| `1` | Plurals |
| `1284` / `1000000` | Thousands separator; badge width (consider `1M` where precision does not matter) |
| `12345678.9` as currency | Overflows totals columns |
| `-42.5` | Sign, red colour logic, accounting parentheses |
| `142%` / `-3%` | Progress bars past their bounds |
| `null` / `undefined` / `NaN` | Rendered literally |
| `1.284` in `de-DE` / `is-IS` vs `1,284` in `en-US` | Hard-coded separators are wrong for half the world |
| `99` → `100` live | Width jump without `tabular-nums` |

**Collections**: 0 items (does an empty state exist?); 1 item (grids that look broken with one card); exactly page size and page size + 1 (an empty page 2); 1,000+ unpaginated; one item ten times larger than the rest; items with identical names.

**Time**: now ("0 seconds ago"); 12 days, 11 months, 3 years ago (switch to an absolute date after about a week); a future date; `1970-01-01`; a timestamp near midnight that lands on a different day in UTC; `1,284 hours` that never rolls up to days. Use `Intl.RelativeTimeFormat` and `Intl.DateTimeFormat`.

**Images**: an avatar URL that 404s; no avatar; a 4000×200 or 200×4000 image (distortion without `object-fit: cover`); a dark transparent logo on dark mode; a slow image (layout shift without dimensions or `aspect-ratio`).

**States**: loading (skeletons that do not match the final layout); an API error (a raw `TypeError` shown to the user); partial data in one list; every status value at once; no permission (does the row still lay out the same?); the current user in the list.

## Report

One row per break, worst first. **Broken**: content unreadable, action unreachable, wrong data shown. **Ugly**: readable but visibly wrong. **Fragile**: fine now, one realistic step from breaking (no limit, no fallback).

| # | Severity | Field | Worst-case value | What happens | Fix (`file:line`) |
|---|---|---|---|---|---|
| 1 | Broken | `email` | `bartholomew.fitzgerald@northwind-industries-holdings.example.com` | Pushes the menu off the row at 400px | `min-width: 0` on the text column, `overflow-wrap: anywhere` on the email, `flex-shrink: 0` on the menu |

Then **decisions for the user** (truncate or wrap a field, what an empty role shows, paginate or virtualize), one line each with a recommendation, and **what held up**, so the user knows the test was real and what not to touch. Close with where the toggle is and its states.

Credit: adapted from emilkowalski/skills skills/break-ui/SKILL.md and skills/break-ui/CATALOG.md @ 2d22863 (MIT).
