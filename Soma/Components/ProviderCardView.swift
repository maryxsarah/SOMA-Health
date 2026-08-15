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
                    .font(.body)
                    .foregroundStyle(isConnected ? SomaTokens.success : SomaTokens.accent)
                    .frame(width: 40, height: 40)
                    .glassLens(cornerRadius: SomaTokens.rPill)

                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.displayName)
                        .font(.body.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    statusView
                }

                Spacer()

                if !provider.isAvailable {
                    Text("provider.status.comingSoon")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .frame(width: 130)
                        .glassLens()
                } else if isConnecting {
                    ProgressView()
                        .frame(width: 130)
                } else if isConnected {
                    // Quiets to plain text once connected -- the animated
                    // ring CTA is a one-per-screen thing (the bottom
                    // Continue button already is it); every provider row
                    // spinning its own "Connect" pill at once was the bug.
                    Text(Self.manageText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Button(action: action) {
                        Text("Connect")
                            .font(.subheadline.bold())
                            .foregroundStyle(SomaTokens.accent)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .frame(width: 130)
                            .glassLens()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: SomaTokens.rCard, style: .continuous)
                .strokeBorder(isConnected ? SomaTokens.success.opacity(0.22) : Color.clear, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var statusView: some View {
        if !provider.isAvailable {
            Text("provider.status.comingSoon")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if isConnected {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                Text(Self.connectedSyncingText)
            }
            .font(.caption)
            .foregroundStyle(SomaTokens.success)
        } else {
            Text(provider.benefitDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private static let manageText = String(
        localized: "provider.manage",
        defaultValue: "Manage",
        comment: "Connect Device screen: trailing label on a row for a provider that's already connected, opens management for it"
    )

    private static let connectedSyncingText = String(
        localized: "provider.status.connectedSyncing",
        defaultValue: "Connected · syncing…",
        comment: "Connect Device screen: status line under a provider name once it's connected"
    )
}
