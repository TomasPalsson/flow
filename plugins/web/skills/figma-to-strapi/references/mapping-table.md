---
name: mapping-table
description: Complete Figma property → Strapi field type mapping reference with examples and edge cases
---

# Figma → Strapi Field Type Mapping

## Component Properties (Primary Source)

These come from `node.componentPropertyDefinitions` — they are the designer's explicit declaration of what's editable.

| Figma Property | Type Value | Strapi Field | Config |
|---|---|---|---|
| TEXT property | `type: "TEXT"` | `string` | `maxLength: 200` unless content is clearly long |
| TEXT (long default >100 chars) | `type: "TEXT"` | `text` | For descriptions, paragraphs |
| BOOLEAN property | `type: "BOOLEAN"` | `boolean` | `default: <defaultValue>` |
| INSTANCE_SWAP (2-4 options) | `type: "INSTANCE_SWAP"` | `enumeration` | `enum: [option names]` |
| INSTANCE_SWAP (5+ or complex) | `type: "INSTANCE_SWAP"` | `component` | Create sub-component |
| VARIANT axis (2 binary values) | variant axis | `boolean` | e.g., "active=true/false" |
| VARIANT axis (3+ values) | variant axis | `enumeration` | `enum: [all variant values]` |

## Child Node Patterns (Secondary Source)

Use these when properties don't fully describe the content model.

| Child Pattern | Detection | Strapi Field | Config |
|---|---|---|---|
| TEXT node (short, <100 chars) | `type === 'TEXT'`, short `characters` | `string` | Only if no property covers it |
| TEXT node (multi-paragraph) | `type === 'TEXT'`, long content, height | `text` | |
| TEXT with mixed styles | Multiple font segments in one text node | `richtext` | Rare — confirm with user |
| IMAGE fill on rectangle/frame | `fills.some(f => f.type === 'IMAGE')` | `media` | `multiple: false, allowedTypes: ["images"]` |
| Frame with 3+ similar children | Same-type children in auto-layout | `component` + `repeatable: true` | Create sub-component for the repeated item |
| INSTANCE child (single) | `type === 'INSTANCE'` | `component` + `repeatable: false` | Map the instance's main component |
| INSTANCE children (repeated) | Multiple instances of same component | `component` + `repeatable: true` | |

## Variant Axis → Field Type Decision

```
Is the axis binary? (exactly 2 values)
├── Yes: Are they true/false, yes/no, show/hide, on/off?
│   └── Yes → boolean
│   └── No → enumeration (with 2 values)
└── No: (3+ values)
    └── enumeration with all values
```

## Naming Conventions

| Figma Name | Strapi Field Name | Rule |
|---|---|---|
| `Show Badge` | `showBadge` | camelCase, preserve intent |
| `CTA Label` | `ctaLabel` | camelCase acronyms |
| `Hero Image` | `heroImage` | camelCase |
| `size=sm/md/lg` | `size` | Use axis name directly |
| `Button` (instance swap) | `button` or `ctaButton` | Add context prefix if ambiguous |
| `Frame 47` | ASK USER | Never use auto-generated names |

## Icon Selection

Pick from Strapi admin icons based on component purpose:

| Component Type | Icon |
|---|---|
| Hero/Banner | `layout` |
| Text block | `text` |
| Image/Media | `picture` |
| Button/CTA | `link` |
| Card | `grid` |
| List/Repeating | `bulletList` |
| Form | `write` |
| Navigation | `layer` |
| Testimonial/Quote | `quote` |
| Feature/Highlight | `star` |

## Edge Cases

**Component with NO properties and only visual layers:**
- Inspect children only
- Each meaningful text node → string field
- Each image fill → media field
- Ask user for field names (don't guess from "Text Layer 1")

**Component that's purely decorative (no editable content):**
- Don't create a Strapi component
- Tell the user this component has no CMS-editable content

**ComponentSet with only style variants (no content variance):**
- Create fields only for content properties
- Map style variants to enum ONLY if editors should choose the style
- Skip visual-only variants (like "state=hover/pressed/disabled")

**Nested instance that IS the content (e.g., Icon component):**
- If the instance swap is choosing from a small set → enumeration
- If the instance swap is a complex content block → nested component
