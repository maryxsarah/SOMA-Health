import Foundation

/// Streak badge tiers shown in Profile -- purely derived from the
/// existing completed-workout streak count (ProfileView's real
/// completedWorkoutStreak, same source as the Home calendar strip's crown
/// badges). No separate persistence of its own; a milestone is "achieved"
/// simply when the current streak has reached its day count.
enum StreakMilestone: Int, CaseIterable, Identifiable {
    case threeDay = 3
    case week = 7
    case twoWeek = 14
    case month = 30
    case sixtyDay = 60
    case hundredDay = 100
    case year = 365

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .threeDay: return "3 Days"
        case .week: return "1 Week"
        case .twoWeek: return "2 Weeks"
        case .month: return "1 Month"
        case .sixtyDay: return "60 Days"
        case .hundredDay: return "100 Days"
        case .year: return "1 Year"
        }
    }

    func isAchieved(streak: Int) -> Bool { streak >= rawValue }
}
