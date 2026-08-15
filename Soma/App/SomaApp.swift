import SuperwallKit
import SwiftUI

@main
struct SomaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()
    @StateObject private var sessionManager = SessionManager()
    @StateObject private var languageManager = LanguageManager.shared

    init() {
        // Must precede AppState's first read of the keychain/UserDefaults.
        // (@StateObject defers its wrappedValue autoclosure past this body.)
        UITestSupport.bootstrapIfNeeded()
    }

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
            .environmentObject(languageManager)
            // Live in-app language override (Profile -> Account -> Language).
            // `.system` resolves to `.autoupdatingCurrent`, so leaving this
            // on its default tracks the device's language exactly as if
            // this modifier weren't here at all.
            .environment(\.locale, languageManager.effectiveLocale)
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
            // this remains Superwall's alone -- except the one universal
            // link this app owns (the signup-confirmation email's "Commit
            // now to your goal" button), handled separately below rather
            // than forwarded to Superwall.
            .onOpenURL { url in
                // www, not bare -- must match Config.emailConfirmationRedirectURL
                // and the Associated Domains entitlement exactly. See
                // either's doc comment for why (soma4health.com
                // redirects to www, which breaks Apple's AASA fetch).
                if url.host == "www.soma4health.com", url.path == "/auth/confirm" {
                    handleEmailConfirmation(url)
                } else {
                    Superwall.handleDeepLink(url)
                }
            }
            // The visual design (white cards, pale-blue gradient, navy
            // pills) is a fixed light aesthetic per spec, not an adaptive
            // one -- without this, system text colors (.primary/.secondary)
            // invert to white in Dark Mode and become unreadable against
            // the still-light background.
            .preferredColorScheme(.light)
        }
    }

    /// Universal-link landing for the branded signup-confirmation email
    /// (supabase/email-templates/confirm-signup.html's "Commit now to
    /// your goal" button, via {{ .ConfirmationURL }} -> Supabase's hosted
    /// verify endpoint -> this URL). Establishes the session and advances
    /// exactly like markSignedIn() -- the same next screen (.survey) the
    /// user would have reached had email confirmation not been required
    /// in between, rather than app launch/Home.
    ///
    /// A tapped-twice or expired link fails here (Supabase redirects an
    /// invalid token to this same URL with `error_description` in the
    /// query instead of tokens in the fragment) -- surfaced via
    /// sessionManager.errorMessage, the same slot OnboardingView already
    /// shows sign-in failures in, since that's where this always lands
    /// (screen is still .onboarding until a session is actually
    /// established).
    private func handleEmailConfirmation(_ url: URL) {
        guard let fragment = url.fragment else {
            let description = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "error_description" }?.value
            sessionManager.errorMessage = description?.removingPercentEncoding
                ?? "That confirmation link has expired. Sign up again to get a new one."
            return
        }
        Task {
            do {
                try await SupabaseClient.shared.completeEmailConfirmation(fragment: fragment)
                AnalyticsManager.shared.signupCompleted()
                await appState.markSignedIn()
            } catch {
                sessionManager.errorMessage = "That confirmation link didn't work. Try signing up again."
            }
        }
    }
}
