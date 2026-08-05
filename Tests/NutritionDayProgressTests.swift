import XCTest
@testable import Soma

final class NutritionDayProgressTests: XCTestCase {

    private let target = NutritionTargets(
        dailyCalories: 2000, dailyProteinG: 150, dailyCarbsG: 200, dailyFatG: 60,
        computedAt: "2026-08-06T00:00:00Z", basis: "mifflin_st_jeor:cut:activity=moderate:sex=female"
    )

    private func entry(calories: Int, protein: Int, carbs: Int? = nil, fat: Int? = nil) -> MealLogEntry {
        MealLogEntry(id: UUID().uuidString, date: "2026-08-06", label: nil, calories: calories, proteinG: protein, carbsG: carbs, fatG: fat, source: "manual", loggedAt: "2026-08-06T12:00:00Z")
    }

    func testSumsMultipleEntries() {
        let progress = NutritionDayProgress.compute(entries: [
            entry(calories: 500, protein: 30, carbs: 40, fat: 15),
            entry(calories: 700, protein: 50, carbs: 60, fat: 20),
        ], target: target)
        XCTAssertEqual(progress.consumedCalories, 1200)
        XCTAssertEqual(progress.consumedProteinG, 80)
        XCTAssertEqual(progress.consumedCarbsG, 100)
        XCTAssertEqual(progress.consumedFatG, 35)
    }

    func testMissingCarbsOrFatCountsAsZeroNotSkipped() {
        let progress = NutritionDayProgress.compute(entries: [
            entry(calories: 500, protein: 30), // no carbs/fat given
            entry(calories: 300, protein: 20, carbs: 25, fat: 10),
        ], target: target)
        XCTAssertEqual(progress.consumedCarbsG, 25)
        XCTAssertEqual(progress.consumedFatG, 10)
    }

    func testEmptyLogYieldsZeroEverything() {
        let progress = NutritionDayProgress.compute(entries: [], target: target)
        XCTAssertEqual(progress.consumedCalories, 0)
        XCTAssertEqual(progress.calorieFraction, 0)
    }

    func testFractionIsExactWithinRange() {
        let progress = NutritionDayProgress.compute(entries: [entry(calories: 1000, protein: 75)], target: target)
        XCTAssertEqual(progress.calorieFraction, 0.5, accuracy: 0.001)
        XCTAssertEqual(progress.proteinFraction, 0.5, accuracy: 0.001)
    }

    func testREGRESSION_fractionNeverExceedsOneEvenWhenOverTarget() {
        let progress = NutritionDayProgress.compute(entries: [entry(calories: 3000, protein: 300)], target: target)
        XCTAssertEqual(progress.calorieFraction, 1.0)
        XCTAssertEqual(progress.proteinFraction, 1.0)
        // The real (uncapped) number is still available for honest display.
        XCTAssertEqual(progress.consumedCalories, 3000)
        XCTAssertGreaterThan(progress.consumedCalories, progress.targetCalories)
    }

    func testCaloriesRemainingNeverGoesNegative() {
        let progress = NutritionDayProgress.compute(entries: [entry(calories: 3000, protein: 300)], target: target)
        XCTAssertEqual(progress.caloriesRemaining, 0)
    }

    func testCaloriesRemainingIsAccurateWhenUnderTarget() {
        let progress = NutritionDayProgress.compute(entries: [entry(calories: 800, protein: 60)], target: target)
        XCTAssertEqual(progress.caloriesRemaining, 1200)
    }

    func testZeroTargetNeverDividesByZero() {
        let zeroTarget = NutritionTargets(dailyCalories: 0, dailyProteinG: 0, dailyCarbsG: 0, dailyFatG: 0, computedAt: "2026-08-06T00:00:00Z", basis: "test")
        let progress = NutritionDayProgress.compute(entries: [entry(calories: 100, protein: 10)], target: zeroTarget)
        XCTAssertEqual(progress.calorieFraction, 0)
    }
}
