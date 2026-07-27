import SwiftUI

/// Sheet shown when tapping a day on Home's calendar strip -- that day's
/// category/message plus any workouts logged that day. Read-only, no
/// tap-through actions (those live on today's RecommendationDetailView).
struct DayDetailView: View {
    let date: String

    @State private var recommendation: DailyRecommendation?
    @State private var logs: [WorkoutLogEntry] = []
    @State private var isLoading = true

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
                                Label(
                                    "\(log.title) — \(BodyPartFocus(rawValue: log.bodyPart)?.displayName ?? log.bodyPart)",
                                    systemImage: "checkmark.circle.fill"
                                )
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
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
        isLoading = false
    }
}

#Preview {
    DayDetailView(date: "2026-07-22")
}
