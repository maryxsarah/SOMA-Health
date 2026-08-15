import SwiftUI

/// The Soma Glass button/chip/tab family (`soma-glass-tokens.css` §"MATERIAL
/// RECIPES"). Every control here is lens (raised, unselected) or gel
/// (filled, selected) -- never animated; the spinning CTA pill lives in
/// `CTAPillButton.swift` and is reserved for a screen's single primary
/// action.
enum SomaButtonSize {
    case lg, md, sm

    var height: CGFloat {
        switch self {
        case .lg: 52
        case .md: 46
        case .sm: 36
        }
    }

    var font: Font {
        switch self {
        case .lg: .system(size: 16.5, weight: .semibold)
        case .md: .system(size: 15, weight: .semibold)
        case .sm: .system(size: 13.5, weight: .semibold)
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .lg: 20
        case .md: 18
        case .sm: 14
        }
    }
}

enum SomaButtonVariant {
    /// Filled accent gel -- the single most important action on the screen.
    case primary
    /// Lens, unselected/secondary -- sits directly under a primary.
    case secondary
    /// Destructive lens, danger-colored text.
    case danger
}

/// A gentle opacity dim while pressed -- no Y-offset/scale, so a floating
/// glass surface doesn't look like it's sinking on tap.
private struct SomaPressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// `.navpill:hover { background: var(--surface-2) }` -- background-only
/// dim while pressed. Navigation, not an action, so it deliberately
/// doesn't carry any other press motion.
struct SomaNavPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct SomaButton: View {
    let title: LocalizedStringKey
    var size: SomaButtonSize = .lg
    var variant: SomaButtonVariant = .primary
    var isEnabled: Bool = true
    var isBlock: Bool = true
    var action: () -> Void = {}

    var body: some View {
        // The lg/block/primary combination is a screen's single hero CTA --
        // give it the signature spinning glass pill. Every other primary
        // (inline, md/sm) stays a static gel fill.
        if variant == .primary, size == .lg, isBlock {
            CTAPillButton(title: title, isEnabled: isEnabled, action: action)
        } else {
            Button(action: action) {
                Text(title)
                    .font(size.font)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: isBlock ? .infinity : nil)
                    .frame(height: size.height)
                    .padding(.horizontal, size.horizontalPadding)
                    .modifier(SomaButtonMaterial(variant: variant))
                    .opacity(isEnabled ? 1 : 0.45)
            }
            .buttonStyle(SomaPressableStyle())
            .disabled(!isEnabled)
        }
    }
}

private struct SomaButtonMaterial: ViewModifier {
    let variant: SomaButtonVariant

    func body(content: Content) -> some View {
        switch variant {
        case .primary:
            content.foregroundStyle(.white).glassGel(.blue)
        case .secondary:
            content.foregroundStyle(SomaTokens.accent).glassLens()
        case .danger:
            content.glassGel(.red)
        }
    }
}

/// 36×36 icon-only control, glass lens + accent glyph. Always needs an
/// accessibility label since there's no visible text.
struct SomaIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SomaTokens.accent)
                .frame(width: 36, height: 36)
                .glassLens(cornerRadius: SomaTokens.rMD)
        }
        .buttonStyle(SomaPressableStyle())
        .accessibilityLabel(accessibilityLabel)
    }
}

/// Selectable pill -- goal chips, "how it felt" chips, etc. Selected =
/// gel fill, unselected = lens; padding drops 1pt when selected so the
/// box size doesn't jump.
struct SomaChip: View {
    let title: LocalizedStringKey
    var isSelected: Bool = false
    /// Dashed border for a one-off (unsaved) thing -- `.chip--oneoff`.
    var isOneOff: Bool = false
    /// Trailing xmark glyph marking "tap removes this" -- needed wherever a
    /// tap deletes rather than selects, since isSelected:true's blue-gel
    /// fill otherwise reads as "this is the picked value" (its meaning
    /// everywhere else this chip is used).
    var showsRemoveIcon: Bool = false
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                if showsRemoveIcon {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                }
            }
            .padding(.horizontal, isSelected ? 10 : 11)
            .padding(.vertical, isSelected ? 5 : 6)
            .frame(minHeight: 34)
            .modifier(SomaChipMaterial(isSelected: isSelected, isOneOff: isOneOff))
        }
        .buttonStyle(.plain)
    }
}

private struct SomaChipMaterial: ViewModifier {
    let isSelected: Bool
    let isOneOff: Bool

    func body(content: Content) -> some View {
        if isSelected {
            content.foregroundStyle(.white).glassGel(.blue)
        } else {
            content
                .foregroundStyle(SomaTokens.ink2)
                .glassLens()
                .overlay(
                    Capsule().strokeBorder(
                        SomaTokens.hairline,
                        style: StrokeStyle(lineWidth: 1, dash: isOneOff ? [4, 3] : [])
                    )
                )
        }
    }
}

/// Glass segmented control (`.seg`/`.seg__item`) -- the selected item gets
/// a raised white chip with accent text, replacing the plain
/// `Picker(.segmented)`. Used by EmailAuthView's sign-in/sign-up tabs.
struct SomaSegmentedControl<T: Hashable & CaseIterable & Identifiable>: View where T.AllCases: RandomAccessCollection {
    @Binding var selection: T
    let title: (T) -> String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(T.allCases) { item in
                let isSelected = item == selection
                Button {
                    selection = item
                } label: {
                    Text(title(item))
                        .font(.system(size: 13, weight: isSelected ? .bold : .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .foregroundStyle(isSelected ? SomaTokens.accent : SomaTokens.ink3)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(Color.white.opacity(0.85))
                                    .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .glassCardFlat(cornerRadius: SomaTokens.rPill)
    }
}

#Preview {
    VStack(spacing: 16) {
        SomaButton(title: "Start workout", size: .lg, variant: .primary) {}
        SomaButton(title: "Swap workout", size: .md, variant: .secondary) {}
        SomaButton(title: "Sign out", size: .md, variant: .danger) {}
        HStack {
            SomaChip(title: "Easy", isSelected: true) {}
            SomaChip(title: "Hard but good") {}
            SomaChip(title: "Too much") {}
        }
        SomaIconButton(systemImage: "arrow.clockwise", accessibilityLabel: "Rescan") {}
    }
    .padding()
    .somaBackground()
}
