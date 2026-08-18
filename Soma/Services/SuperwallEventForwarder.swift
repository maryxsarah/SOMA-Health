import Foundation
import SuperwallKit

/// Forwards the handful of Superwall lifecycle events that map onto
/// AnalyticsManager's existing monetization events, so paywall/purchase
/// activity shows up in Firebase/PostHog exactly like it did when
/// PaywallView fired these calls directly. Deliberately narrow (`default:
/// break` for everything else) rather than guessing at SuperwallEvent case
/// names beyond what Superwall's own docs demonstrate -- Superwall's own
/// dashboard already charts the full event set, so this only needs to
/// cover what Soma's own analytics dashboards care about.
final class SuperwallEventForwarder: NSObject, SuperwallDelegate {
    static let shared = SuperwallEventForwarder()

    private override init() {}

    func handleSuperwallEvent(withInfo eventInfo: SuperwallEventInfo) {
        switch eventInfo.event {
        case .paywallOpen:
            AnalyticsManager.shared.paywallViewed()
        case .freeTrialStart(let product, _):
            AnalyticsManager.shared.trialStarted(plan: product.productIdentifier)
        case .transactionComplete(_, let product, _, _):
            AnalyticsManager.shared.subscriptionStarted(plan: product.productIdentifier)
        default:
            break
        }
    }

    /// Wired for a future "Redeem a code" tap-behavior on Superwall
    /// dashboard paywalls (product decision 2026-08-18) -- the dashboard
    /// action itself is manual owner setup (see docs/pricing-research.md
    /// checklist item 6) and doesn't exist yet, so this sits dormant
    /// until then. Matches the same name Profile's row uses conceptually
    /// (OfferCodeRedemption.present()).
    func handleCustomPaywallAction(withName name: String) {
        guard name == "redeem_offer_code" else { return }
        OfferCodeRedemption.present()
    }

    // subscriptionStatusDidChange is deliberately NOT implemented here:
    // SubscriptionManager.refreshEntitlement() already detects the exact
    // same active->inactive transition (from Transaction.currentEntitlements,
    // the source of truth this app pushes INTO Superwall.shared.subscriptionStatus)
    // and calls AnalyticsManager.shared.subscriptionCancelled() there.
    // Implementing it here too would fire that event twice for one change.
}
