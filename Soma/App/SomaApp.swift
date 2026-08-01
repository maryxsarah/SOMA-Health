import SuperwallKit
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
            // Shake-to-report, live on every screen past sign-in (the
            // insert needs a session; before onboarding completes there is
            // no user row to attach the report to). Presented via UIKit
            // from the top of the presentation stack, not a root .sheet --
            // a root sheet can't present while any other sheet is up,
            // which killed the gesture on exactly the modal screens
            // (paywall, gym photo) where bugs get reported.
            .onShake {
                if appState.screen != .onboarding {
                    FeedbackPresenter.present()
                }
            }
            // Whoop/Oura/Google OAuth all complete via ASWebAuthenticationSession's
            // own in-process callback, not a deep link back into the app, so
            // this is exclusively for Superwall paywall previews/campaign
            // deep links -- no risk of double-handling an OAuth callback.
            .onOpenURL { url in
                Superwall.handleDeepLink(url)
            }
            // The visual design (white cards, pale-blue gradient, navy
            // pills) is a fixed light aesthetic per spec, not an adaptive
            // one -- without this, system text colors (.primary/.secondary)
            // invert to white in Dark Mode and become unreadable against
            // the still-light background.
            .preferredColorScheme(.light)
        }
    }
}
