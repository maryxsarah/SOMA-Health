import SwiftUI

/// The disclosure from guide 09 -- the rule behind it: at most two lines of
/// explanatory prose visible at rest, anything longer collapses. Trigger is
/// an accent label + a chevron that rotates 180° over 140ms (the only thing
/// that animates); the body sits on surface-3 so it reads as a quote, never
/// as a second card. Closed removes the body entirely (no height animation).
struct SomaDisclosure<Content: View, Accessory: View>: View {
    var closedLabel: LocalizedStringKey
    var openLabel: LocalizedStringKey
    /// Leading-aligns the trigger by default; Home's readiness card right-
    /// aligns it under the TODAY pill (guide 09 §1).
    var alignment: HorizontalAlignment
    let content: () -> Content
    /// Optional view sharing the trigger row, right-aligned -- guide 04
    /// pairs "Why this?" with the step tracker pill on one line.
    let triggerAccessory: () -> Accessory

    @State private var isOpen = false

    init(
        closedLabel: LocalizedStringKey = "Why this?",
        openLabel: LocalizedStringKey = "Hide details",
        alignment: HorizontalAlignment = .leading,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder triggerAccessory: @escaping () -> Accessory = { EmptyView() }
    ) {
        self.closedLabel = closedLabel
        self.openLabel = openLabel
        self.alignment = alignment
        self.content = content
        self.triggerAccessory = triggerAccessory
    }

    var body: some View {
        VStack(alignment: alignment, spacing: 8) {
            HStack(alignment: .center) {
                Button {
                    withAnimation(.easeInOut(duration: 0.14)) { isOpen.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Text(isOpen ? openLabel : closedLabel)
                            .font(.system(size: 13, weight: .semibold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .rotationEffect(.degrees(isOpen ? 180 : 0))
                    }
                    .foregroundStyle(SomaTokens.accent)
                }
                .buttonStyle(.plain)

                if Accessory.self != EmptyView.self {
                    Spacer()
                    triggerAccessory()
                }
            }

            if isOpen {
                content()
                    .font(.system(size: 13.5))
                    .lineSpacing(3)
                    .foregroundStyle(SomaTokens.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 13)
                    .padding(.horizontal, 15)
                    .background(
                        RoundedRectangle(cornerRadius: SomaTokens.rXL, style: .continuous)
                            .fill(SomaTokens.surface3)
                    )
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        SomaDisclosure {
            Text("Well recovered — HRV up, resting HR down, 8.5 h of sleep. A good day to go hard.")
        }
    }
    .padding()
}
