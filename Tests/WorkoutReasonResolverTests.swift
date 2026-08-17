import XCTest
@testable import Soma

final class WorkoutReasonResolverTests: XCTestCase {
    private func log(source: String, reasonSnapshot: String? = nil) -> WorkoutLogEntry {
        WorkoutLogEntry(
            id: "log-1", date: "2026-08-09", title: "Test Workout", bodyPart: "full_body", category: "moderate",
            completedAt: "2026-08-09T12:00:00Z", feedback: nil, planSnapshot: nil,
            startedAt: nil, endedAt: nil, feelRating: nil, source: source,
            caloriesBurned: nil, caloriesEstimated: false, reasonSnapshot: reasonSnapshot
        )
    }

    private func recommendation(reason: RecommendationReason) -> DailyRecommendation {
        DailyRecommendation(
            date: "2026-08-09", category: .moderate, message: "Test message", messageDetail: nil, reason: reason,
            sleepCapApplied: false, injuryCapApplied: false, loadCapApplied: false,
            consecutiveDaysCapApplied: false, injuryProtocolCapApplied: false, injuryProtocolModerateCapApplied: false,
            pregnancyCapApplied: false, volumeCapApplied: false, hrvCapApplied: false, stressCapApplied: false,
            injuryProtocolRestApplied: false, moodCapApplied: false, preCapCategory: nil, dataConfidence: nil,
            userRequestedCategory: nil
        )
    }

    // MARK: - A persisted snapshot always wins, regardless of what else is passed in

    func testPersistedSnapshotWinsOutrightOverLiveRecommendation() {
        let entry = log(source: "ai_plan", reasonSnapshot: "Frozen from log time.")
        let result = WorkoutReasonResolver.reason(for: entry, recommendation: recommendation(reason: .whoopHigh), snapshots: [], dayLoadState: .fulfilled)
        XCTAssertEqual(result, "Frozen from log time.")
    }

    // MARK: - ai_plan gets retrospective impact copy too (item 1,
    // completed): prescriptive "why was this suggested" text never appears
    // on a finished session, whatever its source.

    func testAIPlanGetsImpactCopyNotThePrescriptiveExplanation() {
        let entry = log(source: "ai_plan")
        let result = WorkoutReasonResolver.reason(for: entry, recommendation: recommendation(reason: .healthkitLow), snapshots: [], dayLoadState: .fulfilled)
        XCTAssertFalse(result.contains(RecommendationReason.healthkitLow.explanation(snapshots: [])))
        XCTAssertTrue(result.contains("daily target met"))
    }

    func testAIPlanPartialGetsTheCountedTowardCopy() {
        let entry = log(source: "ai_plan")
        let result = WorkoutReasonResolver.reason(for: entry, recommendation: nil, snapshots: [], dayLoadState: .partiallyDone)
        XCTAssertTrue(result.contains("Counted toward your weekly target"))
    }

    // MARK: - manual/device_detected get retrospective impact copy, never
    // the prescriptive "why was this suggested" explanation (item 1 fix --
    // that explanation describes a DIFFERENT session these logs weren't).

    func testManualLogNeverShowsThePrescriptiveExplanation() {
        let entry = log(source: "manual")
        let result = WorkoutReasonResolver.reason(for: entry, recommendation: recommendation(reason: .healthkitLow), snapshots: [], dayLoadState: .fulfilled)
        XCTAssertFalse(result.contains(RecommendationReason.healthkitLow.explanation(snapshots: [])))
        XCTAssertTrue(result.contains("outside Soma's plan"))
    }

    func testDeviceDetectedFulfilledMentionsClosingTodaysQuota() {
        let entry = log(source: "device_detected")
        let result = WorkoutReasonResolver.reason(for: entry, recommendation: recommendation(reason: .healthkitLow), snapshots: [], dayLoadState: .fulfilled)
        XCTAssertFalse(result.contains(RecommendationReason.healthkitLow.explanation(snapshots: [])))
        XCTAssertTrue(result.contains("closed today's quota"))
    }

    func testDeviceDetectedOverreachedAlsoGetsTheDoneCopy() {
        let entry = log(source: "device_detected")
        let result = WorkoutReasonResolver.reason(for: entry, recommendation: nil, snapshots: [], dayLoadState: .overreached)
        XCTAssertTrue(result.contains("closed today's quota"))
    }

    func testDeviceDetectedPartiallyDoneGetsTheOffPlanNoteInstead() {
        let entry = log(source: "device_detected")
        let result = WorkoutReasonResolver.reason(for: entry, recommendation: nil, snapshots: [], dayLoadState: .partiallyDone)
        XCTAssertTrue(result.contains("Detected automatically from a connected device"))
        XCTAssertFalse(result.contains("closed today's quota"))
    }

    // MARK: - manual/device_detected never depend on recommendation being
    // present at all -- impact copy is derived purely from source + dayLoadState.

    func testManualLogWithNoRecommendationStillGetsHonestImpactCopy() {
        let entry = log(source: "manual")
        let result = WorkoutReasonResolver.reason(for: entry, recommendation: nil, snapshots: [], dayLoadState: .fulfilled)
        XCTAssertFalse(result.isEmpty)
        XCTAssertTrue(result.contains("outside Soma's plan"))
    }

    // MARK: - ai_plan with no recommendation row at all -- never empty

    func testAIPlanWithNoRecommendationStillReturnsNonEmptyFallback() {
        // Not reachable in practice (an ai_plan log implies a
        // recommendation existed), but the resolver must never return an
        // empty string regardless of source.
        let entry = log(source: "ai_plan")
        let result = WorkoutReasonResolver.reason(for: entry, recommendation: nil, snapshots: [], dayLoadState: .fulfilled)
        XCTAssertFalse(result.isEmpty)
    }
}
