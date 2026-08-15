import XCTest

/// Temporary, throwaway verification test for the widget-tile cross-row
/// minHeight fix -- not part of the permanent suite, delete after use.
final class VerifyDesignFixTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Reproduces the user's exact reported scenario: Mood off, so Streak
    /// lands alone in row 2 with no row-mate to stretch against.
    func test_verifyStreakAloneMatchesRowOneHeight() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixtures"]
        app.launch()

        let moreButton = app.buttons["More actions"]
        XCTAssertTrue(moreButton.waitForExistence(timeout: 15))
        moreButton.tap()

        let editWidgets = app.buttons["Widgets"]
        XCTAssertTrue(editWidgets.waitForExistence(timeout: 5))
        editWidgets.tap()

        let moodToggle = app.switches.element(boundBy: 4)
        XCTAssertTrue(moodToggle.waitForExistence(timeout: 5))
        moodToggle.tap()

        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()

        let startWorkout = app.buttons["Start workout"]
        XCTAssertTrue(startWorkout.waitForExistence(timeout: 10))
        app.swipeUp()

        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
