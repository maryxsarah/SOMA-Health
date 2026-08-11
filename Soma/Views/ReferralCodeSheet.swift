import SwiftUI

/// Referral-code redemption, moved out of the old PaywallView (retired in
/// favor of Superwall's dashboard-configured paywalls) into its own
/// standalone entry point in Profile -- a Superwall paywall template has no
/// clean way to host arbitrary custom form logic like this without a
/// custom-JS-action bridge, and this is simple enough to not need one.
struct ReferralCodeSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var referralCode = ""
    @State private var isRedeeming = false
    @State private var redeemError: String?
    @State private var redeemSuccessMessage: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Have a referral code?")
                    .font(.title3.bold())
                Text("Redeeming a valid code unlocks free access to Soma Premium for a limited time.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

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

                Spacer()
            }
            .padding(20)
            .dismissKeyboardOnTap()
            .somaBackground()
            .navigationTitle("Referral code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
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
                AnalyticsManager.shared.referralCodeRedeemed(surface: "profile")
                appState.referralBonusUntil = bonusUntil
                await NotificationManager.shared.scheduleUpgradeReminder(bonusUntil: bonusUntil)
                redeemSuccessMessage = String(
                    localized: "referral_code.success",
                    defaultValue: "Applied! Free access extended.",
                    comment: "Shown briefly after a referral code is redeemed successfully, before the sheet auto-dismisses"
                )
                try? await Task.sleep(for: .seconds(1))
                dismiss()
            } catch {
                redeemError = String(
                    localized: "referral_code.invalid",
                    defaultValue: "That code didn't work. Check it and try again.",
                    comment: "Error shown when a referral code fails to redeem"
                )
            }
        }
    }
}
