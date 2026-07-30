import UIKit

/// The one place that knows how to deep-link into the app's Settings page
/// -- the URL-guard + open dance was already pasted into two views
/// (OnboardingView's Apple ID hint, the gym-photo camera explainer), and
/// every future permission-explainer screen would have made a third copy.
/// Callers keep their own button styling; only the action is shared.
@MainActor
enum SystemSettings {
    static func open() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
