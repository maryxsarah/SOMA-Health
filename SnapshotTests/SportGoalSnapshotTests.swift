import SnapshotTesting
import SwiftUI
import XCTest
@testable import Soma

/// Screen-state coverage for the sport-goals feature -- one test per state
/// in UITests/CASES.md (SGP-A1/A2, B2/B3, D3/D4/D7/D8, E1..E5). Reference
/// PNGs are recorded on iPhone 17 Pro / iOS 26.5 (scripts/test.sh snapshot).
///
/// Models are built by decoding wire-shaped JSON -- the feature's structs
/// only have `init(from:)`, and this keeps fixtures honest about what the
/// server actually sends.
@MainActor
final class SportGoalSnapshotTests: XCTestCase {

    private var record: Bool {
        ProcessInfo.processInfo.environment["SNAPSHOT_RECORD"] == "1"
    }

    override func setUpWithError() throws {
        // References are device+OS-pinned; a mismatched simulator would
        // "fail" 20 snapshots that are actually fine.
        try XCTSkipUnless(
            UIDevice.current.systemVersion.hasPrefix("26.5"),
            "Snapshots are pinned to iOS 26.5 (iPhone 17 Pro) — run via scripts/test.sh snapshot"
        )
    }

    // MARK: - JSON helpers

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private func iso(daysAgo: Int) -> String {
        ISO8601DateFormatter().string(from: Date().addingTimeInterval(TimeInterval(-daysAgo * 86400)))
    }

    private func day(fromNow days: Int) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f.string(from: Date().addingTimeInterval(TimeInterval(days * 86400)))
    }

    // MARK: - Fixtures

    private func jumpGoal(targetTable: String = """
        {"bands": {"novice": {"min": 10, "max": 55, "gain_low": 3, "gain_high": 6,
                              "horizon_weeks_low": 10, "horizon_weeks_high": 12},
                   "intermediate": {"min": 55, "max": 75, "gain_low": 2, "gain_high": 4,
                                    "horizon_weeks_low": 10, "horizon_weeks_high": 12}}}
        """) throws -> SportGoal {
        try decode(SportGoal.self, """
        {"id": "g-vjump", "sport_id": "sp-volleyball", "key": "standing_vertical_jump",
         "name": "Standing vertical jump", "kind": "metric", "unit": "cm", "noise_band": 2,
         "measurement_protocol": "Chalk your fingertips and stand side-on to a wall\\nReach up flat-footed and mark your standing reach\\nJump from a standstill and mark the highest touch",
         "target_table": \(targetTable)}
        """)
    }

    private func crowGoal() throws -> SportGoal {
        try decode(SportGoal.self, """
        {"id": "g-crow", "sport_id": "sp-yoga", "key": "crow_pose",
         "name": "Crow pose", "kind": "milestone", "unit": "seconds",
         "measurement_protocol": "Warm wrists first\\nSquat, knees onto upper arms\\nShift weight forward and lift",
         "target_table": {"ladder": ["never_tried", "feet_lift", "hold_3s", "hold_seconds"],
                          "bands": {"novice": {"horizon_weeks_low": 2, "horizon_weeks_high": 8}}}}
        """)
    }

    private func catalog() throws -> SportCatalog {
        let sport = try decode(Sport.self, #"{"id": "sp-volleyball", "name": "Volleyball"}"#)
        let yoga = try decode(Sport.self, #"{"id": "sp-yoga", "name": "Hot Yoga"}"#)
        return SportCatalog(sports: [sport, yoga], goals: [try jumpGoal(), try crowGoal()])
    }

    private func userGoal(
        ageDays: Int,
        status: String = "active",
        pauseReason: String? = nil,
        slipDays: Int? = nil,
        slipReason: String? = nil,
        goalID: String = "g-vjump",
        baselineStage: String? = nil
    ) throws -> UserGoal {
        var fields = [
            "\"id\": \"ug-1\"",
            "\"goal_id\": \"\(goalID)\"",
            "\"kind\": \"preset\"",
            "\"target_kind\": \"metric\"",
            "\"status\": \"\(status)\"",
            "\"baseline_value\": 42",
            "\"target_low\": 3",
            "\"target_high\": 6",
            "\"created_at\": \"\(iso(daysAgo: ageDays))\"",
            "\"eta_start\": \"\(day(fromNow: 70 - ageDays))\"",
            "\"eta_end\": \"\(day(fromNow: 84 - ageDays))\"",
            "\"phase\": \"\(ageDays > 21 ? "build" : "foundation")\"",
        ]
        if let pauseReason { fields.append("\"pause_reason\": \"\(pauseReason)\"") }
        if let slipDays { fields.append("\"eta_slip_days\": \(slipDays)") }
        if let slipReason { fields.append("\"eta_slip_reason\": \"\(slipReason)\"") }
        if let baselineStage { fields.append("\"baseline_stage\": \"\(baselineStage)\"") }
        return try decode(UserGoal.self, "{\(fields.joined(separator: ", "))}")
    }

    private func measurement(_ id: String, kind: String, value: Double, daysAgo: Int) throws -> GoalMeasurement {
        try decode(GoalMeasurement.self, """
        {"id": "\(id)", "user_goal_id": "ug-1", "kind": "\(kind)",
         "value": \(value), "measured_at": "\(iso(daysAgo: daysAgo))"}
        """)
    }

    private func appState(recommendationCategory: String?) throws -> AppState {
        let state = AppState()
        if let recommendationCategory {
            state.currentRecommendation = try decode(DailyRecommendation.self, """
            {"date": "\(day(fromNow: 0))", "category": "\(recommendationCategory)",
             "message": "Solid day.", "reason": "healthkit_medium",
             "sleep_cap_applied": false, "injury_cap_applied": false, "load_cap_applied": false}
            """)
        }
        return state
    }

    // MARK: - Snapshot helpers

    private func snapshotHub(
        _ goal: UserGoal,
        catalog: SportCatalog,
        measurements: [GoalMeasurement],
        readiness: String?,
        height: CGFloat = 1200,
        named name: String,
        file: StaticString = #filePath,
        testName: String = #function
    ) throws {
        let view = GoalHubView(
            goal: goal,
            catalog: catalog,
            history: [],
            onChanged: {},
            onPickNewGoal: {},
            onNextBlock: { _, _ in },
            seedMeasurements: measurements
        )
        .environmentObject(try appState(recommendationCategory: readiness))
        .somaBackground()
        .environment(\.colorScheme, .light)

        assertSnapshot(
            of: view,
            as: .image(layout: .fixed(width: 393, height: height), traits: .init(displayScale: 2)),
            named: name,
            record: record,
            file: file,
            testName: testName
        )
    }

    private func snapshotView(
        _ view: some View,
        height: CGFloat = 1200,
        named name: String,
        file: StaticString = #filePath,
        testName: String = #function
    ) {
        assertSnapshot(
            of: view.environment(\.colorScheme, .light),
            as: .image(layout: .fixed(width: 393, height: height), traits: .init(displayScale: 2)),
            named: name,
            record: record,
            file: file,
            testName: testName
        )
    }

    // MARK: - A. Discovery

    func test_SGP_A1_darkCatalogShowsCalmUnavailableCard() throws {
        snapshotView(
            SportGoalFlowView(seedCatalog: SportCatalog()).environmentObject(try appState(recommendationCategory: nil)),
            height: 500,
            named: "flow-dark-catalog"
        )
    }

    func test_SGP_A2_catalogLoadFailureAsksForRetry() throws {
        snapshotView(
            SportGoalFlowView(seedLoadFailed: true).environmentObject(try appState(recommendationCategory: nil)),
            height: 500,
            named: "flow-load-failed"
        )
    }

    func test_SGP_A5_betaOnboardingSlideOneFitsItsCopy() {
        // Regression: the fixed gallery height truncated slide 1's subtitle
        // to "…or anytime via P…" (BUG-82).
        snapshotView(
            SportGoalOnboardingView(onPickGoal: {}, onClose: {}),
            height: 620,
            named: "beta-onboarding-slide1"
        )
    }

    // MARK: - B. Creation

    func test_SGP_B2_milestoneStartUsesStagesNotNumbers() throws {
        let goal = try crowGoal()
        let sport = try catalog().sports.last
        let view = NavigationStack {
            GoalStartView(goal: goal, sport: sport, seedStage: "feet_lift") {}
                .somaBackground()
        }
        snapshotView(view, named: "start-milestone-crow")
    }

    func test_SGP_B3_baselineOutsideEveryBandPromisesNothing() throws {
        let bandless = try jumpGoal(targetTable: "{}")
        let sport = try catalog().sports.first
        let view = NavigationStack {
            GoalStartView(goal: bandless, sport: sport, prefillBaseline: 42) {}
                .somaBackground()
        }
        snapshotView(view, named: "start-baseline-recorded-no-promise")
    }

    func test_SGP_B1_metricStartRevealsHonestTarget() throws {
        let goal = try jumpGoal()
        let sport = try catalog().sports.first
        let view = NavigationStack {
            GoalStartView(goal: goal, sport: sport, prefillBaseline: 42) {}
                .somaBackground()
        }
        snapshotView(view, named: "start-metric-target-reveal")
    }

    func test_SGP_B4_customCoachFormStartsEmpty() throws {
        let sport = try decode(Sport.self, #"{"id": "sp-volleyball", "name": "Volleyball"}"#)
        let view = NavigationStack {
            CustomGoalFormView(sport: sport) {}
                .somaBackground()
        }
        snapshotView(view, height: 1500, named: "custom-form-empty")
    }

    func test_SGP_B7_safetyConflictRequiresExplicitAcknowledgment() throws {
        // Both wire shapes: a bare string and the pregnancy-flagged object.
        let conflicts = [
            try decode(GoalSafetyConflict.self, #""Depth jumps may conflict with your noted knee injury.""#),
            try decode(GoalSafetyConflict.self, #"{"message": "High-impact plyometrics aren't recommended during pregnancy.", "pregnancy": true}"#),
        ]
        snapshotView(
            GoalConflictWarningView(conflicts: conflicts, onAcknowledge: {})
                .padding(20)
                .somaBackground(),
            height: 420,
            named: "create-safety-conflicts"
        )
    }

    // MARK: - D. Progress & re-test

    func test_SGP_D7_week1ConfirmBaselineOpen() throws {
        try snapshotHub(
            userGoal(ageDays: 6),
            catalog: catalog(),
            measurements: [measurement("m-1", kind: "baseline", value: 42, daysAgo: 6)],
            readiness: "moderate",
            named: "hub-week1-confirm-open"
        )
    }

    func test_SGP_D3_checkpointLockedBetweenEvents() throws {
        try snapshotHub(
            userGoal(ageDays: 10),
            catalog: catalog(),
            measurements: [
                measurement("m-1", kind: "baseline", value: 42, daysAgo: 10),
                measurement("m-2", kind: "baseline_confirm", value: 43, daysAgo: 5),
            ],
            readiness: "moderate",
            named: "hub-checkpoint-locked"
        )
    }

    func test_SGP_D4_lowReadinessDefersMaxTest() throws {
        try snapshotHub(
            userGoal(ageDays: 28),
            catalog: catalog(),
            measurements: [
                measurement("m-1", kind: "baseline", value: 42, daysAgo: 28),
                measurement("m-2", kind: "baseline_confirm", value: 43, daysAgo: 23),
            ],
            readiness: "rest",
            named: "hub-retest-deferred-low-readiness"
        )
    }

    func test_SGP_D2_missedSessionsSlideEtaNeutrally() throws {
        try snapshotHub(
            userGoal(ageDays: 27, slipDays: 9, slipReason: "2 missed sessions + 3 low-readiness days"),
            catalog: catalog(),
            measurements: [
                measurement("m-1", kind: "baseline", value: 42, daysAgo: 27),
                measurement("m-2", kind: "baseline_confirm", value: 43, daysAgo: 22),
            ],
            readiness: "moderate",
            named: "hub-week4-eta-slip"
        )
    }

    func test_SGP_D8_chartGrowsFromMeasurements() throws {
        try snapshotHub(
            userGoal(ageDays: 40),
            catalog: catalog(),
            measurements: [
                measurement("m-1", kind: "baseline", value: 42, daysAgo: 40),
                measurement("m-2", kind: "baseline_confirm", value: 43, daysAgo: 35),
                measurement("m-3", kind: "checkpoint", value: 45, daysAgo: 12),
            ],
            readiness: "moderate",
            named: "hub-chart-trend"
        )
    }

    func test_SGP_D8_milestoneShowsStageLadderNotChart() throws {
        try snapshotHub(
            userGoal(ageDays: 10, goalID: "g-crow", baselineStage: "feet_lift"),
            catalog: catalog(),
            measurements: [],
            readiness: "moderate",
            named: "hub-milestone-stage"
        )
    }

    func test_SGP_D6_withinNoiseBandReadsAsHonestNoChange() throws {
        let view = GoalHubView(
            goal: try userGoal(ageDays: 28),
            catalog: try catalog(),
            history: [],
            onChanged: {},
            onPickNewGoal: {},
            onNextBlock: { _, _ in },
            seedMeasurements: [
                try measurement("m-1", kind: "baseline", value: 42, daysAgo: 28),
                try measurement("m-2", kind: "baseline_confirm", value: 43, daysAgo: 23),
            ],
            seedNoChangeResult: true
        )
        .environmentObject(try appState(recommendationCategory: "moderate"))
        .somaBackground()
        snapshotView(view, named: "hub-retest-no-change")
    }

    // MARK: - E. Lifecycle edges

    func test_SGP_E1_userPauseIsCalmAndResumable() throws {
        try snapshotHub(
            userGoal(ageDays: 20, status: "paused", pauseReason: "user"),
            catalog: catalog(),
            measurements: [measurement("m-1", kind: "baseline", value: 42, daysAgo: 20)],
            readiness: "moderate",
            named: "hub-paused-user"
        )
    }

    func test_SGP_E2_safetyPauseOffersSafeSwitch() throws {
        try snapshotHub(
            userGoal(ageDays: 20, status: "paused", pauseReason: "safety"),
            catalog: catalog(),
            measurements: [measurement("m-1", kind: "baseline", value: 42, daysAgo: 20)],
            readiness: "moderate",
            named: "hub-paused-safety"
        )
    }

    func test_SGP_E3_staleBaselineForcesRemeasure() throws {
        try snapshotHub(
            userGoal(ageDays: 70),
            catalog: catalog(),
            measurements: [
                measurement("m-1", kind: "baseline", value: 42, daysAgo: 70),
                measurement("m-2", kind: "baseline_confirm", value: 43, daysAgo: 65),
            ],
            readiness: "moderate",
            named: "hub-rebaseline-stale"
        )
    }

    func test_SGP_E4_sportGoneDarkKeepsDataReadable() throws {
        try snapshotHub(
            userGoal(ageDays: 20),
            catalog: SportCatalog(), // the sport vanished server-side
            measurements: [measurement("m-1", kind: "baseline", value: 42, daysAgo: 20)],
            readiness: "moderate",
            named: "hub-sport-dark-unavailable"
        )
    }

    func test_SGP_E8_customGoalOffersCoachExportAfterSessions() throws {
        let customGoal = try decode(UserGoal.self, """
        {"id": "ug-c1", "kind": "custom", "target_kind": "commitment", "status": "active",
         "created_at": "\(iso(daysAgo: 14))", "recheck_date": "\(day(fromNow: 42))",
         "workout_text": "3 rounds: 10 approach jumps, 10 block jumps, wall touches",
         "coach_name": "Reyes", "duration_weeks": 8, "frequency_per_week": 3}
        """)
        let view = GoalHubView(
            goal: customGoal,
            catalog: try catalog(),
            history: [],
            onChanged: {},
            onPickNewGoal: {},
            onNextBlock: { _, _ in },
            seedMeasurements: [],
            seedSessionsDone: 5
        )
        .environmentObject(try appState(recommendationCategory: "moderate"))
        .somaBackground()
        snapshotView(view, height: 900, named: "hub-custom-coach-export")
    }

    func test_SGP_E5_achievementCelebratoryVsNeutral() {
        snapshotView(
            VStack(spacing: 16) {
                AchievementCardView(variant: .celebratory(
                    goalName: "Standing vertical jump", deltaText: "+5 cm", dateRange: "Aug–Oct 2026"))
                AchievementCardView(variant: .neutral(
                    goalName: "Standing vertical jump", deltaText: "+1 cm", dateRange: "Aug–Oct 2026"))
            }
            .padding(20)
            .somaBackground(),
            height: 700,
            named: "achievement-cards"
        )
    }
}
