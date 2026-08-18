import SwiftUI

/// The Soma Glass type scale. `Font.weight(_:)` applied after `.italic()`
/// silently doesn't compose on iOS -- weight goes in the initializer,
/// `.italic()` is always last, or New York renders at regular weight.
enum SomaType {
    // MARK: Serif display (New York italic -- weight FIRST, italic LAST)

    /// Home greeting ("Good evening").
    static let greeting = Font.system(size: 28, weight: .semibold, design: .serif).italic()
    /// Hero card title ("Light Movement", "40 min tempo run").
    static let heroTitle = Font.system(size: 33, weight: .bold, design: .serif).italic()
    /// Sheet titles ("Today's checklist", "Your widgets", "Your profile").
    static let sheetTitle = Font.system(size: 26, weight: .bold, design: .serif).italic()
    /// Full-screen titles ("Your health").
    static let screenTitle = Font.system(size: 34, weight: .bold, design: .serif).italic()
    /// Widget values ("6.3 h", "3 / 8", "Good").
    static let widgetValue = Font.system(size: 23, weight: .bold, design: .serif).italic()
    /// Affirmation widget line (16a) -- the quote itself is the hero and
    /// runs up to 3 rows, so it sits well below `widgetValue`'s size.
    static let widgetQuote = Font.system(size: 15.5, weight: .bold, design: .serif).italic()
    /// Big metrics (dashboard hero number, baseline picker) -- bold, size varies by call site.
    static func metric(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .serif).italic()
    }

    // MARK: SF companions (never serif)

    /// Uppercase eyebrow -- pair with .tracking(0.7) + .textCase(.uppercase).
    static let eyebrow = Font.system(size: 11, weight: .bold)
    static let body = Font.system(size: 14)
    static let sub = Font.system(size: 12.5)
    static let caption = Font.system(size: 11.5)
    static let buttonLabel = Font.system(size: 15.5, weight: .bold)
}
