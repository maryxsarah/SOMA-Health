import SuperwallKit
import SwiftUI

private enum PostSetupStep: Int {
    case referralCode, loading, consent, planSummary, bodyPhotos, tryFree, trialReminder, paywall
}

/// Runs everything after Notification Enablement and before Home:
/// optional referral code, the plan-generation loading sequence,
/// Terms/Privacy + health-disclaimer + marketing consent, a plan summary,
/// two soft pre-paywall reassurance screens, and finally the paywall
/// itself. Only marks onboarding complete once this entire sequence
/// finishes.
///
/// `.consent` deliberately runs BEFORE `.planSummary` -- it used to come
/// after, which meant PlanSummaryStepView showed the user's actual first
/// real recommendation (category + message) before they had acknowledged
/// the health disclaimer. That's the one legally load-bearing ordering
/// constraint in this whole sequence; don't move `.consent` back down.
struct PostSetupFlowView: View {
    @EnvironmentObject private var appState: AppState

    @State private var step: PostSetupStep = {
        // Fixture shortcut for the onboarding-paywall matrix -- see
        // UITestSupport.postSetupStartStep. Always .referralCode in
        // Release (the accessor is nil there).
        if UITestSupport.postSetupStartStep == "paywall" { return .paywall }
        return .referralCode
    }()
    /// Fails closed (false) until the profile fetch below actually confirms
    /// an 18+ date_of_birth -- an in-flight fetch or a fetch failure must
    /// never show the photo-comparison step to an unconfirmed user.
    @State private var isConfirmedAdultForBodyPhotos = false
    /// Set only on `PaywallPresentationHandler.onError` -- a real
    /// presentation failure (no network, webview failed to load), not a
    /// skip. The SDK deliberately never calls `feature` in this case ("otherwise
    /// turning internet off would give unlimited access" -- its own comment),
    /// so without this the user was stuck on a blank `Color.clear` forever
    /// with no way forward. `.skipped` (no audience match, holdout, etc.)
    /// already calls `feature` on its own and needs no handling here.
    @State private var paywallError: String?

    var body: some View {
        Group {
            switch step {
            case .referralCode:
                ReferralCodeEntryStepView(
                    onSkip: advance,
                    onRedeemed: {
                        Task {
                            await appState.refreshReferralBonus()
                            advance()
                        }
                    }
                )
            case .loading:
                GeneratingPlanStepView(onFinished: advance)
            case .planSummary:
                PlanSummaryStepView(onContinue: advance)
            case .bodyPhotos:
                BodyPhotosStepView(onContinue: advance)
            case .consent:
                SignUpConsentStepView { marketingOptIn in
                    Task { await saveConsent(marketingOptIn: marketingOptIn) }
                    advance()
                }
            case .tryFree:
                TryFreeReassuranceStepView(onContinue: advance)
            case .trialReminder:
                TrialReminderStepView(onContinue: advance)
            case .paywall:
                // Superwall presents its own paywall modally -- there's
                // nothing to render inline here beyond a brief background
                // while that happens. The onboarding paywall assigned to
                // this placement must be configured non-dismissible (no
                // close button) in the Superwall dashboard paywall editor
                // -- that's what used to be `allowsDismissal: false`.
                Group {
                    if let paywallError {
                        paywallErrorContent(paywallError)
                    } else {
                        Color.clear
                    }
                }
                .somaBackground()
                .task { presentOnboardingPaywall() }
            }
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: step)
        // Load the bonus once for the whole flow, not just on the redeem
        // path. `step` is @State, so relaunching mid-onboarding restarts at
        // .referralCode; a user who already redeemed and now taps Skip would
        // otherwise reach the paywall with referralBonusUntil still nil --
        // which is exactly the "somafirst doesn't suppress the paywall" bug,
        // reached by a different route. AppState holds it in memory only and
        // nothing else loads it before Home.
        .task {
            await appState.refreshReferralBonus()
            await loadAdultConfirmation()
        }
    }

    /// Reads the date_of_birth this same onboarding pass just wrote (via
    /// OnboardingSurveyView.finish -> saveOnboardingSurvey) back from the
    /// server -- there's no in-memory answers to reuse here since this is a
    /// separate view further down the flow. UX-only gate; analyze-body-photo
    /// re-checks server-side regardless of what this reads.
    private func loadAdultConfirmation() async {
        guard let userId = SupabaseClient.shared.currentUserID else { return }
        guard let profile = try? await SupabaseClient.shared.fetchProfile(id: userId) else { return }
        isConfirmedAdultForBodyPhotos = AgeGate.isAdult(dobString: profile.dateOfBirth)
    }

    private func advance() {
        var nextRaw = step.rawValue + 1
        // Skipped entirely while the feature flag is off, or for a user not
        // confirmed 18+ (App Store 4+ rating -- no minors handling for this
        // feature exists, so it simply doesn't appear rather than being
        // shown a softened version) -- behavior stays byte-for-byte
        // identical to before this step existed in either case.
        if PostSetupStep(rawValue: nextRaw) == .bodyPhotos, !Config.enableBodyPhotoUpload || !isConfirmedAdultForBodyPhotos {
            nextRaw += 1
        }
        if let next = PostSetupStep(rawValue: nextRaw) {
            step = next
        } else {
            appState.markOnboardingComplete()
        }
    }

    /// Mirrors the old PaywallView(autoDismissIfBonusActive: true) behavior:
    /// someone who already has free access via a redeemed referral bonus
    /// skips the paywall entirely rather than being asked to pay.
    /// Otherwise, registers the hard-gated onboarding placement -- there is
    /// no "Not now" here; `markOnboardingComplete()` only fires once the
    /// paywall's feature closure runs (a purchase, a restore, or -- if the
    /// dashboard paywall is ever set to Non Gated -- any dismissal).
    private func presentOnboardingPaywall() {
        if let bonusUntil = appState.referralBonusUntil, bonusUntil > Date() {
            appState.markOnboardingComplete()
            return
        }
        Task { await presentOnboardingPaywallAfterEntitlementSync() }
    }

    /// Superwall PERSISTS subscriptionStatus across launches, and our
    /// mirror lands asynchronously at startup -- registering the paywall
    /// against a stale persisted status (e.g. a previous account's active
    /// entitlement on this device) silently skips the audience and eats
    /// the paywall. Await a fresh entitlement read first, then register.
    @MainActor
    private func presentOnboardingPaywallAfterEntitlementSync() async {
        await SubscriptionManager.shared.refreshEntitlement()
        paywallError = nil
        // Diagnostics handler (onSkip logging/analytics) + this screen's
        // own retry UI. onError REPLACES the diagnostics one (the handler
        // stores a single block), so re-report the failure to analytics
        // here alongside setting the visible error state. No win-back
        // onDismiss here on purpose -- onboarding_paywall is not a
        // dismissible-decline placement (see WinBackOfferManager).
        let handler = SuperwallDiagnostics.handler(placement: "onboarding_paywall")
        handler.onError { error in
            AnalyticsManager.shared.paywallPresentationFailed(placement: "onboarding_paywall", error: error)
            paywallError = String(localized: "postSetup.paywall.error", defaultValue: "Couldn't load the checkout screen. Check your connection and try again.", comment: "Shown when Superwall's onboarding paywall fails to present, with a retry button below it")
        }
        Superwall.shared.register(placement: "onboarding_paywall", handler: handler) {
            appState.markOnboardingComplete()
        }
    }

    private func paywallErrorContent(_ message: String) -> some View {
        VStack(spacing: 16) {
            Text(message)
                .font(.body)
                .foregroundStyle(SomaTokens.ink2)
                .multilineTextAlignment(.center)
            SomaButton(title: LocalizedStringKey(String(localized: "postSetup.paywall.retry", defaultValue: "Try again", comment: "Button that retries loading the failed onboarding paywall")), size: .lg, variant: .primary) {
                presentOnboardingPaywall()
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func saveConsent(marketingOptIn: Bool) async {
        guard let userId = SupabaseClient.shared.currentUserID else { return }
        // SignUpConsentStepView's own "Continue" already refuses to fire
        // this callback until acceptedTerms is checked, so reaching here
        // means a real, gated acknowledgment just happened.
        try? await SupabaseClient.shared.upsertUser(id: userId, marketingOptIn: marketingOptIn, legalAck: true)
    }
}
