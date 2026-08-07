import Foundation

/// What the body did during a specific logged workout's window, from
/// whichever source actually reported it -- HealthKit (on-device) is tried
/// first since it needs no external API round-trip and has no
/// availability uncertainty; a connected wearable is the fallback. Shared
/// by DayDetailView and CompletedWorkoutView so both read the exact same
/// real numbers for a given log entry, never a re-derived estimate.
struct WearableSessionSummary {
    let averageHeartRate: Int
    let maxHeartRate: Int
    let source: String

    var sourceDisplayName: String {
        switch source {
        case "whoop": "Whoop"
        case "oura": "Oura"
        case "apple_health": "Apple Health"
        default: source.capitalized
        }
    }

    /// nil when the log has no reliable start/end window, or nothing
    /// reported heart rate for it -- callers render a "no wearable data"
    /// empty state in that case rather than treating it as an error.
    static func fetch(for log: WorkoutLogEntry) async -> WearableSessionSummary? {
        guard let startedAtString = log.startedAt, let endedAtString = log.endedAt,
              let start = parseDate(startedAtString), let end = parseDate(endedAtString)
        else { return nil }

        if HealthKitManager.isAvailable,
           let hkSummary = await HealthKitManager.shared.fetchHeartRateSummary(start: start, end: end) {
            return WearableSessionSummary(
                averageHeartRate: Int(hkSummary.average.rounded()),
                maxHeartRate: Int(hkSummary.max.rounded()),
                source: "apple_health"
            )
        }

        guard let entries = try? await SupabaseClient.shared.fetchProviderWorkoutTimeline(date: log.date, startTime: start, endTime: end) else {
            return nil
        }
        guard let entry = entries.first(where: { $0.averageHeartRate != nil && $0.maxHeartRate != nil }) else {
            return nil
        }
        return WearableSessionSummary(
            averageHeartRate: entry.averageHeartRate!,
            maxHeartRate: entry.maxHeartRate!,
            source: entry.source
        )
    }

    private static func parseDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plainFormatter = ISO8601DateFormatter()
        return formatter.date(from: string) ?? plainFormatter.date(from: string)
    }
}
