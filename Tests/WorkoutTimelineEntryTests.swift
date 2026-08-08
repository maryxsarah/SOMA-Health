import XCTest
@testable import Soma

final class WorkoutTimelineEntryTests: XCTestCase {
    private func entry(durationMinutes: Int, calories: Int?) -> WorkoutTimelineEntry {
        WorkoutTimelineEntry(source: "apple_health", title: "Test", startTime: Date(), durationMinutes: durationMinutes, calories: calories)
    }

    func testHighCalorieBurnRateInfersPushHard() {
        // 1229 kcal / 120 min ≈ 10.24 kcal/min -- the exact real-usage
        // report this feature was built for.
        XCTAssertEqual(entry(durationMinutes: 120, calories: 1229).inferredCategory, "push_hard")
    }

    func testModerateCalorieBurnRateInfersModerate() {
        XCTAssertEqual(entry(durationMinutes: 60, calories: 420).inferredCategory, "moderate")
    }

    func testLowCalorieBurnRateInfersLight() {
        XCTAssertEqual(entry(durationMinutes: 60, calories: 200).inferredCategory, "light")
    }

    func testMissingCaloriesFallsBackToModerate() {
        XCTAssertEqual(entry(durationMinutes: 45, calories: nil).inferredCategory, "moderate")
    }

    func testZeroDurationFallsBackToModerateRatherThanDividingByZero() {
        XCTAssertEqual(entry(durationMinutes: 0, calories: 500).inferredCategory, "moderate")
    }

    // MARK: - qualifyingAutoLogCandidate (real feedback: a walk should
    // never auto-mark the day's workout as done)

    private func entry(durationMinutes: Int, calories: Int? = nil, activityType: String? = nil, title: String = "Test") -> WorkoutTimelineEntry {
        WorkoutTimelineEntry(source: "apple_health", title: title, startTime: Date(), durationMinutes: durationMinutes, calories: calories, activityType: activityType)
    }

    func testWalkIsRecognizedRegardlessOfDuration() {
        XCTAssertTrue(entry(durationMinutes: 90, activityType: "walking").isWalk)
    }

    func testNonWalkActivityTypeIsNotAWalk() {
        XCTAssertFalse(entry(durationMinutes: 90, activityType: "running").isWalk)
    }

    func testMissingActivityTypeIsNotAssumedToBeAWalk() {
        XCTAssertFalse(entry(durationMinutes: 30, activityType: nil).isWalk)
    }

    func testLongWalkNeverQualifiesAsAutoLogCandidate() {
        // The exact real-usage report: a long walk (2k steps worth) must
        // not silently satisfy the day, however long HealthKit says it ran.
        let entries = [entry(durationMinutes: 45, activityType: "walking")]
        XCTAssertNil(WorkoutTimelineEntry.qualifyingAutoLogCandidate(from: entries))
    }

    func testShortEntryUnderMinimumDurationDoesNotQualify() {
        let entries = [entry(durationMinutes: 5, activityType: "running")]
        XCTAssertNil(WorkoutTimelineEntry.qualifyingAutoLogCandidate(from: entries))
    }

    func testRealWorkoutQualifiesEvenWhenAWalkIsAlsoPresent() {
        let walk = entry(durationMinutes: 90, activityType: "walking", title: "Walking")
        let run = entry(durationMinutes: 30, activityType: "running", title: "Running")
        let picked = WorkoutTimelineEntry.qualifyingAutoLogCandidate(from: [walk, run])
        XCTAssertEqual(picked?.title, "Running")
    }

    func testLongestQualifyingNonWalkSessionIsPreferred() {
        let short = entry(durationMinutes: 15, activityType: "running", title: "Short Run")
        let long = entry(durationMinutes: 60, activityType: "cycling", title: "Long Ride")
        let picked = WorkoutTimelineEntry.qualifyingAutoLogCandidate(from: [short, long])
        XCTAssertEqual(picked?.title, "Long Ride")
    }
}
