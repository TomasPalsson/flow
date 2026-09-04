---
name: explainer
description: "Create stunning, interactive single-file HTML explainer pages that visually explain code, projects, concepts, or processes with animations, diagrams, and interactive elements. Use this skill whenever the user wants to explain something visually, create a documentation page, build an interactive walkthrough, generate a project overview, make a 'how it works' page, or wants any kind of educational/explanatory HTML output. Also trigger when the user says 'explain this visually', 'create an explainer', 'make me a page that explains', 'build a walkthrough', 'show how this works as a website', or asks you to explain what you just did as an HTML page. Even if the user just says 'explain' in a context where visual output would help, use this skill."
---

# Explainer Page Builder

Create self-contained, single-file HTML pages that explain code, projects, concepts, or processes through animation, diagrams, interactive elements, and beautiful design. The output is a premium interactive article — not a boring docs page.

## MANDATORY: Load Frontend Design Skill First

**Before writing ANY HTML, you MUST invoke the frontend-design skill.** This is non-negotiable. The frontend-design skill provides essential aesthetic guidelines that prevent generic, flat, AI-looking output. Without it, the explainer will look like every other AI-generated page.

```
Skill tool call:
  skill: "frontend-design:frontend-design"
```

Apply the frontend-design skill's guidance to every visual decision — color palette, typography, spacing, component styling. The explainer skill handles the *structure and content*, the frontend-design skill handles the *aesthetics*.

## What You're Building

A single `.html` file that someone can double-click to open in any browser and immediately understand the thing being explained. It should feel like reading an interactive Stripe docs page or a visual essay on Pudding.cool — polished, engaging, educational.

**Hard requirements:**
- Single self-contained `.html` file (CSS in `<style>`, JS in `<script>`, libraries via CDN)
- Working animations, not placeholder comments
- At least one rendered diagram (Mermaid, Chart.js, or SVG)
- At least one interactive element the reader can manipulate
- Dark/light theme support
- Mobile responsive
- Accessible (skip link, semantic HTML, reduced-motion support)

## Step 1: Understand What You're Explaining

Before touching any HTML:

1. **Read the subject deeply.** If explaining code you just wrote, re-read every file. If explaining a project, understand its architecture. If explaining a concept, know the edge cases.

2. **Find the core insight.** Every good explainer builds toward one "aha moment." What's the one thing that, once understood, makes everything else click? Structure the page to build toward that.

3. **Pick the right metaphor.** Ground technical concepts in something familiar before showing code. "A promise is like a restaurant pager" works because the reader has a mental model to hang the details on. Without an analogy, technical details float disconnected.

4. **Identify the audience.** Adjust depth — a junior dev needs context a senior architect doesn't. When in doubt, use progressive disclosure: simple overview visible by default, details behind collapsible sections.

## Step 2: Plan the Page Structure

Every explainer follows this arc — adapt sections as needed:

### Hero Section
- Bold animated title (CSS fade-up on load)
- One-sentence summary: what this page explains
- Visual hook: a key diagram, animated metric, or eye-catching element
- Estimated reading time

### Overview ("At a Glance")
- High-level Mermaid diagram showing the full picture
- 3-5 bullet key takeaways
- Answers: "What is this, in 30 seconds?"

### Deep Dive Sections (the core)
Choose the pattern that fits the content:

**For code explanations** — Code walkthrough with Prism.js:
- Show the actual code with syntax highlighting
- Step through it with highlighted lines that change per step
- Sticky code panel + scrolling explanation text

**For processes/architecture** — Scrollytelling:
- Sticky visual panel (diagram/code) on one side
- Scrolling narrative steps on the other
- The visual mutates as the reader progresses

**For concepts** — Progressive revelation:
- Start with the analogy/metaphor
- Build to the technical reality step by step
- Each section adds one new concept

**For comparisons** — Before/After:
- Side-by-side panels or tabbed view
- Git-diff-style coloring (red removed, green added)

### Interactive Section
At least one of:
- Live demo with controls (sliders, toggles, inputs)
- Animated diagram that responds to user interaction
- Code walkthrough with step navigation
- Toggleable before/after comparison

### Summary
- Recap the core insight in one paragraph
- Key takeaways as a bulleted list
- Collapsible FAQ for edge cases and "but what about..." questions

## Step 3: Build the HTML

Read `references/toolkit.md` for the complete CDN catalog, code snippets, and patterns. It contains everything you need for:
- Mermaid.js diagrams (flowcharts, sequence, architecture, timeline, etc.)
- Prism.js syntax highlighting with line-by-line walkthroughs
- Animation patterns (CSS scroll reveals, staggered entrances, counters)
- Scrollytelling implementation
- Interactive demo patterns
- Chart.js data visualizations
- Dark/light theme toggle
- Table of contents with active state tracking
- Reading progress bar

### HTML Skeleton

```html
<!DOCTYPE html>
<html lang="en" data-theme="dark">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta name="color-scheme" content="dark light">
  <title>[Explainer Title]</title>

  <!-- Favicon — inline SVG, no extra request -->
  <link rel="icon" type="image/svg+xml" href="data:image/svg+xml,...">

  <!-- Fonts: preconnect BOTH domains, second needs crossorigin -->
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=...&display=swap" rel="stylesheet">

  <!-- Libraries via CDN — see references/toolkit.md for URLs -->

  <style>
    /* 1. Custom Properties (light + dark tokens) */
    /* 2. Reset / Base */
    /* 3. Layout */
    /* 4. Components */
    /* 5. Animations */
    /* 6. Media Queries */

    @media (prefers-reduced-motion: reduce) {
      *, *::before, *::after {
        animation-duration: 0.01ms !important;
        transition-duration: 0.01ms !important;
      }
    }
  </style>
</head>
<body>
  <a href="#main" class="skip-link">Skip to content</a>
  <div class="progress-bar" aria-hidden="true"></div>

  <header class="hero"><!-- Animated title, summary, visual hook --></header>
  <nav class="toc" aria-label="Table of contents"><!-- Sticky ToC --></nav>
  <main id="main">
    <section id="overview"><!-- Diagram + key takeaways --></section>
    <section id="deep-dive"><!-- Core explanatory content --></section>
    <section id="interactive"><!-- Interactive elements --></section>
    <section id="summary"><!-- Recap + FAQ --></section>
  </main>
  <footer><!-- Generated by, timestamp --></footer>

  <script>
    // Theme toggle, scroll reveals, interactive elements, Mermaid init
  </script>
</body>
</html>
```

### Animation Rules

**CSS-first, JS-second.** CSS handles 80% of animation needs:
- `@keyframes` for entrance animations (fade-up, slide-in)
- `transition` for hover/state changes
- `nth-child` delays for staggered reveals

Use JavaScript (IntersectionObserver) for:
- Scroll-triggered section reveals
- Dynamic step walkthroughs
- Counter/number animations

**Performance:** Only animate `transform` and `opacity` — these are compositor-safe and won't cause layout recalculation. Everything else (top, left, width, height, background-color) kills frame rate.

### Diagram Rules

**Mermaid.js is the primary tool.** It turns a text DSL into rendered SVG — perfect for Claude to generate programmatically. Use it for flowcharts, sequence diagrams, architecture diagrams, timelines, Gantt charts, mind maps, and more.

Theme Mermaid to match your color scheme — don't use the default blue theme. See `references/toolkit.md` for theming config.

For data visualization (charts, graphs with numeric data), use **Chart.js** instead.

For custom interactive diagrams that need precise control, use **D3.js** or hand-crafted SVG.

## Step 4: Save and Open

Save the file as `explain-[topic].html` in `~/.explainer/`. Create the directory if it doesn't exist.

```bash
mkdir -p ~/.explainer
# Save file
open ~/.explainer/explain-[topic].html
```

Naming examples:
- `~/.explainer/explain-auth-flow.html`
- `~/.explainer/explain-project-overview.html`
- `~/.explainer/explain-what-changed.html`

## Quality Checklist

Before delivering, verify:

- [ ] Frontend-design skill was invoked and its guidance applied
- [ ] At least one Mermaid diagram renders correctly
- [ ] At least one interactive element works
- [ ] Scroll-triggered animations fire on section entry
- [ ] Dark/light theme toggle works
- [ ] Page is readable on mobile (test at 375px width mentally)
- [ ] `prefers-reduced-motion` media query disables animations
- [ ] Skip link exists as first focusable element
- [ ] Code blocks have syntax highlighting (if showing code)
- [ ] The core insight is clearly communicated
- [ ] No placeholder text — everything is real content about the subject
