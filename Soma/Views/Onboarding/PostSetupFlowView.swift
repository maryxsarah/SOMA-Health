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

    @State private var step: PostSetupStep = .referralCode

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
                PaywallView(onFinished: { appState.markOnboardingComplete() })
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
        }
    }

    private func advance() {
        var nextRaw = step.rawValue + 1
        // Skipped entirely while the feature flag is off, so behavior stays
        // byte-for-byte identical to before this step existed.
        if PostSetupStep(rawValue: nextRaw) == .bodyPhotos, !Config.enableBodyPhotoUpload {
            nextRaw += 1
        }
        if let next = PostSetupStep(rawValue: nextRaw) {
            step = next
        } else {
            appState.markOnboardingComplete()
        }
    }

    private func saveConsent(marketingOptIn: Bool) async {
        guard let userId = SupabaseClient.shared.currentUserID else { return }
        // SignUpConsentStepView's own "Continue" already refuses to fire
        // this callback until acceptedTerms is checked, so reaching here
        // means a real, gated acknowledgment just happened.
        try? await SupabaseClient.shared.upsertUser(id: userId, marketingOptIn: marketingOptIn, legalAck: true)
    }
}
