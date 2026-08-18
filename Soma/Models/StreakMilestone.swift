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
        case .threeDay: return String(localized: "streakMilestone.threeDay", defaultValue: "3 Days", comment: "Streak milestone badge title")
        case .week: return String(localized: "streakMilestone.week", defaultValue: "1 Week", comment: "Streak milestone badge title")
        case .twoWeek: return String(localized: "streakMilestone.twoWeek", defaultValue: "2 Weeks", comment: "Streak milestone badge title")
        case .month: return String(localized: "streakMilestone.month", defaultValue: "1 Month", comment: "Streak milestone badge title")
        case .sixtyDay: return String(localized: "streakMilestone.sixtyDay", defaultValue: "60 Days", comment: "Streak milestone badge title")
        case .hundredDay: return String(localized: "streakMilestone.hundredDay", defaultValue: "100 Days", comment: "Streak milestone badge title")
        case .year: return String(localized: "streakMilestone.year", defaultValue: "1 Year", comment: "Streak milestone badge title")
        }
    }

    func isAchieved(streak: Int) -> Bool { streak >= rawValue }
}
