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
    /// The user's own share code, fetch-or-created on open.
    @State private var myCode: SupabaseClient.MyReferralCode?
    @State private var isRedeeming = false
    @State private var redeemError: String?
    @State private var redeemSuccessMessage: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                if let myCode {
                    myCodeCard(myCode)
                }

                Text(String(localized: "referral_code.title", defaultValue: "Have a referral code?", comment: "Referral code sheet: headline"))
                    .font(SomaType.sheetTitle)
                    .foregroundStyle(SomaTokens.ink)
                Text(String(localized: "referral_code.subtitle", defaultValue: "Redeeming a valid code unlocks free access to Soma Premium for a limited time.", comment: "Referral code sheet: explanation of what redeeming a code does"))
                    .font(.system(size: 13.5))
                    .foregroundStyle(SomaTokens.ink3)

                // "Where's my code?" -- an already-active bonus shows its
                // real state up top instead of an empty entry form (the
                // code itself isn't stored anywhere client-side; the
                // expiry date is the meaningful fact).
                if let bonusUntil = appState.referralBonusUntil, bonusUntil > Date() {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(SomaTokens.success)
                        Text(String(localized: "referral_code.activeBonus", defaultValue: "Free access active until \(bonusUntil.formatted(date: .abbreviated, time: .omitted))", comment: "Referral sheet card shown while a redeemed code's free-access bonus is active, with its end date"))
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(SomaTokens.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.init(top: 13, leading: 14, bottom: 13, trailing: 14))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCardFlat(cornerRadius: SomaTokens.rRow)
                }

                HStack(spacing: 8) {
                    GlassTextField(
                        placeholder: String(localized: "referral_code.placeholder", defaultValue: "Enter code", comment: "Referral code sheet: placeholder for the code text field"),
                        text: $referralCode
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    Button {
                        redeemCode()
                    } label: {
                        Text(String(localized: "referral_code.apply", defaultValue: "Apply", comment: "Referral code sheet: button that submits the entered code"))
                            .font(.system(size: 12.5, weight: .bold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .glassGel(.blue)
                    }
                    .buttonStyle(.plain)
                    .disabled(isRedeeming || referralCode.trimmingCharacters(in: .whitespaces).isEmpty)
                    .opacity(isRedeeming || referralCode.trimmingCharacters(in: .whitespaces).isEmpty ? 0.45 : 1)
                }

                if let redeemError {
                    Text(redeemError)
                        .font(.system(size: 12))
                        .foregroundStyle(SomaTokens.danger)
                }
                if let redeemSuccessMessage {
                    Text(redeemSuccessMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(SomaTokens.success)
                }

                Spacer()
            }
            .padding(20)
            .dismissKeyboardOnTap()
            .somaBackground()
            .task { myCode = try? await SupabaseClient.shared.fetchMyReferralCode() }
            .navigationTitle(String(localized: "referral_code.navigationTitle", defaultValue: "Referral code", comment: "Referral code sheet: navigation title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "referral_code.close", defaultValue: "Close", comment: "Referral code sheet: close button in the toolbar")) { dismiss() }
                }
            }
        }
    }

    /// "Your code" share card -- serif code as the hero, ShareLink, and
    /// the live redemption count once anyone has used it.
    private func myCodeCard(_ code: SupabaseClient.MyReferralCode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "referral_code.mine.eyebrow", defaultValue: "Your code", comment: "Eyebrow above the user's own shareable referral code"))
                .font(.system(size: 10.5, weight: .bold))
                .tracking(0.7)
                .textCase(.uppercase)
                .foregroundStyle(SomaTokens.ink4)
            HStack(spacing: 10) {
                Text(code.code)
                    .font(SomaType.metric(24))
                    .foregroundStyle(SomaTokens.ink)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
                ShareLink(item: String(localized: "referral_code.mine.shareMessage", defaultValue: "Try Soma — my code \(code.code) gives you \(code.bonusDays) days of Premium for free.", comment: "Prefilled share-sheet message for the user's referral code; placeholders are the code and its free-day count")) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SomaTokens.accent)
                        .frame(width: 34, height: 34)
                        .glassLens()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(String(localized: "referral_code.mine.shareAccessibility", defaultValue: "Share your referral code", comment: "VoiceOver label for the share button next to the user's referral code")))
            }
            Text(String(localized: "referral_code.mine.caption", defaultValue: "Gives a friend \(code.bonusDays) days of free access.", comment: "Caption under the user's referral code, with its free-day count"))
                .font(.system(size: 11.5))
                .foregroundStyle(SomaTokens.ink3)
            if code.redemptionCount > 0 {
                Text(String(localized: "referral_code.mine.redemptions", defaultValue: "Used by \(code.redemptionCount) friends so far", comment: "Line under the user's referral code showing how many people redeemed it, pluralized by count"))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(SomaTokens.accent)
            }
        }
        .padding(.init(top: 14, leading: 16, bottom: 14, trailing: 16))
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCardFlat(cornerRadius: SomaTokens.rRow)
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
