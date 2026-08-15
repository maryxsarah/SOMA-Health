import SwiftUI

/// The daily habit-loop card -- sits between the calendar strip and the
/// workout/readiness card on Home. Two modes (see DailyChecklistProgress):
/// a one-time onboarding checklist for a brand-new user, then permanently
/// the standard daily set once every onboarding item is checked.
///
/// Ownership split with HomeView: signals HomeView already has in memory
/// (today's mood, today's workout log, the connected providers, today's
/// recommendation) are passed in rather than re-fetched here, so this card
/// can never show a different answer than the rest of Home already does
/// for the same underlying state. Everything else this card alone needs
/// (meal log, steps, nutrition targets, checklist state, first-ever
/// workout/meal checks) it fetches itself.
struct DailyChecklistCardView: View {
    struct SharedSignals {
        var moodLoggedToday: Bool
        var workoutLoggedToday: Bool
        var healthKitConnected: Bool
        var hasReviewedFirstPlan: Bool
    }

    /// `.full` is every row (the checklist sheet). `.compact` is the Home
    /// dashboard widget -- per the Soma Glass 3e handoff, Home shows only
    /// the first couple of open items plus a link into the sheet for the
    /// rest, not the whole list inline.
    enum Style { case full, compact }

    let date: String
    let signals: SharedSignals
    var style: Style = .full
    /// Compact style only: opens the full checklist sheet.
    var onSeeAll: (() -> Void)? = nil
    /// Set (by HomeView) while a tapped row's destination is still
    /// loading required data -- see HomeView.openTodaysWorkoutDetail's
    /// own doc comment. Shows a spinner on the matching row instead of
    /// its usual chevron, rather than the row appearing to do nothing.
    var loadingDeepLink: ChecklistDeepLink? = nil
    let onDeepLink: (ChecklistDeepLink) -> Void
    /// Lets HomeView mirror checked/total into its own greeting-row progress
    /// pill without duplicating this view's own fetch -- fired once load()
    /// resolves, same numbers `header`'s "N/M today" pill shows.
    var onProgressChange: (Int, Int) -> Void = { _, _ in }

    @State private var progress: DailyChecklistProgress?
    @State private var isLoading = true
    @State private var justCompletedAllItems = false
    @State private var animatedFraction: Double = 0
    /// Guards against re-firing the completion flourish/day-complete write
    /// more than once per appearance of this card.
    @State private var hasWrittenDayComplete = false

    /// Compact style's preview rows -- the first two still-open items, so
    /// the widget always shows something actionable rather than whichever
    /// two happen to sort first.
    private func previewItems(_ progress: DailyChecklistProgress) -> [DailyChecklistItem] {
        Array(progress.items.filter { !$0.isChecked }.prefix(2))
    }

    var body: some View {
        CardView {
            header
            progressBar
            if isLoading {
                SomaLoadingBar(barWidth: 160)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            } else if let progress {
                switch style {
                case .full:
                    VStack(spacing: 10) {
                        ForEach(progress.items) { item in
                            row(for: item)
                        }
                    }
                    if progress.isComplete {
                        completionFlourish(streak: progress.streak)
                    }
                case .compact:
                    if progress.isComplete {
                        completionFlourish(streak: progress.streak)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(previewItems(progress)) { item in
                                row(for: item)
                            }
                        }
                        if let onSeeAll {
                            Button(action: onSeeAll) {
                                Text(String(localized: "dailyChecklist.seeAllTasks", defaultValue: "All \(progress.totalCount) tasks", comment: "Link on the compact Home checklist widget opening the full checklist sheet; placeholder is the total task count"))
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundStyle(SomaTokens.accent)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .task { await load() }
    }

    // MARK: - Header

    private var title: String {
        guard let progress else {
            return String(localized: "dailyChecklist.title.default", defaultValue: "Today's checklist", comment: "Daily checklist card header title shown in the standard (non-onboarding) daily mode")
        }
        return progress.streak > 0 && progress.totalCount == 8
            ? String(localized: "dailyChecklist.title.gettingStarted", defaultValue: "Getting started", comment: "Daily checklist card header title shown during the one-time onboarding checklist")
            : String(localized: "dailyChecklist.title.default", defaultValue: "Today's checklist", comment: "Daily checklist card header title shown in the standard (non-onboarding) daily mode")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.subheadline.bold())
            Spacer()
            if let progress {
                Text(String(localized: "dailyChecklist.header.progressCount", defaultValue: "\(progress.checkedCount)/\(progress.totalCount) today", comment: "Daily checklist header pill showing checked items out of total for today, e.g. '3/8 today'"))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(progress.isComplete ? SomaTokens.success : SomaTokens.ink3)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(progress.isComplete ? SomaTokens.successSoft : SomaTokens.surface3)
                    )
            }
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(SomaTokens.surface3)
                Capsule()
                    .fill(SomaTokens.accent)
                    .frame(width: max(0, geo.size.width * animatedFraction))
            }
        }
        .frame(height: 7)
        .clipShape(Capsule())
        .padding(.vertical, 4)
    }

    // MARK: - Rows

    private func row(for item: DailyChecklistItem) -> some View {
        Button {
            handleTap(item)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                checkbox(isChecked: item.isChecked)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(item.isChecked ? SomaTokens.ink3 : SomaTokens.ink)
                        .strikethrough(item.isChecked && item.daysUntilNextAvailable == nil && item.key != "progress_picture")
                    Text(item.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(SomaTokens.ink3)
                }
                Spacer()
                if item.deepLink != nil, item.deepLink == loadingDeepLink {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.top, 3)
                } else if item.deepLink != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(SomaTokens.ink4)
                        .padding(.top, 3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func checkbox(isChecked: Bool) -> some View {
        ZStack {
            Circle()
                .strokeBorder(isChecked ? SomaTokens.success : SomaTokens.hairline, lineWidth: 1.5)
                .background(Circle().fill(isChecked ? SomaTokens.successSoft : Color.clear))
                .frame(width: 22, height: 22)
            if isChecked {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(SomaTokens.success)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.top, 1)
    }

    // MARK: - Completion flourish

    private func completionFlourish(streak: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "flame.fill")
                .foregroundStyle(SomaTokens.warn)
            Text(streak > 1
                ? String(localized: "dailyChecklist.completion.streak", defaultValue: "Perfect day -- \(streak) days in a row.", comment: "Daily checklist completion flourish shown when the user has a multi-day streak; placeholder is the streak count")
                : String(localized: "dailyChecklist.completion.firstDay", defaultValue: "Perfect day. That's how streaks start.", comment: "Daily checklist completion flourish shown on the first day of a new streak"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SomaTokens.ink2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: SomaTokens.rXL, style: .continuous).fill(SomaTokens.successSoft))
        .scaleEffect(justCompletedAllItems ? 1.0 : 0.96)
        .opacity(justCompletedAllItems ? 1.0 : 0.85)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) { justCompletedAllItems = true }
        }
    }

    // MARK: - Actions

    private func handleTap(_ item: DailyChecklistItem) {
        if item.isManual {
            Task { await toggleManual(item) }
        } else if let deepLink = item.deepLink {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onDeepLink(deepLink)
        }
    }

    private func toggleManual(_ item: DailyChecklistItem) async {
        // Progress-picture's "settled, not due yet" state has no deep link
        // and isn't a real open task -- tapping it does nothing (matches
        // isManual + deepLink == nil meaning "informational only" here).
        guard item.deepLink != nil || item.isChecked else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let scope = item.key.hasPrefix("onboarding_") ? "onboarding" : "daily"
        do {
            if item.isChecked, scope == "daily" {
                try await SupabaseClient.shared.deleteDailyChecklistState(itemKey: item.key, date: date)
            } else {
                try await SupabaseClient.shared.upsertDailyChecklistState(scope: scope, itemKey: item.key, date: date)
                if item.deepLink == .progressPicture || item.deepLink == .profileKitchenEquipment || item.deepLink == .healthDashboard || item.deepLink == .chooseWidgets {
                    onDeepLink(item.deepLink!)
                }
            }
        } catch {
            // Best-effort, same posture as CompletedWorkoutView's backfill
            // write -- the next load() retries.
        }
        await load()
    }

    private func load() async {
        isLoading = true
        async let mealLoggedToday = (try? await SupabaseClient.shared.hasMealLoggedToday(date: date)) ?? false
        async let nutritionTarget = try? SupabaseClient.shared.fetchNutritionTargets()
        async let todaysSteps = HealthKitManager.shared.fetchTodaysSteps()
        async let dailyState = (try? await SupabaseClient.shared.fetchDailyChecklistState(scope: "daily", sinceDate: Self.dateString(daysAgo: 30))) ?? []
        async let onboardingState = (try? await SupabaseClient.shared.fetchDailyChecklistState(scope: "onboarding")) ?? []
        async let everLoggedWorkout = (try? await SupabaseClient.shared.hasEverLoggedWorkout()) ?? false
        async let everLoggedMeal = (try? await SupabaseClient.shared.hasEverLoggedMeal()) ?? false
        async let profile: UserProfile? = {
            guard let userId = SupabaseClient.shared.currentUserID else { return nil }
            return try? await SupabaseClient.shared.fetchProfile(id: userId)
        }()

        let mealToday = await mealLoggedToday
        let target = await nutritionTarget
        let steps = await todaysSteps
        let dailyRows = await dailyState
        let onboardingRows = await onboardingState
        let workoutEver = await everLoggedWorkout
        let mealEver = await everLoggedMeal
        let fetchedProfile = await profile

        let onboardingInputs = DailyChecklistProgress.OnboardingInputs(
            hasGoalsAndWeight: !(fetchedProfile?.goals.isEmpty ?? true) && fetchedProfile?.weightKg != nil,
            kitchenEquipmentAcknowledged: !(fetchedProfile?.householdEquipment.isEmpty ?? true)
                || onboardingRows.contains { $0.itemKey == "onboarding_kitchen_equipment" },
            healthKitConnected: signals.healthKitConnected,
            notificationsEnabled: await NotificationManager.shared.isAuthorized(),
            hasReviewedFirstPlan: signals.hasReviewedFirstPlan
                || onboardingRows.contains { $0.itemKey == "onboarding_review_plan" },
            hasLoggedFirstWorkout: workoutEver,
            hasLoggedFirstMeal: mealEver,
            hasSeenHowSomaWorks: onboardingRows.contains { $0.itemKey == "onboarding_how_soma_works" },
            hasChosenWidgets: onboardingRows.contains { $0.itemKey == "onboarding_choose_widgets" }
        )

        let dayCompleteDates = dailyRows.filter { $0.itemKey == "__day_complete__" }.map(\.date)
        let streak = DailyChecklistProgress.computeStreak(completedDates: dayCompleteDates, today: Self.today())

        let resolved: DailyChecklistProgress
        if !DailyChecklistProgress.isOnboardingComplete(onboardingInputs) {
            resolved = DailyChecklistProgress.computeOnboarding(onboardingInputs)
        } else {
            let lastProgressPicture = dailyRows.filter { $0.itemKey == "progress_picture" }.map(\.date).max()
            let standardInputs = DailyChecklistProgress.StandardInputs(
                mealLoggedToday: mealToday,
                targetProteinG: target?.dailyProteinG, targetCarbsG: target?.dailyCarbsG,
                todaysSteps: steps.map(Int.init), stepGoal: Self.defaultStepGoal,
                moodLoggedToday: signals.moodLoggedToday, workoutLoggedToday: signals.workoutLoggedToday,
                lastProgressPictureDate: lastProgressPicture, today: Self.today()
            )
            resolved = DailyChecklistProgress.computeStandard(standardInputs, streak: streak)
            await NotificationManager.shared.scheduleChecklistNudges(
                mealLoggedToday: mealToday,
                stepsOnTrack: (steps ?? 0) >= Double(Self.defaultStepGoal),
                workoutLoggedToday: signals.workoutLoggedToday,
                openItemTitles: resolved.items.filter { !$0.isChecked }.map(\.title)
            )
        }

        progress = resolved
        isLoading = false
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            animatedFraction = resolved.fraction
        }
        onProgressChange(resolved.checkedCount, resolved.totalCount)

        if resolved.isComplete, !hasWrittenDayComplete {
            hasWrittenDayComplete = true
            try? await SupabaseClient.shared.upsertDailyChecklistState(scope: "daily", itemKey: "__day_complete__", date: date)
        }
    }

    /// No per-user step goal exists yet -- 8,000/day is a standard,
    /// commonly-cited general target, shown honestly as a fixed default
    /// rather than presented as personalized.
    private static let defaultStepGoal = 8000

    private static func today() -> Date { Date() }

    private static func dateString(daysAgo: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: date)
    }
}
