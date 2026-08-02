import XCTest
@testable import Soma

/// The per-reason explanation templates carry "%@"/"%%" placeholders that
/// must never reach the screen raw -- DayDetailView once rendered
/// `explanationTemplate` directly and testers saw "Your Oura readiness was
/// %@" verbatim. These pin the substitution helper both views now share.
final class RecommendationExplanationTests: XCTestCase {

    private func snapshot(source: String, recovery: Double? = nil, readiness: Double? = nil) -> DailySnapshotRow {
        DailySnapshotRow(
            date: nil, source: source, recoveryScore: recovery, readinessScore: readiness,
            hrvMs: nil, sleepHours: nil, restingHr: nil, strainScore: nil, stressScore: nil,
            sleepLightHours: nil, sleepDeepHours: nil, sleepRemHours: nil, sleepAwakeHours: nil
        )
    }

    func testOuraReasonSubstitutesReadinessScore() {
        let text = RecommendationReason.ouraHigh.explanation(snapshots: [snapshot(source: "oura", readiness: 88)])
        XCTAssertTrue(text.contains("was 88,"))
        XCTAssertFalse(text.contains("%@"))
    }

    func testWhoopReasonSubstitutesRecoveryAndRendersPercentSign() {
        let text = RecommendationReason.whoopMedium.explanation(snapshots: [snapshot(source: "whoop", recovery: 55)])
        XCTAssertTrue(text.contains("was 55%,"))
        XCTAssertFalse(text.contains("%@"))
        XCTAssertFalse(text.contains("%%"))
    }

    func testMissingSnapshotFallsBackToDashNotPlaceholder() {
        let text = RecommendationReason.ouraLow.explanation(snapshots: [])
        XCTAssertTrue(text.contains("was —,"))
        XCTAssertFalse(text.contains("%@"))
    }

    func testWrongSourceSnapshotIsNotUsed() {
        // An Oura reason must not pick up a Whoop snapshot's number.
        let text = RecommendationReason.ouraMedium.explanation(snapshots: [snapshot(source: "whoop", recovery: 55)])
        XCTAssertTrue(text.contains("was —,"))
    }

    func testEveryReasonRendersWithoutRawPlaceholders() {
        let allReasons: [RecommendationReason] = [
            .whoopHigh, .whoopMedium, .whoopLow,
            .ouraHigh, .ouraMediumHigh, .ouraMedium, .ouraLow,
            .healthkitHigh, .healthkitMedium, .healthkitLow,
            .insufficientData, .unknown,
        ]
        for reason in allReasons {
            let text = reason.explanation(snapshots: [])
            XCTAssertFalse(text.contains("%@"), "\(reason) leaked a raw %@ placeholder")
            XCTAssertFalse(text.contains("%%"), "\(reason) leaked an unescaped %% placeholder")
        }
    }

    func testScoreIsRounded() {
        let text = RecommendationReason.ouraHigh.explanation(snapshots: [snapshot(source: "oura", readiness: 87.6)])
        XCTAssertTrue(text.contains("was 88,"))
    }
}
