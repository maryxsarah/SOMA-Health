import XCTest
@testable import Soma

/// fetchExerciseLibraryEntry's name-lookup path used to build its
/// percent-encoding inline. Real exercise_library names hit several
/// character classes `.urlQueryAllowed` deliberately leaves unescaped
/// (they're legal URL "sub-delims"): a slash ("Adductor/Groin"), an
/// apostrophe ("Farmer's Walk"), and parentheses with an inner space
/// ("Butt Lift (Bridge)"). None of these throw or fail loudly if handled
/// wrong -- they'd just silently return "no row found" for exactly the
/// exercises whose names need them, which is indistinguishable from a
/// genuine no-photo exercise. Each class gets its own case here, plus a
/// live-endpoint round-trip confirmed by hand against the real table
/// (2026-08-15, see exerciseLibraryLookupPath's doc comment) -- this suite
/// only re-checks the deterministic encoding step, not the network call.
final class ExerciseLibraryLookupTests: XCTestCase {

    /// Round-trips `path` the same way Foundation actually would when
    /// `authorizedRequest` builds a URL from it and the request goes out --
    /// decoding the query value back out and comparing to the original,
    /// rather than eyeballing the encoded string.
    private func decodedNameValue(from path: String) -> String? {
        guard let url = URL(string: "https://example.supabase.co/\(path)"),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        return components.queryItems?.first(where: { $0.name == "name" })?.value
    }

    func testSlashInNameRoundTrips() {
        let path = SupabaseClient.exerciseLibraryLookupPath(libraryId: nil, name: "Adductor/Groin")
        XCTAssertEqual(decodedNameValue(from: path), "eq.Adductor/Groin")
    }

    func testApostropheInNameRoundTrips() {
        let path = SupabaseClient.exerciseLibraryLookupPath(libraryId: nil, name: "Farmer's Walk")
        XCTAssertEqual(decodedNameValue(from: path), "eq.Farmer's Walk")
    }

    func testParenthesesAndInnerSpaceRoundTrip() {
        let path = SupabaseClient.exerciseLibraryLookupPath(libraryId: nil, name: "Butt Lift (Bridge)")
        XCTAssertEqual(decodedNameValue(from: path), "eq.Butt Lift (Bridge)")
    }

    func testPlainSpaceStillEncodes() {
        // The un-special-character baseline: `.urlQueryAllowed` must still
        // escape a bare space, or this whole "leaves sub-delims alone" story
        // would just be regular under-encoding.
        let path = SupabaseClient.exerciseLibraryLookupPath(libraryId: nil, name: "Bent Over Row")
        XCTAssertTrue(path.contains("Bent%20Over%20Row"))
        XCTAssertEqual(decodedNameValue(from: path), "eq.Bent Over Row")
    }

    func testConstructedURLIsNeverNil() {
        // authorizedRequest force-unwraps URL(string:) -- a path that fails
        // to parse doesn't 404, it crashes the app on that exercise's detail
        // sheet. None of these names may ever produce an unparseable URL.
        for name in ["Adductor/Groin", "Farmer's Walk", "Butt Lift (Bridge)", "3/4 Sit-Up"] {
            let path = SupabaseClient.exerciseLibraryLookupPath(libraryId: nil, name: name)
            XCTAssertNotNil(URL(string: "https://example.supabase.co/\(path)"), "failed to parse for name: \(name)")
        }
    }

    func testLibraryIdTakesPrecedenceOverName() {
        let path = SupabaseClient.exerciseLibraryLookupPath(libraryId: "Farmers_Walk", name: "Dumbbell farmer's carry")
        XCTAssertTrue(path.contains("id=eq.Farmers_Walk"))
        XCTAssertFalse(path.contains("name=eq."))
    }
}
