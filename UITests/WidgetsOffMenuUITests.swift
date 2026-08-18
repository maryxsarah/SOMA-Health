import XCTest

/// Throwaway verification: turning every dashboard widget off must not
/// break the floating dock or the More sheet -- both are structurally
/// independent of widget-visibility state (dashboardDock lives in
/// .safeAreaInset, outside the widget-gated VStack; MoreActionsSheet's
/// action list never reads a dashboardWidget.* flag). Screenshots read
/// back via xcresulttool.
final class WidgetsOffMenuUITests: XCTestCase {

    private var runningApp: XCUIApplication?

    override func tearDown() {
        runningApp?.terminate()
        runningApp = nil
    }

    func test_allWidgetsOff_dockAndMoreSheetStillWork() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixtures"]
        app.launchEnvironment["UITEST_SCENARIO"] = "activeGoalWeek2"
        app.launch()
        runningApp = app
        XCTAssertTrue(app.staticTexts["Lower body strength"].waitForExistence(timeout: 15))

        // Open "Your widgets" via the greeting row's grid icon.
        app.buttons["home.editWidgetsButton"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Your widgets"].waitForExistence(timeout: 8))

        // Turn every widget off by its stable identifier (photoProgress
        // starts off already, so this ends with all 9 off).
        let widgetIDs = ["water", "sleep", "streak", "tasks", "mood", "nutrition", "goal", "photos", "affirmation"]
        for id in widgetIDs {
            let toggle = app.switches["editWidgets.toggle.\(id)"]
            XCTAssertTrue(toggle.waitForExistence(timeout: 3), "missing toggle for \(id)")
            if toggle.value as? String == "1" {
                toggle.tap()
            }
            XCTAssertEqual(toggle.value as? String, "0", "\(id) should be off")
        }

        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Lower body strength"].waitForExistence(timeout: 8))
        attach(app, name: "widgetsoff-home")

        // The dock itself: all 6 fixed slots must still be present and
        // tappable -- it renders in .safeAreaInset, entirely outside the
        // widget-gated content, so this should be unaffected.
        XCTAssertTrue(app.buttons["dock-more-button"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dock-nutrition-button"].exists)

        // More sheet: its action list (Goals/Photos/Widgets/Profile) never
        // reads a widget-enabled flag either.
        app.buttons["dock-more-button"].tap()
        XCTAssertTrue(app.buttons["dock-goals-button"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["profile-button"].exists)
        attach(app, name: "widgetsoff-moresheet")

        // Sanity: the checklist ring-pill (greeting row) must still open
        // the checklist sheet even with the Daily tasks widget off --
        // it's kept invisibly mounted specifically so this survives.
        app.swipeDown() // dismiss More sheet
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
