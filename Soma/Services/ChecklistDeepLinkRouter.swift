import Foundation

/// Carries a checklist-nudge notification tap from AppDelegate (a plain
/// UIApplicationDelegate, with no access to the SwiftUI-owned AppState
/// instance) into HomeView. Same `.shared` singleton shape as
/// SupabaseClient/NotificationManager/HealthKitManager elsewhere in this
/// codebase -- deliberately not folded into AppState itself, since
/// AppState is constructed by SomaApp as a @StateObject with no path for
/// AppDelegate to reach it.
@MainActor
final class ChecklistDeepLinkRouter: ObservableObject {
    static let shared = ChecklistDeepLinkRouter()

    /// HomeView observes this, opens the matching sheet, then clears it
    /// back to nil so re-foregrounding the app later doesn't re-trigger
    /// the same navigation.
    @Published var pending: ChecklistDeepLink?

    private init() {}

    func route(rawValue: String) {
        switch rawValue {
        case "logMeal": pending = .logMeal
        case "healthDashboard": pending = .healthDashboard
        case "startWorkout": pending = .startWorkout
        default: break
        }
    }
}
