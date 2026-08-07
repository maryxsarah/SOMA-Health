import XCTest
@testable import Soma

final class BodyMetricsTests: XCTestCase {
    func testKnownWorkedExample() {
        // 70kg / (1.75m)^2 = 22.857...
        let bmi = BodyMetrics.bmi(weightKg: 70, heightCm: 175)
        XCTAssertEqual(bmi!, 22.857, accuracy: 0.01)
    }

    func testMissingWeightReturnsNil() {
        XCTAssertNil(BodyMetrics.bmi(weightKg: nil, heightCm: 175))
    }

    func testMissingHeightReturnsNil() {
        XCTAssertNil(BodyMetrics.bmi(weightKg: 70, heightCm: nil))
    }

    func testNonPositiveHeightReturnsNilRatherThanDividingByZero() {
        XCTAssertNil(BodyMetrics.bmi(weightKg: 70, heightCm: 0))
        XCTAssertNil(BodyMetrics.bmi(weightKg: 70, heightCm: -10))
    }

    func testCategoryBoundaries() {
        XCTAssertEqual(BodyMetrics.bmiCategory(18.4), "Underweight")
        XCTAssertEqual(BodyMetrics.bmiCategory(18.5), "Normal weight")
        XCTAssertEqual(BodyMetrics.bmiCategory(24.9), "Normal weight")
        XCTAssertEqual(BodyMetrics.bmiCategory(25.0), "Overweight")
        XCTAssertEqual(BodyMetrics.bmiCategory(29.9), "Overweight")
        XCTAssertEqual(BodyMetrics.bmiCategory(30.0), "Obese")
    }
}
