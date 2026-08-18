import SwiftUI

/// Soma Glass recipe for text entry (Soma Refresh.dc.html 4d/6c: rgba(255,
/// 255,255,0.5) fill, 1px white 0.85 ring, blur, r22, 14.5pt text,
/// #B0B0BC placeholder). Every free-text input in the app wraps in
/// `.glassInput()` instead of the system `.textFieldStyle(.roundedBorder)`
/// -- plain white square-cornered fields with no ring or glass.
private struct GlassInputModifier: ViewModifier {
    var cornerRadius: CGFloat
    var focused: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .font(.system(size: 14.5))
            .foregroundStyle(SomaTokens.ink)
            .tint(SomaTokens.accent)
            .padding(.init(top: 14, leading: 16, bottom: 14, trailing: 16))
            .background {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay(shape.fill(Color.white.opacity(0.5)))
                    .overlay(shape.strokeBorder(Color.white.opacity(0.85), lineWidth: 1))
                    // Focus: hairline warms up to the accent -- same move as
                    // the selected sport-type card, never a harsh system ring.
                    .overlay(shape.strokeBorder(SomaTokens.accent.opacity(focused ? 0.35 : 0), lineWidth: 1.5))
                    .shadow(
                        color: SomaTokens.accent.opacity(focused ? 0.12 : 0),
                        radius: focused ? 8 : 0, x: 0, y: 3
                    )
            }
            .animation(.easeInOut(duration: 0.16), value: focused)
    }
}

extension View {
    /// Soma Glass text-entry surface. Apply directly to a `TextField`.
    /// Pass the field's `@FocusState` so the ring lights up on focus.
    func glassInput(cornerRadius: CGFloat = 22, focused: Bool = false) -> some View {
        modifier(GlassInputModifier(cornerRadius: cornerRadius, focused: focused))
    }
}

/// Single-line + multiline convenience wrapper with the placeholder color
/// the system TextField can't set (#B0B0BC = SomaTokens.inkPlaceholder).
struct GlassTextField: View {
    let placeholder: String
    @Binding var text: String
    /// nil = single line; a value = multiline with that minimum line count.
    var minLines: Int? = nil

    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(
            "",
            text: $text,
            prompt: Text(placeholder).foregroundStyle(SomaTokens.inkPlaceholder),
            axis: minLines == nil ? .horizontal : .vertical
        )
        .lineLimit((minLines ?? 1)...max(minLines ?? 1, 6))
        .focused($isFocused)
        .glassInput(focused: isFocused)
    }
}
