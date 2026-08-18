import XCTest
@testable import Soma

/// Pins the new users.country/users.city profile fields: lenient decoding
/// (absent means nil, never a thrown decode) and the region display helper.
final class ProfileRegionTests: XCTestCase {

    func testDecodesRegionFieldsWhenPresent() throws {
        let profile = try JSONDecoder().decode(UserProfile.self, from: Data("""
        {"goals": [], "equipment": [], "household_equipment": [], "injury_tags": [], "injury_severity": {},
         "injury_type": {}, "injury_pain_level": {}, "anchor_sessions": [], "country": "US", "city": "Austin"}
        """.utf8))
        XCTAssertEqual(profile.country, "US")
        XCTAssertEqual(profile.city, "Austin")
    }

    func testRegionFieldsAbsentDecodeAsNil() throws {
        let profile = try JSONDecoder().decode(UserProfile.self, from: Data("""
        {"goals": [], "equipment": [], "household_equipment": [], "injury_tags": [], "injury_severity": {},
         "injury_type": {}, "injury_pain_level": {}, "anchor_sessions": []}
        """.utf8))
        XCTAssertNil(profile.country)
        XCTAssertNil(profile.city)
    }

    func testRegionFieldsRoundTripSet() throws {
        var profile = UserProfile.empty
        profile.country = "DE"
        profile.city = "Berlin"
        let decoded = try JSONDecoder().decode(UserProfile.self, from: JSONEncoder().encode(profile))
        XCTAssertEqual(decoded.country, "DE")
        XCTAssertEqual(decoded.city, "Berlin")
    }

    func testRegionFieldsRoundTripNil() throws {
        let decoded = try JSONDecoder().decode(UserProfile.self, from: JSONEncoder().encode(UserProfile.empty))
        XCTAssertNil(decoded.country)
        XCTAssertNil(decoded.city)
    }

    func testRegionDisplayFormats() {
        XCTAssertEqual(UserProfile.regionDisplay(country: "US", city: "Austin"), "Austin, US")
        XCTAssertEqual(UserProfile.regionDisplay(country: "US", city: nil), "US")
        XCTAssertEqual(UserProfile.regionDisplay(country: nil, city: "Austin"), "Austin")
        XCTAssertNil(UserProfile.regionDisplay(country: nil, city: nil))
        XCTAssertNil(UserProfile.regionDisplay(country: "", city: "   "))
    }
}
