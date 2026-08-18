---
name: design-tokens
description: Generate, extend, or audit design tokens in DTCG format with the 3-tier architecture (primitive → semantic → component). Use when the user wants a color palette, type scale, spacing/shadow/radius/motion tokens, multi-brand theming, or wants to validate token files. Covers colors, typography, spacing, shadows, borders, breakpoints, motion, gradients, opacity, blur, sizing, states, theming.
---

# Skill: Design Tokens

Produce and maintain DTCG (`$type`/`$value`) tokens following the project's 3-tier system.

## Steps
1. Soma has no CLAUDE.md-level token doc — the rules live in code: `Soma/Components/Theme.swift` (colors/spacing/radius), `Soma/Components/SomaType.swift` (typography), `Soma/Components/GlassMaterials.swift` (glass/blur). Read those first; they are the source of truth, not `design-kit/tokens/`.
2. Use `design-kit/tokens/*.json` (DTCG format: `colors.json`, `typography.json`, `spacing.json`, `shadows.json`, `borders.json`, `breakpoints.json`, `motion.json`, `gradients.json`, `opacity.json`, `blur.json`, `sizing.json`, `states.json`, `theming.json`) only as a reference architecture (3-tier primitive → semantic → component, OKLCH palette generation) when extending Soma's own token set — never as values to hardcode over the existing Swift ones.
3. Generate/extend tokens:
   - Primitives = raw values (never used directly). Semantic = purpose aliases. Component = component-scoped.
   - New palettes: generate 11 OKLCH shades; verify 500 ≥ 4.5:1 on white (text), 600 ≥ 3:1 (UI) using the `a11y-audit` skill / `python3 design-kit/scripts/contrast.py`.
   - Multi-brand/density → `theming.json`.
4. **Validate**: run `python3 design-kit/scripts/validate_tokens.py` (JSON validity + alias resolution) — only relevant if you edited `design-kit/tokens/*.json` itself.
5. Any new/changed value must land in `Theme.swift`/`SomaType.swift`/`GlassMaterials.swift` as the real, compiled source — the JSON files are notes, not shipped code.

## Output
For Soma, the deliverable is a Swift diff to `Theme.swift`/`SomaType.swift`/`GlassMaterials.swift`, not a JSON file. Use DTCG JSON only as an intermediate reference when useful. Reference existing constants, never hardcode a new literal.
