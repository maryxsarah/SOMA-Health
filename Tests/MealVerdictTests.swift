import XCTest
@testable import Soma

final class MealVerdictTests: XCTestCase {
    func testLowScoresAreOffTarget() {
        XCTAssertEqual(MealVerdict.forScore(1), .offTarget)
        XCTAssertEqual(MealVerdict.forScore(3), .offTarget)
    }

    func testMidLowScoresAreMediocre() {
        XCTAssertEqual(MealVerdict.forScore(4), .mediocre)
        XCTAssertEqual(MealVerdict.forScore(5), .mediocre)
    }

    func testMidHighScoresAreNormal() {
        XCTAssertEqual(MealVerdict.forScore(6), .normal)
        XCTAssertEqual(MealVerdict.forScore(7), .normal)
    }

    func testHighScoresAreExcellent() {
        XCTAssertEqual(MealVerdict.forScore(8), .excellent)
        XCTAssertEqual(MealVerdict.forScore(10), .excellent)
    }

    /// The bug this whole rewrite fixes: a 7/10 (now "Good fit", not
    /// "Excellent choice") must never read as a top-tier endorsement.
    func testSevenIsGoodNotExcellent() {
        XCTAssertEqual(MealVerdict.forScore(7), .normal)
        XCTAssertNotEqual(MealVerdict.forScore(7), .excellent)
    }

    func testEntryWithNoScoreHasNoVerdict() {
        let entry = MealLogEntry(id: "1", date: "2026-08-06", label: nil, calories: 400, proteinG: 20, carbsG: nil, fatG: nil, source: "manual", loggedAt: "2026-08-06T12:00:00Z")
        XCTAssertNil(entry.verdict)
    }

    func testEntryWithScoreDerivesMatchingVerdict() {
        var entry = MealLogEntry(id: "1", date: "2026-08-06", label: nil, calories: 400, proteinG: 20, carbsG: nil, fatG: nil, source: "manual", loggedAt: "2026-08-06T12:00:00Z")
        entry.score = 8
        XCTAssertEqual(entry.verdict, .excellent)
    }
}

final class MealScoreModifierTests: XCTestCase {
    func testParsesSignAndKey() {
        let modifier = MealScoreModifier(raw: "-:alcohol")
        XCTAssertEqual(modifier?.isPositive, false)
        XCTAssertEqual(modifier?.label, "Contains alcohol")
    }

    func testPositiveSign() {
        let modifier = MealScoreModifier(raw: "+:highProteinDensity")
        XCTAssertEqual(modifier?.isPositive, true)
    }

    func testUnrecognizedKeyFallsBackToRawRatherThanDisappearing() {
        let modifier = MealScoreModifier(raw: "-:someFutureModifier")
        XCTAssertEqual(modifier?.label, "someFutureModifier")
    }

    func testMalformedEntryFailsToParse() {
        XCTAssertNil(MealScoreModifier(raw: "alcohol"))
    }
}
