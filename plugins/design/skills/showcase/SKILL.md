---
name: showcase
description: "Create a realistic in-context HTML mockup showing how a proposed UI component or feature would look inside the actual project, with 2-4 distinct design variations the user can switch between. Extracts the project's design DNA (colors, typography, spacing, layout) from its codebase, then builds a self-contained HTML page with a convincing page shell that mimics the real app. Each variation explores a different design direction so the user can compare approaches before committing. Use when the user wants to: preview a UI component before building it, see a proposed feature in the app's visual context, mock up a design, compare design options, showcase a component, or get a design decision preview. Trigger phrases: 'show me what this would look like', 'mockup', 'mock up', 'UI preview', 'design preview', 'design options', 'compare designs', 'showcase this', /showcase."
---

# Showcase

Create a realistic HTML mockup of a proposed component or feature, embedded in a page shell that looks like the actual project, with 2-4 distinct design variations the user can toggle between. The mockup is a decision tool: its job is to help someone say "I want Variation 2" or "none of these, try again" — not to be a prototype.

## Core Mindset

**Match the project, never look generically good.** A polished mockup that doesn't match the project's design language is worse than a rough one that does. Stakeholders who use the product daily will immediately notice "this isn't us" and mentally discard the idea — even if the layout was sound. The #1 failure mode is generating shadcn/ui + Inter + purple accent regardless of what the project actually uses.

**The mockup answers exactly one question: "Should we build this?"** Every element must serve that question. Working hover states help (they show the component is alive). Working pagination does not (it answers an implementation question, not a design question). Before adding anything, ask: "Does this help someone decide yes or no?"

**Context is not decoration — it is the perceptual condition for judgment.** A component in isolation cannot be judged. Human visual judgment is relational: spacing, hierarchy, and color conflicts are only visible against surrounding content. The same button looks fine alone but reveals spacing problems inside a real form.

---

## Phase 1: Extract — Reverse-Engineer the Project's Design DNA

**MANDATORY — READ ENTIRE FILE**: Load [`references/extraction.md`](references/extraction.md) (145 lines) completely before proceeding. **Do NOT load** `references/toolkit.md` here — load it at Phase 2 only.

**Skip extraction.md if**: project has <5 files with no identifiable design system. Use the most polished existing component as canonical reference instead.

The project's design identity lives in what was OVERRIDDEN from framework defaults, not the defaults themselves. A `rounded-lg` in Tailwind may be a deliberate choice or a developer's unthinking default. Your job is to distinguish intent from accident.

### The Four Extraction Layers (work in order)

1. **Config/theme files** (highest signal) — `tailwind.config.js` `theme.extend`, CSS `:root {}` variables, `components.json` (shadcn), `theme.ts` (MUI/Chakra). Every value here is an intentional decision.

2. **Global stylesheets** — `globals.css`, `index.css`. Look for: font-family on body, line-height, custom properties, `@font-face` or font imports. These set the baseline feel.

3. **Usage frequency** — Grep for most-repeated Tailwind classes (`rounded-*`, `shadow-*`, `gap-*`, `text-*`, `bg-*`). A value appearing 40 times across 15 components IS the design system. A value appearing 3 times is an experiment.

4. **Component patterns** — Read the project's Button, Card, and Input components. Together they reveal: primary color, hover treatment, border-radius preference, padding rhythm, shadow depth, font weight for interactive elements.

### What to Extract

Extract colors (primary, background, text, muted, border), border-radius, and spacing from the layers above — these are straightforward. The tokens below are the ones agents typically miss or undervalue:

| Token | Why it's non-obvious |
|-------|---------------------|
| **Max-width** | Determines page feel more than any color. A 1140px container reads entirely differently from a full-bleed layout. Find the wrapper component or `max-w-*` on the main content area. |
| **Shadow system** | Signals design philosophy: none = flat (borders do separation), `shadow-sm` = modern elevated flat (Notion, Linear), layered = Material influence, colored = high-design marketing. |
| **Border style** | Borders-only vs shadow-only separation reveals a "flat" vs "layered" worldview. Projects rarely mix both — identify which one dominates. |
| **Font stack** | Display font signals brand positioning: Inter/Geist = dev SaaS, DM Sans/Jakarta = friendly consumer, system stack = performance-first. The pairing (display + body + mono) matters more than any single font. |

### Synthesize into a one-line design brief

After extracting, write one sentence: "This project feels [adjective] — it uses [font] with [radius] corners, [shadow level] shadows, and [spacing] spacing on a [color] background."

If you can't write this sentence, you haven't extracted enough. Go back.

**When extraction returns ambiguous results** (inconsistent styling, no clear dominant token): Extract the most-repeated value for each token using frequency analysis (see extraction.md). If still ambiguous, default to the project's primary Button component as canonical — its colors, radius, and padding define the minimum viable design system. Note "design tokens estimated from dominant component" in the mockup footer.

---

## Phase 2: Build — Create the In-Context Mockup

**MANDATORY — READ ENTIRE FILE**: Load [`references/toolkit.md`](references/toolkit.md) completely before writing any HTML. **Do NOT re-load** `references/extraction.md` — use tokens already extracted.

**Focus your reading**: Start with the Page Shell Skeleton and Core CSS Pattern (always needed). Then read only the sections relevant to your task:
- Before/After Toggle: ONLY if replacing an existing component
- Responsive Preview Controls: ONLY if responsive behavior is a design question
- Shell Variants: Read the variant matching your shell depth decision from Phase 1
- Edge Cases: Skim headings; read only those matching your component type
- **Do NOT** spend attention on sections irrelevant to your task — they waste context for no benefit

### Step 1: Build the Page Shell

The shell answers three questions for the viewer's brain:

| Question | Minimum answer | Include |
|----------|---------------|---------|
| What app is this? | Brand presence | Logo/wordmark, primary font, background color |
| Where am I? | Navigation context | Top nav with 3-5 items (one active), optional sidebar |
| What am I looking at? | Page context | Page title, optional breadcrumb, surrounding content |

**Shell depth decision:**
- Include sidebar if the project uses a sidebar layout (dashboard, admin, IDE, docs)
- Skip sidebar for content-first layouts (blog, marketing, e-commerce)
- Use `max-width` matching the project's actual content container — NOT full viewport width

**Surrounding content at reduced opacity.** Place 2-3 representative elements (cards, rows, text blocks) above and below where the new component will go. Set these to 40-50% opacity with `pointer-events: none`. This creates realistic density without competing with the spotlight.

### Step 2: Generate 2-4 Design Variations

Generate **3 distinct variations by default** (2 minimum, 4 maximum). Each variation is a different design DIRECTION for the same component — not cosmetic tweaks of the same idea.

**Variations must explore different design directions, not cosmetic variants.** "Blue button vs green button" is not two variations — it's one idea in two colors. Real variations differ on the axes that matter for this component:

| Component type | Axes of meaningful variation |
|---------------|-----------------------------|
| Card / tile | Layout (stacked vs horizontal), visual weight (bordered vs elevated vs flat), info density (compact vs expanded) |
| Form / input | Grouping (inline vs stacked vs stepped), labeling (floating vs above vs inside), density (compact vs comfortable) |
| List / table | Structure (table vs cards vs rows), affordance (click-row vs click-button vs inline-edit), density |
| Nav / menu | Orientation (horizontal vs sidebar vs dropdown), hierarchy (flat vs nested vs tabbed), mobile behavior |
| Modal / sheet | Trigger pattern (center modal vs side drawer vs inline expand), size (compact vs full-width), dismissal |
| Dashboard widget | Data emphasis (big-number vs chart vs list), interactivity (static vs hover-detail vs drill-in) |

**Give each variation a descriptive semantic name**, not "Option A/B/C". The name communicates the design intent:
- ✅ "Minimal", "Structured", "Dense"
- ✅ "Horizontal", "Stacked", "Stepped"
- ✅ "Card Grid", "Row List", "Kanban"
- ❌ "Option 1", "Variant A", "v2"

**Every variation must:**
- Use the EXACT tokens extracted in Phase 1 (same font, border-radius, spacing, color)
- Render inside the SAME page shell with the SAME surrounding content and SAME data
- Be genuinely usable — no straw-man variation you're steering the user away from
- Fit within the same container width (the only thing that changes is the component)

**The variation switcher** is a segmented control at the top of the main content area, labeled with each variation's name. Clicking switches which variation renders in the component slot. See toolkit.md "Variation Switcher" for the HTML/CSS/JS pattern.

**Spotlight technique**: With multiple variations, the switcher itself IS the spotlight — users know exactly what they're evaluating. Use opacity halo on surrounding content (40-50% opacity) as the only additional technique. Do NOT use pulse-once outline or "New" badges when variations are present — they compete with the switcher.

### Step 3: Use Realistic Content

**Never use lorem ipsum.** Use plausible, domain-appropriate content:
- Real-length names (include one long name like "Konstantinos Papadopoulos")
- Non-round numbers ($1,247.83 not $1,200)
- Varying content lengths (one short, one medium, one that tests truncation)
- At least one missing/empty data point (missing avatar, empty field)

**The stress test**: Include at least one data point that pushes the layout — a long string, a large number, or an empty state. This is what makes the mockup honest about how the component will actually look.

### Step 4: Add State Switching (only if states are a design question)

Ask: "Is component state a design question or an implementation question?" If the mockup is about layout, happy path + one stress state is enough — skip the switcher. If the mockup is about interaction design or the component's behavior under different conditions matters for the decision, show 3-4 states.

When states ARE a design question, add a segmented control outside the page shell (typically above the component, positioned so reviewers cannot mistake it for actual UI):

```
[ Default ] [ Empty ] [ Loading ] [ Error ]
```

Use `data-state` attributes and CSS selectors to toggle visibility. Each state renders in the same page context.

### Phase 2 Checkpoint — Before Proceeding to Polish

Verify before continuing:
- Every variation uses the same Phase 1 tokens (font, radius, spacing, color)
- Variations differ on meaningful axes (layout, visual weight, density) — NOT just color or copy
- Each variation has a descriptive semantic name, not "Option A/B/C"
- Shell depth matches project layout (sidebar if dashboard, none if content-first)
- All variations share the same page shell and same sample data
- At least one piece of sample data tests the layout stress case

**The "swap test"**: If you could swap the names of any two variations without the mockup becoming incoherent, they're not meaningfully different — regenerate them with sharper divergence.

If any check fails, fix it now. Polishing a structurally wrong mockup wastes time.

---

## Phase 3: Present — Polish and Open

### Aesthetic Guardrails

- Use the project's ACTUAL font (load via Google Fonts CDN if web font, system font stack if system font)
- Use CSS custom properties for all design tokens — define once in `:root`, override in `[data-theme="dark"]` if the project has dark mode
- Write only the CSS the mockup needs — a tight component may need 80 lines, a dashboard shell may need 300. Complexity should match the component's design questions, not a target line count. Do NOT use Tailwind CDN (compiles in-browser, FOUC risk, large payload)
- Add `transition: all 0.15s ease` on hover states — instant transitions look broken
- Add `prefers-reduced-motion` media query that disables animations
- Never base64-encode fonts (10-32x slower CSS parsing on mobile)

### Theme Toggle

Include a dark/light toggle ONLY if the project has dark mode. Match the project's exact dark mode colors. Do NOT invent a dark mode that doesn't exist.

### Annotation Layer

Include annotations if: the component introduces a new interaction pattern, the design decision is non-obvious from visual inspection alone, or the reviewer is unfamiliar with the codebase. Skip for self-evident changes reviewed by the primary author.

When included, add a show/hide toggle for an annotation overlay that:
- Labels the new component with a colored outline and "NEW" badge
- Shows key design decisions (spacing values, color tokens used)
- Annotations go OUTSIDE the page shell boundary, never inside the UI chrome

### Save and Open

Save as `.showcase/mockup-[feature-name].html` at the project root. Create the `.showcase/` directory if needed, and add `.showcase/` to the project's `.gitignore` if not already present (create `.gitignore` if it doesn't exist). On iteration requests ("more"), update this same file in place — never create a second file. Open the file when done.

---

## Iteration: When the User Says "More"

When the user asks for "more", "try again", "different ideas", or "what else" — they want fresh creative directions in the **same HTML file**, not a new mockup.

1. **Read the existing mockup** — identify which design axes were already explored (layout, density, hierarchy, interaction pattern, visual weight).
2. **Generate variations on UNEXPLORED axes.** If the first round explored layout (stacked vs horizontal vs grid), the next round explores density, interaction model, or information hierarchy. Don't rehash.
3. **Replace the variations in the existing file** — swap the variation HTML and switcher buttons. Keep the page shell, design tokens, surrounding content, and sample data untouched.
4. **Preserve any variation the user explicitly liked.** "I like the second one, show me more" means keep that variation, replace the others.

**Do NOT re-extract design tokens** — Phase 1 was already done. Reuse what's in the file.
**Do NOT rebuild the page shell** — it's already correct. Only touch the component slot and variation switcher.
**Do NOT accumulate variations across rounds** — each round still has 3-4 variations max. Iteration replaces, it doesn't pile up.

---

## NEVER Do These

- **NEVER generate a mockup before extracting the project's design tokens.** A mockup without design extraction defaults to the AI aesthetic (Inter + purple + shadcn) regardless of what the project actually looks like.
- **NEVER use the "AI demo" aesthetic.** No purple gradients, no Inter-as-only-font, no uniform 8px border-radius on everything, no oversized hero sections, no decorative icons on every card, no same-shadow-on-everything. These are immediate tells that the mockup was generated, not designed.
- **NEVER present a component floating in a void.** Always include a page shell. A component on a blank white page communicates nothing about whether it fits the application.
- **NEVER use lorem ipsum.** Use plausible content that tests the layout honestly. "John Doe" and perfectly-fitting text give false confidence.
- **NEVER add before/after for net-new features.** There is no meaningful "before." Before/after anchors stakeholders on loss rather than evaluating the new thing.
- **NEVER use full viewport width when the project has a max-width container.** A component at 1440px in a project with a 1140px container looks wrong in ways that are hard to articulate but immediately felt.
- **NEVER add a dark mode toggle if the project doesn't have dark mode.** Inventing features that don't exist undermines trust in the mockup's accuracy.
- **NEVER make all sample data perfect.** Include at least one edge case (long name, missing data, large number) or the mockup lies about how the component will actually look.
- **NEVER put annotation text inside the UI chrome.** Reviewers will wonder "is that part of the design or a note?" All annotations go outside the page shell boundary.
- **NEVER add skeleton/shimmer loading states to every component.** Shimmer on a component with no real load latency is an AI aesthetic tell — it signals "covering bases" rather than understanding the actual data flow. Add loading states only when the component fetches data.
- **NEVER generate cosmetic-only variations.** "Blue vs green" or "slightly rounder corners" is one design in multiple costumes. Each variation must differ on a meaningful axis (layout, density, hierarchy, interaction pattern) — otherwise the user has no real choice to make.
- **NEVER label variations "Option A/B/C" or "v1/v2/v3".** Generic labels tell the user nothing about what each approach IS. Use descriptive names that communicate the design intent ("Minimal", "Structured", "Dense", "Horizontal", "Stacked").
- **NEVER change the page shell or data between variations.** The point of variations is to compare DESIGNS. If the shell, surrounding content, or data differs between variations, you're comparing scenes, not designs.
- **NEVER ship a straw-man variation.** Every variation must be genuinely usable. If you're including a "bad" option to make another look better, you're manipulating the decision, not supporting it.
- **NEVER generate more than 4 variations.** Choice overload degrades decisions. 3 is the default, 4 is the cap. If you have 5 ideas, cut the weakest.
