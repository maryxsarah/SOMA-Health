import XCTest

/// Throwaway verification for the 13a/13b/13c workout-detail redesign --
/// not part of the permanent suite, delete after use.
final class Verify13ThrowawayTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func test_verifyRecommendationDetailOpens() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixtures"]
        app.launch()

        let startWorkout = app.buttons["Start workout"]
        XCTAssertTrue(startWorkout.waitForExistence(timeout: 15))
        startWorkout.tap()

        let aiCardHeader = app.staticTexts["AI-generated workout"]
        XCTAssertTrue(aiCardHeader.waitForExistence(timeout: 10))

        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "13b-pre-generation"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
