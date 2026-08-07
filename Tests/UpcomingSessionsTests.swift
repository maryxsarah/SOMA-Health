import XCTest
@testable import Soma

final class UpcomingSessionsTests: XCTestCase {

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d))!
    }

    private func dow(_ date: Date) -> Int {
        Calendar.current.component(.weekday, from: date) - 1
    }

    func testWeekdaysReturnsNextMatchingDatesInOrder() {
        let start = date(2026, 8, 10)
        let startDow = dow(start)
        let target1 = (startDow + 2) % 7
        let target2 = (startDow + 4) % 7
        let result = UpcomingSessions.display(
            scheduleRule: .weekdays, scheduleDays: [target1, target2], courtDays: nil, count: 3, from: start
        )
        guard case .dates(let dates) = result else { return XCTFail("expected .dates") }
        XCTAssertEqual(dates.count, 3)
        XCTAssertEqual(dow(dates[0]), target1)
        XCTAssertEqual(dow(dates[1]), target2)
        XCTAssertEqual(dow(dates[2]), target1, "crosses into the following week")
    }

    func testWeekdaysCanIncludeTheStartDateItself() {
        let start = date(2026, 8, 10)
        let result = UpcomingSessions.display(
            scheduleRule: .weekdays, scheduleDays: [dow(start)], courtDays: nil, count: 1, from: start
        )
        guard case .dates(let dates) = result else { return XCTFail("expected .dates") }
        XCTAssertTrue(Calendar.current.isDate(dates[0], inSameDayAs: start))
    }

    func testWeekdaysWithNoDaysSelectedFallsBackToQualitative() {
        let result = UpcomingSessions.display(
            scheduleRule: .weekdays, scheduleDays: [], courtDays: nil, count: 3, from: date(2026, 8, 10)
        )
        guard case .qualitative(let text) = result else { return XCTFail("expected .qualitative") }
        XCTAssertEqual(text, "Whenever readiness allows")
    }

    func testBeforeCourtDaysReturnsTheDayBeforeEachCourtDay() {
        let start = date(2026, 8, 10)
        let startDow = dow(start)
        let courtDay = (startDow + 3) % 7
        let expectedTrainingDow = (courtDay - 1 + 7) % 7
        let result = UpcomingSessions.display(
            scheduleRule: .beforeCourtDays, scheduleDays: nil, courtDays: [courtDay], count: 1, from: start
        )
        guard case .dates(let dates) = result else { return XCTFail("expected .dates") }
        XCTAssertEqual(dow(dates[0]), expectedTrainingDow)
    }

    func testEveryOtherDayNeverFabricatesDates() {
        let result = UpcomingSessions.display(
            scheduleRule: .everyOtherDay, scheduleDays: nil, courtDays: nil, from: date(2026, 8, 10)
        )
        guard case .qualitative(let text) = result else { return XCTFail("expected .qualitative") }
        XCTAssertEqual(text, "Every other day")
    }

    func testReadinessNeverFabricatesDates() {
        let result = UpcomingSessions.display(
            scheduleRule: .readiness, scheduleDays: nil, courtDays: nil, from: date(2026, 8, 10)
        )
        guard case .qualitative(let text) = result else { return XCTFail("expected .qualitative") }
        XCTAssertEqual(text, "Whenever readiness allows")
    }

    func testNilScheduleRuleNeverFabricatesDates() {
        let result = UpcomingSessions.display(
            scheduleRule: nil, scheduleDays: nil, courtDays: nil, from: date(2026, 8, 10)
        )
        guard case .qualitative = result else { return XCTFail("expected .qualitative") }
    }
}
