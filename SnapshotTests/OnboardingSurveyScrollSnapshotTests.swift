import SnapshotTesting
import SwiftUI
import XCTest
@testable import Soma

/// Guards the onboarding survey's longest option lists -- diet (11 cases),
/// kitchen equipment (14 cases), referral source (10 cases) -- against the
/// class of bug reported 2026-08-15: bottom options stuck under the pinned
/// "Continue" button. `SingleSelectQuestionView`/`MultiSelectQuestionView`/
/// `KitchenEquipmentQuestionView` all share one layout:
/// `VStack(spacing:0) { topBar; headline; ScrollView { rows }; PillButton }`
/// -- the ScrollView is a plain sibling laid out before the button, so it
/// can only ever clip its own content short, never spill past its own
/// frame into the button. Each screen gets two snapshots:
///   - "compressed": a shorter-than-any-real-device height, so the list
///     must scroll. Proves the ScrollView clips cleanly instead of the
///     rows spilling into/behind the button.
///   - "full": tall enough for every row to render with nothing clipped.
///     Proves every option (including the very last one) actually exists
///     in the tree and lands above the button with daylight between them,
///     rather than merely being scrollable-but-unreachable.
@MainActor
final class OnboardingSurveyScrollSnapshotTests: XCTestCase {

    private var record: Bool {
        ProcessInfo.processInfo.environment["SNAPSHOT_RECORD"] == "1"
    }

    override func setUpWithError() throws {
        try XCTSkipUnless(
            UIDevice.current.systemVersion.hasPrefix("26.5"),
            "Snapshots are pinned to iOS 26.5 (iPhone 17 Pro) — run via scripts/test.sh snapshot"
        )
    }

    private func snapshotView(
        _ view: some View,
        height: CGFloat,
        named name: String,
        file: StaticString = #filePath,
        testName: String = #function
    ) {
        assertSnapshot(
            of: view.environment(\.colorScheme, .light),
            as: .image(layout: .fixed(width: 393, height: height), traits: .init(displayScale: 2)),
            named: name,
            record: record,
            file: file,
            testName: testName
        )
    }

    // MARK: - Diet (11 options, longest single-select list; screen "10f")

    func test_dietQuestion_compressedHeightScrollsWithoutOverlappingCTA() {
        snapshotView(
            SingleSelectQuestionView<DietType>(
                headline: "Do you follow a specific diet?",
                progress: 0.6,
                selection: .constant(nil),
                onBack: {},
                onContinue: {}
            ),
            height: 620,
            named: "diet-compressed"
        )
    }

    // TEMP bisect: same screen, same 620pt canvas, but Continue forced enabled
    // (non-nil selection) to isolate whether the enabled CTAPillButton state
    // itself is what breaks the layout, independent of KitchenEquipmentQuestionView.
    func test_ZZZ_dietQuestion_compressedHeightWithEnabledCTA() {
        snapshotView(
            SingleSelectQuestionView<DietType>(
                headline: "Do you follow a specific diet?",
                progress: 0.6,
                selection: .constant(.pescatarian),
                onBack: {},
                onContinue: {}
            ),
            height: 620,
            named: "diet-compressed-enabled-cta"
        )
    }

    func test_dietQuestion_fullHeightShowsAllOptionsAboveCTA() {
        snapshotView(
            SingleSelectQuestionView<DietType>(
                headline: "Do you follow a specific diet?",
                progress: 0.6,
                selection: .constant(.pescatarian),
                onBack: {},
                onContinue: {}
            ),
            height: 1400,
            named: "diet-full"
        )
    }

    // MARK: - Kitchen equipment (14 options, longest list of any onboarding screen)

    func test_kitchenEquipmentQuestion_compressedHeightScrollsWithoutOverlappingCTA() {
        snapshotView(
            KitchenEquipmentQuestionView(
                progress: 0.75,
                selection: .constant([]),
                otherText: .constant(""),
                onBack: {},
                onContinue: {}
            ),
            height: 620,
            named: "kitchen-equipment-compressed"
        )
    }

    func test_kitchenEquipmentQuestion_fullHeightShowsAllOptionsAboveCTA() {
        snapshotView(
            KitchenEquipmentQuestionView(
                progress: 0.75,
                selection: .constant([.stove, .oven, .other]),
                otherText: .constant("Sous vide"),
                onBack: {},
                onContinue: {}
            ),
            height: 1500,
            named: "kitchen-equipment-full"
        )
    }

    // MARK: - Referral source (10 options)

    func test_referralSourceQuestion_compressedHeightScrollsWithoutOverlappingCTA() {
        snapshotView(
            SingleSelectQuestionView<ReferralSource>(
                headline: "Where did you hear about us?",
                progress: 0.2,
                selection: .constant(nil),
                onBack: {},
                onContinue: {}
            ),
            height: 620,
            named: "referral-source-compressed"
        )
    }

    func test_referralSourceQuestion_fullHeightShowsAllOptionsAboveCTA() {
        snapshotView(
            SingleSelectQuestionView<ReferralSource>(
                headline: "Where did you hear about us?",
                progress: 0.2,
                selection: .constant(.other),
                onBack: {},
                onContinue: {}
            ),
            height: 1200,
            named: "referral-source-full"
        )
    }
}
