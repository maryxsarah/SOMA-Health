import XCTest

/// TestFlight feedback: on the workout screen, once a generated plan is
/// showing, a drag that STARTS on the generated text does not scroll the
/// page. Reproduces against the seeded activeGoalWeek2 fixture plan.
final class GeneratedPlanScrollUITests: XCTestCase {

    private var runningApp: XCUIApplication?

    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() {
        runningApp?.terminate()
        runningApp = nil
    }

    func test_scroll_startingOnGeneratedPlanText_scrollsTheScreen() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixtures"]
        app.launchEnvironment["UITEST_SCENARIO"] = "activeGoalWeek2"
        app.launch()
        runningApp = app

        // Home's seeded "Today's AI-generated workout" card opens the
        // detail sheet with the plan already present (no generation step).
        let planCard = app.staticTexts["Lower body strength"].firstMatch
        XCTAssertTrue(planCard.waitForExistence(timeout: 30), "Home should show the seeded AI-plan card")
        // Coordinate tap: the text itself reports not-hittable inside the
        // card Button, but its on-screen point is exactly the tap target.
        planCard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        // "Front Box Jump" is the fixture plan's exercise row -- generated
        // text, the exact surface the feedback says can't be scrolled from.
        let exercise = app.staticTexts["Front Box Jump"].firstMatch
        XCTAssertTrue(exercise.waitForExistence(timeout: 10), "The detail sheet should render the generated plan")
        // Bring the plan area fully on screen first.
        app.swipeUp()

        // Reference anchor that stays on screen while we measure.
        let anchor = app.staticTexts["Lower body power"].firstMatch
        XCTAssertTrue(anchor.waitForExistence(timeout: 5))

        // Swipe DOWN starting on each surface; a working scroll moves the
        // anchor down. Compare the generated exercise row against a plain
        // (non-button) text in the same card.
        var deltas: [String: CGFloat] = [:]
        for (label, element) in [("plain-focus-text", anchor), ("exercise-row", exercise)] {
            let before = anchor.frame.midY
            element.swipeDown()
            let after = anchor.frame.midY
            deltas[label] = after - before
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "after-swipe-\(label)"
            attachment.lifetime = .keepAlways
            add(attachment)
            // Re-scroll back down so the next start element is on screen.
            app.swipeUp()
        }

        XCTAssertGreaterThan(abs(deltas["exercise-row"] ?? 0), 40,
                             "Swipe on the generated exercise row should scroll (deltas: \(deltas))")
    }
}
