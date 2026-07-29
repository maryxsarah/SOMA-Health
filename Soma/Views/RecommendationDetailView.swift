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
    @State private var loggedTitlesToday: Set<String> = []
    @State private var recentBodyPartCounts: [BodyPartFocus: Int] = [:]
    @State private var shuffleSeed: UInt64 = 0
    @State private var selectedTitle: String?
    @State private var selectedBodyPart: String?
    @State private var selectedDurationRange: ClosedRange<Int>?
    @State private var preGenerationNotes = ""
    @State private var aiPlan: AIWorkoutPlan?
    @State private var isLoadingAIPlan = false
    @State private var aiPlanError: String?

    @State private var isMarkingComplete = false
    @State private var feedbackText = ""
    @State private var addonSuggestions: [String] = []
    @State private var isFetchingAddons = false

    /// Lets HomeView hand off an already-generated gym-photo plan so it
    /// shows up here immediately -- the "Take a Picture of Your Gym" entry
    /// point now lives on Home (not here), so this is the only way a
    /// gym-photo result reaches this view.
    init(recommendation: DailyRecommendation, seededPlan: AIWorkoutPlan? = nil, seededTitle: String? = nil, seededBodyPart: String? = nil) {
        self.recommendation = recommendation
        _aiPlan = State(initialValue: seededPlan)
        _selectedTitle = State(initialValue: seededTitle)
        _selectedBodyPart = State(initialValue: seededBodyPart)
    }

    /// True once the user has explicitly logged today's workout as done
    /// (via "Mark Workout Complete") -- generating/viewing an AI plan does
    /// NOT complete it, only tapping that button does. Only one workout is
    /// tracked per day, matching the single daily category/recommendation
    /// model, so once true the day's pick is locked in.
    private var isCompletedToday: Bool { !loggedTitlesToday.isEmpty }

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
                    HStack {
                        Text("Workouts that fit today")
                            .font(.body.bold())
                        Spacer()
                        Button {
                            shuffleSeed += 1
                        } label: {
                            Label("Try another", systemImage: "arrow.triangle.2.circlepath")
                                .font(.caption.bold())
                        }
                    }
                    Text(isCompletedToday ? "Today's pick, completed." : "Check the one you want to do today, then tap Generate AI Workout.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(filteredWorkoutSuggestions) { suggestion in
                        workoutRow(suggestion)
                    }
                }

                CardView {
                    Text("AI-generated workout")
                        .font(.body.bold())
                    Text("Exact exercises, sets, weights, and how to do each one -- built around the workout you picked above.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let aiPlan {
                        AIWorkoutPlanView(plan: aiPlan)

                        if isCompletedToday {
                            Label("Workout completed today", systemImage: "crown.fill")
                                .font(.subheadline.bold())
                                .foregroundStyle(.yellow)
                                .padding(.top, 10)

                            if isFetchingAddons {
                                HStack {
                                    ProgressView()
                                    Text("Thinking of ideas for next time…")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.top, 6)
                            } else if !addonSuggestions.isEmpty {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Ideas for next time, based on your feedback")
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                    ForEach(addonSuggestions, id: \.self) { suggestion in
                                        Text("• \(suggestion)")
                                            .font(.caption)
                                    }
                                }
                                .padding(.top, 6)
                            }
                        } else {
                            if let aiPlanError {
                                Text(aiPlanError)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                            TextField("Feedback for next time (optional)", text: $feedbackText, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(2...4)
                                .padding(.top, 8)
                            PillButton(title: "Mark Workout Complete", isEnabled: !isMarkingComplete) {
                                Task { await markWorkoutComplete() }
                            }
                            .padding(.top, 8)
                        }
                    } else if isLoadingAIPlan {
                        HStack {
                            ProgressView()
                            Text("Building your plan…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 4)
                    } else {
                        if let aiPlanError {
                            Text(aiPlanError)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        if selectedTitle == nil {
                            Text("Check a workout above first.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                        } else {
                            TextField("Anything Soma should know for today's workout? (optional)", text: $preGenerationNotes, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(2...4)
                                .padding(.top, 4)
                        }
                        PillButton(title: "Generate AI Workout", isEnabled: selectedTitle != nil && !isLoadingAIPlan) {
                            Task { await loadAIPlan() }
                        }
                        .padding(.top, 4)
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
                    if recommendation.loadCapApplied {
                        Text("Note: today's intensity was capped because of a strenuous session very recently, even though recovery looked strong.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    // Says out loud when the read is thin. Without this a run
                    // of identical days is indistinguishable from the app
                    // being broken -- which is exactly how testers read it.
                    if let caveat = recommendation.dataConfidence?.caveat {
                        Text(caveat)
                            .font(.caption)
                            .foregroundStyle(.secondary)
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

    /// A single-select checkbox per suggestion -- checking one is what
    /// "Generate AI Workout" builds its plan around. Locked once a workout
    /// has been logged for the day (see `isCompletedToday`), so the choice
    /// can't be swapped out from under an already-generated plan.
    private func workoutRow(_ suggestion: WorkoutSuggestion) -> some View {
        let isSelected = selectedTitle == suggestion.title
        return Button {
            selectedTitle = suggestion.title
            selectedBodyPart = suggestion.bodyPart.rawValue
            selectedDurationRange = suggestion.targetDurationMinutes
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isSelected ? Theme.pillFill : .secondary)
                    .font(.body)
                VStack(alignment: .leading, spacing: 2) {
                    if suggestion.id == filteredWorkoutSuggestions.first?.id {
                        Text("SOMA TOP RECOMMENDATION")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Theme.pillFill))
                    }
                    Text(suggestion.title)
                        .font(.subheadline)
                    Text(suggestion.bodyPart.displayName)
                        .font(.caption2.bold())
                        .foregroundStyle(Theme.pillFill)
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .disabled(isCompletedToday)
        .opacity(isCompletedToday && !isSelected ? 0.4 : 1)
        .padding(.vertical, 4)
    }

    /// Filters the fixed candidate list down to what the user's saved
    /// equipment/injuries actually support, prioritizes matches for their
    /// saved goals, then deprioritizes (not removes) whichever body parts
    /// have been trained most in the last 7 days -- avoids stacking the
    /// same muscle group repeatedly across the week, not just avoiding an
    /// exact repeat of yesterday. "Try another" reshuffles within what's
    /// left via a seeded shuffle, so repeated taps give a different order
    /// deterministically rather than a fresh random flicker each render.
    /// Never returns an empty list -- falls back to the unfiltered set if
    /// filtering would otherwise leave nothing to show. The first item in
    /// this ranked order is shown as "SOMA Top Recommendation" in
    /// `workoutRow`.
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

        if shuffleSeed > 0 {
            var rng = SeededGenerator(seed: shuffleSeed)
            candidates.shuffle(using: &rng)
        }

        let goalSet = Set(profile.goals)
        // Stable sort: matching-goal suggestions float to the top, then
        // whichever body part has been trained less recently/frequently
        // this week floats above one trained more (repeat, not remove --
        // still selectable if the user actually wants to repeat a lift).
        return candidates.sorted { lhs, rhs in
            let lhsGoalMatch = !lhs.goals.isDisjoint(with: goalSet)
            let rhsGoalMatch = !rhs.goals.isDisjoint(with: goalSet)
            if lhsGoalMatch != rhsGoalMatch { return lhsGoalMatch && !rhsGoalMatch }

            let lhsCount = recentBodyPartCounts[lhs.bodyPart] ?? 0
            let rhsCount = recentBodyPartCounts[rhs.bodyPart] ?? 0
            return lhsCount < rhsCount
        }
    }

    /// Generates (or fetches the cached) AI plan around whatever's checked
    /// above. This only builds/shows the plan -- it does NOT mark the
    /// workout done. Completion is a separate explicit step
    /// (`markWorkoutComplete`), so the user can review the plan before
    /// committing to having done it.
    ///
    /// Reads `selectedTitle`/`selectedBodyPart` directly rather than
    /// looking the title up in `recommendation.category.workoutSuggestions`
    /// -- a gym-photo-generated workout's title/bodyPart aren't in that
    /// fixed list, so a lookup would silently fail for it.
    private func loadAIPlan() async {
        guard let selectedTitle, let selectedBodyPart else { return }

        isLoadingAIPlan = true
        aiPlanError = nil
        defer { isLoadingAIPlan = false }
        let trimmedNotes = preGenerationNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            aiPlan = try await SupabaseClient.shared.fetchOrGenerateAIWorkoutPlan(
                date: recommendation.date,
                selectedTitle: selectedTitle,
                selectedBodyPart: selectedBodyPart,
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                targetDurationMinutes: selectedDurationRange
            )
        } catch SupabaseError.safetyBlocked(let message) {
            // Shown verbatim. A generic "try again in a moment" would be a
            // lie -- retrying cannot help, and the user would keep tapping.
            aiPlanError = message
        } catch SupabaseError.workoutLocked(let message) {
            aiPlanError = message
        } catch {
            aiPlanError = "Couldn't generate a plan right now. Try again in a moment."
        }
    }

    /// The explicit "I finished this" step -- creates the workout_log row
    /// that Home's calendar strip renders as a crown for the day.
    private func markWorkoutComplete() async {
        guard let selectedTitle, let selectedBodyPart else { return }

        isMarkingComplete = true
        aiPlanError = nil
        defer { isMarkingComplete = false }
        let trimmedFeedback = feedbackText.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await SupabaseClient.shared.logWorkout(
                date: recommendation.date,
                title: selectedTitle,
                bodyPart: selectedBodyPart,
                category: recommendation.category.rawValue,
                feedback: trimmedFeedback.isEmpty ? nil : trimmedFeedback
            )
            loggedTitlesToday.insert(selectedTitle)
            if !trimmedFeedback.isEmpty {
                await fetchAddonSuggestions(feedback: trimmedFeedback, title: selectedTitle, bodyPart: selectedBodyPart)
            }
        } catch {
            aiPlanError = "Couldn't log this workout. Try again."
        }
    }

    /// Best-effort -- if this fails, the workout is still logged fine, the
    /// user just doesn't see follow-up ideas this time.
    private func fetchAddonSuggestions(feedback: String, title: String, bodyPart: String) async {
        isFetchingAddons = true
        defer { isFetchingAddons = false }
        let bodyPartDisplay = BodyPartFocus(rawValue: bodyPart)?.displayName ?? bodyPart
        addonSuggestions = (try? await SupabaseClient.shared.fetchWorkoutAddonSuggestions(
            feedback: feedback,
            workoutTitle: title,
            bodyPart: bodyPartDisplay
        )) ?? []
    }

    private func loadContext() async {
        async let snapshotFetch: [DailySnapshotRow]? = try? SupabaseClient.shared.fetchTodaysSnapshots(date: recommendation.date)
        async let stepsFetch: Double? = HealthKitManager.isAvailable ? await HealthKitManager.shared.fetchRecentAverageSteps() : nil
        async let profileFetch = fetchProfileSafely()
        async let todaysLogsFetch: [WorkoutLogEntry] = (try? await SupabaseClient.shared.fetchWorkoutLogs(date: recommendation.date)) ?? []
        async let recentLogsFetch: [WorkoutLogEntry] = (try? await SupabaseClient.shared.fetchWorkoutLogs(
            fromDate: Self.daysBefore(6, of: recommendation.date),
            toDate: Self.daysBefore(1, of: recommendation.date)
        )) ?? []

        snapshots = await snapshotFetch ?? []
        averageSteps = await stepsFetch
        profile = await profileFetch
        let todaysLogs = await todaysLogsFetch
        loggedTitlesToday = Set(todaysLogs.map(\.title))
        recentBodyPartCounts = await recentLogsFetch.compactMap { BodyPartFocus(rawValue: $0.bodyPart) }
            .reduce(into: [:]) { counts, bodyPart in counts[bodyPart, default: 0] += 1 }

        // Already logged today (e.g. reopening the sheet) -- restore the
        // choice and pull the cached plan rather than leaving the picker
        // blank as if nothing had been done yet.
        if selectedTitle == nil, let alreadyLogged = todaysLogs.first {
            selectedTitle = alreadyLogged.title
            selectedBodyPart = alreadyLogged.bodyPart
            await loadAIPlan()
        }
    }

    private func fetchProfileSafely() async -> UserProfile {
        guard let userId = SupabaseClient.shared.currentUserID else { return .empty }
        return (try? await SupabaseClient.shared.fetchProfile(id: userId)) ?? .empty
    }

    private static func daysBefore(_ days: Int, of dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        guard let date = formatter.date(from: dateString),
              let earlier = Calendar.current.date(byAdding: .day, value: -days, to: date) else {
            return dateString
        }
        return formatter.string(from: earlier)
    }
}

/// Tiny deterministic RNG so "Try another" gives a stable, different order
/// per tap instead of reshuffling on every SwiftUI re-render.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 1 : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
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
            injuryCapApplied: false,
            loadCapApplied: false,
            dataConfidence: .low
        )
    )
}
