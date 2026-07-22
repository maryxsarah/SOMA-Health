import SwiftUI

/// Shown when the user taps into a recommendation's detail view without
/// an active subscription or referral bonus. The Home card itself (today's
/// category + message) always stays free -- this only gates the deeper
/// step target / workout suggestions / "why" explanation.
struct PaywallView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var referralCode = ""
    @State private var isRedeeming = false
    @State private var redeemError: String?
    @State private var redeemSuccessMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                OrbView(state: .idle)
                    .scaleEffect(0.7)
                    .frame(height: 160)
                    .allowsHitTesting(false)

                VStack(spacing: 8) {
                    Text("Unlock your full plan")
                        .font(Theme.display)
                        .multilineTextAlignment(.center)
                    Text("See exactly which workouts fit today, your step target, and why -- not just the headline.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 16)

                CardView {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Soma Premium")
                                .font(.body.bold())
                            Text("14 days free, then \(priceText)/month")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    if let error = subscriptionManager.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    PillButton(
                        title: "Start Free Trial",
                        isEnabled: !subscriptionManager.isPurchasing
                    ) {
                        Task {
                            await subscriptionManager.purchase()
                            if subscriptionManager.isSubscribed {
                                dismiss()
                            }
                        }
                    }

                    Button("Restore Purchases") {
                        Task {
                            await subscriptionManager.restorePurchases()
                            if subscriptionManager.isSubscribed {
                                dismiss()
                            }
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                }

                CardView {
                    Text("Have a referral code?")
                        .font(.body.bold())
                    HStack(spacing: 8) {
                        TextField("Enter code", text: $referralCode)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)
                        Button("Apply") {
                            redeemCode()
                        }
                        .font(.body.bold())
                        .disabled(isRedeeming || referralCode.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if let redeemError {
                        Text(redeemError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    if let redeemSuccessMessage {
                        Text(redeemSuccessMessage)
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }

                Button("Not now") { dismiss() }
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .dismissKeyboardOnTap()
        }
        .scrollDismissesKeyboard(.interactively)
        .somaBackground()
    }

    private var priceText: String {
        subscriptionManager.product?.displayPrice ?? "$4.99"
    }

    private func redeemCode() {
        let code = referralCode.trimmingCharacters(in: .whitespaces)
        guard !code.isEmpty else { return }
        isRedeeming = true
        redeemError = nil
        redeemSuccessMessage = nil

        Task {
            defer { isRedeeming = false }
            do {
                let bonusUntil = try await SupabaseClient.shared.redeemReferralCode(code)
                appState.referralBonusUntil = bonusUntil
                // No payment method needed during the bonus period -- this
                // is the only nudge to actually subscribe, fired once the
                // bonus runs out.
                await NotificationManager.shared.scheduleUpgradeReminder(at: bonusUntil)
                redeemSuccessMessage = "Applied! Free access extended."
                try? await Task.sleep(for: .seconds(1))
                dismiss()
            } catch {
                redeemError = "That code didn't work. Check it and try again."
            }
        }
    }
}

#Preview {
    PaywallView()
        .environmentObject(AppState())
}
