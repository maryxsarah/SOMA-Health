import SnapshotTesting
import SwiftUI
import XCTest
@testable import Soma

extension LocalizationSnapshotTests {

    func test_home_localizedAcrossLanguages() throws {
        let state = try appState(recommendationCategory: "moderate")
        snapshotAcrossLocales(height: 1400, named: "home") {
            HomeView()
                .environmentObject(state)
        }
    }

    func test_profile_localizedAcrossLanguages() throws {
        let state = try appState()
        snapshotAcrossLocales(height: 1400, named: "profile") {
            ProfileView()
                .environmentObject(state)
                .environmentObject(LanguageManager.shared)
        }
    }

    func test_connectDevice_localizedAcrossLanguages() throws {
        let state = try appState()
        snapshotAcrossLocales(height: 700, named: "connect-device") {
            ConnectDeviceView()
                .environmentObject(state)
        }
    }

    func test_notificationEnablement_localizedAcrossLanguages() throws {
        let state = try appState()
        snapshotAcrossLocales(height: 700, named: "notification-enablement") {
            NotificationEnablementView()
                .environmentObject(state)
        }
    }

    func test_onboarding_localizedAcrossLanguages() throws {
        let state = try appState()
        let sessionManager = SessionManager()
        snapshotAcrossLocales(height: 900, named: "onboarding") {
            OnboardingView()
                .environmentObject(state)
                .environmentObject(sessionManager)
        }
    }
}
