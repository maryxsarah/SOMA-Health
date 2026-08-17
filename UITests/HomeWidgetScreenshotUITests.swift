import XCTest

/// Throwaway visual check: scrolls Home to the widget area with the
/// nutrition fixture on and attaches screenshots (used to verify the
/// full-width nutrition tile + trial banner layouts without a device).
final class HomeWidgetScreenshotUITests: XCTestCase {

    private var runningApp: XCUIApplication?

    override func tearDown() {
        runningApp?.terminate()
        runningApp = nil
    }

    func test_screenshot_homeWidgets() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixtures"]
        app.launchEnvironment["UITEST_SCENARIO"] = "activeGoalWeek2"
        app.launchEnvironment["UITEST_NUTRITION_STATE"] = "perfect"
        app.launch()
        runningApp = app

        XCTAssertTrue(app.staticTexts["Lower body strength"].waitForExistence(timeout: 15))
        app.swipeUp()
        attach(app, name: "home-widgets-1")
        app.swipeUp()
        attach(app, name: "home-widgets-2")
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
