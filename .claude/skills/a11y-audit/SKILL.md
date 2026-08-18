---
name: a11y-audit
description: Audit a UI or design against WCAG 2.2 AA/AAA and ARIA patterns, returning criterion-referenced findings with severity and specific fixes. Use when the user wants an accessibility check, contrast verification, keyboard/screen-reader review, or wants to confirm a component meets POUR.
---

# Skill: Accessibility Audit

Evaluate against WCAG 2.2 and the project's ARIA patterns.

## Steps — adapted for SwiftUI (Soma), not web
1. Read `design-kit/accessibility/wcag-checklist.md` (POUR-organized, P0/P1/P2) and `design-kit/accessibility/aria-patterns.md`, translating each ARIA pattern to its SwiftUI/UIKit accessibility equivalent (VoiceOver, not a screen reader on HTML).
2. Check the mandatory P0 set per component, in SwiftUI terms: reachable via VoiceOver swipe navigation and, where relevant, Full Keyboard Access; focus indicator visible; correct `.accessibilityLabel`/`.accessibilityAddTraits`/`.accessibilityValue`; contrast (4.5:1 text / 3:1 UI); tap target ≥44×44pt (Apple HIG — stricter than the kit's 24px web baseline); no color-only signaling (e.g. error state needs an icon/text, not just red).
3. WCAG 2.2 additions still apply conceptually: focus must not be obscured by a sheet/overlay, target size, and (if Soma ever adds biometric/password auth) accessible authentication.
4. **Contrast — measure, don't eyeball.** The kit's `measure_render.mjs`/`verify_states.mjs` render HTML in a browser and do not apply to compiled SwiftUI — skip them. For any color pair (from `Theme.swift` or new), measure with `python3 design-kit/scripts/contrast.py "<fg>" "<bg>"`. Never state a ratio you did not measure. For real verification of the rendered UI, use the `run` skill to check VoiceOver behavior and contrast in the Simulator, or a `SnapshotTests/` case, in both light and dark mode.
5. Check Reduce Motion handling (`@Environment(\.accessibilityReduceMotion)` / `UIAccessibility.isReduceMotionEnabled`) — use `design-kit/taste/motion-choreography.md` for general motion judgment, adapted to SwiftUI's animation APIs rather than CSS transitions.

## Output
A findings table: WCAG criterion (e.g. 1.4.3) · severity (P0/P1/P2) · what fails · specific fix. Confirm passes explicitly. Accessibility may never be traded for aesthetics.
