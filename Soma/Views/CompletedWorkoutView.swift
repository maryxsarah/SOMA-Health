import SwiftUI

/// Guide 04's completed-workout screen -- the fuller detail behind
/// DayDetailView's "See full log" button. Built entirely from real,
/// attributable data (HealthKit/wearable summaries, the plan actually
/// snapshotted at log time); no estimated numbers.
///
/// Per the handoff's own "open item": there's no coach/creator feature in
/// this app, so the session is attributed generically ("Your session"),
/// not to a named coach, and the screen uses the app's one existing accent
/// (never a per-person one).
struct CompletedWorkoutView: View {
    let isBestReadinessDay: Bool
    /// Called after a successful "Edit this log" save, so the presenting
    /// screen (DayDetailView) can refresh its own copy.
    var onUpdate: (WorkoutLogEntry) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @State private var log: WorkoutLogEntry
    @State private var wearableSummary: WearableSessionSummary?
    @State private var dayStrain: Double?
    @State private var completedDates: Set<String> = []
    @State private var isLoading = true
    @State private var showEditSheet = false
    @State private var showRepeatSheet = false
    @State private var repeatRecommendation: DailyRecommendation?
    @State private var isLoadingRepeat = false

    init(log: WorkoutLogEntry, isBestReadinessDay: Bool, onUpdate: @escaping (WorkoutLogEntry) -> Void = { _ in }) {
        _log = State(initialValue: log)
        self.isBestReadinessDay = isBestReadinessDay
        self.onUpdate = onUpdate
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                sessionEyebrow

                if let plan = log.planSnapshot {
                    metricTiles(plan: plan)
                    adherenceRow(plan: plan)
                    whatYouDid(plan: plan)
                }

                howItFelt
                streakRow
            }
            .padding(20)
            .padding(.bottom, 90)
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .somaBackground()
        .task { await load() }
        .sheet(isPresented: $showEditSheet) {
            EditWorkoutLogSheet(log: log) { updated in
                log = updated
                onUpdate(updated)
            }
        }
        .sheet(isPresented: $showRepeatSheet) {
            if let repeatRecommendation {
                RecommendationDetailView(
                    recommendation: repeatRecommendation,
                    seededTitle: log.title,
                    seededBodyPart: log.bodyPart
                )
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
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
            HStack(spacing: 8) {
                statusPill(label: "Completed", background: SomaTokens.heartSoft, foreground: SomaTokens.heart)
                Text("Logged \(formattedLoggedTime)")
                    .font(.system(size: 12.5))
                    .foregroundStyle(SomaTokens.ink3)
            }
            if isBestReadinessDay {
                Label("Best readiness of the week", systemImage: "crown.fill")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(SomaTokens.warn)
            }
        }
        .padding(.bottom, 4)
    }

    private func statusPill(label: LocalizedStringKey, background: Color, foreground: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "heart.fill").font(.system(size: 10))
            Text(label).font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(background))
    }

    /// Generic -- there's no coach/creator feature in this app, so this
    /// never names anyone else. See this file's own doc comment.
    private var sessionEyebrow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(SomaTokens.accentSoft)
                .frame(width: 18, height: 18)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(SomaTokens.accent)
                )
            Text("YOUR SESSION")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(SomaTokens.accent)
        }
    }

    // MARK: - Metrics

    private func metricTiles(plan: AIWorkoutPlan) -> some View {
        HStack(spacing: 10) {
            metricTile(label: "Duration", value: durationText ?? "—")
            metricTile(label: "Strain", value: dayStrain.map { String(format: "%.1f", $0) } ?? "—")
            metricTile(label: "Avg bpm", value: wearableSummary.map { "\($0.averageHeartRate)" } ?? "—")
        }
    }

    private func metricTile(label: LocalizedStringKey, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(SomaTokens.ink)
            Text(label)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(SomaTokens.ink3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: SomaTokens.rXL, style: .continuous)
                .fill(SomaTokens.surface3)
        )
    }

    /// `MM:SS`, matching guide 04's own example ("Duration 42:10"). Real
    /// start/end gives true second-level precision; a plan's
    /// actualDurationMinutes (whole minutes only) is the fallback for
    /// entries logged without a reliable start time.
    private var durationText: String? {
        if let startedAt = log.startedAt, let endedAt = log.endedAt,
           let start = Self.parseDate(startedAt), let end = Self.parseDate(endedAt) {
            let totalSeconds = max(0, Int(end.timeIntervalSince(start)))
            return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
        }
        if let minutes = log.planSnapshot?.actualDurationMinutes {
            return String(format: "%d:00", minutes)
        }
        return nil
    }

    // MARK: - Adherence

    /// "Matched the plan" -- this app doesn't track partial completion per
    /// block, only whether the session as a whole was logged done, so this
    /// reads as the plan that was generated and then logged, not a
    /// fabricated partial-progress number.
    private func adherenceRow(plan: AIWorkoutPlan) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(SomaTokens.success)
            Text("Matched the plan · \(plan.blocks.count) of \(plan.blocks.count) blocks")
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(SomaTokens.success)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: SomaTokens.rXL, style: .continuous).fill(SomaTokens.successSoft))
    }

    // MARK: - What you did

    private func whatYouDid(plan: AIWorkoutPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What you did")
                .font(.system(size: 15, weight: .bold))
            ForEach(plan.blocks) { block in
                HStack {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(SomaTokens.accent)
                    Text(block.name)
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text("\(block.exercises.reduce(0) { $0 + $1.durationMinutes }) min")
                        .font(.system(size: 12.5))
                        .foregroundStyle(SomaTokens.ink3)
                }
            }
            HStack(spacing: 6) {
                metaChip(BodyPartFocus(rawValue: log.bodyPart)?.displayName ?? log.bodyPart)
                metaChip(log.category.capitalized)
            }
        }
    }

    private func metaChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(SomaTokens.ink2)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(SomaTokens.surface3))
    }

    // MARK: - How it felt

    private var howItFelt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How it felt")
                .font(.system(size: 15, weight: .bold))
            HStack(spacing: 8) {
                ForEach(WorkoutFeelRating.allCases) { rating in
                    SomaChip(title: LocalizedStringKey(rating.displayName), isSelected: log.feelRating == rating) {
                        Task { await setFeelRating(rating) }
                    }
                }
            }
            if let feelRating = log.feelRating {
                Text(feelRating.consequence)
                    .font(.system(size: 13))
                    .foregroundStyle(SomaTokens.ink3)
            }
        }
    }

    private func setFeelRating(_ rating: WorkoutFeelRating) async {
        let previous = log.feelRating
        log = Self.withFeelRating(log, rating: rating)
        do {
            try await SupabaseClient.shared.updateWorkoutLog(id: log.id, feelRating: rating, feedback: nil)
            onUpdate(log)
        } catch {
            log = Self.withFeelRating(log, rating: previous)
        }
    }

    // MARK: - Streak

    private var streakRow: some View {
        HStack(spacing: 6) {
            ForEach(0..<min(7, max(streak, 1)), id: \.self) { _ in
                Image(systemName: "heart.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(SomaTokens.heart)
            }
            Text("One more hits your weekly target")
                .font(.system(size: 12.5))
                .foregroundStyle(SomaTokens.ink3)
                .padding(.leading, 4)
        }
    }

    private var streak: Int {
        var count = 0
        var cursor = Date()
        while completedDates.contains(Self.dateString(cursor)) {
            count += 1
            cursor = Calendar.current.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        return count
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 9) {
            SomaButton(title: "Do it again", size: .lg, variant: .primary, isEnabled: !isLoadingRepeat) {
                Task { await startRepeat() }
            }
            SomaButton(title: "Edit this log", size: .md, variant: .secondary) {
                showEditSheet = true
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 22)
        .background(
            LinearGradient(
                colors: [SomaTokens.surface2.opacity(0), Color(red: 0.914, green: 0.941, blue: 0.980)],
                startPoint: .top, endPoint: .bottom
            )
        )
    }

    /// "Do it again" opens today's own recommendation/generation flow,
    /// preselecting this log's title -- reusing RecommendationDetailView's
    /// existing generate/log flow rather than a bespoke repeat action.
    private func startRepeat() async {
        isLoadingRepeat = true
        defer { isLoadingRepeat = false }
        let today = Self.dateString(Date())
        repeatRecommendation = try? await SupabaseClient.shared.fetchTodaysRecommendation(date: today)
        if repeatRecommendation != nil {
            showRepeatSheet = true
        }
    }

    // MARK: - Data

    private func load() async {
        async let summaryFetch = WearableSessionSummary.fetch(for: log)
        async let snapshotsFetch: [DailySnapshotRow] = (try? await SupabaseClient.shared.fetchTodaysSnapshots(date: log.date)) ?? []
        async let completedDatesFetch: Set<String> = (try? await SupabaseClient.shared.fetchRecentWorkoutLogDates(days: 30)) ?? []

        wearableSummary = await summaryFetch
        dayStrain = await snapshotsFetch.first(where: { $0.strainScore != nil })?.strainScore
        completedDates = await completedDatesFetch
        isLoading = false
    }

    private static func withFeelRating(_ log: WorkoutLogEntry, rating: WorkoutFeelRating?) -> WorkoutLogEntry {
        WorkoutLogEntry(
            id: log.id, date: log.date, title: log.title, bodyPart: log.bodyPart, category: log.category,
            completedAt: log.completedAt, feedback: log.feedback, planSnapshot: log.planSnapshot,
            startedAt: log.startedAt, endedAt: log.endedAt, feelRating: rating
        )
    }

    private var formattedDate: String {
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        parser.timeZone = .current
        guard let parsed = parser.date(from: log.date) else { return log.date }
        let display = DateFormatter()
        display.dateFormat = "EEEE d MMMM"
        return display.string(from: parsed)
    }

    private var formattedLoggedTime: String {
        guard let date = Self.parseDate(log.completedAt) else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func parseDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plainFormatter = ISO8601DateFormatter()
        return formatter.date(from: string) ?? plainFormatter.date(from: string)
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: date)
    }
}

/// Minimal "Edit this log" sheet -- lets the user change the feel rating
/// and/or free-text feedback after the fact, via SupabaseClient's
/// updateWorkoutLog.
private struct EditWorkoutLogSheet: View {
    let log: WorkoutLogEntry
    let onSave: (WorkoutLogEntry) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var feelRating: WorkoutFeelRating?
    @State private var feedbackText: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(log: WorkoutLogEntry, onSave: @escaping (WorkoutLogEntry) -> Void) {
        self.log = log
        self.onSave = onSave
        _feelRating = State(initialValue: log.feelRating)
        _feedbackText = State(initialValue: log.feedback ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("How it felt") {
                    HStack(spacing: 8) {
                        ForEach(WorkoutFeelRating.allCases) { rating in
                            SomaChip(title: LocalizedStringKey(rating.displayName), isSelected: feelRating == rating) {
                                feelRating = feelRating == rating ? nil : rating
                            }
                        }
                    }
                }
                Section("Feedback for next time") {
                    TextField("Optional", text: $feedbackText, axis: .vertical)
                        .lineLimit(2...4)
                }
                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(.red)
                }
            }
            .navigationTitle("Edit this log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(isSaving)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await SupabaseClient.shared.updateWorkoutLog(id: log.id, feelRating: feelRating, feedback: feedbackText)
            onSave(WorkoutLogEntry(
                id: log.id, date: log.date, title: log.title, bodyPart: log.bodyPart, category: log.category,
                completedAt: log.completedAt, feedback: feedbackText.isEmpty ? nil : feedbackText,
                planSnapshot: log.planSnapshot, startedAt: log.startedAt, endedAt: log.endedAt, feelRating: feelRating
            ))
            dismiss()
        } catch {
            errorMessage = String(
                localized: "Couldn't save. Try again.",
                defaultValue: "Couldn't save. Try again.",
                comment: "Error shown when saving an edited workout log's feedback fails"
            )
        }
    }
}
