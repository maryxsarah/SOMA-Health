import XCTest

/// Verifies the onboarding survey's longest option lists -- diet (11
/// cases, screen "10f"), kitchen equipment (14, the longest of any
/// onboarding screen), referral source (10) -- actually scroll all the way
/// to their last option, and that the pinned "Continue" button never
/// blocks tapping it. This is the regression class reported 2026-08-15:
/// bottom options "stuck" under Continue with no way to reach them.
///
/// Lands directly on each screen via UITEST_ONBOARDING_SURVEY_STEP (see
/// UITestSupport.onboardingSurveyStartStep) instead of replaying the ~17
/// preceding survey questions to reach it.
final class OnboardingSurveyScrollUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(step: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixtures"]
        app.launchEnvironment["UITEST_ONBOARDING_SURVEY_STEP"] = step
        app.launch()
        return app
    }

    /// Swipes the survey's ScrollView up until `element` is on-screen and
    /// hittable, or gives up after `maxSwipes` -- XCUITest has no native
    /// "scroll to element" API.
    private func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 20) -> Bool {
        let scrollView = app.scrollViews.firstMatch
        var attempts = 0
        while !element.isHittable, attempts < maxSwipes {
            scrollView.swipeUp()
            attempts += 1
        }
        return element.isHittable
    }

    /// The last option row must exist, become reachable by scrolling, and
    /// -- the actual regression this guards against -- not be vertically
    /// overlapped by Continue: its top must sit at or below the row's
    /// bottom before the tap, not just "the tap happened to land".
    @discardableResult
    private func selectLastOptionWithoutOverlap(_ lastOptionLabel: String, app: XCUIApplication) -> XCUIElement {
        let lastOption = app.buttons[lastOptionLabel]
        XCTAssertTrue(lastOption.waitForExistence(timeout: 10), "\(lastOptionLabel) row should exist in the tree")
        if !scrollUntilHittable(lastOption, in: app) {
            let shot = XCUIScreen.main.screenshot()
            let screenshotURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("scroll-failure-\(lastOptionLabel.replacingOccurrences(of: " ", with: "_")).png")
            try? shot.pngRepresentation.write(to: screenshotURL)
            XCTFail("\(lastOptionLabel) should become hittable by scrolling the option list. Frame: \(lastOption.frame), Continue frame: \(app.buttons["Continue"].frame)")
        }

        let continueButton = app.buttons["Continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(
            continueButton.frame.minY, lastOption.frame.maxY,
            "Continue must sit below \(lastOptionLabel), not overlap it"
        )

        lastOption.tap()
        return continueButton
    }

    // TEMP diagnostic -- checks whether the simulator is delivering taps to
    // SwiftUI content at all right now (see soma-simulator-swiftui-tap-
    // delivery-broken memory), by tapping a visible, no-scroll-needed row.
    // Remove after use.
    func test_ZZZ_diagnosticPlainTapOnVisibleOption() {
        let app = launch(step: "dietType")
        XCTAssertTrue(app.staticTexts["Do you follow a specific diet?"].waitForExistence(timeout: 15))
        let balanced = app.buttons["Balanced"]
        XCTAssertTrue(balanced.waitForExistence(timeout: 10))
        XCTAssertTrue(balanced.isHittable, "Balanced should be on-screen without any scrolling")
        balanced.tap()
        let continueButton = app.buttons["Continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 5))
        XCTAssertTrue(continueButton.isEnabled, "Tapping a visible option should enable Continue")
    }

    // MARK: - Diet (11 options, longest single-select list)

    func test_dietQuestion_scrollsToLastOptionAndContinues() {
        let app = launch(step: "dietType")
        XCTAssertTrue(app.staticTexts["Do you follow a specific diet?"].waitForExistence(timeout: 15))

        let continueButton = selectLastOptionWithoutOverlap("I don't follow any diet", app: app)
        XCTAssertTrue(continueButton.isEnabled, "Selecting the last option should enable Continue")
        continueButton.tap()

        XCTAssertTrue(
            app.staticTexts["What's in your kitchen?"].waitForExistence(timeout: 10),
            "Continue should advance from the diet question to kitchen equipment"
        )
    }

    // MARK: - Kitchen equipment (14 options, longest list of any onboarding screen)

    func test_kitchenEquipmentQuestion_scrollsToLastOptionAndContinues() {
        let app = launch(step: "kitchenEquipment")
        XCTAssertTrue(app.staticTexts["What's in your kitchen?"].waitForExistence(timeout: 15))

        // Continue here is never gated on a selection, so this only checks
        // reachability + no overlap, not isEnabled.
        let continueButton = selectLastOptionWithoutOverlap("Other", app: app)
        continueButton.tap()

        XCTAssertTrue(
            app.staticTexts["What would you like to accomplish?"].waitForExistence(timeout: 10),
            "Continue should advance from kitchen equipment to the accomplishment question"
        )
    }

    // MARK: - Referral source (10 options)

    func test_referralSourceQuestion_scrollsToLastOptionAndContinues() {
        let app = launch(step: "referralSource")
        XCTAssertTrue(app.staticTexts["Where did you hear about us?"].waitForExistence(timeout: 15))

        let continueButton = selectLastOptionWithoutOverlap("Other", app: app)
        XCTAssertTrue(continueButton.isEnabled, "Selecting the last option should enable Continue")
        continueButton.tap()

        XCTAssertTrue(
            app.staticTexts["Designed to help you stay on track"].waitForExistence(timeout: 10),
            "Continue should advance from referral source to the trust-chart step"
        )
    }
}
