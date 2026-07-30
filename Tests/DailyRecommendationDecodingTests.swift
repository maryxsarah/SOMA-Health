import XCTest
@testable import Soma

/// The app decodes `daily_recommendation` rows from two different places --
/// a PostgREST read and the generate-recommendation Edge Function response --
/// through one Codable model. These pin the parts that would break silently:
/// a renamed column, or a null in the newly added confidence field.
final class DailyRecommendationDecodingTests: XCTestCase {

    private func decode(_ json: String) throws -> DailyRecommendation {
        try JSONDecoder().decode(DailyRecommendation.self, from: Data(json.utf8))
    }

    func testDecodesAFullRow() throws {
        let recommendation = try decode("""
        {
          "date": "2026-07-28",
          "category": "push_hard",
          "message": "Go for it.",
          "reason": "healthkit_high",
          "data_confidence": "high",
          "sleep_cap_applied": false,
          "injury_cap_applied": false,
          "load_cap_applied": false
        }
        """)

        XCTAssertEqual(recommendation.category, .pushHard)
        XCTAssertEqual(recommendation.reason, .healthkitHigh)
        XCTAssertEqual(recommendation.dataConfidence, .high)
    }

    func testDecodesRowsWrittenBeforeDataConfidenceExisted() throws {
        // The column is nullable with no backfill, precisely because rows
        // written earlier have genuinely unknown confidence. Decoding must
        // tolerate that rather than throwing and blanking the Home screen.
        let recommendation = try decode("""
        {
          "date": "2026-07-25",
          "category": "moderate",
          "message": "Solid day.",
          "reason": "healthkit_medium",
          "data_confidence": null,
          "sleep_cap_applied": false,
          "injury_cap_applied": false,
          "load_cap_applied": false
        }
        """)

        XCTAssertNil(recommendation.dataConfidence)
    }

    func testDecodesWhenDataConfidenceKeyIsAbsentEntirely() throws {
        let recommendation = try decode("""
        {
          "date": "2026-07-25",
          "category": "rest",
          "message": "Rest up.",
          "reason": "unknown",
          "sleep_cap_applied": true,
          "injury_cap_applied": false,
          "load_cap_applied": false
        }
        """)

        XCTAssertNil(recommendation.dataConfidence)
        XCTAssertTrue(recommendation.sleepCapApplied)
    }

    // MARK: - Server-owned reason vocabulary

    func testUnrecognizedReasonDecodesAsUnknownInsteadOfThrowing() throws {
        // REGRESSION: the server's reason vocabulary grows ahead of shipped
        // clients -- insufficient_data appeared in the database before any
        // build had its enum case, and synthesized decoding threw for the
        // whole row, blanking Home for exactly the users the new reason was
        // written for. The value here is deliberately one no enum case will
        // ever claim, so this keeps guarding whatever the server adds next.
        let recommendation = try decode("""
        {
          "date": "2026-07-30",
          "category": "moderate",
          "message": "Starting cautiously.",
          "reason": "some_future_reason_this_build_has_never_heard_of",
          "data_confidence": "low",
          "sleep_cap_applied": false,
          "injury_cap_applied": false,
          "load_cap_applied": false
        }
        """)

        XCTAssertEqual(recommendation.reason, .unknown)
    }

    func testInsufficientDataReasonDecodesToItsRealCase() throws {
        // The fallback must not swallow values the client *does* know --
        // insufficient_data gained a real case (with its own copy and tip)
        // when dev merged, and it should decode as itself, not .unknown.
        let recommendation = try decode("""
        {
          "date": "2026-07-30",
          "category": "moderate",
          "message": "Starting cautiously.",
          "reason": "insufficient_data",
          "data_confidence": "low",
          "sleep_cap_applied": false,
          "injury_cap_applied": false,
          "load_cap_applied": false
        }
        """)

        XCTAssertEqual(recommendation.reason, .insufficientData)
    }

    func testRowsWithoutTheNewerCapFlagsDecodeWithFalse() throws {
        // Responses from an Edge Function version predating the
        // consecutive-days and injury-protocol caps omit those keys
        // entirely -- deployments and app releases are not atomic. Decoded
        // as false, not as a failure. (The JSON in the other tests already
        // covers the keys-present path.)
        let recommendation = try decode("""
        {
          "date": "2026-07-30",
          "category": "moderate",
          "message": "Solid day.",
          "reason": "healthkit_medium",
          "sleep_cap_applied": false,
          "injury_cap_applied": false,
          "load_cap_applied": false
        }
        """)

        XCTAssertFalse(recommendation.consecutiveDaysCapApplied)
        XCTAssertFalse(recommendation.injuryProtocolCapApplied)
        XCTAssertFalse(recommendation.injuryProtocolModerateCapApplied)
    }

    // MARK: - Caveat copy

    func testLowConfidenceShowsACaveat() {
        // A run of identical days with no explanation is what made testers
        // report the feature as broken. Low confidence must say so.
        XCTAssertNotNil(DataConfidence.low.caveat)
    }

    func testHighConfidenceShowsNoCaveat() {
        XCTAssertNil(DataConfidence.high.caveat)
    }

    func testMissingConfidenceShowsNoCaveat() {
        let confidence: DataConfidence? = nil
        XCTAssertNil(confidence?.caveat)
    }
}
