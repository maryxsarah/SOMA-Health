import SuperwallKit
import SwiftUI

/// Screen 4 -- Home. No text input, no chat history, no voice button.
struct HomeView: View {
    @EnvironmentObject private var appState: AppState

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showDetail = false
    @State private var showProfile = false
    @State private var showHealthDashboard = false
    @State private var recentRecommendations: [DailyRecommendation] = []
    @State private var selectedDay: String?
    @State private var todaysWorkoutLog: WorkoutLogEntry?
    @State private var completedDates: Set<String> = []
    // Manual activity logging (real feedback: users want to log a sport
    // session -- soccer, volleyball, hot yoga -- outside the AI plan).
    // showManualWorkoutDetail routes "see today's workout" to
    // CompletedWorkoutView instead of RecommendationDetailView whenever
    // todaysWorkoutLog.source == "manual", since that view has no
    // suggestion titles to match a manually-logged activity against.
    @State private var showLogManualWorkout = false
    @State private var showManualWorkoutDetail = false
    @State private var timelineEntries: [WorkoutTimelineEntry] = []

    @State private var showGymPhotoFlow = false
    // Goal-progress card -- previously the only way to find the goal/
    // current body photo feature was one buried row deep in Profile's
    // Training tab. Loaded independently of `profile` in ProfileView since
    // Home never otherwise touches the users row's photo/DOB fields.
    @State private var hasGoalBodyPhoto = false
    @State private var hasCurrentBodyPhoto = false
    @State private var isConfirmedAdultForBodyPhotos = false
    @State private var showGoalBodyProgress = false
    // Nutrition row -- nil target means never computed yet (no goal/
    // current photo pair analyzed), handled the same "hidden CTA instead
    // of a broken row" way the goal-progress row handles no photos yet.
    @State private var nutritionTarget: NutritionTargets?
    @State private var nutritionProgress: NutritionDayProgress?
    @State private var showNutrition = false
    @State private var showSeededDetail = false
    @State private var pendingGymPlan: (AIWorkoutPlan, String, String)?

    /// Today's confirmed ("Add to today's plan") AI plan, if any -- distinct
    /// from todaysWorkoutLog (completed). Persists across relaunch, unlike
    /// pendingGymPlan which only exists for the current view session.
    @State private var todaysAIPlan: TodaysAIPlan?
    /// Real consecutive-day streak of gym-photo scans (ai_generation_log,
    /// source = gym_photo), not workout completion -- see
    /// fetchGymPhotoScanDates's own doc comment.
    @State private var scanStreak = 0
    /// Raw scan dates -- feeds the scan streak.
    @State private var scanDates: Set<String> = []
    /// All AI generations logged today (any source) -- compared against the
    /// tier's daily limit to drive the scan row's `locked` state.
    @State private var todaysGenerationCount = 0
    /// Profile's weekly session target -- the week card's progress bar and
    /// streak pill must agree with Profile (guide 03, SELF-CHECK).
    @State private var weeklyTarget: Int?
    /// Today's snapshot rows -- feeds the readiness disclosure's inputs line.
    @State private var todaysSnapshots: [DailySnapshotRow] = []
    /// Active sport goal + its catalog -- the readiness card's goal line
    /// renders only when a real active goal exists (kill-switch rule).
    @State private var activeSportGoal: UserGoal?
    @State private var sportGoalCatalog: SportCatalog?
    @State private var showSportGoalScreen = false
    /// Launch-period promo entry: dismiss is forever (guide 05's rule),
    /// so it persists across sessions rather than living in view state.
    @AppStorage("sportGoalPromoDismissed") private var sportGoalPromoDismissed = false
    /// The onboarding gallery shows on the FIRST card tap only (guide 08);
    /// after that the card goes straight to the sport list.
    @AppStorage("sportGoalOnboardingSeen") private var sportGoalOnboardingSeen = false
    @State private var showSportGoalOnboarding = false
    /// Set when onboarding's "Pick a goal" fires -- the goal flow sheet
    /// opens from the cover's onDismiss, never over a live cover.
    @State private var openGoalFlowAfterOnboarding = false
    /// "Not feeling it today?" confirmation dialog, and the in-flight state
    /// for setting/clearing that request. See restDayRequestControl.
    @State private var showRestDayOptions = false
    @State private var isSettingRestDayRequest = false

    var body: some View {
        ScrollView {
            // Guide 03 order: nav pill → greeting → week card → readiness
            // card → scan row. The orb is gone (22% of the screen carrying
            // no information); raw metric tiles live in the dashboard.
            // 16 (was 12): the orb-era screen breathed more; with it gone
            // the cards read cramped at 12 on a standard-height device.
            VStack(spacing: 16) {
                topRow

                greetingBlock

                weekCard

                if showSportGoalPromo {
                    sportGoalPromoCard
                }

                Group {
                    if let recommendation = appState.currentRecommendation {
                        readinessCard(recommendation)
                    } else {
                        needsDataCard
                    }
                }

                if let todaysWorkoutLog {
                    todaysWorkoutCard(todaysWorkoutLog)
                } else if let todaysAIPlan, todaysAIPlan.addedToPlan {
                    aiGeneratedWorkoutCard(todaysAIPlan)
                }

                scanRow

                goalProgressRow

                nutritionRow

                if !timelineEntries.isEmpty {
                    timelineCard
                }
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 40)
        }
        .somaBackground()
        .task {
            await loadTodaysRecommendation()
            await appState.refreshReferralBonus()
            await loadRecentRecommendations()
            await loadTodaysWorkoutLog()
            await loadCompletedDates()
            await loadTimeline()
            await loadTodaysAIPlan()
            await loadWeeklyProgressAndStreak()
            await loadGoalBodyPhotoState()
            await loadNutritionState()
        }
        .refreshable {
            await checkNow()
            await loadRecentRecommendations()
            await loadTodaysWorkoutLog()
            await loadCompletedDates()
            await loadTimeline()
            await loadTodaysAIPlan()
            await loadWeeklyProgressAndStreak()
            await loadNutritionState()
        }
        .sheet(isPresented: $showDetail, onDismiss: {
            Task {
                await loadTodaysWorkoutLog()
                await loadCompletedDates()
                await loadTimeline()
                await loadTodaysAIPlan()
            }
        }) {
            if let recommendation = appState.currentRecommendation {
                RecommendationDetailView(recommendation: recommendation)
            }
        }
        .sheet(isPresented: $showProfile, onDismiss: {
            // The beta toggle lives in Profile -- refetch so the promo
            // card appears (or disappears) the moment the sheet closes.
            Task { await loadSportGoal() }
        }) {
            ProfileView()
        }
        .sheet(isPresented: $showGoalBodyProgress, onDismiss: {
            Task { await loadGoalBodyPhotoState() }
        }) {
            GoalBodyProgressView()
        }
        .sheet(isPresented: $showNutrition, onDismiss: {
            Task { await loadNutritionState() }
        }) {
            NutritionView()
        }
        .sheet(isPresented: $showLogManualWorkout, onDismiss: {
            Task {
                await loadTodaysWorkoutLog()
                await loadCompletedDates()
                await loadWeeklyProgressAndStreak()
            }
        }) {
            LogManualWorkoutView()
        }
        .sheet(isPresented: $showManualWorkoutDetail) {
            if let todaysWorkoutLog {
                CompletedWorkoutView(log: todaysWorkoutLog, isBestReadinessDay: isBestReadinessDay) { updated in
                    self.todaysWorkoutLog = updated
                }
            }
        }
        .sheet(isPresented: $showHealthDashboard) {
            HealthDashboardView()
        }
        .sheet(isPresented: $showSportGoalScreen, onDismiss: {
            Task { await loadSportGoal() }
        }) {
            SportGoalFlowView()
        }
        .fullScreenCover(isPresented: $showSportGoalOnboarding, onDismiss: {
            if openGoalFlowAfterOnboarding {
                openGoalFlowAfterOnboarding = false
                showSportGoalScreen = true
            }
        }) {
            SportGoalOnboardingView(
                onPickGoal: {
                    openGoalFlowAfterOnboarding = true
                    showSportGoalOnboarding = false
                },
                onClose: { showSportGoalOnboarding = false }
            )
            .presentationBackground(.clear)
        }
        .sheet(isPresented: $showGymPhotoFlow, onDismiss: {
            Task {
                await loadTodaysAIPlan()
                // A scan just happened -- refresh the quota count and streak
                // so the scan row's locked state reflects it immediately.
                await loadWeeklyProgressAndStreak()
            }
            guard pendingGymPlan != nil else { return }
            Task {
                // The seeded sheet needs today's recommendation, which can
                // be missing in memory (a failed fetch earlier, or a
                // midnight rollover clearing it) even though the gym
                // generation just succeeded server-side against the DB row.
                // Presenting anyway rendered an empty sheet whose dismiss
                // discarded the plan -- so re-fetch first, and only
                // present once there is something to seed into.
                if appState.currentRecommendation == nil {
                    await loadTodaysRecommendation()
                }
                if appState.currentRecommendation != nil {
                    showSeededDetail = true
                }
                // Still no recommendation: keep pendingGymPlan rather than
                // dropping it. The plan is also persisted server-side in
                // ai_workout_plan, so the detail view surfaces it once a
                // recommendation loads.
            }
        }) {
            GymPhotoWorkoutView(date: Self.todayDateString()) { plan, title, bodyPart in
                pendingGymPlan = (plan, title, bodyPart)
            }
        }
        .sheet(isPresented: $showSeededDetail, onDismiss: {
            pendingGymPlan = nil
            Task {
                await loadTodaysWorkoutLog()
                await loadCompletedDates()
                await loadTimeline()
                await loadTodaysAIPlan()
            }
        }) {
            if let recommendation = appState.currentRecommendation, let pendingGymPlan {
                RecommendationDetailView(
                    recommendation: recommendation,
                    seededPlan: pendingGymPlan.0,
                    seededTitle: pendingGymPlan.1,
                    seededBodyPart: pendingGymPlan.2
                )
            }
        }
        .sheet(isPresented: Binding(
            get: { selectedDay != nil },
            set: { if !$0 { selectedDay = nil } }
        )) {
            if let selectedDay {
                DayDetailView(date: selectedDay, recentRecommendations: recentRecommendations)
            }
        }
    }

    /// The Home card (today's category + message) always stays free --
    /// only the tap-through detail (step target, workout suggestions, why
    /// explanation) requires an active subscription or referral bonus.
    /// The bonus check stays in Swift (Superwall's dashboard has no
    /// visibility into it); everything else -- is this user paying, and
    /// does today's audience even show a paywall -- is entirely Superwall's
    /// call via the "detail_access" placement's campaign configuration.
    private func requestDetailAccess(then action: @escaping () -> Void) {
        if let until = appState.referralBonusUntil, until > Date() {
            action()
            return
        }
        Superwall.shared.register(placement: "detail_access", feature: action)
    }

    /// Today's logged workout might be an AI-plan completion (has
    /// suggestion titles to match against RecommendationDetailView's
    /// "already logged" state) or a manually-logged activity (no such
    /// titles -- CompletedWorkoutView is the generic detail screen that
    /// already degrades gracefully with no plan_snapshot, see
    /// DayDetailView's own use of it). Same paywall gate either way.
    private func openTodaysWorkoutDetail() {
        if todaysWorkoutLog?.source == "manual" {
            requestDetailAccess { showManualWorkoutDetail = true }
        } else {
            requestDetailAccess { showDetail = true }
        }
    }

    private var isBestReadinessDay: Bool {
        CalendarStripView.bestReadinessDate(among: recentRecommendations) == Self.todayDateString()
    }

    /// guide 02: pill top-left (opposite the gear), badge top-right --
    /// nothing else in that row. Previously the Dashboard was reachable
    /// only from deep inside Profile, easy to miss entirely.
    private var topRow: some View {
        HStack {
            Button {
                AnalyticsManager.shared.featureUsed(name: "health_dashboard")
                showHealthDashboard = true
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Dashboard")
                        .font(.system(size: 13.5, weight: .semibold))
                    // The badge counts filled hearts in the strip below,
                    // computed from the exact same 7-day window/dataset --
                    // if they ever disagreed, guide 02 says the strip wins,
                    // so this reuses `completedDates` rather than a
                    // separately-fetched calendar-week count.
                    if doneThisWeekCount > 0 {
                        Text("\(doneThisWeekCount) done")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(SomaTokens.heart)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(SomaTokens.heartSoft))
                    }
                }
                .foregroundStyle(SomaTokens.accentDeep)
                .padding(.leading, 10)
                .padding(.trailing, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(SomaTokens.surface)
                        .overlay(Capsule().stroke(SomaTokens.hairline, lineWidth: 1))
                        .somaCardShadow()
                )
            }
            .buttonStyle(SomaNavPillButtonStyle())

            Spacer()

            Button {
                showProfile = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.title3)
                    .foregroundStyle(Theme.pillFill)
            }
        }
        .padding(.top, 2)
    }

    private var doneThisWeekCount: Int {
        Set(CalendarStripView.lastDayStrings()).intersection(completedDates).count
    }

    // MARK: - Greeting (guide 03: "where am I")

    private var greetingBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Self.longDateString())
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SomaTokens.ink3)
            Text(Self.timeOfDayGreeting())
                .font(Theme.display)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Week card (guide 03: strip + weekly progress + streak pill)

    private var weekCard: some View {
        CardView {
            CalendarStripView(
                recommendations: recentRecommendations,
                completedDates: completedDates,
                selectedDate: selectedDay,
                onSelectDay: { selectedDay = $0 }
            )

            Divider().overlay(SomaTokens.hairline)

            weeklyProgress
        }
    }

    /// "4 of 5 sessions this week" + a target-count segment bar + "1 to go"
    /// pill. Filled segments must equal filled hearts, and both must equal
    /// Profile's weekly target -- so both derive from the same
    /// completedDates set the strip renders (SELF-CHECK, guide 03).
    private var weeklyProgress: some View {
        let target = max(weeklyTarget ?? 5, 1)
        let done = min(doneThisWeekCount, target)
        let toGo = target - done
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(doneThisWeekCount) of \(target) sessions this week")
                    .font(.system(size: 13.5, weight: .semibold))
                Spacer()
                if toGo > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "heart")
                            .font(.system(size: 11, weight: .semibold))
                        Text("\(toGo) to go")
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .foregroundStyle(SomaTokens.heart)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(SomaTokens.heartSoft))
                }
            }
            HStack(spacing: 5) {
                ForEach(0..<target, id: \.self) { index in
                    Capsule()
                        .fill(index < done ? SomaTokens.heart : SomaTokens.surface4)
                        .frame(height: 6)
                }
            }
        }
    }

    // MARK: - Readiness card (guide 03: category + one line + disclosure + CTA)

    private func readinessCard(_ recommendation: DailyRecommendation) -> some View {
        CardView {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(recommendation.category.displayTitle)
                        .font(.system(size: 32, design: .serif).italic())
                    // The only screen a day-1 user is guaranteed to see --
                    // without this, a zero-signal "moderate" reads exactly
                    // like a real one until they tap through to Detail.
                    if recommendation.reason == .insufficientData {
                        Text("Building your baseline")
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                    }
                    Text(recommendation.message)
                        .font(.system(size: 14))
                        .foregroundStyle(SomaTokens.ink2)
                        .lineLimit(2)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    Text("TODAY")
                        .font(.system(size: 10.5, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(SomaTokens.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(SomaTokens.accentSoft))
                }
            }

            SomaDisclosure {
                VStack(alignment: .leading, spacing: 6) {
                    Text(recommendation.reason.explanation(snapshots: todaysSnapshots))
                    if !readinessInputs.isEmpty {
                        Text(readinessInputs.joined(separator: " · "))
                            .font(.system(size: 12.5, weight: .semibold))
                    }
                }
            }

            if let activeSportGoal {
                goalRow(activeSportGoal)
            }

            Divider().overlay(SomaTokens.hairline)

            if todaysWorkoutLog != nil {
                // Today's session is already logged -- reviewing it is the
                // action now; the detail sheet shows the completed state.
                SomaButton(title: "Check workout details", size: .lg, variant: .secondary) {
                    openTodaysWorkoutDetail()
                }
            } else {
                SomaButton(title: "Start workout", size: .lg, variant: .primary) {
                    requestDetailAccess { showDetail = true }
                }
            }

            // Always available, regardless of whether today's AI workout
            // is logged -- a user might do this INSTEAD of (or in
            // addition to) the AI plan. Free, no paywall: this is basic
            // tracking, same posture as manual meal logging.
            Button {
                showLogManualWorkout = true
            } label: {
                Text("Log a different activity")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(SomaTokens.accent)
            }
            .buttonStyle(.plain)

            restDayRequestControl(recommendation)
        }
    }

    /// Lets the user directly ask for a rest/active-recovery day regardless
    /// of what today's health-data-driven category says -- persisted
    /// server-side (see setRecommendationOverride), so it survives an app
    /// restart and generate-workout-plan/generate-gym-workout honor it too.
    /// Hidden once today's workout is already logged, since there's
    /// nothing left to override at that point.
    @ViewBuilder
    private func restDayRequestControl(_ recommendation: DailyRecommendation) -> some View {
        if todaysWorkoutLog == nil {
            if let requested = recommendation.userRequestedCategory {
                Button {
                    Task { await setRestDayRequest(nil) }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("You requested a \(requested == .rest ? "rest" : "active recovery") day today — Undo")
                    }
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(SomaTokens.ink3)
                }
                .buttonStyle(.plain)
                .disabled(isSettingRestDayRequest)
            } else {
                Button {
                    showRestDayOptions = true
                } label: {
                    Text("Not feeling it today?")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(SomaTokens.accent)
                }
                .buttonStyle(.plain)
                .disabled(isSettingRestDayRequest)
                .confirmationDialog("Request a different day", isPresented: $showRestDayOptions, titleVisibility: .visible) {
                    Button("Rest day") { Task { await setRestDayRequest(.rest) } }
                    Button("Active recovery") { Task { await setRestDayRequest(.light) } }
                    Button("Cancel", role: .cancel) {}
                }
            }
        }
    }

    private func setRestDayRequest(_ category: RecommendationCategory?) async {
        isSettingRestDayRequest = true
        defer { isSettingRestDayRequest = false }
        do {
            try await SupabaseClient.shared.setRecommendationOverride(date: Self.todayDateString(), category: category)
            await loadTodaysRecommendation()
        } catch {
            // Best-effort, same as the other Home refresh calls -- the
            // affordance stays in its pre-tap state so the user can retry.
        }
    }

    /// The card shows only while the feature's front door makes sense:
    /// beta catalog open, no goal yet, never after a dismiss.
    private var showSportGoalPromo: Bool {
        Config.enableSportGoals
            && !sportGoalPromoDismissed
            && activeSportGoal == nil
            && sportGoalCatalog?.isEmpty == false
    }

    /// Temporary NEW promo card (guide 05) -- the beta feature's front
    /// door. Once a goal exists the readiness card's goal row replaces it.
    private var sportGoalPromoCard: some View {
        // Two sibling buttons, no gesture layered over the whole card --
        // the open area and the dismiss X can never steal each other's tap.
        HStack(spacing: 0) {
            Button {
                if sportGoalOnboardingSeen {
                    showSportGoalScreen = true
                } else {
                    sportGoalOnboardingSeen = true
                    showSportGoalOnboarding = true
                }
            } label: {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(SomaTokens.accentSoft)
                        .frame(width: 36, height: 36)
                        .overlay(
                            Image(systemName: "target")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(SomaTokens.accent)
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Train for your sport")
                                .font(.system(size: 14.5, weight: .semibold))
                                .foregroundStyle(SomaTokens.ink)
                            Text("NEW")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(0.6)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(SomaTokens.accent))
                        }
                        Text("Pick one measurable goal — we build it into your plan")
                            .font(.system(size: 12))
                            .foregroundStyle(SomaTokens.ink4)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                sportGoalPromoDismissed = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SomaTokens.ink5)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 14)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(SomaTokens.surface)
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(SomaTokens.accentSoft, lineWidth: 1))
        )
    }

    /// A quiet one-line goal status + chevron -- deliberately not a button
    /// style that could compete with the card's single CTA.
    private func goalRow(_ goal: UserGoal) -> some View {
        Button {
            showSportGoalScreen = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "target")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SomaTokens.accent)
                Text(goalRowText(goal))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SomaTokens.ink2)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SomaTokens.ink5)
            }
        }
        .buttonStyle(SomaNavPillButtonStyle())
    }

    private func goalRowText(_ goal: UserGoal) -> String {
        let name = goal.displayName(in: sportGoalCatalog)
        if goal.kind == .custom, let weeks = goal.durationWeeks, let week = goal.currentWeek {
            return "\(name) · week \(min(week, weeks)) of \(weeks)"
        }
        if let weekLine = goal.weekLine {
            return "\(name) · \(weekLine)"
        }
        return name
    }

    /// The real inputs behind today's read -- only what a source actually
    /// reported, never fabricated (guide 09's Home disclosure row).
    private var readinessInputs: [String] {
        var parts: [String] = []
        if let sleep = todaysSnapshots.compactMap(\.sleepHours).first {
            parts.append("Sleep \(String(format: "%.1f", sleep)) h")
        }
        if let hrv = todaysSnapshots.compactMap(\.hrvMs).first {
            parts.append("HRV \(Int(hrv.rounded())) ms")
        }
        if let rhr = todaysSnapshots.compactMap(\.restingHr).first {
            parts.append("Resting HR \(Int(rhr.rounded())) bpm")
        }
        return parts
    }

    // MARK: - Scan row (guide 03: three states, never greyed-out-and-inert)

    private enum ScanState { case available, locked, hidden }

    /// Mirrors the server's tiered quota (generationLimits.ts): 3/day on
    /// annual, 1/day otherwise -- an explicit product decision there.
    private var dailyGenerationLimit: Int {
        SubscriptionManager.shared.tier == "annual" ? 3 : 1
    }

    private var scanState: ScanState {
        // A committed or completed workout removes the row entirely.
        if todaysWorkoutLog != nil || todaysAIPlan?.addedToPlan == true { return .hidden }
        // Lock only when today's quota is actually spent -- one scan must not
        // lock out an annual subscriber who still has generations left.
        if todaysGenerationCount >= dailyGenerationLimit { return .locked }
        return .available
    }

    @ViewBuilder
    private var scanRow: some View {
        switch scanState {
        case .hidden:
            EmptyView()
        case .available:
            Button {
                requestDetailAccess {
                    AnalyticsManager.shared.featureUsed(name: "gym_photo_workout")
                    showGymPhotoFlow = true
                }
            } label: {
                scanRowBody(
                    plate: SomaTokens.accentSoft, icon: "camera.fill", iconColor: SomaTokens.accent,
                    title: "Somewhere else today?",
                    subtitle: scanStreak > 1
                        ? "Scan the gym — we rebuild the plan · \(scanStreak)-day streak"
                        : "Scan the gym — we rebuild the plan"
                ) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SomaTokens.ink4)
                }
            }
            .buttonStyle(.plain)
        case .locked:
            if SubscriptionManager.shared.tier == "annual" {
                // Already on the top tier -- pitching an upgrade they own
                // would be wrong, so just say when the quota resets.
                scanRowBody(
                    plate: SomaTokens.warnSoft, icon: "lock.fill", iconColor: SomaTokens.warn,
                    title: "Today's generations are used",
                    subtitle: "Up to \(dailyGenerationLimit) AI workouts a day — more tomorrow"
                ) {
                    EmptyView()
                }
            } else {
                // The locked copy says what happened before it asks for money.
                Button {
                    Superwall.shared.register(placement: "view_premium")
                } label: {
                    scanRowBody(
                        plate: SomaTokens.warnSoft, icon: "lock.fill", iconColor: SomaTokens.warn,
                        title: "Today's scan is used",
                        subtitle: "Upgrade for up to 3 scans and workouts a day"
                    ) {
                        Text("PRO")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(SomaTokens.accentDeep))
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Previously the only way to find the goal/current body photo feature
    /// was one row buried deep in Profile's Training tab -- this surfaces
    /// it on Home instead, in one of two states: a CTA to add photos at
    /// all, or (once both exist) a tap-through to the actual comparison,
    /// framed as "your progress" rather than a settings row, since seeing
    /// it regularly is what's meant to keep someone coming back. Gated the
    /// same way the underlying feature already is (flag + adult
    /// confirmation) -- this is a second entry point, not a bypass.
    @ViewBuilder
    private var goalProgressRow: some View {
        if Config.enableBodyPhotoUpload && isConfirmedAdultForBodyPhotos {
            Button {
                AnalyticsManager.shared.featureUsed(name: "goal_progress_home_card")
                showGoalBodyProgress = true
            } label: {
                if hasGoalBodyPhoto && hasCurrentBodyPhoto {
                    scanRowBody(
                        plate: SomaTokens.accentSoft, icon: "photo.on.rectangle.angled", iconColor: SomaTokens.accent,
                        title: "Your progress",
                        subtitle: "See how you're tracking toward your goal photo"
                    ) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(SomaTokens.ink4)
                    }
                } else {
                    scanRowBody(
                        plate: SomaTokens.accentSoft, icon: "camera.fill", iconColor: SomaTokens.accent,
                        title: "Add your goal photo",
                        subtitle: "Helps point your plan and nutrition in the right direction"
                    ) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(SomaTokens.ink4)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    /// nil target (never computed -- no goal/current photo pair analyzed
    /// yet) shows a CTA rather than hiding entirely, same as
    /// goalProgressRow's own two-state pattern -- nutrition targets are a
    /// direct downstream product of that same photo comparison, so
    /// pointing here back at it is the honest "how do I get one" answer.
    private var nutritionRow: some View {
        Button {
            AnalyticsManager.shared.featureUsed(name: "nutrition_home_card")
            showNutrition = true
        } label: {
            if let nutritionTarget, let nutritionProgress {
                scanRowBody(
                    plate: SomaTokens.accentSoft, icon: "fork.knife", iconColor: SomaTokens.accent,
                    title: "Nutrition",
                    subtitle: "\(nutritionProgress.consumedCalories) / \(nutritionTarget.dailyCalories) kcal today"
                ) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SomaTokens.ink4)
                }
            } else {
                scanRowBody(
                    plate: SomaTokens.accentSoft, icon: "fork.knife", iconColor: SomaTokens.accent,
                    title: "Get your nutrition targets",
                    subtitle: "A daily calorie and macro target built around your goal"
                ) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SomaTokens.ink4)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func scanRowBody(plate: Color, icon: String, iconColor: Color, title: String, subtitle: String, @ViewBuilder trailing: () -> some View) -> some View {
        CardView {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: SomaTokens.rMD, style: .continuous).fill(plate))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(SomaTokens.ink3)
                }
                Spacer()
                trailing()
            }
        }
    }

    /// Tapping opens the detail sheet in its completed state -- same
    /// destination as the readiness card's "Check workout details" CTA.
    private func todaysWorkoutCard(_ log: WorkoutLogEntry) -> some View {
        Button {
            openTodaysWorkoutDetail()
        } label: {
            CardView {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(log.source == "manual" ? "Today's activity" : "Today's workout")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(log.title)
                            .font(.body.bold())
                    }
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// Shown once a plan is added to today's plan but not yet completed --
    /// distinct from todaysWorkoutCard (completed, via workout_log). Tapping
    /// opens the same detail sheet the recommendation card does, so "Mark
    /// Workout Complete" stays a separate, explicit action from here.
    private func aiGeneratedWorkoutCard(_ aiPlan: TodaysAIPlan) -> some View {
        Button {
            requestDetailAccess { showDetail = true }
        } label: {
            CardView {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Today's AI-generated workout")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(aiPlan.selectedTitle)
                            .font(.body.bold())
                        if aiPlan.source == "gym_photo" {
                            Text("Generated with your gym picture")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// What was actually recorded today, across every connected source --
    /// distinct from `todaysWorkoutCard` above (which reflects what the
    /// user told Soma they did). Merged client-side since HealthKit can
    /// only be read on-device while Oura/Whoop are read server-side.
    private var timelineCard: some View {
        CardView {
            Text("Today's timeline")
                .font(.body.bold())
            ForEach(timelineEntries) { entry in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title)
                            .font(.subheadline.bold())
                        Text("\(entry.sourceDisplayName) — \(Self.timeString(entry.startTime)) — \(entry.durationMinutes) min\(entry.calories.map { " — \($0) kcal" } ?? "")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var needsDataCard: some View {
        CardView {
            Text("Soma needs today's data")
                .font(.body.bold())
            Text("Pull to refresh, or check now.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            PillButton(title: "Check now", isEnabled: !isLoading) {
                Task { await checkNow() }
            }
        }
    }

    /// Reads today's row first; if it doesn't exist yet, generates it on
    /// the spot instead of leaving the user on a stale/empty state.
    ///
    /// BGAppRefreshTask timing is best-effort only (iOS decides whether it
    /// runs at all some mornings), so a plain read alone means "opening
    /// the app in the morning" and "having today's real recommendation"
    /// aren't reliably the same thing. Falling back to the same call
    /// "Check now" uses closes that gap -- every app open either shows an
    /// already-generated row or generates one immediately.
    private func loadTodaysRecommendation() async {
        do {
            if let recommendation = try await SupabaseClient.shared.fetchTodaysRecommendation(date: Self.todayDateString()) {
                appState.currentRecommendation = recommendation
                return
            }
        } catch {
            // Falls through to the generate-on-open path below.
        }
        await checkNow()
    }

    /// Feeds the calendar strip -- silent on failure, same as the other
    /// plain reads (worst case the strip just shows neutral gray dots).
    private func loadRecentRecommendations() async {
        recentRecommendations = (try? await SupabaseClient.shared.fetchRecentRecommendations()) ?? recentRecommendations
    }

    /// Reflects "Mark Workout Complete" in RecommendationDetailView --
    /// refreshed on appear, pull-to-refresh, and whenever the detail sheet
    /// closes (that's the only place a log can be created).
    private func loadTodaysWorkoutLog() async {
        let logs = (try? await SupabaseClient.shared.fetchWorkoutLogs(date: Self.todayDateString())) ?? []
        todaysWorkoutLog = logs.first
    }

    /// Feeds the calendar strip's crown badge -- silent on failure, same
    /// as the other plain reads.
    private func loadCompletedDates() async {
        completedDates = (try? await SupabaseClient.shared.fetchRecentWorkoutLogDates()) ?? completedDates
    }

    /// Feeds the "Take a Picture of Your Gym" disable gate and the
    /// persistent AI-generated-workout card -- silent on failure, same as
    /// the other plain reads.
    private func loadTodaysAIPlan() async {
        todaysAIPlan = (try? await SupabaseClient.shared.fetchTodaysAIPlan(date: Self.todayDateString())) ?? todaysAIPlan
    }

    /// Feeds the scan card's streak -- the Dashboard pill's "N done" badge
    /// no longer needs its own fetch here, since it's derived directly from
    /// `completedDates` (see `doneThisWeekCount`), the same data the
    /// calendar strip itself renders.
    private func loadWeeklyProgressAndStreak() async {
        async let scanDatesFetch: Set<String> = (try? await SupabaseClient.shared.fetchGymPhotoScanDates()) ?? []
        async let profileFetch: UserProfile? = {
            guard let userId = SupabaseClient.shared.currentUserID else { return nil }
            return try? await SupabaseClient.shared.fetchProfile(id: userId)
        }()
        async let snapshotsFetch: [DailySnapshotRow] = (try? await SupabaseClient.shared.fetchTodaysSnapshots(date: Self.todayDateString())) ?? []
        async let generationCountFetch: Int = (try? await SupabaseClient.shared.fetchTodaysGenerationCount(date: Self.todayDateString())) ?? 0

        scanDates = await scanDatesFetch
        scanStreak = Self.streak(from: scanDates)
        let profile = await profileFetch
        weeklyTarget = profile?.weeklySessionTarget
        todaysSnapshots = await snapshotsFetch
        todaysGenerationCount = await generationCountFetch
        await loadSportGoal()
    }

    /// Reuses loadWeeklyProgressAndStreak's own profile fetch would mean
    /// waiting on scan dates/snapshots too just to know if a goal photo is
    /// set -- cheap enough on its own to just fetch again independently.
    private func loadGoalBodyPhotoState() async {
        guard let userId = SupabaseClient.shared.currentUserID,
              let profile = try? await SupabaseClient.shared.fetchProfile(id: userId) else { return }
        hasGoalBodyPhoto = profile.goalBodyPhotoPath != nil
        hasCurrentBodyPhoto = profile.currentBodyPhotoPath != nil
        isConfirmedAdultForBodyPhotos = AgeGate.isAdult(dobString: profile.dateOfBirth)
    }

    /// nil target (never computed -- no goal/current photo pair analyzed
    /// yet) is a real, valid state, not an error -- the row below shows a
    /// CTA instead of hiding entirely, same posture as goalProgressRow's
    /// own "add your goal photo" state.
    private func loadNutritionState() async {
        guard let target = try? await SupabaseClient.shared.fetchNutritionTargets() else {
            nutritionTarget = nil
            nutritionProgress = nil
            return
        }
        nutritionTarget = target
        let entries = (try? await SupabaseClient.shared.fetchMealLogs(date: Self.todayDateString())) ?? []
        nutritionProgress = NutritionDayProgress.compute(entries: entries, target: target)
    }

    /// Best-effort: no goal (or a failed fetch) simply means no goal row --
    /// the same natural "off" state the server kill switch produces.
    private func loadSportGoal() async {
        guard Config.enableSportGoals else { return }
        // In parallel -- the goal read no longer gates the catalog read.
        // The catalog is always refetched: it's RLS-gated by the beta
        // toggle, so this is what makes the promo card appear (or every
        // entry point vanish) in the same session the toggle changes.
        async let goalFetch: UserGoal? = try? await SupabaseClient.shared.fetchActiveGoal()
        async let catalogFetch: SportCatalog? = try? await SupabaseClient.shared.fetchSportCatalog()
        activeSportGoal = await goalFetch
        if let catalog = await catalogFetch {
            sportGoalCatalog = catalog
        }
    }

    private static func longDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, d MMMM"
        return formatter.string(from: Date())
    }

    private static func timeOfDayGreeting() -> String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
    }

    /// Consecutive days up to and including today present in `dates`.
    private static func streak(from dates: Set<String>) -> Int {
        var count = 0
        var cursor = Date()
        while dates.contains(dateString(cursor)) {
            count += 1
            cursor = Calendar.current.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        return count
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    /// Merges HealthKit's on-device workouts with Oura/Whoop's
    /// server-fetched ones into one chronological timeline. Each half
    /// fails independently (silent on failure) -- worst case the timeline
    /// just shows whichever source actually responded.
    private func loadTimeline() async {
        async let healthKitEntries: [WorkoutTimelineEntry] = HealthKitManager.isAvailable
            ? await HealthKitManager.shared.fetchTodaysWorkouts()
            : []
        async let providerEntries: [WorkoutTimelineEntry] = (try? await SupabaseClient.shared.fetchProviderWorkoutTimeline(date: Self.todayDateString())) ?? []

        async let syncedEntries: [WorkoutTimelineEntry] = (try? await SupabaseClient.shared.fetchSyncedHealthKitWorkouts(date: Self.todayDateString())) ?? []

        let hkEntries = await healthKitEntries
        if !hkEntries.isEmpty {
            Task { try? await SupabaseClient.shared.syncHealthKitWorkouts(hkEntries) }
        }

        // Server-stored HealthKit workouts fill in what this device did not
        // record itself -- a session logged on another phone or watch. Local
        // wins on collision, since it is the source of truth for this device
        // and may be newer than the last successful sync.
        let localKeys = Set(hkEntries.map { "\($0.source)|\($0.startTime.timeIntervalSince1970)" })
        let syncedOnly = await syncedEntries.filter {
            !localKeys.contains("\($0.source)|\($0.startTime.timeIntervalSince1970)")
        }

        let merged = await (hkEntries + syncedOnly + providerEntries)
        timelineEntries = merged.sorted { $0.startTime < $1.startTime }
    }

    /// Manual fallback ("Check now" / pull-to-refresh) -- calls the same
    /// Edge Function the automated morning triggers use.
    private func checkNow() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let snapshot = HealthKitManager.isAvailable
                ? await HealthKitManager.shared.fetchTodaysMetrics()
                : nil
            let recommendation = try await SupabaseClient.shared.invokeGenerateRecommendation(
                date: Self.todayDateString(),
                healthkit: snapshot
            )
            appState.currentRecommendation = recommendation
            NotificationManager.shared.markSentToday()
        } catch {
            // Covers "expired wearable token" / "zero connected devices" --
            // show a clear message instead of crashing.
            errorMessage = "Couldn't fetch today's data. Reconnect a device or try again."
        }
    }

    private static func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func todayDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: Date())
    }
}

#Preview {
    HomeView()
        .environmentObject(AppState())
        .environmentObject(SubscriptionManager.shared)
}
