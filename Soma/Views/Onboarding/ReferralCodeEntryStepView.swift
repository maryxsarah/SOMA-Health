import SwiftUI

/// "Enter referral code (optional)" -- standalone step in the onboarding
/// sequence (the same redemption is also always available later from the
/// Paywall itself, for anyone who skips this or gets a code afterward).
struct ReferralCodeEntryStepView: View {
    let onSkip: () -> Void
    let onRedeemed: () -> Void

    @State private var code = ""
    @State private var isRedeeming = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                Text(String(localized: "referral_code.title", defaultValue: "Enter referral code", comment: "Headline on the referral code entry step"))
                    .font(Theme.display)
                Text(String(localized: "referral_code.subtitle", defaultValue: "Optional -- you can skip this step.", comment: "Subtitle on the referral code entry step"))
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)

            CardView {
                HStack(spacing: 8) {
                    TextField(String(localized: "referral_code.placeholder", defaultValue: "Referral Code", comment: "Placeholder text for the referral code input field"), text: $code)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .glassCardFlat(cornerRadius: SomaTokens.rXL)
                    Button(String(localized: "referral_code.submit", defaultValue: "Submit", comment: "Button that submits the entered referral code")) { redeem() }
                        .font(.body.bold())
                        .disabled(isRedeeming || code.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            PillButton(title: LocalizedStringKey(String(localized: "referral_code.skip", defaultValue: "Skip", comment: "Button that skips the optional referral code step")), isEnabled: !isRedeeming, action: onSkip)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
        }
        .somaBackground()
        .dismissKeyboardOnTap()
    }

    private func redeem() {
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isRedeeming = true
        errorMessage = nil

        Task {
            defer { isRedeeming = false }
            do {
                _ = try await SupabaseClient.shared.redeemReferralCode(trimmed)
                AnalyticsManager.shared.referralCodeRedeemed(surface: "onboarding")
                onRedeemed()
            } catch {
                errorMessage = String(
                    localized: "referral_code.invalid",
                    defaultValue: "That code didn't work. Check it and try again.",
                    comment: "Error shown when a referral code fails to redeem"
                )
            }
        }
    }
}
