import XCTest
@testable import Soma

/// Pins the weekday picker's display-order↔server-value contract: the UI
/// shows Monday-first (M T W T F S S) but must EMIT the server convention
/// (0=Sunday..6=Saturday, JS getUTCDay -- create-goal validates 0..6).
final class WeekdayMappingTests: XCTestCase {

    func testFullDisplayOrderMapping() {
        XCTAssertEqual(WeekdayMiniPicker.dayValuesInDisplayOrder, [1, 2, 3, 4, 5, 6, 0])
    }

    func testSundayShownLastEmitsServerZero() {
        XCTAssertEqual(WeekdayMiniPicker.dayValuesInDisplayOrder.last, 0)
    }

    func testEmittedValuesCoverServerRangeExactlyOnce() {
        XCTAssertEqual(Set(WeekdayMiniPicker.dayValuesInDisplayOrder), Set(0...6))
        XCTAssertEqual(WeekdayMiniPicker.dayValuesInDisplayOrder.count, 7)
    }

    func testShortNamesFollowServerConvention() {
        XCTAssertEqual(WeekdayMiniPicker.shortName(forValue: 0), "Sun")
        XCTAssertEqual(WeekdayMiniPicker.shortName(forValue: 1), "Mon")
        XCTAssertEqual(WeekdayMiniPicker.shortName(forValue: 6), "Sat")
        XCTAssertEqual(WeekdayMiniPicker.shortName(forValue: 7), "?")
    }
}
