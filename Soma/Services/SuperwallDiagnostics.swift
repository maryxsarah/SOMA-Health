import Foundation
import SuperwallKit
import os

/// Every `Superwall.shared.register(placement:...)` call site should pass
/// this as its `handler:` argument. Without it, a misconfigured placement
/// (no campaign attached to it on the dashboard) or a presentation error
/// (e.g. the paywall webview failing to load) both fail *silently* --
/// SuperwallKit's own `register` implementation (PublicPresentation.swift)
/// calls the `feature` completion block unconditionally for both the
/// `.skipped` state and the non-gated `.declined` branch of `.dismissed`,
/// so the screen behaves exactly as if nothing were wrong at all. That's
/// indistinguishable, from inside the app, from "the user is already
/// subscribed" -- there is no other signal.
///
/// Two layers, because they cover different failure moments:
/// - `os.Logger`: visible in the Xcode console immediately, including in
///   Debug builds, where AnalyticsManager reports nothing at all (see its
///   own `#if !DEBUG` guard) -- this is what a developer testing locally
///   needs.
/// - `AnalyticsManager`: visible in PostHog/Firebase, which is what a
///   TestFlight or production failure needs, since nobody's attached to a
///   console for those.
enum SuperwallDiagnostics {
    private static let logger = Logger(subsystem: "com.skollnitzer.soma", category: "superwall")

    static func handler(placement: String) -> PaywallPresentationHandler {
        let handler = PaywallPresentationHandler()

        handler.onError { error in
            logger.error(
                "Paywall presentation error for placement \"\(placement, privacy: .public)\": \(String(describing: error), privacy: .public)"
            )
            AnalyticsManager.shared.paywallPresentationFailed(placement: placement, error: error)
        }

        handler.onSkip { reason in
            logger.warning(
                "Paywall skipped for placement \"\(placement, privacy: .public)\": \(reason.description, privacy: .public)"
            )
            AnalyticsManager.shared.paywallSkipped(placement: placement, reason: reason.description)
        }

        return handler
    }

    /// "Subscribe early" for TRIAL users. A trial user is ENTITLED, so
    /// subscription-gated campaigns (audience "not subscribed" -- what
    /// view_premium uses) silently skip for them. This registers the
    /// dedicated `upgrade_from_trial` placement instead -- attach a
    /// campaign to it in the Superwall dashboard with an audience that
    /// INCLUDES active subscribers -- and, until/unless such a campaign
    /// exists, guarantees the tap still does something by falling back
    /// (onSkip/onError) to the caller's native manage-subscriptions sheet.
    static func registerTrialUpgrade(onNoPaywall: @escaping @MainActor () -> Void) {
        let handler = handler(placement: "upgrade_from_trial")
        handler.onSkip { reason in
            logger.warning("upgrade_from_trial skipped (\(reason.description, privacy: .public)) -- falling back to manage-subscriptions")
            AnalyticsManager.shared.paywallSkipped(placement: "upgrade_from_trial", reason: reason.description)
            Task { @MainActor in onNoPaywall() }
        }
        handler.onError { error in
            logger.error("upgrade_from_trial error: \(String(describing: error), privacy: .public)")
            AnalyticsManager.shared.paywallPresentationFailed(placement: "upgrade_from_trial", error: error)
            Task { @MainActor in onNoPaywall() }
        }
        Superwall.shared.register(placement: "upgrade_from_trial", handler: handler)
    }
}
