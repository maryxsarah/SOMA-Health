import XCTest
@testable import Soma

final class WorkoutCalorieEstimatorTests: XCTestCase {
    // MET * 3.5 * weightKg / 200 * minutes, rounded to the nearest kcal.

    func testModerateSessionEstimatesFromMetFormula() {
        // 6.0 MET * 3.5 * 70kg / 200 * 40min = 294 kcal exactly.
        XCTAssertEqual(
            WorkoutCalorieEstimator.estimateCalories(category: .moderate, durationMinutes: 40, weightKg: 70),
            294
        )
    }

    func testLightSessionEstimatesLowerThanModerate() {
        let light = WorkoutCalorieEstimator.estimateCalories(category: .light, durationMinutes: 30, weightKg: 65)
        let moderate = WorkoutCalorieEstimator.estimateCalories(category: .moderate, durationMinutes: 30, weightKg: 65)
        XCTAssertNotNil(light)
        XCTAssertNotNil(moderate)
        XCTAssertLessThan(light!, moderate!)
    }

    func testPushHardSessionEstimatesHigherThanModerate() {
        let pushHard = WorkoutCalorieEstimator.estimateCalories(category: .pushHard, durationMinutes: 45, weightKg: 80)
        let moderate = WorkoutCalorieEstimator.estimateCalories(category: .moderate, durationMinutes: 45, weightKg: 80)
        XCTAssertNotNil(pushHard)
        XCTAssertNotNil(moderate)
        XCTAssertGreaterThan(pushHard!, moderate!)
    }

    // MARK: - Never a guess without a real weight (this app's "no
    // estimated numbers presented as real" rule at its strictest)

    func testMissingWeightReturnsNilRatherThanAFabricatedNumber() {
        XCTAssertNil(WorkoutCalorieEstimator.estimateCalories(category: .moderate, durationMinutes: 40, weightKg: nil))
    }

    func testZeroOrNegativeWeightReturnsNil() {
        XCTAssertNil(WorkoutCalorieEstimator.estimateCalories(category: .moderate, durationMinutes: 40, weightKg: 0))
        XCTAssertNil(WorkoutCalorieEstimator.estimateCalories(category: .moderate, durationMinutes: 40, weightKg: -5))
    }

    func testZeroOrNegativeDurationReturnsNil() {
        XCTAssertNil(WorkoutCalorieEstimator.estimateCalories(category: .moderate, durationMinutes: 0, weightKg: 70))
        XCTAssertNil(WorkoutCalorieEstimator.estimateCalories(category: .moderate, durationMinutes: -10, weightKg: 70))
    }

    // MARK: - Rest is never logged as a workout, so it never estimates

    func testRestCategoryNeverEstimates() {
        XCTAssertNil(WorkoutCalorieEstimator.estimateCalories(category: .rest, durationMinutes: 30, weightKg: 70))
    }
}
