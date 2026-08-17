import SuperwallKit
import StoreKit
import SwiftUI

/// Screen 4 -- Home. No text input, no chat history, no voice button.
struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var checklistRouter = ChecklistDeepLinkRouter.shared
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showDetail = false
    @State private var showProfile = false
    @State private var showHealthDashboard = false
    @State private var healthDashboardInitialSection: HealthDashboardView.DashboardSection = .overview
    @State private var recentRecommendations: [DailyRecommendation] = []
    @State private var selectedDay: String?
    @State private var todaysWorkoutLog: WorkoutLogEntry?
    @State private var completedDates: Set<String> = []
    @State private var goalTrainingDates: Set<String> = []
    // Manual activity logging (real feedback: users want to log a sport
    // session -- soccer, volleyball, hot yoga -- outside the AI plan).
    // showManualWorkoutDetail routes "see today's workout" to
    // CompletedWorkoutView instead of RecommendationDetailView whenever
    // todaysWorkoutLog.source == "manual", since that view has no
    // suggestion titles to match a manually-logged activity against.
    @State private var showLogManualWorkout = false
    @State private var showManualWorkoutDetail = false

    // Daily "how are you feeling?" check-in -- real feedback: "some
    // human-level metric that the app optimizes ... showing that the
    // metric improves with app usage." Trend view lives on the Health
    // Dashboard's Overview tab; this card is just the daily capture.
    @State private var todaysMood: DailyMoodEntry?
    @State private var isSavingMood = false
    /// Real feedback: "when the user taps on one of the emojis ... nothing
    /// happens." logMood used to fail completely silently (the daily_mood
    /// table not existing yet on a given backend was one real cause, but
    /// ANY failure -- network, auth -- looked identical to the user: a tap
    /// that visibly did nothing). Surfacing this turns a mystery bug report
    /// into something the user can see and retry.
    @State private var moodError: String?

    /// Daily "how long did you sleep?" check-in -- shown only when no
    /// wearable reported real hours for today (see `sleepWidgetTile`).
    /// Same upsert/error-surfacing posture as mood, just for a different
    /// metric.
    @State private var todaysSleepLog: DailySleepLogEntry?
    /// "Tap to change" reveals the duration chips without discarding
    /// `todaysSleepLog` -- see `loadTodaysSleep`'s doc comment for why it
    /// used to be cleared to nil instead.
    @State private var isEditingSleep = false
    @State private var isSavingSleep = false
    @State private var sleepError: String?
    @State private var timelineEntries: [WorkoutTimelineEntry] = []

    @State private var showGymPhotoFlow = false
    @State private var scanUnavailableReason: ScanUnavailableReason?
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
    /// Gym-photo scans generated today (gym_photo source only -- each AI
    /// feature has its own independent daily cap now) -- compared against
    /// the tier's daily limit to drive the scan row's `locked` state. See
    /// SupabaseClient.fetchTodaysGenerationCount's doc comment.
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
    /// "Not feeling it today?" confirmation dialog, and the in-flight state
    /// for setting/clearing that request. See restDayRequestControl.
    @State private var showRestDayOptions = false
    @State private var isSettingRestDayRequest = false

    /// Set while openTodaysWorkoutDetail() is loading today's
    /// recommendation before it can present anything -- see that
    /// function's own doc comment. Only the checklist's "Review your
    /// first plan" row can actually trigger this (the readiness card's
    /// own buttons never exist until a recommendation is already
    /// showing); DailyChecklistCardView shows a spinner on the matching
    /// row instead of its usual chevron while this is set, rather than
    /// presenting an empty sheet.
    @State private var checklistLoadingDeepLink: ChecklistDeepLink?

    /// The "How Soma Works" tour, opened from the checklist's "See how
    /// Soma works" row (first time) -- see handleChecklistDeepLink.
    @State private var showHowSomaWorks = false
    /// DailyChecklistCardView owns its own private load() behind a
    /// .task, with no external refresh hook -- bumping this and applying
    /// it as the card's .id() is how HomeView forces a reload after the
    /// tour's completion write, the same way changing a List row's id
    /// forces SwiftUI to recreate (and thus re-.task) that row.
    @State private var checklistRefreshToken = 0
    /// Mirrored from DailyChecklistCardView's own load() via onProgressChange
    /// -- nil until that view has actually loaded once (inline widget or the
    /// greeting-row pill's sheet), never a fabricated placeholder count.
    @State private var checklistDone: Int?
    @State private var checklistTotal: Int?
    @State private var showChecklistSheet = false
    @State private var showHistoryCalendar = false

    // MARK: - Dashboard widgets + dock (Soma Glass 3a/3c/3e handoff)

    /// Which optional cards show on the dashboard -- set from
    /// `EditWidgetsSheet` (3c). Log workout isn't here: it's the dock's
    /// pinned-first action, not a toggleable widget. Defaults match the
    /// handoff mockup's toggle states.
    @AppStorage("dashboardWidget.water") private var waterWidgetEnabled = true
    @AppStorage("dashboardWidget.sleep") private var sleepWidgetEnabled = true
    @AppStorage("dashboardWidget.streak") private var streakWidgetEnabled = true
    @AppStorage("dashboardWidget.dailyTasks") private var dailyTasksWidgetEnabled = true
    @AppStorage("dashboardWidget.mood") private var moodWidgetEnabled = true
    @AppStorage("dashboardWidget.nutrition") private var nutritionWidgetEnabled = true
    @AppStorage("dashboardWidget.sportGoal") private var sportGoalWidgetEnabled = true
    @AppStorage("dashboardWidget.photoProgress") private var photoProgressWidgetEnabled = false
    @AppStorage("dashboardWidget.affirmation") private var affirmationWidgetEnabled = true
    @State private var showEditWidgets = false
    /// Affirmation widget (16a) -- today's line, its sheet, and the
    /// inline refresh action's in-flight/limit state.
    @State private var todaysAffirmation: DailyAffirmation?
    @State private var showAffirmations = false
    /// PRO chip tap (15a): the native manage-subscriptions sheet.
    @State private var showManageSubscriptions = false
    @State private var affirmationSheetStartsEditing = false
    @State private var isRegeneratingAffirmation = false
    /// Streak tile tap -> the same share card Profile's streak section
    /// offers (real feedback: streak must be tappable and sharable).
    @State private var showStreakShare = false
    @State private var showMoreActions = false
    /// Set by `MoreActionsSheet` right before it dismisses itself, fired
    /// from that sheet's own `.onDismiss` -- the same chain-sheets pattern
    /// `showGymPhotoFlow`'s seeded-detail flow uses, so this sheet and the
    /// action's own sheet never try to present at the same time.
    @State private var pendingMoreAction: (() -> Void)?

    /// Water tracker widget -- UI-only per the design handoff ("no backend
    /// anywhere... kept as a placeholder by the user's explicit choice").
    /// Keyed by day so it doesn't carry yesterday's count into today.
    @State private var waterGlassesToday = 0
    private static func waterStorageKey(for date: String = Self.todayDateString()) -> String { "water.\(date)" }

    /// Reads a past day's water count straight from the same date-keyed
    /// UserDefaults entry this widget already writes -- lets the history
    /// calendar's "perfect day" crown check water without a backend, same
    /// UI-only-placeholder scope this widget already has.
    static func waterGlasses(on date: String) -> Int {
        UserDefaults.standard.integer(forKey: waterStorageKey(for: date))
    }

    /// Glass size chip (9b) -- a standing preference, not day-scoped, that
    /// the "+"/"-" and droplet-tap actions all read but don't themselves
    /// change; only the chip's own tap cycles it.
    @AppStorage("water.glassSizeML") private var waterGlassSizeML = 250
    private static let waterGlassSizes = [150, 200, 250, 330, 500]

    private func cycleWaterGlassSize() {
        let sizes = Self.waterGlassSizes
        let currentIndex = sizes.firstIndex(of: waterGlassSizeML) ?? 2
        waterGlassSizeML = sizes[(currentIndex + 1) % sizes.count]
    }

    private enum TrainingSource { case somasPick, custom }
    /// Custom-training source toggle (5a/5b) -- UI + local selection only.
    /// No matching recommendation-engine code exists for this yet, so
    /// `.custom` shows an honest "coming soon" state rather than a
    /// fabricated workout (see `customTrainingCard`).
    @State private var trainingSource: TrainingSource = .somasPick
    @AppStorage("customTrainingSportId") private var customTrainingSportId = ""
    @State private var showCustomTrainingPicker = false

    var body: some View {
        ScrollView {
            // Soma Glass 3a order: a bare "•••" settings glyph top-right
            // (the mockup's own status-bar row -- "21:36 •••" -- the dots
            // are a real settings entry point, not decoration) → bare week
            // strip (no card, sits directly on the gradient) → greeting
            // row (with the checklist ring-pill) → hero card. No weekly-
            // progress card on Home -- the week reads from the hearts
            // themselves. Health dashboard is reachable from the dock.
            VStack(spacing: 16) {
                settingsRow

                bareWeekStrip

                greetingRow

                if subscriptionManager.isInTrial {
                    trialUpgradeBanner
                }

                if showTrainingSourceToggle {
                    trainingSourceToggle
                }

                Group {
                    if trainingSource == .custom {
                        customTrainingCard
                    } else if let recommendation = appState.currentRecommendation {
                        readinessCard(recommendation)
                    } else {
                        needsDataCard
                    }
                }

                if todaysWorkoutLog == nil, let todaysAIPlan, todaysAIPlan.addedToPlan {
                    aiGeneratedWorkoutCard(todaysAIPlan)
                }

                widgetGrid

                if dailyTasksWidgetEnabled {
                    dailyChecklistWidget
                }

                if photoProgressWidgetEnabled {
                    goalProgressRow
                }

                if !timelineEntries.isEmpty {
                    timelineCard
                }
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 100)
            // Keeps checklistDone/checklistTotal populated even when the
            // "Daily tasks" widget is off, so the greeting row's ring-pill
            // -- the only other entry point into the checklist sheet --
            // doesn't become permanently unreachable (onProgressChange only
            // ever fires from a mounted DailyChecklistCardView).
            .background(
                Group {
                    if !dailyTasksWidgetEnabled {
                        dailyChecklistWidget
                            .frame(width: 0, height: 0)
                            .clipped()
                            .hidden()
                            .accessibilityHidden(true)
                    }
                }
            )
        }
        .somaBackground()
        .safeAreaInset(edge: .bottom) {
            dashboardDock
        }
        .task {
            waterGlassesToday = UserDefaults.standard.integer(forKey: Self.waterStorageKey())
            await loadTodaysRecommendation()
            await appState.refreshReferralBonus()
            await loadRecentRecommendations()
            await loadTodaysWorkoutLog()
            // Independent fetches feeding the calendar strip's two separate
            // badges (crown/star) -- no data dependency between them.
            async let completedDatesFetch: Void = loadCompletedDates()
            async let goalTrainingDatesFetch: Void = loadGoalTrainingDates()
            await completedDatesFetch
            await goalTrainingDatesFetch
            await loadTimeline()
            await autoLogDeviceDetectedWorkoutIfNeeded()
            await loadTodaysAIPlan()
            await loadWeeklyProgressAndStreak()
            await loadGoalBodyPhotoState()
            await loadNutritionState()
            try? await loadTodaysMood()
            try? await loadTodaysSleep()
            await loadTodaysAffirmation()
        }
        .refreshable {
            await checkNow()
            await loadRecentRecommendations()
            await loadTodaysWorkoutLog()
            // Independent fetches feeding the calendar strip's two separate
            // badges (crown/star) -- no data dependency between them.
            async let completedDatesFetch: Void = loadCompletedDates()
            async let goalTrainingDatesFetch: Void = loadGoalTrainingDates()
            await completedDatesFetch
            await goalTrainingDatesFetch
            await loadTimeline()
            await autoLogDeviceDetectedWorkoutIfNeeded()
            await loadTodaysAIPlan()
            await loadWeeklyProgressAndStreak()
            await loadNutritionState()
            try? await loadTodaysMood()
            try? await loadTodaysSleep()
            await loadTodaysAffirmation()
        }
        .sheet(isPresented: $showDetail, onDismiss: {
            Task {
                await loadTodaysWorkoutLog()
                async let completedDatesFetch: Void = loadCompletedDates()
                async let goalTrainingDatesFetch: Void = loadGoalTrainingDates()
                await completedDatesFetch
                await goalTrainingDatesFetch
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
            // Date of birth is also edited inside Profile (Account
            // settings) -- without this, isConfirmedAdultForBodyPhotos
            // stayed stuck at whatever it was on Home's initial load, so
            // the "Add your date of birth" nudge never cleared even after
            // the user actually added one and dismissed back to Home.
            Task { await loadGoalBodyPhotoState() }
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
            HealthDashboardView(initialSection: healthDashboardInitialSection)
        }
        .sheet(isPresented: $showHowSomaWorks) {
            HowSomaWorksTourView(onFinish: {
                showHowSomaWorks = false
                Task { await completeHowSomaWorksItem() }
            })
        }
        .sheet(isPresented: $showSportGoalScreen, onDismiss: {
            Task { await loadSportGoal() }
        }) {
            SportGoalFlowView()
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
        .alert(
            scanUnavailableAlertTitle,
            isPresented: Binding(get: { scanUnavailableReason != nil }, set: { if !$0 { scanUnavailableReason = nil } })
        ) {
            Button(String(localized: "home.scanGym.unavailable.gotIt", defaultValue: "Got it", comment: "Dismiss button for the scan-gym-unavailable alert")) {}
        } message: {
            Text(scanUnavailableAlertMessage)
        }
        .sheet(isPresented: $showSeededDetail, onDismiss: {
            pendingGymPlan = nil
            Task {
                await loadTodaysWorkoutLog()
                async let completedDatesFetch: Void = loadCompletedDates()
                async let goalTrainingDatesFetch: Void = loadGoalTrainingDates()
                await completedDatesFetch
                await goalTrainingDatesFetch
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
                DayDetailView(date: selectedDay, recentRecommendations: recentRecommendations, activeSportGoal: activeSportGoal)
            }
        }
        .sheet(isPresented: $showChecklistSheet) {
            checklistSheet
        }
        .sheet(isPresented: $showHistoryCalendar) {
            HistoryCalendarView()
        }
        .sheet(isPresented: $showEditWidgets) {
            EditWidgetsSheet(
                waterEnabled: $waterWidgetEnabled,
                sleepEnabled: $sleepWidgetEnabled,
                streakEnabled: $streakWidgetEnabled,
                dailyTasksEnabled: $dailyTasksWidgetEnabled,
                moodEnabled: $moodWidgetEnabled,
                nutritionEnabled: $nutritionWidgetEnabled,
                sportGoalEnabled: $sportGoalWidgetEnabled,
                photoProgressEnabled: $photoProgressWidgetEnabled,
                affirmationEnabled: $affirmationWidgetEnabled
            )
        }
        .manageSubscriptionsSheet(isPresented: $showManageSubscriptions)
        .sheet(isPresented: $showAffirmations, onDismiss: {
            affirmationSheetStartsEditing = false
            // The sheet can edit/regenerate today's line -- re-read so the
            // widget reflects it the moment the sheet closes.
            Task { await loadTodaysAffirmation() }
        }) {
            AffirmationsView(startEditing: affirmationSheetStartsEditing)
        }
        .sheet(isPresented: $showMoreActions, onDismiss: {
            pendingMoreAction?()
            pendingMoreAction = nil
        }) {
            MoreActionsSheet(actions: configurableDockActions + overflowDockActions) { selected in
                pendingMoreAction = selected.action
                showMoreActions = false
            }
        }
        .sheet(isPresented: $showCustomTrainingPicker) {
            CustomTrainingPickerSheet(
                sports: sportGoalCatalog?.sports ?? [],
                selectedSportId: customTrainingSportId.isEmpty ? nil : customTrainingSportId
            ) { sport in
                customTrainingSportId = sport.id
                trainingSource = .custom
            }
        }
        .onChange(of: checklistRouter.pending) { _, newValue in
            guard let newValue else { return }
            handleChecklistDeepLink(newValue)
            checklistRouter.pending = nil
        }
        .onAppear {
            // Covers the cold-launch case (app wasn't already running when
            // the notification was tapped) -- onChange alone only fires
            // for a value that changes while this view already exists.
            if let pending = checklistRouter.pending {
                handleChecklistDeepLink(pending)
                checklistRouter.pending = nil
            }
            #if DEBUG
            // Fixture-run shortcut straight into the History calendar --
            // this Mac's Simulator intermittently stops delivering synthetic
            // taps to SwiftUI content (see the project's own note), so
            // screenshot verification of 15a needs a tap-free way in.
            if UITestSupport.isActive,
               ProcessInfo.processInfo.arguments.contains("--ui-test-open-history") {
                showHistoryCalendar = true
            }
            #endif
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
        let handler = SuperwallDiagnostics.handler(placement: "detail_access")
        // Dismissible placement -- eligible for the exit-intent win-back
        // offer on a genuine decline. onboarding_paywall deliberately
        // does NOT get this (see PostSetupFlowView.presentOnboardingPaywall).
        handler.onDismiss { _, result in
            WinBackOfferManager.maybePresentAfterDecline(result: result)
        }
        Superwall.shared.register(placement: "detail_access", handler: handler, feature: action)
    }

    /// The single routing decision for "what does today's workout look
    /// like right now" -- the readiness card's own "Start workout"/"Check
    /// workout details" buttons both call this (see readinessCard) rather
    /// than each re-implementing the branch, and the checklist's
    /// "Review your first plan" deep link (.startWorkout) reuses it too,
    /// which is the fix this doc comment exists to explain:
    ///
    /// Previously this function ONLY handled the "something is already
    /// logged" case (the two branches below) -- correct for the readiness
    /// card, since its "Check workout details" button only ever exists
    /// once todaysWorkoutLog is non-nil. But the checklist's "Review your
    /// first plan" row is tappable for a brand-new user with NO log yet
    /// (that's the entire premise of the row), and calling this same
    /// function unconditionally fell into the `else` branch below,
    /// presenting CompletedWorkoutView with a nil log -- a blank sheet
    /// (its own `if let todaysWorkoutLog` guard just rendered nothing).
    ///
    /// Three real destinations now:
    ///   - Nothing logged yet -> today's plan/"why" (RecommendationDetailView),
    ///     same content the readiness card's "Start workout" button shows.
    ///     Needs appState.currentRecommendation loaded first -- unlike the
    ///     readiness card (which never renders its buttons until a
    ///     recommendation already exists), the checklist card can be
    ///     tapped before HomeView's own load finishes, so this loads it
    ///     on demand (with checklistLoadingDeepLink driving a spinner on
    ///     the tapped row) rather than presenting an empty sheet.
    ///   - Logged via the AI plan -> the same RecommendationDetailView,
    ///     which renders its own "already completed" state.
    ///   - Logged manually or auto-detected -> CompletedWorkoutView, the
    ///     generic completed-activity screen (no AI suggestion titles to
    ///     match against). Same paywall gate in every case.
    private func openTodaysWorkoutDetail() {
        guard todaysWorkoutLog != nil else {
            guard appState.currentRecommendation != nil else {
                guard checklistLoadingDeepLink == nil else { return } // already loading
                checklistLoadingDeepLink = .startWorkout
                Task {
                    await loadTodaysRecommendation()
                    checklistLoadingDeepLink = nil
                    if appState.currentRecommendation != nil {
                        requestDetailAccess { showDetail = true }
                    }
                    // A failed load leaves currentRecommendation nil and
                    // simply does nothing further here -- no worse than
                    // the row not responding, never an empty sheet.
                }
                return
            }
            requestDetailAccess { showDetail = true }
            return
        }
        if todaysWorkoutLog?.source == "ai_plan" {
            requestDetailAccess { showDetail = true }
        } else {
            requestDetailAccess { showManualWorkoutDetail = true }
        }
    }

    private var isBestReadinessDay: Bool {
        CalendarStripView.bestReadinessDate(among: recentRecommendations) == Self.todayDateString()
    }


    // MARK: - Greeting (guide 03: "where am I")

    /// Date eyebrow + serif greeting, with the checklist's live progress as
    /// a compact ring-pill on the trailing edge (3a: "greeting row = date
    /// eyebrow + serif greeting left, checklist N/M ring-pill right, opens
    /// the checklist -- the checklist card itself isn't on 3a's first
    /// viewport"). The pill shows "—" rather than a fabricated count until
    /// DailyChecklistCardView has actually loaded once (inline widget or
    /// this row's own sheet).
    private var greetingRow: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.longDateString())
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SomaTokens.ink3)
                Text(Self.timeOfDayGreeting())
                    .font(SomaType.greeting)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                editWidgetsButton

                historyCalendarButton

                // No placeholder state -- until DailyChecklistCardView has
                // actually loaded once (inline widget or this pill's own
                // sheet), there's nothing real to show, so show nothing.
                if let checklistDone, let checklistTotal, checklistTotal > 0 {
                    Button {
                        showChecklistSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            ProgressRing(fraction: Double(checklistDone) / Double(checklistTotal))
                                .frame(width: 14, height: 14)
                            Text(String(localized: "home.greetingRow.checklistProgress", defaultValue: "\(checklistDone)/\(checklistTotal)", comment: "Home: greeting row ring-pill showing checklist items done out of total, e.g. '3/5'"))
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundStyle(SomaTokens.accent)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 7)
                        .glassLens()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// 3a: calendar-lens entry point immediately left of the checklist
    /// ring-pill -- opens the new month-grid history screen (15a). Distinct
    /// from tapping a day chip in the week strip, which still opens
    /// `DayDetailView` for that single day.
    /// Quick access to the widget picker, right next to the calendar lens
    /// -- same 30pt lens recipe; previously the sheet was only reachable
    /// through the dock's More sheet.
    private var editWidgetsButton: some View {
        Button {
            showEditWidgets = true
        } label: {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SomaTokens.accent)
                .frame(width: 30, height: 30)
                .glassLens(cornerRadius: SomaTokens.rPill)
        }
        .buttonStyle(SomaNavPillButtonStyle())
        .accessibilityLabel(String(localized: "home.greetingRow.editWidgets.accessibilityLabel", defaultValue: "Edit widgets", comment: "Home: greeting row grid-icon button that opens the edit-widgets sheet"))
        .accessibilityIdentifier("home.editWidgetsButton")
    }

    private var historyCalendarButton: some View {
        Button {
            showHistoryCalendar = true
        } label: {
            // 3a draws its own minimal glyph (rounded rect + 2 hinge ticks +
            // 1 divider line) rather than SF Symbol "calendar" -- that
            // symbol bakes in a 3x3 dot grid that reads busy/off-center at
            // 18pt inside a 30pt circle.
            HistoryCalendarGlyph()
                .stroke(SomaTokens.accent, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                .frame(width: 18, height: 18)
                .frame(width: 30, height: 30)
                .glassLens(cornerRadius: SomaTokens.rPill)
        }
        .buttonStyle(SomaNavPillButtonStyle())
        .accessibilityLabel(String(localized: "home.greetingRow.historyCalendar.accessibilityLabel", defaultValue: "History", comment: "Home: greeting row calendar-icon button that opens the full training history calendar"))
        .accessibilityIdentifier("home.historyCalendarButton")
    }

    /// The mockup's own top row (`21:36 •••`) -- the dots are a real
    /// settings entry point (opens Profile directly), not a decorative
    /// status-bar stand-in. No time label: the real device status bar
    /// already shows one.
    private var settingsRow: some View {
        HStack(spacing: 8) {
            Spacer()
            // 15a's gold plaque: PRO (paid) / N DAYS (promo bonus) /
            // TRIAL · N DAYS (trial), immediately left of the ••• --
            // plain free users see nothing here.
            if let chipState = SubscriptionChipState.resolve(
                isSubscribed: subscriptionManager.isSubscribed,
                isInTrial: subscriptionManager.isInTrial,
                expirationDate: subscriptionManager.expirationDate,
                referralBonusUntil: appState.referralBonusUntil
            ) {
                SubscriptionStatusChip(state: chipState) {
                    switch chipState {
                    case .paid:
                        showManageSubscriptions = true
                    case .trial:
                        // Entitled user -- view_premium's audience skips
                        // them; see SuperwallDiagnostics.registerTrialUpgrade.
                        SuperwallDiagnostics.registerTrialUpgrade { showManageSubscriptions = true }
                    case .promoBonus:
                        let handler = SuperwallDiagnostics.handler(placement: "view_premium")
                        handler.onDismiss { _, result in
                            WinBackOfferManager.maybePresentAfterDecline(result: result)
                        }
                        Superwall.shared.register(placement: "view_premium", handler: handler)
                    }
                }
            }
            Button {
                showProfile = true
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(SomaTokens.ink4)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(SomaNavPillButtonStyle())
            .accessibilityLabel(String(localized: "home.settingsRow.accessibilityLabel", defaultValue: "Settings", comment: "Home: top-right ellipsis button that opens Profile/settings"))
        }
    }

    // MARK: - Week strip (Soma Glass 3a: bare hearts directly on the
    // gradient, no card chrome) + weekly progress pill

    private var bareWeekStrip: some View {
        CalendarStripView(
            recommendations: recentRecommendations,
            completedDates: completedDates,
            goalTrainingDates: goalTrainingDates,
            selectedDate: selectedDay,
            onSelectDay: { selectedDay = $0 }
        )
    }

    /// Reuses signals HomeView already loads for its own cards (mood,
    /// workout log, connected providers, today's recommendation) rather
    /// than having the checklist card re-fetch them independently -- see
    /// DailyChecklistCardView's own doc comment on why.
    private var dailyChecklistCard: some View {
        DailyChecklistCardView(
            date: Self.todayDateString(),
            signals: DailyChecklistCardView.SharedSignals(
                moodLoggedToday: todaysMood != nil,
                workoutLoggedToday: todaysWorkoutLog != nil,
                healthKitConnected: !appState.connectedProviders.isEmpty,
                hasReviewedFirstPlan: appState.currentRecommendation != nil
            ),
            loadingDeepLink: checklistLoadingDeepLink,
            onDeepLink: handleChecklistDeepLink,
            onProgressChange: { done, total in
                checklistDone = done
                checklistTotal = total
            }
        )
        .id(checklistRefreshToken)
    }

    /// Home's own "Your widgets" entry -- per the Soma Glass 3e handoff
    /// this is a compact preview (title/counter/progress bar + the first
    /// couple of open items + a link into the full list), not the whole
    /// checklist inline; the sheet still shows every item via
    /// `dailyChecklistCard`'s `.full` default.
    private var dailyChecklistWidget: some View {
        DailyChecklistCardView(
            date: Self.todayDateString(),
            signals: DailyChecklistCardView.SharedSignals(
                moodLoggedToday: todaysMood != nil,
                workoutLoggedToday: todaysWorkoutLog != nil,
                healthKitConnected: !appState.connectedProviders.isEmpty,
                hasReviewedFirstPlan: appState.currentRecommendation != nil
            ),
            style: .compact,
            onSeeAll: { showChecklistSheet = true },
            loadingDeepLink: checklistLoadingDeepLink,
            onDeepLink: handleChecklistDeepLink,
            onProgressChange: { done, total in
                checklistDone = done
                checklistTotal = total
            }
        )
        .id(checklistRefreshToken)
    }

    /// Sheet the greeting row's ring-pill opens -- same `dailyChecklistCard`
    /// content whether or not the inline widget is also toggled on.
    private var checklistSheet: some View {
        NavigationStack {
            ScrollView {
                dailyChecklistCard
                    .padding(20)
            }
            .somaSheetBackground()
            .navigationTitle(String(localized: "home.checklist.sheetTitle", defaultValue: "Today's checklist", comment: "Home: navigation title for the checklist sheet"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "home.checklist.doneButton", defaultValue: "Done", comment: "Home: button that dismisses the checklist sheet")) { showChecklistSheet = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Persists the "How Soma Works" tour's completion the exact same way
    /// every other onboarding checklist item is persisted --
    /// DailyChecklistCardView.toggleManual's own call, just invoked from
    /// here instead since this row is non-manual (tapping opens the tour,
    /// not an instant toggle). Only ever called from the tour's own
    /// final-card action (see the showHowSomaWorks sheet below) -- never
    /// from a plain swipe-to-dismiss, so backing out early never falsely
    /// credits having seen it.
    private func completeHowSomaWorksItem() async {
        try? await SupabaseClient.shared.upsertDailyChecklistState(
            scope: "onboarding", itemKey: "onboarding_how_soma_works", date: Self.todayDateString()
        )
        checklistRefreshToken += 1
    }

    private func handleChecklistDeepLink(_ deepLink: ChecklistDeepLink) {
        switch deepLink {
        case .logMeal:
            showNutrition = true
        case .healthDashboard:
            showHealthDashboard = true
        case .moodCheckIn:
            break // Already visible on Home itself -- nothing further to open.
        case .startWorkout:
            openTodaysWorkoutDetail()
        case .logWorkout:
            // Always the manual-logging form -- see ChecklistDeepLink's
            // own doc comment on why this is deliberately separate from
            // .startWorkout above.
            showLogManualWorkout = true
        case .howSomaWorks:
            showHowSomaWorks = true
        case .progressPicture:
            showGoalBodyProgress = true
        case .profileGoals, .profileKitchenEquipment, .connectDevices:
            // Profile owns all three editors (Training tab, kitchen
            // equipment row, device connections) -- one entry point,
            // same as tapping the gear icon, rather than plumbing a
            // second way into each individual sub-sheet.
            showProfile = true
        case .enableNotifications:
            Task { try? await NotificationManager.shared.requestAuthorization() }
        case .chooseWidgets:
            showEditWidgets = true
        }
    }

    /// The checklist ring-pill's 14pt indicator (also reused by the ring
    /// pill itself) -- a static trim-drawn ring, no animation.
    private struct ProgressRing: View {
        var fraction: Double
        var body: some View {
            ZStack {
                Circle().stroke(SomaTokens.accent.opacity(0.18), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: max(0.02, min(fraction, 1)))
                    .stroke(SomaTokens.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
    }

    // MARK: - Readiness card (guide 03: category + one line + disclosure + CTA)

    /// Today's logged-activity state relative to the category's own rough
    /// calorie target -- drives readinessCard's headline/subtitle/CTA below
    /// so the card actually reflects reality once something's logged,
    /// instead of forever pitching the same suggestion (item 2 fix). See
    /// DayLoadState's own doc comment.
    private func dayLoadState(for recommendation: DailyRecommendation) -> DayLoadState {
        DayLoadState.resolve(
            hasLoggedWorkout: todaysWorkoutLog != nil,
            loggedKcal: todaysWorkoutLog?.caloriesBurned,
            target: recommendation.category.dayLoadTargetKcal
        )
    }

    private func readinessCard(_ recommendation: DailyRecommendation) -> some View {
        let state = dayLoadState(for: recommendation)
        let isDone = state == .fulfilled || state == .overreached
        return VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(readinessHeadline(recommendation, state: state))
                        .font(SomaType.heroTitle)
                    // The only screen a day-1 user is guaranteed to see --
                    // without this, a zero-signal "moderate" reads exactly
                    // like a real one until they tap through to Detail.
                    if recommendation.reason == .insufficientData, state == .pending {
                        Text(String(localized: "home.readiness.buildingBaseline", defaultValue: "Building your baseline", comment: "Home: badge shown on the readiness card while there isn't enough data yet for a real reading"))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.orange.opacity(0.15)))
                    }
                    Text(readinessSubtitle(recommendation, state: state))
                        .font(.system(size: 14))
                        .foregroundStyle(SomaTokens.ink2)
                        .lineLimit(3)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    HStack(spacing: 6) {
                        readinessRefreshButton
                        Text(String(localized: "home.readiness.todayBadge", defaultValue: "TODAY", comment: "Home: small all-caps badge on the readiness card marking it as today's reading"))
                            .font(.system(size: 10.5, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(SomaTokens.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(SomaTokens.accentSoft))
                    }
                }
            }

            if let todaysWorkoutLog {
                loggedWorkoutRow(todaysWorkoutLog)
            }

            // Once today's activity is done, the pitch below (chips,
            // "why this?", the goal row) is about a session that no longer
            // applies -- de-emphasized out entirely rather than left
            // stale underneath the completed state.
            if !isDone {
                // 3a: always-visible flat-tinted metric chips (they carry
                // data, not affordance -- never `.glassLens()`/`.glassGel()`),
                // not hidden inside the disclosure. Duration always exists
                // (the category's own fixed suggestion pool, not
                // fabricated); health inputs only when a source actually
                // reported them.
                let chips = heroChips(for: recommendation)
                if chips.count > 1 {
                    // True equal-width columns (unlike an HStack + maxWidth:
                    // .infinity, which only splits LEFTOVER space -- each
                    // child still claims its own minimum content width
                    // first, so the longest chip, e.g. "Resting HR 61 bpm",
                    // won out and got truncated instead of shrinking evenly
                    // with the rest). Same flexible-GridItem recipe the
                    // Sleep widget's 2x2 grid already uses successfully,
                    // just N columns in one row.
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: chips.count), spacing: 8) {
                        ForEach(chips, id: \.self) { HomeMetricChip(text: $0) }
                    }
                } else if let onlyChip = chips.first {
                    HStack(spacing: 8) {
                        HomeMetricChip(text: onlyChip, fillsRow: false)
                    }
                }

                SomaDisclosure {
                    Text(recommendation.messageDetail ?? recommendation.reason.explanation(snapshots: todaysSnapshots))
                }

                if sportGoalWidgetEnabled, let activeSportGoal {
                    goalRow(activeSportGoal)
                }
            }

            Divider().overlay(SomaTokens.hairline)

            switch state {
            case .pending:
                // Same routing call as "Check workout details" below --
                // openTodaysWorkoutDetail() branches on todaysWorkoutLog
                // itself, so both buttons can share one implementation
                // instead of this one re-inlining the nil-case directly.
                SomaButton(title: LocalizedStringKey(String(localized: "home.readiness.startWorkoutButton", defaultValue: "Start workout", comment: "Home: readiness card primary CTA when nothing is logged yet")), size: .lg, variant: .primary) {
                    openTodaysWorkoutDetail()
                }
            case .partiallyDone:
                SomaButton(title: LocalizedStringKey(String(localized: "home.readiness.checkWorkoutDetailsButton", defaultValue: "Check workout details", comment: "Home: readiness card CTA once today's workout is already logged")), size: .lg, variant: .secondary) {
                    openTodaysWorkoutDetail()
                }
            case .fulfilled, .overreached:
                SomaButton(title: LocalizedStringKey(String(localized: "home.readiness.whatsNextButton", defaultValue: "What's next", comment: "Home: readiness card CTA once today's activity target is already met or exceeded")), size: .lg, variant: .secondary) {
                    openTodaysWorkoutDetail()
                }
            }

            switch state {
            case .pending, .partiallyDone:
                // Always available -- a user might do this INSTEAD of (or
                // in addition to) the AI plan. Free, no paywall: this is
                // basic tracking, same posture as manual meal logging.
                Button {
                    showLogManualWorkout = true
                } label: {
                    Text(String(localized: "home.readiness.logDifferentActivity", defaultValue: "Log a different activity", comment: "Home: readiness card link to log an activity outside the AI plan"))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(SomaTokens.accent)
                }
                .buttonStyle(.plain)
            case .fulfilled:
                // A link, deliberately not a second CTA -- today's target
                // is already met, so this is "if you really want to", not
                // something the card is pushing.
                Button {
                    showLogManualWorkout = true
                } label: {
                    Text(String(localized: "home.readiness.trainAnywayLink", defaultValue: "Train anyway", comment: "Home: readiness card low-emphasis link to log more activity once today's target is already met"))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(SomaTokens.ink3)
                }
                .buttonStyle(.plain)
            case .overreached:
                // No CTA suggesting more activity at all -- today's already
                // well past target.
                EmptyView()
            }

            if state == .pending {
                restDayRequestControl(recommendation)
            }
        }
        .padding(.init(top: 24, leading: 24, bottom: 20, trailing: 24))
        .background {
            let shape = RoundedRectangle(cornerRadius: 32, style: .continuous)
            if isDone {
                // Visually lower priority once today's done -- no
                // accent-tinted glow pulling the eye back to a pitch
                // that's already been acted on.
                shape.fill(SomaTokens.surface3)
            } else {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay(shape.fill(Color.white.opacity(0.4)))
                    .overlay(shape.strokeBorder(Color.white.opacity(0.75), lineWidth: 1))
                    .shadow(color: Color(red: 94 / 255, green: 130 / 255, blue: 220 / 255).opacity(0.12), radius: 20, x: 0, y: 16)
            }
        }
    }

    private func readinessHeadline(_ recommendation: DailyRecommendation, state: DayLoadState) -> String {
        switch state {
        case .pending, .partiallyDone:
            return recommendation.category.displayTitle
        case .fulfilled:
            return String(localized: "home.readiness.fulfilled.headline", defaultValue: "Done for today", comment: "Home: readiness card headline once today's logged activity has met the day's target")
        case .overreached:
            return String(localized: "home.readiness.overreached.headline", defaultValue: "Plenty today", comment: "Home: readiness card headline once today's logged activity is well past the day's target")
        }
    }

    private func readinessSubtitle(_ recommendation: DailyRecommendation, state: DayLoadState) -> String {
        switch state {
        case .pending:
            return recommendation.message
        case .partiallyDone:
            let logged = todaysWorkoutLog?.caloriesBurned ?? 0
            let target = recommendation.category.dayLoadTargetKcal
            return String(localized: "home.readiness.partiallyDone.subtitle", defaultValue: "You've logged \(logged) of \(target) kcal today. A light session would finish it off.", comment: "Home: readiness card subtitle once some, but not enough, of today's activity target is logged; both numbers are kcal")
        case .fulfilled:
            if let calories = todaysWorkoutLog?.caloriesBurned, calories > 0 {
                return String(localized: "home.readiness.fulfilled.subtitleWithCalories", defaultValue: "\(calories) kcal logged. Daily target met.", comment: "Home: readiness card subtitle once today's activity target is met, with a real calorie number")
            }
            return String(localized: "home.readiness.fulfilled.subtitle", defaultValue: "Today's activity is logged. Daily target met.", comment: "Home: readiness card subtitle once today's activity target is met, no calorie number available")
        case .overreached:
            return String(localized: "home.readiness.overreached.subtitle", defaultValue: "Today's already a lot. Tomorrow will be easier.", comment: "Home: readiness card subtitle once today's logged activity is well past the day's target")
        }
    }

    /// Always-visible manual refresh, independent of needsDataCard (which
    /// disappears the instant ANY recommendation exists, even a stale/thin
    /// one from a pre-sleep open -- see checkNow()'s doc comment on why
    /// that matters). Same checkNow() path as pull-to-refresh, just
    /// reachable without needing to pull, and reachable at all once
    /// today's card already has content. isLoading is shared with the
    /// rest of Home's refresh affordances, so this spins in lockstep with
    /// pull-to-refresh/"Check now" if either is triggered instead.
    private var readinessRefreshButton: some View {
        Button {
            Task { await checkNow() }
        } label: {
            Group {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.65)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .foregroundStyle(SomaTokens.accent)
            .frame(width: 26, height: 26)
            .background(Circle().fill(SomaTokens.accentSoft))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .animation(.easeInOut(duration: 0.2), value: isLoading)
        .accessibilityLabel(String(localized: "home.readiness.refreshAccessibilityLabel", defaultValue: "Refresh today's readiness", comment: "Home: accessibility label for the readiness card's manual refresh button"))
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
                        // Two full sentences rather than an interpolated
                        // "rest"/"active recovery" fragment -- that word sat
                        // inside an otherwise-localized string and would have
                        // shipped in English inside every translation.
                        Text(requested == .rest
                            ? String(localized: "home.restDay.requestedRest", defaultValue: "You requested a rest day today — Undo", comment: "Home: shown after the user asks for a rest day instead of today's plan; tapping undoes the request")
                            : String(localized: "home.restDay.requestedActiveRecovery", defaultValue: "You requested an active recovery day today — Undo", comment: "Home: shown after the user asks for an active recovery day instead of today's plan; tapping undoes the request"))
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
                    Text(String(localized: "home.restDay.prompt", defaultValue: "Not feeling it today?", comment: "Home: link that opens the rest-day/active-recovery request options"))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(SomaTokens.accent)
                }
                .buttonStyle(.plain)
                .disabled(isSettingRestDayRequest)
                .confirmationDialog(String(localized: "home.restDay.dialogTitle", defaultValue: "Request a different day", comment: "Home: title of the confirmation dialog for requesting a rest or active-recovery day"), isPresented: $showRestDayOptions, titleVisibility: .visible) {
                    Button(String(localized: "home.restDay.restDayOption", defaultValue: "Rest day", comment: "Home: rest-day request dialog option")) { Task { await setRestDayRequest(.rest) } }
                    Button(String(localized: "home.restDay.activeRecoveryOption", defaultValue: "Active recovery", comment: "Home: rest-day request dialog option")) { Task { await setRestDayRequest(.light) } }
                    Button(String(localized: "home.restDay.cancelOption", defaultValue: "Cancel", comment: "Home: rest-day request dialog cancel option"), role: .cancel) {}
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
            return String(localized: "home.goalRow.customWeek", defaultValue: "\(name) · week \(min(week, weeks)) of \(weeks)", comment: "Home: goal row summary for a custom-length goal -- goal name, then current week of total weeks")
        }
        if let weekLine = goal.weekLine {
            return String(localized: "home.goalRow.weekLine", defaultValue: "\(name) · \(weekLine)", comment: "Home: goal row summary -- goal name, then a status/week line supplied by the goal")
        }
        return name
    }

    /// The real inputs behind today's read -- only what a source actually
    /// reported, never fabricated (guide 09's Home disclosure row).
    private var readinessInputs: [String] {
        var parts: [String] = []
        if let sleep = todaysSnapshots.compactMap(\.sleepHours).first {
            let hours = String(format: "%.1f", sleep)
            parts.append(String(localized: "home.readiness.sleep", defaultValue: "Sleep \(hours) h", comment: "Home: readiness disclosure input chip -- hours of sleep"))
        }
        if let hrv = todaysSnapshots.compactMap(\.hrvMs).first {
            parts.append(String(localized: "home.readiness.hrv", defaultValue: "HRV \(Int(hrv.rounded())) ms", comment: "Home: readiness disclosure input chip -- heart rate variability in milliseconds"))
        }
        if let rhr = todaysSnapshots.compactMap(\.restingHr).first {
            // Abbreviated ("RHR", not "Resting HR") to match "HRV"'s own
            // compactness -- this chip sits in a hard equal-width 4-column
            // row (readinessCard) with no room for the spelled-out form.
            parts.append(String(localized: "home.readiness.restingHR", defaultValue: "RHR \(Int(rhr.rounded())) bpm", comment: "Home: readiness disclosure input chip -- resting heart rate in beats per minute, abbreviated to match this row's tight equal-width chip layout"))
        }
        return parts
    }

    /// Duration first (always exists -- the category's own fixed
    /// suggestion pool, same "real but not personalized" rule as
    /// `stepTarget`, not the AI-generated plan), then real readinessInputs.
    private func heroChips(for recommendation: DailyRecommendation) -> [String] {
        var chips: [String] = []
        if let duration = recommendation.category.workoutSuggestions.first?.targetDurationMinutes {
            chips.append(Self.durationChipText(duration))
        }
        chips.append(contentsOf: readinessInputs)
        return chips
    }

    private static func durationChipText(_ range: ClosedRange<Int>) -> String {
        if range.lowerBound == range.upperBound {
            return String(localized: "home.chip.duration", defaultValue: "\(range.lowerBound) min", comment: "Home: hero chip showing today's suggested workout duration, e.g. '40 min'")
        }
        return String(localized: "home.chip.durationRange", defaultValue: "\(range.lowerBound)–\(range.upperBound) min", comment: "Home: hero chip showing today's suggested workout duration as a range, e.g. '20–30 min'")
    }

    // MARK: - Scan row (guide 03: three states, never greyed-out-and-inert)

    private enum ScanState { case available, locked, hidden }

    /// Why a tap on the dock's always-visible "Scan gym" icon didn't open
    /// the scan flow -- surfaced via `.alert` so the icon never just sits
    /// there doing nothing (see `performScanGymAction`).
    private enum ScanUnavailableReason { case workoutSet, quotaSpent }

    private var scanUnavailableAlertTitle: String {
        switch scanUnavailableReason {
        case .quotaSpent:
            String(localized: "home.scanGym.unavailable.quotaSpent.title", defaultValue: "Today's scans used up", comment: "Alert title shown when tapping Scan gym after today's generation quota is spent")
        case .workoutSet, nil:
            String(localized: "home.scanGym.unavailable.workoutSet.title", defaultValue: "Today's workout is set", comment: "Alert title shown when tapping Scan gym after today's workout is already logged or planned")
        }
    }

    private var scanUnavailableAlertMessage: String {
        switch scanUnavailableReason {
        case .quotaSpent:
            String(localized: "home.scanGym.unavailable.quotaSpent.message", defaultValue: "You've used today's gym scans. More opens up tomorrow.", comment: "Alert message shown when tapping Scan gym after today's generation quota is spent")
        case .workoutSet, nil:
            String(localized: "home.scanGym.unavailable.workoutSet.message", defaultValue: "You've already logged or added today's workout, so there's nothing to scan for right now.", comment: "Alert message shown when tapping Scan gym after today's workout is already logged or planned")
        }
    }

    /// Mirrors the server's tiered PER-SOURCE quota (generationLimits.ts):
    /// 3/day on annual, 1/day otherwise, counted for gym_photo alone --
    /// an explicit product decision there.
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

    /// Real feedback: "some human-level metric that the app optimizes ...
    /// showing that the metric improves with app usage." Once answered,
    /// collapses to a compact confirmation rather than staying an
    /// always-visible 5-button row -- it's a one-tap daily habit, not a
    /// permanent fixture competing with the actual workout content.
    /// Same tile shell/eyebrow language as `waterWidgetTile`/`sleepWidgetTile`
    /// (9a's own "chips match the water/sleep family" note) -- was a bare
    /// `CardView` row before, the one widget that didn't match the others.
    private var moodCheckInRow: some View {
        homeWidgetTileFrame {
        VStack(alignment: .leading, spacing: 3) {
            if let todaysMood, let rating = MoodRating(rawValue: todaysMood.rating) {
                HStack(spacing: 6) {
                    Image(systemName: "face.smiling")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SomaTokens.accent)
                    Text(String(localized: "home.widget.mood.eyebrow", defaultValue: "Mood", comment: "Home: mood widget tile eyebrow label"))
                        .font(.system(size: 10.5, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(SomaTokens.ink4)
                    Spacer(minLength: 0)
                    MoodFaceIcon(rating: rating, color: .white, lineWidth: 1.4)
                        .frame(width: 18, height: 18)
                        .frame(width: 27, height: 27)
                        .glassGel(.blue, cornerRadius: 13.5)
                }
                Text(rating.displayName)
                    .font(Theme.display)
                    .fontWidth(.condensed)
                    .padding(.top, 3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(String(localized: "home.moodCheckIn.loggedAt", defaultValue: "\(Self.moodLoggedTimeText(todaysMood.loggedAt)) · tap to change", comment: "Home: mood widget caption once logged today, e.g. '9:02 AM · tap to change'"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(SomaTokens.ink5)
                    .padding(.top, 2)
                    .lineLimit(2)
                    .onTapGesture { self.todaysMood = nil }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "face.smiling")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SomaTokens.accent)
                    Text(String(localized: "home.widget.mood.eyebrow", defaultValue: "Mood", comment: "Home: mood widget tile eyebrow label"))
                        .font(.system(size: 10.5, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(SomaTokens.ink4)
                }
                .padding(.bottom, 6)
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "home.moodCheckIn.prompt", defaultValue: "How are you feeling today?", comment: "Home: mood check-in prompt shown before the user has logged today's mood"))
                        .font(.system(size: 12.5, weight: .semibold))
                    HStack(spacing: 4) {
                        ForEach(MoodRating.allCases) { rating in
                            Button {
                                Task { await logMood(rating) }
                            } label: {
                                MoodFaceIcon(rating: rating)
                                    .frame(width: 20, height: 20)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(rating.displayName))
                        }
                    }
                    if let moodError {
                        Text(moodError)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.red)
                    }
                }
                .disabled(isSavingMood)
            }
        }
        }
    }

    /// Ported from the Turn 9 handoff's mood SVGs -- stroke circle + two eye
    /// dots + a mouth curve that varies by rating -- replacing the emoji
    /// glyphs the build shipped with (design note: "Faces are stroke icons,
    /// no emoji").
    private struct MoodFaceIcon: View {
        let rating: MoodRating
        var color: Color = SomaTokens.accent
        var lineWidth: CGFloat = 1.6

        var body: some View {
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let eyeSize = lineWidth * 1.6
                ZStack {
                    Circle().stroke(color, lineWidth: lineWidth)
                    Circle().fill(color).frame(width: eyeSize, height: eyeSize)
                        .position(x: 9.0 / 24 * w, y: 9.5 / 24 * h)
                    Circle().fill(color).frame(width: eyeSize, height: eyeSize)
                        .position(x: 15.0 / 24 * w, y: 9.5 / 24 * h)
                    MoodMouthShape(rating: rating)
                        .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                }
            }
            .aspectRatio(1, contentMode: .fit)
        }
    }

    /// Mouth path coordinates lifted 1:1 from the handoff's 24x24 viewBox
    /// SVGs (one cubic curve per rating, `okay` is a straight line).
    private struct MoodMouthShape: Shape {
        let rating: MoodRating

        func path(in rect: CGRect) -> Path {
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: rect.minX + x / 24 * rect.width, y: rect.minY + y / 24 * rect.height)
            }
            var path = Path()
            switch rating {
            case .rough:
                path.move(to: point(9, 16))
                path.addCurve(to: point(15, 16), control1: point(10.2, 14.4), control2: point(13.8, 14.4))
            case .notGreat:
                path.move(to: point(9, 15.3))
                path.addCurve(to: point(15, 15.3), control1: point(10.5, 14.4), control2: point(13.5, 14.4))
            case .okay:
                path.move(to: point(9.5, 15))
                path.addLine(to: point(14.5, 15))
            case .good:
                path.move(to: point(9, 14.5))
                path.addCurve(to: point(15, 14.5), control1: point(10.5, 15.9), control2: point(13.5, 15.9))
            case .great:
                path.move(to: point(8.8, 13.8))
                path.addCurve(to: point(15.2, 13.8), control1: point(10.4, 15.9), control2: point(13.6, 15.9))
            }
            return path
        }
    }

    /// Trial-time upgrade highlight (TestFlight feedback: during a free
    /// trial the app should surface "Upgrade now" in-app, not only at the
    /// paywall) -- routes to the same view_premium placement Profile uses.
    private var trialUpgradeBanner: some View {
        Button {
            AnalyticsManager.shared.featureUsed(name: "trial_upgrade_banner")
            // Same entitled-user routing as the status-row chip.
            SuperwallDiagnostics.registerTrialUpgrade { showManageSubscriptions = true }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SomaTokens.accent)
                Text(String(localized: "home.trialUpgradeBanner.title", defaultValue: "You're on a free trial", comment: "Home: trial upgrade banner title"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(SomaTokens.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                Text(String(localized: "home.trialUpgradeBanner.cta", defaultValue: "Upgrade now", comment: "Home: trial upgrade banner call to action"))
                    .font(.footnote.bold())
                    .foregroundStyle(SomaTokens.accent)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(SomaTokens.accent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .glassCardFlat(cornerRadius: SomaTokens.rPill)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.trialUpgradeBanner")
    }

    /// The dock's "Scan gym" action (3a) -- same three-state decision
    /// `scanRow` used to render inline, now a tap consequence instead of a
    /// row: the dock icon itself is always present (it's a stable nav
    /// anchor like Log workout), quota-locked taps route to the same
    /// paywall/quota messaging as before instead of disappearing.
    private func performScanGymAction() {
        switch scanState {
        case .available:
            requestDetailAccess {
                AnalyticsManager.shared.featureUsed(name: "gym_photo_workout")
                showGymPhotoFlow = true
            }
        case .hidden:
            // A committed or completed workout already removed this row's
            // affordance -- the dock icon staying tappable must not still
            // open a second scan for a day that's already spoken for. Says
            // so via alert rather than a silent no-op (which read as the
            // button randomly "not working").
            scanUnavailableReason = .workoutSet
        case .locked:
            if SubscriptionManager.shared.tier != "annual" {
                let handler = SuperwallDiagnostics.handler(placement: "view_premium")
                handler.onDismiss { _, result in
                    WinBackOfferManager.maybePresentAfterDecline(result: result)
                }
                Superwall.shared.register(placement: "view_premium", handler: handler)
            } else {
                // Annual tier, quota spent for today: no paywall to show,
                // but still owes the tap an explanation rather than silence.
                scanUnavailableReason = .quotaSpent
            }
        }
    }

    /// Opens the sport goal flow directly -- the feature is opt-in now, so
    /// the dock's "Goals" icon goes straight to sport selection instead of
    /// forcing the first-time onboarding gallery in front of it.
    private func openSportGoal() {
        showSportGoalScreen = true
    }

    // MARK: - Widget grid (3a) -- Water + Sleep, the two small metric tiles

    /// 2 flexible columns, not a raw HStack -- an HStack only splits evenly
    /// when every child's ideal content width happens to be comparable
    /// (true for water+sleep, not once mood's longer prompt text joined
    /// them: it silently claimed most of the row). Grid columns reserve
    /// equal width per cell regardless of content, and a trailing lone
    /// tile (only one of the three enabled) still occupies just its own
    /// column instead of stretching to the full row.
    private static let widgetGridColumns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible())]

    @ViewBuilder
    private var widgetGrid: some View {
        if waterWidgetEnabled || sleepWidgetEnabled || streakWidgetEnabled || moodWidgetEnabled || affirmationWidgetEnabled {
            LazyVGrid(columns: Self.widgetGridColumns, alignment: .leading, spacing: 14) {
                if waterWidgetEnabled {
                    waterWidgetTile
                }
                if sleepWidgetEnabled {
                    sleepWidgetTile
                }
                if streakWidgetEnabled {
                    streakWidgetTile
                }
                if moodWidgetEnabled {
                    moodCheckInRow
                }
                if affirmationWidgetEnabled {
                    affirmationWidgetTile
                }
            }
        }
        // Full-width row, not a grid cell (TestFlight feedback: "Nutrition
        // feature needs to be bigger") -- the extra width also fits the
        // per-macro breakdown a half-tile never could.
        if nutritionWidgetEnabled {
            nutritionWidgetTile
        }
    }

    /// Same source as Profile's streakSection (SupabaseClient.fetchRecentWorkoutLogDates,
    /// already fetched here for the calendar strip's crown badges) -- reuses
    /// ProfileStore's pure streak-counting function instead of duplicating it.
    private var currentStreak: Int { ProfileStore.streak(from: completedDates) }

    private var streakWidgetTile: some View {
        // Tappable (real feedback: "Streak not clickable -- needs to be,
        // and needs 'sharable feature'") -- opens the same share card
        // Profile's streak section already offers, one implementation.
        Button {
            showStreakShare = true
        } label: {
            streakWidgetTileContent
        }
        .buttonStyle(.plain)
        .accessibilityHint(String(localized: "home.widget.streak.shareHint", defaultValue: "Opens a shareable streak card", comment: "Home: VoiceOver hint on the streak widget tile"))
        .sheet(isPresented: $showStreakShare) {
            ProfileView.StreakShareSheet(
                streakDays: currentStreak,
                category: appState.currentRecommendation?.category,
                steps: nil
            )
        }
    }

    private var streakWidgetTileContent: some View {
        homeWidgetTileFrame {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(currentStreak > 0 ? SomaTokens.accent : SomaTokens.ink4)
                    Text(String(localized: "home.widget.streak.eyebrow", defaultValue: "Streak", comment: "Home: streak widget tile eyebrow label"))
                        .font(.system(size: 10.5, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(SomaTokens.ink4)
                    Spacer(minLength: 0)
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(SomaTokens.accent)
                }
                // Item 5 fix: a short token ("2 days"), not a full sentence
                // ("2-day streak") -- the value slot uses the same large
                // display font every other tile's value does, and a
                // sentence-length string there truncated ("2-day stre…").
                // The full phrase already lives in the subtitle below.
                Text(currentStreak > 0
                    ? String(localized: "home.widget.streak.valueShort", defaultValue: "\(currentStreak) days", comment: "Short streak-length value, e.g. '2 days' -- pluralized by count")
                    : String(localized: "home.widget.streak.inactiveHeadline", defaultValue: "No active streak", comment: "Streak widget headline when there is no current streak"))
                    .font(currentStreak > 0 ? Theme.display : .system(size: 14.5, weight: .semibold))
                    .fontWidth(currentStreak > 0 ? .condensed : nil)
                    .padding(.top, 3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(currentStreak > 0
                    ? String(localized: "home.widget.streak.activeSubtitle", defaultValue: "Keep showing up -- consistency compounds.", comment: "Streak widget subtitle when a streak is active")
                    : String(localized: "home.widget.streak.inactiveSubtitle", defaultValue: "Log a workout today to start one.", comment: "Streak widget subtitle when there is no current streak"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(SomaTokens.ink5)
                    .padding(.top, 2)
                    .lineLimit(2)
            }
        }
    }

    /// Affirmation widget (16a, Turn 16) -- 14a's one-anatomy rule:
    /// eyebrow -> hero (the line itself, up to 3 rows) -> support ->
    /// pinned actions. The line is today's server-cached generation;
    /// refresh is the day's one manual regeneration, pencil jumps into
    /// the sheet's edit-in-place, "List" opens the sheet (16b).
    private var affirmationWidgetTile: some View {
        homeWidgetTileFrame {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(todaysAffirmation == nil ? SomaTokens.ink4 : SomaTokens.accent)
                    Text(String(localized: "home.widget.affirmation.eyebrow", defaultValue: "Affirmation", comment: "Home: affirmation widget tile eyebrow label"))
                        .font(.system(size: 10.5, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(SomaTokens.ink4)
                    Spacer(minLength: 0)
                }
                if let line = todaysAffirmation?.text {
                    Text(line)
                        .font(SomaType.widgetQuote)
                        .foregroundStyle(SomaTokens.ink)
                        .padding(.top, 3)
                        .lineLimit(3)
                        .minimumScaleFactor(0.8)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(String(localized: "home.widget.affirmation.placeholder", defaultValue: "Your line for today is on its way.", comment: "Home: affirmation widget placeholder while today's line loads or hasn't generated yet"))
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(SomaTokens.ink3)
                        .padding(.top, 3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(String(localized: "home.widget.affirmation.support", defaultValue: "New each morning", comment: "Home: affirmation widget support caption"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(SomaTokens.ink5)
                    .padding(.top, 2)
                Spacer(minLength: 6)
                HStack(spacing: 6) {
                    Button {
                        affirmationSheetStartsEditing = true
                        showAffirmations = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(SomaTokens.accent)
                            .frame(width: 27, height: 27)
                            .glassLens()
                    }
                    .buttonStyle(.plain)
                    .disabled(todaysAffirmation == nil)
                    .opacity(todaysAffirmation == nil ? 0.35 : 1)
                    .accessibilityLabel(Text(String(localized: "home.widget.affirmation.editAccessibility", defaultValue: "Edit today's affirmation", comment: "Home: VoiceOver label for the affirmation widget's pencil button")))

                    Button {
                        Task { await regenerateAffirmationInline() }
                    } label: {
                        Group {
                            if isRegeneratingAffirmation {
                                ProgressView()
                                    .scaleEffect(0.6)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(SomaTokens.accent)
                            }
                        }
                        .frame(width: 27, height: 27)
                        .glassLens()
                    }
                    .buttonStyle(.plain)
                    .disabled(isRegeneratingAffirmation || todaysAffirmation?.regenerationAvailable == false)
                    .opacity(todaysAffirmation?.regenerationAvailable == false ? 0.35 : 1)
                    .accessibilityLabel(Text(String(localized: "home.widget.affirmation.refreshAccessibility", defaultValue: "Get a new line", comment: "Home: VoiceOver label for the affirmation widget's refresh button")))

                    Spacer(minLength: 0)

                    Button {
                        affirmationSheetStartsEditing = false
                        showAffirmations = true
                    } label: {
                        HStack(spacing: 3) {
                            Text(String(localized: "home.widget.affirmation.listLabel", defaultValue: "List", comment: "Home: affirmation widget label opening the full affirmations sheet"))
                                .font(.system(size: 11, weight: .bold))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundStyle(SomaTokens.accent)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text(String(localized: "home.widget.affirmation.openHint", defaultValue: "Opens your affirmations", comment: "Home: VoiceOver hint on the affirmation widget's List button")))
                }
            }
        }
    }

    private func loadTodaysAffirmation() async {
        guard affirmationWidgetEnabled else { return }
        let date = Self.todayDateString()
        if let cached = try? await SupabaseClient.shared.fetchTodaysAffirmation(date: date) {
            todaysAffirmation = cached
            return
        }
        // Fresh morning before the background pass ran (or first use) --
        // generate now; the server caches per (user, date), so this stays
        // one generation a day no matter how often Home appears.
        todaysAffirmation = try? await SupabaseClient.shared.fetchOrGenerateDailyAffirmation(date: date)
    }

    private func regenerateAffirmationInline() async {
        guard !isRegeneratingAffirmation else { return }
        isRegeneratingAffirmation = true
        defer { isRegeneratingAffirmation = false }
        do {
            todaysAffirmation = try await SupabaseClient.shared.fetchOrGenerateDailyAffirmation(date: Self.todayDateString(), forceRegenerate: true)
        } catch let error as SupabaseError {
            // Quota spent -- keep today's line, just disable the refresh
            // affordance (the sheet's footer is where the "why" lives).
            if case .generationLimitReached = error, let current = todaysAffirmation {
                todaysAffirmation = DailyAffirmation(text: current.text, generatedAt: current.generatedAt, regenerationAvailable: false)
            }
        } catch {
            // Offline/transient -- today's line stays; nothing to show here.
        }
    }

    /// Nutrition widget (mockup 3e "NUTRITION · 1 240 / of 1 900 kcal" +
    /// 14a's one-anatomy rule: eyebrow -> hero value -> supporting visual
    /// -> bottom action). Data is the same `nutritionProgress` /
    /// `nutritionTarget` pair Home already loads for the dock entry --
    /// this tile renders it instead of leaving it invisible. No target
    /// computed yet -> an honest set-up state, never fabricated numbers.
    private var nutritionWidgetTile: some View {
        Button {
            showNutrition = true
        } label: {
            homeWidgetTileFrame {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Image(systemName: "fork.knife")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(SomaTokens.accent)
                        Text(String(localized: "home.widget.nutrition.eyebrow", defaultValue: "Nutrition", comment: "Home: nutrition widget tile eyebrow label"))
                            .font(.system(size: 10.5, weight: .bold))
                            .tracking(0.6)
                            .foregroundStyle(SomaTokens.ink4)
                        Spacer(minLength: 0)
                    }
                    if let progress = nutritionProgress {
                        Text(progress.consumedCalories.formatted())
                            .font(Theme.display)
                            .fontWidth(.condensed)
                            .padding(.top, 3)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(String(localized: "home.widget.nutrition.ofTarget", defaultValue: "of \(progress.targetCalories.formatted()) kcal", comment: "Home: nutrition widget caption under the consumed-calories value; placeholder is the daily calorie target"))
                            .font(.system(size: 11.5))
                            .foregroundStyle(SomaTokens.ink5)
                            .lineLimit(1)
                        Capsule()
                            .fill(SomaTokens.accentSoft14)
                            .frame(height: 4)
                            .overlay(alignment: .leading) {
                                GeometryReader { geo in
                                    Capsule()
                                        .fill(SomaTokens.accent)
                                        .frame(width: geo.size.width * min(1, Double(progress.consumedCalories) / Double(max(1, progress.targetCalories))))
                                }
                            }
                            .padding(.top, 6)
                            .accessibilityHidden(true)
                        HStack(spacing: 12) {
                            nutritionMacroCell(title: String(localized: "home.widget.nutrition.protein", defaultValue: "Protein", comment: "Home: nutrition widget macro column title"), consumed: progress.consumedProteinG, target: progress.targetProteinG)
                            nutritionMacroCell(title: String(localized: "home.widget.nutrition.carbs", defaultValue: "Carbs", comment: "Home: nutrition widget macro column title"), consumed: progress.consumedCarbsG, target: progress.targetCarbsG)
                            nutritionMacroCell(title: String(localized: "home.widget.nutrition.fat", defaultValue: "Fat", comment: "Home: nutrition widget macro column title"), consumed: progress.consumedFatG, target: progress.targetFatG)
                        }
                        .padding(.top, 8)
                    } else {
                        Text(String(localized: "home.widget.nutrition.noTargetHeadline", defaultValue: "No target yet", comment: "Home: nutrition widget headline before a calorie target has been computed"))
                            .font(.system(size: 14.5, weight: .semibold))
                            .padding(.top, 3)
                            .lineLimit(1)
                        Text(String(localized: "home.widget.nutrition.noTargetSubtitle", defaultValue: "Log meals to build today's picture.", comment: "Home: nutrition widget subtitle before a calorie target has been computed"))
                            .font(.system(size: 11.5))
                            .foregroundStyle(SomaTokens.ink5)
                            .padding(.top, 2)
                            .lineLimit(2)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(String(localized: "home.widget.nutrition.hint", defaultValue: "Opens nutrition", comment: "Home: VoiceOver hint on the nutrition widget tile"))
    }

    private func nutritionMacroCell(title: String, consumed: Int, target: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(SomaTokens.ink4)
                .lineLimit(1)
            Text(String(localized: "home.widget.nutrition.macroValue", defaultValue: "\(consumed) / \(target) g", comment: "Home: nutrition widget macro cell value, consumed vs target grams"))
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(SomaTokens.inkParagraph)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var waterGoalReached: Bool { waterGlassesToday >= 8 }

    private var waterWidgetTile: some View {
        homeWidgetTileFrame {
            // Item 5: same header->value rhythm as every other tile
            // (spacing 3 + value .padding(.top, 3)), so the value line
            // sits on one shared baseline across the whole grid.
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(waterGoalReached ? SomaTokens.success : SomaTokens.accent)
                    Text(String(localized: "home.widget.water.eyebrow", defaultValue: "Water", comment: "Home: water widget tile eyebrow label"))
                        .font(.system(size: 10.5, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(SomaTokens.ink4)
                    Spacer(minLength: 0)
                    if waterGoalReached {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(SomaTokens.success)
                    }
                }
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text("\(waterGlassesToday)")
                        .font(Theme.display)
                        .fontWidth(.condensed)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(String(localized: "home.widget.water.goalSuffix", defaultValue: "/ 8", comment: "Home: water widget fragment shown after the glass count, denoting the daily goal of 8 glasses"))
                        .font(.system(size: 13))
                        .foregroundStyle(SomaTokens.ink4)
                }
                .padding(.top, 3)
                waterDropletRow
                waterControlRow
                    .padding(.top, 6)
            }
        }
    }

    /// 8 droplets as a progress indicator -- "tap a drop to set the exact
    /// count" (9b), so each one is also a direct-set control, not just a
    /// readout of the "+"/"-" buttons below.
    private var waterDropletRow: some View {
        HStack(spacing: 4) {
            ForEach(1...8, id: \.self) { index in
                Button {
                    waterGlassesToday = index
                    UserDefaults.standard.set(waterGlassesToday, forKey: Self.waterStorageKey())
                } label: {
                    Image(systemName: index <= waterGlassesToday ? "drop.fill" : "drop")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(
                            waterGoalReached
                                ? SomaTokens.success
                                : SomaTokens.accent.opacity(index <= waterGlassesToday ? 1 : 0.3)
                        )
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(String(localized: "home.widget.water.accessibilityCount", defaultValue: "\(waterGlassesToday) of 8 glasses", comment: "Home: VoiceOver summary of the water droplet row")))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: waterGlassesToday = min(waterGlassesToday + 1, 8)
            case .decrement: waterGlassesToday = max(waterGlassesToday - 1, 0)
            @unknown default: break
            }
            UserDefaults.standard.set(waterGlassesToday, forKey: Self.waterStorageKey())
        }
    }

    /// "-" / glass-size chip / "+" -- the chip swaps for a "Goal hit" label
    /// once today's 8 glasses are logged (9b).
    private var waterControlRow: some View {
        HStack(spacing: 8) {
            Button {
                waterGlassesToday = max(waterGlassesToday - 1, 0)
                UserDefaults.standard.set(waterGlassesToday, forKey: Self.waterStorageKey())
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(SomaTokens.accent)
                    .frame(width: 27, height: 27)
                    .glassLens()
            }
            .buttonStyle(.plain)
            .disabled(waterGlassesToday == 0)
            .opacity(waterGlassesToday == 0 ? 0.35 : 1)
            .accessibilityLabel(Text(String(localized: "home.widget.water.removeGlassAccessibility", defaultValue: "Remove a glass of water", comment: "Home: VoiceOver label for the water widget's minus button")))

            Spacer(minLength: 0)

            if waterGoalReached {
                Text(String(localized: "home.widget.water.goalHit", defaultValue: "Goal hit", comment: "Home: water widget label once today's 8-glass goal is reached"))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(SomaTokens.success)
            } else {
                Button {
                    cycleWaterGlassSize()
                } label: {
                    Text(String(localized: "home.widget.water.glassSizeChip", defaultValue: "\(waterGlassSizeML) ml", comment: "Home: water widget chip showing the current glass size, e.g. '250 ml'"))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(SomaTokens.accent)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(SomaTokens.accentSoft10))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(String(localized: "home.widget.water.glassSizeAccessibility", defaultValue: "Glass size, \(waterGlassSizeML) milliliters. Double tap to change.", comment: "Home: VoiceOver label for the water widget's glass-size chip")))
            }

            Spacer(minLength: 0)

            Button {
                waterGlassesToday = min(waterGlassesToday + 1, 99)
                UserDefaults.standard.set(waterGlassesToday, forKey: Self.waterStorageKey())
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(SomaTokens.accent)
                    .frame(width: 27, height: 27)
                    .glassLens()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(String(localized: "home.widget.water.addGlassAccessibility", defaultValue: "Add a glass of water", comment: "Home: VoiceOver label for the water widget's plus button")))
        }
    }

    @ViewBuilder
    private func sleepEyebrow<Trailing: View>(@ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "moon.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SomaTokens.accent)
            Text(String(localized: "home.widget.sleep.eyebrow", defaultValue: "Sleep", comment: "Home: sleep widget tile eyebrow label"))
                .font(.system(size: 10.5, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(SomaTokens.ink4)
            Spacer(minLength: 0)
            trailing()
        }
    }

    private var sleepEyebrowPlain: some View {
        sleepEyebrow { EmptyView() }
    }

    /// Three states (9g): a wearable-sourced `todaysSnapshots` row always
    /// wins over a manual log for the same day ("wearable connected ->
    /// chips never show"); a manual log wins over the empty prompt; no data
    /// at all shows the four one-tap duration chips, same pattern as
    /// `moodCheckInRow`'s face row -- no sheet.
    private var sleepWidgetTile: some View {
        let snapshot = todaysSnapshots.first(where: { $0.sleepHours != nil })
        return homeWidgetTileFrame {
        VStack(alignment: .leading, spacing: 3) {
            if let snapshot, let hours = snapshot.sleepHours {
                sleepEyebrow { sleepSourceBadge(snapshot.source) }
                Text(String(format: "%.1f \(HealthMetricFamily.sleep.unit)", hours))
                    .font(Theme.display)
                    .fontWidth(.condensed)
                    .padding(.top, 3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let bar = SleepPhaseSegments(snapshot: snapshot) {
                    bar.padding(.top, 3)
                    Text(bar.captionText)
                        .font(.system(size: 11.5))
                        .foregroundStyle(SomaTokens.ink5)
                        .padding(.top, 2)
                        .lineLimit(2)
                }
            } else if !isEditingSleep, let todaysSleepLog, let bucket = SleepDurationBucket(rawValue: todaysSleepLog.bucket) {
                sleepEyebrow {
                    Text(bucket.chipLabel)
                        .font(.system(size: 10.5, weight: .bold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .glassGel(.blue, cornerRadius: 999)
                }
                Text(bucket.verdict)
                    .font(Theme.display)
                    .fontWidth(.condensed)
                    .padding(.top, 3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityIdentifier("sleep-widget-logged-verdict")
                Text(String(localized: "home.sleepCheckIn.loggedAt", defaultValue: "\(Self.sleepLoggedTimeText(todaysSleepLog.loggedAt)) · tap to change", comment: "Home: sleep widget caption once logged today, e.g. '8:12 AM · tap to change'"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(SomaTokens.ink5)
                    .padding(.top, 2)
                    .lineLimit(2)
                    .onTapGesture { self.isEditingSleep = true }
            } else {
                sleepEyebrowPlain
                    .padding(.bottom, 6)
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "home.sleepCheckIn.prompt", defaultValue: "How long last night?", comment: "Home: sleep check-in prompt shown before the user has logged today's sleep"))
                        .font(.system(size: 12.5, weight: .semibold))
                    // 2x2, not a single 4-wide row -- the tile only gets
                    // half the widget grid's ~390pt width (shared with
                    // water), leaving ~140pt of content width. Four chips
                    // in one row truncated to "<...", "..." at that width;
                    // two per row gives each chip roughly its full label's
                    // worth of room.
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 4), GridItem(.flexible())], spacing: 4) {
                        ForEach(SleepDurationBucket.allCases) { bucket in
                            Button {
                                Task { await logSleep(bucket) }
                            } label: {
                                Text(bucket.chipLabel)
                                    .font(.system(size: 11.5, weight: .bold))
                                    .foregroundStyle(SomaTokens.accent)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .frame(maxWidth: .infinity)
                                    .glassLens(cornerRadius: 999)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier(Self.sleepChipAccessibilityID(bucket))
                        }
                    }
                    if let sleepError {
                        Text(sleepError)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.red)
                    }
                }
                .disabled(isSavingSleep)
            }
        }
        }
    }

    private static func sleepChipAccessibilityID(_ bucket: SleepDurationBucket) -> String {
        switch bucket {
        case .underSix: "sleep-chip-under6"
        case .sixSeven: "sleep-chip-6-7"
        case .sevenEight: "sleep-chip-7-8"
        case .eightPlus: "sleep-chip-8plus"
        }
    }

    @ViewBuilder
    private func sleepSourceBadge(_ source: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(SomaTokens.success).frame(width: 6, height: 6)
            Text(Self.sleepSourceDisplayName(source))
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(SomaTokens.success)
    }

    private static func sleepSourceDisplayName(_ source: String) -> String {
        switch source {
        case "whoop": String(localized: "provider.whoop", defaultValue: "Whoop", comment: "Connected-device provider display name; brand name, not translated")
        case "oura": String(localized: "provider.oura", defaultValue: "Oura", comment: "Connected-device provider display name; brand name, not translated")
        case "healthkit": String(localized: "provider.appleHealth", defaultValue: "Apple Health", comment: "Connected-device provider display name; brand name, not translated")
        default: source.capitalized
        }
    }

    /// Single-night phase bar for the wearable state -- a thin horizontal
    /// strip, distinct from `SleepStageBarChart`'s multi-day column chart
    /// (Health Dashboard trend view). Reuses that component's own color
    /// tokens for visual consistency. `nil` when the source reported hours
    /// but no stage breakdown at all -- an honest gap, not a zero-height bar
    /// pretending to be real data (same posture as `SleepStageBarChart`).
    private struct SleepPhaseSegments: View {
        let deep: Double?
        let rem: Double?
        let light: Double?
        let awake: Double?

        init?(snapshot: DailySnapshotRow) {
            guard snapshot.sleepDeepHours != nil || snapshot.sleepRemHours != nil
                || snapshot.sleepLightHours != nil || snapshot.sleepAwakeHours != nil
            else { return nil }
            deep = snapshot.sleepDeepHours
            rem = snapshot.sleepRemHours
            light = snapshot.sleepLightHours
            awake = snapshot.sleepAwakeHours
        }

        private var total: Double { (deep ?? 0) + (rem ?? 0) + (light ?? 0) + (awake ?? 0) }

        var body: some View {
            GeometryReader { geometry in
                HStack(spacing: 3) {
                    segment(deep, color: Theme.pillFill, width: geometry.size.width)
                    segment(rem, color: Theme.orbPrimary, width: geometry.size.width)
                    segment(light, color: Theme.orbSecondary, width: geometry.size.width)
                    segment(awake, color: Theme.pillFill.opacity(0.25), width: geometry.size.width)
                }
            }
            .frame(height: 6)
        }

        @ViewBuilder
        private func segment(_ hours: Double?, color: Color, width: CGFloat) -> some View {
            if let hours, hours > 0, total > 0 {
                Capsule().fill(color).frame(width: max(2, width * CGFloat(hours / total)))
            }
        }

        /// Matches the 9g mock's caption -- Deep/REM/Awake only (Light is
        /// still drawn in the bar above, just not spelled out here).
        var captionText: String {
            func hoursText(_ value: Double?) -> String? {
                guard let value else { return nil }
                return String(format: "%.1f", value)
            }
            var parts: [String] = []
            if let deepText = hoursText(deep) {
                parts.append(String(localized: "home.widget.sleep.deep", defaultValue: "Deep \(deepText)", comment: "Home: sleep widget phase caption, deep sleep hours"))
            }
            if let remText = hoursText(rem) {
                parts.append(String(localized: "home.widget.sleep.rem", defaultValue: "REM \(remText)", comment: "Home: sleep widget phase caption, REM sleep hours"))
            }
            if let awake, awake > 0 {
                let minutes = Int((awake * 60).rounded())
                parts.append(String(localized: "home.widget.sleep.awake", defaultValue: "Awake \(minutes) m", comment: "Home: sleep widget phase caption, minutes spent awake"))
            }
            return parts.joined(separator: " · ")
        }
    }

    /// Exact 3a widget-tile recipe -- lighter/more transparent than the
    /// standard `.glassCard()` (0.32 white vs 0.42, radius 26 vs 24, no
    /// outer shadow) so the two-up grid doesn't read as heavy as the hero.
    private struct HomeWidgetTileBackground: View {
        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
            shape
                .fill(.ultraThinMaterial)
                .overlay(shape.fill(Color.white.opacity(0.32)))
                .overlay(shape.strokeBorder(Color.white.opacity(0.65), lineWidth: 1))
        }
    }

    /// Shared outer frame/padding/background for the 4 widgetGrid tiles
    /// (Water/Sleep/Streak/Mood) -- was copy-pasted 4x with an identical
    /// comment (item 5 fix: collapsed to one definition). Each tile's
    /// internal layout still differs (Water's droplet row, Sleep's 3-way
    /// state, Mood's face grid vs. logged state) -- this only unifies the
    /// part that was already meant to be identical across all 4.
    private func homeWidgetTileFrame<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            // maxHeight too, not just maxWidth -- LazyVGrid equalizes each
            // ROW's layout height across columns, but without this each
            // tile's own background only wraps ITS content's natural
            // height, leaving the shorter tile's card visibly shorter than
            // its row-mate's (e.g. Water taller than Sleep once Sleep's
            // phase-breakdown line wraps to 2 lines in a longer
            // translation). minHeight ALSO fixed, not just maxHeight --
            // row-only equalization still let a tile with no row-mate
            // (Streak, whenever Mood is off and it lands alone in row 2)
            // end up visibly shorter than row 1's pair, since nothing
            // forces separate ROWS to match each other, only same-row
            // siblings. 128 hugs Water's natural height (4 content lines +
            // this padding) -- the tallest realistic tile, not a magic number.
            .frame(maxWidth: .infinity, minHeight: 128, maxHeight: .infinity, alignment: .topLeading)
            .padding(.init(top: 16, leading: 18, bottom: 16, trailing: 18))
            .background(HomeWidgetTileBackground())
    }

    /// Flat tinted metric chip -- deliberately NOT `.glassLens()`/`SomaChip`:
    /// per 3a these carry data (today's sleep/HRV/resting-HR reading), not
    /// affordance, so they never get the raised-control treatment.
    private struct HomeMetricChip: View {
        let text: String
        /// Equal-width only makes sense with 2+ chips in the row -- with
        /// just one (e.g. only the always-present duration chip, no health
        /// source reporting yet), forcing maxWidth: .infinity stretches it
        /// across the whole card instead of hugging its content.
        var fillsRow: Bool = true
        var body: some View {
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SomaTokens.accent)
                .lineLimit(1)
                // Low-ish floor deliberately: with 4 true-equal-width
                // columns, the longest chip needs real room to shrink into
                // or it truncates and hides the actual number -- losing the
                // reading is worse than smaller text. Paired with
                // shortening "Resting HR"/"HRV"-style labels at the source
                // (readinessInputs) rather than relying on scale alone,
                // which would need an illegibly tiny floor to guarantee a
                // fit for every language's translation.
                .minimumScaleFactor(0.45)
                .frame(maxWidth: fillsRow ? .infinity : nil)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 160 / 255, green: 190 / 255, blue: 250 / 255).opacity(0.22),
                                    SomaTokens.accentSoft10
                                ],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.4), lineWidth: 1))
                }
        }
    }

    // MARK: - Custom training source (5a/5b)

    /// Only offered once there's an actual catalog of sport types to pick
    /// from -- same kill-switch rule `showSportGoalPromo` already follows.
    private var showTrainingSourceToggle: Bool {
        Config.enableSportGoals && sportGoalCatalog?.isEmpty == false
    }

    private var trainingSourceToggle: some View {
        HStack(spacing: 4) {
            Button {
                trainingSource = .somasPick
            } label: {
                Text(String(localized: "home.trainingSource.somasPick", defaultValue: "Soma's pick", comment: "Home: training-source toggle option for the AI-generated plan"))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(trainingSource == .somasPick ? SomaTokens.accent : SomaTokens.ink4)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background {
                        if trainingSource == .somasPick { Color.clear.glassLens(cornerRadius: SomaTokens.rPill) }
                    }
            }
            .buttonStyle(.plain)
            Button {
                trainingSource = .custom
            } label: {
                Text(String(localized: "home.trainingSource.custom", defaultValue: "Custom training", comment: "Home: training-source toggle option for picking a sport type directly"))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(trainingSource == .custom ? SomaTokens.accent : SomaTokens.ink4)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background {
                        if trainingSource == .custom { Color.clear.glassLens(cornerRadius: SomaTokens.rPill) }
                    }
            }
            .buttonStyle(.plain)
        }
        .padding(4)
        .glassCardFlat(cornerRadius: SomaTokens.rPill)
    }

    private var selectedCustomSport: Sport? {
        sportGoalCatalog?.sports.first { $0.id == customTrainingSportId } ?? sportGoalCatalog?.sports.first
    }

    /// Honest placeholder, not a fabricated workout: no recommendation-
    /// engine hook exists yet for "build today's session for sport X"
    /// (see the handoff doc's explicit "no matching code checked" note on
    /// 5a/5b) -- this lets the user pick and see their sport type without
    /// pretending Soma already generates sport-specific sessions here.
    private var customTrainingCard: some View {
        CardView {
            HStack {
                if let selectedCustomSport {
                    HStack(spacing: 8) {
                        Image(systemName: selectedCustomSport.iconSystemName)
                            .foregroundStyle(SomaTokens.accent)
                        Text(selectedCustomSport.name.uppercased())
                            .font(.system(size: 11, weight: .bold))
                            .tracking(0.7)
                            .foregroundStyle(SomaTokens.accent)
                    }
                } else {
                    Text(String(localized: "home.customTraining.eyebrow", defaultValue: "CUSTOM TRAINING", comment: "Home: custom-training card fallback eyebrow tag before a sport type is picked"))
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.7)
                        .foregroundStyle(SomaTokens.accent)
                }
                Spacer()
                Button {
                    showCustomTrainingPicker = true
                } label: {
                    Text(String(localized: "home.customTraining.changeTypeButton", defaultValue: "Change type", comment: "Home: custom-training card button that opens the sport-type picker"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SomaTokens.ink4)
                }
                .buttonStyle(.plain)
            }
            Text(selectedCustomSport?.name ?? String(localized: "home.customTraining.pickSportTypeFallback", defaultValue: "Pick a sport type", comment: "Home: custom-training card headline before a sport type is picked"))
                .font(Theme.display)
            Text(String(localized: "home.customTraining.comingSoonBody", defaultValue: "Custom training by sport type is coming soon — Soma will build sport-specific sessions here. For now, Soma's pick still adapts to today's readiness.", comment: "Home: custom-training card body explaining the feature isn't built yet"))
                .font(.system(size: 13.5))
                .foregroundStyle(SomaTokens.ink3)
            SomaButton(title: LocalizedStringKey(String(localized: "home.customTraining.backToSomasPickButton", defaultValue: "Back to Soma's pick", comment: "Home: custom-training card button that switches back to the AI-generated plan")), size: .md, variant: .secondary, isBlock: false) {
                trainingSource = .somasPick
            }
        }
    }

    // MARK: - Floating quick-action dock (3a) + More sheet (4h)

    /// Slot 1 -- always "Dashboard" (health overview), gel-styled since it's
    /// the dock's primary entry point per the mockup.
    private var dashboardDockAction: DashboardDockAction {
        DashboardDockAction(
            id: "dashboard", assetImage: "soma.dock.dashboard", style: .gel,
            label: LocalizedStringKey(String(localized: "home.dock.dashboard.label", defaultValue: "Dashboard", comment: "Home: dock/More-sheet visible label for the health dashboard icon")),
            accessibilityLabel: String(localized: "home.dock.dashboard", defaultValue: "Health dashboard", comment: "Home: floating dock icon that opens the health dashboard's overview section"),
            action: {
                AnalyticsManager.shared.featureUsed(name: "health_dashboard")
                healthDashboardInitialSection = .overview
                showHealthDashboard = true
            }
        )
    }

    /// Slot 2 -- always "Log workout", per the handoff doc.
    private var logWorkoutDockAction: DashboardDockAction {
        DashboardDockAction(
            id: "logWorkout", assetImage: "soma.dock.log",
            label: LocalizedStringKey(String(localized: "home.dock.logWorkout.label", defaultValue: "Log workout", comment: "Home: dock/More-sheet visible label for the log-workout icon")),
            accessibilityLabel: String(localized: "home.dock.logWorkout", defaultValue: "Log workout", comment: "Home: floating dock icon that opens the manual workout log form"),
            action: { showLogManualWorkout = true }
        )
    }

    /// Slots 3-5 -- fixed defaults rather than the mockup's drag-to-reorder
    /// (persisted custom ordering is a bigger feature than this visual
    /// pass covers; logged as a follow-up, see docs/bug-log.md).
    private var configurableDockActions: [DashboardDockAction] {
        [
            DashboardDockAction(
                id: "scanGym", assetImage: "soma.dock.scan", label: LocalizedStringKey(String(localized: "home.dock.scanGym.label", defaultValue: "Scan gym", comment: "Home: dock/More-sheet visible label for the scan-gym icon")),
                accessibilityLabel: String(localized: "home.dock.scanGym", defaultValue: "Scan the gym", comment: "Home: floating dock icon that opens the gym-photo workout flow"),
                action: performScanGymAction
            ),
            DashboardDockAction(
                id: "activity", assetImage: "soma.dock.activity", label: LocalizedStringKey(String(localized: "home.dock.activity.label", defaultValue: "Activity", comment: "Home: dock/More-sheet visible label for the activity icon")),
                accessibilityLabel: String(localized: "home.dock.activity", defaultValue: "Activity", comment: "Home: floating dock icon that opens the health dashboard's activity section"),
                action: {
                    AnalyticsManager.shared.featureUsed(name: "health_dashboard")
                    healthDashboardInitialSection = .activity
                    showHealthDashboard = true
                }
            ),
            // Real feedback: "Nutrition should be more accessible in menu,
            // and goal should move to additional" -- nutrition takes the
            // dock slot, Goals moves to the More sheet.
            DashboardDockAction(
                id: "nutrition", assetImage: "soma.dock.nutrition", label: LocalizedStringKey(String(localized: "home.dock.nutrition.label", defaultValue: "Nutrition", comment: "Home: dock/More-sheet visible label for the nutrition icon")),
                accessibilityLabel: String(localized: "home.dock.nutrition", defaultValue: "Nutrition", comment: "Home: More-sheet icon that opens today's nutrition"),
                accessibilityIdentifier: "dock-nutrition-button",
                action: {
                    AnalyticsManager.shared.featureUsed(name: "nutrition_home_card")
                    showNutrition = true
                }
            )
        ]
    }

    /// Everything else -- reachable from the "More" sheet (4h) even though
    /// it isn't in a dock slot: sport goals, photo progress, editing
    /// widgets, profile. Goals swapped places with Nutrition (real
    /// feedback: nutrition needs the more accessible slot; a goal, once
    /// set, is mostly consumed through Home's goal row anyway).
    private var overflowDockActions: [DashboardDockAction] {
        [
            DashboardDockAction(
                id: "goals", assetImage: "soma.dock.goal", label: LocalizedStringKey(String(localized: "home.dock.goals.label", defaultValue: "Goals", comment: "Home: dock/More-sheet visible label for the sport goal icon")),
                accessibilityLabel: String(localized: "home.dock.goals", defaultValue: "Sport goal", comment: "Home: floating dock icon that opens the sport goal flow"),
                // Stable hook for XCUITest -- the identifier survives the
                // move into the More sheet (OptionalAccessibilityIdentifier
                // in MoreActionsSheet applies it to the sheet row too).
                accessibilityIdentifier: "dock-goals-button",
                action: openSportGoal
            ),
            DashboardDockAction(
                id: "photos", systemImage: "photo.on.rectangle.angled", label: LocalizedStringKey(String(localized: "home.dock.photos.label", defaultValue: "Photos", comment: "Home: dock/More-sheet visible label for the goal photo progress icon")),
                accessibilityLabel: String(localized: "home.dock.photos", defaultValue: "Goal photo progress", comment: "Home: More-sheet icon that opens goal photo progress"),
                action: {
                    AnalyticsManager.shared.featureUsed(name: "goal_progress_home_card")
                    showGoalBodyProgress = true
                }
            ),
            DashboardDockAction(
                id: "widgets", systemImage: "square.grid.2x2.fill", label: LocalizedStringKey(String(localized: "home.dock.widgets.label", defaultValue: "Widgets", comment: "Home: dock/More-sheet visible label for the edit-widgets icon")),
                accessibilityLabel: String(localized: "home.dock.widgets", defaultValue: "Edit widgets", comment: "Home: More-sheet icon that opens the edit-widgets sheet"),
                action: { showEditWidgets = true }
            ),
            DashboardDockAction(
                id: "profile", systemImage: "person.crop.circle.fill", label: LocalizedStringKey(String(localized: "home.dock.profile.label", defaultValue: "Profile", comment: "Home: dock/More-sheet visible label for the profile icon")),
                accessibilityLabel: String(localized: "home.dock.profile", defaultValue: "Profile", comment: "Home: More-sheet icon that opens the profile screen"),
                // Stable hook for XCUITest (see UITests/CASES.md) -- Profile
                // used to be a persistent top-row gear icon; it's now only
                // reachable from here, but the existing tests still look
                // this identifier up directly.
                accessibilityIdentifier: "profile-button",
                action: { showProfile = true }
            )
        ]
    }

    /// Slot 6 -- always "More", per the handoff doc.
    private var moreDockAction: DashboardDockAction {
        DashboardDockAction(
            id: "more", assetImage: "soma.dock.more",
            label: LocalizedStringKey(String(localized: "home.dock.more.label", defaultValue: "More", comment: "Home: dock/More-sheet visible label for the more-actions icon")),
            accessibilityLabel: String(localized: "home.dock.more", defaultValue: "More actions", comment: "Home: floating dock icon that opens the all-actions sheet"),
            accessibilityIdentifier: "dock-more-button",
            action: { showMoreActions = true }
        )
    }

    private var dashboardDock: some View {
        DashboardDockView(actions: [dashboardDockAction, logWorkoutDockAction] + configurableDockActions + [moreDockAction])
            .padding(.horizontal, 18)
            .padding(.bottom, 14)
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
                        title: LocalizedStringKey(String(localized: "home.goalProgress.yourProgress.title", defaultValue: "Your progress", comment: "Home: goal-progress row title once both goal and current photos exist")),
                        subtitle: LocalizedStringKey(String(localized: "home.goalProgress.yourProgress.subtitle", defaultValue: "See how you're tracking toward your goal photo", comment: "Home: goal-progress row subtitle once both goal and current photos exist"))
                    ) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(SomaTokens.ink4)
                    }
                } else {
                    scanRowBody(
                        plate: SomaTokens.accentSoft, icon: "camera.fill", iconColor: SomaTokens.accent,
                        title: LocalizedStringKey(String(localized: "home.goalProgress.addGoalPhoto.title", defaultValue: "Add your goal photo", comment: "Home: goal-progress row title before a goal photo is uploaded")),
                        subtitle: LocalizedStringKey(String(localized: "home.goalProgress.addGoalPhoto.subtitle", defaultValue: "Helps point your plan and nutrition in the right direction", comment: "Home: goal-progress row subtitle before a goal photo is uploaded"))
                    ) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(SomaTokens.ink4)
                    }
                }
            }
            .buttonStyle(.plain)
        } else if Config.enableBodyPhotoUpload {
            // Real feedback: "the progress picture section is gone now."
            // Traced to accounts with no date_of_birth on record (e.g.
            // created before the onboarding DOB step existed) --
            // AgeGate.isAdult fails closed on a missing DOB, so the row
            // above vanished entirely with no explanation. Same two-state
            // "CTA vs. hidden" pattern as everywhere else on this screen:
            // say what's missing and how to fix it, don't just disappear.
            Button {
                AnalyticsManager.shared.featureUsed(name: "goal_progress_dob_prompt")
                showProfile = true
            } label: {
                scanRowBody(
                    plate: SomaTokens.accentSoft, icon: "person.fill.questionmark", iconColor: SomaTokens.accent,
                    title: LocalizedStringKey(String(localized: "home.goalProgress.addDOB.title", defaultValue: "Add your date of birth", comment: "Home: goal-progress row title shown when date of birth is missing, blocking goal photo uploads")),
                    subtitle: LocalizedStringKey(String(localized: "home.goalProgress.addDOB.subtitle", defaultValue: "Confirms you're 18+ to unlock Goal Body progress photos", comment: "Home: goal-progress row subtitle shown when date of birth is missing"))
                ) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SomaTokens.ink4)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func scanRowBody(plate: Color, icon: String, iconColor: Color, title: LocalizedStringKey, subtitle: LocalizedStringKey, @ViewBuilder trailing: () -> some View) -> some View {
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

    /// Compact "what got logged" row, folded directly into readinessCard's
    /// fulfilled/overreached/partiallyDone states (item 2 fix) instead of
    /// rendering as its own separate card underneath -- having both the
    /// still-pitching recommendation AND a "you already did this" card
    /// stacked was the reported bug.
    private func loggedWorkoutRow(_ log: WorkoutLogEntry) -> some View {
        Button {
            openTodaysWorkoutDetail()
        } label: {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.todaysWorkoutCardEyebrow(for: log.source))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(log.title)
                        .font(.subheadline.bold())
                }
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: SomaTokens.rXL, style: .continuous).fill(SomaTokens.surface3))
        }
        .buttonStyle(.plain)
    }

    private static func todaysWorkoutCardEyebrow(for source: String) -> String {
        switch source {
        case "manual": String(localized: "home.workoutCard.eyebrow.manual", defaultValue: "Today's activity", comment: "Home: eyebrow label over today's workout card when the log was manually entered")
        case "device_detected": String(localized: "home.workoutCard.eyebrow.deviceDetected", defaultValue: "Detected automatically", comment: "Home: eyebrow label over today's workout card when the log was auto-detected from a connected device")
        default: String(localized: "home.workoutCard.eyebrow.aiPlan", defaultValue: "Today's workout", comment: "Home: eyebrow label over today's workout card when the log came from the AI-generated plan")
        }
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
                        Text(String(localized: "home.aiPlanCard.eyebrow", defaultValue: "Today's AI-generated workout", comment: "Home: eyebrow label over today's AI-generated workout card"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(aiPlan.selectedTitle)
                            .font(.body.bold())
                        if aiPlan.source == "gym_photo" {
                            Text(String(localized: "home.aiPlanCard.gymPhotoNote", defaultValue: "Generated with your gym picture", comment: "Home: note shown on the AI-generated workout card when it was created from a gym photo scan"))
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
            Text(String(localized: "home.timeline.title", defaultValue: "Today's timeline", comment: "Home: title for today's activity timeline card"))
                .font(.body.bold())
            ForEach(timelineEntries) { entry in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title)
                            .font(.subheadline.bold())
                        // Two full sentences (with/without calories) rather
                        // than fragment-translating a trailing optional
                        // clause -- word order around the number varies by
                        // language, so a bolted-on " — X kcal" suffix can't
                        // be translated correctly on its own.
                        Text(entry.calories.map { calories in
                            String(localized: "home.timeline.entry.withCalories", defaultValue: "\(entry.sourceDisplayName) — \(Self.timeString(entry.startTime)) — \(entry.durationMinutes) min — \(calories.formatted()) kcal", comment: "Home: today's timeline entry -- source name, start time, duration, and calories burned")
                        } ?? String(localized: "home.timeline.entry.noCalories", defaultValue: "\(entry.sourceDisplayName) — \(Self.timeString(entry.startTime)) — \(entry.durationMinutes) min", comment: "Home: today's timeline entry -- source name, start time, and duration, no calories reported"))
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
            Text(String(localized: "home.needsData.title", defaultValue: "Soma needs today's data", comment: "Home: title shown when there's no recommendation yet to display"))
                .font(.body.bold())
            Text(String(localized: "home.needsData.subtitle", defaultValue: "Pull to refresh, or check now.", comment: "Home: subtitle shown when there's no recommendation yet to display"))
                .font(.caption)
                .foregroundStyle(.secondary)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            PillButton(title: LocalizedStringKey(String(localized: "home.needsData.checkNowButton", defaultValue: "Check now", comment: "Home: button that manually fetches today's recommendation")), isEnabled: !isLoading) {
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

    /// Feeds the calendar strip's star badge -- silent on failure, same as
    /// the other plain reads.
    private func loadGoalTrainingDates() async {
        guard Config.enableSportGoals else { return }
        goalTrainingDates = (try? await SupabaseClient.shared.fetchGoalTrainingDates()) ?? goalTrainingDates
    }

    /// Feeds the "Take a Picture of Your Gym" disable gate and the
    /// persistent AI-generated-workout card -- silent on failure, same as
    /// the other plain reads.
    private func loadTodaysAIPlan() async {
        todaysAIPlan = (try? await SupabaseClient.shared.fetchTodaysAIPlan(date: Self.todayDateString())) ?? todaysAIPlan
    }

    /// Feeds the scan card's streak.
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

    /// `throws` (not `try?`) on purpose -- called right after a write in
    /// `logMood`, where a swallowed read failure looked exactly like the
    /// write itself silently doing nothing (real feedback: "nothing
    /// happens"). The plain `.task`/`.refreshable` call sites below still
    /// want a best-effort read, so they keep their own `try?`.
    private func loadTodaysMood() async throws {
        todaysMood = try await SupabaseClient.shared.fetchTodaysMood(date: Self.todayDateString())
    }

    private func logMood(_ rating: MoodRating) async {
        isSavingMood = true
        moodError = nil
        defer { isSavingMood = false }
        do {
            try await SupabaseClient.shared.logMood(date: Self.todayDateString(), rating: rating.rawValue)
            try await loadTodaysMood()
        } catch {
            // Visible now instead of silent -- real feedback: "when the
            // user taps on one of the emojis ... nothing happens." The
            // row of options stays tappable either way so the user can
            // retry without leaving the screen.
            moodError = String(localized: "home.moodCheckIn.error", defaultValue: "Couldn't save that -- check your connection and try again.", comment: "Home: shown when saving the daily mood check-in fails")
        }
    }

    /// Same "throws on purpose" posture as `loadTodaysMood` -- called right
    /// after a write in `logSleep` so a swallowed read failure can't look
    /// like the tap did nothing. Also the one place that clears
    /// `isEditingSleep`, so every reload path (.task, .refreshable, a
    /// completed logSleep) re-syncs the "tap to change" chips back to
    /// whatever the server actually has, instead of leaving the widget
    /// stuck on the picker if the user tapped "change" and then navigated
    /// away without picking a new value.
    private func loadTodaysSleep() async throws {
        todaysSleepLog = try await SupabaseClient.shared.fetchTodaysSleepLog(date: Self.todayDateString())
        isEditingSleep = false
    }

    private func logSleep(_ bucket: SleepDurationBucket) async {
        isSavingSleep = true
        sleepError = nil
        defer { isSavingSleep = false }
        do {
            try await SupabaseClient.shared.logSleep(date: Self.todayDateString(), bucket: bucket)
            try await loadTodaysSleep()
        } catch {
            sleepError = String(localized: "home.sleepCheckIn.error", defaultValue: "Couldn't save that -- check your connection and try again.", comment: "Home: shown when saving the daily sleep check-in fails")
        }
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
        case 5..<12: String(localized: "home.greeting.morning", defaultValue: "Good morning", comment: "Home: greeting shown in the morning")
        case 12..<18: String(localized: "home.greeting.afternoon", defaultValue: "Good afternoon", comment: "Home: greeting shown in the afternoon")
        default: String(localized: "home.greeting.evening", defaultValue: "Good evening", comment: "Home: greeting shown in the evening")
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
        // Explicit LOCAL-day bounds -- without them the edge function
        // defaults to the UTC day, which west of UTC includes yesterday
        // evening's session and auto-marked today done at wake-up.
        async let providerEntries: [WorkoutTimelineEntry] = (try? await SupabaseClient.shared.fetchProviderWorkoutTimeline(
            date: Self.todayDateString(),
            startTime: Calendar.current.startOfDay(for: Date()),
            endTime: Date()
        )) ?? []

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

    /// Closes a real gap: a workout captured passively by a connected
    /// health source (Apple Health, Oura, Whoop) never marked today as
    /// done unless the user ALSO tapped through and logged it explicitly
    /// -- real feedback: "did a 2h workout, burned 1229 kcal, Soma didn't
    /// confirm it," even though the timeline card was already showing it.
    /// Runs after loadTodaysWorkoutLog/loadTimeline; auto-creates a
    /// workout_log row from today's longest qualifying device-detected
    /// session once nothing is logged yet, tagged source:
    /// "device_detected" so it's clearly distinct from something the user
    /// explicitly logged (openTodaysWorkoutDetail routes it to the
    /// generic CompletedWorkoutView, same as a manual entry).
    private func autoLogDeviceDetectedWorkoutIfNeeded() async {
        guard todaysWorkoutLog == nil else { return }
        // Real feedback: "I went for a 2k steps walk, but SOMA is not
        // giving me a workout ... only a real workout should mark the day
        // done, not just a walk." See qualifyingAutoLogCandidate: a
        // trivial multi-minute entry (HealthKit logs even a short walk as
        // its own "workout") shouldn't silently satisfy the whole day,
        // and neither should a walk of any length -- only a deliberate
        // workout session should suppress today's generated plan.
        guard let entry = WorkoutTimelineEntry.qualifyingAutoLogCandidate(from: timelineEntries)
        else { return }

        let endedAt = Calendar.current.date(byAdding: .minute, value: entry.durationMinutes, to: entry.startTime) ?? entry.startTime
        // Two full sentences rather than a fragment-translating a trailing
        // optional clause -- same posture as the timeline entry text above.
        let feedback = entry.calories.map { calories in
            String(localized: "home.autoLog.feedbackWithCalories", defaultValue: "Detected automatically from \(entry.sourceDisplayName) -- \(calories.formatted()) kcal burned.", comment: "Home: auto-generated workout-log note when a device-detected session is logged automatically, including calories burned")
        } ?? String(localized: "home.autoLog.feedbackNoCalories", defaultValue: "Detected automatically from \(entry.sourceDisplayName).", comment: "Home: auto-generated workout-log note when a device-detected session is logged automatically, no calories reported")

        do {
            try await SupabaseClient.shared.logWorkout(
                date: Self.todayDateString(),
                title: entry.title,
                bodyPart: "full_body",
                category: entry.inferredCategory,
                feedback: feedback,
                startedAt: entry.startTime,
                endedAt: endedAt,
                source: "device_detected",
                // Pre-log state: the "closed today's quota" variant only
                // becomes true once this very log lands, so freeze the
                // state-independent detected line instead.
                reasonSnapshot: WorkoutReasonResolver.impactNote(source: "device_detected", dayLoadState: .pending)
            )
            await loadTodaysWorkoutLog()
            await loadCompletedDates()
            await loadWeeklyProgressAndStreak()
        } catch {
            // Best-effort -- next app open or pull-to-refresh retries.
            // Not surfaced as an error banner: the user did nothing wrong
            // here, there's just nothing yet for them to act on.
        }
    }

    /// Manual fallback ("Check now" / pull-to-refresh / the readiness
    /// card's refresh icon / the cold-open fallback in
    /// loadTodaysRecommendation) -- calls the same Edge Function the
    /// automated morning triggers use, but deliberately does NOT call
    /// markSentToday(). That flag means "a local notification was sent
    /// today" (see NotificationManager's own doc comment) and gates
    /// whether Trigger A/B fire at all -- this path never schedules a
    /// notification, so marking it sent here previously caused a real bug:
    /// a pre-sleep cold open (before Oura/Whoop have a real reading)
    /// silently disabled that morning's later automatic re-check, since
    /// Trigger A/B's own `guard !hasSentToday()` would then skip BOTH the
    /// notification AND the regenerate call for the rest of the day. The
    /// stale/thin read then only ever got corrected by the user manually
    /// reopening or refreshing -- which needsDataCard's "Check now" made
    /// unreachable anyway the moment any recommendation, even a bad one,
    /// existed. See readinessCard's refresh icon for the always-visible
    /// manual escape hatch this fix pairs with.
    private func checkNow() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        AnalyticsManager.shared.recommendationRequested()
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
            AnalyticsManager.shared.recommendationGenerated()
        } catch {
            // Covers "expired wearable token" / "zero connected devices" --
            // show a clear message instead of crashing.
            errorMessage = String(localized: "home.error.couldNotFetch", defaultValue: "Couldn't fetch today's data. Reconnect a device or try again.", comment: "Home: shown when the check-now/refresh fetch fails")
            AnalyticsManager.shared.recommendationFailed()
        }
    }

    /// Explicit locale -- DateFormatter's own default (Locale.autoupdatingCurrent)
    /// tracks the SYSTEM locale only, not the in-app language override, so
    /// this could otherwise show English time formatting under a Russian
    /// in-app override even though the rest of the screen switched live.
    private static func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        formatter.locale = LanguageManager.shared.effectiveLocale
        return formatter.string(from: date)
    }

    /// "9:02 AM"-style caption under the compact mood chip -- falls back to
    /// "Logged" if `loggedAt` doesn't parse (never blocks the collapsed
    /// state on a formatting edge case).
    private static func moodLoggedTimeText(_ loggedAt: String) -> String {
        let isoWithFraction = ISO8601DateFormatter()
        isoWithFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso = ISO8601DateFormatter()
        guard let date = isoWithFraction.date(from: loggedAt) ?? iso.date(from: loggedAt) else {
            return String(localized: "home.moodCheckIn.loggedFallback", defaultValue: "Logged", comment: "Home: mood widget caption when today's logged-at timestamp can't be parsed")
        }
        return timeString(date)
    }

    /// Same parse-with-fallback shape as `moodLoggedTimeText`, for the sleep
    /// widget's "logged HH:MM · tap to change" caption.
    private static func sleepLoggedTimeText(_ loggedAt: String) -> String {
        let isoWithFraction = ISO8601DateFormatter()
        isoWithFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso = ISO8601DateFormatter()
        guard let date = isoWithFraction.date(from: loggedAt) ?? iso.date(from: loggedAt) else {
            return String(localized: "home.sleepCheckIn.loggedFallback", defaultValue: "Logged", comment: "Home: sleep widget caption when today's logged-at timestamp can't be parsed")
        }
        return timeString(date)
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

/// The 3a handoff's own calendar-lens glyph -- a 24x24 viewBox rounded rect
/// + two hinge ticks + one header-divider line, no fill. Scales to whatever
/// frame it's given.
private struct HistoryCalendarGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = rect.width / 24
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * scale, y: y * scale) }

        var path = Path()
        path.addRoundedRect(
            in: CGRect(x: 3 * scale, y: 4 * scale, width: 18 * scale, height: 18 * scale),
            cornerSize: CGSize(width: 4 * scale, height: 4 * scale)
        )
        path.move(to: pt(3, 9))
        path.addLine(to: pt(21, 9))
        path.move(to: pt(8, 2))
        path.addLine(to: pt(8, 6))
        path.move(to: pt(16, 2))
        path.addLine(to: pt(16, 6))
        return path
    }
}
