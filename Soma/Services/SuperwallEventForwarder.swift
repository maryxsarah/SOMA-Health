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

    // subscriptionStatusDidChange is deliberately NOT implemented here:
    // SubscriptionManager.refreshEntitlement() already detects the exact
    // same active->inactive transition (from Transaction.currentEntitlements,
    // the source of truth this app pushes INTO Superwall.shared.subscriptionStatus)
    // and calls AnalyticsManager.shared.subscriptionCancelled() there.
    // Implementing it here too would fire that event twice for one change.
}
