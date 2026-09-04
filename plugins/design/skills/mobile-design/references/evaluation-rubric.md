---
name: mobile-evaluation-rubric
description: The 9-dimension mobile design scoring rubric used by the evaluator subagent ONLY. The generator must not read this (it contaminates the generator/evaluator separation). Weighted dimensions, 1-5 anchors, composite formula, grades, and the vision-match verdict.
---

# Mobile Design Evaluation Rubric (evaluator subagent only)

Nine dimensions, weights sum to 100%, 1-5 scale, ship threshold composite >= 4.0. Score each dimension independently and evidence-first (cite the specific screenshot/element before the number). Weights are an expert starting point, not empirically tuned — apply judgment.

| # | Dimension | Weight |
|---|-----------|--------|
| 1 | Usability (Nielsen H1-H10) | 20% |
| 2 | Platform Nativeness | 15% |
| 3 | Ergonomics & Touch Targets | 15% |
| 4 | Safe Area & Device Fit | 10% |
| 5 | Composition & Visual Hierarchy | 10% |
| 6 | Color & Typography | 10% |
| 7 | Interaction & States | 10% |
| 8 | Accessibility & Resilience | 7% |
| 9 | Microcopy | 3% |

## 1. Usability (20%)
Nielsen H1-H10, same as web. Mobile nuance: deviating from the platform's internalized navigation (iOS tab+stack+swipe-back; Android nav bar + back gesture) is a severity-3 violation. Unvirtualized infinite scroll (visible in code) is H8 severity-2.

## 2. Platform Nativeness (15%) — does it feel like it belongs on this OS
Sub-checks (avg, round to 0.5): navigation model uses platform primitives; component vocabulary native where warranted (bottom sheets not centered modals, FAB/chips on Android); typography platform-appropriate (>=17pt iOS / >=16sp Android body); motion language (iOS springs vs Material easing); system chrome (status-bar content style matches background). Anchors: 1 = WebView with no adaptation (tap highlights, no swipe-back); 3 = RN primitives but web modals/Inter/web easing; 5 = indistinguishable from native to a non-developer.

## 3. Ergonomics & Touch Targets (15%)
Sub-checks: touch-target compliance (>=44pt/48dp; >=95% = 5, 80-94% = 4, 60-79% = 3, 40-59% = 2, <40% = 1; padded hit areas pass even if the glyph is small); primary actions reachable one-handed in the bottom ~65%; >=8pt gap between hit areas; no app swipe gesture conflicting with system swipe-back/drawer (conflict = severity-3).

## 4. Safe Area & Device Fit (10%) — tightest pass/fail from a screenshot, nearly binary
Top inset (no content under status bar / Dynamic Island, ~54pt on 14 Pro+); bottom inset (interactive content above the home indicator/gesture bar); side insets in landscape; scroll content insets; keyboard avoidance (form not hidden behind keyboard = severity-4). 5 = no violations; 3 = one significant inset violation; 2 = multiple or keyboard blocks a field; 1 = primary content unreachable.

## 5. Composition & Visual Hierarchy (10%)
Web sub-dimensions (focal point, reading order, balance, density, consistency) with mobile adjustments: single-column reading order, vertical rhythm/sectioning over F/Z patterns, lower density than web (penalize web-density ports), persistent CTAs/FAB assessed for visual weight.

## 6. Color & Typography (10%)
Web criteria plus: dark mode is required — if no dark-mode screenshot/tokens, dock 1 full point; a glass/blur spec must render as real system blur not a flat rectangle (also a Platform-Nativeness hit); body floor 16pt (17pt iOS preferred), web 14px body unacceptable; line length 30-50 chars fine on mobile.

## 7. Interaction & States (10%)
Nine states with hover replaced by **pressed/active feedback** (absence = severity-2, tap feels dead); plus swipe-row states and pull-to-refresh states where used. 8-9 covered = 5, 6-7 = 4, 4-5 = 3, 2-3 = 2, <=1 = 1. Animation: iOS springs for sheets, Material motion on Android, never animate layout, virtualized lists.

## 8. Accessibility & Resilience (7%)
Contrast (>=4.5 body / 3:1 large+UI), color not sole signifier, labels on interactive elements; plus VoiceOver/TalkBack label sanity, Dynamic Type at ~2x without breakage, dark-mode semantic integrity, landscape robustness. "Cannot determine from screenshot — requires [tool]" is valid output. 5 = verified clean; 3.5 = minor likely issues, resilience unverified; 2 = contrast failures or known Dynamic Type breakage; 1 = multiple high-impact.

## 9. Microcopy (3%)
Web 7-point checklist plus truncation risk at 320pt and large Dynamic Type. 7/7 = 5, 5-6 = 4, 3-4 = 3, 1-2 = 2, 0 = 1.

## Composite + grade
```
Composite = Usability*.20 + PlatformNative*.15 + Ergonomics*.15 + SafeArea*.10
          + Composition*.10 + ColorType*.10 + Interaction*.10 + Accessibility*.07 + Microcopy*.03
```
4.5-5.0 A ship · 4.0-4.4 B ship with minor polish · 3.0-3.9 C revise · 2.0-2.9 D significant redesign · 1.0-1.9 F restart. Ship threshold >= 4.0.

## Vision-Match verdict (when screenshots + design intent are both provided)
Run the build-vs-vision checklist (safe areas, touch targets, color/spacing vs tokens, platform components, dark mode, state coverage, typography, alignment) flagging PASS/FAIL/CANNOT-DETERMINE.
- STRONG = >=85% PASS and no FAIL in safe areas or primary-color match
- PARTIAL = 60-84% PASS, or 1-2 FAILs in non-critical areas
- DIVERGED = <60% PASS, or any FAIL in safe area, touch target, or fundamental navigation pattern
If no screenshot provided: "VISION MATCH: CANNOT VERIFY — rubric scored from intent only." For PARTIAL/DIVERGED, list each mismatch with severity and the phase it routes back to.

## Routing low dimensions back to a phase
Usability -> Phase 2. Platform-Nativeness -> Phase 1 (stance) or Phase 3 (execution). Ergonomics/Composition/Color+Type -> Phase 3. Safe-Area -> Phase 4 implementation fix (code bug, not design). Interaction -> Phase 2 (missing states) or 3/4 (wrong states). Accessibility -> Phase 3 or implementation. Microcopy -> Phase 4.

## Iteration
>= 4.0 ship. 3.5-3.9 apply top 3 fixes, re-spawn a FRESH evaluator (no prior-score anchoring). < 3.5 route the lowest dimension back. DIVERGED vision-match -> fix the build/intent gap before re-scoring. Cap 4 loops; if the composite moves < 0.3 across 3 iterations the brief and platform conventions may be in genuine tension — surface it to the user rather than grinding.
