import XCTest
@testable import Soma

final class GoalJourneyProgressTests: XCTestCase {

    private func isoString(daysAgo: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    func testNilWhenAnyRequiredInputIsMissing() {
        XCTAssertNil(GoalJourneyProgress.compute(createdAt: nil, weightKg: 80, desiredWeightKg: 75, goalPace: .recommended))
        XCTAssertNil(GoalJourneyProgress.compute(createdAt: isoString(daysAgo: 10), weightKg: nil, desiredWeightKg: 75, goalPace: .recommended))
        XCTAssertNil(GoalJourneyProgress.compute(createdAt: isoString(daysAgo: 10), weightKg: 80, desiredWeightKg: nil, goalPace: .recommended))
        XCTAssertNil(GoalJourneyProgress.compute(createdAt: isoString(daysAgo: 10), weightKg: 80, desiredWeightKg: 75, goalPace: nil))
    }

    func testNilOnAnUnparseableDateString() {
        XCTAssertNil(GoalJourneyProgress.compute(createdAt: "not-a-date", weightKg: 80, desiredWeightKg: 75, goalPace: .recommended))
    }

    func testDaysElapsedMatchesRealCalendarDistance() throws {
        let progress = try XCTUnwrap(GoalJourneyProgress.compute(
            createdAt: isoString(daysAgo: 14), weightKg: 80, desiredWeightKg: 75, goalPace: .recommended
        ))
        XCTAssertEqual(progress.daysElapsed, 14)
    }

    func testFractionNeverExceedsOneEvenPastTheEstimatedTimeline() throws {
        // 5kg at "recommended" pace -> a small estimate (a few months);
        // 900 days elapsed is guaranteed to blow past it.
        let progress = try XCTUnwrap(GoalJourneyProgress.compute(
            createdAt: isoString(daysAgo: 900), weightKg: 80, desiredWeightKg: 75, goalPace: .recommended
        ))
        XCTAssertEqual(progress.fraction, 1.0)
        // The real elapsed count still tells the honest story even capped.
        XCTAssertEqual(progress.daysElapsed, 900)
    }

    func testFractionIsZeroOnDayOne() throws {
        let progress = try XCTUnwrap(GoalJourneyProgress.compute(
            createdAt: isoString(daysAgo: 0), weightKg: 80, desiredWeightKg: 75, goalPace: .recommended
        ))
        XCTAssertEqual(progress.fraction, 0, accuracy: 0.001)
    }

    func testFasterPaceShrinksTheEstimatedTotalDays() throws {
        let recommended = try XCTUnwrap(GoalJourneyProgress.compute(
            createdAt: isoString(daysAgo: 10), weightKg: 80, desiredWeightKg: 75, goalPace: .recommended
        ))
        let fast = try XCTUnwrap(GoalJourneyProgress.compute(
            createdAt: isoString(daysAgo: 10), weightKg: 80, desiredWeightKg: 75, goalPace: .fast
        ))
        XCTAssertLessThan(fast.estimatedTotalDays, recommended.estimatedTotalDays)
    }

    func testEstimatedTotalDaysIsAlwaysAtLeastOneMonth() throws {
        // desiredWeightKg == weightKg -> zero delta, still floors to 1 month.
        let progress = try XCTUnwrap(GoalJourneyProgress.compute(
            createdAt: isoString(daysAgo: 5), weightKg: 80, desiredWeightKg: 80, goalPace: .recommended
        ))
        XCTAssertEqual(progress.estimatedTotalDays, 30)
        XCTAssertFalse(progress.hasReliableEstimate,
                       "a near-zero weight delta must not be shown as a confident 1-month estimate")
    }

    // REGRESSION: a stale/tiny weight target must not claim a specific,
    // misleadingly short timeline next to an ambitious goal photo.
    func testTinyDeltaIsMarkedUnreliableEvenOnFastPace() throws {
        let progress = try XCTUnwrap(GoalJourneyProgress.compute(
            createdAt: isoString(daysAgo: 13), weightKg: 60, desiredWeightKg: 61, goalPace: .fast
        ))
        XCTAssertFalse(progress.hasReliableEstimate)
    }

    func testMeaningfulDeltaIsMarkedReliable() throws {
        let progress = try XCTUnwrap(GoalJourneyProgress.compute(
            createdAt: isoString(daysAgo: 13), weightKg: 60, desiredWeightKg: 75, goalPace: .recommended
        ))
        XCTAssertTrue(progress.hasReliableEstimate)
    }
}
