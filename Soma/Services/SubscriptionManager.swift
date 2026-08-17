import StoreKit
import SuperwallKit

/// Source of truth for "does this device have an active subscription" --
/// reads StoreKit 2's `Transaction.currentEntitlements` directly, syncs the
/// resulting tier to Supabase (`users.subscription_tier`, used server-side
/// for AI-generation limits), and mirrors the result into
/// `Superwall.shared.subscriptionStatus` (required because Soma configures
/// Superwall with a custom PurchaseController -- see SomaPurchaseController
/// -- which makes Superwall stop tracking subscription status on its own).
/// Purchasing/restoring itself now goes through Superwall's dashboard
/// paywalls (SomaPurchaseController delegates to `Superwall.shared.purchase`/
/// `restorePurchases`), not this class -- there is deliberately no
/// `purchase()`/`loadProducts()` here anymore. Additive to, not a
/// replacement for, the referral-code bonus tracked server-side in
/// `users.referral_bonus_until` (see AppState).
@MainActor
final class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()

    static let monthlyProductID = "com.skollnitzer.soma.premium.monthly"
    static let annualProductID = "com.skollnitzer.soma.premium.annual"

    @Published private(set) var isSubscribed = false
    /// The tier last synced to Supabase ("free"/"monthly"/"annual") -- lets
    /// UI quota gates mirror the server's tier-scaled generation limits.
    @Published private(set) var tier = "free"
    /// Subscribed via an introductory (free-trial) offer -- drives the
    /// in-app "Upgrade now" highlight while the trial runs.
    @Published private(set) var isInTrial = false

    private var transactionListener: Task<Void, Never>?

    private init() {
        transactionListener = Task { [weak self] in
            await self?.listenForTransactionUpdates()
        }
        Task { [weak self] in
            await self?.refreshEntitlement()
        }
    }

    deinit {
        transactionListener?.cancel()
    }

    func refreshEntitlement() async {
        // StoreKit has no direct "user cancelled" push -- this is the one
        // observable signal available: isSubscribed flipping true -> false
        // across a refresh (expired, revoked/refunded, or no longer in
        // currentEntitlements at all). Doesn't change the entitlement logic
        // below, just observes its before/after result.
        let wasSubscribed = isSubscribed
        defer {
            if wasSubscribed, !isSubscribed {
                AnalyticsManager.shared.subscriptionCancelled()
            }
        }

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productID == Self.monthlyProductID || transaction.productID == Self.annualProductID
            else { continue }
            isSubscribed = transaction.revocationDate == nil
            tier = isSubscribed ? (transaction.productID == Self.annualProductID ? "annual" : "monthly") : "free"
            let offerType: Transaction.OfferType? = if #available(iOS 17.2, *) {
                transaction.offer?.type
            } else {
                transaction.offerType
            }
            isInTrial = isSubscribed && offerType == .introductory
            updateSubscriptionTierRemote(tier)
            mirrorSubscriptionStatusToSuperwall()
            return
        }
        isSubscribed = false
        tier = "free"
        isInTrial = false
        updateSubscriptionTierRemote("free")
        mirrorSubscriptionStatusToSuperwall()
    }

    /// A single "premium" entitlement identifier covers both plans --
    /// which plan (monthly vs annual) is tracked separately in Supabase's
    /// `subscription_tier`, not duplicated into Superwall's entitlement
    /// set, since Superwall's own paywall gating only needs "paid or not."
    private func mirrorSubscriptionStatusToSuperwall() {
        Superwall.shared.subscriptionStatus = isSubscribed ? .active([Entitlement(id: "premium")]) : .inactive
    }

    /// Fire-and-forget, best-effort -- see SupabaseClient.updateSubscriptionTier's
    /// own comment on why a client-reported tier is an acceptable trust
    /// model here (a cost-control soft limit, not a security boundary).
    private func updateSubscriptionTierRemote(_ tier: String) {
        Task { try? await SupabaseClient.shared.updateSubscriptionTier(tier) }
    }

    private func listenForTransactionUpdates() async {
        for await result in Transaction.updates {
            guard case .verified(let transaction) = result else { continue }
            await transaction.finish()
            await refreshEntitlement()
        }
    }
}
