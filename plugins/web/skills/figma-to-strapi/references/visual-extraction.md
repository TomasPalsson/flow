---
name: visual-extraction
description: Complete use_figma script for extracting visual properties (colors, gradients, typography, spacing, effects, decorative elements) from Figma nodes and converting to CSS/Tailwind values
---

# Visual Property Extraction Script

Run this via `use_figma` after calling `figma:figma-use` skill. Replace `NODE_ID` with the target node.

## Full Extraction Script

```javascript
const node = await figma.getNodeByIdAsync("NODE_ID");
if (!node) return { error: "Node not found" };

// --- Color conversion helpers ---
function toHex(r, g, b) {
  return '#' + [r, g, b].map(c => Math.round(c * 255).toString(16).padStart(2, '0')).join('');
}
function toRgba(r, g, b, a) {
  return `rgba(${Math.round(r * 255)}, ${Math.round(g * 255)}, ${Math.round(b * 255)}, ${Number(a.toFixed(3))})`;
}

// --- Gradient angle from transform matrix ---
function gradientAngle(transform) {
  if (!transform) return 180;
  const [[m00, m01], [m10, m11]] = transform;
  const angleRad = Math.atan2(m10, m00);
  const angleDeg = angleRad * (180 / Math.PI);
  return Math.round((angleDeg + 90 + 360) % 360);
}

// --- Extract fills ---
function extractFills(fills) {
  if (!fills || fills === figma.mixed) return [];
  return fills.filter(f => f.visible !== false).map(fill => {
    if (fill.type === 'SOLID') {
      const { r, g, b } = fill.color;
      const a = fill.opacity ?? 1;
      return { type: 'solid', hex: toHex(r, g, b), rgba: toRgba(r, g, b, a), opacity: a };
    }
    if (fill.type === 'GRADIENT_LINEAR' || fill.type === 'GRADIENT_RADIAL' || fill.type === 'GRADIENT_ANGULAR') {
      const angle = gradientAngle(fill.gradientTransform);
      const stops = fill.gradientStops.map(s => ({
        position: Math.round(s.position * 100),
        color: toRgba(s.color.r, s.color.g, s.color.b, s.color.a)
      }));
      let css;
      if (fill.type === 'GRADIENT_LINEAR') {
        css = `linear-gradient(${angle}deg, ${stops.map(s => `${s.color} ${s.position}%`).join(', ')})`;
      } else if (fill.type === 'GRADIENT_RADIAL') {
        css = `radial-gradient(circle, ${stops.map(s => `${s.color} ${s.position}%`).join(', ')})`;
      } else {
        css = `conic-gradient(from ${angle}deg, ${stops.map(s => `${s.color} ${s.position}%`).join(', ')})`;
      }
      return { type: fill.type.toLowerCase(), angle, stops, css };
    }
    if (fill.type === 'IMAGE') {
      return { type: 'image', scaleMode: fill.scaleMode, imageHash: fill.imageHash };
    }
    return { type: fill.type };
  });
}

// --- Extract effects ---
function extractEffects(effects) {
  if (!effects) return [];
  return effects.filter(e => e.visible !== false).map(effect => {
    if (effect.type === 'DROP_SHADOW' || effect.type === 'INNER_SHADOW') {
      const { r, g, b, a } = effect.color;
      const inset = effect.type === 'INNER_SHADOW' ? 'inset ' : '';
      const css = `${inset}${effect.offset.x}px ${effect.offset.y}px ${effect.radius}px ${effect.spread || 0}px ${toRgba(r, g, b, a)}`;
      return { type: effect.type.toLowerCase(), css, offset: effect.offset, blur: effect.radius, spread: effect.spread || 0, color: toRgba(r, g, b, a) };
    }
    if (effect.type === 'LAYER_BLUR' || effect.type === 'BACKGROUND_BLUR') {
      return { type: effect.type.toLowerCase(), radius: effect.radius, css: `blur(${effect.radius}px)` };
    }
    return { type: effect.type };
  });
}

// --- Extract typography from text node ---
function extractTypography(textNode) {
  const fontName = textNode.fontName;
  const family = fontName === figma.mixed ? 'mixed' : fontName.family;
  const style = fontName === figma.mixed ? 'mixed' : fontName.style;
  const fontSize = textNode.fontSize === figma.mixed ? 'mixed' : textNode.fontSize;
  const lh = textNode.lineHeight;
  let lineHeight = 'auto';
  if (lh !== figma.mixed) {
    if (lh.unit === 'PIXELS') lineHeight = `${lh.value}px`;
    else if (lh.unit === 'PERCENT') lineHeight = `${lh.value}%`;
  }
  const ls = textNode.letterSpacing;
  let letterSpacing = '0';
  if (ls !== figma.mixed) {
    if (ls.unit === 'PIXELS') letterSpacing = `${ls.value}px`;
    else if (ls.unit === 'PERCENT') letterSpacing = `${ls.value / 100}em`;
  }
  const textColor = textNode.fills?.[0]?.type === 'SOLID'
    ? toRgba(textNode.fills[0].color.r, textNode.fills[0].color.g, textNode.fills[0].color.b, textNode.fills[0].opacity ?? 1)
    : null;

  // Map Figma style names to CSS font-weight
  const weightMap = { Thin: 100, ExtraLight: 200, Light: 300, Regular: 400, Medium: 500, SemiBold: 600, Bold: 700, ExtraBold: 800, Black: 900 };
  const weight = weightMap[style?.split(' ')[0]] || 400;
  const italic = style?.includes('Italic') || false;

  return { family, style, weight, italic, fontSize, lineHeight, letterSpacing, textColor, characters: textNode.characters };
}

// --- Extract layout ---
function extractLayout(frame) {
  if (!frame.layoutMode || frame.layoutMode === 'NONE') return null;
  return {
    direction: frame.layoutMode === 'HORIZONTAL' ? 'row' : 'column',
    gap: frame.itemSpacing,
    padding: { top: frame.paddingTop, right: frame.paddingRight, bottom: frame.paddingBottom, left: frame.paddingLeft },
    primaryAlign: frame.primaryAxisAlignItems,
    counterAlign: frame.counterAxisAlignItems,
    sizing: { width: frame.layoutSizingHorizontal, height: frame.layoutSizingVertical }
  };
}

// --- Recursive child extraction (visual data, not just content) ---
function extractVisualTree(parent, depth = 0) {
  if (depth > 4) return [];
  return (parent.children || []).map(child => {
    const info = {
      name: child.name,
      type: child.type,
      width: Math.round(child.width),
      height: Math.round(child.height),
      x: Math.round(child.x),
      y: Math.round(child.y),
      opacity: child.opacity,
      visible: child.visible,
      fills: extractFills(child.fills),
      effects: extractEffects(child.effects),
      cornerRadius: child.cornerRadius === figma.mixed
        ? { tl: child.topLeftRadius, tr: child.topRightRadius, br: child.bottomRightRadius, bl: child.bottomLeftRadius }
        : child.cornerRadius || 0,
      blendMode: child.blendMode !== 'NORMAL' ? child.blendMode : undefined,
    };

    if (child.type === 'TEXT') {
      info.typography = extractTypography(child);
    }

    if (child.layoutMode && child.layoutMode !== 'NONE') {
      info.layout = extractLayout(child);
    }

    if (child.children?.length) {
      info.children = extractVisualTree(child, depth + 1);
    }

    return info;
  });
}

// --- Build the complete visual DNA ---
const visualDNA = {
  name: node.name,
  type: node.type,
  width: Math.round(node.width),
  height: Math.round(node.height),
  fills: extractFills(node.fills),
  effects: extractEffects(node.effects),
  cornerRadius: node.cornerRadius === figma.mixed
    ? { tl: node.topLeftRadius, tr: node.topRightRadius, br: node.bottomRightRadius, bl: node.bottomLeftRadius }
    : node.cornerRadius || 0,
  opacity: node.opacity,
  layout: extractLayout(node),
  children: extractVisualTree(node)
};

return visualDNA;
```

## How to Use the Output

The script returns a JSON object with the complete visual tree. Use it to:

### 1. Background/Container Styling
```
fills[0].css → use as background value
  e.g., "linear-gradient(180deg, rgba(26, 37, 54, 1) 0%, rgba(78, 207, 160, 1) 100%)"
  → className="bg-[linear-gradient(180deg,_rgba(26,37,54,1)_0%,_rgba(78,207,160,1)_100%)]"
```

### 2. Typography
```
children[].typography.family → font-[FamilyName]
children[].typography.fontSize → text-[48px]
children[].typography.weight → font-[300]
children[].typography.lineHeight → leading-[56px]
children[].typography.letterSpacing → tracking-[-0.5px]
children[].typography.textColor → text-[rgba(255,255,255,0.8)]
children[].typography.italic → italic
```

### 3. Decorative Elements
Look for children with:
- `opacity < 1` → positioned div with `opacity-[0.2]`
- `blendMode` set → `mix-blend-[multiply]`
- No text content but have fills → background decorations
- Repeated similar shapes → map with a loop, use exact `width`, `height`, `x`, `y`

### 4. Layout
```
layout.direction → flex-row or flex-col
layout.gap → gap-[24px]
layout.padding → px-[64px] py-[96px]
layout.primaryAlign → justify-center / justify-between / etc.
layout.counterAlign → items-center / items-start / etc.
```

### 5. Effects
```
effects[].css → shadow-[0_4px_6px_rgba(0,0,0,0.1)]
effects[].css (blur) → backdrop-blur-[8px] or blur-[4px]
```

## Gradient Angle Conversion

Figma stores gradients as a 2x3 transform matrix. The script handles this, but if you need to verify manually:

- Figma's default linear gradient (top-to-bottom) has transform `[[0,1,0],[0,0,1]]` → CSS `180deg`
- The formula extracts the angle from `atan2(m10, m00)` and adds 90° to convert to CSS convention
- If a gradient looks wrong after conversion, compare with the `get_screenshot` output and adjust ±180° (gradient direction can be ambiguous)

## When to Use SVG Export Instead

If a decorative element has ANY of these, export it as SVG rather than trying to reproduce with CSS:
- Complex masking or clipping paths
- More than 3 overlapping gradient layers
- Path-based shapes (not simple rectangles/circles)
- Blurs applied to specific sub-layers within a group
- Pattern fills

To export via Plugin API: `await node.exportAsync({ format: 'SVG' })` — this returns the SVG markup as a string.
