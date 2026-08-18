import StoreKit
import SuperwallKit
import UIKit

/// Delegates purchase/restore to Superwall's own StoreKit 2 handling
/// (`Superwall.shared.purchase`/`restorePurchases`) rather than
/// reimplementing it -- Soma's products are plain App Store subscriptions
/// with no external billing system, so there's nothing custom to route.
/// Using a PurchaseController at all (rather than Superwall's zero-config
/// default) exists only so SubscriptionManager stays the one place that
/// reads `Transaction.currentEntitlements` and syncs `subscription_tier` to
/// Supabase -- see SubscriptionManager.refreshEntitlement(), which is what
/// keeps `Superwall.shared.subscriptionStatus` in sync.
final class SomaPurchaseController: PurchaseController {
    static let shared = SomaPurchaseController()

    private init() {}

    func purchase(product: StoreProduct) async -> PurchaseResult {
        await Superwall.shared.purchase(product)
    }

    func restorePurchases() async -> RestorationResult {
        await Superwall.shared.restorePurchases()
    }
}

/// Apple Offer Code redemption (the "invite a friend to 1 free month"
/// mechanism, product decision 2026-08-18) -- additive to, not a
/// replacement for, the custom in-app referral system in ReferralCodeSheet.
/// A redeemed code arrives via `Transaction.updates`, which
/// SubscriptionManager already listens on to refresh entitlement and
/// re-mirror status to Superwall, so there's nothing to wire up here
/// beyond presenting Apple's own sheet.
@MainActor
enum OfferCodeRedemption {
    static func present() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
        else { return }
        Task {
            try? await AppStore.presentOfferCodeRedeemSheet(in: scene)
        }
    }
}
