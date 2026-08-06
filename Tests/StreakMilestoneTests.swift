import XCTest
@testable import Soma

final class StreakMilestoneTests: XCTestCase {
    func testZeroStreakAchievesNothing() {
        for milestone in StreakMilestone.allCases {
            XCTAssertFalse(milestone.isAchieved(streak: 0))
        }
    }

    func testExactBoundaryCountsAsAchieved() {
        XCTAssertTrue(StreakMilestone.week.isAchieved(streak: 7))
        XCTAssertTrue(StreakMilestone.month.isAchieved(streak: 30))
    }

    func testOneDayShortIsNotAchieved() {
        XCTAssertFalse(StreakMilestone.week.isAchieved(streak: 6))
        XCTAssertFalse(StreakMilestone.hundredDay.isAchieved(streak: 99))
    }

    func testHighStreakAchievesEveryMilestone() {
        for milestone in StreakMilestone.allCases {
            XCTAssertTrue(milestone.isAchieved(streak: 400))
        }
    }

    func testMilestonesAreOrderedAscending() {
        let values = StreakMilestone.allCases.map(\.rawValue)
        XCTAssertEqual(values, values.sorted())
    }
}
