import SnapshotTesting
import SwiftUI
import XCTest
@testable import Soma

/// One test per top-level screen, each rendering that screen under all 9
/// shipped locales (en/es/fr/it/de/ru/ka/hy/sr) in one run -- catches broken layouts,
/// truncated text, and keys that resolve to their raw name instead of
/// translated text (see LanguageManager.swift's `.environment(\.locale, ...)`
/// note: this only proves out the SwiftUI `Text(...)` path, not
/// `String(localized:)` calls in Models/Services, since those read the
/// process locale rather than the view-tree environment one).
///
/// Split across `LocalizationSnapshotTests+*.swift` files (one extension
/// per screen group) so multiple screens' fixtures can be authored/edited
/// independently without touching a shared file. Reference PNGs are
/// machine-local (git-ignored) -- record once with `--record`, eyeball
/// them, then this suite guards against regressions same as
/// SportGoalSnapshotTests.
@MainActor
final class LocalizationSnapshotTests: XCTestCase {

    /// All shipped locale codes, in `AppLanguage.allCases` order minus
    /// `.system` (a snapshot needs a concrete locale, not "whatever the
    /// simulator happens to be set to").
    static let localeCodes = ["en", "es", "fr", "it", "de", "ru", "ka", "hy", "sr"]

    var record: Bool {
        ProcessInfo.processInfo.environment["SNAPSHOT_RECORD"] == "1"
    }

    override func setUpWithError() throws {
        // References are device+OS-pinned; a mismatched simulator would
        // "fail" every snapshot for a reason unrelated to localization.
        try XCTSkipUnless(
            UIDevice.current.systemVersion.hasPrefix("26.5"),
            "Snapshots are pinned to iOS 26.5 (iPhone 17 Pro) — run via scripts/test.sh snapshot"
        )
    }

    // MARK: - Shared fixture helpers (used by every +Group extension)

    func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    /// Mirrors SportGoalSnapshotTests' helper of the same shape -- a bare
    /// `AppState()` plus an optional decoded `DailyRecommendation` seeded
    /// onto `currentRecommendation`, since several screens read it via
    /// `@EnvironmentObject`.
    func appState(recommendationCategory: String? = nil) throws -> AppState {
        let state = AppState()
        if let recommendationCategory {
            state.currentRecommendation = try decode(DailyRecommendation.self, """
            {"date": "2026-08-11", "category": "\(recommendationCategory)",
             "message": "Solid day for quality work.",
             "reason": "Your HRV was close to your recent baseline and you slept enough -- a good sign of recovery.",
             "sleep_cap_applied": false, "injury_cap_applied": false, "load_cap_applied": false}
            """)
        }
        return state
    }

    /// One assertSnapshot call per locale, named `"<name>-<code>"` so all 8
    /// land as separate reference PNGs under one test function -- a single
    /// failure clearly names which language regressed.
    func snapshotAcrossLocales<V: View>(
        height: CGFloat = 1200,
        named name: String,
        file: StaticString = #filePath,
        testName: String = #function,
        @ViewBuilder _ makeView: () -> V
    ) {
        let view = makeView()
        for code in Self.localeCodes {
            assertSnapshot(
                of: view
                    .environment(\.locale, Locale(identifier: code))
                    .environment(\.colorScheme, .light),
                as: .image(layout: .fixed(width: 393, height: height), traits: .init(displayScale: 2)),
                named: "\(name)-\(code)",
                record: record,
                file: file,
                testName: testName
            )
        }
    }
}
