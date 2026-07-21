import SwiftUI

enum PillButtonStyle {
    case primary
    /// Disabled, shows a checkmark and "Connected" -- used once a
    /// provider's Connect button succeeds.
    case connected
}

/// Dark blue filled pill/capsule with bold white text, per spec. Covers
/// both the flow buttons ("Get Started", "Continue", "Finish Setup") and
/// the provider "Connect" -> "Connected" transition in one component.
struct PillButton: View {
    let title: String
    var style: PillButtonStyle = .primary
    var isEnabled: Bool = true
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if style == .connected {
                    Image(systemName: "checkmark")
                }
                Text(style == .connected ? "Connected" : title)
                    .font(.body.bold())
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                Capsule().fill(Theme.pillFill.opacity(effectivelyEnabled ? 1.0 : 0.4))
            )
        }
        .disabled(!effectivelyEnabled)
    }

    private var effectivelyEnabled: Bool {
        style != .connected && isEnabled
    }
}

#Preview {
    VStack(spacing: 16) {
        PillButton(title: "Get Started") {}
        PillButton(title: "Continue", isEnabled: false) {}
        PillButton(title: "Connect", style: .connected) {}
    }
    .padding()
}
