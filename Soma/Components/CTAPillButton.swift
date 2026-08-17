import SwiftUI

/// CTA pill — byte-for-byte against soma-glass-tokens.css §4:
///   .cta-pill-wrap  = pill, padding 1.5, overflow hidden, bg white 0.35,
///                     two blue drop shadows. NO stroke rings.
///   .cta-pill-spin  = 600×600 conic layer, CENTERED UNDER the label,
///                     rotating -- the layer spins, the pill mask stays.
///   .cta-pill-label = near-white gradient pill on top.
///
/// Rotating a STROKED CAPSULE (`Capsule().stroke(angular).rotationEffect`)
/// spins the pill outline itself into a diagonal smear -- rotate the
/// energy layer, never a capsule stroke. The white ring / blue hairline /
/// sheen from an earlier pass belong to `.glassLens`, not the CTA -- the
/// CSS has none of them here.
///
/// Disabled is its own recipe (8b: "flat 45% glass, no ring, no spin,
/// muted blue-gray label -- not grayed-out text on the same surface"), not
/// the enabled recipe dimmed by opacity -- a dimmed-but-still-spinning ring
/// read as broken/loading, not "not ready yet".
struct CTAPillButton: View {
    let title: LocalizedStringKey
    var icon: Image? = nil
    var isEnabled: Bool = true
    var action: () -> Void = {}

    @State private var spinAngle: Angle = .zero

    var body: some View {
        Button(action: action) {
            Group {
                if isEnabled { enabledLabel } else { disabledLabel }
            }
            .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onAppear { startSpinIfNeeded() }
        .onChange(of: isEnabled) { _, newValue in
            if newValue {
                startSpinIfNeeded()
            } else {
                // Reset (no animation) so the next enable can animate
                // 0->360 again -- reassigning the same terminal angle is a
                // no-op and would otherwise leave the ring frozen forever
                // after the first disable/enable cycle.
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { spinAngle = .zero }
            }
        }
    }

    /// Skipped under XCTest (unit/snapshot/UI all set this) -- a continuous
    /// rotation makes every snapshot capture nondeterministic (whatever
    /// angle the ring happens to be at when the test harness grabs the
    /// frame), which reads as a random pixel diff in every screen that has
    /// a primary CTA, not a real visual regression.
    private func startSpinIfNeeded() {
        guard isEnabled, ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        withAnimation(.somaSpin) { spinAngle = .degrees(360) }
    }

    private var enabledLabel: some View {
        labelContent(color: SomaTokens.accent)
            .shadow(color: .white.opacity(0.5), radius: 0.5, x: 0, y: 1)
            .padding(.vertical, 16)
            .background(labelPill)
            .padding(1.5)                        // the 1.5px energy gap
            .background(energyLayer.allowsHitTesting(false)) // directly behind label
            .background(Capsule().fill(Color.white.opacity(0.35))) // base
            .clipShape(Capsule())                // = overflow:hidden
            .shadow(color: SomaTokens.accent.opacity(0.16), radius: 12, x: 0, y: 10)
            .shadow(color: SomaTokens.accent.opacity(0.10), radius: 3, x: 0, y: 2)
    }

    /// Flat, static -- no gradient sheen, no energy ring, muted text on a
    /// plain translucent fill (8b's disabled recipe, not a faded copy of
    /// the active one).
    private var disabledLabel: some View {
        labelContent(color: Color(red: 169 / 255, green: 180 / 255, blue: 206 / 255))
            .padding(.vertical, 16)
            .background(Capsule().fill(Color.white.opacity(0.45)))
            .padding(1.5)
            .background(Capsule().fill(Color.white.opacity(0.3)))
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Color(red: 120 / 255, green: 150 / 255, blue: 220 / 255).opacity(0.12), lineWidth: 1))
    }

    private func labelContent(color: Color) -> some View {
        HStack(spacing: 8) {
            icon?.resizable().aspectRatio(contentMode: .fit).frame(width: 17, height: 17)
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(color)
        .frame(maxWidth: .infinity)
    }

    private var labelPill: some View {
        let shape = Capsule()
        return shape
            .fill(.ultraThinMaterial)
            .overlay(shape.fill(LinearGradient(
                colors: [
                    Color(red: 238 / 255, green: 243 / 255, blue: 255 / 255).opacity(0.95),
                    Color(red: 224 / 255, green: 233 / 255, blue: 254 / 255).opacity(0.92)
                ],
                startPoint: .top, endPoint: .bottom)))
            // Bright strip hugging the inner pill's top rim.
            .overlay(
                shape.strokeBorder(
                    LinearGradient(stops: [.init(color: .white.opacity(0.8), location: 0),
                                           .init(color: .white.opacity(0), location: 0.35)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1.5)
                    .allowsHitTesting(false))
            // Soft blue pooling at the bottom third.
            .overlay(
                shape.fill(LinearGradient(stops: [.init(color: SomaTokens.accent.opacity(0), location: 0.55),
                                                  .init(color: SomaTokens.accent.opacity(0.1), location: 1)],
                                          startPoint: .top, endPoint: .bottom))
                    .padding(1)
                    .allowsHitTesting(false))
    }

    /// The SQUARE spinning layer (css .cta-pill-spin): a 600pt conic sheet
    /// centered on the button; the clipShape above crops it to the pill, so
    /// the bright 40–70° slice reads as a highlight TRAVELING along the rim.
    /// Rotate THIS, never a capsule stroke.
    private var energyLayer: some View {
        AngularGradient(
            stops: [
                .init(color: SomaTokens.accent.opacity(0), location: 0),
                .init(color: Color(red: 140 / 255, green: 175 / 255, blue: 255 / 255).opacity(0.95), location: 0.11),
                .init(color: SomaTokens.accent.opacity(0.5), location: 0.19),
                .init(color: SomaTokens.accent.opacity(0), location: 0.31),
                .init(color: SomaTokens.accent.opacity(0), location: 1)
            ],
            center: .center
        )
        .frame(width: 600, height: 600)     // a background may overflow its
        .rotationEffect(spinAngle)          // view -- sizing stays content-driven,
                                            // the clipShape crops the rest
    }
}

#Preview {
    VStack(spacing: 16) {
        CTAPillButton(title: "Start workout") {}
        CTAPillButton(title: "Continue", isEnabled: false) {}
    }
    .padding(20)
    .somaBackground()
}
