import SwiftUI

/// Sheet shown when tapping a day on Home's calendar strip -- that day's
/// category/message plus any workouts logged that day. Read-only, no
/// tap-through actions (those live on today's RecommendationDetailView).
struct DayDetailView: View {
    let date: String

    @State private var recommendation: DailyRecommendation?
    @State private var logs: [WorkoutLogEntry] = []
    /// Wearable heart-rate summary per logged workout, keyed by
    /// WorkoutLogEntry.id -- only populated for entries with a real
    /// started_at/ended_at window (see SupabaseClient.logWorkout). A
    /// missing entry (not even attempted) vs. a present-but-nil summary
    /// both render the same "no wearable data" empty state -- the
    /// distinction doesn't matter to the user.
    @State private var wearableSummaries: [String: WearableSessionSummary] = [:]
    @State private var isLoading = true

    /// What the body did, from whichever source actually reported it for
    /// this exact window -- HealthKit (on-device) is tried first since it
    /// needs no external API round-trip and has no availability
    /// uncertainty; a connected wearable is the fallback.
    struct WearableSessionSummary {
        let averageHeartRate: Int
        let maxHeartRate: Int
        let source: String
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(formattedDate)
                    .font(Theme.display)

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else if let recommendation {
                    CardView {
                        Text(recommendation.category.displayTitle)
                            .font(.body.bold())
                        Text(recommendation.message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if !logs.isEmpty {
                        CardView {
                            Text("Workouts logged")
                                .font(.body.bold())
                            ForEach(logs) { log in
                                VStack(alignment: .leading, spacing: 8) {
                                    Label(
                                        "\(log.title) — \(BodyPartFocus(rawValue: log.bodyPart)?.displayName ?? log.bodyPart)",
                                        systemImage: "checkmark.circle.fill"
                                    )
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                    // What was performed -- SOMA's own
                                    // logged data. Entries logged before
                                    // plan_snapshot existed just show the
                                    // label above, same as always.
                                    if let planSnapshot = log.planSnapshot {
                                        Text("What was performed")
                                            .font(.caption.bold())
                                            .foregroundStyle(.secondary)
                                        AIWorkoutPlanView(plan: planSnapshot)
                                    }

                                    // How the body responded -- from the
                                    // connected wearable, time-windowed to
                                    // this specific session, never the
                                    // whole day's data. Only shown at all
                                    // for entries that captured a real
                                    // start/end window in the first place.
                                    if log.startedAt != nil, log.endedAt != nil {
                                        Divider().padding(.vertical, 2)
                                        Text("How the body responded")
                                            .font(.caption.bold())
                                            .foregroundStyle(.secondary)
                                        if let summary = wearableSummaries[log.id] {
                                            Text("Avg \(summary.averageHeartRate) bpm, max \(summary.maxHeartRate) bpm (\(summary.sourceDisplayName))")
                                                .font(.subheadline)
                                        } else {
                                            Text("No wearable data available for this session.")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .padding(.top, 4)
                            }
                        }
                    }
                } else {
                    CardView {
                        Text("No data for this day")
                            .font(.body.bold())
                        Text("Either it's before you connected a device, or no data came in that day.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(20)
        }
        .somaBackground()
        .task { await load() }
    }

    private var formattedDate: String {
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        parser.timeZone = .current
        guard let parsed = parser.date(from: date) else { return date }

        let display = DateFormatter()
        display.dateStyle = .full
        return display.string(from: parsed)
    }

    private func load() async {
        async let recommendationFetch: DailyRecommendation? = try? SupabaseClient.shared.fetchTodaysRecommendation(date: date)
        async let logsFetch: [WorkoutLogEntry] = (try? await SupabaseClient.shared.fetchWorkoutLogs(date: date)) ?? []

        recommendation = await recommendationFetch
        logs = await logsFetch

        for log in logs where log.startedAt != nil && log.endedAt != nil {
            if let summary = await fetchWearableSummary(for: log) {
                wearableSummaries[log.id] = summary
            }
        }
        isLoading = false
    }

    /// HealthKit first (on-device, no external API uncertainty), then
    /// whichever connected wearable actually reports heart rate for this
    /// exact window (see fetch-workout-timeline's own honest-gap handling
    /// -- Oura never reports HR, Whoop does when its API returns it).
    private func fetchWearableSummary(for log: WorkoutLogEntry) async -> WearableSessionSummary? {
        guard let startedAtString = log.startedAt, let endedAtString = log.endedAt,
              let start = Self.parseDate(startedAtString), let end = Self.parseDate(endedAtString)
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

private extension DayDetailView.WearableSessionSummary {
    var sourceDisplayName: String {
        switch source {
        case "whoop": "Whoop"
        case "oura": "Oura"
        case "apple_health": "Apple Health"
        default: source.capitalized
        }
    }
}

#Preview {
    DayDetailView(date: "2026-07-22")
}
