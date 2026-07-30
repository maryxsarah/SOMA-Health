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
        // REGRESSION: the server's reason vocabulary grows ahead of the
        // client -- the dev branch's insufficient_data migration added a
        // value this build's enum doesn't have, and synthesized decoding
        // threw for the whole row, blanking Home for exactly the users
        // (no health data yet) the new reason was written for.
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

        XCTAssertEqual(recommendation.reason, .unknown)
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
