import SwiftUI

/// Screen 2 -- Connect Device.
struct ConnectDeviceView: View {
    @EnvironmentObject private var appState: AppState

    @State private var connecting: Set<Provider> = []
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("Connect your devices.")
                    .font(Theme.display)
                Text("Connect at least one to get started.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding(.top, 48)

            VStack(spacing: 16) {
                ForEach(Provider.allCases) { provider in
                    ProviderCardView(
                        provider: provider,
                        isConnected: appState.connectedProviders.contains(provider),
                        isConnecting: connecting.contains(provider),
                        action: { connect(provider) }
                    )
                }
            }
            .padding(.horizontal, 20)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Spacer()

            PillButton(
                title: "Continue",
                isEnabled: !appState.connectedProviders.isEmpty
            ) {
                appState.advanceToNotifications()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .somaBackground()
        // Belt-and-suspenders alongside markSignedIn's own fire-and-forget
        // call -- guarantees this screen always shows the real,
        // server/OS-verified state (a provider connected in an earlier
        // session, before this sign-out, still shows Connected) no matter
        // which path led here. See AppState.refreshConnectedProviders.
        .task {
            await appState.refreshConnectedProviders()
        }
    }

    private func connect(_ provider: Provider) {
        guard !connecting.contains(provider) else { return }
        connecting.insert(provider)
        errorMessage = nil

        Task {
            defer { connecting.remove(provider) }
            do {
                switch provider {
                case .appleHealth:
                    try await HealthKitManager.shared.requestAuthorization()
                case .whoop:
                    try await WhoopOAuthManager.shared.connect()
                    Task { await SupabaseClient.shared.backfillRecentHistory() }
                case .oura:
                    try await OuraOAuthManager.shared.connect()
                    Task { await SupabaseClient.shared.backfillRecentHistory() }
                }
                appState.markProviderConnected(provider)
                AnalyticsManager.shared.deviceConnected(provider: provider.rawValue)
            } catch {
                errorMessage = String(
                    localized: "connectDevice.error",
                    defaultValue: "Couldn't connect \(provider.displayName): \(error.localizedDescription)",
                    comment: "Error shown when connecting a health/wearable provider fails; first placeholder is the provider name, second is the underlying error description"
                )
            }
        }
    }
}

#Preview {
    ConnectDeviceView()
        .environmentObject(AppState())
}
