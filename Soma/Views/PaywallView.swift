import StoreKit
import SwiftUI

private enum SubscriptionPlan {
    case annual, monthly
}

/// Shown when the user taps into a recommendation's detail view without
/// an active subscription or referral bonus, and also as the final step
/// of onboarding. The Home card itself (today's category + message)
/// always stays free -- this only gates the deeper step target / workout
/// suggestions / "why" explanation.
struct PaywallView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @Environment(\.dismiss) private var dismiss

    /// Called instead of the sheet-dismiss environment action when this
    /// view is embedded as a plain step (e.g. in the onboarding post-setup
    /// flow) rather than presented via `.sheet`. Falls back to `dismiss()`
    /// when nil, so the existing Home-screen sheet usage is unaffected.
    var onFinished: (() -> Void)?

    /// True for the two *gating* presentations (onboarding's final step,
    /// and tapping a locked detail view): someone who already has free
    /// access via a referral bonus should not be asked to pay. False when
    /// the user opened this deliberately to subscribe -- otherwise the
    /// screen would close itself the instant they tried to buy, and since
    /// this is the only purchase surface in the app, there would be no way
    /// to subscribe at all during a 14-day bonus.
    var autoDismissIfBonusActive: Bool = true

    @State private var selectedPlan: SubscriptionPlan = .annual
    @State private var referralCode = ""
    @State private var isRedeeming = false
    @State private var redeemError: String?
    @State private var redeemSuccessMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                OrbView(state: .idle)
                    .scaleEffect(0.85)
                    .frame(height: 200)
                    .allowsHitTesting(false)

                VStack(spacing: 8) {
                    Text(selectedPlan == .annual ? "Start your 7-day free trial to continue" : "Continue with Soma Premium")
                        .font(Theme.display)
                        .multilineTextAlignment(.center)
                    Text("See exactly which workouts fit today, your step target, and why — not just the headline.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 16)

                VStack(spacing: 12) {
                    planRow(
                        plan: .annual,
                        title: "Start for free & save",
                        subtitle: annualBillingText,
                        priceHeadline: annualMonthlyEquivalentText,
                        badge: "7 DAYS FREE"
                    )
                    planRow(
                        plan: .monthly,
                        title: "Monthly",
                        subtitle: nil,
                        priceHeadline: monthlyPriceText ?? Self.unavailablePrice,
                        badge: nil
                    )
                }

                if let error = subscriptionManager.errorMessage {
                    VStack(spacing: 8) {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)

                        // Products were only ever fetched once, in
                        // SubscriptionManager.init -- a blip at launch left
                        // the paywall permanently unbuyable with no way out.
                        if subscriptionManager.productsIncomplete {
                            Button("Try again") {
                                Task { await subscriptionManager.loadProducts() }
                            }
                            .font(.caption.bold())
                            .disabled(subscriptionManager.isLoadingProducts)
                        }
                    }
                }

                PillButton(
                    title: selectedPlan == .annual ? "Start Free Trial" : "Continue",
                    // Without the product check this stayed fully enabled
                    // while there was nothing to buy: the tap hit a `guard
                    // let product` and returned silently, so the button just
                    // did nothing, over and over.
                    isEnabled: !subscriptionManager.isPurchasing && selectedProduct != nil
                ) {
                    Task {
                        guard let product = selectedProduct else { return }
                        await subscriptionManager.purchase(product)
                        if subscriptionManager.isSubscribed {
                            finish()
                        }
                    }
                }

                if let finePrint {
                    Text(finePrint)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }

                Button("Restore Purchases") {
                    Task {
                        await subscriptionManager.restorePurchases()
                        if subscriptionManager.isSubscribed {
                            finish()
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

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

                Button("Not now") { finish() }
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .dismissKeyboardOnTap()
        }
        .scrollDismissesKeyboard(.interactively)
        .somaBackground()
        .task {
            checkReferralBonusSkip()
            // SubscriptionManager only loads products once, at init. If
            // that attempt failed (no network at launch, StoreKit not ready
            // yet), every later visit to this screen inherited the failure
            // -- so the paywall retries for itself when it opens.
            if subscriptionManager.productsIncomplete, !subscriptionManager.isLoadingProducts {
                await subscriptionManager.loadProducts()
            }
        }
    }

    /// Mirrors HomeView.hasDetailAccess's bonus check -- if a referral
    /// bonus is currently active, skip the paywall entirely rather than
    /// showing "Pay Now"/"Start Free Trial" to someone who already has
    /// free access (previously this view never checked the bonus at all,
    /// so redeeming "somafirst" earlier in onboarding still ended in a
    /// payment prompt).
    private func checkReferralBonusSkip() {
        guard autoDismissIfBonusActive else { return }
        if let bonusUntil = appState.referralBonusUntil, bonusUntil > Date() {
            finish()
        }
    }

    private var selectedProduct: Product? {
        switch selectedPlan {
        case .annual: subscriptionManager.annualProduct
        case .monthly: subscriptionManager.monthlyProduct
        }
    }

    /// Stands in for a price StoreKit hasn't returned. These used to fall
    /// back to hardcoded "$39.99"/"$4.99"/"$3.33/mo", so a failed product
    /// load still rendered confident prices -- and fine print promising
    /// them -- for a purchase the app could not actually make, at whatever
    /// the App Store's real (possibly localized) price turned out to be.
    private static let unavailablePrice = "—"

    private var annualPriceText: String? {
        subscriptionManager.annualProduct?.displayPrice
    }

    private var monthlyPriceText: String? {
        subscriptionManager.monthlyProduct.map { "\($0.displayPrice)/mo" }
    }

    private var annualMonthlyEquivalentText: String {
        guard let product = subscriptionManager.annualProduct else { return Self.unavailablePrice }
        // Formatted with the product's own storefront format style -- a
        // hardcoded "$%.2f" here rendered the raw decimal with a dollar
        // sign on every storefront (e.g. "¥6,000 billed annually" next to
        // a "$500.00/mo" headline).
        return (product.price / 12).formatted(product.priceFormatStyle) + "/mo"
    }

    private var annualBillingText: String {
        guard let annualPriceText else { return "Annual plan" }
        return "\(annualPriceText) billed annually"
    }

    /// Nil while there's no real price behind it -- the terms describe a
    /// purchase, so they're hidden rather than invented when that purchase
    /// isn't available.
    private var finePrint: String? {
        switch selectedPlan {
        case .annual:
            guard let annualPriceText else { return nil }
            return "7 days free, then \(annualPriceText) per year. Billed annually and renews automatically unless canceled in the App Store."
        case .monthly:
            guard let monthlyPriceText else { return nil }
            return "\(monthlyPriceText), billed monthly and renews automatically unless canceled in the App Store."
        }
    }

    private func planRow(plan: SubscriptionPlan, title: String, subtitle: String?, priceHeadline: String, badge: String?) -> some View {
        Button {
            selectedPlan = plan
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                if let badge {
                    Text(badge)
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Theme.pillFill)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.body.bold())
                        if let subtitle {
                            Text(subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(priceHeadline)
                        .font(.title3.bold())
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(selectedPlan == plan ? Theme.pillFill : Color(.systemGray5), lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
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
                await NotificationManager.shared.scheduleUpgradeReminder(bonusUntil: bonusUntil)
                redeemSuccessMessage = "Applied! Free access extended."
                try? await Task.sleep(for: .seconds(1))
                finish()
            } catch {
                redeemError = "That code didn't work. Check it and try again."
            }
        }
    }

    private func finish() {
        if let onFinished {
            onFinished()
        } else {
            dismiss()
        }
    }
}

#Preview {
    PaywallView()
        .environmentObject(AppState())
}
