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
