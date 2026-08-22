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

    /// True once the user has already answered the system prompt with "Don't
    /// Allow" -- iOS never re-shows that prompt after a first denial, so
    /// callers need this to route to Settings instead of re-requesting.
    func isDenied() async -> Bool {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus == .denied
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
        content.title = String(localized: "notification.upgradeReminder.title", defaultValue: "Your free access ends in 2 days", comment: "Push notification title warning the user their referral bonus access is ending soon")
        content.body = String(localized: "notification.upgradeReminder.body", defaultValue: "Subscribe to Soma Premium to keep getting your full daily plan -- workouts, step targets, and more.", comment: "Push notification body warning the user their referral bonus access is ending soon")
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

    // MARK: - Cooking timer
    //
    // CookModeView's per-step countdown. A fixed identifier is
    // deliberate: only one step is ever showing at a time, so starting a
    // new timer always means whatever was pending is now stale and
    // should be replaced, never stacked.

    private static let cookingTimerIdentifier = "cooking-timer"

    /// One-shot "time's up" alert, same UNTimeIntervalNotificationTrigger
    /// shape as scheduleUpgradeReminder -- keeps the countdown meaningful
    /// even if the user backgrounds the app mid-step (switches apps while
    /// something simmers) instead of relying on a foreground-only
    /// decrementing counter that would silently freeze.
    func scheduleCookingTimer(seconds: TimeInterval, stepText: String) async {
        guard seconds > 0 else { return }
        cancelCookingTimer()

        let content = UNMutableNotificationContent()
        content.title = String(localized: "notification.cookingTimer.title", defaultValue: "Timer's up", comment: "Push notification title when a cooking step's timer finishes")
        content.body = stepText
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: Self.cookingTimerIdentifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        )

        await withCheckedContinuation { continuation in
            center.add(request) { _ in continuation.resume() }
        }
    }

    /// Called when the user resets/restarts a step's timer, or navigates
    /// away from the step (or out of cook mode entirely) while one is
    /// still running -- same removePendingNotificationRequests shape as
    /// cancelEveningWorkoutReminder.
    func cancelCookingTimer() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.cookingTimerIdentifier])
    }

    // MARK: - Quiet hours
    //
    // Off by default so nobody's existing schedule silently changes until
    // they opt in via Settings (ProfileView's Account > Notifications row).
    // Stored as minute-of-day (0-1439), not Date -- only the clock time
    // matters, never a specific calendar day.

    private let quietHoursEnabledKey = "com.soma.app.quietHoursEnabled"
    private let quietHoursStartMinuteKey = "com.soma.app.quietHoursStartMinute"
    private let quietHoursEndMinuteKey = "com.soma.app.quietHoursEndMinute"
    private static let defaultQuietHoursStartMinute = 22 * 60
    private static let defaultQuietHoursEndMinute = 7 * 60

    var isQuietHoursEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: quietHoursEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: quietHoursEnabledKey) }
    }

    var quietHoursStartMinute: Int {
        get { UserDefaults.standard.object(forKey: quietHoursStartMinuteKey) as? Int ?? Self.defaultQuietHoursStartMinute }
        set { UserDefaults.standard.set(newValue, forKey: quietHoursStartMinuteKey) }
    }

    var quietHoursEndMinute: Int {
        get { UserDefaults.standard.object(forKey: quietHoursEndMinuteKey) as? Int ?? Self.defaultQuietHoursEndMinute }
        set { UserDefaults.standard.set(newValue, forKey: quietHoursEndMinuteKey) }
    }

    /// Pushes `date` forward to the end of quiet hours if it falls inside
    /// the user's configured window; a no-op if quiet hours are off or the
    /// time falls outside them. Uses Calendar.nextDate rather than manual
    /// wraparound arithmetic so an overnight window (e.g. 22:00-07:00)
    /// behaves the same as a same-day one.
    private func adjustedForQuietHours(_ date: Date) -> Date {
        guard isQuietHoursEnabled else { return date }
        let start = quietHoursStartMinute
        let end = quietHoursEndMinute
        guard start != end else { return date }

        let calendar = Calendar.current
        let minuteOfDay = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        let inQuietHours = start < end
            ? (minuteOfDay >= start && minuteOfDay < end)
            : (minuteOfDay >= start || minuteOfDay < end)
        guard inQuietHours else { return date }

        var endComponents = DateComponents()
        endComponents.hour = end / 60
        endComponents.minute = end % 60
        return calendar.nextDate(after: date, matching: endComponents, matchingPolicy: .nextTimePreservingSmallerComponents) ?? date
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
    // schedule time (progress check-in's workout count, streak-aware
    // copy) -- never a guess about live state a local notification has no
    // way to check at the moment it actually fires.

    private static let middayMovementHour = 13
    private static let eveningWorkoutHour = 18
    private static let eveningWorkoutMinute = 30
    private static let progressCheckInHour = 20
    /// Duolingo's own published reasoning: 23.5h after the last logged
    /// activity consistently outperforms a fixed reminder clock time --
    /// see docs/notifications-plan.md. Used only by the event-driven path
    /// (scheduleStreakProtectionReminder); the once-a-day catch-up
    /// fallback below has no precise "last logged at" timestamp to anchor
    /// to, so it keeps the fixed evening hour.
    private static let streakReminderInterval: TimeInterval = 23.5 * 3600
    /// Wide enough to detect every StreakMilestone tier (up to 365 days)
    /// -- the in-app streak display elsewhere in the app intentionally
    /// stays on a shorter/cheaper fetch window (see docs/widgetkit-plan.md),
    /// but a milestone celebration needs the real number to ever fire for
    /// the longer tiers.
    private static let streakLookbackDays = 400

    /// Orchestrates all three -- the single call site both BackgroundTask-
    /// Manager's daily refresh and NotificationEnablementView's "enable"
    /// success path use, so the data-fetching + scheduling logic lives in
    /// exactly one place. Best-effort throughout: a failed fetch just
    /// means today's copy falls back to generic (never blocks the other
    /// notifications, never crashes).
    func scheduleTodaysEngagementNotifications() async {
        let date = todayKey()
        async let workoutsThisWeek = (try? SupabaseClient.shared.fetchRecentWorkoutLogDates(days: 7))?.count ?? 0
        async let streak = (try? SupabaseClient.shared.fetchRecentWorkoutLogDates(days: Self.streakLookbackDays)).map(ProfileStore.streak(from:)) ?? 0
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

        let resolvedStreak = await streak
        await scheduleMiddayMovementNudge(for: date, streak: resolvedStreak)
        await scheduleEveningWorkoutReminder(for: date, streak: resolvedStreak)
        await scheduleProgressCheckIn(for: date, dayNumber: await dayNumber, workoutsThisWeek: await workoutsThisWeek)
        await scheduleAffirmationReminders()
    }

    /// Generic movement copy when there's no active streak to reference;
    /// streak-aware copy otherwise. Either way there's no way to check
    /// live step/movement data at the moment this actually fires, so it
    /// never claims to know whether the user has moved today.
    private func scheduleMiddayMovementNudge(for date: String, streak: Int) async {
        let content = UNMutableNotificationContent()
        content.sound = .default
        if streak > 0 {
            content.title = String(localized: "notification.middayMovement.streakTitle", defaultValue: "Keep it going", comment: "Push notification title nudging the user to move, shown when they have an active workout streak")
            content.body = String(localized: "notification.middayMovement.streakBody", defaultValue: "A short walk keeps your \(streak)-day streak's momentum going.", comment: "Push notification body nudging the user to move, referencing their active streak length")
        } else {
            content.title = String(localized: "notification.middayMovement.title", defaultValue: "Stay moving", comment: "Push notification title nudging the user to move during the day")
            content.body = String(localized: "notification.middayMovement.body", defaultValue: "Even a short walk supports today's recovery and tomorrow's readiness.", comment: "Push notification body nudging the user to move during the day")
        }
        await scheduleToday(hour: Self.middayMovementHour, minute: 0, identifier: "midday-movement-\(date)", content: content)
    }

    /// Once-a-day catch-up fallback for the evening reminder -- covers
    /// days the event-driven path (scheduleStreakProtectionReminder) never
    /// got to run (e.g. no workout logged in a while, so nothing re-armed
    /// tomorrow's reminder). Fixed evening hour, since there's no precise
    /// "last logged at" timestamp available here to anchor to. Cancelled
    /// the moment today's workout is actually logged -- see
    /// cancelEveningWorkoutReminder, called from RecommendationDetailView's
    /// markWorkoutComplete.
    private func scheduleEveningWorkoutReminder(for date: String, streak: Int) async {
        await scheduleToday(
            hour: Self.eveningWorkoutHour, minute: Self.eveningWorkoutMinute,
            identifier: Self.eveningWorkoutReminderIdentifier(for: date), content: eveningReminderContent(streak: streak)
        )
    }

    /// Shared copy for the evening reminder in both its forms: this
    /// once-a-day fallback and scheduleStreakProtectionReminder's
    /// event-driven one. Framed as protecting something the user already
    /// has, never as a threat -- a zero streak gets the original generic
    /// copy instead, so this never nags someone who has nothing to
    /// protect yet.
    private func eveningReminderContent(streak: Int) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.sound = .default
        if streak > 0 {
            content.title = String(localized: "notification.streakProtection.title", defaultValue: "Protect your streak", comment: "Push notification title reminding the user to protect their active workout streak")
            content.body = String(localized: "notification.streakProtection.body", defaultValue: "You're on a \(streak)-day streak. Log today's workout to keep it going.", comment: "Push notification body reminding the user to protect their streak, showing the current streak length in days")
        } else {
            content.title = String(localized: "notification.eveningWorkout.title", defaultValue: "Still time today", comment: "Push notification title reminding the user their workout is still open in the evening")
            content.body = String(localized: "notification.eveningWorkout.body", defaultValue: "Your workout is ready whenever you are -- log it when you're done to keep your streak.", comment: "Push notification body reminding the user their workout is still open in the evening")
        }
        return content
    }

    /// Anchored to the exact moment a workout was just logged rather than
    /// a fixed clock time -- see streakReminderInterval's doc comment.
    /// Clamped to never fire earlier than the fallback's own evening floor
    /// on that day, so a very-early workout doesn't produce an
    /// early-morning ping the next day -- the copy still reads "today."
    private func scheduleStreakProtectionReminder(afterLogAt logTime: Date, streak: Int) async {
        let anchor = logTime.addingTimeInterval(Self.streakReminderInterval)
        let floor = Calendar.current.date(bySettingHour: Self.eveningWorkoutHour, minute: Self.eveningWorkoutMinute, second: 0, of: anchor) ?? anchor
        let fireDate = max(anchor, floor)
        let identifier = Self.eveningWorkoutReminderIdentifier(for: dateKey(for: fireDate))
        await schedule(at: fireDate, identifier: identifier, content: eveningReminderContent(streak: streak))
    }

    /// Real numbers, computed once at schedule time -- "Day X" from the
    /// same GoalJourneyProgress the goal-photo progress bar uses, and an
    /// actual count of workouts logged this week. Falls back to
    /// encouragement-without-a-number when either is unavailable (e.g. no
    /// desired weight/pace set yet) rather than fabricating one.
    private func scheduleProgressCheckIn(for date: String, dayNumber: Int?, workoutsThisWeek: Int) async {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "notification.progressCheckIn.title", defaultValue: "Your progress", comment: "Push notification title for the evening progress check-in")
        content.sound = .default
        let workoutClause = workoutsThisWeek > 0
            ? String(
                localized: "notification.progress.workoutsLogged",
                defaultValue: "\(workoutsThisWeek) workouts logged this week -- keep the momentum.",
                comment: "Weekly progress notification body, pluralized by workout count"
              )
            : String(localized: "notification.progressCheckIn.noWorkoutsBody", defaultValue: "Consistency beats intensity. A short session today still counts.", comment: "Push notification body for the evening progress check-in when no workouts were logged this week")
        content.body = dayNumber.map {
            String(localized: "notification.progressCheckIn.dayBody", defaultValue: "Day \($0) of your journey. \(workoutClause)", comment: "Push notification body for the evening progress check-in, showing the day number in the user's journey plus a workout summary clause")
        } ?? workoutClause
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

    // MARK: - Workout-logged event (streak protection + milestones)

    /// Called right after a workout is logged (RecommendationDetailView's
    /// markWorkoutComplete, right after cancelEveningWorkoutReminder
    /// clears today's now-moot pending reminder). Re-fetches the real
    /// streak -- today's log is in the data now, so this reflects it --
    /// celebrates a freshly-crossed StreakMilestone tier if any, and
    /// schedules tomorrow's streak-protection reminder anchored to this
    /// exact moment rather than waiting for the next daily catch-up.
    func handleWorkoutLogged(at logTime: Date) async {
        let dates = (try? await SupabaseClient.shared.fetchRecentWorkoutLogDates(days: Self.streakLookbackDays)) ?? []
        let streak = ProfileStore.streak(from: dates)

        if let milestone = StreakMilestone(rawValue: streak) {
            await scheduleMilestoneCelebration(milestone: milestone)
        }
        await scheduleStreakProtectionReminder(afterLogAt: logTime, streak: streak)
    }

    private let lastCelebratedMilestoneKey = "com.soma.app.lastCelebratedMilestoneStreak"
    private let lastCelebratedMilestoneDateKey = "com.soma.app.lastCelebratedMilestoneDate"

    /// Fires once per (milestone, day) pair -- logging a second workout
    /// the same day recomputes the identical streak and must not
    /// re-celebrate it, but genuinely re-reaching the same tier after a
    /// later streak reset should still celebrate again.
    private func scheduleMilestoneCelebration(milestone: StreakMilestone) async {
        let today = todayKey()
        let defaults = UserDefaults.standard
        let alreadyCelebratedToday = defaults.string(forKey: lastCelebratedMilestoneDateKey) == today
            && defaults.integer(forKey: lastCelebratedMilestoneKey) == milestone.rawValue
        guard !alreadyCelebratedToday else { return }
        defaults.set(milestone.rawValue, forKey: lastCelebratedMilestoneKey)
        defaults.set(today, forKey: lastCelebratedMilestoneDateKey)

        let content = UNMutableNotificationContent()
        content.title = String(localized: "notification.milestone.title", defaultValue: "Milestone unlocked", comment: "Push notification title celebrating a newly-reached streak milestone")
        content.body = String(localized: "notification.milestone.body", defaultValue: "\(milestone.title) streak -- and counting. Keep it up.", comment: "Push notification body celebrating a newly-reached streak milestone, showing the milestone's display title such as '1 Week'")
        content.sound = .default

        let request = UNNotificationRequest(identifier: "milestone-\(milestone.rawValue)-\(today)", content: content, trigger: nil)
        await withCheckedContinuation { continuation in
            center.add(request) { _ in continuation.resume() }
        }
    }

    // MARK: - Scheduling primitives

    /// Schedules `content` for today at the given local hour/minute --
    /// thin wrapper over `schedule(at:identifier:content:)` below.
    private func scheduleToday(hour: Int, minute: Int, identifier: String, content: UNNotificationContent) async {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        guard let fireDate = Calendar.current.date(from: components) else { return }
        await schedule(at: fireDate, identifier: identifier, content: content)
    }

    /// Schedules `content` for `fireDate`, pushed past the end of quiet
    /// hours if it would otherwise land inside them. Silently skips if the
    /// (possibly-adjusted) time has already passed -- never fires late/
    /// immediately as a substitute (tomorrow's scheduling call covers the
    /// next occurrence normally). Same identifier overwrites any still-
    /// pending request from an earlier call, so calling this more than
    /// once for the same slot is always safe.
    private func schedule(at fireDate: Date, identifier: String, content: UNNotificationContent) async {
        let adjusted = adjustedForQuietHours(fireDate)
        guard adjusted > Date() else { return }

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: adjusted),
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
                title: String(localized: "notification.checklistBreakfast.title", defaultValue: "Log breakfast?", comment: "Push notification: evening nudge title when today's meal hasn't been logged"),
                body: String(localized: "notification.checklistBreakfast.body", defaultValue: "A quick log now keeps today's nutrition bars on track.", comment: "Push notification: evening nudge body when today's meal hasn't been logged"),
                deepLink: .logMeal
            )
        }
        if !stepsOnTrack {
            await scheduleChecklistNudge(
                hour: Self.checklistStepsHour, minute: 0, identifier: "checklist-steps-\(date)",
                title: String(localized: "notification.checklistSteps.title", defaultValue: "Behind on steps today", comment: "Push notification: evening nudge title when today's step goal is behind pace"),
                body: String(localized: "notification.checklistSteps.body", defaultValue: "A short walk this afternoon closes most of the gap.", comment: "Push notification: evening nudge body when today's step goal is behind pace"),
                deepLink: .healthDashboard
            )
        }
        if !openItemTitles.isEmpty {
            let recap: String
            if openItemTitles.count == 1 {
                recap = String(localized: "notification.checklistRecap.singleItem", defaultValue: "Still open: \(openItemTitles[0]).", comment: "Push notification body: exactly one checklist item still open tonight")
            } else {
                let joined = openItemTitles.prefix(2).joined(separator: ", ")
                let suffix = openItemTitles.count > 2
                    ? String(localized: "notification.checklistRecap.andMore", defaultValue: ", and more", comment: "Appended when more than 2 checklist items remain open tonight")
                    : ""
                recap = String(localized: "notification.checklistRecap.multipleItems", defaultValue: "Still open: \(joined)\(suffix).", comment: "Push notification body: multiple checklist items still open tonight; first placeholder is up to 2 item names joined by commas, second is an optional ', and more' suffix")
            }
            await scheduleChecklistNudge(
                hour: Self.checklistEveningRecapHour, minute: Self.checklistEveningRecapMinute,
                identifier: "checklist-recap-\(date)",
                title: String(localized: "notification.checklistRecap.title", defaultValue: "Today's checklist", comment: "Push notification: evening recap title listing still-open checklist items"),
                body: recap,
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

    // MARK: - Affirmation reminders (16c)
    //
    // Off by default, like quiet hours -- nobody gets new pushes until
    // they opt in (16c's toggle, reachable from Profile > Notifications
    // and the Affirmations sheet's bell). All prefs are local device
    // state, same posture as quiet hours: plain UserDefaults, no sync.

    private let affirmationEnabledKey = "com.soma.app.affirmationRemindersEnabled"
    private let affirmationPerDayKey = "com.soma.app.affirmationRemindersPerDay"
    private let affirmationSlotMinuteKeys = [
        "com.soma.app.affirmationSlot0Minute",
        "com.soma.app.affirmationSlot1Minute",
        "com.soma.app.affirmationSlot2Minute",
    ]
    private let affirmationSourceKey = "com.soma.app.affirmationSource"
    private let affirmationRecentLinesKey = "com.soma.app.affirmationRecentLines"
    /// 16c defaults: 08:30 / 15:00 / 20:00 (minute-of-day, same encoding
    /// as quiet hours). The stagger pass below shifts any that land within
    /// an hour of another Soma push, so these stay the *user-visible*
    /// times while never double-firing next to a fixed slot.
    static let affirmationDefaultSlotMinutes = [8 * 60 + 30, 15 * 60, 20 * 60]

    /// Where reminder lines come from (16c "Draw lines from") -- today's
    /// generated line, the user's own kept list, or both interleaved.
    enum AffirmationSource: String {
        case generated, list, both
    }

    var affirmationRemindersEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: affirmationEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: affirmationEnabledKey) }
    }

    /// 1-3 pushes a day; mockup default is 2.
    var affirmationRemindersPerDay: Int {
        get { min(max(UserDefaults.standard.object(forKey: affirmationPerDayKey) as? Int ?? 2, 1), 3) }
        set { UserDefaults.standard.set(min(max(newValue, 1), 3), forKey: affirmationPerDayKey) }
    }

    func affirmationSlotMinute(_ index: Int) -> Int {
        guard affirmationSlotMinuteKeys.indices.contains(index) else { return Self.affirmationDefaultSlotMinutes[0] }
        return UserDefaults.standard.object(forKey: affirmationSlotMinuteKeys[index]) as? Int
            ?? Self.affirmationDefaultSlotMinutes[index]
    }

    func setAffirmationSlotMinute(_ minute: Int, at index: Int) {
        guard affirmationSlotMinuteKeys.indices.contains(index) else { return }
        UserDefaults.standard.set(minute, forKey: affirmationSlotMinuteKeys[index])
    }

    var affirmationSource: AffirmationSource {
        get { AffirmationSource(rawValue: UserDefaults.standard.string(forKey: affirmationSourceKey) ?? "") ?? .both }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: affirmationSourceKey) }
    }

    /// Schedules today's affirmation pushes -- joins the same daily pass as
    /// the engagement notifications (called at the end of
    /// scheduleTodaysEngagementNotifications, plus directly whenever 16b/16c
    /// change what should fire). Always clears today's three potential slots
    /// first, so toggling off or dropping 3x -> 1x removes stale pendings.
    /// The payload is just the line itself -- no title, no "tap to open"
    /// filler, per 16c's preview.
    func scheduleAffirmationReminders() async {
        let date = todayKey()
        let identifiers = (0..<3).map { "affirmation-\($0)-\(date)" }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        guard affirmationRemindersEnabled else { return }

        let lines = await affirmationCandidateLines(for: date)
        guard !lines.isEmpty else { return }
        let picked = pickAffirmationLines(from: lines, count: affirmationRemindersPerDay)

        let calendar = Calendar.current
        for (index, line) in picked.enumerated() {
            var components = calendar.dateComponents([.year, .month, .day], from: Date())
            let minute = affirmationSlotMinute(index)
            components.hour = minute / 60
            components.minute = minute % 60
            guard let slotDate = calendar.date(from: components) else { continue }
            let content = UNMutableNotificationContent()
            content.body = line
            content.sound = .default
            await schedule(at: staggeredPastFixedSlots(slotDate), identifier: identifiers[index], content: content)
        }
        recordAffirmationUse(picked, on: date)
    }

    /// Candidate pool per the 16c source setting. Passive reads only --
    /// scheduling must never trigger (and thus never burn) a generation.
    private func affirmationCandidateLines(for date: String) async -> [String] {
        let source = affirmationSource
        var generated: [String] = []
        if source != .list, let today = try? await SupabaseClient.shared.fetchTodaysAffirmation(date: date) {
            generated = [today.text]
        }
        var list: [String] = []
        if source != .generated {
            list = ((try? await SupabaseClient.shared.fetchAffirmationLines()) ?? [])
                .filter(\.inRotation)
                .map(\.text)
        }
        // "Both interleaves" -- today's line leads (it's today's), then the list.
        return generated + list
    }

    /// 16c: "never repeating a line within 3 days." Lines used in the last
    /// 3 days are skipped while enough unused ones remain; with a pool
    /// smaller than that, reuse beats silence. Never duplicates a line
    /// within the same day -- with fewer distinct lines than slots, later
    /// slots simply don't fire.
    private func pickAffirmationLines(from lines: [String], count: Int) -> [String] {
        let recent = affirmationRecentUse()
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -3, to: Date()) ?? Date()
        let fresh = lines.filter { line in
            guard let usedKey = recent[line], let used = dateFromKey(usedKey) else { return true }
            return used < cutoff
        }
        let pool = fresh.isEmpty ? lines : fresh
        var picked: [String] = []
        for line in pool where picked.count < count {
            if !picked.contains(line) { picked.append(line) }
        }
        return picked
    }

    /// 16c: affirmation pushes stagger >= 60 min from any other fixed Soma
    /// slot so mornings (and evenings) never double-fire. Walks forward
    /// past each conflict; bounded so a pathological config can't loop.
    private func staggeredPastFixedSlots(_ date: Date) -> Date {
        let fixedMinutes = [
            Self.checklistBreakfastHour * 60,
            Self.middayMovementHour * 60,
            Self.checklistStepsHour * 60,
            Self.eveningWorkoutHour * 60 + Self.eveningWorkoutMinute,
            Self.progressCheckInHour * 60,
            Self.checklistEveningRecapHour * 60 + Self.checklistEveningRecapMinute,
        ]
        let calendar = Calendar.current
        var result = date
        for _ in 0..<12 {
            let minuteOfDay = calendar.component(.hour, from: result) * 60 + calendar.component(.minute, from: result)
            guard let conflict = fixedMinutes.first(where: { abs($0 - minuteOfDay) < 60 }) else { break }
            result = calendar.date(byAdding: .minute, value: (conflict + 60) - minuteOfDay, to: result) ?? result
        }
        return result
    }

    /// [line text: yyyy-MM-dd last scheduled] -- local-only usage memory
    /// backing the 3-day no-repeat rule, pruned past 7 days so it can't
    /// grow unbounded. Recorded at schedule time (delivery isn't
    /// observable for a local notification), which is the right
    /// approximation: a line scheduled today shouldn't be re-picked
    /// tomorrow whether or not the user saw it.
    private func affirmationRecentUse() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: affirmationRecentLinesKey) as? [String: String] ?? [:]
    }

    private func recordAffirmationUse(_ lines: [String], on date: String) {
        var recent = affirmationRecentUse()
        for line in lines { recent[line] = date }
        let calendar = Calendar.current
        let pruneCutoff = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        recent = recent.filter { _, value in
            guard let used = dateFromKey(value) else { return false }
            return used >= pruneCutoff
        }
        UserDefaults.standard.set(recent, forKey: affirmationRecentLinesKey)
    }

    private func dateFromKey(_ key: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.date(from: key)
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
        dateKey(for: Date())
    }

    private func dateKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: date)
    }
}
