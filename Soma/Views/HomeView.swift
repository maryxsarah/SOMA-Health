import SwiftUI

/// Screen 4 -- Home. No text input, no chat history, no voice button.
struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var subscriptionManager: SubscriptionManager

    @State private var orbState: OrbState = .idle
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showDetail = false
    @State private var showProfile = false
    @State private var showPaywall = false

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 8)

                OrbView(state: orbState)

                Group {
                    if let recommendation = appState.currentRecommendation {
                        recommendationCard(recommendation)
                    } else {
                        needsDataCard
                    }
                }
                .padding(.horizontal, 20)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 40)
        }
        .somaBackground()
        .safeAreaInset(edge: .top) {
            HStack {
                Spacer()
                Button {
                    showProfile = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.title3)
                        .foregroundStyle(Theme.pillFill)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .task {
            await loadTodaysRecommendation()
            await appState.refreshReferralBonus()
        }
        .refreshable {
            await checkNow()
        }
        .sheet(isPresented: $showDetail) {
            if let recommendation = appState.currentRecommendation {
                RecommendationDetailView(recommendation: recommendation)
            }
        }
        .sheet(isPresented: $showProfile) {
            ProfileView()
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    /// The Home card (today's category + message) always stays free --
    /// only the tap-through detail (step target, workout suggestions, why
    /// explanation) requires an active subscription or referral bonus.
    private var hasDetailAccess: Bool {
        if subscriptionManager.isSubscribed { return true }
        if let until = appState.referralBonusUntil, until > Date() { return true }
        return false
    }

    private func recommendationCard(_ recommendation: DailyRecommendation) -> some View {
        Button {
            if hasDetailAccess {
                showDetail = true
            } else {
                showPaywall = true
            }
        } label: {
            CardView {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(recommendation.category.displayTitle)
                            .font(Theme.display)
                        Text(recommendation.message)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var needsDataCard: some View {
        CardView {
            Text("Soma needs today's data")
                .font(.body.bold())
            Text("Pull to refresh, or check now.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            PillButton(title: "Check now", isEnabled: !isLoading) {
                Task { await checkNow() }
            }
        }
    }

    /// Plain read on appear -- does NOT invoke the mutating function, so
    /// opening the app doesn't generate a new recommendation every time.
    private func loadTodaysRecommendation() async {
        do {
            if let recommendation = try await SupabaseClient.shared.fetchTodaysRecommendation(date: Self.todayDateString()) {
                appState.currentRecommendation = recommendation
            }
        } catch {
            // Falls through to the "needs data" card -- covers the "zero
            // daily_snapshot / no recommendation yet" no-crash case.
        }
    }

    /// Manual fallback ("Check now" / pull-to-refresh) -- calls the same
    /// Edge Function the automated morning triggers use.
    private func checkNow() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let snapshot = HealthKitManager.isAvailable
                ? await HealthKitManager.shared.fetchTodaysMetrics()
                : nil
            let recommendation = try await SupabaseClient.shared.invokeGenerateRecommendation(
                date: Self.todayDateString(),
                healthkit: snapshot
            )
            appState.currentRecommendation = recommendation
            NotificationManager.shared.markSentToday()
            triggerNewMessagePulse()
        } catch {
            // Covers "expired wearable token" / "zero connected devices" --
            // show a clear message instead of crashing.
            errorMessage = "Couldn't fetch today's data. Reconnect a device or try again."
        }
    }

    private func triggerNewMessagePulse() {
        orbState = .newMessage
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            orbState = .idle
        }
    }

    private static func todayDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: Date())
    }
}

#Preview {
    HomeView()
        .environmentObject(AppState())
        .environmentObject(SubscriptionManager.shared)
}
