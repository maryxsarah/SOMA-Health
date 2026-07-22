import Foundation

/// Exactly the 4 screens in the spec -- no tab bar, no chat, no extra
/// screens.
enum AppScreen {
    case onboarding
    case survey
    case connectDevice
    case notifications
    case postSetup
    case home
}

@MainActor
final class AppState: ObservableObject {
    // `screen` is a stored, manually-advanced value rather than derived
    // from `connectedProviders` -- deriving it would auto-navigate away
    // from Connect Device the instant the FIRST provider connects, before
    // the user taps "Continue" (which the spec requires as the gate).
    @Published var screen: AppScreen
    @Published var connectedProviders: Set<Provider>
    @Published var onboardingComplete: Bool
    @Published var currentRecommendation: DailyRecommendation?

    /// Referral-code bonus expiry, if any -- additive to (not a substitute
    /// for) an active StoreKit subscription. `nil` or in the past means no
    /// bonus is active. Combined with SubscriptionManager.isSubscribed by
    /// views to decide whether to show the paywall.
    @Published var referralBonusUntil: Date?

    private static let onboardingCompleteKey = "com.soma.app.onboardingComplete"
    private static let connectedProvidersKey = "com.soma.app.connectedProviders"

    init() {
        let signedIn = SupabaseClient.shared.isSignedIn
        let complete = UserDefaults.standard.bool(forKey: Self.onboardingCompleteKey)
        onboardingComplete = complete

        // Persisted (not just in-memory) so Profile's "Connect more
        // devices" section shows accurate status across app relaunches,
        // not only during the single onboarding session.
        let storedProviders = UserDefaults.standard.stringArray(forKey: Self.connectedProvidersKey) ?? []
        connectedProviders = Set(storedProviders.compactMap(Provider.init(rawValue:)))

        if !signedIn {
            screen = .onboarding
        } else if complete {
            screen = .home
        } else {
            // Signed in but never finished onboarding (e.g. app was
            // killed mid-flow) -- simplest correct resumption for V1 is
            // to restart at Connect Device rather than track finer-
            // grained progress.
            screen = .connectDevice
        }
    }

    func markSignedIn() {
        screen = .survey
    }

    func markProviderConnected(_ provider: Provider) {
        connectedProviders.insert(provider)
        UserDefaults.standard.set(connectedProviders.map(\.rawValue), forKey: Self.connectedProvidersKey)
    }

    func advanceToNotifications() {
        screen = .notifications
    }

    func advanceToPostSetup() {
        screen = .postSetup
    }

    func markOnboardingComplete() {
        onboardingComplete = true
        UserDefaults.standard.set(true, forKey: Self.onboardingCompleteKey)
        screen = .home
    }

    /// Refreshes the referral bonus expiry from Supabase. Called on Home
    /// appear and again after a successful redemption on the paywall.
    func refreshReferralBonus() async {
        guard let userId = SupabaseClient.shared.currentUserID else { return }
        referralBonusUntil = try? await SupabaseClient.shared.fetchReferralBonusUntil(id: userId)
    }

    /// Clears the local session and resets onboarding state so the app
    /// falls straight back to Onboarding -- lets the full signup flow be
    /// re-tested in the same running app, without reinstalling.
    func signOut() {
        SupabaseClient.shared.signOut()
        onboardingComplete = false
        connectedProviders = []
        currentRecommendation = nil
        referralBonusUntil = nil
        UserDefaults.standard.removeObject(forKey: Self.onboardingCompleteKey)
        UserDefaults.standard.removeObject(forKey: Self.connectedProvidersKey)
        screen = .onboarding
    }
}
