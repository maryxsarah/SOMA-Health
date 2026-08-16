import SwiftUI

/// Last 30 days of logged workouts -- reachable from ProfileView. Distinct
/// from Home's calendar strip (which only shows a crown dot per day): this
/// is the actual list the backlog asked for, so the user can see what was
/// trained, when, and whether it was completed, without tapping through
/// each day individually.
struct TrainingHistoryView: View {
    @State private var logs: [WorkoutLogEntry] = []
    @State private var isLoading = true
    @State private var selectedDate: String?
    /// Feeds DayDetailView's "best readiness of the week" crown -- same
    /// 7-day window and source Home's calendar strip already uses.
    @State private var recentRecommendations: [DailyRecommendation] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else if logs.isEmpty {
                        CardView {
                            Text(String(localized: "trainingHistory.empty.title", defaultValue: "No workouts logged yet", comment: "Training history: empty-state title"))
                                .font(.body.bold())
                            Text(String(localized: "trainingHistory.empty.subtitle", defaultValue: "Completed workouts from the last 30 days will show up here.", comment: "Training history: empty-state subtitle"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(logs) { log in
                            Button {
                                selectedDate = log.date
                            } label: {
                                CardView {
                                    HStack(alignment: .top) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(log.title)
                                                .font(.body.bold())
                                                .foregroundStyle(.primary)
                                            Text("\(formattedDate(log.date)) — \(BodyPartFocus(rawValue: log.bodyPart)?.displayName ?? log.bodyPart)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(20)
            }
            .somaBackground()
            .navigationTitle(String(localized: "trainingHistory.navigationTitle", defaultValue: "Training History", comment: "Navigation title for the training history list"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: Binding(
            get: { selectedDate != nil },
            set: { if !$0 { selectedDate = nil } }
        )) {
            if let selectedDate {
                DayDetailView(date: selectedDate, recentRecommendations: recentRecommendations)
            }
        }
        .task { await load() }
    }

    private func formattedDate(_ dateString: String) -> String {
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        parser.timeZone = .current
        guard let parsed = parser.date(from: dateString) else { return dateString }

        let display = DateFormatter()
        display.dateStyle = .medium
        return display.string(from: parsed)
    }

    private func load() async {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -29, to: end) ?? end

        logs = (try? await SupabaseClient.shared.fetchWorkoutLogs(
            fromDate: formatter.string(from: start),
            toDate: formatter.string(from: end)
        )) ?? []
        recentRecommendations = (try? await SupabaseClient.shared.fetchRecentRecommendations()) ?? []
        isLoading = false
    }
}

#Preview {
    TrainingHistoryView()
}
