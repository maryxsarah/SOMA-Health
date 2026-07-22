import SwiftUI

@main
struct SomaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()
    @StateObject private var sessionManager = SessionManager()

    var body: some Scene {
        WindowGroup {
            // Exactly the 4 screens in sequence -- no NavigationStack, no
            // tab bar, per spec.
            Group {
                switch appState.screen {
                case .onboarding:
                    OnboardingView()
                case .survey:
                    OnboardingSurveyView()
                case .connectDevice:
                    ConnectDeviceView()
                case .notifications:
                    NotificationEnablementView()
                case .postSetup:
                    PostSetupFlowView()
                case .home:
                    HomeView()
                }
            }
            .environmentObject(appState)
            .environmentObject(sessionManager)
            .environmentObject(SubscriptionManager.shared)
            // The visual design (white cards, pale-blue gradient, navy
            // pills) is a fixed light aesthetic per spec, not an adaptive
            // one -- without this, system text colors (.primary/.secondary)
            // invert to white in Dark Mode and become unreadable against
            // the still-light background.
            .preferredColorScheme(.light)
        }
    }
}
