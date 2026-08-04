import XCTest

/// The four sport-goal journeys from UITests/CASES.md, run against the
/// in-app fixture stub (UITestSupport.swift): `--ui-test-fixtures` +
/// UITEST_SCENARIO select the world each test starts in. No real network.
final class SportGoalJourneyTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixtures"]
        app.launchEnvironment["UITEST_SCENARIO"] = scenario
        app.launch()
        return app
    }

    private func text(_ app: XCUIApplication, containing needle: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", needle)).firstMatch
    }

    /// Opens the goal hub via Home's quiet goal row.
    private func openHub(_ app: XCUIApplication) {
        let goalRow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Standing vertical jump")
        ).firstMatch
        XCTAssertTrue(goalRow.waitForExistence(timeout: 20), "Home should show the goal row")
        goalRow.tap()
    }

    // MARK: - J1 · SGP-B1 + SGP-A5

    func test_SGP_B1_createJumpGoal() {
        let app = launch(scenario: "catalogOpen")

        // Beta front door + first-tap onboarding popup (SGP-A5).
        let promo = text(app, containing: "Train for your sport")
        XCTAssertTrue(promo.waitForExistence(timeout: 20), "Promo card should show while the catalog is open")
        promo.tap()
        let skip = app.buttons["Skip — I'll find it later"]
        XCTAssertTrue(skip.waitForExistence(timeout: 10), "First tap must show the 4-slide popup")
        skip.tap()

        // Second tap goes straight to the sport list.
        XCTAssertTrue(promo.waitForExistence(timeout: 10))
        promo.tap()
        XCTAssertTrue(text(app, containing: "What do you train for?").waitForExistence(timeout: 10))
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Volleyball'")).firstMatch.tap()

        // Goal list -> start screen.
        let goal = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Standing vertical jump'")).firstMatch
        XCTAssertTrue(goal.waitForExistence(timeout: 10))
        goal.tap()
        XCTAssertTrue(text(app, containing: "How to measure").waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Start the block"].exists,
                       "No CTA before a baseline is entered — nothing is promised for free")

        // Enter a baseline by dragging the ruler; the honest target reveals.
        let ruler = app.descendants(matching: .any)["ruler-number-picker"].firstMatch
        XCTAssertTrue(ruler.waitForExistence(timeout: 5))
        ruler.swipeRight()
        XCTAssertTrue(text(app, containing: "A realistic target").waitForExistence(timeout: 5),
                      "Entering a baseline must reveal the evidence-band target")

        let start = app.buttons["Start the block"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()

        // The flow lands on the hub for the new goal.
        XCTAssertTrue(text(app, containing: "VOLLEYBALL · GOAL").waitForExistence(timeout: 15))
        XCTAssertTrue(text(app, containing: "Week 1 of 10–12").waitForExistence(timeout: 5))

        // Home now carries the quiet goal row.
        app.swipeDown(velocity: .fast)
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Standing vertical jump"))
                .firstMatch.waitForExistence(timeout: 10),
            "Home's readiness card should show the goal row after creation"
        )
    }

    // MARK: - J2 · SGP-C1 + SGP-D1

    func test_SGP_D1_completeWorkoutCountsSession() {
        let app = launch(scenario: "activeGoalWeek2")

        let cta = app.buttons["Start workout"]
        XCTAssertTrue(cta.waitForExistence(timeout: 20))
        // Referral bonus (fixture, 2099) must be in memory before the tap so
        // the detail opens without Superwall; the goal row loading proves
        // Home's task chain (which fetches the bonus first) has finished.
        _ = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Standing vertical jump'"))
            .firstMatch.waitForExistence(timeout: 20)
        cta.tap()

        // Today's restored plan carries a REAL goal_block marker -> eyebrow.
        XCTAssertTrue(text(app, containing: "GOAL BLOCK").waitForExistence(timeout: 20),
                      "Plan with a goal_block marker must show the goal eyebrow (BUG-77)")

        let complete = app.buttons["Complete workout"]
        XCTAssertTrue(complete.waitForExistence(timeout: 10))
        complete.tap()

        // Logged: the commitment CTA is gone from the sheet...
        XCTAssertTrue(text(app, containing: "logged").waitForExistence(timeout: 10)
                      || !complete.exists)
        app.swipeDown(velocity: .fast)

        // ...and Home flips to the completed state.
        XCTAssertTrue(app.buttons["Check workout details"].waitForExistence(timeout: 15),
                      "A logged goal-block day is a counted session (SGP-D1)")
    }

    // MARK: - J3 · SGP-D2

    func test_SGP_D2_missedSessionsSlideEta() {
        let app = launch(scenario: "activeGoalWeek4Slipped")
        openHub(app)

        XCTAssertTrue(text(app, containing: "Week 4 of 10–12").waitForExistence(timeout: 15))
        XCTAssertTrue(
            text(app, containing: "Moved +9 days — 2 missed sessions + 3 low-readiness days").exists,
            "Skipping never fails the goal — it slides the ETA, stated neutrally"
        )
        // The goal is alive and pausable, not failed.
        XCTAssertTrue(app.buttons["Pause goal"].exists)
    }

    // MARK: - J4 · SGP-D5 (+ SGP-D4 rest-day variant)

    func test_SGP_D5_retestOpenOnModerateDay() {
        let app = launch(scenario: "activeGoalDay28")
        openHub(app)

        let retest = app.buttons["Mid-block re-test"]
        XCTAssertTrue(retest.waitForExistence(timeout: 15),
                      "Day 28 on a moderate day opens the checkpoint re-test")
        retest.tap()

        XCTAssertTrue(text(app, containing: "Best of 3 counts").waitForExistence(timeout: 5))
        let ruler = app.descendants(matching: .any)["ruler-number-picker"].firstMatch
        XCTAssertTrue(ruler.waitForExistence(timeout: 5))
        ruler.swipeLeft()
        app.buttons["Record attempt 1"].tap()
        ruler.swipeLeft()
        app.buttons["Record attempt 2"].tap()

        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Save '")).firstMatch.tap()

        // Any honest outcome card (progress / within-noise) ends with Done.
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 10),
                      "Saving a re-test must land on a result card")
    }

    func test_SGP_D4_restDayDefersRetest() {
        let app = launch(scenario: "activeGoalDay28Rest")
        openHub(app)

        XCTAssertTrue(text(app, containing: "Not today — recovery is low.").waitForExistence(timeout: 15),
                      "A rest/light day closes the max-test window")
        XCTAssertFalse(app.buttons["Mid-block re-test"].exists)
    }
}
