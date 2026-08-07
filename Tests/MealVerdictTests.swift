import XCTest
@testable import Soma

final class MealVerdictTests: XCTestCase {
    func testLowScoresAreNotGreat() {
        XCTAssertEqual(MealVerdict.forScore(1), .notGreat)
        XCTAssertEqual(MealVerdict.forScore(3), .notGreat)
    }

    func testMidScoresAreOK() {
        XCTAssertEqual(MealVerdict.forScore(4), .ok)
        XCTAssertEqual(MealVerdict.forScore(6), .ok)
    }

    func testHighScoresAreGood() {
        XCTAssertEqual(MealVerdict.forScore(7), .good)
        XCTAssertEqual(MealVerdict.forScore(10), .good)
    }

    func testEntryWithNoScoreHasNoVerdict() {
        let entry = MealLogEntry(id: "1", date: "2026-08-06", label: nil, calories: 400, proteinG: 20, carbsG: nil, fatG: nil, source: "manual", loggedAt: "2026-08-06T12:00:00Z")
        XCTAssertNil(entry.verdict)
    }

    func testEntryWithScoreDerivesMatchingVerdict() {
        var entry = MealLogEntry(id: "1", date: "2026-08-06", label: nil, calories: 400, proteinG: 20, carbsG: nil, fatG: nil, source: "manual", loggedAt: "2026-08-06T12:00:00Z")
        entry.score = 8
        XCTAssertEqual(entry.verdict, .good)
    }
}
