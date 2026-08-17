import XCTest

/// Covers 15a: the calendar-icon entry point added to Home's greeting row
/// (3a, left of the checklist ring-pill) and the month-grid history screen
/// it opens. Runs against the in-app fixture stub (`UITestSupport.swift`) --
/// no real network.
final class HistoryCalendarUITests: XCTestCase {

    private var runningApp: XCUIApplication?

    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() {
        runningApp?.terminate()
        runningApp = nil
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixtures"]
        app.launch()
        runningApp = app
        return app
    }

    /// Diagnostic: does an existing, already-working Home sheet (Settings,
    /// via the "..." ellipsis) open correctly in this exact build/runtime?
    /// Isolates whether a failure is specific to the new calendar sheet or
    /// a broader issue with this simulator/build.
    func test_diagnostic_settingsEllipsis_opensProfileSheet() {
        let app = launch()

        let ellipsis = app.buttons["ellipsis"]
        XCTAssertTrue(ellipsis.waitForExistence(timeout: 15))
        ellipsis.tap()

        let doneButton = app.buttons["Done"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 10), "Tapping the settings ellipsis should open the Profile sheet")
    }

    /// Diagnostic: `showChecklistSheet` sits right next to `showHistoryCalendar`
    /// in HomeView's modifier chain (13th vs 14th stacked `.sheet()`). If this
    /// ALSO fails to open, the issue is chain depth/count, not code specific
    /// to the new calendar button.
    func test_diagnostic_checklistPill_opensChecklistSheet() {
        let app = launch()

        let pill = app.buttons["0/9"]
        XCTAssertTrue(pill.waitForExistence(timeout: 15), "Home's greeting row should show the checklist ring-pill")
        pill.tap()

        let sheetTitle = app.navigationBars["Today's checklist"]
        XCTAssertTrue(sheetTitle.waitForExistence(timeout: 10), "Tapping the checklist pill should open the checklist sheet")
    }

    func test_calendarButton_opensHistoryScreen() {
        let app = launch()

        let calendarButton = app.buttons["home.historyCalendarButton"]
        XCTAssertTrue(calendarButton.waitForExistence(timeout: 15), "Home's greeting row should show the calendar-icon entry point")
        calendarButton.tap()

        // 15a draws its own pinned header (no NavigationStack toolbar) --
        // the close lens is the stable handle for "the screen is open".
        let closeButton = app.buttons["historyCalendar.closeButton"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 10), "Tapping the calendar icon should open the History screen")

        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "history-calendar-screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
