import XCTest

/// Drives the full onboarding cycle (Welcome -> email sign-up -> the
/// ~22-step survey -> Connect Devices -> Notifications -> PostSetup) for
/// the demo-video recording, logging every tap's on-screen position and
/// timestamp so a post-process step can burn in click indicators, and
/// every screen's visible text so the narration script can be written
/// from what actually happened, not from memory.
///
/// Requires `UITestSupport.isOnboardingDemo` (`--ui-test-onboarding-demo`)
/// so the app boots into the real `OnboardingView` with a stubbed network
/// instead of the other UI tests' signed-in-Home shortcut -- see
/// `Soma/Services/UITestSupport.swift`.
final class OnboardingDemoRecordingTests: XCTestCase {
    struct StepEvent: Codable {
        let t: Double
        let x: Double?
        let y: Double?
        let label: String
        let screenTexts: [String]
    }

    private static var events: [StepEvent] = []
    private static var startTime = Date()
    private static let logPath =
        FileManager.default.temporaryDirectory.appendingPathComponent("onboarding-demo-taps.json").path

    override func setUpWithError() throws {
        continueAfterFailure = true
        Self.events = []
        Self.startTime = Date()
        // This test has repeatedly hit XCTest's own "restarting after
        // unexpected exit, crash, or test timeout" in-process retry on this
        // Mac -- which reruns test_recordFullOnboarding WITHOUT a fresh
        // process, so these one-shot "handled" flags must be reset here too
        // or a restarted pass silently skips them (looks like "nothing
        // happened" even though the code ran before the earlier crash).
        Self.desiredWeightHandled = false
        Self.workoutFrequencyHandled = false
        Self.healthConnectAttempted = false
    }

    func test_recordFullOnboarding() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-onboarding-demo"]

        // HealthKit/notifications both raise a real system alert -- auto
        // -allow so the recording never sits on a system sheet.
        addUIInterruptionMonitor(withDescription: "System permission dialogs") { alert in
            for label in ["Allow", "Allow While Using App", "Allow Once", "OK", "Turn On"] {
                let button = alert.buttons[label]
                if button.exists {
                    button.tap()
                    return true
                }
            }
            return false
        }

        Self.startTime = Date()
        app.launch()
        record(app, label: "App launch -- Welcome")

        tapAndLog(app.buttons["Continue with Email"], app: app, label: "Tap \u{201C}Continue with Email\u{201D}")

        // Credentials + Log In mode arrive pre-set in demo mode
        // (EmailAuthView's own doc comment: this simulator/XCTest combo
        // can't reliably deliver synthesized taps to this screen's
        // controls -- reproduced even after a full `simctl erase`, and a
        // retry loop on the mode toggle didn't help either). Record the
        // reveal, then just proceed straight to submit. Both the segmented
        // tab and the submit CTA are labeled "Log In" -- disambiguate by
        // frame position (submit button sits lower on screen) rather than
        // element ordering.
        let emailField = app.textFields["Email"]
        if emailField.waitForExistence(timeout: 5) {
            record(app, label: "Email/password pre-filled, Log In mode")
            let logInMatches = app.buttons.matching(NSPredicate(format: "label == 'Log In'")).allElementsBoundByIndex
            if let submitButton = logInMatches.max(by: { $0.frame.midY < $1.frame.midY }) {
                tapAndLog(submitButton, app: app, label: "Tap \u{201C}Log In\u{201D} (submit)")
            }
        }

        driveUntilHome(app)
        writeLog()
    }

    // MARK: - Generic driver

    /// Steps through whatever screen is on-screen without hardcoding every
    /// one of the ~30 onboarding steps: pick the first selectable option
    /// if one exists, then tap the most likely primary CTA. Text fields
    /// (blockers notes, anchor session name) are left blank -- both are
    /// optional (their `PillButton(title: "Continue", ...)` carries no
    /// `isEnabled` gate), and typing into them hits the same simulator
    /// focus issue `EmailAuthView`'s doc comment describes. Bails after 80
    /// steps or a screen with no tappable next-action, whichever first.
    private func driveUntilHome(_ app: XCUIApplication) {
        let homeMarker = app.descendants(matching: .any)["dock-more-button"]
        var stepCount = 0

        while !homeMarker.exists, stepCount < 80 {
            stepCount += 1
            handleConnectDevicesIfPresent(app)
            handleDesiredWeightIfPresent(app)
            record(app, label: "Screen \(stepCount)")

            if !handleWorkoutFrequencyIfPresent(app) {
                let optionButtons = app.scrollViews.buttons
                if optionButtons.count > 0, optionButtons.element(boundBy: 0).isHittable {
                    tapAndLog(optionButtons.element(boundBy: 0), app: app, label: "Pick first option")
                }
            }

            if !tapPrimaryCTA(app) { break }
            usleep(500_000)
        }

        if homeMarker.waitForExistence(timeout: 15) {
            record(app, label: "Arrived at Home")
        }
    }

    private static var desiredWeightHandled = false

    /// `WeightQuestionView`'s desired-weight step defaults to the SAME
    /// value as current weight (`answers.desiredWeightKg ?? answers.weightKg
    /// ?? 70`) -- the generic "pick first option, tap Continue" driver never
    /// touches the drag-based `WeightScalePicker` (no buttons to pick), so
    /// desired == current, a zero delta. `GoalJourneyProgress` then reads
    /// "delta too small" and several downstream screens (progress bar, plan
    /// summary) render their empty/no-estimate state instead of real
    /// content.
    ///
    /// First attempt (text-relative offset, 0.05s press) never registered
    /// at all -- confirmed live via extracted video frames + the "70.0"
    /// weight text unchanged in the post-drag screenshot; a bare touch-down
    /// that brief likely never gave SwiftUI's `DragGesture` a real "began"
    /// event before the drag-to fired. This version presses longer first,
    /// uses whole-app-frame-relative coordinates (screen-center-ish,
    /// sidestepping any text-frame-offset math), and logs the actual
    /// before/after weight text so a future run can verify from the JSON
    /// log alone. Rightward translation decreases the value (see
    /// WeightScalePicker.swift's own `newValue = dragStartWeight - delta`).
    private func handleDesiredWeightIfPresent(_ app: XCUIApplication) {
        guard !Self.desiredWeightHandled else { return }
        guard app.staticTexts["What's your desired weight?"].exists else { return }
        Self.desiredWeightHandled = true
        let before = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", #"^\d+\.\d$"#)).firstMatch.label
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        start.press(forDuration: 0.4, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        usleep(400_000)
        let after = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", #"^\d+\.\d$"#)).firstMatch.label
        logNonTap(label: "Dragged desired-weight scale: \(before) -> \(after)")
    }

    /// `SingleSelectQuestionView`'s "How many workouts do you do per week?"
    /// step -- the generic driver's "pick first option" would select the
    /// sparsest choice (0-2), which leads to thin/empty-looking workout
    /// suggestions and plan content on later screens. Pick the middle
    /// option (3-5) instead. Returns true if it handled (and logged) the
    /// tap, so the caller skips its own generic "pick first option" step.
    private static var workoutFrequencyHandled = false

    private func handleWorkoutFrequencyIfPresent(_ app: XCUIApplication) -> Bool {
        guard !Self.workoutFrequencyHandled else { return false }
        guard app.staticTexts["How many workouts do you do per week?"].exists else { return false }
        Self.workoutFrequencyHandled = true
        let options = app.scrollViews.buttons
        guard options.count > 1, options.element(boundBy: 1).isHittable else { return false }
        tapAndLog(options.element(boundBy: 1), app: app, label: "Pick \u{201C}3\u{2013}5\u{201D} workouts")
        return true
    }

    private static var healthConnectAttempted = false

    /// Apple Health's real HealthKit consent sheet doesn't reliably show
    /// in this simulator (confirmed by direct testing: no in-app or
    /// system UI appears at all after `requestAuthorization()`, even with
    /// the HealthKit entitlement present) -- `HealthKitManager.isAuthorized()`
    /// has a demo-only bypass for exactly this reason (see its doc
    /// comment). Tap "Connect" once for the visual beat; Continue clears
    /// on its own once that bypass reports authorized on the next
    /// `AppState.refreshConnectedProviders()`. Whoop/Oura are OAuth
    /// webviews with no fixture-able backend, so the demo only ever
    /// attempts Apple Health.
    private func handleConnectDevicesIfPresent(_ app: XCUIApplication) {
        guard !Self.healthConnectAttempted else { return }
        let appleHealthLabel = app.staticTexts["Apple Health"]
        guard appleHealthLabel.exists else { return }
        let connectButtons = app.buttons.matching(NSPredicate(format: "label == %@", "Connect")).allElementsBoundByIndex
        guard !connectButtons.isEmpty else { return }
        // `element(boundBy: 0)` on the raw match set is NOT guaranteed to be
        // Apple Health's row -- Whoop/Oura also show a "Connect" button with
        // the identical label before they're connected, and this previously
        // tapped whichever one happened to enumerate first (confirmed live:
        // opened a real api.prod.whoop.com OAuth webview instead). Pick the
        // "Connect" button whose row sits closest, vertically, to the
        // "Apple Health" text itself.
        let targetY = appleHealthLabel.frame.midY
        guard let appleHealthConnect = connectButtons.min(by: { abs($0.frame.midY - targetY) < abs($1.frame.midY - targetY) }) else { return }
        Self.healthConnectAttempted = true
        tapAndLog(appleHealthConnect, app: app, label: "Tap \u{201C}Connect\u{201D} (Apple Health)")
        sleep(2)
    }

    private func tapPrimaryCTA(_ app: XCUIApplication) -> Bool {
        let candidates = [
            "Continue", "Yes", "No", "Done", "Next", "Allow", "Not Now", "Skip",
            "Get Started", "Save", "Maybe Later", "Continue with limited access",
        ]
        for label in candidates {
            let button = app.buttons[label]
            if button.exists, button.isHittable, button.isEnabled {
                tapAndLog(button, app: app, label: "Tap \u{201C}\(label)\u{201D}")
                return true
            }
        }
        // Never fall through onto a provider row's own action -- "Connect"
        // is Whoop/Oura (OAuth webviews with no fixture backend, see
        // handleConnectDevicesIfPresent) and "Manage" is Apple Health once
        // already connected; both would otherwise look like a plausible
        // "last enabled button" on the Connect Devices screen while
        // Continue is still disabled/settling.
        let excluded: Set<String> = ["Connect", "Manage"]
        if let last = app.buttons.allElementsBoundByIndex.last(where: { $0.isHittable && $0.isEnabled && !excluded.contains($0.label) }) {
            tapAndLog(last, app: app, label: "Tap \u{201C}\(last.label)\u{201D}")
            return true
        }
        return false
    }

    // MARK: - Logging

    private func tapAndLog(_ element: XCUIElement, app: XCUIApplication, label: String) {
        guard element.waitForExistence(timeout: 5) else { return }
        let frame = element.frame
        Self.events.append(StepEvent(
            t: Date().timeIntervalSince(Self.startTime),
            x: frame.midX, y: frame.midY,
            label: label,
            screenTexts: Array(app.staticTexts.allElementsBoundByIndex.prefix(4).map(\.label))
        ))
        writeLog()
        element.tap()
    }

    private func record(_ app: XCUIApplication, label: String) {
        Self.events.append(StepEvent(
            t: Date().timeIntervalSince(Self.startTime),
            x: nil, y: nil,
            label: label,
            screenTexts: Array(app.staticTexts.allElementsBoundByIndex.prefix(5).map(\.label))
        ))
        writeLog()
    }

    private func logNonTap(label: String) {
        Self.events.append(StepEvent(t: Date().timeIntervalSince(Self.startTime), x: nil, y: nil, label: label, screenTexts: []))
        writeLog()
    }

    /// Rewritten after every event (not just at the end) so a crash or
    /// hang mid-recording still leaves a usable partial log.
    private func writeLog() {
        guard let data = try? JSONEncoder().encode(Self.events) else { return }
        try? data.write(to: URL(fileURLWithPath: Self.logPath))
    }
}
