---
name: ux-principles
description: Nielsen's 10 heuristics with expert nuance, Don Norman's principles, Gestalt, cognitive laws, and priority ranking for LLM design output. Load when the Phase 2 body summary is insufficient for a specific decision.
---

# UX Principles — Expert Reference

Load this file when resolving a specific UX concern that the SKILL.md Phase 2 summary does not cover, OR when the evaluator subagent needs the full rubric for Nielsen's 10.

---

## Nielsen's 10 Usability Heuristics (with expert nuance)

*Original 1994, revised January 2024. Source: nngroup.com/articles/ten-usability-heuristics/*

### H1 — Visibility of System Status
*The system should always keep users informed about what is going on, through appropriate feedback within a reasonable amount of time.*

**Expert nuance:**
- Response time windows: 100ms = immediate, 1s = maintained focus, 10s = attention break. (Nielsen thresholds)
- Status visibility exists at multiple altitudes: micro-feedback on actions, ambient state (badges, step indicators), macro progress (breadcrumbs, wizards).
- The subtlest violations are silent partial failures — a filter applies but the only indicator is a subtle badge users miss entirely.

**Literal checks:**
- Loading feedback for operations >1s?
- Explicit success/failure confirmation after submit?
- Current location clearly indicated (active nav, breadcrumb, step indicator)?
- Error state visually distinct from idle state?

### H2 — Match Between System and the Real World
*Speak the users' language — words, phrases, and concepts familiar to the user rather than system-oriented terms.*

**Expert nuance:**
- "Real world" is audience-relative. Medical software for clinicians should use clinical terminology — lay terms would violate this heuristic for that population.
- Icons without labels are a frequent violation: a hamburger icon means nothing without prior exposure.
- Extends to interaction logic: a shopping cart should behave like a cart (items persist), not like a queue (items expire with no warning).

**Literal checks:**
- Jargon, technical IDs, HTTP codes exposed?
- Dates, currencies, measurements in user's locale format?
- Conceptual model matches how users think about the domain?

### H3 — User Control and Freedom
*Users often choose functions by mistake and need a clearly marked "emergency exit."*

**Expert nuance:**
- Undo is NOT always the right mechanism. For safety-critical states (medical dosing, financial transactions), preview/confirm prevents errors; undo only catches them after the fact.
- Over-reliance on confirmation dialogs as a substitute for real undo is an anti-pattern — users click through all of them.
- "Emergency exit" applies to deep flows: users in a multi-step wizard need a way back without losing progress.

**Literal checks:**
- Undo for destructive actions?
- Cancel/back path from every modal and multi-step flow?
- Confirmation dialogs for irreversible actions?
- Wizards don't lose state on browser back?

### H4 — Consistency and Standards
*Users should not have to wonder whether different words, situations, or actions mean the same thing. Follow platform conventions.*

**Expert nuance:**
- Internal consistency almost always beats external consistency when they conflict — EXCEPT for platform-level conventions (iOS back gesture, browser back) where deep muscle memory wins.
- "Consistent and wrong" is better than "inconsistent and right": users can learn a non-standard pattern if it's consistent.
- Consistency enables recognition, which is faster and less error-prone than recall (connects to H6).

### H5 — Error Prevention
*Better than good error messages is a careful design that prevents a problem from occurring in the first place.*

**Expert nuance:**
- Norman distinguishes **slips** (correct intent, wrong execution) from **mistakes** (wrong intent). Slips need physical safeguards (spacing, confirmation); mistakes need better information design.
- Constraints are the strongest form of error prevention — disabling invalid options removes the possibility of certain errors entirely.
- Inline validation must be carefully timed: on every keystroke is more annoying than preventing errors. Validate on blur (focus loss), not on keypress.

### H6 — Recognition Rather Than Recall
*Minimize memory load by making elements, actions, and options visible.*

**Expert nuance:**
- Floating labels that disappear when typing violate this heuristic — users forget what they were filling in, especially in long forms.
- Recognition vs. recall is the primary reason visual menus outperform command lines for novices.
- Context switching kills recall. Inline help, tooltips, and progressive disclosure address this.

### H7 — Flexibility and Efficiency of Use
*Shortcuts — hidden from novice users — may speed up interaction for the expert user.*

**Expert nuance:**
- "Flexibility" doesn't mean showing everything at once — it's progressive disclosure.
- Accelerators are only useful if discoverable. The keyboard shortcut no one knows provides no value.
- Frequently violated in enterprise software by removing features to "simplify" — the actual need is better IA, not fewer features.

### H8 — Aesthetic and Minimalist Design
*Every extra unit of information competes with relevant information and diminishes its relative visibility.*

**Expert nuance:**
- "Minimalist" does NOT mean whitespace-heavy. A complex medical imaging tool with many controls is not a violation if all those controls are needed.
- The subtlest violators are decorative elements that add cognitive overhead: stock photography, generic icons, marketing copy on task-focused screens.
- Progressive disclosure is the mechanism: primary interface minimal, secondary/tertiary detail on demand.

### H9 — Help Users Recognize, Diagnose, and Recover from Errors
*Error messages should be expressed in plain language, precisely indicate the problem, and constructively suggest a solution.*

**Expert nuance:**
- Error messages have an implicit trust dimension. Vague errors feel like the system is hiding something, which erodes trust.
- Position matters: errors must appear near the cause. Form-level error banners at the top of a 20-field form tell users nothing.
- Slips need minimal interruption; mistakes need education.

### H10 — Help and Documentation
*If documentation is necessary, make it easy to search, focused on the user's task, list concrete steps, and not too large.*

**Expert nuance:**
- This is the last-resort heuristic — extensive documentation is a signal that the feature has a usability problem.
- Embedded help (tooltips, inline guidance) is always more effective than external help (separate docs).
- Empty states are a documentation opportunity.

### Nielsen Severity Scale (0-4)

For heuristic evaluation:
- **0** — Not a problem
- **1** — Cosmetic; fix if spare time; no task impact
- **2** — Minor; low priority; causes friction but users work around it
- **3** — Major; high priority; impairs task completion for many users
- **4** — Catastrophe; must fix before release; prevents task completion

Severity is a function of **frequency × impact × persistence**.

---

## Don Norman's Design Principles

*From "The Design of Everyday Things," revised edition (Basic Books, 2013).*

### Affordances vs. Signifiers (the critical 2013 revision)

Norman revised his definition between the 1988 and 2013 editions. In 1988 he used "affordance" loosely to mean "perceived affordance." In 2013 he clarified: **an affordance exists regardless of whether it is perceived**. A glass door affords pushing whether or not there is a visual cue.

**UI implication:** In software, affordances are constructed through pixels — every element's physical action possibilities (click, tap) exist regardless. What matters is PERCEIVED affordance. A flat, borderless text label does not look clickable even if it is.

**The flat design controversy:** Flat design often removes signifiers (shadows, bevels, underlines) while preserving affordances. The result is lower discoverability. Ghost buttons (outline-only) have lower click rates than filled buttons because the signifier is weaker.

### Signifiers

Signifiers communicate where action should take place. They make affordances perceivable.

UI signifiers: borders around inputs, underlines on links, shadows on buttons, disclosure triangles on accordions, cursor changes (pointer/text/grab).

**Expert rule:** Do not remove signifiers in pursuit of visual minimalism and wonder why users don't interact with things. Assume nothing about what users will discover without signifiers.

### Feedback

Feedback must be timely, informative, and appropriately prominent. Too slow: user loses confidence. Too fast: user misses it. Too persistent: banner blindness.

Feedback types: visual (state changes, loading indicators), auditory (use sparingly), haptic (mobile), textual (status messages, toasts).

**Mode errors** — user thinks system is in state A but it's actually in state B — are the root of double-submission bugs and data loss. Caused by poor feedback design.

### Constraints — The Strongest Form of Error Prevention

Norman's hierarchy: **constraints > affordances/signifiers > feedback > conceptual models**. If something cannot be done, it cannot go wrong.

- **Logical constraints:** Disable options that are logically unavailable.
- **Semantic constraints:** Date pickers accepting only valid dates; file uploads filtered by MIME type.
- **Cultural constraints:** RTL UI for RTL languages; red for error, green for success (in Western contexts).

Over-constraining is also a failure — users need to understand WHY an option is disabled.

### Mapping

Natural mapping uses spatial or physical analogy to make controls intuitive.

**UI implications:**
- Scroll direction maps to content direction
- Volume sliders: left→right low→high, OR bottom→top
- Form layout matches reading/processing order of underlying process

**Expert nuance:** When natural metaphors don't exist, consistent mapping (always the same, even if arbitrary) is the next best.

### Conceptual Models

The user builds a mental model from the "system image" — the design artifact. The designer's model and the user's model differ; mismatches cause errors.

**The designer's job:** minimize the gap between the designer's conceptual model, the system image, and the user's mental model. Onboarding, documentation, progressive disclosure all close this gap. Best solution: a system image so clear no education is needed.

---

## Gestalt Principles (UI-Applied)

Gestalt principles describe how the human visual system pre-attentively groups elements (~200-250ms, before conscious thought).

### Proximity
Elements spatially close are perceived as belonging together.
**Whitespace IS information architecture.** Reducing whitespace to "fit more" destroys grouping cues. "Make it more compact" usually means "make it harder to understand."

### Similarity
Elements sharing visual properties (color, shape, size) are perceived as one group.
**Similarity can override proximity:** a red element in a cluster of blue elements is grouped with other red elements elsewhere in the interface, not with its surrounding blue ones. Color carries grouping weight even when layout doesn't.

### Continuity
The eye prefers smooth, continuous paths. Elements along a line or curve are perceived as connected.
**The "bleeding edge" carousel:** A card visibly cut off at the edge triggers continuity — users scroll. A carousel showing only complete cards with dots has lower discovery rates because continuity is broken.

### Closure
The brain fills in gaps to perceive complete shapes.
**Skeleton screens exploit closure** — users perceive structure before content loads, reducing perceived wait.

### Common Region (Enclosure)
Elements enclosed within a common boundary are perceived as a group regardless of proximity.
**Card UI is a direct application.** Removing card borders in favor of whitespace-only separation is risky — the grouping cue weakens, requiring increased whitespace to compensate.

### Figure/Ground
Visual system separates the field into figure (prominent) and ground (receding).
**Modal dialogs create figure against dimmed ground.** If the dim is insufficient, the modal doesn't read as figure and the hierarchy collapses. In dark mode, figure/ground inverts — be careful with component libraries that assume light-mode figure/ground.

### Law of Prägnanz (Simplicity)
The brain prefers the simplest interpretation of ambiguous visual input.
**This is the Gestalt basis for H8 (Minimalism).** Beautiful simple layouts are beautiful BECAUSE they are easy to parse, not the other way around. The brain is minimizing processing effort, not seeking beauty.

---

## Cognitive Laws

### Fitts's Law (1954)
*T = a + b × log₂(2D/W)*
Time to acquire a target is logarithmic in distance/width ratio.

**Practical rules:**
- Apple HIG: 44×44pt minimum touch targets. Material: 48×48dp. WCAG 2.2 Minimum: 24×24 CSS px (this is a floor).
- Primary CTAs at natural end of attention flow.
- Contextual actions near content they affect.
- **Exploit screen edges and corners.** Cursor stops at edges — effectively infinite width. This is why menu bar is top-edge and Start is corner.
- 8px spacing between 44px targets is insufficient.

### Hick's Law (1952)
*T = b × log₂(n + 1)*
Decision time increases logarithmically with number of choices.

**Practical rules:**
- Navigation menus: 3-5 top-level items.
- Progressive disclosure — don't present all features at once.
- Categorize, don't list.

**Nuance:** Hick applies to DECISION time, not COMPLETION time. Sorted, searchable long lists can still be fast. Don't over-apply to remove useful options.

### Miller's Law (1956, revised 2001)
Original: 7±2 items in working memory. Cowan revision: ~4 items when rehearsal is prevented.

**The critical insight:** the unit is a CHUNK of meaningful information, not a raw data item. A user who knows card suits remembers "four aces" as one chunk, not four items. Interface design that creates patterns reduces effective working memory load.

### Doherty Threshold (1982)
Productivity soars when system response time is <400ms.

**Nielsen thresholds:**
- 100ms: immediate
- 1s: user notices but maintains thought
- 10s: attention breaks, users switch tasks

**Perceived performance > actual performance.** A 1s response with a well-designed skeleton can feel faster than 600ms with a blank screen.

---

## Krug's Laws ("Don't Make Me Think")

### First Law: Don't Make Me Think
Every moment of puzzlement adds cognitive overhead and erodes confidence.

**Expert nuance:** "Self-evident" is audience-relative. A product for expert users can use domain language. The error is assuming users are more (or less) sophisticated than they are.

### Second Law: People Don't Read, They Scan
Users scan for items matching their goal, skipping everything else (F-pattern, Z-pattern).

**Application:**
- Headings are navigation aids, not organizational courtesies.
- Bullet points > prose for most UI copy.
- CTA labels must describe the outcome: "Download the 2024 Report (PDF, 2MB)" > "Click Here"
- **OK/Cancel is a scanning failure.** Label buttons with specific actions: "Delete Account" / "Keep Account."

### Third Law: Users Muddle Through
Users try the first plausible thing. They don't invest in understanding systems.

**Application:**
- Satisficing means prominent placement is consequential.
- Onboarding that assumes users read instructions is wrong.
- The first interaction determines the mental model for all subsequent interactions.
- Features discoverable only through docs are used by <5% of users.

---

## Laws of UX (Yablonski) — Top 10 for LLM Design

### Jakob's Law
*Users spend most of their time on other sites. They prefer your site to work the same way.*

**Implication:** Convention is a gift from the ecosystem. Creativity goes into content, branding, copy. Preserve convention in interaction patterns, navigation location, form behavior, error handling.

### Tesler's Law (Conservation of Complexity)
Every application has inherent complexity that cannot be removed — only moved.

**Common violation:** Hiding power-user functionality behind "simplified" UI and providing it only through APIs or support. Complexity didn't disappear — it moved to support burden.

### Von Restorff Effect (Isolation)
The element that differs from the rest is most likely to be remembered.

**Limit:** If TOO many elements are distinctive, distinctiveness loses meaning. Only ONE element per screen should be maximally distinct. This is the principle behind "one primary CTA per screen."

### Peak-End Rule (Kahneman)
People judge experiences by the peak moment and the end, not the average.

**Expert application:** The end state is design-controllable. Confirmation pages, success screens, post-purchase emails are the END of a flow and are often undertreated. A well-designed order confirmation screen significantly improves satisfaction scores even if checkout was mediocre.

### Zeigarnik Effect
People remember uncompleted tasks better than completed ones.

**Application:** Progress indicators, streaks, "3 of 5 steps complete" leverage the open-loop drive. Used ethically for genuinely valuable actions. Used manipulatively creates anxiety — distinguish.

### Postel's Law (Robustness Principle)
*Be liberal in what you accept; be conservative in what you send.*

**UI application:** Accept "555 867 5309," "555-867-5309," "(555) 867-5309" as valid phone numbers. Display in one normalized format. Most form validation errors are Postel's Law violations — the system refuses input it could trivially normalize.

---

## Priority Ranking for LLM Design Output

**Tier 1 — Non-negotiable (apply to every design):**
1. H2 Match System/Real World — labels, errors, copy in user vocabulary
2. H1 Visibility of System Status — every interactive state designed
3. H9 Error Recognition/Recovery — errors specific and actionable
4. H5 Error Prevention — constraints > confirmations > messages
5. WCAG 1.4.3 Contrast + 2.1.1 Keyboard — catastrophic when they fail

**Tier 2 — High leverage, routinely missed:**
6. Fitts's Law — touch target sizes, proximity of related actions
7. Proximity (Gestalt) — whitespace as information architecture
8. H4 Consistency — same action = same everything throughout
9. H8 Minimalism via progressive disclosure
10. Jakob's Law — convention by default; justify every deviation

**Tier 3 — Expert differentiation:**
11. Tesler's Law — when simplifying, specify where complexity goes
12. Peak-End Rule — design the success/completion state explicitly
13. H3 User Control — undo > confirmations
14. Norman's Signifiers — describe affordances explicitly
15. WCAG 3.3.2 Labels + 4.1.2 Name/Role/Value

**Tier 4 — Context-dependent:**
16. Hick's Law — navigation, menus, any choice set
17. Zeigarnik — onboarding, progress tracking, re-engagement
18. Miller's Law — information density, forms, dashboards
19. Doherty Threshold — loading and transition behavior
20. WCAG 2.4.3 Focus Order — SPAs and modal-heavy interfaces

---

## Accessibility as UX — The Expert Framing

WCAG compliance is frequently treated as legal obligation, separate from "good UX." Experts reject this. Accessibility features are usability features:

- **Captions/transcripts** serve users in noisy environments and non-native speakers, not just deaf users.
- **Keyboard navigation** serves power users, not just motor-impaired users.
- **High contrast** serves users in bright sunlight, not just users with low vision.
- **Screen reader semantics** serve voice control users (Dragon, Siri), not just blind users.
- **Responsive zoom** serves older users and users on small screens.

The "curb cut effect" — disability accommodations that improve the experience for all users — operates across almost every WCAG success criterion.
