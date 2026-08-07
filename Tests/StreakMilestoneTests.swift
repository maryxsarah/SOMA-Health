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

final class ProfileViewStreakTests: XCTestCase {
    /// Same "yyyy-MM-dd" + .current formatting streak(from:) uses internally.
    private func dateString(daysAgo: Int, hour: Int = 12, minute: Int = 0) -> String {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: Date())!
        let atTime = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: atTime)
    }

    func testNoLogsIsZeroStreak() {
        XCTAssertEqual(ProfileView.streak(from: []), 0)
    }

    func testSingleTodayEntryIsOneDayStreak() {
        XCTAssertEqual(ProfileView.streak(from: [dateString(daysAgo: 0)]), 1)
    }

    func testConsecutiveDaysContinueTheStreak() {
        let dates: Set<String> = [dateString(daysAgo: 0), dateString(daysAgo: 1), dateString(daysAgo: 2)]
        XCTAssertEqual(ProfileView.streak(from: dates), 3)
    }

    func testMissedDayBreaksTheStreak() {
        // Today and 2 days ago present, yesterday missing -- the walk-back
        // stops the moment it hits the gap.
        let dates: Set<String> = [dateString(daysAgo: 0), dateString(daysAgo: 2)]
        XCTAssertEqual(ProfileView.streak(from: dates), 1)
    }

    func testNoEntryTodayShowsZeroEvenWithAPriorStreak() {
        // A real run through yesterday earns no credit until today is
        // actually logged -- matches the calendar strip's own crown badges.
        let dates: Set<String> = [dateString(daysAgo: 1), dateString(daysAgo: 2), dateString(daysAgo: 3)]
        XCTAssertEqual(ProfileView.streak(from: dates), 0)
    }

    func testLongUnbrokenStreakCountsEveryDay() {
        let dates = Set((0..<10).map { dateString(daysAgo: $0) })
        XCTAssertEqual(ProfileView.streak(from: dates), 10)
    }

    func testEntryJustBeforeMidnightAndJustAfterAreDistinctDays() {
        // 11:59pm "yesterday" and 12:01am "today" are different local days -- both count.
        let dates: Set<String> = [
            dateString(daysAgo: 1, hour: 23, minute: 59),
            dateString(daysAgo: 0, hour: 0, minute: 1),
        ]
        XCTAssertEqual(ProfileView.streak(from: dates), 2)
    }

    func testFutureDatesInTheSetDontInflateTheStreak() {
        // Defensive: streak(from:) walks backward from today, so a stray
        // future-dated entry (clock skew, bad data) is simply never visited.
        let dates: Set<String> = [dateString(daysAgo: 0), dateString(daysAgo: -5)]
        XCTAssertEqual(ProfileView.streak(from: dates), 1)
    }
}
