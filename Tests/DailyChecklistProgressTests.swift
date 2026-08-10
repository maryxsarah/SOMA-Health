import XCTest
@testable import Soma

final class DailyChecklistProgressTests: XCTestCase {

    private func date(_ string: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.date(from: string)!
    }

    // MARK: - Standard mode item computation

    private func standardInputs(
        mealLoggedToday: Bool = false,
        todaysSteps: Int? = nil,
        stepGoal: Int = 8000,
        moodLoggedToday: Bool = false,
        workoutLoggedToday: Bool = false,
        lastProgressPictureDate: String? = nil,
        today: String = "2026-08-10"
    ) -> DailyChecklistProgress.StandardInputs {
        .init(
            mealLoggedToday: mealLoggedToday, targetProteinG: 150, targetCarbsG: 200,
            todaysSteps: todaysSteps, stepGoal: stepGoal, moodLoggedToday: moodLoggedToday,
            workoutLoggedToday: workoutLoggedToday, lastProgressPictureDate: lastProgressPictureDate,
            today: date(today)
        )
    }

    func testAllFourCoreItemsUncheckedWhenNothingLoggedYet() {
        let progress = DailyChecklistProgress.computeStandard(standardInputs(), streak: 0)
        XCTAssertEqual(progress.checkedCount, 0)
        XCTAssertFalse(progress.isComplete)
    }

    func testMealLoggedTodayAutoChecksBreakfastItem() {
        let progress = DailyChecklistProgress.computeStandard(standardInputs(mealLoggedToday: true), streak: 0)
        XCTAssertTrue(progress.items.first { $0.key == "log_breakfast" }!.isChecked)
    }

    func testStepsBelowGoalIsUnchecked() {
        let progress = DailyChecklistProgress.computeStandard(standardInputs(todaysSteps: 4000, stepGoal: 8000), streak: 0)
        XCTAssertFalse(progress.items.first { $0.key == "hit_step_goal" }!.isChecked)
    }

    func testStepsAtOrAboveGoalAutoChecks() {
        let progress = DailyChecklistProgress.computeStandard(standardInputs(todaysSteps: 8000, stepGoal: 8000), streak: 0)
        XCTAssertTrue(progress.items.first { $0.key == "hit_step_goal" }!.isChecked)
    }

    func testAllItemsCheckedMeansComplete() {
        let progress = DailyChecklistProgress.computeStandard(
            standardInputs(
                mealLoggedToday: true, todaysSteps: 9000, stepGoal: 8000,
                moodLoggedToday: true, workoutLoggedToday: true,
                lastProgressPictureDate: "2026-08-10", today: "2026-08-10"
            ),
            streak: 3
        )
        XCTAssertTrue(progress.isComplete)
        XCTAssertEqual(progress.checkedCount, progress.totalCount)
    }

    // MARK: - Progress picture 7-day cadence

    func testProgressPictureDueImmediatelyWhenNeverDone() {
        let progress = DailyChecklistProgress.computeStandard(standardInputs(lastProgressPictureDate: nil), streak: 0)
        let item = progress.items.first { $0.key == "progress_picture" }!
        XCTAssertFalse(item.isChecked)
        XCTAssertNotNil(item.deepLink)
    }

    func testProgressPictureStaysSettledWithinSevenDays() {
        let progress = DailyChecklistProgress.computeStandard(
            standardInputs(lastProgressPictureDate: "2026-08-06", today: "2026-08-10"), streak: 0
        )
        let item = progress.items.first { $0.key == "progress_picture" }!
        // Settled (isChecked true so it doesn't count as an open task) but
        // never hidden -- always present with a "next in N days" subtitle.
        XCTAssertTrue(item.isChecked)
        XCTAssertEqual(item.daysUntilNextAvailable, 3)
        XCTAssertNil(item.deepLink)
    }

    func testProgressPictureBecomesDueAgainAfterSevenDays() {
        let progress = DailyChecklistProgress.computeStandard(
            standardInputs(lastProgressPictureDate: "2026-08-01", today: "2026-08-10"), streak: 0
        )
        let item = progress.items.first { $0.key == "progress_picture" }!
        XCTAssertFalse(item.isChecked)
        XCTAssertNotNil(item.deepLink)
    }

    func testProgressPictureCheckedEarlierTodayShowsDone() {
        let progress = DailyChecklistProgress.computeStandard(
            standardInputs(lastProgressPictureDate: "2026-08-10", today: "2026-08-10"), streak: 0
        )
        let item = progress.items.first { $0.key == "progress_picture" }!
        XCTAssertTrue(item.isChecked)
        XCTAssertEqual(item.daysUntilNextAvailable, nil)
    }

    // MARK: - Onboarding mode completeness

    func testOnboardingIncompleteUntilEveryItemChecked() {
        var inputs = DailyChecklistProgress.OnboardingInputs(
            hasGoalsAndWeight: true, kitchenEquipmentAcknowledged: true, healthKitConnected: true,
            notificationsEnabled: true, hasReviewedFirstPlan: true, hasLoggedFirstWorkout: true,
            hasLoggedFirstMeal: true, hasSeenHowSomaWorks: false
        )
        XCTAssertFalse(DailyChecklistProgress.isOnboardingComplete(inputs))
        inputs.hasSeenHowSomaWorks = true
        XCTAssertTrue(DailyChecklistProgress.isOnboardingComplete(inputs))
    }

    // MARK: - Streak computation

    func testStreakZeroWhenNoDaysCompleted() {
        XCTAssertEqual(DailyChecklistProgress.computeStreak(completedDates: [], today: date("2026-08-10")), 0)
    }

    func testStreakCountsConsecutiveDaysEndingToday() {
        let streak = DailyChecklistProgress.computeStreak(
            completedDates: ["2026-08-08", "2026-08-09", "2026-08-10"], today: date("2026-08-10")
        )
        XCTAssertEqual(streak, 3)
    }

    func testStreakCountsAsOfYesterdayWhenTodayNotYetComplete() {
        let streak = DailyChecklistProgress.computeStreak(
            completedDates: ["2026-08-08", "2026-08-09"], today: date("2026-08-10")
        )
        XCTAssertEqual(streak, 2)
    }

    func testGapBreaksTheStreak() {
        let streak = DailyChecklistProgress.computeStreak(
            completedDates: ["2026-08-05", "2026-08-09", "2026-08-10"], today: date("2026-08-10")
        )
        XCTAssertEqual(streak, 2) // Only 08-09 and 08-10 are consecutive; 08-05 is orphaned by the gap.
    }

    func testDuplicateOrUnsortedDatesDontInflateOrBreakTheStreak() {
        let streak = DailyChecklistProgress.computeStreak(
            completedDates: ["2026-08-10", "2026-08-09", "2026-08-09", "2026-08-08"], today: date("2026-08-10")
        )
        XCTAssertEqual(streak, 3)
    }
}
