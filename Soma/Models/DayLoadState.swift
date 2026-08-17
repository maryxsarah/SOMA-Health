import Foundation

/// How much of today's activity target a logged workout actually closed --
/// lets Home/RecommendationDetail/CompletedWorkout all agree on whether
/// today still needs a nudge toward more activity, or whether the day is
/// already done (or overdone). Derived purely from what's already logged;
/// never recomputed server-side, never persisted -- a pure function of
/// today's WorkoutLogEntry.caloriesBurned vs. the category's own
/// dayLoadTargetKcal, so it's always in sync with whatever's on screen.
enum DayLoadState {
    /// Nothing logged yet today.
    case pending
    /// Something's logged, but well under the day's target.
    case partiallyDone
    /// At or reasonably above the day's target.
    case fulfilled
    /// Well past the day's target -- no further nudge belongs here.
    case overreached

    /// Thresholds are multiples of the category's dayLoadTargetKcal, not
    /// hardcoded absolute numbers, so they scale with today's category.
    private static let fulfilledThreshold = 1.0
    private static let overreachedThreshold = 1.5

    /// `hasLoggedWorkout` and `loggedKcal` are separate on purpose: a
    /// workout can be logged before its calorie estimate/reading resolves
    /// (see WorkoutLogEntry.caloriesBurned's own doc comment), and that
    /// case must still count as done -- not silently fall back to
    /// `.pending` and keep pitching a session the user already completed.
    static func resolve(hasLoggedWorkout: Bool, loggedKcal: Int?, target: Int) -> DayLoadState {
        guard hasLoggedWorkout else { return .pending }
        guard let loggedKcal, loggedKcal > 0, target > 0 else { return .fulfilled }
        let ratio = Double(loggedKcal) / Double(target)
        if ratio >= overreachedThreshold { return .overreached }
        if ratio >= fulfilledThreshold { return .fulfilled }
        return .partiallyDone
    }
}
