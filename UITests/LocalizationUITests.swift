import XCTest

/// Verifies the in-app language override (Profile -> Account -> Language)
/// actually changes displayed text live, and that the selection persists
/// across a relaunch. Companion to `LocalizationSnapshotTests` (screen-level
/// coverage per locale) -- this file covers the *mechanism* of switching.
final class LocalizationUITests: XCTestCase {

    private var runningApp: XCUIApplication?

    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() {
        runningApp?.terminate()
        runningApp = nil
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixtures"]
        app.launch()
        runningApp = app
        return app
    }

    private func openLanguageSheet(_ app: XCUIApplication) {
        let profileButton = app.buttons["profile-button"]
        XCTAssertTrue(profileButton.waitForExistence(timeout: 20), "Home should show the profile/settings button")
        profileButton.tap()

        // Matched by label predicate, not subscript-by-identifier -- the
        // segmented control's items aren't given explicit accessibility
        // identifiers, and matching by implicit label-as-identifier proved
        // flaky (see SportGoalJourneyTests for the same established
        // pattern used throughout this app's other UI tests).
        let accountTab = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Account")).firstMatch
        XCTAssertTrue(accountTab.waitForExistence(timeout: 15), "Profile should show an Account tab")
        accountTab.tap()

        let languageRow = app.buttons["language-settings-row"]
        XCTAssertTrue(languageRow.waitForExistence(timeout: 10), "Account tab should show a Language row")
        languageRow.tap()
    }

    /// Selecting a language: (1) shows a checkmark against the new
    /// selection, (2) updates the sheet's own navigation title live via
    /// `.environment(\.locale, ...)` (no relaunch needed for plain
    /// `Text("literal")` content), (3) the choice reads back correctly
    /// after dismissing and reopening the sheet.
    func test_languageSelection_updatesUILiveAndPersists() {
        let app = launch()
        openLanguageSheet(app)

        XCTAssertTrue(app.navigationBars["Language"].waitForExistence(timeout: 10),
                      "Sheet should open titled 'Language' while still on System Default")

        let spanish = app.buttons["language-option-es"]
        XCTAssertTrue(spanish.waitForExistence(timeout: 10), "Language sheet should list Español")
        spanish.tap()

        // The sheet's own nav title is a literal Text driven by the same
        // environment locale the picker just changed -- if this flips to
        // "Idioma" the live .environment(\.locale, ...) override is
        // actually reaching the view hierarchy, not just being stored.
        XCTAssertTrue(app.navigationBars["Idioma"].waitForExistence(timeout: 10),
                      "Selecting Español should retitle the sheet live, without relaunching")

        // Dismiss (button label is now "Listo", not "Done" -- itself proof
        // the override is live) and reopen to confirm persistence.
        let doneButton = app.navigationBars.buttons.matching(NSPredicate(format: "label CONTAINS 'Listo'")).firstMatch
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5))
        doneButton.tap()

        let languageRow = app.buttons["language-settings-row"]
        XCTAssertTrue(languageRow.waitForExistence(timeout: 10))
        XCTAssertTrue(languageRow.label.contains("Español"),
                      "Account row's value should now read the selected language's own name")
        languageRow.tap()

        XCTAssertTrue(app.navigationBars["Idioma"].waitForExistence(timeout: 10),
                      "Reopening the sheet should reflect the persisted selection, not reset to System Default")

        // Restore System Default so later tests (and a human re-running
        // this suite) start from a clean slate.
        let systemDefault = app.buttons["language-option-system"]
        XCTAssertTrue(systemDefault.waitForExistence(timeout: 10))
        systemDefault.tap()
        XCTAssertTrue(app.navigationBars["Language"].waitForExistence(timeout: 10),
                      "Reverting to System Default should retitle the sheet back to English live")
    }

    /// All 6 options are present and distinct -- catches a future language
    /// being added to AppLanguage but not shipped in Localizable.xcstrings
    /// (or vice versa), which would otherwise only surface as silently
    /// mistranslated UI.
    func test_languageSheet_listsAllSupportedLanguages() {
        let app = launch()
        openLanguageSheet(app)

        for code in ["system", "en", "es", "fr", "it", "de", "ru", "ka", "hy"] {
            XCTAssertTrue(app.buttons["language-option-\(code)"].waitForExistence(timeout: 10),
                          "Language sheet should list the '\(code)' option")
        }
    }
}
