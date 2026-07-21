import SwiftUI

/// Sheet shown when tapping the Home recommendation card. Everything here
/// is fixed, template-driven content (per-category step target/workouts,
/// per-reason explanation/tip, with real numbers substituted in) -- no
/// AI-generated freeform text, matching the rest of the app's approach.
struct RecommendationDetailView: View {
    let recommendation: DailyRecommendation

    @State private var snapshots: [DailySnapshotRow] = []
    @State private var averageSteps: Double?
    @State private var profile: UserProfile = .empty

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(recommendation.category.displayTitle)
                        .font(Theme.display)
                    Text(recommendation.message)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                CardView {
                    Text("Today's step target")
                        .font(.body.bold())
                    Text(recommendation.category.stepTarget)
                        .font(.title2.bold())
                        .foregroundStyle(Theme.pillFill)
                    if let averageSteps {
                        Text("You've averaged ~\(Int(averageSteps)) steps/day over the last week.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                CardView {
                    Text("Workouts that fit today")
                        .font(.body.bold())
                    if !profile.equipment.isEmpty || !profile.injuryTags.isEmpty {
                        Text("Tailored to your saved equipment and injuries.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(filteredWorkoutSuggestions) { suggestion in
                        Label(suggestion.title, systemImage: "checkmark.circle")
                            .font(.subheadline)
                    }
                }

                CardView {
                    Text("Why today")
                        .font(.body.bold())
                    Text(explanationText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if recommendation.sleepCapApplied {
                        Text("Note: today's intensity was capped because of short sleep, even though recovery looked strong.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if recommendation.injuryCapApplied {
                        Text("Note: today's intensity was capped because of a noted injury, even though recovery looked strong.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                CardView {
                    Text("Look out for tomorrow")
                        .font(.body.bold())
                    Text(recommendation.reason.tomorrowTip)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .somaBackground()
        .task {
            await loadContext()
        }
    }

    private var explanationText: String {
        switch recommendation.reason {
        case .whoopHigh, .whoopMedium, .whoopLow:
            let value = snapshots.first(where: { $0.source == "whoop" })?.recoveryScore
            return String(format: recommendation.reason.explanationTemplate, formattedNumber(value))
        case .ouraHigh, .ouraMediumHigh, .ouraMedium, .ouraLow:
            let value = snapshots.first(where: { $0.source == "oura" })?.readinessScore
            return String(format: recommendation.reason.explanationTemplate, formattedNumber(value))
        case .healthkitHigh, .healthkitMedium, .healthkitLow, .unknown:
            return recommendation.reason.explanationTemplate
        }
    }

    private func formattedNumber(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(Int(value.rounded()))
    }

    /// Filters the fixed candidate list down to what the user's saved
    /// equipment/injuries actually support, then prioritizes matches for
    /// their saved goals. Never returns an empty list -- falls back to the
    /// unfiltered set if filtering would otherwise leave nothing to show.
    private var filteredWorkoutSuggestions: [WorkoutSuggestion] {
        let all = recommendation.category.workoutSuggestions
        let hasInjury = !profile.injuryTags.isEmpty

        var candidates = profile.equipment.isEmpty
            ? all
            : all.filter { $0.equipment == .bodyweightOnly || profile.equipment.contains($0.equipment) }

        if hasInjury {
            candidates = candidates.filter { !$0.highImpact }
        }
        if candidates.isEmpty {
            candidates = all
        }

        guard !profile.goals.isEmpty else { return candidates }
        let goalSet = Set(profile.goals)
        // Stable sort: matching-goal suggestions float to the top, ties
        // otherwise keep their original order.
        return candidates.sorted { lhs, rhs in
            let lhsMatches = !lhs.goals.isDisjoint(with: goalSet)
            let rhsMatches = !rhs.goals.isDisjoint(with: goalSet)
            return lhsMatches && !rhsMatches
        }
    }

    private func loadContext() async {
        async let snapshotFetch: [DailySnapshotRow]? = try? SupabaseClient.shared.fetchTodaysSnapshots(date: recommendation.date)
        async let stepsFetch: Double? = HealthKitManager.isAvailable ? await HealthKitManager.shared.fetchRecentAverageSteps() : nil
        async let profileFetch = fetchProfileSafely()

        snapshots = await snapshotFetch ?? []
        averageSteps = await stepsFetch
        profile = await profileFetch
    }

    private func fetchProfileSafely() async -> UserProfile {
        guard let userId = SupabaseClient.shared.currentUserID else { return .empty }
        return (try? await SupabaseClient.shared.fetchProfile(id: userId)) ?? .empty
    }
}

#Preview {
    RecommendationDetailView(
        recommendation: DailyRecommendation(
            date: "2026-07-21",
            category: .light,
            message: "Take it easier today — a short walk, mobility work, or light yoga (20-30 min) is ideal.",
            reason: .healthkitMedium,
            sleepCapApplied: false,
            injuryCapApplied: false
        )
    )
}
