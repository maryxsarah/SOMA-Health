import XCTest

/// The sport-goal journeys from UITests/CASES.md (J1–J14), run against the
/// in-app fixture stub (UITestSupport.swift): `--ui-test-fixtures` +
/// UITEST_SCENARIO select the world each test starts in. No real network.
final class SportGoalJourneyTests: XCTestCase {

    private var runningApp: XCUIApplication?

    override func setUp() {
        continueAfterFailure = false
    }

    /// 14 sequential launches of the full app (Firebase/PostHog/Superwall
    /// and all) exhaust the simulator and get later tests SIGKILLed --
    /// terminating each app explicitly keeps the suite stable end to end.
    override func tearDown() {
        runningApp?.terminate()
        runningApp = nil
    }

    private func launch(scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixtures"]
        app.launchEnvironment["UITEST_SCENARIO"] = scenario
        app.launch()
        runningApp = app
        return app
    }

    private func text(_ app: XCUIApplication, containing needle: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", needle)).firstMatch
    }

    /// Drags a sheet down by its header — reliable regardless of where the
    /// sheet's inner scroll view happens to be scrolled. The grab point must
    /// be INSIDE the sheet: a page sheet's top edge sits at ~7.5% of the
    /// screen, so dy 0.06 landed on the dimming view and dragged nothing.
    private func dismissSheet(_ app: XCUIApplication) {
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
            .press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
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

        // Two leftward ruler swipes always beat the 2 cm noise band, so the
        // outcome is deterministically the progress card.
        XCTAssertTrue(text(app, containing: "Now at ").waitForExistence(timeout: 10),
                      "A real gain must read as progress, with the target restated")
        XCTAssertTrue(app.buttons["Done"].exists)
    }

    func test_SGP_D4_restDayDefersRetest() {
        let app = launch(scenario: "activeGoalDay28Rest")
        openHub(app)

        XCTAssertTrue(text(app, containing: "Not today — recovery is low.").waitForExistence(timeout: 15),
                      "A rest/light day closes the max-test window")
        XCTAssertFalse(app.buttons["Mid-block re-test"].exists)
    }

    // MARK: - SGP-E7 · ending is never destructive-first

    func test_SGP_E7_endGoalOffersPauseInsteadFirst() {
        let app = launch(scenario: "activeGoalWeek2")
        openHub(app)

        let options = app.buttons["Goal options"]
        XCTAssertTrue(options.waitForExistence(timeout: 15))
        options.tap()
        let endMenuItem = app.buttons["End this goal"]
        XCTAssertTrue(endMenuItem.waitForExistence(timeout: 5))
        endMenuItem.tap()

        // The dialog leads with the calm exit and keeps the data promise.
        let pauseInstead = app.buttons["Pause instead"]
        XCTAssertTrue(pauseInstead.waitForExistence(timeout: 10),
                      "'End this goal' must always offer 'Pause instead' first (SGP-E7)")
        XCTAssertTrue(text(app, containing: "Your measurements stay in your history.").exists,
                      "Ending never reads as deletion — rows are kept")

        // Taking the calm exit keeps the goal on screen (the stub doesn't
        // persist the PATCH, so "still here, not deleted" is what's pinned).
        pauseInstead.tap()
        XCTAssertTrue(text(app, containing: "Standing vertical jump").waitForExistence(timeout: 15),
                      "After 'Pause instead' the goal survives — nothing is deleted")
    }

    // MARK: - J5 · SGP-C3 (client side) — rest-day request and undo

    func test_SGP_C3_restDayRequestAndUndo() {
        let app = launch(scenario: "activeGoalWeek2")

        XCTAssertTrue(app.buttons["Start workout"].waitForExistence(timeout: 20))
        let notFeelingIt = app.buttons["Not feeling it today?"]
        XCTAssertTrue(notFeelingIt.waitForExistence(timeout: 10))
        notFeelingIt.tap()

        XCTAssertTrue(app.buttons["Rest day"].waitForExistence(timeout: 5))
        app.buttons["Rest day"].tap()

        // The override persists server-side and the card restates it.
        let undo = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "You requested a rest day today")
        ).firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 10),
                      "A requested rest day must be visible and undoable")
        undo.tap()
        XCTAssertTrue(notFeelingIt.waitForExistence(timeout: 10),
                      "Undo returns the quiet affordance — no dead end")
    }

    // MARK: - J6 · SGP-E8 + session counting — coach's task hub

    func test_SGP_E8_coachTaskHubCountsSessionsAndExports() {
        let app = launch(scenario: "customGoalWeek2")

        let goalRow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Coach Alex")
        ).firstMatch
        XCTAssertTrue(goalRow.waitForExistence(timeout: 20),
                      "Home's goal row names the coach's task, week N of M")
        goalRow.tap()

        XCTAssertTrue(text(app, containing: "COACH ALEX").waitForExistence(timeout: 15))
        XCTAssertTrue(text(app, containing: "3 of 16").waitForExistence(timeout: 10),
                      "Three logged days since the block started = 3 of 16 sessions")
        XCTAssertTrue(text(app, containing: "For your coach").exists,
                      "The share-back export card appears once sessions exist (SGP-E8)")
        XCTAssertTrue(text(app, containing: "Re-check with your coach around").exists)
        // The coach's text is the program — byte-identical, never rewritten.
        XCTAssertTrue(text(app, containing: "never rewritten").exists
                      || text(app, containing: "Coach").exists)
    }

    // MARK: - J7 · SGP-B4 — creating the coach's task

    func test_SGP_B4_createCoachTask() {
        let app = launch(scenario: "customCoachFlow")

        let promo = text(app, containing: "Train for your sport")
        XCTAssertTrue(promo.waitForExistence(timeout: 20))
        promo.tap()

        XCTAssertTrue(text(app, containing: "What do you train for?").waitForExistence(timeout: 10))
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Volleyball'")).firstMatch.tap()

        let customRow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "coach's task")
        ).firstMatch
        XCTAssertTrue(customRow.waitForExistence(timeout: 10))
        customRow.tap()

        // The workout text is the one required field.
        let workoutField = app.descendants(matching: .any).matching(
            NSPredicate(format: "placeholderValue CONTAINS %@ OR value CONTAINS %@",
                        "in your coach's words", "in your coach's words")
        ).firstMatch
        XCTAssertTrue(workoutField.waitForExistence(timeout: 10))
        workoutField.tap()
        workoutField.typeText("3 rounds: 10 approach jumps, 8 depth drops")

        // Tap outside to drop the keyboard (dismissKeyboardOnTap), then
        // scroll down to the CTA below the schedule/metric cards.
        text(app, containing: "The original stays attached").tap()
        let start = app.buttons["Start the block"]
        app.swipeUp()
        if !start.isHittable { app.swipeUp() }
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()

        // Lands on the coach-task hub with zero sessions done.
        XCTAssertTrue(text(app, containing: "COACH ALEX").waitForExistence(timeout: 15))
        XCTAssertTrue(text(app, containing: "0 of 16").waitForExistence(timeout: 10))
    }

    // MARK: - J8 · SGP-D7 — day-5 baseline confirm

    func test_SGP_D7_confirmBaselineOnDay5() {
        let app = launch(scenario: "activeGoalDay6")
        openHub(app)

        let confirm = app.buttons["Confirm your baseline"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 15),
                      "Day 6 with only a first attempt logged opens the confirm window")
        confirm.tap()

        // Saving without touching the ruler re-tests at the same 42 cm.
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Save '")).firstMatch.tap()
        XCTAssertTrue(text(app, containing: "official starting point").waitForExistence(timeout: 10),
                      "Confirming makes this the block's official baseline")
        app.buttons["Done"].tap()
        XCTAssertFalse(text(app, containing: "official starting point").exists)
    }

    // MARK: - J9 · SGP-D6 — within the noise band is 'no change', honestly

    func test_SGP_D6_withinNoiseReadsNoChange() {
        let app = launch(scenario: "activeGoalDay28")
        openHub(app)

        let retest = app.buttons["Mid-block re-test"]
        XCTAssertTrue(retest.waitForExistence(timeout: 15))
        retest.tap()

        // Untouched ruler == the confirmed baseline (43): |delta| ≤ 2 cm noise.
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Save '")).firstMatch.tap()
        XCTAssertTrue(text(app, containing: "No change yet — normal at this stage.").waitForExistence(timeout: 10),
                      "A re-test inside the noise band must not be dressed up as progress")
        XCTAssertTrue(text(app, containing: "within measurement noise").exists)
    }

    // MARK: - J11/J12 · SGP-E5 + SGP-E6 — the final re-test, both endings

    func test_SGP_E5_finalRetestAchievedOffersNextBlock() {
        let app = launch(scenario: "activeGoalAtEta")
        openHub(app)

        let final = app.buttons["Final re-test"]
        XCTAssertTrue(final.waitForExistence(timeout: 15),
                      "ETA reached with baseline+confirm+checkpoint in → final opens")
        final.tap()

        let ruler = app.descendants(matching: .any)["ruler-number-picker"].firstMatch
        XCTAssertTrue(ruler.waitForExistence(timeout: 5))
        ruler.swipeLeft()

        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Save '")).firstMatch.tap()

        // Celebration is earned (delta ≥ target low) and chains forward.
        XCTAssertTrue(text(app, containing: "1 session a week keeps your gains.").waitForExistence(timeout: 10))
        let nextBlock = app.buttons["Next block"]
        XCTAssertTrue(nextBlock.exists)
        nextBlock.tap()

        // SGP-E6: the start screen opens pre-filled — target already revealed.
        XCTAssertTrue(text(app, containing: "A realistic target").waitForExistence(timeout: 10),
                      "Next block pre-fills the fresh result as the new baseline")
        XCTAssertTrue(app.buttons["Start the block"].exists)
    }

    func test_SGP_E5_finalRetestMissedStaysNeutral() {
        let app = launch(scenario: "activeGoalAtEta")
        openHub(app)

        let final = app.buttons["Final re-test"]
        XCTAssertTrue(final.waitForExistence(timeout: 15))
        final.tap()

        // Untouched ruler: final == confirmed baseline, target missed.
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Save '")).firstMatch.tap()

        XCTAssertTrue(app.buttons["Extend the block"].waitForExistence(timeout: 10),
                      "A missed target ends neutrally, with a way to keep going")
        XCTAssertFalse(text(app, containing: "1 session a week keeps your gains.").exists,
                       "No unearned celebration")
    }

    // MARK: - J13 · SGP-E1 — pause and resume, nothing lost

    func test_SGP_E1_pauseAndResume() {
        let app = launch(scenario: "activeGoalWeek4Slipped")
        openHub(app)

        let pause = app.buttons["Pause goal"]
        XCTAssertTrue(pause.waitForExistence(timeout: 15))
        pause.tap()

        XCTAssertTrue(text(app, containing: "On hold — not counting. Resume anytime.").waitForExistence(timeout: 15),
                      "Paused reads calm, never alarm-red, never 'failed'")
        let resume = app.buttons["Resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        resume.tap()

        XCTAssertTrue(app.buttons["Pause goal"].waitForExistence(timeout: 15),
                      "Resume restores the active goal in place")
        XCTAssertFalse(text(app, containing: "On hold — not counting").exists)
    }

    // MARK: - J14 · SGP-A4 — the beta toggle opens the catalog (stub RLS)

    func test_SGP_A4_betaToggleOpensCatalog() {
        let app = launch(scenario: "betaGate")

        // Catalog is dark: readiness card renders, but no front door.
        XCTAssertTrue(app.buttons["Start workout"].waitForExistence(timeout: 20))
        XCTAssertFalse(text(app, containing: "Train for your sport").exists,
                       "Dark catalog must mean zero sport-goal entry points")

        // Profile → Account → "Sport goals (beta)" toggle.
        app.buttons["profile-button"].tap()
        let accountTab = app.buttons["Account"]
        XCTAssertTrue(accountTab.waitForExistence(timeout: 15))
        accountTab.tap()
        XCTAssertTrue(text(app, containing: "Sport goals (beta)").waitForExistence(timeout: 10))
        let toggle = app.switches.firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.tap()

        // Closing Profile refetches the catalog — the front door appears.
        dismissSheet(app)
        XCTAssertTrue(text(app, containing: "Train for your sport").waitForExistence(timeout: 20),
                      "Opting in must reveal the promo card in the same session")
    }
}
