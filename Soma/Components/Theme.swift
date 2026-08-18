import SwiftUI

/// Legacy palette, still referenced by the ~25 screens outside the
/// original SomaTokens pass. Repointed to the Soma Glass accent/blob
/// colors (2026-08 handoff) so those screens pick up the new brand blue
/// without a per-call-site edit; `display`/`eyebrow` were already correct
/// (serif-italic headline, tracked-caps eyebrow) and are unchanged.
enum Theme {
    static let pillFill = SomaTokens.accent
    static let orbPrimary = SomaTokens.blobBlue
    static let orbSecondary = SomaTokens.blobViolet

    static var display: Font {
        // Weight must be in the initializer -- `.italic().weight()` doesn't
        // compose on iOS and silently renders at regular weight.
        .system(size: 34, weight: .bold, design: .serif).italic()
    }

    static var eyebrow: Font {
        .system(.subheadline, design: .default).weight(.medium)
    }
}

/// Design tokens for Soma Glass (2026-08 handoff, `soma-glass-tokens.css`) --
/// translucent glass surfaces over a soft blue/violet gradient, replacing
/// the flat white-card system from the 2026-07 handoff. Member names are
/// kept stable across the migration so the ~50 existing call sites didn't
/// need touching; values are lifted directly from the token sheet, and new
/// members (accent light/lighter/deepest, radii below `rCard`, blur/motion
/// constants, blob colors) cover what the old flat system had no
/// equivalent for.
enum SomaTokens {
    // MARK: Ink (text) -- ink/ink2/ink3/ink4/ink5 keep their old names but
    // now point at the closest glass ink-N level per the token sheet's own
    // mapping notes; inkRowTitle/inkParagraph/inkPlaceholder are new.
    static let ink = Color(red: 0.078, green: 0.078, blue: 0.122)          // #14141F -- ink-1, headings
    static let inkRowTitle = Color(red: 0.227, green: 0.227, blue: 0.282) // #3A3A48 -- ink-2, row titles
    static let ink2 = Color(red: 0.353, green: 0.353, blue: 0.408)         // #5A5A68 -- ink-3, body/secondary
    static let inkParagraph = Color(red: 0.420, green: 0.420, blue: 0.471) // #6B6B78 -- ink-4, long-form copy
    static let ink3 = Color(red: 0.541, green: 0.541, blue: 0.600)         // #8A8A99 -- ink-5, captions/subtitles
    static let ink4 = Color(red: 0.604, green: 0.604, blue: 0.651)         // #9A9AA6 -- ink-6, eyebrows
    static let inkPlaceholder = Color(red: 0.690, green: 0.690, blue: 0.737) // #B0B0BC -- ink-7, placeholder
    static let ink5 = Color(red: 0.753, green: 0.753, blue: 0.792)         // #C0C0CA -- ink-8, faint icon strokes
    /// Glass hairline ring -- `rgba(120,150,220,0.22)`, doubles as the
    /// thin stroke around lens/gel surfaces and any remaining flat line.
    static let hairline = Color(red: 120 / 255, green: 150 / 255, blue: 220 / 255).opacity(0.22)

    // MARK: Surfaces -- translucent white at increasing opacity (glass-card
    // = 0.42, glass-card-flat = 0.5); flat `.fill(SomaTokens.surfaceN)`
    // call sites read as soft glass automatically once composed over the
    // new gradient background, no call-site changes needed.
    static let surface = Color.white.opacity(0.9)      // near-opaque -- sheets, fields
    static let surface2 = Color.white.opacity(0.5)      // glass-card-flat
    static let surface3 = Color.white.opacity(0.6)      // grouped rows, "quote" fills
    static let surface4 = Color.white.opacity(0.75)     // progress-track backgrounds

    // MARK: Accent (single, app-wide -- never per-creator, never a second hue)
    static let accent = Color(red: 0x1B / 255, green: 0x4A / 255, blue: 0xE2 / 255)        // #1B4AE2
    static let accentLight = Color(red: 0x5A / 255, green: 0x7D / 255, blue: 0xF5 / 255)   // #5A7DF5 -- gradient top stop
    static let accentLighter = Color(red: 0x8F / 255, green: 0xAE / 255, blue: 0xF8 / 255) // #8FAEF8 -- gel highlight stop
    static let accentDeep = Color(red: 0x1B / 255, green: 0x3F / 255, blue: 0xC9 / 255)    // #1B3FC9
    static let accentDeepest = Color(red: 0x16 / 255, green: 0x29 / 255, blue: 0x7E / 255) // #16297E -- orb core shadow
    static let accentSoft = accentSoft10
    static let accentSoft10 = Color(red: 27 / 255, green: 74 / 255, blue: 226 / 255).opacity(0.1)
    static let accentSoft14 = Color(red: 27 / 255, green: 74 / 255, blue: 226 / 255).opacity(0.14)
    static let accentSoft22 = Color(red: 120 / 255, green: 150 / 255, blue: 220 / 255).opacity(0.22)

    // MARK: Semantic
    static let success = Color(red: 0x1E / 255, green: 0x9E / 255, blue: 0x6A / 255)   // #1E9E6A
    static let successSoft = Color(red: 30 / 255, green: 158 / 255, blue: 106 / 255).opacity(0.12)
    static let successDot = Color(red: 0.161, green: 0.749, blue: 0.549)               // #29BF8C, unchanged
    static let warn = Color(red: 0xC9 / 255, green: 0x8A / 255, blue: 0x1E / 255)      // #C98A1E
    static let warnSoft = Color(red: 240 / 255, green: 190 / 255, blue: 100 / 255).opacity(0.16)
    static let warnLine = Color(red: 0.953, green: 0.886, blue: 0.745)                 // #F3E2BE, unchanged
    static let danger = Color(red: 0xD1 / 255, green: 0x44 / 255, blue: 0x44 / 255)    // #D14444
    static let dangerSoft = Color(red: 224 / 255, green: 90 / 255, blue: 90 / 255).opacity(0.1)
    static let heart = Color(red: 0.949, green: 0.349, blue: 0.349)                    // #F25959, unchanged
    static let heartSoft = Color(red: 0.992, green: 0.918, blue: 0.918)                // #FDEAEA, unchanged
    static let heartLine = Color(red: 0.984, green: 0.851, blue: 0.851)                // #FBD9D9, unchanged
    static let neutralDot = Color(red: 0.843, green: 0.843, blue: 0.871)               // #D7D7DE, unchanged
    static let star = Color(red: 0.949, green: 0.702, blue: 0.129)                     // #F2B321, unchanged
    static let starSoft = Color(red: 0.996, green: 0.961, blue: 0.867)                 // #FEF5DD, unchanged
    static let starLine = Color(red: 0.988, green: 0.894, blue: 0.667)                 // #FCE4AA, unchanged

    // MARK: Backgrounds -- the 175deg screen gradient + 3 soft ambient blobs
    static let bgScreenTop = Color(red: 0xF7 / 255, green: 0xFA / 255, blue: 0xFE / 255)
    static let bgScreenMid = Color(red: 0xED / 255, green: 0xF3 / 255, blue: 0xFC / 255)
    static let bgScreenBottom = Color(red: 0xE3 / 255, green: 0xED / 255, blue: 0xFA / 255)
    static let blobBlue = Color(red: 122 / 255, green: 162 / 255, blue: 255 / 255)
    static let blobViolet = Color(red: 186 / 255, green: 156 / 255, blue: 255 / 255)
    static let blobCyan = Color(red: 120 / 255, green: 200 / 255, blue: 255 / 255)

    // MARK: Radii (glass ramp: check 6 · tile 16 · row 20 · card 24 · pill 999)
    static let rCheck: CGFloat = 6    // checkboxes
    static let rMD: CGFloat = 10      // sm button
    static let rXL: CGFloat = 14      // md/secondary button, inline cards
    static let rTile: CGFloat = 16    // small icon tiles
    static let r2XL: CGFloat = 16     // lg button
    static let rRow: CGFloat = 20     // list rows
    static let rCard: CGFloat = 24    // cards, big glass surfaces
    static let rSheet: CGFloat = 26   // white header block, bottom corners only
    static let rPill: CGFloat = 999   // buttons, chips, tabs, toggles

    // MARK: Blur -- companion `.blur(radius:)` amounts for background/glow
    // layers (SwiftUI Material types don't take an arbitrary blur radius,
    // so these back hand-rolled soft layers like the screen blobs).
    static let blurCard: CGFloat = 20
    static let blurControl: CGFloat = 16
    static let blurButton: CGFloat = 14
    static let blurDock: CGFloat = 30

    // MARK: Motion -- every keyframe used anywhere in the system.
    static let spinDuration: Double = 4       // somaSpin, CTA pill ring
    static let breathDuration: Double = 3     // somaBreath
    static let glowDuration: Double = 2       // somaGlow / somaHeartGlow / somaRingGlow

    // MARK: Elevation (legacy flat-shadow colors, still used by a few
    // hand-rolled shadows outside the glass material recipes)
    static let shCardColor = Color(red: 0.071, green: 0.078, blue: 0.122).opacity(0.06)
    static let shRaisedColor = Color(red: 0.071, green: 0.078, blue: 0.122).opacity(0.08)
    static let shTabColor = Color(red: 0.071, green: 0.078, blue: 0.122).opacity(0.12)
    static let shKnobColor = Color(red: 0.071, green: 0.078, blue: 0.122).opacity(0.25)
}

extension View {
    /// `--sh-card`
    func somaCardShadow() -> some View {
        shadow(color: SomaTokens.shCardColor, radius: 1, x: 0, y: 1)
    }

    /// `--sh-raised`
    func somaRaisedShadow() -> some View {
        shadow(color: SomaTokens.shRaisedColor, radius: 14, x: 0, y: 8)
    }

    /// `--sh-tab` -- the selected pill inside a SomaSegmentedControl
    func somaTabShadow() -> some View {
        shadow(color: SomaTokens.shTabColor, radius: 1, x: 0, y: 1)
    }
}

extension View {
    func somaBackground() -> some View {
        background(BackgroundGradientView())
    }

    /// A sheet's background needs to read as clearly opaque glass, not the
    /// bare gradient a full screen uses -- a near-solid white wash over the
    /// same gradient, per the 3a handoff's sheet-container recipe. Use this
    /// (never bare `.somaBackground()`) on anything presented as a `.sheet`.
    func somaSheetBackground() -> some View {
        background {
            ZStack {
                BackgroundGradientView()
                Color.white.opacity(0.55).ignoresSafeArea()
            }
        }
    }

    /// Thin glass card -- content containers (hero cards, widget tiles,
    /// list groups). See `GlassMaterials.swift` for the material recipe.
    func cardStyle() -> some View {
        padding(20)
            .glassCard()
    }
}
