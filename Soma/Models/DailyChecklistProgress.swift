import Foundation

/// Pure aggregation feeding HomeView's daily checklist card -- same
/// "compute from real inputs, no hidden state" shape as
/// NutritionDayProgress.compute. Two entry points: computeOnboarding for a
/// brand-new user's one-time guided list, computeStandard for the
/// recurring daily set every other user sees. HomeView decides which one
/// to call by checking whether every onboarding item is already checked
/// (DailyChecklistProgress.isOnboardingComplete).
struct DailyChecklistProgress {
    let items: [DailyChecklistItem]
    /// Day-over-day streak of fully-completed days, counting backward from
    /// today (today counts only once it's itself fully checked). Computed
    /// from consecutive `__day_complete__` marker dates -- see the
    /// migration's own comment on why this can't be recomputed from raw
    /// logs after the fact.
    let streak: Int

    var checkedCount: Int { items.filter(\.isChecked).count }
    var totalCount: Int { items.count }
    var isComplete: Bool { totalCount > 0 && checkedCount == totalCount }
    var fraction: Double { totalCount > 0 ? Double(checkedCount) / Double(totalCount) : 0 }

    // MARK: - Onboarding mode

    struct OnboardingInputs {
        var hasGoalsAndWeight: Bool
        var kitchenEquipmentAcknowledged: Bool
        var healthKitConnected: Bool
        var notificationsEnabled: Bool
        var hasReviewedFirstPlan: Bool
        var hasLoggedFirstWorkout: Bool
        var hasLoggedFirstMeal: Bool
        var hasSeenHowSomaWorks: Bool
    }

    /// True once every onboarding item would already show checked --
    /// HomeView uses this (not a separate stored flag) to decide when to
    /// stop showing onboarding mode and switch to computeStandard
    /// permanently, so the two modes can never disagree about which one
    /// is "supposed" to be showing.
    static func isOnboardingComplete(_ inputs: OnboardingInputs) -> Bool {
        computeOnboarding(inputs).isComplete
    }

    static func computeOnboarding(_ inputs: OnboardingInputs) -> DailyChecklistProgress {
        let items = [
            DailyChecklistItem(
                key: "onboarding_goal_profile",
                title: String(localized: "dailyChecklist.onboarding.goalProfile.title", defaultValue: "Set your goal & profile", comment: "Onboarding checklist item title"),
                subtitle: String(localized: "dailyChecklist.onboarding.goalProfile.subtitle", defaultValue: "Weight, goal, and the basics Soma tailors your plan from.", comment: "Onboarding checklist item subtitle"),
                isChecked: inputs.hasGoalsAndWeight,
                isManual: false, deepLink: .profileGoals, daysUntilNextAvailable: nil
            ),
            DailyChecklistItem(
                key: "onboarding_kitchen_equipment",
                title: String(localized: "dailyChecklist.onboarding.kitchenEquipment.title", defaultValue: "Set your kitchen equipment", comment: "Onboarding checklist item title"),
                subtitle: String(localized: "dailyChecklist.onboarding.kitchenEquipment.subtitle", defaultValue: "So meal ideas only ever use what you actually have.", comment: "Onboarding checklist item subtitle"),
                isChecked: inputs.kitchenEquipmentAcknowledged,
                isManual: true, deepLink: .profileKitchenEquipment, daysUntilNextAvailable: nil
            ),
            DailyChecklistItem(
                key: "onboarding_healthkit",
                title: String(localized: "dailyChecklist.onboarding.healthkit.title", defaultValue: "Connect a health source", comment: "Onboarding checklist item title"),
                subtitle: String(localized: "dailyChecklist.onboarding.healthkit.subtitle", defaultValue: "Apple Health, Whoop, or Oura -- powers your daily readiness.", comment: "Onboarding checklist item subtitle"),
                isChecked: inputs.healthKitConnected,
                isManual: false, deepLink: .connectDevices, daysUntilNextAvailable: nil
            ),
            DailyChecklistItem(
                key: "onboarding_notifications",
                title: String(localized: "dailyChecklist.onboarding.notifications.title", defaultValue: "Enable notifications", comment: "Onboarding checklist item title"),
                subtitle: String(localized: "dailyChecklist.onboarding.notifications.subtitle", defaultValue: "So your morning plan actually reaches you.", comment: "Onboarding checklist item subtitle"),
                isChecked: inputs.notificationsEnabled,
                isManual: false, deepLink: .enableNotifications, daysUntilNextAvailable: nil
            ),
            DailyChecklistItem(
                key: "onboarding_review_plan",
                title: String(localized: "dailyChecklist.onboarding.reviewPlan.title", defaultValue: "Review your first plan", comment: "Onboarding checklist item title"),
                subtitle: String(localized: "dailyChecklist.onboarding.reviewPlan.subtitle", defaultValue: "See why Soma suggested today's session.", comment: "Onboarding checklist item subtitle"),
                isChecked: inputs.hasReviewedFirstPlan,
                isManual: false, deepLink: .startWorkout, daysUntilNextAvailable: nil
            ),
            DailyChecklistItem(
                key: "onboarding_first_workout",
                title: String(localized: "dailyChecklist.onboarding.firstWorkout.title", defaultValue: "Log your first workout", comment: "Onboarding checklist item title"),
                subtitle: String(localized: "dailyChecklist.onboarding.firstWorkout.subtitle", defaultValue: "Follow today's plan, or log your own activity.", comment: "Onboarding checklist item subtitle"),
                isChecked: inputs.hasLoggedFirstWorkout,
                // Was .startWorkout -- identical to "Review your first
                // plan" above, which routed both through
                // openTodaysWorkoutDetail()'s "already logged" branches
                // only. For a new user (todaysWorkoutLog == nil, the
                // whole premise of this row existing), that fell through
                // to a CompletedWorkoutView sheet guarded on a log that
                // doesn't exist -- a blank page. This item's real
                // destination is the manual-logging form, always
                // presentable regardless of what's loaded elsewhere.
                isManual: false, deepLink: .logWorkout, daysUntilNextAvailable: nil
            ),
            DailyChecklistItem(
                key: "onboarding_first_meal",
                title: String(localized: "dailyChecklist.onboarding.firstMeal.title", defaultValue: "Log your first meal", comment: "Onboarding checklist item title"),
                subtitle: String(localized: "dailyChecklist.onboarding.firstMeal.subtitle", defaultValue: "Type it, dictate it, or use \"What can I make?\"", comment: "Onboarding checklist item subtitle"),
                isChecked: inputs.hasLoggedFirstMeal,
                isManual: false, deepLink: .logMeal, daysUntilNextAvailable: nil
            ),
            DailyChecklistItem(
                key: "onboarding_how_soma_works",
                title: String(localized: "dailyChecklist.onboarding.howSomaWorks.title", defaultValue: "See how Soma works", comment: "Onboarding checklist item title"),
                subtitle: String(localized: "dailyChecklist.onboarding.howSomaWorks.subtitle", defaultValue: "A 6-card tour of what's actually in the app.", comment: "Onboarding checklist item subtitle"),
                isChecked: inputs.hasSeenHowSomaWorks,
                // Was isManual + .healthDashboard -- tapping used to mark
                // this complete instantly (before showing anything real)
                // and just opened the Dashboard. Now opens the actual
                // tour (HowSomaWorksTourView); completion happens only
                // once its final card's action fires.
                isManual: false, deepLink: .howSomaWorks, daysUntilNextAvailable: nil
            ),
        ]
        // Onboarding mode has no daily streak of its own -- it's a
        // one-time list, not a recurring day. 0 reads as "no streak yet,"
        // never fabricated.
        return DailyChecklistProgress(items: items, streak: 0)
    }

    // MARK: - Standard daily mode

    struct StandardInputs {
        var mealLoggedToday: Bool
        var targetProteinG: Int?
        var targetCarbsG: Int?
        var todaysSteps: Int?
        var stepGoal: Int
        var moodLoggedToday: Bool
        var workoutLoggedToday: Bool
        /// Most recent date (yyyy-MM-dd) the progress-picture row was
        /// checked, if ever -- drives both the 7-day cadence and the
        /// "next in N days" copy.
        var lastProgressPictureDate: String?
        var today: Date
    }

    static func computeStandard(_ inputs: StandardInputs, streak: Int) -> DailyChecklistProgress {
        var items: [DailyChecklistItem] = []

        let macroClause: String
        if let protein = inputs.targetProteinG, let carbs = inputs.targetCarbsG {
            macroClause = String(localized: "dailyChecklist.standard.breakfast.macroSubtitle", defaultValue: "~\(protein)g protein, \(carbs)g carbs to stay fueled and full.", comment: "Standard-mode checklist item subtitle: today's remaining protein/carb targets")
        } else {
            macroClause = String(localized: "dailyChecklist.standard.breakfast.noTargetSubtitle", defaultValue: "Log what you eat to keep today's bars filling in.", comment: "Standard-mode checklist item subtitle shown when no macro targets are on file")
        }
        items.append(DailyChecklistItem(
            key: "log_breakfast",
            title: String(localized: "dailyChecklist.standard.breakfast.title", defaultValue: "Log breakfast", comment: "Standard-mode checklist item title"),
            subtitle: macroClause,
            isChecked: inputs.mealLoggedToday,
            isManual: false, deepLink: .logMeal, daysUntilNextAvailable: nil
        ))

        let stepsSubtitle: String
        if let steps = inputs.todaysSteps {
            stepsSubtitle = String(localized: "dailyChecklist.standard.steps.progressSubtitle", defaultValue: "\(steps.formatted()) / \(inputs.stepGoal.formatted()) steps today.", comment: "Standard-mode checklist item subtitle: steps taken vs today's step goal")
        } else {
            stepsSubtitle = String(localized: "dailyChecklist.standard.steps.noDataSubtitle", defaultValue: "Target: \(inputs.stepGoal.formatted()) steps -- connect Apple Health to track it.", comment: "Standard-mode checklist item subtitle shown when no step data is available")
        }
        items.append(DailyChecklistItem(
            key: "hit_step_goal",
            title: String(localized: "dailyChecklist.standard.steps.title", defaultValue: "Hit your step goal", comment: "Standard-mode checklist item title"),
            subtitle: stepsSubtitle,
            isChecked: (inputs.todaysSteps ?? 0) >= inputs.stepGoal,
            isManual: false, deepLink: .healthDashboard, daysUntilNextAvailable: nil
        ))

        items.append(DailyChecklistItem(
            key: "mood_checkin",
            title: String(localized: "dailyChecklist.standard.mood.title", defaultValue: "Check how you're feeling", comment: "Standard-mode checklist item title"),
            subtitle: String(localized: "dailyChecklist.standard.mood.subtitle", defaultValue: "One tap -- helps Soma see what's actually working.", comment: "Standard-mode checklist item subtitle"),
            isChecked: inputs.moodLoggedToday,
            isManual: false, deepLink: .moodCheckIn, daysUntilNextAvailable: nil
        ))

        items.append(DailyChecklistItem(
            key: "complete_workout",
            title: String(localized: "dailyChecklist.standard.workout.title", defaultValue: "Complete today's workout", comment: "Standard-mode checklist item title"),
            subtitle: String(localized: "dailyChecklist.standard.workout.subtitle", defaultValue: "Follow today's plan, or log your own activity.", comment: "Standard-mode checklist item subtitle"),
            isChecked: inputs.workoutLoggedToday,
            isManual: false, deepLink: .startWorkout, daysUntilNextAvailable: nil
        ))

        let (showsToday, daysUntilNext, isCheckedToday) = progressPictureState(
            lastDate: inputs.lastProgressPictureDate, today: inputs.today
        )
        if showsToday {
            items.append(DailyChecklistItem(
                key: "progress_picture",
                title: String(localized: "dailyChecklist.standard.progressPicture.title", defaultValue: "Progress picture", comment: "Standard-mode checklist item title"),
                subtitle: isCheckedToday
                    ? String(localized: "dailyChecklist.standard.progressPicture.doneSubtitle", defaultValue: "Done for this week -- see you next week.", comment: "Standard-mode checklist item subtitle shown once this week's progress picture is done")
                    : String(localized: "dailyChecklist.standard.progressPicture.dueSubtitle", defaultValue: "Compare against your goal photo -- a weekly gut-check that keeps you coming back.", comment: "Standard-mode checklist item subtitle shown when this week's progress picture is due"),
                isChecked: isCheckedToday,
                isManual: true, deepLink: .progressPicture, daysUntilNextAvailable: nil
            ))
        } else {
            items.append(DailyChecklistItem(
                key: "progress_picture",
                title: String(localized: "dailyChecklist.standard.progressPicture.title", defaultValue: "Progress picture", comment: "Standard-mode checklist item title"),
                subtitle: daysUntilNext == 1
                    ? String(localized: "dailyChecklist.standard.progressPicture.nextInOneDay", defaultValue: "Next one in \(daysUntilNext) day.", comment: "Standard-mode checklist item subtitle: progress picture becomes due in exactly 1 day")
                    : String(localized: "dailyChecklist.standard.progressPicture.nextInDays", defaultValue: "Next one in \(daysUntilNext) days.", comment: "Standard-mode checklist item subtitle: progress picture becomes due in more than 1 day"),
                isChecked: true, // Not actionable right now -- shown as a settled, upcoming moment, not an open task.
                isManual: true, deepLink: nil, daysUntilNextAvailable: daysUntilNext
            ))
        }

        return DailyChecklistProgress(items: items, streak: streak)
    }

    /// Once every 7 days, not calendar-week-aligned -- keyed off the last
    /// completion date so "every 7 days from whenever you actually last
    /// did it" holds regardless of which weekday that was.
    /// Returns (isActionableToday, daysUntilNextAvailable, isCheckedToday).
    private static func progressPictureState(lastDate: String?, today: Date) -> (Bool, Int, Bool) {
        guard let lastDate, let last = Self.parseDate(lastDate) else { return (true, 0, false) }
        let calendar = Calendar.current
        let daysSince = calendar.dateComponents([.day], from: calendar.startOfDay(for: last), to: calendar.startOfDay(for: today)).day ?? 7
        if daysSince == 0 {
            return (true, 0, true) // Checked earlier today.
        }
        if daysSince >= 7 {
            return (true, 0, false) // Due again.
        }
        return (false, 7 - daysSince, false)
    }

    private static func parseDate(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.date(from: string)
    }

    /// Consecutive `__day_complete__` dates ending at (or one before)
    /// `today` -- a gap of even one day resets the count to 0 from that
    /// point, "don't break the chain." `completedDates` need not be
    /// sorted or deduped; both are handled here.
    static func computeStreak(completedDates: [String], today: Date) -> Int {
        let uniqueDates = Set(completedDates)
        let calendar = Calendar.current
        var streak = 0
        var cursor = calendar.startOfDay(for: today)
        let todayString = Self.dateString(cursor)
        // If today isn't complete yet, the streak is "as of yesterday" --
        // still real, just doesn't advance until today locks in too.
        if !uniqueDates.contains(todayString) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = yesterday
        }
        while uniqueDates.contains(Self.dateString(cursor)) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: date)
    }
}
