import Foundation

/// One actual recorded workout session for the day -- merged client-side
/// from two origins: HealthKit (read on-device, since Apple doesn't let a
/// server read HealthKit) and connected wearables (Oura/Whoop, read via
/// fetch-workout-timeline). Distinct from `WorkoutLogEntry`, which is what
/// the user told Soma they did -- this is what the source actually
/// recorded, shown as a timeline under today's recommendation.
struct WorkoutTimelineEntry: Identifiable {
    let id = UUID()
    let source: String
    let title: String
    let startTime: Date
    let durationMinutes: Int
    let calories: Int?
    /// Nil whenever the source doesn't report it -- Oura's workout
    /// collection never does (no fabricated number in its place); Whoop's
    /// does, when its own API returns it for that session. Defaults nil so
    /// HealthKit-sourced entries (which never carry this) don't need to
    /// pass it explicitly.
    let averageHeartRate: Int?
    let maxHeartRate: Int?
    /// Stable machine key for the underlying HKWorkoutActivityType (e.g.
    /// "walking", "running") -- distinct from `title`, which is a
    /// user-facing display string and shouldn't be pattern-matched on.
    /// Nil for provider (Oura/Whoop) entries, which don't carry this
    /// concept, and for synced-from-another-device entries synced before
    /// this column existed.
    let activityType: String?

    init(source: String, title: String, startTime: Date, durationMinutes: Int, calories: Int?, averageHeartRate: Int? = nil, maxHeartRate: Int? = nil, activityType: String? = nil) {
        self.source = source
        self.title = title
        self.startTime = startTime
        self.durationMinutes = durationMinutes
        self.calories = calories
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
        self.activityType = activityType
    }

    /// Real feedback: "I went for a 2k steps walk, but SOMA is not giving
    /// me a workout ... only when a workout is picked from the wearable
    /// device (a real workout, not just a walk) should SOMA mark the day
    /// as done." HealthKit logs even an incidental everyday walk as its
    /// own HKWorkout, so duration/calories alone can't tell a deliberate
    /// session apart from a walk to the shops -- the activity type can.
    var isWalk: Bool { activityType == "walking" }

    var sourceDisplayName: String {
        switch source {
        case "whoop": "Whoop"
        case "oura": "Oura"
        case "apple_health": "Apple Health"
        default: source.capitalized
        }
    }

    /// Used by HomeView's auto-log-from-device-detection pass (see
    /// autoLogDeviceDetectedWorkoutIfNeeded) to give an auto-created
    /// workout_log row SOME category rather than none -- a rough proxy
    /// only, since calorie burn rate correlates with intensity but isn't
    /// a substitute for the AI plan's own category signal. Missing
    /// calories (Oura's workout collection never reports them) falls
    /// back to the safe middle default rather than guessing low or high.
    var inferredCategory: String {
        guard let calories, durationMinutes > 0 else { return "moderate" }
        let caloriesPerMinute = Double(calories) / Double(durationMinutes)
        if caloriesPerMinute >= 10 { return "push_hard" }
        if caloriesPerMinute >= 6 { return "moderate" }
        return "light"
    }

    /// Pure selection logic behind HomeView's autoLogDeviceDetectedWorkoutIfNeeded:
    /// which (if any) of today's device-detected timeline entries should
    /// auto-satisfy the day and suppress a generated workout. A trivial
    /// multi-minute entry (HealthKit logs even a short walk as its own
    /// "workout") shouldn't count, and neither should a walk of ANY length
    /// -- real feedback confirmed a walk must never substitute for a real
    /// workout, however long it runs. Among the remaining candidates,
    /// prefers the longest session over merely the chronologically-first.
    static func qualifyingAutoLogCandidate(
        from entries: [WorkoutTimelineEntry],
        minimumMinutes: Int = 10
    ) -> WorkoutTimelineEntry? {
        entries
            .filter { $0.durationMinutes >= minimumMinutes && !$0.isWalk }
            .max(by: { $0.durationMinutes < $1.durationMinutes })
    }
}
