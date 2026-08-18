import SnapshotTesting
import SwiftUI
import XCTest
@testable import Soma

extension LocalizationSnapshotTests {

    func test_referralCodeSheet_localizedAcrossLanguages() throws {
        let state = try appState()
        snapshotAcrossLocales(height: 500, named: "referral-code-sheet") {
            ReferralCodeSheet()
                .environmentObject(state)
        }
    }

    func test_goalBodyProgress_localizedAcrossLanguages() throws {
        snapshotAcrossLocales(height: 1400, named: "goal-body-progress") {
            GoalBodyProgressView()
        }
    }

    func test_bodyPhotoComparison_localizedAcrossLanguages() throws {
        let placeholder = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40)).image { ctx in
            UIColor.systemGray4.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        }
        snapshotAcrossLocales(height: 700, named: "body-photo-comparison") {
            BodyPhotoComparisonView(goalImage: placeholder, currentImage: placeholder)
        }
    }

    func test_legalDocument_localizedAcrossLanguages() throws {
        snapshotAcrossLocales(height: 1400, named: "legal-document") {
            LegalDocumentView(
                title: "Privacy Policy",
                text: "This is placeholder legal text used only to verify the surrounding chrome renders correctly in every language. " + String(repeating: "Lorem ipsum dolor sit amet. ", count: 20)
            )
        }
    }
}
