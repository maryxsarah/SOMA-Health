import XCTest

/// Throwaway visual check for Turn 16 (Affirmations): screenshots the
/// Home affirmation widget tile, the Affirmations sheet (16b), the
/// reminder settings page (16c), and the edit-widgets sheet's new row --
/// same attach-and-read-via-xcresulttool technique as
/// HomeWidgetScreenshotUITests / BUG-120.
final class AffirmationScreenshotUITests: XCTestCase {

    private var runningApp: XCUIApplication?

    override func tearDown() {
        runningApp?.terminate()
        runningApp = nil
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixtures"]
        app.launchEnvironment["UITEST_SCENARIO"] = "activeGoalWeek2"
        app.launch()
        runningApp = app
        XCTAssertTrue(app.staticTexts["Lower body strength"].waitForExistence(timeout: 15))
        return app
    }

    func test_screenshot_affirmationWidgetAndSheet() {
        let app = launch()

        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Affirmation"].waitForExistence(timeout: 10))
        attach(app, name: "affirmation-widget-tile")

        app.buttons["List"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Affirmations"].waitForExistence(timeout: 10))
        // Give the fixture-backed generation call a beat to land.
        _ = app.staticTexts["You don't need a perfect day -- just ten honest minutes."].waitForExistence(timeout: 8)
        attach(app, name: "affirmations-sheet")

        app.buttons["Reminder settings"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Send through the day"].waitForExistence(timeout: 8))
        attach(app, name: "affirmation-reminders")
    }

    func test_screenshot_editWidgetsRow() {
        let app = launch()

        app.buttons["dock-more-button"].firstMatch.tap()
        let editWidgets = app.buttons["Edit widgets"].firstMatch
        XCTAssertTrue(editWidgets.waitForExistence(timeout: 8))
        editWidgets.tap()
        XCTAssertTrue(app.staticTexts["Your widgets"].waitForExistence(timeout: 8))
        app.swipeUp()
        attach(app, name: "edit-widgets-affirmation-row")
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
