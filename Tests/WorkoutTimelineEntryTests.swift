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

    // MARK: - confirmationCandidate (real feedback: a walk must never
    // SILENTLY mark the day's workout as done -- but since nothing here
    // writes anything anymore, a walk is a legitimate candidate to ASK the
    // user about, same as any other detected activity type)

    private func entry(durationMinutes: Int, calories: Int? = nil, activityType: String? = nil, title: String = "Test") -> WorkoutTimelineEntry {
        WorkoutTimelineEntry(source: "apple_health", title: title, startTime: Date(), durationMinutes: durationMinutes, calories: calories, activityType: activityType)
    }

    func testWalkIsRecognizedRegardlessOfDuration() {
        XCTAssertTrue(entry(durationMinutes: 90, activityType: "walking").isWalk)
    }

    func testNonWalkActivityTypeIsNotAWalk() {
        XCTAssertFalse(entry(durationMinutes: 90, activityType: "running").isWalk)
    }

    func testMissingActivityTypeIsNotAssumedToBeAWalk() {
        XCTAssertFalse(entry(durationMinutes: 30, activityType: nil).isWalk)
    }

    func testLongWalkIsAskableAsAConfirmationCandidate() {
        // The exact real-usage report: a long walk (2k steps worth) was
        // never askable at all -- it just got silently excluded, which is
        // what made the SILENT auto-log of OTHER activities feel arbitrary.
        // Now the walk itself is a valid candidate to surface a yes/no
        // prompt for; only the user's own answer decides whether it counts.
        let entries = [entry(durationMinutes: 45, activityType: "walking", title: "Walking")]
        XCTAssertEqual(WorkoutTimelineEntry.confirmationCandidate(from: entries)?.title, "Walking")
    }

    func testShortEntryUnderMinimumDurationDoesNotQualify() {
        let entries = [entry(durationMinutes: 5, activityType: "running")]
        XCTAssertNil(WorkoutTimelineEntry.confirmationCandidate(from: entries))
    }

    func testLongestQualifyingSessionIsPreferredEvenWhenTheLongestIsAWalk() {
        let walk = entry(durationMinutes: 90, activityType: "walking", title: "Walking")
        let run = entry(durationMinutes: 30, activityType: "running", title: "Running")
        let picked = WorkoutTimelineEntry.confirmationCandidate(from: [walk, run])
        XCTAssertEqual(picked?.title, "Walking")
    }

    func testLongestQualifyingSessionIsPreferred() {
        let short = entry(durationMinutes: 15, activityType: "running", title: "Short Run")
        let long = entry(durationMinutes: 60, activityType: "cycling", title: "Long Ride")
        let picked = WorkoutTimelineEntry.confirmationCandidate(from: [short, long])
        XCTAssertEqual(picked?.title, "Long Ride")
    }

    // MARK: - `excluding` (already-asked entries fall back to the next
    // candidate, rather than the whole function giving up)

    func testRegressionAlreadyAskedLongestEntryFallsBackToTheNextQualifyingEntry() {
        // BUG report: a 90-min walk was declined (asked about) earlier
        // today. A genuine 30-min run appears later. Picking the single
        // longest entry FIRST and only then checking whether it was asked
        // about meant the walk (still longest) blocked the run from ever
        // being offered -- confirmationCandidate must exclude already-asked
        // entries before ranking, not after.
        let walk = entry(durationMinutes: 90, activityType: "walking", title: "Walking")
        let run = entry(durationMinutes: 30, activityType: "running", title: "Running")
        let picked = WorkoutTimelineEntry.confirmationCandidate(from: [walk, run], excluding: [walk.stableKey])
        XCTAssertEqual(picked?.title, "Running")
    }

    func testAllQualifyingEntriesAlreadyAskedYieldsNoCandidate() {
        let walk = entry(durationMinutes: 90, activityType: "walking", title: "Walking")
        let picked = WorkoutTimelineEntry.confirmationCandidate(from: [walk], excluding: [walk.stableKey])
        XCTAssertNil(picked)
    }

    func testExcludingDefaultsToEmptySoExistingCallersAreUnaffected() {
        let entries = [entry(durationMinutes: 45, activityType: "walking", title: "Walking")]
        XCTAssertEqual(WorkoutTimelineEntry.confirmationCandidate(from: entries)?.title, "Walking")
    }

    // MARK: - stableKey (survives a re-fetch, unlike `id`)

    func testStableKeyIsIdenticalAcrossTwoFetchesOfTheSameUnderlyingSession() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let first = WorkoutTimelineEntry(source: "apple_health", title: "Walking", startTime: start, durationMinutes: 45, calories: 120, activityType: "walking")
        let second = WorkoutTimelineEntry(source: "apple_health", title: "Walking", startTime: start, durationMinutes: 45, calories: 120, activityType: "walking")
        XCTAssertNotEqual(first.id, second.id, "id is a fresh UUID every fetch")
        XCTAssertEqual(first.stableKey, second.stableKey, "stableKey should survive a re-fetch of the same session")
    }

    func testStableKeyDiffersForDifferentSourcesAtTheSameStartTime() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let healthKit = WorkoutTimelineEntry(source: "apple_health", title: "Run", startTime: start, durationMinutes: 30, calories: nil)
        let whoop = WorkoutTimelineEntry(source: "whoop", title: "Run", startTime: start, durationMinutes: 30, calories: nil)
        XCTAssertNotEqual(healthKit.stableKey, whoop.stableKey)
    }
}
