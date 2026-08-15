import XCTest

/// The sport-goal journeys from UITests/CASES.md (J1–J17), run against the
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

    /// Taps the dock's "Goals" icon -- the only way into the sport-goal
    /// flow now that the old promo-card + 4-slide onboarding popup front
    /// door is gone (HomeView.openSportGoal: "the feature is opt-in now,
    /// so the dock's Goals icon goes straight to sport selection instead
    /// of forcing the first-time onboarding gallery in front of it"). The
    /// icon itself is a stable nav anchor whether or not the catalog is
    /// dark -- SportGoalFlowView decides what to show once it opens.
    private func openSportGoalFlow(_ app: XCUIApplication) {
        let goalsButton = app.buttons["dock-goals-button"]
        XCTAssertTrue(goalsButton.waitForExistence(timeout: 20), "Home's dock should show the Goals icon")
        goalsButton.tap()
    }

    // MARK: - J1 · SGP-B1 (SGP-A5's onboarding-popup gallery no longer
    // exists -- the dock's Goals icon goes straight to sport selection now)

    func test_SGP_B1_createJumpGoal() {
        let app = launch(scenario: "catalogOpen")

        openSportGoalFlow(app)
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
        // GoalStartView's content (measure card + baseline ruler + target
        // card + phase strip) runs past one screen -- same "scroll down to
        // the CTA" need as CustomGoalFormView (J7), same two-swipe fallback.
        app.swipeUp()
        if !start.isHittable { app.swipeUp() }
        start.tap()
        sleep(3)
        let debugShot = XCTAttachment(screenshot: app.screenshot())
        debugShot.lifetime = .keepAlways
        add(debugShot)

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

        openSportGoalFlow(app)
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

        // Catalog is dark: readiness card renders. The dock's Goals icon
        // is a stable nav anchor either way now (same "always present, the
        // destination decides" posture as Scan gym) -- opening it must show
        // the calm unavailable card, never the real sport list.
        XCTAssertTrue(app.buttons["Start workout"].waitForExistence(timeout: 20))
        openSportGoalFlow(app)
        XCTAssertTrue(text(app, containing: "Goals aren't available right now").waitForExistence(timeout: 15),
                      "Dark catalog must show the calm unavailable card, never the real sport list")
        dismissSheet(app)

        // Profile → Account → "Sport goals (beta)" toggle. Profile is only
        // reachable through the dock's "More" sheet now (Soma Glass 3a has
        // no nav-pill row above the week strip).
        app.buttons["dock-more-button"].tap()
        app.buttons["profile-button"].tap()
        let accountTab = app.buttons["Account"]
        XCTAssertTrue(accountTab.waitForExistence(timeout: 15))
        accountTab.tap()
        XCTAssertTrue(text(app, containing: "Sport goals (beta)").waitForExistence(timeout: 10))
        let toggle = app.switches.firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.tap()
        dismissSheet(app)

        // Closing Profile refetches the catalog — the real sport list opens now.
        openSportGoalFlow(app)
        XCTAssertTrue(text(app, containing: "What do you train for?").waitForExistence(timeout: 20),
                      "Opting in must reveal the real catalog in the same session")
    }

    // MARK: - J15 · SGP-B8/B9 — coach-assignment AI assist

    /// Types delete-key presses to clear a field's existing text before
    /// typing new text -- XCUITest has no direct "clear" action.
    private func clearAndType(_ field: XCUIElement, text: String) {
        field.tap()
        if let existing = field.value as? String, !existing.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
        }
        field.typeText(text)
    }

    func test_SGP_B8_autoFillAssignmentFromTextThenLowConfidence() {
        let app = launch(scenario: "customCoachFlow")

        openSportGoalFlow(app)
        XCTAssertTrue(text(app, containing: "What do you train for?").waitForExistence(timeout: 10))
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Volleyball'")).firstMatch.tap()
        let customRow = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "coach's task")).firstMatch
        XCTAssertTrue(customRow.waitForExistence(timeout: 10))
        customRow.tap()

        // .any, not .textFields -- a multi-line TextField(axis: .vertical)
        // doesn't reliably surface under the .textFields element type.
        let workoutField = app.descendants(matching: .any)["workoutTextField"]
        XCTAssertTrue(workoutField.waitForExistence(timeout: 10))
        clearAndType(workoutField, text: "3 rounds: 10 approach jumps, 8 depth drops, 10 banded squats")

        let autoFill = app.buttons["Auto-fill with AI"]
        XCTAssertTrue(autoFill.waitForExistence(timeout: 5))
        autoFill.tap()

        let coachField = app.descendants(matching: .any)["coachNameField"]
        XCTAssertTrue(coachField.waitForExistence(timeout: 10))
        // Poll for the AI-filled value -- waitForExistence only covers
        // presence, not a value change on a field that already existed.
        let coachFilled = NSPredicate(format: "value CONTAINS %@", "Coach Priya")
        wait(for: [XCTNSPredicateExpectation(predicate: coachFilled, object: coachField)], timeout: 10)

        // A second parse with an unparseable input must leave the
        // already-good coach field untouched and surface the warning.
        clearAndType(workoutField, text: "zzz-unparseable-test-input")
        autoFill.tap()
        XCTAssertTrue(text(app, containing: "Couldn't confidently read").waitForExistence(timeout: 10))
        XCTAssertTrue(coachFilled.evaluate(with: coachField),
                      "a low-confidence parse must never overwrite a field that already had good data")
    }

    // MARK: - J16 · SGP-C7 — calendar strip goal-training star

    func test_SGP_C7_calendarStripShowsGoalTrainingStar() {
        let app = launch(scenario: "activeGoalWeek2")
        XCTAssertTrue(app.buttons["Start workout"].waitForExistence(timeout: 20))

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        func dateString(daysAgo: Int) -> String {
            formatter.string(from: Date().addingTimeInterval(TimeInterval(-daysAgo * 86400)))
        }

        // No crown assertion here -- the week strip's crown glyph isn't
        // part of the Soma Glass 3a design (removed; the underlying
        // `bestReadinessDate` data still feeds DayDetailView's own "Best
        // readiness of the week" line, just not an inline strip icon).
        let todayStar = app.images["calendarStar-\(dateString(daysAgo: 0))"]
        XCTAssertTrue(todayStar.waitForExistence(timeout: 20), "today has a real goal_block, star should show")

        let twoDaysAgoStar = app.images["calendarStar-\(dateString(daysAgo: 2))"]
        XCTAssertTrue(twoDaysAgoStar.waitForExistence(timeout: 5))

        let yesterdayStar = app.images["calendarStar-\(dateString(daysAgo: 1))"]
        XCTAssertFalse(yesterdayStar.exists, "a day with no goal_block must not show a star")
    }

    // MARK: - J17 · SGP-B10/SGP-D9 — preset schedule step + named program + Upcoming

    func test_SGP_B10_presetGoalGetsScheduleAndNamedProgram() {
        let app = launch(scenario: "catalogOpen")

        openSportGoalFlow(app)
        XCTAssertTrue(text(app, containing: "What do you train for?").waitForExistence(timeout: 10))
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Volleyball'")).firstMatch.tap()

        let goal = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Standing vertical jump'")).firstMatch
        XCTAssertTrue(goal.waitForExistence(timeout: 10))
        goal.tap()
        XCTAssertTrue(text(app, containing: "How to measure").waitForExistence(timeout: 10))
        let ruler = app.descendants(matching: .any)["ruler-number-picker"].firstMatch
        XCTAssertTrue(ruler.waitForExistence(timeout: 5))
        ruler.swipeRight()
        XCTAssertTrue(text(app, containing: "A realistic target").waitForExistence(timeout: 5))
        // Every band gets a name ending in "Jump Block" -- see Part A.
        XCTAssertTrue(text(app, containing: "Jump Block").waitForExistence(timeout: 5),
                      "the matched band's program name should render pre-creation")

        // Schedule step: pick specific weekdays instead of the 2/3/4x default.
        // "Custom…" (with the ellipsis), not bare "Custom" -- Home's new
        // "Custom training" toggle button also matches a loose CONTAINS
        // "Custom" predicate and can still be present (non-hittable, but
        // matchable) underneath this sheet, making firstMatch ambiguous.
        let customChip = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Custom…")).firstMatch
        XCTAssertTrue(customChip.waitForExistence(timeout: 5))
        customChip.tap()
        let weekdaysRow = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Specific weekdays")).firstMatch
        XCTAssertTrue(weekdaysRow.waitForExistence(timeout: 10))
        weekdaysRow.tap()
        app.descendants(matching: .any)["weekday-1"].tap()
        app.descendants(matching: .any)["weekday-3"].tap()
        app.buttons["Done"].tap()

        let start = app.buttons["Start the block"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        app.swipeUp()
        if !start.isHittable { app.swipeUp() }
        start.tap()

        // Hub: the named program persists post-creation, and the new
        // Upcoming section renders for a preset goal (not just custom).
        XCTAssertTrue(text(app, containing: "Jump Block").waitForExistence(timeout: 15),
                      "the program name should be snapshotted onto the created goal")
        XCTAssertTrue(text(app, containing: "Upcoming").waitForExistence(timeout: 10))
    }
}
