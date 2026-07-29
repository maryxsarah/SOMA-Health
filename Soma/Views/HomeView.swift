import SwiftUI

/// Screen 4 -- Home. No text input, no chat history, no voice button.
struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var subscriptionManager: SubscriptionManager

    @State private var orbState: OrbState = .idle
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showDetail = false
    @State private var showProfile = false
    @State private var showPaywall = false
    @State private var recentRecommendations: [DailyRecommendation] = []
    @State private var selectedDay: String?
    @State private var todaysWorkoutLog: WorkoutLogEntry?
    @State private var completedDates: Set<String> = []
    @State private var timelineEntries: [WorkoutTimelineEntry] = []

    @State private var showGymPhotoFlow = false
    @State private var showSeededDetail = false
    @State private var pendingGymPlan: (AIWorkoutPlan, String, String)?

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                CalendarStripView(recommendations: recentRecommendations, completedDates: completedDates, onSelectDay: { selectedDay = $0 })
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                OrbView(state: orbState)

                Group {
                    if let recommendation = appState.currentRecommendation {
                        recommendationCard(recommendation)
                    } else {
                        needsDataCard
                    }
                }
                .padding(.horizontal, 20)

                // Primary CTA for the gym-photo feature -- reachable without
                // scrolling, matching the rest of the app's PillButton
                // styling rather than a bespoke look. Disabled once today's
                // workout is logged, same lock the fixed suggestion list
                // already has, so this is the one place that needs it now
                // that the entry point lives here instead of also inside
                // RecommendationDetailView.
                PillButton(
                    title: "Take a Picture of Your Gym",
                    isEnabled: todaysWorkoutLog == nil
                ) {
                    if hasDetailAccess {
                        showGymPhotoFlow = true
                    } else {
                        showPaywall = true
                    }
                }
                .padding(.horizontal, 20)

                if let todaysWorkoutLog {
                    todaysWorkoutCard(todaysWorkoutLog)
                        .padding(.horizontal, 20)
                }

                if !timelineEntries.isEmpty {
                    timelineCard
                        .padding(.horizontal, 20)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 40)
        }
        .somaBackground()
        .safeAreaInset(edge: .top) {
            HStack {
                Spacer()
                Button {
                    showProfile = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.title3)
                        .foregroundStyle(Theme.pillFill)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .task {
            await loadTodaysRecommendation()
            await appState.refreshReferralBonus()
            await loadRecentRecommendations()
            await loadTodaysWorkoutLog()
            await loadCompletedDates()
            await loadTimeline()
        }
        .refreshable {
            await checkNow()
            await loadRecentRecommendations()
            await loadTodaysWorkoutLog()
            await loadCompletedDates()
            await loadTimeline()
        }
        .sheet(isPresented: $showDetail, onDismiss: {
            Task {
                await loadTodaysWorkoutLog()
                await loadCompletedDates()
                await loadTimeline()
            }
        }) {
            if let recommendation = appState.currentRecommendation {
                RecommendationDetailView(recommendation: recommendation)
            }
        }
        .sheet(isPresented: $showProfile) {
            ProfileView()
        }
        .sheet(isPresented: $showGymPhotoFlow, onDismiss: {
            if pendingGymPlan != nil {
                showSeededDetail = true
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
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .sheet(isPresented: Binding(
            get: { selectedDay != nil },
            set: { if !$0 { selectedDay = nil } }
        )) {
            if let selectedDay {
                DayDetailView(date: selectedDay)
            }
        }
    }

    /// The Home card (today's category + message) always stays free --
    /// only the tap-through detail (step target, workout suggestions, why
    /// explanation) requires an active subscription or referral bonus.
    private var hasDetailAccess: Bool {
        if subscriptionManager.isSubscribed { return true }
        if let until = appState.referralBonusUntil, until > Date() { return true }
        return false
    }

    private func recommendationCard(_ recommendation: DailyRecommendation) -> some View {
        Button {
            if hasDetailAccess {
                showDetail = true
            } else {
                showPaywall = true
            }
        } label: {
            CardView {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(recommendation.category.displayTitle)
                            .font(Theme.display)
                        // The only screen a day-1 user is guaranteed to see --
                        // without this, a zero-signal "moderate" reads exactly
                        // like a real one until they tap through to Detail.
                        if recommendation.reason == .insufficientData {
                            Text("Building your baseline")
                                .font(.caption.bold())
                                .foregroundStyle(.orange)
                        }
                        Text(recommendation.message)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func todaysWorkoutCard(_ log: WorkoutLogEntry) -> some View {
        CardView {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Today's workout")
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
            triggerNewMessagePulse()
        } catch {
            // Covers "expired wearable token" / "zero connected devices" --
            // show a clear message instead of crashing.
            errorMessage = "Couldn't fetch today's data. Reconnect a device or try again."
        }
    }

    private func triggerNewMessagePulse() {
        orbState = .newMessage
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            orbState = .idle
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
