import FirebaseAnalytics
import Foundation
import PostHog

/// Single, strongly-typed entry point for all analytics events -- fans
/// each one out to both Google Analytics for Firebase (GA4) and PostHog.
/// Every call site should go through one of the methods below -- never
/// call `Analytics.logEvent` or `PostHogSDK.shared.capture` directly
/// elsewhere in the app -- so event names/parameter keys are defined
/// exactly once and can't drift or typo across call sites, and adding a
/// third backend later is a one-line change in `log(_:parameters:)`
/// rather than a sweep across every call site.
final class AnalyticsManager {
    static let shared = AnalyticsManager()

    private init() {}

    // MARK: - Lifecycle

    func appOpened() {
        log(.appOpened)
    }

    func onboardingStarted() {
        log(.onboardingStarted)
    }

    func onboardingCompleted() {
        log(.onboardingCompleted)
    }

    // MARK: - Auth

    func signupCompleted() {
        log(.signupCompleted)
    }

    func loginCompleted() {
        log(.loginCompleted)
    }

    // MARK: - Onboarding funnel

    func deviceConnected(provider: String) {
        log(.deviceConnected, parameters: [Parameter.provider: provider])
    }

    func notificationsEnabled() {
        log(.notificationsEnabled)
    }

    // MARK: - Core product usage

    func firstPrompt() {
        log(.firstPrompt)
    }

    /// Also fires `firstPrompt()` exactly once ever, the first time this is
    /// called on a given device -- keeps that one-time bookkeeping inside
    /// the analytics layer itself rather than pushing a "have I done this
    /// before" flag onto every call site.
    func promptSubmitted() {
        if !UserDefaults.standard.bool(forKey: Self.hasSubmittedFirstPromptKey) {
            UserDefaults.standard.set(true, forKey: Self.hasSubmittedFirstPromptKey)
            firstPrompt()
        }
        log(.promptSubmitted)
    }

    func aiResponseReceived() {
        log(.aiResponseReceived)
    }

    func recommendationRequested() {
        log(.recommendationRequested)
    }

    func recommendationGenerated() {
        log(.recommendationGenerated)
    }

    func recommendationFailed() {
        log(.recommendationFailed)
    }

    // MARK: - Referral

    func referralCodeRedeemed(surface: String) {
        log(.referralCodeRedeemed, parameters: [Parameter.surface: surface])
    }

    // MARK: - Monetization

    func paywallViewed() {
        log(.paywallViewed)
    }

    func trialStarted(plan: String) {
        log(.trialStarted, parameters: [Parameter.plan: plan])
    }

    func subscriptionStarted(plan: String) {
        log(.subscriptionStarted, parameters: [Parameter.plan: plan])
    }

    func subscriptionCancelled() {
        log(.subscriptionCancelled)
    }

    /// A `register(placement:)` call errored before it could present --
    /// e.g. the paywall webview failed to load. See SuperwallDiagnostics,
    /// the sole call site for this and `paywallSkipped` below.
    func paywallPresentationFailed(placement: String, error: Error) {
        log(
            .paywallPresentationFailed,
            parameters: [
                Parameter.placement: placement,
                Parameter.errorDescription: String(describing: error),
            ]
        )
    }

    /// A `register(placement:)` call was skipped -- most often because the
    /// placement isn't attached to any campaign on the Superwall dashboard
    /// yet (`PaywallSkippedReason.placementNotFound`), which otherwise
    /// looks identical to "user already has access." See SuperwallDiagnostics.
    func paywallSkipped(placement: String, reason: String) {
        log(.paywallSkipped, parameters: [Parameter.placement: placement, Parameter.reason: reason])
    }

    // MARK: - Generic

    func featureUsed(name: String) {
        log(.featureUsed, parameters: [Parameter.featureName: name])
    }

    // MARK: - Private

    /// Event names shared by both backends -- snake_case, which is both
    /// GA4's and PostHog's own convention -- defined once here rather than
    /// as inline string literals at every call site above.
    private enum Event: String {
        case appOpened = "app_opened"
        case onboardingStarted = "onboarding_started"
        case onboardingCompleted = "onboarding_completed"
        case signupCompleted = "signup_completed"
        case loginCompleted = "login_completed"
        case deviceConnected = "device_connected"
        case notificationsEnabled = "notifications_enabled"
        case firstPrompt = "first_prompt"
        case promptSubmitted = "prompt_submitted"
        case aiResponseReceived = "ai_response_received"
        case recommendationRequested = "recommendation_requested"
        case recommendationGenerated = "recommendation_generated"
        case recommendationFailed = "recommendation_failed"
        case referralCodeRedeemed = "referral_code_redeemed"
        case paywallViewed = "paywall_viewed"
        case trialStarted = "trial_started"
        case subscriptionStarted = "subscription_started"
        case subscriptionCancelled = "subscription_cancelled"
        case paywallPresentationFailed = "paywall_presentation_failed"
        case paywallSkipped = "paywall_skipped"
        case featureUsed = "feature_used"
    }

    private enum Parameter {
        static let plan = "plan"
        static let featureName = "feature_name"
        static let provider = "provider"
        static let surface = "surface"
        static let placement = "placement"
        static let reason = "reason"
        static let errorDescription = "error_description"
    }

    private static let hasSubmittedFirstPromptKey = "com.soma.analytics.hasSubmittedFirstPrompt"

    private func log(_ event: Event, parameters: [String: Any]? = nil) {
        // Debug builds never report analytics (SDKs aren't even configured
        // there, see AppDelegate) -- skip so the console stays quiet too.
        #if !DEBUG
        Analytics.logEvent(event.rawValue, parameters: parameters)
        PostHogSDK.shared.capture(event.rawValue, properties: parameters)
        #endif
    }
}
