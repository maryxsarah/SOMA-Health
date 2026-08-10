import Foundation
import SuperwallKit

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

    /// Providers whose stored refresh token failed server-side (revoked,
    /// expired) -- distinct from `connectedProviders`, which is a local
    /// cache set once at connect time and has no way to learn this on its
    /// own. Not persisted: always re-fetched fresh via
    /// SupabaseClient.fetchConnectionStatus() (see ProfileView), so it
    /// can never show a stale "needs reconnect" state after the user has
    /// already fixed it.
    @Published var providersNeedingReconnect: Set<Provider> = []

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
        // Fire-and-forget: Whoop/Oura tokens are a persistent per-user
        // server table and HealthKit's grant is an OS-level install
        // permission -- neither is affected by a prior sign-out (see
        // signOut's own doc comment) -- so a returning user's real
        // connections should already show as connected by the time they
        // reach Connect Device, without blocking this screen transition
        // on the network round trip. See refreshConnectedProviders.
        Task { await refreshConnectedProviders() }
    }

    /// Server-verified refresh of `connectedProviders`/`providersNeedingReconnect`
    /// -- the fix for a real bug: `connectedProviders` was a local cache
    /// written once at connect time and wiped by signOut() below, with
    /// nothing on the next sign-in ever re-deriving it from the real
    /// source of truth. That made every returning user's already-connected
    /// Whoop/Oura/HealthKit look disconnected on Connect Device, even
    /// though nothing about the actual connection had changed --
    /// Whoop/Oura tokens live in wearable_tokens (a persistent per-user
    /// server table, confirmed in generate-recommendation/index.ts) and
    /// HealthKit's authorization is an OS-level install grant this app's
    /// sign-out can't touch even if it wanted to.
    ///
    /// Called on every sign-in (markSignedIn) and defensively again
    /// whenever Connect Device or Profile's device rows appear, so this
    /// is never stale regardless of which screen the user lands on.
    func refreshConnectedProviders() async {
        async let statusFetch: SupabaseClient.ConnectionStatus? = try? await SupabaseClient.shared.fetchConnectionStatus()
        async let healthKitAuthorized: Bool = {
            guard HealthKitManager.isAvailable else { return false }
            return await HealthKitManager.shared.isAuthorized()
        }()

        var connected: Set<Provider> = []
        var needingReconnect: Set<Provider> = []

        if let status = await statusFetch {
            if status.whoop.connected { connected.insert(.whoop) }
            if status.whoop.needsReconnect { needingReconnect.insert(.whoop) }
            if status.oura.connected { connected.insert(.oura) }
            if status.oura.needsReconnect { needingReconnect.insert(.oura) }
        } else {
            // A failed fetch (network blip) must never erase a Whoop/Oura
            // connection this app already believed in -- only a
            // successful, authoritative read is allowed to remove one.
            connected.formUnion(connectedProviders.intersection([.whoop, .oura]))
        }

        if await healthKitAuthorized {
            connected.insert(.appleHealth)
        }

        connectedProviders = connected
        UserDefaults.standard.set(connected.map(\.rawValue), forKey: Self.connectedProvidersKey)
        providersNeedingReconnect = needingReconnect
    }

    func markProviderConnected(_ provider: Provider) {
        connectedProviders.insert(provider)
        UserDefaults.standard.set(connectedProviders.map(\.rawValue), forKey: Self.connectedProvidersKey)
        // A fresh connect always clears any prior reconnect flag server-
        // side (see store-wearable-token) -- mirror that immediately
        // instead of waiting for the next fetchConnectionStatus() call.
        providersNeedingReconnect.remove(provider)
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
        AnalyticsManager.shared.onboardingCompleted()
    }

    /// Refreshes the referral bonus expiry from Supabase. Called on Home
    /// appear and again after a successful redemption on the paywall.
    func refreshReferralBonus() async {
        guard let userId = SupabaseClient.shared.currentUserID else { return }
        referralBonusUntil = try? await SupabaseClient.shared.fetchReferralBonusUntil(id: userId)
        // Scheduling here (rather than only at the Paywall's own redeem
        // call site) means the onboarding-step redemption path
        // (ReferralCodeEntryStepView, via PostSetupFlowView's onRedeemed)
        // gets the reminder too, without duplicating the offset math.
        if let bonusUntil = referralBonusUntil {
            await NotificationManager.shared.scheduleUpgradeReminder(bonusUntil: bonusUntil)
        }
    }

    /// Clears the local session and resets onboarding state so the app
    /// falls straight back to Onboarding -- lets the full signup flow be
    /// re-tested in the same running app, without reinstalling.
    ///
    /// Wiping `connectedProviders`/its UserDefaults mirror here is safe,
    /// NOT a connection loss: `SupabaseClient.shared.signOut()` only
    /// clears the local Supabase session keychain entry -- it never
    /// touches `wearable_tokens` (a persistent per-user server table) or
    /// calls any HealthKit API, so Whoop/Oura/HealthKit all remain
    /// genuinely connected server/OS-side. This is just the CLIENT's
    /// cache of that fact being cleared; refreshConnectedProviders()
    /// (called from markSignedIn on the next sign-in) re-derives the real
    /// state from wearable_tokens and HKHealthStore rather than ever
    /// re-inferring it from this now-empty cache.
    func signOut() {
        SupabaseClient.shared.signOut()
        Superwall.shared.reset()
        onboardingComplete = false
        connectedProviders = []
        providersNeedingReconnect = []
        currentRecommendation = nil
        referralBonusUntil = nil
        UserDefaults.standard.removeObject(forKey: Self.onboardingCompleteKey)
        UserDefaults.standard.removeObject(forKey: Self.connectedProvidersKey)
        screen = .onboarding
    }
}
