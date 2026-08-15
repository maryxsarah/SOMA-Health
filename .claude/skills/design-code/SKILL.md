---
name: design-code
description: Generate production-ready, accessible, token-driven SwiftUI code for a Soma screen or component, reusing Theme.swift/SomaType.swift/GlassMaterials.swift. Use when the user wants working SwiftUI code for a component or screen, e.g. from a Claude Design handoff.
---

# Skill: Design Code

Render components into a target framework via the adapter system.

## Steps — Soma (SwiftUI) is the only target here
1. Target framework is fixed: SwiftUI, matching Soma's existing conventions in `Soma/Components/` and `Soma/Views/`.
2. Read `design-kit/frameworks/adapter-protocol.md` (universal contract: token resolution, component contract, styling, dark mode, motion) and `design-kit/frameworks/swiftui.md` (concrete SwiftUI patterns) — treat both as a reference style guide, not literal file paths to import.
3. Before writing anything new, check `Soma/Components/` for an existing equivalent (`Theme.swift`, `SomaType.swift`, `GlassMaterials.swift`, `PillButton.swift`, `SomaButton.swift`, `CTAPillButton.swift`, etc.) — reuse/extend over duplicating.
4. Pull the component spec from `design-kit/components/*` for anatomy/variants/states as a checklist, and translate `design-kit/accessibility/aria-patterns.md` into SwiftUI accessibility modifiers (see design-component skill). Resolve every value to Soma's real tokens (`Theme.swift`/`SomaType.swift`/`GlassMaterials.swift`), falling back to `design-kit/tokens/*.json` only as inspiration for a brand-new category Soma doesn't have yet.

## Output rules (mandatory)
Use Soma's real tokens (never hardcode) · include accessibility modifiers on every interactive element · handle all applicable states · support dark mode via `Color` assets/semantic tokens (not literal light-mode hex) · honor Dynamic Type and Reduce Motion · **deliver complete Swift files, no placeholders/`// ...`**.

## Verification (mandatory before declaring done) — adapted for a compiled SwiftUI app, not HTML
The kit's own verification scripts (`verify_states.mjs`, `axe_audit.mjs`, `measure_render.mjs`, `taste_audit.mjs`, `accuracy_report.mjs`) render HTML in a browser via Playwright — they do not run against Swift source and must not be invoked here. Use instead:
1. **No hardcoded values** — every color/spacing/radius/shadow/duration/font traces to `Theme.swift`/`SomaType.swift`/`GlassMaterials.swift`. Run `python3 design-kit/scripts/lint_hardcodes.py <changed .swift files>` — it does understand `.swift` and will flag raw hex colors (magic-number spacing/radius CGFloats are not caught by the regex, review those by eye).
2. **All applicable states present** — Default, Pressed (`ButtonStyle.isPressed`/`configuration.isPressed`), Disabled (`.disabled(...)`/`isEnabled`), Loading (`ProgressView` + disabled interaction), Error, Selected — or justified N/A. "Hover"/"Focus ring" only apply on iPad/Mac Catalyst pointer input (`.hoverEffect`, `.onHover`) or keyboard/VoiceOver focus (`.accessibilityFocused`, `.focusable`) — don't force web-style hover states onto touch-only UI.
3. **Accessibility wired** — translate ARIA (`design-kit/accessibility/aria-patterns.md`) into SwiftUI: `.accessibilityLabel`, `.accessibilityHint`, `.accessibilityValue`, `.accessibilityAddTraits`, correct grouping via `.accessibilityElement(children:)`; ≥44×44pt tap target (Apple HIG, stricter than the kit's 24px web minimum); verify any new color pair with `python3 design-kit/scripts/contrast.py "<fg>" "<bg>"`.
4. **Dark mode + Dynamic Type + Reduce Motion** — colors resolve via semantic assets/Theme.swift (not a hardcoded light hex), text scales with Dynamic Type (avoid fixed `.frame(height:)` that clips scaled text), animations respect `UIAccessibility.isReduceMotionEnabled` / `@Environment(\.accessibilityReduceMotion)`.
5. **Completeness** — full files, no truncation; if asked for N screens/components, deliver N.
6. **Single-theme consistency** — every screen consumes the same `Theme`/`SomaType`/`GlassMaterials` — never define a one-off color or font literal for a single screen.
7. **Reuse over duplication** — extend `PillButton`/`SomaButton`/`CTAPillButton`/existing card & sheet components before hand-rolling a new one; a new modal/sheet reuses the app's existing dismiss/focus-return pattern (VoiceOver focus should return to the invoking control on dismiss).
8. **Semantic token BY INTENT** — destructive actions (Delete/Remove) use a destructive/red token and SwiftUI's `.destructive` button role, never the primary-action color; the same action must look the same everywhere it appears in the app.
9. **No emoji as icons** — use **SF Symbols** (`Image(systemName:)`), matching the existing icon usage in `Soma/Resources/Assets.xcassets` and `Soma/Components/`, never an emoji as a control icon.
10. **Destructive confirmation UX** — irreversible actions (delete account/data) need a `confirmationDialog`/`alert` whose confirm button restates the action ("Delete account", not "OK"), consistent with Apple HIG.
11. **Taste pre-flight** — read `design-kit/taste/design-taste.md` for the general anti-slop checklist (states, hierarchy, density, no dead whitespace) as judgment, not a literal web checklist.
12. **Verify by actually running it.** There is no automated render gate for SwiftUI here — build the target and check the real UI: use the `run` skill to launch Soma in the Simulator, or add/update a case in `SnapshotTests/` for the touched component, and visually confirm every state in light **and** dark mode before declaring done. Never claim a state "looks right" without having actually built and viewed it.
