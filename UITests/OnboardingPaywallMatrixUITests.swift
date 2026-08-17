import XCTest

/// Throwaway matrix for the onboarding paywall step (PostSetupFlowView
/// .paywall) under mocked subscription states, using the
/// UITEST_POSTSETUP=paywall shortcut. Expected behavior per case:
/// - free (no bonus): Superwall's onboarding_paywall campaign matches
///   ("unsubscribed users") -- the dashboard paywall PRESENTS.
/// - trial / premium: the user is entitled -- the campaign audience
///   skips, the SDK runs the feature closure, onboarding completes and
///   Home appears with NO paywall. That silent pass-through is the
///   by-design behavior the matrix documents.
/// Screenshots read back via xcresulttool.
final class OnboardingPaywallMatrixUITests: XCTestCase {

    private var runningApp: XCUIApplication?

    override func tearDown() {
        runningApp?.terminate()
        runningApp = nil
    }

    private func launchAtPaywall(subscription: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-onboarding-demo-resume"]
        app.launchEnvironment["UITEST_POSTSETUP"] = "paywall"
        app.launchEnvironment["UITEST_NO_REFERRAL_BONUS"] = "1"
        app.launchEnvironment["UITEST_SUBSCRIPTION"] = subscription
        app.launch()
        runningApp = app
        // Give Superwall time to fetch config + either present or skip
        // through to Home.
        sleep(10)
        return app
    }

    func test_paywall_free() {
        let app = launchAtPaywall(subscription: "free")
        attach(app, name: "onbpaywall-free")
    }

    func test_paywall_trial() {
        let app = launchAtPaywall(subscription: "trial")
        attach(app, name: "onbpaywall-trial")
    }

    func test_paywall_premiumAnnual() {
        let app = launchAtPaywall(subscription: "premium_annual")
        attach(app, name: "onbpaywall-premium")
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
