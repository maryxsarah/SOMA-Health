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
            date: "2026-08-09", category: .moderate, message: "Test message", reason: reason,
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
        let result = WorkoutReasonResolver.reason(for: entry, recommendation: recommendation(reason: .whoopHigh), snapshots: [])
        XCTAssertEqual(result, "Frozen from log time.")
    }

    // MARK: - ai_plan uses the recommendation's own explanation, verbatim

    func testAIPlanUsesRecommendationExplanationDirectly() {
        let entry = log(source: "ai_plan")
        let result = WorkoutReasonResolver.reason(for: entry, recommendation: recommendation(reason: .healthkitLow), snapshots: [])
        XCTAssertEqual(result, RecommendationReason.healthkitLow.explanationTemplate)
    }

    // MARK: - manual/device_detected get the real readiness read PLUS an
    // honest note that this specific session wasn't the suggested plan

    func testManualLogWithRecommendationAppendsOffPlanNote() {
        let entry = log(source: "manual")
        let result = WorkoutReasonResolver.reason(for: entry, recommendation: recommendation(reason: .healthkitLow), snapshots: [])
        XCTAssertTrue(result.hasPrefix(RecommendationReason.healthkitLow.explanationTemplate))
        XCTAssertTrue(result.contains("outside today's suggested plan"))
    }

    func testDeviceDetectedLogWithRecommendationAppendsOffPlanNote() {
        let entry = log(source: "device_detected")
        let result = WorkoutReasonResolver.reason(for: entry, recommendation: recommendation(reason: .healthkitLow), snapshots: [])
        XCTAssertTrue(result.contains("Detected automatically from a connected device"))
    }

    // MARK: - No recommendation row at all for that date -- never empty

    func testManualLogWithNoRecommendationGetsHonestFallback() {
        let entry = log(source: "manual")
        let result = WorkoutReasonResolver.reason(for: entry, recommendation: nil, snapshots: [])
        XCTAssertFalse(result.isEmpty)
        XCTAssertTrue(result.contains("You logged this yourself"))
    }

    func testDeviceDetectedLogWithNoRecommendationGetsHonestFallback() {
        let entry = log(source: "device_detected")
        let result = WorkoutReasonResolver.reason(for: entry, recommendation: nil, snapshots: [])
        XCTAssertFalse(result.isEmpty)
        XCTAssertTrue(result.contains("Detected automatically"))
    }

    func testAIPlanWithNoRecommendationStillReturnsNonEmptyFallback() {
        // Not reachable in practice (an ai_plan log implies a
        // recommendation existed), but the resolver must never return an
        // empty string regardless of source.
        let entry = log(source: "ai_plan")
        let result = WorkoutReasonResolver.reason(for: entry, recommendation: nil, snapshots: [])
        XCTAssertFalse(result.isEmpty)
    }
}
