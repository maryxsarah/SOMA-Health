import SwiftUI

/// The glass material recipes from `soma-glass-tokens.css` §"MATERIAL
/// RECIPES", translated to SwiftUI. CSS multi-layer `box-shadow` has no
/// direct SwiftUI equivalent -- SwiftUI only offers outer drop shadows, no
/// inset ones -- so each CSS layer becomes its own named piece composited
/// in the same stacking order as the source recipe, rather than one
/// flattened approximation:
///   - `backdrop-filter: blur()` → `.ultraThinMaterial`
///   - CSS `background` gradient → a matching `LinearGradient` fill
///   - `inset 0 0 0 1px <white>` → an inset hairline `.strokeBorder()`
///   - `0 0 0 1px <tint>` → a second, outer-ring `.strokeBorder()`
///   - `inset 0 2px 3px <white>` (the top specular highlight every glass
///     surface carries) → `topSpecular(_:opacity:)`, a white-to-clear
///     gradient confined to roughly the shape's top third
///   - `inset 0 -Ypx Zpx <tint>` (the cool bottom shadow) →
///     `bottomInsetTint(_:color:opacity:)`, the mirror gradient from the
///     bottom edge
///   - the outer `0 Ypx Zpx <tint>` → a real `.shadow()`
enum GlassGelTone {
    case blue, red
}

/// CSS `inset 0 2px 3px rgba(255,255,255,X)` -- confined to roughly the
/// top third/half of the shape (`heightFraction`), never masked separately
/// since a `LinearGradient` already holds its last stop's color (here,
/// transparent) for the remainder of the shape on its own.
private func topSpecular(_ shape: some Shape, opacity: Double, heightFraction: CGFloat = 0.42) -> some View {
    shape.fill(
        LinearGradient(
            colors: [Color.white.opacity(opacity), Color.white.opacity(0)],
            startPoint: .top, endPoint: UnitPoint(x: 0.5, y: heightFraction)
        )
    )
}

/// CSS `inset 0 -Ypx Zpx rgba(...)` -- the cool-toned bottom inset shadow.
private func bottomInsetTint(_ shape: some Shape, color: Color, opacity: Double, startFraction: CGFloat = 0.55) -> some View {
    shape.fill(
        LinearGradient(
            colors: [color.opacity(0), color.opacity(opacity)],
            startPoint: UnitPoint(x: 0.5, y: startFraction), endPoint: .bottom
        )
    )
}

private struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat
    var flat: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content.background {
            if flat {
                // glass-card-flat: no blur, no outer shadow -- lighter
                // weight for grouped list rows.
                shape
                    .fill(Color.white.opacity(0.5))
                    .overlay(shape.strokeBorder(Color.white.opacity(0.85), lineWidth: 1))
            } else {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay(shape.fill(Color.white.opacity(0.42)))
                    .overlay(shape.strokeBorder(Color.white.opacity(0.8), lineWidth: 1))
                    .shadow(color: Color(red: 94 / 255, green: 130 / 255, blue: 220 / 255).opacity(0.1), radius: 13, x: 0, y: 10)
            }
        }
    }
}

/// Raised, unselected control -- the full 5-layer `.glass-lens` recipe.
private struct GlassLensModifier: ViewModifier {
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content.background(
            ZStack {
                shape.fill(.ultraThinMaterial)
                // Literal `soma-glass-tokens.css` stops (0.98/0.75/0.3/0.5)
                // -- an earlier pass here cut these ~30% to compensate for
                // `.ultraThinMaterial` reading weaker than a real CSS
                // `backdrop-filter: blur()`, but that also muted the
                // specular/tint/ring layers riding on top of it into an
                // overall flat, washed-out lens ("эффекты кривые"). Full
                // literal values, matching the design's own SwiftUI port.
                shape.fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.98),
                            Color.white.opacity(0.75),
                            Color(red: 240 / 255, green: 246 / 255, blue: 255 / 255).opacity(0.3),
                            Color(red: 224 / 255, green: 234 / 255, blue: 252 / 255).opacity(0.5)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                topSpecular(shape, opacity: 0.9, heightFraction: 0.38)
                bottomInsetTint(shape, color: Color(red: 94 / 255, green: 130 / 255, blue: 220 / 255), opacity: 0.14)
                shape.strokeBorder(Color.white.opacity(0.95), lineWidth: 1)
            }
            // Outer hairline is a plain .stroke() pushed half a point
            // OUTSIDE the shape (not another strokeBorder on the same
            // inward band) -- two strokeBorders here wash into one mushy
            // edge instead of two distinct rings. SomaTokens.accentSoft22
            // (0.22) rather than a hand-rolled 0.4 -- the doubled opacity
            // read as a hard outline instead of a soft glass edge.
            .overlay(shape.stroke(SomaTokens.accentSoft22, lineWidth: 1).padding(-0.5))
            // Two shadows, matching the CSS recipe's soft lift + tight
            // contact shadow -- one shadow alone left every lens looking
            // like it was floating rather than resting on the surface.
            .shadow(color: Color(red: 94 / 255, green: 130 / 255, blue: 220 / 255).opacity(0.18), radius: 8, x: 0, y: 7)
            .shadow(color: Color(red: 94 / 255, green: 130 / 255, blue: 220 / 255).opacity(0.12), radius: 2, x: 0, y: 2)
        )
    }
}

/// Selected / primary -- the full 4-layer `.glass-gel-*` recipe.
private struct GlassGelModifier: ViewModifier {
    var tone: GlassGelTone
    var cornerRadius: CGFloat

    private var fillColors: [Color] {
        switch tone {
        case .blue:
            [
                Color(red: 90 / 255, green: 130 / 255, blue: 245 / 255).opacity(0.85),
                SomaTokens.accent.opacity(0.85),
                Color(red: 20 / 255, green: 50 / 255, blue: 170 / 255).opacity(0.8),
                SomaTokens.accent.opacity(0.85)
            ]
        case .red:
            [
                Color(red: 240 / 255, green: 120 / 255, blue: 120 / 255).opacity(0.5),
                SomaTokens.danger.opacity(0.4),
                Color(red: 190 / 255, green: 60 / 255, blue: 60 / 255).opacity(0.35),
                SomaTokens.danger.opacity(0.4)
            ]
        }
    }

    private var bottomTintColor: Color {
        switch tone {
        case .blue: Color(red: 20 / 255, green: 40 / 255, blue: 150 / 255)
        case .red: Color(red: 180 / 255, green: 50 / 255, blue: 50 / 255)
        }
    }

    private var shadowColor: Color {
        switch tone {
        case .blue: SomaTokens.accent.opacity(0.26)
        case .red: Color(red: 200 / 255, green: 60 / 255, blue: 60 / 255).opacity(0.16)
        }
    }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .foregroundStyle(tone == .blue ? Color.white : SomaTokens.danger)
            .background(
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(LinearGradient(colors: fillColors, startPoint: .top, endPoint: .bottom))
                    topSpecular(shape, opacity: tone == .blue ? 0.6 : 0.55, heightFraction: 0.3)
                    bottomInsetTint(shape, color: bottomTintColor, opacity: tone == .blue ? 0.25 : 0.14, startFraction: 0.5)
                    shape.strokeBorder(Color.white.opacity(tone == .blue ? 0.5 : 0.3), lineWidth: 1)
                }
                .shadow(color: shadowColor, radius: 7, x: 0, y: 6)
            )
    }
}

/// The floating quick-action dock's own capsule chrome -- same 5-layer
/// family as `.glassLens()` but its own background gradient/blur/shadow
/// (the mockup's dock div is its own recipe, not a lens reused at scale).
private struct GlassDockModifier: ViewModifier {
    func body(content: Content) -> some View {
        let shape = Capsule()
        content.background(
            ZStack {
                shape.fill(.ultraThinMaterial)
                shape.fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.4),
                            Color.white.opacity(0.14),
                            Color(red: 228 / 255, green: 236 / 255, blue: 252 / 255).opacity(0.28)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                topSpecular(shape, opacity: 0.8, heightFraction: 0.3)
                bottomInsetTint(shape, color: Color(red: 94 / 255, green: 130 / 255, blue: 220 / 255), opacity: 0.1)
                shape.strokeBorder(Color.white.opacity(0.65), lineWidth: 1)
            }
            .overlay(shape.stroke(Color(red: 120 / 255, green: 150 / 255, blue: 220 / 255).opacity(0.35), lineWidth: 1.25).padding(-0.5))
            .shadow(color: Color(red: 94 / 255, green: 130 / 255, blue: 220 / 255).opacity(0.28), radius: 36, x: 0, y: 14)
        )
    }
}

extension View {
    /// Thin glass card -- content containers (hero cards, widget tiles, list groups).
    func glassCard(cornerRadius: CGFloat = SomaTokens.rCard) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius, flat: false))
    }

    /// Lighter-weight glass, no blur/outer shadow -- grouped list rows.
    func glassCardFlat(cornerRadius: CGFloat = SomaTokens.rRow) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius, flat: true))
    }

    /// Raised, unselected control -- icon buttons, unselected chips/tabs,
    /// unselected day/streak badges.
    func glassLens(cornerRadius: CGFloat = SomaTokens.rPill) -> some View {
        modifier(GlassLensModifier(cornerRadius: cornerRadius))
    }

    /// Selected / primary -- filled chips, filled toggle track, selected
    /// day/streak badge, danger actions (`.red`).
    func glassGel(_ tone: GlassGelTone = .blue, cornerRadius: CGFloat = SomaTokens.rPill) -> some View {
        modifier(GlassGelModifier(tone: tone, cornerRadius: cornerRadius))
    }

    /// The floating quick-action dock's capsule chrome.
    func glassDock() -> some View {
        modifier(GlassDockModifier())
    }
}

// MARK: - Motion

extension Animation {
    static var somaBreath: Animation {
        .easeInOut(duration: SomaTokens.breathDuration).repeatForever(autoreverses: true)
    }

    static var somaGlow: Animation {
        .easeInOut(duration: SomaTokens.glowDuration).repeatForever(autoreverses: true)
    }

    static var somaSpin: Animation {
        .linear(duration: SomaTokens.spinDuration).repeatForever(autoreverses: false)
    }
}

#Preview("Lens vs Gel vs Dock") {
    VStack(spacing: 24) {
        HStack(spacing: 16) {
            Image(systemName: "heart")
                .frame(width: 50, height: 50)
                .glassLens()
            Image(systemName: "heart.fill")
                .foregroundStyle(.white)
                .frame(width: 50, height: 50)
                .glassGel(.blue)
        }

        HStack(spacing: 0) {
            ForEach(["dumbbell.fill", "camera.viewfinder", "target"], id: \.self) { name in
                Image(systemName: name)
                    .frame(width: 50, height: 50)
                    .glassLens()
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(8)
        .glassDock()
        .padding(.horizontal, 18)
    }
    .padding()
    .somaBackground()
}
