import SwiftUI

private enum PostSetupStep: Int {
    case referralCode, loading, planSummary, consent, tryFree, trialReminder, paywall
}

/// Runs everything after Notification Enablement and before Home:
/// optional referral code, the plan-generation loading sequence, a plan
/// summary, Terms/Privacy + marketing consent, two soft pre-paywall
/// reassurance screens, and finally the paywall itself. Only marks
/// onboarding complete once this entire sequence finishes.
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
    }

    private func advance() {
        if let next = PostSetupStep(rawValue: step.rawValue + 1) {
            step = next
        } else {
            appState.markOnboardingComplete()
        }
    }

    private func saveConsent(marketingOptIn: Bool) async {
        guard let userId = SupabaseClient.shared.currentUserID else { return }
        try? await SupabaseClient.shared.upsertUser(id: userId, marketingOptIn: marketingOptIn)
    }
}
