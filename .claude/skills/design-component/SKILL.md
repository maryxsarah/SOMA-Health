---
name: design-component
description: Design a UI component spec to the house quality bar — anatomy, variants, sizes, the 8 states, token mapping, and accessibility. Use when the user wants to design or document a component (button, input, tabs, toast, combobox, date picker, modal, etc.) at the spec level before or alongside code. For generating framework code, use design-code.
---

# Skill: Design Component

Produce a complete component specification matching the project format.

## Steps
1. No project CLAUDE.md exists for Soma — treat `design-kit/components/*.md` as a spec-format reference (quality bar, the 8-state table, Atomic Design) rather than a rulebook to obey literally.
2. Check if a spec already exists: `design-kit/components/atoms.md`, `molecules.md`, `organisms.md`, `templates.md`, `navigation.md`, `feedback.md`, `forms-advanced.md`, `overlays.md`. Match the existing spec format for the write-up, but check for an actual existing SwiftUI equivalent in `Soma/Components/` before speccing a new one — Soma already reuses `PillButton`, `SomaButton`, `CTAPillButton`, `GlassMaterials`, etc.
3. Translate ARIA patterns (`design-kit/accessibility/aria-patterns.md`) to SwiftUI accessibility, not literal HTML/ARIA: role → `.accessibilityAddTraits(...)`, name → `.accessibilityLabel(...)`, value → `.accessibilityValue(...)`, hint → `.accessibilityHint(...)`. Pull target/contrast minimums from `design-kit/accessibility/wcag-checklist.md`.
4. Map every value to Soma's real tokens first (`Theme.swift`, `SomaType.swift`, `GlassMaterials.swift`); use `design-kit/tokens/*.json` only when Soma has no equivalent token yet.
5. Apply visual judgment from `design-kit/taste/design-taste.md` if present (states, focus, no slop) — treat as general taste guidance, not framework-specific rules.
6. Optional fast start: `python3 design-kit/scripts/scaffold_component.py "<Name>"` to emit a markdown spec stub, then fill it in.

## Output
Spec with: anatomy diagram, variants table, sizes table, all applicable states, token mapping, accessibility (VoiceOver label/traits/keyboard), and a note to render via `design-kit/frameworks/swiftui.md` conventions.

## Accuracy — verify every state, don't assume (mandatory when code is produced)
A component is only "correct" when **every variant × state** renders right — not just the resting default. There is no automated render gate for SwiftUI in this kit (`verify_states.mjs`/`axe_audit.mjs`/`measure_render.mjs`/`verify_focustrap.mjs` are Playwright-over-HTML and do not apply here). Instead:
- Build a **states harness**: a `#Preview` (or a temporary debug screen) showing the component in each applicable state — default, pressed, disabled, loading, error, selected, and hover/focus only where the platform actually has them (iPad/Mac pointer, keyboard/VoiceOver focus) — × each variant.
- Actually run it in the Simulator (or Preview canvas) in **both light and dark**, and at a large Dynamic Type size. Never claim a state is correct without having looked at it rendered.
- For any new/changed color pair, measure with `python3 design-kit/scripts/contrast.py "<fg>" "<bg>"` — don't eyeball contrast.

## Contrast/a11y checks do NOT prove pixels are right. RENDER AND LOOK.
A control can pass every contrast check while still being visibly broken: a toggle that doesn't actually flip its bound state, an icon glyph off-center inside its frame, a custom checkmark drawn with inconsistent stroke weight vs. its indeterminate/dash state, a `.animation()` that leaves the view mid-transition when state changes rapidly. Screenshot or eyeball the Preview/Simulator for every state, specifically checking:
- **Functional**: tap each control and confirm the bound `@State`/`@Binding` actually changed — not just that something animated.
- **Geometry**: glyphs/icons centered in their frame, not clipped by a fixed `.frame(height:)` at large Dynamic Type sizes.
- **Consistency**: the same component (e.g. a custom checkbox-style control) must look and behave identically everywhere it's reused — factor one `View`/`ButtonStyle`, never hand-roll a near-duplicate per screen.

## Responsive — every component works across device sizes and Dynamic Type
Build so nothing clips or overflows: avoid fixed `.frame(width:)` that can't shrink on a compact device (iPhone SE) or grow with Dynamic Type (`.frame(height:)` on text-containing views is the most common cause of clipped text). Prefer `.frame(minWidth:idealWidth:maxWidth:)`, `ViewThatFits`, and let text wrap rather than truncating unless truncation is the intended design. If Soma supports iPad, check split-view/compact widths too.

## Motion — tokenized, honors Reduce Motion, animates the thing that actually changes
Use durations/easing consistent with what's already established in `GlassMaterials.swift`/existing components rather than inventing new ones per component. A component that expands/collapses should animate size/opacity, not just snap `if` a view in/out — wrap the state change in `withAnimation` (or an implicit `.animation(value:)`) and gate it behind `@Environment(\.accessibilityReduceMotion)` so Reduce Motion drops or shortens it.

## Layout — fill the space, don't ship AI-sparse screens
A screen that's 80% empty `Spacer()` reads as machine-generated. When designing a dashboard-style screen, fill it with real, plausible content (a stats row + a list + something visual), matching the density of Soma's existing dashboard/detail views, not one lonely widget centered in a mostly-empty screen.

## Icons — SF Symbols, matching existing usage
Use `Image(systemName:)` (SF Symbols) consistent with the icons already used across `Soma/Components/` and `Soma/Resources/Assets.xcassets` — never an emoji as a functional icon, and never a hand-drawn path when an SF Symbol already covers the concept.

## Graphical / icon-only controls (3:1, theme-stable)
A no-text control (icon-only button, dot indicator, kebab menu) is held to **3:1** contrast (WCAG 1.4.11), not the 4.5:1 text minimum — measure with `contrast.py` against both the light and dark background it actually sits on. Colors that flip meaning between light/dark (e.g. an accent used as both a light-mode fill and dark-mode text) must be re-checked in both modes, not assumed from one.
