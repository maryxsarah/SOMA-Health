import UserNotifications

/// Local notifications only -- no APNs, per spec.
final class NotificationManager {
    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()
    private let sentDateDefaultsKey = "com.soma.app.lastNotificationSentDate"

    func requestAuthorization() async throws {
        _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Read-only status check -- the daily checklist's "enable
    /// notifications" onboarding item uses this instead of re-prompting.
    func isAuthorized() async -> Bool {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus == .authorized
    }

    /// Fires immediately (nil trigger) with the day's fixed category/message.
    func scheduleImmediateNotification(category: RecommendationCategory, message: String) async {
        let content = UNMutableNotificationContent()
        content.title = category.displayTitle
        content.body = message
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "daily-recommendation-\(todayKey())",
            content: content,
            trigger: nil
        )

        await withCheckedContinuation { continuation in
            center.add(request) { _ in continuation.resume() }
        }
    }

    /// Schedules a one-time reminder 2 days BEFORE a referral code's
    /// free-access bonus ends (not at expiry itself) -- e.g. "somafirst"
    /// grants 14 days with no payment method required; this fires on day
    /// 12, giving a 2-day heads-up rather than a same-day surprise.
    /// Re-redeeming another code reschedules this same notification rather
    /// than stacking multiple reminders, since the identifier is fixed.
    func scheduleUpgradeReminder(bonusUntil: Date) async {
        let reminderDate = Calendar.current.date(byAdding: .day, value: -2, to: bonusUntil) ?? bonusUntil
        let interval = reminderDate.timeIntervalSinceNow
        guard interval > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Your free access ends in 2 days"
        content.body = "Subscribe to Soma Premium to keep getting your full daily plan -- workouts, step targets, and more."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "referral-upgrade-reminder",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        )

        await withCheckedContinuation { continuation in
            center.add(request) { _ in continuation.resume() }
        }
    }

    // MARK: - Daily engagement notifications (movement / evening workout / progress)
    //
    // Three touchpoints beyond the existing morning recommendation, all
    // local and day-stamped (identifier includes today's date, same
    // pattern as scheduleImmediateNotification's own "-\(todayKey())"
    // suffix) so each is scheduled fresh once a day rather than as an
    // indefinitely-repeating trigger -- that's what makes
    // cancelEveningWorkoutReminder below possible: cancelling a repeating
    // trigger would kill EVERY future day's reminder, not just today's.
    //
    // Content is either genuinely fixed-safe (movement: true regardless of
    // what the user has actually done) or computed from real data at
    // schedule time (progress check-in's workout count) -- never a guess
    // about live state a local notification has no way to check at the
    // moment it actually fires.

    private static let middayMovementHour = 13
    private static let eveningWorkoutHour = 18
    private static let eveningWorkoutMinute = 30
    private static let progressCheckInHour = 20

    /// Orchestrates all three -- the single call site both BackgroundTask-
    /// Manager's daily refresh and NotificationEnablementView's "enable"
    /// success path use, so the data-fetching + scheduling logic lives in
    /// exactly one place. Best-effort throughout: a failed fetch just
    /// means today's copy falls back to generic (never blocks the other
    /// notifications, never crashes).
    func scheduleTodaysEngagementNotifications() async {
        let date = todayKey()
        async let workoutsThisWeek = (try? SupabaseClient.shared.fetchRecentWorkoutLogDates(days: 7))?.count ?? 0
        async let dayNumber: Int? = {
            guard let userId = SupabaseClient.shared.currentUserID,
                  let profile = try? await SupabaseClient.shared.fetchProfile(id: userId),
                  let progress = GoalJourneyProgress.compute(
                      createdAt: profile.createdAt,
                      weightKg: profile.weightKg,
                      desiredWeightKg: profile.desiredWeightKg,
                      goalPace: profile.goalPace
                  )
            else { return nil }
            return progress.daysElapsed + 1
        }()

        await scheduleMiddayMovementNudge(for: date)
        await scheduleEveningWorkoutReminder(for: date)
        await scheduleProgressCheckIn(for: date, dayNumber: await dayNumber, workoutsThisWeek: await workoutsThisWeek)
    }

    /// Generic, always-appropriate copy -- there's no way to check live
    /// step/movement data at the moment this actually fires, so it never
    /// claims to know whether the user has moved today.
    private func scheduleMiddayMovementNudge(for date: String) async {
        let content = UNMutableNotificationContent()
        content.title = "Stay moving"
        content.body = "Even a short walk supports today's recovery and tomorrow's readiness."
        content.sound = .default
        await scheduleToday(hour: Self.middayMovementHour, minute: 0, identifier: "midday-movement-\(date)", content: content)
    }

    /// Cancelled the moment today's workout is actually logged -- see
    /// cancelEveningWorkoutReminder, called from RecommendationDetailView's
    /// markWorkoutComplete. If it's never logged, this fires as a genuine
    /// reminder; if it is, the pending request is removed before it can.
    private func scheduleEveningWorkoutReminder(for date: String) async {
        let content = UNMutableNotificationContent()
        content.title = "Still time today"
        content.body = "Your workout is ready whenever you are -- log it when you're done to keep your streak."
        content.sound = .default
        await scheduleToday(
            hour: Self.eveningWorkoutHour, minute: Self.eveningWorkoutMinute,
            identifier: Self.eveningWorkoutReminderIdentifier(for: date), content: content
        )
    }

    /// Real numbers, computed once at schedule time -- "Day X" from the
    /// same GoalJourneyProgress the goal-photo progress bar uses, and an
    /// actual count of workouts logged this week. Falls back to
    /// encouragement-without-a-number when either is unavailable (e.g. no
    /// desired weight/pace set yet) rather than fabricating one.
    private func scheduleProgressCheckIn(for date: String, dayNumber: Int?, workoutsThisWeek: Int) async {
        let content = UNMutableNotificationContent()
        content.title = "Your progress"
        content.sound = .default
        let workoutClause = workoutsThisWeek > 0
            ? "\(workoutsThisWeek) workout\(workoutsThisWeek == 1 ? "" : "s") logged this week -- keep the momentum."
            : "Consistency beats intensity. A short session today still counts."
        content.body = dayNumber.map { "Day \($0) of your journey. \(workoutClause)" } ?? workoutClause
        await scheduleToday(hour: Self.progressCheckInHour, minute: 0, identifier: "progress-checkin-\(date)", content: content)
    }

    /// Removes today's (and only today's -- the identifier is day-
    /// stamped) evening workout reminder. A no-op if it already fired or
    /// was never scheduled (e.g. notifications disabled).
    func cancelEveningWorkoutReminder(for date: String) {
        center.removePendingNotificationRequests(withIdentifiers: [Self.eveningWorkoutReminderIdentifier(for: date)])
    }

    private static func eveningWorkoutReminderIdentifier(for date: String) -> String {
        "evening-workout-reminder-\(date)"
    }

    /// Schedules `content` for today at the given local hour/minute.
    /// Silently skips if that time has already passed today -- never
    /// fires late/immediately as a substitute (tomorrow's scheduling call
    /// covers the next occurrence normally). Same identifier overwrites
    /// any still-pending request from an earlier call this same day
    /// (Trigger A and Trigger B can both invoke this), so calling it more
    /// than once per day is always safe.
    private func scheduleToday(hour: Int, minute: Int, identifier: String, content: UNNotificationContent) async {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        guard let fireDate = Calendar.current.date(from: components), fireDate > Date() else { return }

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate),
            repeats: false
        )
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        await withCheckedContinuation { continuation in
            center.add(request) { _ in continuation.resume() }
        }
    }

    // MARK: - Daily checklist nudges
    //
    // Distinct from the 3 engagement notifications above (which predate
    // the checklist and fire unconditionally except the evening workout
    // one) -- these three are ALL gated on real, freshly-read state and
    // simply don't get scheduled at all when the item's already checked,
    // so "never nudge for an already-checked item" holds by construction
    // rather than by a completion-time cancel. Capped at 3/day by having
    // exactly 3 possible nudges, one per daypart, each independently
    // skippable -- a fully-on-track day schedules zero of them.

    private static let checklistBreakfastHour = 10
    private static let checklistStepsHour = 15
    private static let checklistEveningRecapHour = 20
    private static let checklistEveningRecapMinute = 30

    /// Deep-link identifiers carried in each notification's userInfo --
    /// AppDelegate reads this on tap and forwards it to AppState, which
    /// HomeView observes to open the right sheet directly instead of just
    /// landing on Home. Raw strings (not ChecklistDeepLink itself) because
    /// UNNotificationContent.userInfo is [AnyHashable: Any], not Codable.
    enum ChecklistNudgeDeepLink: String {
        case logMeal, healthDashboard, startWorkout
    }

    /// Single call site (HomeView's checklist card, once per day it's
    /// computed) -- scheduling is naturally idempotent via the day-stamped
    /// identifiers scheduleToday already uses, and any nudge whose item is
    /// already checked is simply never scheduled to begin with.
    func scheduleChecklistNudges(mealLoggedToday: Bool, stepsOnTrack: Bool, workoutLoggedToday: Bool, openItemTitles: [String]) async {
        let date = todayKey()
        if !mealLoggedToday {
            await scheduleChecklistNudge(
                hour: Self.checklistBreakfastHour, minute: 0, identifier: "checklist-breakfast-\(date)",
                title: "Log breakfast?", body: "A quick log now keeps today's nutrition bars on track.",
                deepLink: .logMeal
            )
        }
        if !stepsOnTrack {
            await scheduleChecklistNudge(
                hour: Self.checklistStepsHour, minute: 0, identifier: "checklist-steps-\(date)",
                title: "Behind on steps today", body: "A short walk this afternoon closes most of the gap.",
                deepLink: .healthDashboard
            )
        }
        if !openItemTitles.isEmpty {
            let recap = openItemTitles.count == 1
                ? "Still open: \(openItemTitles[0])."
                : "Still open: \(openItemTitles.prefix(2).joined(separator: ", "))\(openItemTitles.count > 2 ? ", and more" : "")."
            await scheduleChecklistNudge(
                hour: Self.checklistEveningRecapHour, minute: Self.checklistEveningRecapMinute,
                identifier: "checklist-recap-\(date)",
                title: "Today's checklist", body: recap,
                deepLink: workoutLoggedToday ? .healthDashboard : .startWorkout
            )
        }
    }

    private func scheduleChecklistNudge(hour: Int, minute: Int, identifier: String, title: String, body: String, deepLink: ChecklistNudgeDeepLink) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["checklistDeepLink": deepLink.rawValue]
        await scheduleToday(hour: hour, minute: minute, identifier: identifier, content: content)
    }

    // MARK: - "Already sent today" flag
    //
    // Shared by both the HealthKit-observer trigger and the
    // BGAppRefreshTask fallback so a day never gets double-notified.

    func hasSentToday() -> Bool {
        UserDefaults.standard.string(forKey: sentDateDefaultsKey) == todayKey()
    }

    func markSentToday() {
        UserDefaults.standard.set(todayKey(), forKey: sentDateDefaultsKey)
    }

    private func todayKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: Date())
    }
}
