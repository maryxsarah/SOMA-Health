import Foundation

/// Where tapping a checklist row should take the user -- HomeView owns the
/// actual sheet-presentation @State for each of these; this enum is just
/// the "which one" signal, same role WorkoutLogEntry.source plays for
/// CompletedWorkoutView's routing.
enum ChecklistDeepLink: Equatable {
    case logMeal
    case healthDashboard
    case moodCheckIn
    case startWorkout
    case progressPicture
    case profileGoals
    case profileKitchenEquipment
    case connectDevices
    case enableNotifications
}

/// One row in the daily checklist card. `isChecked` is always freshly
/// computed by DailyChecklistProgress -- this struct never stores whether
/// something is checked independently of that computation, so a row can
/// never disagree with the data it's supposedly reflecting.
struct DailyChecklistItem: Identifiable, Equatable {
    let key: String
    let title: String
    let subtitle: String
    let isChecked: Bool
    /// True for rows with no automatic signal -- tapping the row itself
    /// toggles it (via DailyChecklistState) rather than opening a deep
    /// link. A row is either manual OR has a deepLink, never both: a
    /// manual row's only "action" IS the check, so there's nothing else
    /// for a tap to open.
    let isManual: Bool
    let deepLink: ChecklistDeepLink?
    /// Only meaningful for the standard-mode progress-picture row -- days
    /// until it's actionable again. Nil everywhere else.
    let daysUntilNextAvailable: Int?

    var id: String { key }
}

/// Mirrors a `daily_checklist_state` row -- see that migration's own
/// comment for what "scope" and "date" mean for onboarding vs. daily rows.
struct DailyChecklistStateRow: Decodable {
    let itemKey: String
    let date: String

    enum CodingKeys: String, CodingKey {
        case itemKey = "item_key"
        case date
    }
}
