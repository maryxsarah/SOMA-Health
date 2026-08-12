import SwiftUI
import UIKit

/// Guide 04's completed-workout screen -- the fuller detail behind
/// DayDetailView's "See full log" button. Built entirely from real,
/// attributable data (HealthKit/wearable summaries, the plan actually
/// snapshotted at log time); no estimated numbers presented as measured.
///
/// Per the handoff's own "open item": there's no coach/creator feature in
/// this app, so the session is attributed generically ("Your session"),
/// not to a named coach, and the screen uses the app's one existing accent
/// (never a per-person one).
///
/// This is the app's single biggest post-workout trust-and-reward moment,
/// and every source (AI plan, manual, device-detected) must land here with
/// real content -- an exercise breakdown, a calorie number, and a visible
/// "why today" explanation -- never a near-empty screen. See
/// WorkoutCalorieEstimator and WorkoutReasonResolver for the two honest
/// fallbacks that make that true for sources with no plan_snapshot.
struct CompletedWorkoutView: View {
    let isBestReadinessDay: Bool
    /// Called after a successful "Edit this log" save, or after the lazy
    /// calorie/reason backfill below, so the presenting screen
    /// (DayDetailView) can refresh its own copy.
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
    /// Resolved "why this workout today" text -- always non-empty once
    /// load() finishes. Held separately from log.reasonSnapshot so the
    /// card has something to show even before the backfill write (if any)
    /// completes.
    @State private var resolvedReason: String = ""
    /// Drives the calorie hero's count-up -- starts at 0 every time this
    /// screen appears and animates toward log.caloriesBurned.
    @State private var displayedCalories: Int = 0
    /// The first-open checkmark scale-bounce (see markFlourishIfFirstOpen).
    @State private var showFlourish = false

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

                caloriesHero

                metricTiles

                whyTodayCard

                if let plan = log.planSnapshot {
                    adherenceRow(plan: plan)
                }
                whatYouDidSection

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
        // Proportionate to a routine daily action -- a small badge next to
        // the header, not a full-screen celebration. See
        // markFlourishIfFirstOpen: plays once per log, ever.
        .overlay(alignment: .topTrailing) {
            if showFlourish {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(SomaTokens.success)
                    .scaleEffect(showFlourish ? 1 : 0.4)
                    .transition(.scale.combined(with: .opacity))
                    .padding(.top, 2)
            }
        }
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

    // MARK: - Calorie hero (requirement 2: hero stat, not buried)

    @ViewBuilder
    private var caloriesHero: some View {
        if log.caloriesBurned != nil {
            VStack(spacing: 2) {
                Text("\(displayedCalories)")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(SomaTokens.ink)
                    .contentTransition(.numericText())
                HStack(spacing: 6) {
                    Text(String(localized: "completedWorkout.calories.unit", defaultValue: "kcal burned", comment: "Completed workout: unit label under the calorie count"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SomaTokens.ink3)
                    // Never presented as measured when it isn't -- see
                    // WorkoutCalorieEstimator's own doc comment.
                    if log.caloriesEstimated {
                        Text(String(localized: "completedWorkout.calories.estimatedBadge", defaultValue: "ESTIMATED", comment: "Completed workout: badge shown when the calorie count is an estimate, not a measured reading"))
                            .font(.system(size: 9.5, weight: .bold))
                            .tracking(0.4)
                            .foregroundStyle(SomaTokens.ink4)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(SomaTokens.surface3))
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        } else {
            // Neither a real reading nor an estimate was possible (no
            // device data for this window AND no weight on file) -- an
            // honest "--", never a fabricated number.
            VStack(spacing: 2) {
                Text("—")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(SomaTokens.ink4)
                Text(String(localized: "completedWorkout.calories.unavailable", defaultValue: "Calories unavailable for this session", comment: "Completed workout: shown when no calorie reading or estimate could be produced"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SomaTokens.ink4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Metrics (unconditional -- every source gets these three)

    private var metricTiles: some View {
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

    /// Whole-minute duration for WorkoutCalorieEstimator -- same two
    /// sources as durationText above, just as an Int rather than a display
    /// string.
    private var durationMinutesForEstimate: Int? {
        if let startedAt = log.startedAt, let endedAt = log.endedAt,
           let start = Self.parseDate(startedAt), let end = Self.parseDate(endedAt) {
            let minutes = Int(end.timeIntervalSince(start) / 60)
            return minutes > 0 ? minutes : nil
        }
        return log.planSnapshot?.actualDurationMinutes
    }

    // MARK: - Why this workout today (requirement 3: visible, no tap)

    /// Deliberately NOT a SomaDisclosure -- this is the app's biggest
    /// post-workout trust moment, and hiding the reasoning behind a tap is
    /// exactly the pattern this requirement calls out as wrong here.
    private var whyTodayCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SomaTokens.accent)
                Text(String(localized: "completedWorkout.whyToday.eyebrow", defaultValue: "WHY THIS WORKOUT TODAY", comment: "Completed workout: eyebrow label over the why-this-workout explanation"))
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(SomaTokens.accent)
            }
            Text(resolvedReason.isEmpty ? " " : resolvedReason)
                .font(.system(size: 13.5))
                .foregroundStyle(SomaTokens.ink2)
                .redacted(reason: resolvedReason.isEmpty ? .placeholder : [])
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: SomaTokens.rXL, style: .continuous).fill(SomaTokens.surface3))
    }

    // MARK: - Adherence (ai_plan only -- this app has no per-block partial
    // completion for any other source)

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

    // MARK: - What you did (requirement 1: always some itemized breakdown)

    @ViewBuilder
    private var whatYouDidSection: some View {
        if let plan = log.planSnapshot {
            whatYouDid(plan: plan)
        } else {
            fallbackWhatYouDid
        }
    }

    private func whatYouDid(plan: AIWorkoutPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What you did")
                .font(.system(size: 15, weight: .bold))
            ForEach(Array(plan.blocks.enumerated()), id: \.offset) { index, block in
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
                .staggerReveal(index)
            }
            HStack(spacing: 6) {
                metaChip(BodyPartFocus(rawValue: log.bodyPart)?.displayName ?? log.bodyPart)
                metaChip(Self.categoryDisplayName(log.category))
            }
        }
    }

    /// Manual and device-detected logs have no plan_snapshot -- this app
    /// never asks a manually-logged sport session for a per-exercise
    /// breakdown (LogManualWorkoutView only captures title/body
    /// part/effort/duration/notes), and HealthKitManager exposes no
    /// route/segment data to build one for a device-detected session
    /// either. Rather than leaving "What you did" blank, this shows the
    /// one itemized row that IS real: the session actually logged, with
    /// whatever free-text notes the user (or the auto-log feedback string)
    /// left. Every source still gets a real breakdown, just a one-row one.
    private var fallbackWhatYouDid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What you did")
                .font(.system(size: 15, weight: .bold))
            HStack(alignment: .top) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(SomaTokens.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(log.title)
                        .font(.system(size: 14, weight: .semibold))
                    if let feedback = log.feedback, !feedback.isEmpty {
                        Text(feedback)
                            .font(.system(size: 12.5))
                            .foregroundStyle(SomaTokens.ink3)
                    }
                }
                Spacer()
                if let durationText {
                    Text(durationText)
                        .font(.system(size: 12.5))
                        .foregroundStyle(SomaTokens.ink3)
                }
            }
            .staggerReveal(0)
            HStack(spacing: 6) {
                metaChip(BodyPartFocus(rawValue: log.bodyPart)?.displayName ?? log.bodyPart)
                metaChip(Self.categoryDisplayName(log.category))
                metaChip(Self.sourceDisplayName(log.source))
            }
        }
    }

    private static func sourceDisplayName(_ source: String) -> String {
        switch source {
        case "manual": String(localized: "completedWorkout.source.manual", defaultValue: "Self-logged", comment: "Completed workout: meta chip source label for a manually-logged activity")
        case "device_detected": String(localized: "completedWorkout.source.deviceDetected", defaultValue: "Detected automatically", comment: "Completed workout: meta chip source label for an auto-detected activity")
        default: String(localized: "completedWorkout.source.aiPlan", defaultValue: "AI plan", comment: "Completed workout: meta chip source label for an AI-generated plan")
        }
    }

    /// Prefers the already-localized RecommendationCategory display name --
    /// log.category is the raw enum rawValue ("moderate", "push_hard"), and
    /// simply capitalizing it (the previous behavior) always showed English
    /// regardless of locale. Falls back to the capitalized raw value only
    /// for a category string that doesn't match a known case.
    private static func categoryDisplayName(_ category: String) -> String {
        RecommendationCategory(rawValue: category)?.displayTitle ?? category.capitalized
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
        // Subtle, once per presentation -- requirement 4.
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        async let summaryFetch = WearableSessionSummary.fetch(for: log)
        async let snapshotsFetch: [DailySnapshotRow] = (try? await SupabaseClient.shared.fetchTodaysSnapshots(date: log.date)) ?? []
        async let completedDatesFetch: Set<String> = (try? await SupabaseClient.shared.fetchRecentWorkoutLogDates(days: 30)) ?? []
        // Any date, not just today -- this screen is also opened for past
        // days via DayDetailView, and fetchTodaysRecommendation already
        // takes an arbitrary date despite its name.
        async let recommendationFetch: DailyRecommendation? = try? await SupabaseClient.shared.fetchTodaysRecommendation(date: log.date)

        let summary = await summaryFetch
        let snapshots = await snapshotsFetch
        let recommendation = await recommendationFetch
        wearableSummary = summary
        dayStrain = snapshots.first(where: { $0.strainScore != nil })?.strainScore
        completedDates = await completedDatesFetch
        isLoading = false

        await backfillComputedFieldsIfNeeded(snapshots: snapshots, recommendation: recommendation)
        markFlourishIfFirstOpen()
        await animateCaloriesIfNeeded()
    }

    /// Lazy backfill, same shape as NutritionView.autoRateUnratedEntries():
    /// resolve once, persist, and every later open of this log reads the
    /// frozen result instead of recomputing. Historical (pre-migration)
    /// rows fall back to a live resolve every time until this runs once.
    private func backfillComputedFieldsIfNeeded(snapshots: [DailySnapshotRow], recommendation: DailyRecommendation?) async {
        var caloriesBurned = log.caloriesBurned
        var caloriesEstimated = log.caloriesEstimated
        var reasonSnapshot = log.reasonSnapshot
        var needsWrite = false

        if caloriesBurned == nil {
            if let measured = await measuredCalories() {
                caloriesBurned = measured
                caloriesEstimated = false
                needsWrite = true
            } else if let duration = durationMinutesForEstimate,
                      let category = RecommendationCategory(rawValue: log.category) {
                let weight = await Self.fetchUserWeightKg()
                if let estimate = WorkoutCalorieEstimator.estimateCalories(category: category, durationMinutes: duration, weightKg: weight) {
                    caloriesBurned = estimate
                    caloriesEstimated = true
                    needsWrite = true
                }
            }
        }

        if reasonSnapshot?.isEmpty ?? true {
            reasonSnapshot = WorkoutReasonResolver.reason(for: log, recommendation: recommendation, snapshots: snapshots)
            needsWrite = true
        }

        log.caloriesBurned = caloriesBurned
        log.caloriesEstimated = caloriesEstimated
        log.reasonSnapshot = reasonSnapshot
        resolvedReason = reasonSnapshot ?? ""

        guard needsWrite else { return }
        do {
            try await SupabaseClient.shared.updateWorkoutLogComputedFields(
                id: log.id, caloriesBurned: caloriesBurned, caloriesEstimated: caloriesEstimated, reasonSnapshot: reasonSnapshot
            )
            onUpdate(log)
        } catch {
            // Best-effort -- the freshly-resolved values still render this
            // time either way; the next open just retries the write.
        }
    }

    /// Real calorie reading for this log's exact session window, same
    /// two-tier shape as WearableSessionSummary.fetch (on-device HealthKit
    /// first, connected-provider timeline fallback) -- kept independent of
    /// WearableSessionSummary itself since that struct's own nil-gating is
    /// heart-rate-specific and DayDetailView depends on that staying
    /// unchanged.
    private func measuredCalories() async -> Int? {
        guard let startedAtString = log.startedAt, let endedAtString = log.endedAt,
              let start = Self.parseDate(startedAtString), let end = Self.parseDate(endedAtString)
        else { return nil }

        if HealthKitManager.isAvailable,
           let kcal = await HealthKitManager.shared.fetchActiveEnergy(start: start, end: end) {
            return kcal
        }
        guard let entries = try? await SupabaseClient.shared.fetchProviderWorkoutTimeline(date: log.date, startTime: start, endTime: end) else {
            return nil
        }
        return entries.first(where: { $0.calories != nil })?.calories
    }

    private static func fetchUserWeightKg() async -> Double? {
        guard let userId = SupabaseClient.shared.currentUserID,
              let profile = try? await SupabaseClient.shared.fetchProfile(id: userId) else { return nil }
        return profile.weightKg
    }

    /// Plays once, ever, per log id (tracked in UserDefaults) -- "first
    /// time a given day's workout is marked complete" in practice means
    /// "first time this log's detail screen is opened", since nothing in
    /// this app navigates straight into CompletedWorkoutView at the actual
    /// moment a workout is logged (every log site just dismisses a sheet;
    /// the user always taps back in separately to see this screen).
    private func markFlourishIfFirstOpen() {
        var seen = Set(UserDefaults.standard.stringArray(forKey: Self.flourishSeenLogIdsKey) ?? [])
        guard !seen.contains(log.id) else { return }
        seen.insert(log.id)
        UserDefaults.standard.set(Array(seen), forKey: Self.flourishSeenLogIdsKey)

        withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) {
            showFlourish = true
        }
        Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                showFlourish = false
            }
        }
    }

    private static let flourishSeenLogIdsKey = "com.soma.app.completedWorkoutFlourishSeenLogIds"

    /// Spring-based count-up from 0 to the resolved calorie total --
    /// requirement 2. No-op (stays at 0, caloriesHero shows the "--" empty
    /// state) when there's genuinely nothing to show.
    private func animateCaloriesIfNeeded() async {
        guard let target = log.caloriesBurned, target > 0 else { return }
        displayedCalories = 0
        let steps = 18
        for step in 1...steps {
            try? await Task.sleep(nanoseconds: 22_000_000)
            let next = Int((Double(target) * Double(step) / Double(steps)).rounded())
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                displayedCalories = next
            }
        }
        displayedCalories = target
    }

    private static func withFeelRating(_ log: WorkoutLogEntry, rating: WorkoutFeelRating?) -> WorkoutLogEntry {
        WorkoutLogEntry(
            id: log.id, date: log.date, title: log.title, bodyPart: log.bodyPart, category: log.category,
            completedAt: log.completedAt, feedback: log.feedback, planSnapshot: log.planSnapshot,
            startedAt: log.startedAt, endedAt: log.endedAt, feelRating: rating, source: log.source,
            caloriesBurned: log.caloriesBurned, caloriesEstimated: log.caloriesEstimated, reasonSnapshot: log.reasonSnapshot
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

/// Staggered fade+slide-in for each exercise/breakdown row (requirement 4)
/// -- one small view-local animation, not a new shared component, since
/// nothing else in the app currently needs a per-row stagger.
private struct StaggerReveal: ViewModifier {
    let index: Int
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 8)
            .onAppear {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75).delay(Double(index) * 0.04)) {
                    appeared = true
                }
            }
    }
}

private extension View {
    func staggerReveal(_ index: Int) -> some View {
        modifier(StaggerReveal(index: index))
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
                planSnapshot: log.planSnapshot, startedAt: log.startedAt, endedAt: log.endedAt, feelRating: feelRating,
                source: log.source,
                caloriesBurned: log.caloriesBurned, caloriesEstimated: log.caloriesEstimated, reasonSnapshot: log.reasonSnapshot
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
