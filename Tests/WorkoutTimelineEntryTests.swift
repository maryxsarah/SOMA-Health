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
}
