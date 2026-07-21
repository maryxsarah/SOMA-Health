import SwiftUI

/// One row on Screen 2 (Connect Device): provider name, connection
/// status, and a Connect/Connected pill button.
struct ProviderCardView: View {
    let provider: Provider
    let isConnected: Bool
    let isConnecting: Bool
    let action: () -> Void

    var body: some View {
        CardView {
            HStack(spacing: 16) {
                Image(systemName: provider.systemImageName)
                    .font(.title2)
                    .foregroundStyle(Theme.pillFill)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.displayName)
                        .font(.body.bold())
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !provider.isAvailable {
                    Text("Coming Soon")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .frame(width: 130)
                        .background(Capsule().fill(Color(.systemGray6)))
                } else if isConnecting {
                    ProgressView()
                        .frame(width: 130)
                } else {
                    PillButton(
                        title: "Connect",
                        style: isConnected ? .connected : .primary,
                        action: action
                    )
                    .frame(width: 130)
                }
            }
        }
    }

    private var statusText: String {
        if !provider.isAvailable { return "Coming soon" }
        return isConnected ? "Connected" : "Not connected"
    }
}
