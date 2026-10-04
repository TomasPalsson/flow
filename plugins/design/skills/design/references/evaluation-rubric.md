---
name: evaluation-rubric
description: The complete scoring rubric for the design evaluator subagent. 7 weighted dimensions (usability first) with explicit scoring tables, Nielsen severity scale, bias mitigations, and required output format. Loaded by the evaluator subagent, NOT by the generating Claude.
---

# Evaluation Rubric — For the Evaluator Subagent

**This file is loaded by the evaluator subagent, not by the design skill's main flow.** The generating Claude should NOT read this file — that would pollute the prompt that shapes generation with the criteria that shape evaluation, collapsing the very separation we are trying to preserve.

---

## Nielsen Severity Scale (0-4)

Apply per violation, not per heuristic.

| Rating | Label | Meaning |
|--------|-------|---------|
| 0 | Not a problem | Disagree this is an issue |
| 1 | Cosmetic | Only fix if spare time; no task impact |
| 2 | Minor | Low priority; friction but users work around it |
| 3 | Major | High priority; impairs task completion for many users |
| 4 | Catastrophe | Must fix before release; prevents task completion |

Severity is a function of three factors:
- **Frequency** — how often will users encounter this?
- **Impact** — how hard is recovery?
- **Persistence** — one-time stumble or recurring on every pass?

---

## Nielsen's 10 Heuristics — Literal Checks

### H1 — Visibility of System Status
- Loading feedback for operations >1s?
- Explicit success/failure confirmation after submit?
- Current location indicated (active nav, breadcrumb, step indicator)?
- Error state visually distinct from idle state?
- Async operations show progress AND completion?

### H2 — Match Between System and Real World
- Any jargon, technical IDs, HTTP codes, database field names in user-facing text?
- Icons have real-world metaphors users share?
- Dates, currencies, measurements in user's locale format?
- Error messages in plain language?

### H3 — User Control and Freedom
- Undo for destructive actions (delete, send, publish)?
- Cancel/back path from every modal, drawer, multi-step flow?
- Confirmation dialogs for irreversible actions?
- Wizards that don't lose state on browser back?

### H4 — Consistency and Standards
- Same actions labeled consistently (Save/Update/Apply)?
- Interactive elements look interactive (underlined links, raised buttons)?
- Visual language matches platform conventions OR product design system?
- Primary/secondary/destructive button hierarchies consistent?

### H5 — Error Prevention
- Irreversible actions gated by confirmation?
- Forms use type-appropriate inputs (date picker, select)?
- Inline validation before submit?
- Ambiguous states made impossible by UI constraints?

### H6 — Recognition Rather Than Recall
- Actions visible or one-click discoverable?
- Dropdowns/pickers show all valid choices vs. requiring memorization?
- User's history/recent items shown when re-entering flow?
- Keyboard shortcuts discoverable (tooltip, legend)?

### H7 — Flexibility and Efficiency of Use
- Keyboard shortcuts for power users?
- Bulk actions available?
- Shortcuts to frequently accessed features?
- Advanced filters/options for expert users?

*Severity of H7 violations often 1-2 unless product targets expert users.*

### H8 — Aesthetic and Minimalist Design
- Every element earning its place?
- Secondary/rarely used features de-emphasized or progressively disclosed?
- Information density appropriate for context?
- No decorative chartjunk, redundant labels, repetitive iconography?

### H9 — Help Users Recognize, Diagnose, Recover
- Does every error message tell: what went wrong, why, what to do next?
- Errors displayed near the relevant field?
- Validation feedback constructive ("Password must be ≥8 characters") vs. accusatory ("Invalid input")?
- Network/system errors distinguished from user errors?

### H10 — Help and Documentation
- Contextual help available (tooltips, inline explanations)?
- Empty states instructional?
- For complex tasks, walkthrough or onboarding flow?

---

## The 7-Dimension Composite Rubric

### Scoring Scale (all dimensions)

| Score | Label | Description |
|-------|-------|-------------|
| 1 | Failing | Systematic failures; unusable or inaccessible |
| 2 | Poor | Several significant issues; impairs core tasks |
| 3 | Adequate | Meets baseline; noticeable issues but core tasks completable |
| 4 | Good | Minor issues only; most users succeed without friction |
| 5 | Excellent | No meaningful issues |

Half-scores permitted (1.5, 2.5, 3.5, 4.5). Every score must be accompanied by a one-sentence rationale with specific evidence.

---

### Dimension 1: Usability — Weight 25%

Grade via Nielsen's 10 heuristics with severity logging.

**Scoring table:**
| Condition | Score |
|-----------|-------|
| No violations found | 5 |
| Only severity 0-1 violations | 4 |
| 1-2 severity-2 violations, no severity 3-4 | 3.5 |
| 3+ severity-2 OR 1 severity-3 | 3 |
| 2+ severity-3 OR 1 severity-4 | 2 |
| Multiple severity-3 and/or severity-4 | 1 |

**Output format:**
```
H1: [violation description] — severity [0-4]
H3: [violation description] — severity [0-4]
...
Usability score: X/5 — [rationale]
```

---

### Dimension 2: Composition and Visual Hierarchy — Weight 10%

**Sub-dimensions (score each 1-5):**

| Sub-dimension | Poor (1-2) | Adequate (3) | Excellent (4-5) |
|---------------|-----------|--------------|-----------------|
| Focal point | No clear focal; everything equal weight | One focal but competing elements | Single clear focal; eye led naturally |
| Reading order | Contradicts natural scan | Partial scan path | Scan path matches priority |
| Balance | Visually unstable/chaotic | Acceptable but uninspired | Intentional balance, rhythm |
| Density | Cluttered or wastefully sparse | Manageable | Optimal for context |
| Consistency | Random spacing/layout | Some inconsistency | Rigorous grid and spacing system |

Average sub-scores, round to nearest 0.5.

---

### Dimension 3: Color and Typography — Weight 10%

**Color sub-criteria (each = 1 point):**
- [ ] Palette limited to ≤5 hues
- [ ] OKLCH or systematic palette (not ad hoc)
- [ ] Color reinforces semantic meaning consistently
- [ ] **NOT indigo/purple as primary unless brand-justified**
- [ ] **NO pure black, NO pure white** (unless a dossier directive, the brand system or the platform specifies it)
- [ ] **NO gray text on colored backgrounds**
- [ ] WCAG AA contrast (4.5:1 body, 3:1 large/UI)

**Typography sub-criteria (each = 1 point):**
- [ ] **NOT Inter/Roboto/Arial/system-ui/Space Grotesk as default** (unless a dossier directive, the brand system or the platform specifies it)
- [ ] Fonts with ≥5 weights
- [ ] Body line-height 1.4-1.6
- [ ] Display line-height 1.0-1.2
- [ ] Letter-spacing -0.02em to -0.04em for display >40px
- [ ] Letter-spacing +0.05em to +0.12em for ALL CAPS
- [ ] Max 2-3 font families
- [ ] Line length 45-75 characters for body

**Scoring:** Count met criteria from each sub-list.
- 14+ / 15 → 5
- 12-13 / 15 → 4
- 9-11 / 15 → 3
- 6-8 / 15 → 2
- ≤5 / 15 → 1

---

### Dimension 4: Interaction and Flow — Weight 15%

**States to check (9 possible):**
1. Default
2. Hover
3. Focus-visible
4. Active
5. Disabled
6. Loading
7. Error
8. Success
9. Empty

**Additional checks:**
- Affordance clarity — do interactive elements look interactive?
- Task path — how many steps to complete primary task? Irreducible or gratuitous?
- Micro-interactions — correct easing (ease-out-quart, 150-300ms, transform/opacity only)?

**Scoring:**
| Score | Condition |
|-------|-----------|
| 5 | 8-9 states covered, primary task direct, interactions self-evident |
| 4 | 6-7 states covered, minor discoverability issue |
| 3 | 4-5 states covered, or gratuitous task steps |
| 2 | 2-3 states covered, patterns unclear/inconsistent |
| 1 | ≤1 state covered, primary task not completable from design |

---

### Dimension 5: Accessibility — Weight 15%

Triage into three buckets:

**Likely failures (visible from design):**
- Contrast below 4.5:1 body / 3:1 large/UI
- Color-only error/state indicators
- Missing visible form labels
- No visible focus states
- Touch targets <24×24px
- Placeholder as only label
- Icon-only buttons with no apparent label

**Probable passes (reasonable inference):**
- Heading hierarchy logical
- Images contextually purposed
- Error states include text

**Cannot determine from static design:**
- Keyboard navigation flow
- Screen reader output quality
- ARIA attribute correctness
- `prefers-reduced-motion` respect
- Dynamic content announcements

**Scoring:**
- No likely failures + probable passes → 4-5
- 1-2 low-impact likely failures → 3
- 3+ likely failures OR 1 high-impact failure (e.g., contrast on primary CTA) → 2
- Multiple high-impact failures → 1

---

### Dimension 6: Content and Microcopy — Weight 10%

**Check each (1 point each, max 7):**
- [ ] Labels action-oriented and specific (not "Submit" but "Save changes")
- [ ] Error messages constructive and specific
- [ ] Empty states instructional, not just "No data"
- [ ] CTAs communicate value ("Start free trial" not "Click here")
- [ ] Jargon-free
- [ ] Tone consistent
- [ ] **NO AI vocabulary** — if text contains ANY of: revolutionize, unlock, seamless, game-changing, cutting-edge, next-level, the future of, empower your, scale without limits, build the future, transform your workflow — this criterion FAILS

**Scale to 1-5:** 7/7 = 5, 5-6 = 4, 3-4 = 3, 1-2 = 2, 0 = 1.

---

### Dimension 7: Project Specificity and Creativity — Weight 15%

Judged on four things, never against a named example site: (a) built from this client's real content, (b) recognisable (could only belong to this project), (c) not the generic AI look, (d) appropriate to the audience. Usability outranks this dimension: a distinctive look that hurts the primary task is marked down here too. Observations first.

- **Signature idea**: read the contract's `HERO TREATMENT` and `DIRECTIVES` lines when present and name the one idea that makes the project recognisable, citing source file and dossier fact ids. It may be type, layout, colour, photography (named dossier assets plus the crop, sequence and grade rule), the product UI (the real capture and workflow), data (the chart and what it encodes), motion, drawn graphics (the device at hero scale and one other scale) or a utility surface judged at detail scale (numerals, empty states, icons, copy), where a FAIL is a fix item, never a rebuild. No treatment is preferred; a plain, clean build that serves the user and uses the client's content well can score high. None, or only abstract decoration (gradient blob, mesh, noise hero, stock icon set) → say so.
- **Subject swap**: name a same-category business in another town. List every graphic, headline and control that would become false for it. Fewer than 3 items means the design is generic.
- **Real content**: does at least one visual or section encode real dossier data (menu toppings, sizes, hours, address)? Cite element and fact. Also PASS when the main visual is the client's own dossier asset.
- **Not the generic AI look**: name the typical AI version of this page (font, primary colour, layout, copy tone) and say how this build differs materially.
- **Controls in the design's material** (persuade/experience; operate surfaces keep platform conventions and are judged on tokens): nav, buttons, chips, cart, confirmation. A default underline nav or flat pill button reads as vibe-coded.
- **Audience fit**: would the dossier's paying audience find this look credible and appropriate in mood for the trade, and do reading surfaces stay legible? A FAIL names the specific element, not "feels off".
- **Graphics craft (when the page has custom graphics; screenshots only)**: each graphic has a UX or brand job; faces are not drawn on objects (food, products), no mascots or emoji-blobs; subjects distinguishable at thumbnail size; one consistent style; alt text or `aria-hidden` present (see `GRAPHICS.md` when supplied). Photography and product-ui add fidelity (no filter, blend or overlay on client images), natural resolution at least 1.5x rendered, and crop (focal subject not cut by the nav). No screenshots → "Cannot determine from source alone".
- **Named fold checks**: when a built page exists, report each gated row with the `fold-check.mjs` line quoted (run `fold-check.mjs <built page> --mode <mode> --treatment <HERO TREATMENT from the contract>` from the vary skill directory, the sibling of this skill; never search the filesystem for it). Rows printed `[INFO]` are not gated; a missing line is a RECAPTURE only if its row is gated. In every mode text collisions (`collisions-desktop`, `collisions-phone`) gate: no visible text box, HTML or svg `<text>`, overlaps another or is more than 30% covered by an opaque later-painted element; name the two texts on a FAIL. Also quote `page-overflow`, `meta-copy`, `duplicate-content` and `headline-on-fold` (operate/read: `title-on-fold`). Native platforms (ios/android): device screenshots, fold rows N/A.
- **Directive compliance**: list each `DIRECTIVES` line (the user's own words, e.g. "no illustrations", "black and white", "use our photos") and mark it kept or broken with evidence. A broken directive caps this dimension at 2 and is a critical issue. Directives outrank this skill's bars; a build that obeys a directive is not marked down for the bar it suspends.

Score:
- 1: nothing project-specific (no photographed, captured, typographic, drawn, layout or data element from this project); survives a competitor swap whole
- 2: decorative effects only; one or two real facts in copy
- 3: one project-specific element, but generic or appearing once
- 4: a clear signature idea built from cited facts at 2+ scales or placements, controls in the design's material, 3+ false items in the subject swap, visibly not the generic AI look and right for the audience
- 5: as 4, plus the idea carries real data or content, the first screen announces the project, clean at thumbnail size

Score 2 or below is a critical issue and returns the work to Phase 3 (purpose, dossier, concept, signature idea), except under utility, when Phase 3 was skipped (component, critique, polish, audit), or for a broken directive, which go to Phase 4 fix items.

---

## Composite Score Calculation

```
Composite = (Usability × 0.25)
          + (Interaction × 0.15)
          + (Accessibility × 0.15)
          + (Microcopy × 0.10)
          + (Composition × 0.10)
          + (Color+Type × 0.10)
          + (Specificity and creativity × 0.15)
```

| Composite | Grade | Meaning |
|-----------|-------|---------|
| 4.5-5.0 | **A** | Publishable |
| 4.0-4.4 | **B** | Ship-ready with minor polish |
| 3.0-3.9 | **C** | Needs revision before shipping |
| 2.0-2.9 | **D** | Significant redesign required |
| 1.0-1.9 | **F** | Fundamental issues; restart recommended |

---

## LLM Evaluator Bias Mitigations

Apply these consistently. Each counters a documented bias:

1. **Verbosity bias** — LLMs favor longer, more detailed designs because there's more to comment on. Counter: assess each dimension independently; do not let impressiveness bleed across dimensions.

2. **Positional/recency bias** — When evaluating alternatives, LLMs may favor first or last. Counter: evaluate each design independently before comparing.

3. **Self-preference bias** — LLMs score higher on designs matching training data aesthetic (typical SaaS dashboards). Counter: require citation of specific evidence for every score; disallow unsupported scores.

4. **Leniency bias** — LLMs trend toward middle-high scores unless explicitly anchored. Counter: provide calibration examples; require justification for any score above 4.

5. **Halo effect** — Strong visual polish inflates usability scores. Counter: score dimensions sequentially, committing to each score before viewing the next dimension.

---

## Structural Practices for Consistent Scoring

1. **One dimension at a time.** Never score all dimensions at once.

2. **Evidence-first scoring.** List findings before assigning a score.

3. **Calibration anchors.** Reference examples:
   - Score 1 example: form with no labels, no validation, no error messages, no focus indicators
   - Score 3 example: landing page with Inter, indigo primary, generic copy, no empty states
   - Score 5 example: no meaningful issues, every state designed, accessible, specific copy

4. **Structured output.** Fixed template; no free-form.

5. **Separation of observation and judgment.** Separate fields for WHAT was observed and WHAT score that implies.

6. **Negative-first framing.** Ask "what is wrong with this?" before "what is good?" Counters leniency bias.

7. **Severity-first for heuristics.** Log all violations before assigning dimension score. Scoring first anchors subsequent findings.

8. **"Cannot determine" as valid output.** For items not assessable from design (keyboard, screen reader), explicitly state "Cannot determine from static design — requires manual verification."

---

## Dimensions That Score Reliably vs. Unreliably

### High-signal (score confidently):
- Contrast ratios (computable)
- Heuristic violations with clear evidence (H1, H3, H4, H9)
- Type scale presence/absence
- State coverage
- Microcopy quality (direct, specific)
- Anti-pattern detection (purple gradient, Inter, uniform rounded-2xl, etc.)

### Lower-signal (caveat your scores):
- "Aesthetic quality" as holistic impression (too subjective without anchors)
- H8 (Minimalism) — context-dependent; what's minimal for a dashboard is cluttered for a landing page
- Emotional resonance / brand fit (requires brand context the evaluator may lack)
- H7 (Flexibility for experts) — hard without knowing user population

**Mitigation:** For lower-signal dimensions, reduce confidence in score or explicitly note the context assumption you made.
