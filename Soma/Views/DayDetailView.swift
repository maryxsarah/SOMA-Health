import SwiftUI

/// Sheet shown when tapping a day on Home's calendar strip -- guide 03 of
/// the handoff. A day always resolves to exactly one state (done / todo /
/// skipped) and never renders "no data for this day": if nothing was
/// logged, the day still knows what was planned (or, for a date with no
/// recommendation row at all, says so plainly instead of pretending).
struct DayDetailView: View {
    let date: String
    /// The same 7-day window Home's calendar strip already fetched -- used
    /// only to check whether `date` is the week's best-readiness day, so
    /// this screen's crown line can never disagree with the strip's crown
    /// glyph (both derive from CalendarStripView.bestReadinessDate).
    let recentRecommendations: [DailyRecommendation]

    @Environment(\.dismiss) private var dismiss

    @State private var recommendation: DailyRecommendation?
    @State private var log: WorkoutLogEntry?
    @State private var plannedPlan: TodaysAIPlan?
    @State private var wearableSummary: WearableSessionSummary?
    @State private var snapshots: [DailySnapshotRow] = []
    @State private var isLoading = true

    @State private var showActionSheet = false
    @State private var showCompletedSheet = false
    @State private var showRescheduleInfo = false
    @State private var isCompleting = false
    @State private var completeError: String?

    private enum DayState {
        case done, todo, skipped, upcoming
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerBlock

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else {
                    readinessCard
                    workoutCard
                }
            }
            .padding(20)
            .padding(.bottom, 90)
        }
        .safeAreaInset(edge: .bottom) {
            if !isLoading { bottomBar }
        }
        .somaBackground()
        .task { await load() }
        .sheet(isPresented: $showActionSheet, onDismiss: { Task { await load() } }) {
            if let recommendation {
                RecommendationDetailView(recommendation: recommendation)
            }
        }
        .sheet(isPresented: $showCompletedSheet, onDismiss: { Task { await load() } }) {
            if let log {
                CompletedWorkoutView(log: log, isBestReadinessDay: isBestReadinessDay) { updated in
                    self.log = updated
                }
            }
        }
        .alert("Reschedule", isPresented: $showRescheduleInfo) {
            Button("Got it", role: .cancel) {}
        } message: {
            Text("Soma doesn't move workouts between days yet -- pick another day from the week strip on Home to do it there instead.")
        }
    }

    // MARK: - State

    private var state: DayState {
        if log != nil { return .done }
        if isToday { return .todo }
        // A future planned day isn't "Missed" -- only past days can be.
        return date > Self.todayString ? .upcoming : .skipped
    }

    private var isToday: Bool { date == Self.todayString }

    private var isBestReadinessDay: Bool {
        CalendarStripView.bestReadinessDate(among: recentRecommendations) == date
    }

    // MARK: - Header

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .foregroundStyle(SomaTokens.ink)
                }
                Spacer()
            }
            Text(formattedDate)
                .font(Theme.display)
            statusPill
            if isBestReadinessDay {
                Label("Best readiness of the week", systemImage: "crown.fill")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(SomaTokens.warn)
            }
        }
    }

    private var statusPill: some View {
        let info: (label: String, fg: Color, bg: Color, systemImage: String) = switch state {
        case .done: ("Completed", SomaTokens.heart, SomaTokens.heartSoft, "heart.fill")
        case .todo: ("Planned for today", SomaTokens.accent, SomaTokens.accentSoft, "heart")
        case .upcoming: ("Planned", SomaTokens.accent, SomaTokens.accentSoft, "heart")
        case .skipped: ("Missed", SomaTokens.ink3, SomaTokens.surface3, "heart")
        }
        return HStack(spacing: 4) {
            Image(systemName: info.systemImage).font(.system(size: 10))
            Text(info.label).font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(info.fg)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(info.bg))
    }

    // MARK: - Readiness card

    /// Existing app language, unchanged -- category/message the user
    /// already sees on Home, plus a "READINESS THAT DAY" eyebrow.
    @ViewBuilder
    private var readinessCard: some View {
        if let recommendation {
            CardView {
                Text("READINESS THAT DAY")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(SomaTokens.ink4)
                Text(recommendation.category.displayTitle)
                    .font(.system(size: 15, weight: .bold))
                Text(recommendation.message)
                    .font(.system(size: 14))
                    .foregroundStyle(SomaTokens.ink2)
            }
        }
    }

    // MARK: - Workout card

    /// 4pt left border in the state color -- the only place a colored
    /// left border is allowed, since it encodes state, not decoration.
    private var workoutCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch state {
            case .done:
                if let log {
                    Text(log.title)
                        .font(.system(size: 15, weight: .bold))
                    if let plan = log.planSnapshot {
                        blockDots(plan: plan)
                        AIWorkoutPlanView(plan: plan)
                    }
                    metaLine
                    footerChip
                }
            case .todo, .upcoming:
                if let plannedPlan {
                    Text(plannedPlan.selectedTitle)
                        .font(.system(size: 15, weight: .bold))
                    blockDots(plan: plannedPlan.plan)
                    AIWorkoutPlanView(plan: plannedPlan.plan)
                } else if let suggestion = topSuggestion {
                    Text(suggestion.title)
                        .font(.system(size: 15, weight: .bold))
                    Text("Not generated yet -- tap Start workout to build today's plan.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(SomaTokens.ink3)
                }
                metaLine
                footerChip
            case .skipped:
                Text(plannedTitleForSkippedDay)
                    .font(.system(size: 15, weight: .bold))
                metaLine
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: SomaTokens.rCard, style: .continuous)
                .fill(SomaTokens.surface)
                .somaCardShadow()
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(stateColor)
                .frame(width: 4)
                .padding(.vertical, 8)
        }
    }

    private var stateColor: Color {
        switch state {
        case .done: SomaTokens.heart
        case .todo, .upcoming: SomaTokens.accent
        case .skipped: SomaTokens.ink3
        }
    }

    /// 6pt state-colored dot + block name -- the same list is the plan
    /// when planned and the record when done.
    private func blockDots(plan: AIWorkoutPlan) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(plan.blocks) { block in
                HStack(spacing: 8) {
                    Circle().fill(stateColor).frame(width: 6, height: 6)
                    Text(block.name)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(SomaTokens.ink2)
                }
            }
        }
    }

    /// Switches per state: strain/avg bpm (done) -> why it fits (todo) ->
    /// why it's missing (skipped).
    @ViewBuilder
    private var metaLine: some View {
        switch state {
        case .done:
            if let wearableSummary {
                Text("Avg \(wearableSummary.averageHeartRate) bpm, max \(wearableSummary.maxHeartRate) bpm (\(wearableSummary.sourceDisplayName))")
                    .font(.system(size: 12.5))
                    .foregroundStyle(SomaTokens.ink3)
            }
        case .todo, .upcoming:
            if let recommendation {
                Text(recommendation.reason.explanation(snapshots: snapshots))
                    .font(.system(size: 12.5))
                    .foregroundStyle(SomaTokens.ink3)
            }
        case .skipped:
            Text("Two skips in a week breaks the streak.")
                .font(.system(size: 12.5))
                .foregroundStyle(SomaTokens.ink3)
        }
    }

    /// Self-rating (done) or required gear (planned).
    @ViewBuilder
    private var footerChip: some View {
        switch state {
        case .done:
            if let feelRating = log?.feelRating {
                SomaChip(title: feelRating.displayName, isSelected: true) {}
                    .allowsHitTesting(false)
            }
        case .todo, .upcoming:
            if let gear = requiredGear {
                SomaChip(title: gear, isSelected: false) {}
                    .allowsHitTesting(false)
            }
        case .skipped:
            EmptyView()
        }
    }

    private var requiredGear: String? {
        let title = plannedPlan?.selectedTitle
        let suggestions = recommendation?.category.workoutSuggestions ?? []
        return (suggestions.first(where: { $0.title == title }) ?? suggestions.first)?.equipment.displayName
    }

    private var topSuggestion: WorkoutSuggestion? {
        recommendation?.category.workoutSuggestions.first
    }

    /// What would have been suggested that day, derived from the day's own
    /// real recorded category -- never a fabricated specific workout.
    private var plannedTitleForSkippedDay: String {
        if let plannedPlan { return plannedPlan.selectedTitle }
        if let title = topSuggestion?.title { return title }
        return "No plan was recorded for this day"
    }

    // MARK: - Bottom bar

    @ViewBuilder
    private var bottomBar: some View {
        switch state {
        case .todo:
            VStack(spacing: 9) {
                if let completeError {
                    Text(completeError)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.red)
                }
                if plannedPlan != nil {
                    // A plan already exists for today -- the primary action
                    // is finishing it, not re-opening the generator.
                    SomaButton(title: "Complete workout", size: .lg, variant: .primary, isEnabled: !isCompleting) {
                        Task { await completePlannedWorkout() }
                    }
                    SomaButton(title: "View or swap workout", size: .md, variant: .secondary, isEnabled: recommendation != nil) {
                        showActionSheet = true
                    }
                } else {
                    SomaButton(title: "Start workout", size: .lg, variant: .primary, isEnabled: recommendation != nil) {
                        showActionSheet = true
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 22)
        case .skipped:
            if recommendation != nil {
                VStack(spacing: 9) {
                    SomaButton(title: "Log it anyway", size: .lg, variant: .primary) {
                        showActionSheet = true
                    }
                    SomaButton(title: "Reschedule", size: .md, variant: .secondary) {
                        showRescheduleInfo = true
                    }
                }
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 22)
            }
        case .done:
            VStack(spacing: 9) {
                SomaButton(title: "Do it again", size: .lg, variant: .primary) {
                    showActionSheet = true
                }
                SomaButton(title: "See full log", size: .md, variant: .secondary) {
                    showCompletedSheet = true
                }
            }
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 22)
        case .upcoming:
            EmptyView()
        }
    }

    /// Logs the already-planned workout as done, right from this screen --
    /// the same workout_log write RecommendationDetailView's "Mark Workout
    /// Complete" does, without making the user re-enter the generator.
    private func completePlannedWorkout() async {
        guard let plannedPlan else { return }
        isCompleting = true
        completeError = nil
        defer { isCompleting = false }
        // templateBodyPart covers gym-photo plans, whose titles are never in
        // the fixed suggestion list and would otherwise log as full_body.
        let bodyPart = plannedPlan.plan.substitutedBodyPart
            ?? plannedPlan.plan.templateBodyPart
            ?? recommendation?.category.workoutSuggestions.first(where: { $0.title == plannedPlan.selectedTitle })?.bodyPart.rawValue
            ?? BodyPartFocus.fullBody.rawValue
        do {
            try await SupabaseClient.shared.logWorkout(
                date: date,
                title: plannedPlan.selectedTitle,
                bodyPart: bodyPart,
                category: plannedPlan.category,
                planSnapshot: plannedPlan.plan
            )
            await load()
        } catch {
            completeError = "Couldn't log this workout. Try again."
        }
    }

    // MARK: - Data

    private var formattedDate: String {
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        parser.timeZone = .current
        guard let parsed = parser.date(from: date) else { return date }
        let display = DateFormatter()
        display.dateFormat = "EEEE d MMMM"
        return display.string(from: parsed)
    }

    private static var todayString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: Date())
    }

    private func load() async {
        async let recommendationFetch: DailyRecommendation? = try? SupabaseClient.shared.fetchTodaysRecommendation(date: date)
        async let logsFetch: [WorkoutLogEntry] = (try? await SupabaseClient.shared.fetchWorkoutLogs(date: date)) ?? []
        async let plannedFetch: TodaysAIPlan? = try? await SupabaseClient.shared.fetchTodaysAIPlan(date: date)
        async let snapshotsFetch: [DailySnapshotRow] = (try? await SupabaseClient.shared.fetchTodaysSnapshots(date: date)) ?? []

        recommendation = await recommendationFetch
        log = await logsFetch.first
        plannedPlan = await plannedFetch
        snapshots = await snapshotsFetch

        if let log {
            wearableSummary = await WearableSessionSummary.fetch(for: log)
        }
        isLoading = false
    }
}

#Preview {
    DayDetailView(date: "2026-07-22", recentRecommendations: [])
}
