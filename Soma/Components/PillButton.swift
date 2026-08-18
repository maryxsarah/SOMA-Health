import SwiftUI

enum PillButtonStyle {
    case primary
    /// Disabled, shows a checkmark and "Connected" -- used once a
    /// provider's Connect button succeeds.
    case connected
}

/// The app-wide primary CTA. `.primary` renders as the signature spinning
/// glass pill (`CTAPillButton`, per `soma-glass-tokens.css` -- the only
/// animated button in the system). `.connected` is a static done-state
/// pill and is never animated.
struct PillButton: View {
    let title: LocalizedStringKey
    var icon: Image? = nil
    var style: PillButtonStyle = .primary
    var isEnabled: Bool = true
    var action: () -> Void = {}

    var body: some View {
        switch style {
        case .primary:
            CTAPillButton(title: title, icon: icon, isEnabled: isEnabled, action: action)
        case .connected:
            Button(action: action) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                    Text(String(localized: "pillButton.connected", defaultValue: "Connected", comment: "Pill button label shown in the disabled 'connected' state"))
                        .font(.body.bold())
                }
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .glassGel(.blue)
                .opacity(0.55)
            }
            .disabled(true)
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        PillButton(title: "Get Started") {}
        PillButton(title: "Continue", isEnabled: false) {}
        PillButton(title: "Connect", style: .connected) {}
    }
    .padding()
    .somaBackground()
}
