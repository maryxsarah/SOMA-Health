import XCTest

/// Throwaway visual matrix: subscription-dependent UI (3a Home top /
/// trial banner, 3e nutrition tile, 12b Profile hub card subtitle, the
/// Account page's PLAN group) under trial / premium / free+promo-bonus,
/// with the mocked entitlement mirrored into Superwall. Screenshots read
/// back via xcresulttool, same technique as AffirmationScreenshotUITests.
final class SubscriptionMatrixScreenshotUITests: XCTestCase {

    private var runningApp: XCUIApplication?

    override func tearDown() {
        runningApp?.terminate()
        runningApp = nil
    }

    private func launch(subscription: String?) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixtures"]
        app.launchEnvironment["UITEST_SCENARIO"] = "activeGoalWeek2"
        if let subscription { app.launchEnvironment["UITEST_SUBSCRIPTION"] = subscription }
        app.launch()
        runningApp = app
        XCTAssertTrue(app.staticTexts["Lower body strength"].waitForExistence(timeout: 15))
        return app
    }

    private func captureFlow(_ app: XCUIApplication, prefix: String) {
        attach(app, name: "\(prefix)-home-top")
        app.swipeUp()
        attach(app, name: "\(prefix)-home-widgets")

        // 12b hub via the top-right ••• (opens Profile directly).
        app.buttons["Settings"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Your profile"].waitForExistence(timeout: 8))
        attach(app, name: "\(prefix)-profile-hub")

        // Account page: PLAN group with the Subscription row. The hub
        // card is a NavigationLink whose label combines title+subtitle,
        // so match the visible "Account" text, scrolling it into view.
        let accountText = app.staticTexts["Account"].firstMatch
        if !accountText.isHittable { app.swipeUp() }
        accountText.tap()
        _ = app.staticTexts["Subscription"].waitForExistence(timeout: 8)
        attach(app, name: "\(prefix)-account-settings")
    }

    func test_trial() {
        let app = launch(subscription: "trial")
        captureFlow(app, prefix: "trial")
    }

    func test_premiumAnnual() {
        let app = launch(subscription: "premium_annual")
        captureFlow(app, prefix: "premium")
    }

    /// No StoreKit sub, but the fixture profile's 2099 referral bonus is
    /// active -- the promo-code state.
    func test_freeWithPromoBonus() {
        let app = launch(subscription: "free")
        captureFlow(app, prefix: "promo")
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
