import XCTest
@testable import Soma

/// Covers the two pure helpers behind the Apple-Health metric snapshot.
/// Both replaced code that was silently wrong in production:
/// - metrics used to be "the single most recent sample of all time", which
///   submitted stale values as today's and poisoned the server-side baseline;
/// - sleep used to be the plain sum of sample durations, which double-counts
///   whenever more than one source writes overlapping samples.
final class HealthKitMetricsTests: XCTestCase {

    // MARK: - median

    func testMedianOfOddCount() {
        XCTAssertEqual(HealthKitManager.median([3, 1, 2]), 2)
    }

    func testMedianOfEvenCountAveragesTheMiddlePair() {
        XCTAssertEqual(HealthKitManager.median([1, 2, 3, 4]), 2.5)
    }

    func testMedianOfEmptyIsNil() {
        // Callers rely on nil meaning "nothing recorded in the window" so
        // they can omit the metric instead of sending something stale.
        XCTAssertNil(HealthKitManager.median([]))
    }

    func testMedianResistsOutliers() {
        // Passive Apple Watch SDNN readings are noisy enough that a single
        // artefact is expected. The mean here would be 63.25 -- a fabricated
        // "great HRV day"; the median stays with the real cluster.
        XCTAssertEqual(HealthKitManager.median([100, 50, 52, 51]), 51.5)
    }

    func testMedianOfSingleSample() {
        // Resting HR is typically written once per day, so a one-element
        // window is the normal case, not an edge case.
        XCTAssertEqual(HealthKitManager.median([67]), 67)
    }

    // MARK: - mergedDuration

    private let epoch = Date(timeIntervalSince1970: 0)

    private func interval(_ startHour: Double, _ endHour: Double) -> (start: Date, end: Date) {
        (start: epoch.addingTimeInterval(startHour * 3600),
         end: epoch.addingTimeInterval(endHour * 3600))
    }

    private func hours(_ intervals: [(start: Date, end: Date)]) -> Double {
        HealthKitManager.mergedDuration(intervals) / 3600
    }

    func testSingleInterval() {
        XCTAssertEqual(hours([interval(0, 8)]), 8)
    }

    func testIdenticalIntervalsFromTwoSourcesCountOnce() {
        // The actual production failure: an Apple Watch and a third-party
        // sleep app both writing the same night turned 8 hours into 16.
        XCTAssertEqual(hours([interval(0, 8), interval(0, 8)]), 8)
    }

    func testPartiallyOverlappingIntervalsMerge() {
        XCTAssertEqual(hours([interval(0, 5), interval(4, 8)]), 8)
    }

    func testAdjacentIntervalsMergeWithoutGap() {
        XCTAssertEqual(hours([interval(0, 4), interval(4, 8)]), 8)
    }

    func testGapsAreNotCounted() {
        // Waking in the middle of the night is real and should not be
        // counted as sleep.
        XCTAssertEqual(hours([interval(0, 3), interval(5, 7)]), 5)
    }

    func testUnsortedInputIsHandled() {
        // HealthKit sample order is not guaranteed; the query passes
        // sortDescriptors: nil.
        XCTAssertEqual(hours([interval(5, 7), interval(0, 3)]), 5)
    }

    func testFullyNestedIntervalIsAbsorbed() {
        XCTAssertEqual(hours([interval(0, 8), interval(2, 4)]), 8)
    }

    func testEmptyInputIsZero() {
        XCTAssertEqual(HealthKitManager.mergedDuration([]), 0)
    }

    func testZeroLengthIntervalsAreDropped() {
        XCTAssertEqual(HealthKitManager.mergedDuration([interval(3, 3)]), 0)
    }

    func testInvertedIntervalIsDropped() {
        // Defensive: an end before its start would otherwise contribute a
        // negative duration and quietly reduce total sleep.
        XCTAssertEqual(hours([interval(0, 8), interval(5, 4)]), 8)
    }
}
