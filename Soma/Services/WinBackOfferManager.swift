import StoreKit
import SuperwallKit

/// Exit-intent win-back offer: after a user DECLINES a dismissible paywall
/// (view_premium, detail_access -- never onboarding_paywall, which is
/// deliberately non-dismissible, see PostSetupFlowView.presentOnboardingPaywall),
/// registers the "paywall_exit_offer" placement, frequency-capped to once
/// per rolling 7 days per user via users.exit_offer_shown_at (server-as-
/// source-of-truth / client-cache, mirroring AppState.refreshReferralBonus
/// rather than inventing a new pattern).
///
/// The 30%-off mechanic itself is a real App Store subscription
/// promotional offer, applied via a signed compact JWS
/// (sign-promotional-offer Edge Function) passed to StoreKit 2's
/// `Product.PurchaseOption.promotionalOffer(_:compactJWS:)`. This is
/// deliberately NOT routed through `Superwall.shared.purchase()` --
/// SuperwallKit 4.16.1's own purchase path never inserts a
/// `.promotionalOffer` PurchaseOption (confirmed against the pinned SDK's
/// ProductPurchaserSK2.swift) -- so this purchase is triggered instead by
/// a Superwall paywall "Custom Callback" button (`onCustomCallbackHandler`,
/// added to SuperwallKit in 2025 -- see CustomCallback.swift), which keeps
/// the paywall's visual layer entirely in the Superwall dashboard editor
/// while this file does the actual signed purchase. Both purchase paths
/// still land in the same place: StoreKit 2's shared `Transaction.updates`,
/// which SubscriptionManager already listens to regardless of which code
/// path started the purchase.
enum WinBackOfferManager {
    private static let placement = "paywall_exit_offer"
    /// The Custom Callback name this file expects the dashboard paywall's
    /// "Accept 30% off" button to be configured with, plus the two
    /// variables it must pass along -- see the copy/layout brief.
    private static let customCallbackName = "apply_winback_discount"
    private static let minimumIntervalBetweenOffers: TimeInterval = 7 * 24 * 60 * 60

    /// Call from the `onDismiss` handler of any DISMISSIBLE paywall
    /// placement's `PaywallPresentationHandler`. No-ops for purchased/
    /// restored outcomes -- only a genuine decline should ever see a
    /// "wait, don't go" offer -- and respects the 7-day cap.
    static func maybePresentAfterDecline(result: PaywallResult) {
        guard result == .declined else { return }
        Task {
            guard await isEligible() else { return }
            await presentOffer()
        }
    }

    private static func isEligible() async -> Bool {
        guard let userId = SupabaseClient.shared.currentUserID else { return false }
        // Read failure (offline, transient 5xx) fails OPEN -- same call as
        // AppState.refreshReferralBonus makes for its own `try?` read.
        // Worst case on a failure here is one extra offer shown; that's
        // the right side to fail on for a frequency cap, not a security
        // boundary (see the migration's own comment).
        guard let lastShown = try? await SupabaseClient.shared.fetchExitOfferShownAt(id: userId) else {
            return true
        }
        return Date().timeIntervalSince(lastShown) > minimumIntervalBetweenOffers
    }

    private static func presentOffer() async {
        let handler = SuperwallDiagnostics.handler(placement: placement)

        handler.onPresent { _ in
            Task { try? await SupabaseClient.shared.markExitOfferShown() }
        }
        handler.onCustomCallback { callback in
            await handleCustomCallback(callback)
        }

        Superwall.shared.register(placement: placement, handler: handler)
    }

    private static func handleCustomCallback(_ callback: CustomCallback) async -> CustomCallbackResult {
        guard callback.name == customCallbackName else {
            return .failure(data: ["error": "unrecognized callback: \(callback.name)"])
        }
        guard let productId = callback.variables?["productId"] as? String,
              let offerId = callback.variables?["offerId"] as? String
        else {
            return .failure(data: ["error": "missing productId/offerId variables"])
        }

        do {
            let compactJWS = try await SupabaseClient.shared.signPromotionalOffer(
                productID: productId,
                offerID: offerId,
                transactionID: await currentAppTransactionID()
            )

            guard let product = try await StoreKit.Product.products(for: [productId]).first else {
                return .failure(data: ["error": "product not found: \(productId)"])
            }

            let options = Set(StoreKit.Product.PurchaseOption.promotionalOffer(offerId, compactJWS: compactJWS))
            let result = try await product.purchase(options: options)

            switch result {
            case .success(.verified(let transaction)):
                await transaction.finish()
                await SubscriptionManager.shared.refreshEntitlement()
                return .success()
            case .success(.unverified(_, let error)):
                return .failure(data: ["error": "unverified transaction: \(error.localizedDescription)"])
            case .userCancelled:
                return .failure(data: ["error": "cancelled"])
            case .pending:
                return .failure(data: ["error": "pending"])
            @unknown default:
                return .failure(data: ["error": "unknown purchase result"])
            }
        } catch {
            return .failure(data: ["error": error.localizedDescription])
        }
    }

    /// Optional but Apple-recommended input to the promotional-offer
    /// signature -- available even for someone who's never purchased
    /// anything (unlike a real transaction ID). Best-effort: a failure to
    /// obtain one (e.g. no network) just means signPromotionalOffer omits
    /// the claim, not a blocker for the purchase attempt.
    private static func currentAppTransactionID() async -> String? {
        guard case .verified(let appTransaction) = try? await AppTransaction.shared else { return nil }
        return appTransaction.appTransactionID
    }
}
