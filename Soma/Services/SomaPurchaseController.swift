import StoreKit
import SuperwallKit

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
