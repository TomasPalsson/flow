---
name: figma-to-strapi
description: "Convert Figma component designs into Strapi v5 component schemas AND matching React/Next.js components. Extracts editable properties (TEXT, BOOLEAN, INSTANCE_SWAP, variants) from Figma components, generates CMS field definitions, then produces a typed .tsx component with Tailwind styling. Use when: (1) user has a Figma component and wants a matching Strapi content model + React component, (2) setting up a CMS-driven website and needs to create components from designs, (3) syncing design system components to content types, (4) asking 'how do I make this Figma component editable in the CMS?'. Requires: Figma MCP authenticated + Strapi project (typically at cms/) + Next.js project (typically at website/). Keywords: figma, strapi, component, schema, cms, content model, design-to-cms, content type, react, tsx, /figma-to-strapi."
---

# Figma → Strapi Component Generator

Generate Strapi v5 component schemas and matching React/Next.js components by inspecting Figma components. Maps design properties to CMS fields, then produces a typed `.tsx` component with Tailwind styling that renders the content.

**Prerequisites:** Figma MCP authenticated, Strapi project at `cms/`, Next.js project at `website/`.
**MANDATORY:** You MUST call the `figma:figma-use` skill (via the Skill tool) before making ANY Figma MCP call. This skill loads the Figma plugin's execution context. Without it, `use_figma` calls will fail or return incomplete data. Call it once at the start — it persists for the session.

---

## Core Principle

**Map from component PROPERTIES, not visual layers.**

Figma components expose their editable surface through properties (TEXT, BOOLEAN, INSTANCE_SWAP) and variant axes. These ARE the content model. Child node inspection is secondary — use it only to discover media fields and repeating structures that properties don't cover.

## Thinking Framework

Before mapping any component, ask yourself:

1. **What will editors actually edit?** Only create fields for mutable content. Drop shadows, background colors, divider lines — these are design concerns, not content.
2. **Is this schema encouraging good editorial UX?** If the resulting schema has >8 fields, warn the user — complex components should be split.
3. **Are there reusable sub-components?** If a nested structure appears in multiple places, extract it as a separate Strapi component to avoid duplication.

---

## Workflow

### Phase 1: Get the Figma Component

Ask the user for their Figma file URL and which component to convert. Extract `FILE_KEY` from `figma.com/design/<FILE_KEY>/...`. If URL has `?node-id=X-Y`, convert to `X:Y` for the API.

### Phase 2: Inspect the Component

**Step 1 — Load Figma skill (HARD GATE):** Call the `figma:figma-use` skill using the Skill tool. Do NOT proceed to Step 2 until this completes successfully. If it fails, troubleshoot authentication before continuing.

**Step 2 — Run inspection script.** Use `use_figma` to extract the component's content model:

```javascript
const node = await figma.getNodeByIdAsync("NODE_ID");
if (!node) return { error: "Component not found" };

const result = { name: node.name, type: node.type, properties: [], variants: [], variantValues: {}, children: [] };

// PRIMARY: Extract component properties
if (node.componentPropertyDefinitions) {
  result.properties = Object.entries(node.componentPropertyDefinitions).map(([key, def]) => ({
    key, type: def.type, defaultValue: def.defaultValue,
    variantOptions: def.variantOptions || null
  }));
}

// If ComponentSet, extract variant axes
if (node.type === 'COMPONENT_SET') {
  for (const child of node.children) {
    for (const pair of child.name.split(', ')) {
      const [prop, val] = pair.split('=').map(s => s.trim());
      if (!result.variantValues[prop]) result.variantValues[prop] = [];
      if (!result.variantValues[prop].includes(val)) result.variantValues[prop].push(val);
    }
  }
  result.variants = Object.keys(result.variantValues);
}

// SECONDARY: Inspect children for media/text/repeating patterns
function inspect(parent, depth = 0) {
  if (depth > 3) return [];
  return (parent.children || []).map(child => {
    const info = { name: child.name, type: child.type };
    if (child.type === 'TEXT') { info.characters = child.characters; info.fontSize = child.fontSize; }
    if (child.fills?.some(f => f.type === 'IMAGE')) info.hasImage = true;
    if (child.type === 'FRAME' && child.children?.length > 1) {
      info.childCount = child.children.length;
      info.layoutMode = child.layoutMode;
      info.allSameType = child.children.every(c => c.type === child.children[0].type);
    }
    info.children = inspect(child, depth + 1);
    return info;
  });
}
result.children = inspect(node);
return result;
```

### Phase 3: Map to Strapi Schema

**MANDATORY — READ ENTIRE FILE**: Before mapping fields, load [`references/mapping-table.md`](references/mapping-table.md) completely. It contains critical decision trees for INSTANCE_SWAP handling, variant axis conversion, naming conventions, and edge cases. **Do NOT load during Phases 1-2** — only here. **Essential when** the component has INSTANCE_SWAP properties, 5+ variants, or nested instances — these require the detailed decision trees in the reference.

Apply the mapping from the reference table. Quick summary:

| Figma Property | Strapi Field |
|---|---|
| TEXT | `string` (or `text` if >100 chars default) |
| BOOLEAN | `boolean` |
| INSTANCE_SWAP (few options) | `enumeration` |
| INSTANCE_SWAP (complex) | nested `component` |
| VARIANT (binary) | `boolean` |
| VARIANT (3+ values) | `enumeration` |
| Child with IMAGE fill | `media` |
| Repeated similar children | `component` with `repeatable: true` |

**Skip visual-only variants** like state=hover/pressed/disabled — editors don't control interaction states.

### Phase 4: Present, Confirm, Write Schema

**NEVER write files without showing the user first.** Present the generated schema, wait for confirmation, then write to `cms/src/components/<category>/`. If the user suggests field name changes, apply them — they know their editorial language better than Figma layer names do.

### Phase 5: Extract Visual DNA

**This phase is what makes the component LOOK like the Figma design, not just function like it.**

After the schema is confirmed, extract exact visual properties from Figma. The content model (Phase 2-4) tells you WHAT editors control. The visual DNA tells you HOW it looks.

**Step 1 — Get the design context from Figma MCP.** Use the Figma MCP's `get_design_context` tool, passing the Figma file URL and node selection. This returns a **pre-translated React + Tailwind representation** of the frame — colors, gradients, spacing, typography already converted to utility classes. This is your PRIMARY styling reference. It gives you production-ready class names and structure.

**Step 2 — Get a screenshot for visual reference.** Use the Figma MCP's `get_screenshot` tool with the same selection. This gives you a PNG of the exact Figma frame — your ground truth for visual comparison. Save/show this to compare against the rendered component later.

**Step 3 — Extract precise visual tokens via `use_figma`.** Run the visual extraction script from [`references/visual-extraction.md`](references/visual-extraction.md) to get exact values the `get_design_context` might miss or approximate:

- Exact gradient stops (RGBA + position) and gradient angle
- All fill colors as hex/rgba
- Typography: font family, size, weight, line-height, letter-spacing
- Layout: padding, gap, alignment, sizing modes
- Effects: shadows with offset/blur/spread/color
- Corner radius values
- Opacity and blend modes on decorative layers
- Decorative elements (overlays, bars, patterns) with their exact properties

**Step 4 — Identify decorative elements.** Scan children for non-content layers:
- Layers with opacity < 1 or blend modes ≠ NORMAL
- Frames/rectangles that serve as background overlays
- Repeated similar shapes (like the vertical bars in a hero section)
- Gradient overlays on top of other elements

For each decorative element, decide: **CSS reproduction** (gradients, pseudo-elements, background patterns) vs **SVG export** (complex shapes, masks, illustrations). Use CSS when possible; export SVG when the element is too complex to reproduce accurately.

### Phase 6: Generate React Component + Live Preview

Combine the Strapi schema (content model) with the visual DNA (exact styling) to produce a pixel-accurate component.

**Component generation rules:**

1. **Props from schema:** Each Strapi attribute becomes a typed prop. Map: `string`/`text` → `string`, `boolean` → `boolean`, `enumeration` → union type, `media` → `{ url: string; alternativeText?: string }`, `component` → imported sub-component type or inline interface.
2. **Styling from visual DNA (CRITICAL):** Use the EXACT values from Phase 5:
   - Use `get_design_context` output as the primary source for Tailwind classes
   - Use extracted hex colors in arbitrary Tailwind values: `bg-[#1a2536]`, `text-[#ffffff]`
   - Use exact gradient CSS: `bg-[linear-gradient(180deg,_#1a2536_0%,_#2a5a5a_50%,_#4ecfa0_100%)]`
   - Use exact font specs: `font-[family-name]`, `text-[48px]`, `font-[300]`, `leading-[56px]`, `tracking-[-0.5px]`
   - Use exact spacing: `px-[64px]`, `py-[96px]`, `gap-[24px]`
   - Reproduce decorative elements with positioned `<div>`s using absolute positioning, opacity, and exact dimensions
   - Apply shadows: `shadow-[0_4px_6px_rgba(0,0,0,0.1)]`
3. **Sensible defaults:** Provide placeholder content matching the Figma default values so the component renders meaningfully without data.
4. **Keep it simple:** Generate a single presentational component. No data fetching, no Strapi API calls — those belong in the page or container that uses this component.

**NEVER approximate colors.** Don't write `bg-green-400` when the actual color is `#4ecfa0`. Don't write `text-gray-600` when it's `rgba(255,255,255,0.8)`. Always use the exact extracted value with Tailwind's arbitrary value syntax `[...]`.

**NEVER skip decorative elements.** If the Figma design has subtle background bars, overlays, patterns, or gradients — reproduce them. These are what make a design look polished vs generic. Use absolute positioning within a `relative` container.

**Live preview flow:**

1. Write the component to `website/src/components/<ComponentName>.tsx`
2. Create a temporary preview route at `website/src/app/preview/<component-name>/page.tsx` that:
   - Imports the component
   - Renders it with dummy data derived from the schema defaults and Figma inspection
   - Uses realistic placeholder images (via `https://placehold.co/` or similar)
   - Shows multiple variants if the component has enumeration/boolean props (render each variant stacked vertically with a label)
3. Ensure the Next.js dev server is running (`bun run dev` in `website/`). If not, start it.
4. Open the preview in the browser using Chrome DevTools MCP (`navigate_page` to `http://localhost:3000/preview/<component-name>`)
5. Take a screenshot of the rendered component

**HARD GATE — visual comparison before proceeding.** Place the Figma screenshot (from Phase 5 Step 2) side-by-side with the rendered screenshot. Compare:
- Background gradient direction and color stops — do they match?
- Typography — correct font, size, weight, color, spacing?
- Decorative elements — are they present, correctly positioned, right opacity?
- Spacing — padding and gaps match the design?
- Overall proportions — aspect ratio, container height correct?

If ANY visual element is noticeably off, fix it and re-screenshot. **Loop until the rendered component is visually indistinguishable from the Figma frame at normal viewing distance.**

Then ask the user:
- Does this match your Figma design?
- Any adjustments needed?

**After approval:**
- Keep the component at `website/src/components/<ComponentName>.tsx`
- Delete the preview route (`rm -rf website/src/app/preview/<component-name>/`)
- Confirm final file location to the user

---

## Common Issues

| Problem | Symptom | Solution |
|---|---|---|
| Component has NO properties | `properties` array is empty | Fall back to child node inspection only. Map TEXT children → string, IMAGE fills → media. Ask user for field names. |
| Component is purely decorative | No text, no images, no editable content | Tell user — don't create a Strapi component. Not all design components need CMS representation. |
| Too many fields (>10) | Inspection returns many properties + children | Suggest splitting into nested sub-components. Group related fields. |
| INSTANCE_SWAP has 20+ options | `preferredValues` or `variantOptions` is very long | Create a separate Strapi component instead of a 20-option enum. Or ask if editors really need all options. |
| Deeply nested component (4+ levels) | Children contain instances containing instances | Flatten to max 2 levels. Extract inner structures as standalone components. |
| Figma authentication not set up | MCP tools fail | Guide user: call `mcp__plugin_figma_figma__authenticate`, complete OAuth flow. |
| Component not found by ID | API returns null | Verify node-id format (hyphens → colons). Check correct page. Try searching by name instead. |
| No components in file | Inspection finds 0 components | File may use frames, not components. Ask user to identify which frame/group represents the reusable block. |
| Field naming conflict | Two properties map to same camelCase name | Prefix with context: e.g., `headerTitle` vs `cardTitle`. Never silently overwrite. |

---

## Anti-Patterns

**NEVER create a field for every visual layer.** Drop shadows, background colors, divider lines, padding — these are design concerns, not content. **Why:** Editors get overwhelmed by visual minutiae. If your schema has 10 fields and 7 are colors/spacing, you've created admin debt. Strapi editors aren't Figma property panels — they're content teams who need to focus on meaning, not style.

**NEVER use `richtext` for button labels or short text (<150 chars).** **Why:** richtext invokes Strapi's heavy block editor. Button labels need consistency, not formatting. Editors expect a simple text input, see a full editor, and waste time formatting when they shouldn't. Use `string`.

**NEVER rely only on child node inspection when component properties exist.** Properties are the designer's explicit declaration of "what's editable." **Why:** A component might have a TEXT property named "label" AND a TEXT child node. Inspecting only children duplicates fields or misses the property's semantic meaning. Properties are authoritative — children are supplementary.

**NEVER nest components >2 levels deep.** If you're creating component-inside-component-inside-component, flatten. **Why:** Strapi's editor UX collapses beyond 2 levels. Editors can't see or navigate the structure. You'll get: "How do I edit the button inside the card inside the section?"

**NEVER use auto-generated Figma layer names ("Frame 47", "Text Layer 1") as field names.** Ask the user for editorial names. **Why:** Editors see these names in the admin panel. "Text Layer 1" is nonsense to a content team. They need editorial language: "headline", "description", "ctaLabel" — words that match how they think about content.

**NEVER approximate colors with named Tailwind classes.** Don't write `bg-green-400` when the extracted color is `#4ecfa0`. Don't write `text-gray-200` when it's `rgba(255,255,255,0.8)`. **Why:** Named classes are from Tailwind's default palette, not the design. Using them produces a component that looks "close enough" but never matches — the gradient is slightly off, the text is slightly wrong, the overall feel is generic instead of designed. Always use arbitrary values: `bg-[#4ecfa0]`, `text-[rgba(255,255,255,0.8)]`.

**NEVER skip decorative elements because they're "not content."** Background bars, gradient overlays, semi-transparent shapes, subtle patterns — these are what distinguish a designed component from a generic one. **Why:** The Hero example: without the vertical bars and precise gradient, it's just centered text on a green background — indistinguishable from a template. With them, it's a specific, recognizable design. Extract their exact positions, dimensions, opacities, and colors from the visual DNA and reproduce them.

---

## Example

**Input:** Figma "Hero Section" component with:
- Properties: `heading` (TEXT, default "Welcome"), `subheading` (TEXT, default "Learn more about..."), `showBadge` (BOOLEAN)
- Variant: `layout = centered / left-aligned`
- Children: rectangle with IMAGE fill, Button instance

**Output:** `cms/src/components/blocks/hero.json`
```json
{
  "collectionName": "components_blocks_heroes",
  "info": {
    "displayName": "Hero",
    "description": "Hero section with heading, image, and call-to-action",
    "icon": "layout"
  },
  "options": {},
  "attributes": {
    "heading": { "type": "string", "required": true, "maxLength": 120 },
    "subheading": { "type": "text" },
    "showBadge": { "type": "boolean", "default": false },
    "layout": { "type": "enumeration", "enum": ["centered", "left-aligned"], "default": "centered" },
    "image": { "type": "media", "multiple": false, "required": true, "allowedTypes": ["images"] },
    "ctaButton": { "type": "component", "repeatable": false, "component": "shared.button" }
  }
}
```
