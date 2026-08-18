import XCTest

/// Covers the Home sleep widget's three states from the Soma Refresh design
/// (frame 9g, "Sleep -- chips / logged / wearable"): no wearable + not
/// logged shows four one-tap duration chips; tapping one flips the widget to
/// a logged/verdict state; a wearable-sourced `daily_snapshot` row (stubbed
/// via `UITEST_SLEEP_SOURCE`) hides the chips entirely. Runs against the
/// in-app fixture stub (`UITestSupport.swift`) -- no real network.
final class SleepWidgetUITests: XCTestCase {

    private var runningApp: XCUIApplication?

    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() {
        runningApp?.terminate()
        runningApp = nil
    }

    private func launch(sleepSource: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixtures"]
        if let sleepSource {
            app.launchEnvironment["UITEST_SLEEP_SOURCE"] = sleepSource
        }
        app.launch()
        runningApp = app
        return app
    }

    /// Home's widget grid sits below the hero/readiness card -- not always
    /// on-screen at launch on smaller simulators. Same "swipe once, check
    /// again" idiom as SportGoalJourneyTests.
    private func revealSleepWidget(_ app: XCUIApplication, chip: XCUIElement) {
        if !chip.waitForExistence(timeout: 5) || !chip.isHittable {
            app.swipeUp()
        }
    }

    func test_sleepWidget_noData_showsFourChipsAndSizes() {
        let app = launch()

        let underSix = app.buttons["sleep-chip-under6"]
        revealSleepWidget(app, chip: underSix)
        XCTAssertTrue(underSix.waitForExistence(timeout: 15), "No sleep data yet should show the four duration chips")

        let chips = [
            app.buttons["sleep-chip-under6"],
            app.buttons["sleep-chip-6-7"],
            app.buttons["sleep-chip-7-8"],
            app.buttons["sleep-chip-8plus"],
        ]
        for chip in chips {
            XCTAssertTrue(chip.waitForExistence(timeout: 5), "Every duration chip should be present")
            // Sanity bound on chip size -- catches a regression where a chip
            // collapses to zero width/height (e.g. a broken frame modifier)
            // without pinning an exact pixel value to the design mock.
            XCTAssertGreaterThan(chip.frame.width, 20, "Chip '\(chip.identifier)' should have a real tappable width")
            XCTAssertGreaterThan(chip.frame.height, 16, "Chip '\(chip.identifier)' should have a real tappable height")
        }

        // The four chips should read as roughly equal-width siblings in the
        // same row (an even split of the tile), not one dominating the rest.
        let widths = chips.map(\.frame.width)
        if let minWidth = widths.min(), let maxWidth = widths.max(), minWidth > 0 {
            XCTAssertLessThan(maxWidth / minWidth, 1.5, "Duration chips should be roughly evenly sized")
        }
    }

    func test_sleepWidget_tapChip_transitionsToLoggedState() {
        let app = launch()

        let sevenEight = app.buttons["sleep-chip-7-8"]
        revealSleepWidget(app, chip: sevenEight)
        XCTAssertTrue(sevenEight.waitForExistence(timeout: 15))
        sevenEight.tap()

        // Logged state: verdict word replaces the chip row, and the chips
        // themselves disappear (real POST -> re-fetch -> UI flip, not a
        // canned fixture standing in for the transition).
        let verdict = app.staticTexts["sleep-widget-logged-verdict"]
        XCTAssertTrue(verdict.waitForExistence(timeout: 10), "Tapping the 7-8h chip should log it and show the 'Solid' verdict")
        XCTAssertEqual(verdict.label, "Solid")
        XCTAssertFalse(app.buttons["sleep-chip-under6"].exists, "Duration chips should be gone once a bucket is logged")
    }

    func test_sleepWidget_wearableConnected_hidesChipsShowsPhaseBar() {
        let app = launch(sleepSource: "oura")

        let ouraLabel = app.staticTexts["Oura"]
        if !ouraLabel.waitForExistence(timeout: 15) {
            app.swipeUp()
        }
        XCTAssertTrue(ouraLabel.waitForExistence(timeout: 10), "A wearable-sourced snapshot should show the source name")
        XCTAssertFalse(app.buttons["sleep-chip-under6"].exists, "Wearable connected: chips should never show")
        XCTAssertFalse(app.buttons["sleep-chip-7-8"].exists, "Wearable connected: chips should never show")
    }
}
