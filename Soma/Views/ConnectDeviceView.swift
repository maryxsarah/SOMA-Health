import SwiftUI

/// Screen 2 -- Connect Device.
struct ConnectDeviceView: View {
    @EnvironmentObject private var appState: AppState

    @State private var connecting: Set<Provider> = []
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text(String(localized: "connectDevice.headline", defaultValue: "Connect your devices.", comment: "Connect device screen: headline"))
                    .font(Theme.display)
                Text(String(localized: "connectDevice.body", defaultValue: "Soma plans each day from your body's signals — sleep, HRV and workouts. Connect at least one source to get a tailored plan.", comment: "Connect device screen: explanation of why a device connection is needed"))
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding(.top, 48)
            .padding(.horizontal, 24)

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

            Text(String(localized: "connectDevice.footer", defaultValue: "Add or remove sources anytime in Settings → Health.", comment: "Connect device screen: footer note about changing sources later"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Spacer()

            PillButton(
                title: LocalizedStringKey(String(localized: "connectDevice.cta.continue", defaultValue: "Continue", comment: "Connect device screen: CTA button to proceed to the next onboarding step")),
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
