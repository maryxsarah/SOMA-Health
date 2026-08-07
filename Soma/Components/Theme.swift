import SwiftUI

enum Theme {
    static let pillFill = Color(red: 0.09, green: 0.16, blue: 0.36)
    static let backgroundTop = Color.white
    static let backgroundBottom = Color(red: 0.85, green: 0.92, blue: 1.0)
    static let orbPrimary = Color(red: 0.25, green: 0.55, blue: 0.85)
    static let orbSecondary = Color(red: 0.35, green: 0.78, blue: 0.75)

    static var display: Font {
        .system(.largeTitle, design: .serif).italic()
    }

    static var eyebrow: Font {
        .system(.subheadline, design: .default).weight(.medium)
    }
}

/// Design tokens for the 2026-07 handoff (`handoff/css/soma-tokens.css`) --
/// the five screens it covers (Home/week-strip, day-detail, completed-
/// workout, Profile, and the shared button system). Values are lifted
/// directly from that stylesheet. There is no per-creator `[data-theme]`
/// variant here -- creator lenses/coaches aren't a feature this app has,
/// so every screen uses the single `accent` below, never a per-person one.
/// Everywhere else in the app keeps using `Theme` above unchanged.
enum SomaTokens {
    // MARK: Neutrals
    static let ink = Color(red: 0.078, green: 0.078, blue: 0.122)      // #14141F
    static let ink2 = Color(red: 0.431, green: 0.431, blue: 0.482)     // #6E6E7B
    static let ink3 = Color(red: 0.541, green: 0.541, blue: 0.600)     // #8A8A99
    static let ink4 = Color(red: 0.604, green: 0.604, blue: 0.651)     // #9A9AA6
    static let ink5 = Color(red: 0.788, green: 0.788, blue: 0.824)     // #C9C9D2
    static let hairline = Color(red: 0.902, green: 0.902, blue: 0.925) // #E6E6EC
    static let surface = Color.white                                   // #FFFFFF
    static let surface2 = Color(red: 0.980, green: 0.980, blue: 0.988) // #FAFAFC
    static let surface3 = Color(red: 0.957, green: 0.957, blue: 0.973) // #F4F4F8
    static let surface4 = Color(red: 0.945, green: 0.945, blue: 0.961) // #F1F1F5

    // MARK: Accent (single, app-wide -- never per-creator)
    static let accent = Color(red: 0.039, green: 0.357, blue: 0.827)     // #0A5BD3
    static let accentSoft = Color(red: 0.894, green: 0.929, blue: 0.984) // #E4EDFB
    static let accentDeep = Color(red: 0.071, green: 0.235, blue: 0.478) // #123C7A

    // MARK: Semantic
    static let success = Color(red: 0.122, green: 0.478, blue: 0.333)     // #1F7A55
    static let successSoft = Color(red: 0.914, green: 0.969, blue: 0.941) // #E9F7F0
    static let successDot = Color(red: 0.161, green: 0.749, blue: 0.549)  // #29BF8C
    static let warn = Color(red: 0.604, green: 0.420, blue: 0.118)        // #9A6B1E
    static let warnSoft = Color(red: 1.0, green: 0.969, blue: 0.902)      // #FFF7E6
    static let warnLine = Color(red: 0.953, green: 0.886, blue: 0.745)    // #F3E2BE
    static let danger = Color(red: 0.761, green: 0.263, blue: 0.263)      // #C24343
    static let heart = Color(red: 0.949, green: 0.349, blue: 0.349)       // #F25959
    static let heartSoft = Color(red: 0.992, green: 0.918, blue: 0.918)   // #FDEAEA
    static let heartLine = Color(red: 0.984, green: 0.851, blue: 0.851)   // #FBD9D9
    static let neutralDot = Color(red: 0.843, green: 0.843, blue: 0.871)  // #D7D7DE
    static let star = Color(red: 0.949, green: 0.702, blue: 0.129)        // #F2B321
    static let starSoft = Color(red: 0.996, green: 0.961, blue: 0.867)    // #FEF5DD
    static let starLine = Color(red: 0.988, green: 0.894, blue: 0.667)    // #FCE4AA

    // MARK: Radii (Mubert ramp: 4·6·8·10·12·16·pill)
    static let rMD: CGFloat = 10   // sm button
    static let rLG: CGFloat = 12   // segmented-control trough
    static let rXL: CGFloat = 14   // md/secondary button, inline cards
    static let r2XL: CGFloat = 16  // lg button
    static let rCard: CGFloat = 20 // content cards inside the scroll area
    static let rSheet: CGFloat = 26 // white header block, bottom corners only

    // MARK: Elevation
    /// `0 1px 2px rgba(18,20,31,.06)`
    static let shCardColor = Color(red: 0.071, green: 0.078, blue: 0.122).opacity(0.06)
    /// `0 8px 28px rgba(18,20,31,.08)`
    static let shRaisedColor = Color(red: 0.071, green: 0.078, blue: 0.122).opacity(0.08)
    /// `0 1px 2px rgba(18,20,31,.12)` -- selected segmented-control item
    static let shTabColor = Color(red: 0.071, green: 0.078, blue: 0.122).opacity(0.12)
    /// `0 1px 3px rgba(18,20,31,.25)` -- switch knob
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

    func cardStyle() -> some View {
        padding(20)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.08), radius: 16, x: 0, y: 8)
            )
    }
}
