import SwiftUI

/// The button system from `handoff/css/soma-buttons.css` (guide 00), used
/// only by the five screens that handoff covers -- Home, the week strip,
/// day-detail, the completed-workout screen, and Profile's bottom bar.
/// `PillButton` is untouched and stays in use everywhere else (Onboarding,
/// Paywall, etc. weren't part of this pass).
enum SomaButtonSize {
    case lg, md, sm

    var height: CGFloat {
        switch self {
        case .lg: 52
        case .md: 46
        case .sm: 36
        }
    }

    var radius: CGFloat {
        switch self {
        case .lg: SomaTokens.r2XL
        case .md: SomaTokens.rXL
        case .sm: SomaTokens.rMD
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
    /// Filled accent -- the single most important action on the screen.
    case primary
    /// White, hairline border -- sits directly under a primary.
    case secondary
    /// Destructive, white with danger-colored text (never filled red --
    /// filled red is reserved for the "done" heart).
    case danger
}

/// `:active` is a 0.5pt Y-offset, never a scale (per guide 00 -- "DAW-near").
private struct SomaPressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(y: configuration.isPressed ? 0.5 : 0)
    }
}

/// `.navpill:hover { background: var(--surface-2) }` -- background-only
/// dim while pressed, no Y-offset. Navigation, not an action, so it
/// deliberately doesn't carry the button system's `:active` motion (guide
/// 02, step 4).
struct SomaNavPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct SomaButton: View {
    let title: String
    var size: SomaButtonSize = .lg
    var variant: SomaButtonVariant = .primary
    var isEnabled: Bool = true
    var isBlock: Bool = true
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(size.font)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: isBlock ? .infinity : nil)
                .frame(height: size.height)
                .padding(.horizontal, size.horizontalPadding)
                .foregroundStyle(foregroundColor)
                .background(background)
                .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(SomaPressableStyle())
        .disabled(!isEnabled)
    }

    @ViewBuilder
    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: size.radius, style: .continuous)
        switch variant {
        case .primary:
            shape.fill(SomaTokens.accent)
                // Only the bottom-bar lg primary floats over the scrolling
                // list; an md/sm primary sits inside a card that already
                // carries --sh-raised, so a second shadow would read as a
                // double card (guide 00, step 3).
                .shadow(color: size == .lg ? SomaTokens.accent.opacity(0.22) : .clear, radius: 9, x: 0, y: 6)
        case .secondary:
            shape.fill(SomaTokens.surface)
                .overlay(shape.stroke(SomaTokens.hairline, lineWidth: 1))
        case .danger:
            shape.fill(SomaTokens.surface)
                .overlay(shape.stroke(SomaTokens.hairline, lineWidth: 1))
        }
    }

    private var foregroundColor: Color {
        switch variant {
        case .primary: .white
        case .secondary: SomaTokens.accent
        case .danger: SomaTokens.danger
        }
    }
}

/// 36×36 icon-only control, accent-soft plate + accent glyph. Always needs
/// an accessibility label since there's no visible text.
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
                .background(
                    RoundedRectangle(cornerRadius: SomaTokens.rMD, style: .continuous)
                        .fill(SomaTokens.accentSoft)
                )
        }
        .buttonStyle(SomaPressableStyle())
        .accessibilityLabel(accessibilityLabel)
    }
}

/// Selectable pill -- goal chips, "how it felt" chips, etc. Selection is
/// carried by BOTH a 2pt accent border and the accent-soft fill, never fill
/// alone (guide 00, step 5); padding drops 1pt when selected so the box
/// size doesn't jump.
struct SomaChip: View {
    let title: String
    var isSelected: Bool = false
    /// Dashed border for a one-off (unsaved) thing -- `.chip--oneoff`.
    var isOneOff: Bool = false
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(isSelected ? SomaTokens.accent : Color(red: 0.353, green: 0.353, blue: 0.4))
                .padding(.horizontal, isSelected ? 10 : 11)
                .padding(.vertical, isSelected ? 5 : 6)
                .frame(minHeight: 34)
                .background(
                    Capsule().fill(isSelected ? SomaTokens.accentSoft : SomaTokens.surface)
                )
                .overlay(
                    Capsule().strokeBorder(
                        isSelected ? SomaTokens.accent : SomaTokens.hairline,
                        style: StrokeStyle(lineWidth: isSelected ? 2 : 1, dash: isOneOff ? [4, 3] : [])
                    )
                )
        }
        .buttonStyle(.plain)
    }
}

/// Profile's 3-tab control (`.seg`/`.seg__item`) -- the selected item gets
/// a white pill with `--sh-tab`, replacing the plain `Picker(.segmented)`.
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
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? SomaTokens.ink : SomaTokens.ink3)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(isSelected ? SomaTokens.surface : .clear)
                                .somaTabShadow()
                                .opacity(isSelected ? 1 : 0)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: SomaTokens.rLG, style: .continuous)
                .fill(SomaTokens.surface4)
        )
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
}
