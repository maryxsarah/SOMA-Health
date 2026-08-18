import Foundation
import UIKit

/// Fixture harness for SomaUITests (see UITests/CASES.md). Active only in
/// DEBUG builds launched with `--ui-test-fixtures`; Release compiles to a
/// pair of constant nils, so nothing here can ever run in production.
///
/// Design: the whole app keeps talking to SupabaseClient exactly as in
/// production -- only the client's URLSession is swapped for one whose
/// URLProtocol answers with PostgREST/Edge-Function wire JSON. Decoding,
/// lenient-field handling, and every view's real data path stay exercised.
enum UITestSupport {
    #if DEBUG
    static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-test-fixtures") || isOnboardingDemo || isOnboardingDemoResume
    }

    /// Demo-recording mode (see `OnboardingDemoRecordingTests`): the
    /// network is still stubbed (never hits real Supabase), but
    /// `bootstrapIfNeeded()` below skips the signed-in shortcut so the app
    /// boots into the real `OnboardingView` instead of Home.
    static var isOnboardingDemo: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-test-onboarding-demo")
    }

    /// Fast-iteration variant of the above, for developing the recording
    /// script itself: seeds a signed-in session but leaves onboarding
    /// incomplete, which `AppState.init()` already resumes at Connect
    /// Device (its own "app was killed mid-flow" path) -- skips the ~10
    /// minute email-signup + 22-question survey prefix every retry.
    static var isOnboardingDemoResume: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-test-onboarding-demo-resume")
    }

    /// Onboarding survey screen tests (OnboardingSurveyScrollUITests): boots
    /// straight onto `OnboardingSurveyView` at a specific question, matching
    /// a `SurveyStep` case name (e.g. "dietType"), instead of replaying the
    /// ~17 preceding questions just to reach the one screen under test.
    static var onboardingSurveyStartStep: String? {
        ProcessInfo.processInfo.environment["UITEST_ONBOARDING_SURVEY_STEP"]
    }

    /// Boots straight into PostSetupFlowView (value names the step, e.g.
    /// "paywall") -- the onboarding-paywall matrix would otherwise need
    /// ~8 scripted taps through connect/notifications/consent to reach it.
    /// Requires --ui-test-onboarding-demo-resume (signed in, onboarding
    /// incomplete).
    static var postSetupStartStep: String? {
        ProcessInfo.processInfo.environment["UITEST_POSTSETUP"]
    }

    /// Mocked StoreKit entitlement for fixture runs -- the simulator has
    /// no real purchases, so subscription-dependent UI (trial banner,
    /// Subscription row, quota locks, Superwall gating) is otherwise
    /// untestable. Set via UITEST_SUBSCRIPTION: "trial" |
    /// "premium_monthly" | "premium_annual" | "free". Nil = don't mock.
    static var subscriptionMock: (isSubscribed: Bool, tier: String, isInTrial: Bool)? {
        guard isActive else { return nil }
        switch ProcessInfo.processInfo.environment["UITEST_SUBSCRIPTION"] {
        case "trial": return (true, "monthly", true)
        case "premium_monthly": return (true, "monthly", false)
        case "premium_annual": return (true, "annual", false)
        case "free": return (false, "free", false)
        default: return nil
        }
    }

    /// Session whose requests never leave the process. Nil when inactive.
    static var stubbedSession: URLSession? {
        guard isActive else { return nil }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FixtureURLProtocol.self]
        return URLSession(configuration: config)
    }

    /// Runs before AppState is constructed (SomaApp.init): fakes a signed-in
    /// Supabase session and pre-seeds the UserDefaults the scenario needs.
    static func bootstrapIfNeeded() {
        guard isActive else { return }
        // Animations only cost wall-clock and simulator memory here.
        UIView.setAnimationsEnabled(false)
        // Demo mode wants the REAL onboarding screens, not the signed-in
        // shortcut every other fixture scenario relies on -- skip the
        // session seed entirely and let OnboardingView show for real.
        // Keychain items survive `simctl uninstall`+reinstall (by design,
        // same as a real device), so an earlier `-resume` run's fake
        // session would otherwise leak into this one and skip straight
        // to Connect Device -- clear it explicitly every launch.
        guard !isOnboardingDemo else {
            KeychainStore().clear()
            return
        }
        KeychainStore().save(StoredSession(
            userID: "00000000-0000-0000-0000-0000000000ff",
            accessToken: "fixture-access-token",
            refreshToken: "fixture-refresh-token",
            expiresAt: Date().addingTimeInterval(10 * 365 * 86400)
        ))
        // Resume mode: signed in but deliberately NOT onboardingComplete,
        // so AppState.init()'s own "killed mid-flow" branch lands it at
        // Connect Device -- skips the signup+survey prefix for iterating
        // on just that screen.
        guard !isOnboardingDemoResume else { return }
        // Same idea as the resume guard above: leave onboardingComplete
        // unset so AppState.init() takes its "signed in, not complete"
        // branch, which onboardingSurveyStartStep then steers to .survey.
        guard onboardingSurveyStartStep == nil else { return }
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: "com.soma.app.onboardingComplete")
        let scenario = FixtureScenario.current
        defaults.set(scenario.promoDismissedAtLaunch, forKey: "sportGoalPromoDismissed")
        defaults.set(scenario.onboardingSeenAtLaunch, forKey: "sportGoalOnboardingSeen")
        // A LocalizationUITests run that failed mid-test can leave this
        // simulator stuck on a non-English language -- reset on every launch.
        defaults.removeObject(forKey: "com.soma.app.languageOverride")
        defaults.removeObject(forKey: "AppleLanguages")
        // Same idea: manual dev testing on a reused simulator can leave the
        // Home widget-visibility toggles off, silently hiding whichever
        // widget a UI test depends on -- force every toggle back to its
        // documented default (HomeView's own @AppStorage declarations) on
        // every fixture launch.
        defaults.set(true, forKey: "dashboardWidget.water")
        defaults.set(true, forKey: "dashboardWidget.sleep")
        defaults.set(true, forKey: "dashboardWidget.dailyTasks")
        defaults.set(true, forKey: "dashboardWidget.mood")
        defaults.set(true, forKey: "dashboardWidget.nutrition")
        defaults.set(true, forKey: "dashboardWidget.sportGoal")
        defaults.set(false, forKey: "dashboardWidget.photoProgress")
        defaults.set(true, forKey: "dashboardWidget.affirmation")
    }
    #else
    static let isActive = false
    static let isOnboardingDemo = false
    static let isOnboardingDemoResume = false
    static let onboardingSurveyStartStep: String? = nil
    static let stubbedSession: URLSession? = nil
    static let subscriptionMock: (isSubscribed: Bool, tier: String, isInTrial: Bool)? = nil
    static let postSetupStartStep: String? = nil
    static func bootstrapIfNeeded() {}
    #endif
}

#if DEBUG

// MARK: - Scenarios

/// One value per SomaUITests journey -- passed via the UITEST_SCENARIO
/// launch environment. Each scenario is just a different set of rows.
enum FixtureScenario: String {
    /// J1: catalog visible, no goal yet, beta popup not seen.
    case catalogOpen
    /// J2/J5: active jump goal in week 2 + today's AI plan with a goal block.
    case activeGoalWeek2
    /// J2b: same active goal, but today's AI plan carries no goal block --
    /// a regular training day (SGP-D1's other half, client side).
    case activeGoalNoBlockToday
    /// J3/J13: week 4, ETA slipped +9 days (2 missed + 3 low-readiness).
    case activeGoalWeek4Slipped
    /// J8: day 6, baseline logged, confirm window open.
    case activeGoalDay6
    /// J4/J9: day 28, baseline confirmed, checkpoint open, moderate day.
    case activeGoalDay28
    /// J4 negative: same day-28 state on a requested rest day.
    case activeGoalDay28Rest
    /// J11/J12: ETA reached, all pre-final measurements in, final open.
    case activeGoalAtEta
    /// J6: existing coach's-task goal, week 2, three sessions already done.
    case customGoalWeek2
    /// J7: catalog open, creating the coach's task from the form.
    case customCoachFlow

    static var current: FixtureScenario {
        ProcessInfo.processInfo.environment["UITEST_SCENARIO"]
            .flatMap(FixtureScenario.init(rawValue:)) ?? .catalogOpen
    }

    var hasActiveGoal: Bool {
        switch self {
        case .catalogOpen, .customCoachFlow: false
        default: true
        }
    }

    var isCustomGoal: Bool { self == .customGoalWeek2 }

    var defaultCategory: String {
        self == .activeGoalDay28Rest ? "rest" : "moderate"
    }

    /// Days since the goal block started.
    var goalAgeDays: Int {
        switch self {
        case .catalogOpen, .customCoachFlow: 0
        case .activeGoalDay6: 6
        case .activeGoalWeek2, .activeGoalNoBlockToday, .customGoalWeek2: 10
        case .activeGoalWeek4Slipped: 27
        case .activeGoalDay28, .activeGoalDay28Rest: 28
        case .activeGoalAtEta: 70
        }
    }

    var promoDismissedAtLaunch: Bool {
        switch self {
        case .catalogOpen, .customCoachFlow: false
        default: true
        }
    }

    /// J1 exercises the first-tap popup; the other front-door scenarios go
    /// straight to the sport list.
    var onboardingSeenAtLaunch: Bool { self != .catalogOpen }
}

/// Independent of FixtureScenario -- passed via the UITEST_SLEEP_SOURCE
/// launch environment so the Home sleep widget's wearable-connected state
/// (9g) is reachable without a dedicated scenario. Nil (the default)
/// reproduces today's real "nothing synced yet" behavior: daily_snapshot
/// empty, sleepWidgetTile falls through to the manual chip-log states.
enum SleepSourceFixture: String {
    case oura, whoop, healthkit

    static var current: SleepSourceFixture? {
        ProcessInfo.processInfo.environment["UITEST_SLEEP_SOURCE"]
            .flatMap(SleepSourceFixture.init(rawValue:))
    }
}

/// Independent of FixtureScenario -- passed via the UITEST_NUTRITION_STATE
/// launch environment so any sport-goal scenario can also carry a nutrition
/// day. Nil (the default) reproduces today's real behavior: nutrition_targets
/// empty, nutritionRow shows its CTA state.
enum NutritionFixtureState: String {
    case perfect, over, under

    static var current: NutritionFixtureState? {
        ProcessInfo.processInfo.environment["UITEST_NUTRITION_STATE"]
            .flatMap(NutritionFixtureState.init(rawValue:))
    }
}

// MARK: - Fixture data (PostgREST wire shapes)

/// All rows are built at request time so relative dates (week 4, day 28)
/// hold no matter when the test runs.
enum FixtureData {
    static let goalID = "00000000-0000-0000-0000-00000000aa01"
    static let userGoalID = "00000000-0000-0000-0000-00000000bb01"
    static let customGoalID = "00000000-0000-0000-0000-00000000cc01"

    static func iso(daysAgo: Int) -> String {
        ISO8601DateFormatter().string(from: Date().addingTimeInterval(TimeInterval(-daysAgo * 86400)))
    }

    static func day(fromNow days: Int) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f.string(from: Date().addingTimeInterval(TimeInterval(days * 86400)))
    }

    static var today: String { day(fromNow: 0) }

    // MARK: - Nutrition fixtures

    static func loggedAt(hoursAgo: Int) -> String {
        ISO8601DateFormatter().string(from: Date().addingTimeInterval(TimeInterval(-hoursAgo * 3600)))
    }

    static let nutritionTargetsRow: [String: Any] = [
        "daily_calories": 2200, "daily_protein_g": 160, "daily_carbs_g": 220, "daily_fat_g": 70,
        "computed_at": iso(daysAgo: 3), "basis": "mifflin_st_jeor:cut:activity=moderate:sex=female",
    ]

    /// Three calorie stories against the 2200 kcal target above -- perfect
    /// (right on target), over (a heavy day, protein still lags), under
    /// (light on volume even though the choices themselves score well).
    static func mealLogRows(state: NutritionFixtureState) -> [[String: Any]] {
        func row(_ id: String, _ label: String, cal: Int, protein: Int, carbs: Int, fat: Int,
                  score: Int, rationale: String, hoursAgo: Int) -> [String: Any] {
            ["id": id, "date": today, "label": label, "calories": cal, "protein_g": protein,
             "carbs_g": carbs, "fat_g": fat, "source": "manual", "logged_at": loggedAt(hoursAgo: hoursAgo),
             "score": score, "rationale": rationale]
        }
        switch state {
        case .perfect:
            return [
                row("ml-1", "Salmon, rice & greens", cal: 760, protein: 46, carbs: 72, fat: 26,
                    score: 9, rationale: "Great protein and healthy fats for dinner.", hoursAgo: 1),
                row("ml-2", "Grilled chicken bowl", cal: 640, protein: 55, carbs: 62, fat: 16,
                    score: 9, rationale: "Balanced macros, right on target for lunch.", hoursAgo: 6),
                row("ml-3", "Almonds & apple", cal: 410, protein: 10, carbs: 46, fat: 20,
                    score: 7, rationale: "Solid snack, keeps carbs and fat on pace.", hoursAgo: 3),
                row("ml-4", "Greek yogurt & berries", cal: 380, protein: 32, carbs: 40, fat: 9,
                    score: 8, rationale: "High protein, fits your macro split well.", hoursAgo: 11),
            ]
        case .over:
            return [
                row("ml-1", "Double cheeseburger & fries", cal: 980, protein: 42, carbs: 88, fat: 52,
                    score: 3, rationale: "Way over on fat, protein too low for the calories.", hoursAgo: 6),
                row("ml-2", "Pasta carbonara", cal: 820, protein: 30, carbs: 90, fat: 34,
                    score: 4, rationale: "Heavy on carbs and fat relative to today's target.", hoursAgo: 1),
                row("ml-3", "Ice cream", cal: 430, protein: 6, carbs: 52, fat: 20,
                    score: 2, rationale: "Mostly added sugar, barely moves protein.", hoursAgo: 3),
                row("ml-4", "Bagel with cream cheese", cal: 520, protein: 18, carbs: 68, fat: 20,
                    score: 5, rationale: "Fine as breakfast, but sets up a heavy day.", hoursAgo: 12),
            ]
        case .under:
            return [
                row("ml-1", "Grilled fish & veggies", cal: 720, protein: 50, carbs: 35, fat: 26,
                    score: 8, rationale: "Well balanced, just not enough volume today.", hoursAgo: 1),
                row("ml-2", "Small salad with chicken", cal: 380, protein: 32, carbs: 20, fat: 16,
                    score: 8, rationale: "Good protein, but a light lunch overall.", hoursAgo: 6),
                row("ml-3", "Protein bar", cal: 210, protein: 15, carbs: 22, fat: 8,
                    score: 7, rationale: "Decent macros, still leaves calories on the table.", hoursAgo: 9),
                row("ml-4", "Black coffee & banana", cal: 140, protein: 2, carbs: 33, fat: 1,
                    score: 6, rationale: "Light start, most of the day's target still ahead.", hoursAgo: 12),
            ]
        }
    }

    /// All 4 launch-catalog sports (matches the real seed,
    /// `20260803130000_seed_sport_goal_catalog.sql`) -- Volleyball alone
    /// only ever exercised the existing SGP-* journeys; the other three
    /// were missing from the fixture entirely, so any manual/automated
    /// `--ui-test-fixtures` run showed just one sport in the picker (6a)
    /// instead of the real catalog's four.
    static let sports: [[String: Any]] = [
        ["id": "sp-volleyball", "name": "Volleyball", "variant": NSNull()],
        ["id": "sp-hot-yoga", "name": "Hot Yoga", "variant": NSNull()],
        ["id": "sp-climbing", "name": "Climbing", "variant": NSNull()],
        ["id": "sp-padel", "name": "Padel", "variant": NSNull()],
    ]

    private static func simpleTargetTable(programName: String) -> [String: Any] {
        [
            "bands": [
                "novice": ["min": 10, "max": 55, "gain_low": 3, "gain_high": 6,
                           "horizon_weeks_low": 10, "horizon_weeks_high": 12, "program_name": "Foundation \(programName)"],
                "intermediate": ["min": 55, "max": 75, "gain_low": 2, "gain_high": 4,
                                 "horizon_weeks_low": 10, "horizon_weeks_high": 12, "program_name": "Builder \(programName)"],
            ],
        ]
    }

    /// Goal names/keys/units are real, lifted from the seed migration --
    /// only the target_table numbers are fixture-simplified placeholders
    /// (same posture the original Volleyball entry already had).
    static let sportGoals: [[String: Any]] = [
        [
            "id": goalID,
            "sport_id": "sp-volleyball",
            "key": "standing_vertical_jump",
            "name": "Standing vertical jump",
            "kind": "metric",
            "unit": "cm",
            "measurement_protocol": "Chalk your fingertips and stand side-on to a wall\nReach up flat-footed and mark your standing reach\nJump from a standstill and mark the highest touch — the difference is your jump",
            "noise_band": 2,
            "target_table": simpleTargetTable(programName: "Jump Block"),
        ],
        [
            "id": "volleyball_wall_pass_60s", "sport_id": "sp-volleyball", "key": "wall_pass_60s",
            "name": "Wall-pass count in 60 seconds", "kind": "metric", "unit": "count",
            "measurement_protocol": "Mark a line on a wall at 3.4 m and pass the ball against it above the line for 60 seconds.",
            "noise_band": 5, "target_table": simpleTargetTable(programName: "Pass Block"),
        ],
        [
            "id": "hot_yoga_forward_fold", "sport_id": "sp-hot-yoga", "key": "forward_fold",
            "name": "Forward-fold depth", "kind": "metric", "unit": "cm",
            "measurement_protocol": "Stand with feet hip-width, fold forward, and measure fingertip distance to the floor.",
            "noise_band": 2, "target_table": simpleTargetTable(programName: "Flexibility Block"),
        ],
        [
            "id": "hot_yoga_crow_pose", "sport_id": "sp-hot-yoga", "key": "crow_pose",
            "name": "Crow pose", "kind": "metric", "unit": "seconds",
            "measurement_protocol": "Hold crow pose (both feet off the ground) for as long as possible.",
            "noise_band": 2, "target_table": simpleTargetTable(programName: "Balance Block"),
        ],
        [
            "id": "climbing_dead_hang", "sport_id": "sp-climbing", "key": "dead_hang",
            "name": "Max dead hang", "kind": "metric", "unit": "seconds",
            "measurement_protocol": "Hang from a pull-up bar with a full grip for as long as possible.",
            "noise_band": 3, "target_table": simpleTargetTable(programName: "Grip Block"),
        ],
        [
            "id": "climbing_max_pullups", "sport_id": "sp-climbing", "key": "max_pullups",
            "name": "Max strict pull-ups", "kind": "metric", "unit": "reps",
            "measurement_protocol": "From a dead hang, pull chin over the bar with strict form -- no kipping.",
            "noise_band": 1, "target_table": simpleTargetTable(programName: "Pull Block"),
        ],
        [
            "id": "padel_wall_rally_60s", "sport_id": "sp-padel", "key": "wall_rally_60s",
            "name": "Wall-rally count in 60 seconds", "kind": "metric", "unit": "count",
            "measurement_protocol": "Rally against a wall for 60 seconds; count consecutive legal hits.",
            "noise_band": 4, "target_table": simpleTargetTable(programName: "Rally Block"),
        ],
        [
            "id": "padel_lateral_shuttle", "sport_id": "sp-padel", "key": "lateral_shuttle",
            "name": "Lateral shuttle time", "kind": "metric", "unit": "seconds",
            "measurement_protocol": "Sprint laterally between two markers 5 m apart, 5 round trips, time the total.",
            "noise_band": 1, "target_table": simpleTargetTable(programName: "Agility Block"),
        ],
    ]

    static func presetGoalRow(ageDays: Int, status: String = "active", pauseReason: String? = nil, slip: Bool = false) -> [String: Any] {
        var row: [String: Any] = [
            "id": userGoalID,
            "goal_id": goalID,
            "kind": "preset",
            "target_kind": "metric",
            "status": status,
            "baseline_value": 42,
            "target_low": 3,
            "target_high": 6,
            "program_name": "Foundation Jump Block",
            "created_at": iso(daysAgo: ageDays),
            "eta_start": day(fromNow: 70 - ageDays),
            "eta_end": day(fromNow: 84 - ageDays),
            "phase": ageDays > 21 ? "build" : "foundation",
        ]
        if let pauseReason { row["pause_reason"] = pauseReason }
        if slip {
            row["eta_slip_days"] = 9
            row["eta_slip_reason"] = "2 missed sessions + 3 low-readiness days"
        }
        return row
    }

    static func customGoalRow(ageDays: Int, status: String = "active", pauseReason: String? = nil) -> [String: Any] {
        var row: [String: Any] = [
            "id": customGoalID,
            "kind": "custom",
            "target_kind": "commitment",
            "status": status,
            "coach_name": "Alex",
            "given_text": "Approach jump needs more spring before the season",
            "workout_text": "3 rounds: 10 approach jumps, 8 depth drops, 10 banded squats. Full rest between rounds.",
            "duration_weeks": 8,
            "frequency_per_week": 2,
            "created_at": iso(daysAgo: ageDays),
            "recheck_date": day(fromNow: 56 - ageDays),
        ]
        if let pauseReason { row["pause_reason"] = pauseReason }
        return row
    }

    static func goalRow(scenario: FixtureScenario, status: String, pauseReason: String?) -> [String: Any] {
        scenario.isCustomGoal
            ? customGoalRow(ageDays: scenario.goalAgeDays, status: status, pauseReason: pauseReason)
            : presetGoalRow(ageDays: scenario.goalAgeDays, status: status, pauseReason: pauseReason,
                            slip: scenario == .activeGoalWeek4Slipped)
    }

    static func measurements(scenario: FixtureScenario) -> [[String: Any]] {
        func row(_ id: String, _ kind: String, _ value: Double, daysAgo: Int) -> [String: Any] {
            ["id": id, "user_goal_id": userGoalID, "kind": kind,
             "value": value, "measured_at": iso(daysAgo: daysAgo)]
        }
        switch scenario {
        case .catalogOpen, .customCoachFlow, .customGoalWeek2:
            return []
        case .activeGoalDay6:
            return [row("m-1", "baseline", 42, daysAgo: 6)]
        case .activeGoalWeek2, .activeGoalNoBlockToday:
            return [row("m-1", "baseline", 42, daysAgo: 10)]
        case .activeGoalWeek4Slipped:
            return [row("m-1", "baseline", 42, daysAgo: 27),
                    row("m-2", "baseline_confirm", 43, daysAgo: 22)]
        case .activeGoalDay28, .activeGoalDay28Rest:
            return [row("m-1", "baseline", 42, daysAgo: 28),
                    row("m-2", "baseline_confirm", 43, daysAgo: 23)]
        case .activeGoalAtEta:
            return [row("m-1", "baseline", 42, daysAgo: 70),
                    row("m-2", "baseline_confirm", 43, daysAgo: 65),
                    row("m-3", "checkpoint", 45, daysAgo: 42)]
        }
    }

    /// ~5 weeks of past workouts so the history calendar isn't empty on
    /// manual fixture runs; none today, Home still offers "Start workout".
    static var pastWorkoutLogs: [[String: Any]] {
        let entries: [(daysAgo: Int, title: String, bodyPart: String, category: String)] = [
            (1, "Lower body strength", "legs", "moderate"),
            (2, "Recovery mobility", "full_body", "light"),
            (4, "Upper body push", "chest", "moderate"),
            (6, "Lower body power", "legs", "push_hard"),
            (8, "Zone 2 run", "full_body", "light"),
            (10, "Full body strength", "full_body", "moderate"),
            (13, "Upper body pull", "back", "moderate"),
            (15, "Plyo + core", "legs", "push_hard"),
            (18, "Recovery mobility", "full_body", "light"),
            (20, "Lower body strength", "legs", "moderate"),
            (23, "Upper body push", "chest", "moderate"),
            (25, "Zone 2 run", "full_body", "light"),
            (28, "Full body strength", "full_body", "moderate"),
            (31, "Lower body power", "legs", "push_hard"),
            (34, "Upper body pull", "back", "moderate"),
        ]
        return entries.enumerated().map { index, entry in
            // "source" is REQUIRED by WorkoutLogEntry's synthesized Codable --
            // one row without it fails the whole array's decode, and the
            // callers' `try?` swallows that into an empty-looking history.
            ["id": "wl-hist-\(index)",
             "date": day(fromNow: -entry.daysAgo),
             "title": entry.title,
             "body_part": entry.bodyPart,
             "category": entry.category,
             "source": "ai_plan",
             "calories_estimated": false,
             "completed_at": iso(daysAgo: entry.daysAgo)]
        }
    }

    /// Matching daily_recommendation history (fetchRecentRecommendations)
    /// so past calendar days carry a category, not just workout dots.
    static func recommendationHistory(days: Int = 40) -> [[String: Any]] {
        (1...days).map { daysAgo in
            ["date": day(fromNow: -daysAgo),
             "category": ["moderate", "light", "push_hard", "rest"][daysAgo % 4],
             "message": "Solid day for quality work.",
             "reason": "healthkit_medium",
             "data_confidence": "high",
             "sleep_cap_applied": false,
             "injury_cap_applied": false,
             "load_cap_applied": false]
        }
    }

    /// Three past sessions for the coach's-task hub ("3 of 16"); none today,
    /// so Home still offers "Start workout".
    static var customGoalPastLogs: [[String: Any]] {
        [1, 3, 5].enumerated().map { index, daysAgo in
            ["id": "wl-seed-\(index)",
             "date": day(fromNow: -daysAgo),
             "title": "Coach Alex's task",
             "body_part": "legs",
             "category": "moderate",
             "source": "ai_plan",
             "calories_estimated": false,
             "completed_at": iso(daysAgo: daysAgo)]
        }
    }

    static func recommendation(scenario: FixtureScenario, requested: String?) -> [String: Any] {
        var row: [String: Any] = [
            "date": today,
            "category": requested ?? scenario.defaultCategory,
            "message": "Solid day for quality work.",
            "reason": "healthkit_medium",
            "data_confidence": "high",
            "sleep_cap_applied": false,
            "injury_cap_applied": false,
            "load_cap_applied": false,
        ]
        if let requested {
            row["user_requested_category"] = requested
        } else if scenario == .activeGoalDay28Rest {
            row["user_requested_category"] = "rest"
        }
        return row
    }

    /// A real plyo exercise actually mapped to the vertical jump goal
    /// (goal_exercise seed, 'plyo' role) -- name matches exerciseLibraryRow
    /// so ExerciseDetailView's name-based lookup finds real media.
    static let planExercise: [String: Any] = [
        "name": "Front Box Jump",
        "sets": 3,
        "reps": "5",
        "weight_guidance": "Bodyweight",
        "intensity": "Explosive, full recovery between sets",
        "duration_minutes": 8,
        "instructions": "Land soft, step down between reps.",
    ]

    /// Real exercise_library row, id/name/instructions/image_paths all
    /// copied verbatim from the seeded DB row -- exercise-media is a public
    /// bucket under an `exercises/` prefix (see the
    /// 20260731092000_fix_exercise_image_paths_prefix migration), so
    /// ExerciseDetailView's image fetch (URLSession.shared, not stubbed)
    /// loads the real photo over real network.
    static let exerciseLibraryRow: [String: Any] = [
        "id": "Front_Box_Jump",
        "name": "Front Box Jump",
        "force": "push",
        "level": "beginner",
        "mechanic": "compound",
        "equipment": "other",
        "primary_muscles": ["hamstrings"],
        "secondary_muscles": ["abductors", "adductors", "calves", "glutes", "quadriceps"],
        "instructions": [
            "Begin with a box of an appropriate height 1-2 feet in front of you. Stand with your feet should width apart. This will be your starting position.",
            "Perform a short squat in preparation for jumping, swinging your arms behind you.",
            "Rebound out of this position, extending through the hips, knees, and ankles to jump as high as possible. Swing your arms forward and up.",
            "Land on the box with the knees bent, absorbing the impact through the legs. You can jump from the box back to the ground, or preferably step down one leg at a time.",
        ],
        "category": "plyometrics",
        "image_paths": ["exercises/Front_Box_Jump/0.jpg", "exercises/Front_Box_Jump/1.jpg"],
    ]

    /// Real exercise_library rows, verbatim from the live seeded DB
    /// (2026-08-15, matching generate-gym-workout/templates.ts's newly
    /// hand-audited library_id mappings) -- lets todaysAIPlan below
    /// exercise a *gym-photo-shaped* plan (library_id + target_area set
    /// per exercise, exactly how generate-gym-workout emits them) with
    /// more than one distinct real photo, plus genuinely no-match cases,
    /// instead of every exercise silently resolving to the same fixture
    /// row regardless of which one was tapped. See exerciseLibraryRow
    /// above for the pre-existing name-lookup (AI-plan path) case.
    static let buttLiftBridgeRow: [String: Any] = [
        "id": "Butt_Lift_Bridge",
        "name": "Butt Lift (Bridge)",
        "force": "push",
        "level": "beginner",
        "mechanic": "isolation",
        "equipment": "body only",
        "primary_muscles": ["glutes"],
        "secondary_muscles": ["hamstrings"],
        "instructions": [
            "Lie flat on the floor on your back with the hands by your side and your knees bent. Your feet should be placed around shoulder width. This will be your starting position.",
            "Pushing mainly with your heels, lift your hips off the floor while keeping your back straight. Breathe out as you perform this part of the motion and hold at the top for a second.",
            "Slowly go back to the starting position as you breathe in.",
        ],
        "category": "strength",
        "image_paths": ["exercises/Butt_Lift_Bridge/0.jpg", "exercises/Butt_Lift_Bridge/1.jpg"],
    ]

    static let farmersWalkRow: [String: Any] = [
        "id": "Farmers_Walk",
        "name": "Farmer's Walk",
        "force": NSNull(),
        "level": "intermediate",
        "mechanic": "compound",
        "equipment": "other",
        "primary_muscles": ["forearms"],
        "secondary_muscles": ["abdominals", "glutes", "hamstrings", "lower back", "quadriceps", "traps"],
        "instructions": [
            "There are various implements that can be used for the farmers walk. These can also be performed with heavy dumbbells or short bars if these implements aren't available. Begin by standing between the implements.",
            "After gripping the handles, lift them up by driving through your heels, keeping your back straight and your head up.",
            "Walk taking short, quick steps, and don't forget to breathe. Move for a given distance, typically 50-100 feet, as fast as possible.",
        ],
        "category": "strongman",
        "image_paths": ["exercises/Farmers_Walk/0.jpg", "exercises/Farmers_Walk/1.jpg"],
    ]

    /// Keyed by exercise_library.id -- the exercise_library route below
    /// looks a request's `id=eq.X`/`name=eq.X` filter up here directly,
    /// same shape PostgREST would actually resolve it to. Absent = a
    /// genuine no-match, same as the real table (e.g. any of
    /// CONFIRMED_NO_LIBRARY_EQUIVALENT's names).
    static let exerciseLibraryRowsById: [String: [String: Any]] = [
        "Front_Box_Jump": exerciseLibraryRow,
        "Butt_Lift_Bridge": buttLiftBridgeRow,
        "Farmers_Walk": farmersWalkRow,
    ]

    static let exerciseLibraryRowsByName: [String: [String: Any]] = [
        "Front Box Jump": exerciseLibraryRow,
        "Butt Lift (Bridge)": buttLiftBridgeRow,
        "Farmer's Walk": farmersWalkRow,
    ]

    /// A gym-photo-shaped exercise entry -- library_id + target_area set,
    /// exactly like generate-gym-workout emits (never both nil the way
    /// the plain AI-plan path's `planExercise` is), so ExerciseDetailView
    /// exercises its id-first lookup and (for the no-match cases) its
    /// target_area-driven fallback categorization.
    static func gymExercise(name: String, libraryId: String?, targetArea: String) -> [String: Any] {
        var row: [String: Any] = [
            "name": name,
            "sets": 1,
            "reps": "10",
            "weight_guidance": "bodyweight",
            "intensity": "RPE 6/10",
            "duration_minutes": 2,
            "instructions": "",
            "target_area": targetArea,
        ]
        // Omitted entirely when nil, matching how templates.ts itself never
        // guesses a library_id -- the field is genuinely absent, not null.
        if let libraryId { row["library_id"] = libraryId }
        return row
    }

    /// ai_workout_plan row for J2 -- the plan genuinely carries the
    /// goal_block marker, so the GOAL BLOCK eyebrow is earned (BUG-77).
    static var todaysAIPlan: [[String: Any]] {
        [[
            "category": "moderate",
            "selected_title": "Lower body strength",
            "added_to_plan": true,
            "source": "suggestion",
            "plan": [
                "focus": "Lower body power",
                "warm_up": [planExercise],
                "blocks": [[
                    "name": "Block 1",
                    "rounds": 1,
                    "rest_between_rounds": "90s",
                    // planExercise covers the plain AI-plan (name-only
                    // lookup) media path; the four gymExercise entries
                    // below are library_id + target_area shaped exactly
                    // like generate-gym-workout emits them, covering: a
                    // second real photo (proves lookup isn't just always
                    // resolving to the one fixture row), and one fallback
                    // case per MediaFallbackCategory bucket.
                    "exercises": [
                        planExercise,
                        FixtureData.gymExercise(name: "Glute bridge", libraryId: "Butt_Lift_Bridge", targetArea: "Glutes, hamstrings"),
                        FixtureData.gymExercise(name: "Dumbbell farmer's hold", libraryId: "Farmers_Walk", targetArea: "Grip, core"),
                        FixtureData.gymExercise(name: "Wall sit", libraryId: nil, targetArea: "Quads"),
                        FixtureData.gymExercise(name: "Burpee", libraryId: nil, targetArea: "Full body, cardio"),
                        FixtureData.gymExercise(name: "Box breathing", libraryId: nil, targetArea: "Nervous system -- brings heart rate back down"),
                    ],
                ]],
                "cool_down": [planExercise],
                "goal_block": ["kind": "preset", "text": "plyo: box jumps, low dose"],
            ],
        ]]
    }

    /// Same shape as todaysAIPlan, minus the goal_block key -- an ordinary
    /// day for a user who still has an active goal (SGP-D1's other half).
    static var todaysAIPlanNoGoalBlock: [[String: Any]] {
        [[
            "category": "moderate",
            "selected_title": "Lower body strength",
            "added_to_plan": true,
            "source": "suggestion",
            "plan": [
                "focus": "Lower body power",
                "warm_up": [planExercise],
                "blocks": [[
                    "name": "Block 1",
                    "rounds": 1,
                    "rest_between_rounds": "90s",
                    "exercises": [planExercise],
                ]],
                "cool_down": [planExercise],
            ],
        ]]
    }

    /// A completed AI-plan workout from yesterday, `plan_snapshot` included
    /// -- lets CompletedWorkoutView's "What you did" per-exercise tap
    /// wiring (see ExerciseDetailView, and the CompletedWorkoutView.swift
    /// change that added it) be exercised in a UI test/manual run without
    /// needing to interactively complete today's workout first. Reuses
    /// todaysAIPlan's own exercise set, so the same real-photo/fallback-
    /// category coverage documented on that fixture applies here too.
    static var pastAIWorkoutLog: [String: Any] {
        [
            "id": "wl-seed-past-ai",
            "date": day(fromNow: -1),
            "title": "Lower body strength",
            "body_part": "lower_body",
            "category": "moderate",
            "source": "ai_plan",
            "completed_at": iso(daysAgo: 1),
            "plan_snapshot": (todaysAIPlan.first?["plan"]) as Any,
            // WorkoutLogEntry.caloriesEstimated is non-optional (default
            // `false` only covers Swift's memberwise init, not synthesized
            // Decodable -- a missing key here throws, silently failing the
            // whole [WorkoutLogEntry] array decode via callers' `try?` and
            // leaving DayDetailView/CompletedWorkoutView looking at an
            // empty log list instead of this row).
            "calories_estimated": false,
        ]
    }

    /// Same shape as todaysAIPlan, framed as a coach's verbatim block --
    /// lets the custom-goal "return and do today's session" demo show real
    /// exercises too, not just the preset path.
    static var customTodaysAIPlan: [[String: Any]] {
        [[
            "category": "moderate",
            "selected_title": "Coach Alex's task",
            "added_to_plan": true,
            "source": "suggestion",
            "plan": [
                "focus": "Coach-assigned session",
                "warm_up": [planExercise],
                "blocks": [[
                    "name": "Block 1",
                    "rounds": 1,
                    "rest_between_rounds": "90s",
                    "exercises": [planExercise],
                ]],
                "cool_down": [planExercise],
                "goal_block": ["kind": "custom", "text": "3 rounds: 10 approach jumps, 8 depth drops, 10 banded squats."],
            ],
        ]]
    }

    /// Ranged ai_workout_plan rows for the calendar strip's star badge --
    /// today and 2-days-ago carry a goal block, yesterday doesn't. Covers
    /// both preset (activeGoalWeek2) and custom (customGoalWeek2) goals.
    static func goalTrainingPlanRows(scenario: FixtureScenario) -> [[String: Any]] {
        guard scenario == .activeGoalWeek2 || scenario == .customGoalWeek2 else { return [] }
        let kind = scenario == .customGoalWeek2 ? "custom" : "preset"
        func row(daysAgo: Int, hasGoalBlock: Bool) -> [String: Any] {
            let goalBlock: Any = hasGoalBlock ? ["kind": kind, "text": "plyo: box jumps, low dose"] : NSNull()
            // Top-level "goal_block", matching the real endpoint's PostgREST
            // path-select alias (select=date,goal_block:plan->goal_block) --
            // not nested under "plan" the way the full plan document is.
            return [
                "date": day(fromNow: -daysAgo),
                "goal_block": goalBlock,
            ]
        }
        return [row(daysAgo: 0, hasGoalBlock: true), row(daysAgo: 1, hasGoalBlock: false), row(daysAgo: 2, hasGoalBlock: true)]
    }

    /// parse-goal-assignment's success payload -- "Coach Priya" differs from
    /// customGoalRow's manual "Alex" default so a test can tell them apart.
    static let parsedAssignment: [String: Any] = [
        "givenText": "Add spring before the season",
        "workoutText": "3 rounds: 10 approach jumps, 8 depth drops, 10 banded squats.",
        "coachName": "Coach Priya",
        "durationWeeks": 8,
        "frequencyPerWeek": 3,
        "scheduleRule": NSNull(),
        "scheduleDays": NSNull(),
        "courtDays": NSNull(),
    ]
}

// MARK: - URLProtocol stub

/// Routes every SupabaseClient request to a canned wire response. Mutable
/// state (created goal, status changes, rest-day override, logged workouts)
/// lives in statics so a journey's writes are visible to its later reads.
final class FixtureURLProtocol: URLProtocol {
    private static let stateLock = NSLock()
    private static var goalCreated = false
    private static var goalStatus = "active"
    private static var goalPauseReason: String?
    private static var requestedCategory: String?
    private static var loggedWorkouts: [[String: Any]] = []
    /// 16b: kept/custom affirmation lines saved during this fixture run --
    /// lets Keep/"Write your own"/hearts/delete round-trip offline.
    private static var savedAffirmations: [[String: Any]] = []
    /// Mood/sleep check-ins logged during this fixture run -- the widgets
    /// re-read after writing, and the generic empty-GET fallback made a
    /// successful tap look like nothing happened.
    private static var savedMood: [String: Any]?
    private static var savedSleep: [String: Any]?
    private static var insertedMeasurements: [[String: Any]] = []
    private static var loggedSleep: [String: Any]?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let scenario = FixtureScenario.current
        let path = request.url?.path ?? ""
        let query = request.url?.query?.removingPercentEncoding ?? ""
        let method = request.httpMethod ?? "GET"

        let body = route(scenario: scenario, path: path, query: query, method: method, requestBody: requestBodyJSON())

        let data = (try? JSONSerialization.data(withJSONObject: body.payload)) ?? Data("[]".utf8)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: body.status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    /// URLProtocol never sees `httpBody` -- only the stream.
    private func requestBodyJSON() -> [String: Any] {
        guard let stream = request.httpBodyStream else { return [:] }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 16 * 1024
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// PostgREST-style single `eq.` filter value for one field
    /// ("id=eq.Farmers_Walk" -> "Farmers_Walk"). `query` is already
    /// percent-decoded once by `startLoading` above; the `&`-split here
    /// only breaks on a literal ampersand, so a decoded value that itself
    /// contained `&`, `=`, or `+` would still misparse -- no exercise_library
    /// name does (verified against the real table), so that's a known,
    /// harmless limit of this fixture parser, not of the app's own encoding.
    private func queryFilterValue(_ query: String, field: String) -> String? {
        let prefix = "\(field)=eq."
        for param in query.components(separatedBy: "&") where param.hasPrefix(prefix) {
            return String(param.dropFirst(prefix.count))
        }
        return nil
    }

    /// PostgREST-style day filtering ("date=eq.X", "date=gte.A&date=lte.B").
    private func filterByDate(_ rows: [[String: Any]], query: String) -> [[String: Any]] {
        var eq: String?, gte: String?, lte: String?
        for param in query.components(separatedBy: "&") {
            if param.hasPrefix("date=eq.") { eq = String(param.dropFirst(8)) }
            if param.hasPrefix("date=gte.") { gte = String(param.dropFirst(9)) }
            if param.hasPrefix("date=lte.") { lte = String(param.dropFirst(9)) }
        }
        return rows.filter { row in
            guard let date = row["date"] as? String else { return true }
            if let eq, date != eq { return false }
            if let gte, date < gte { return false }
            if let lte, date > lte { return false }
            return true
        }
    }

    private func route(
        scenario: FixtureScenario, path: String, query: String, method: String, requestBody: [String: Any]
    ) -> (payload: Any, status: Int) {
        Self.stateLock.lock()
        defer { Self.stateLock.unlock() }

        switch true {
        // Onboarding-demo mode only: a signup response shaped exactly like
        // SupabaseClient's private AuthResponse (access_token/refresh_token/
        // expires_in/user.id/user.email) so the real signUpWithEmail() path
        // decodes it and treats the recording session as signed in, without
        // ever touching the real Supabase project.
        case UITestSupport.isOnboardingDemo && path.hasSuffix("/auth/v1/signup"):
            return ([
                "access_token": "demo-recording-access-token",
                "refresh_token": "demo-recording-refresh-token",
                "expires_in": 3600,
                "user": ["id": "00000000-0000-0000-0000-0000000000fe", "email": requestBody["email"] as? String ?? "demo@example.com"],
            ] as [String: Any], 200)

        // Same idea, for the "Log In" path OnboardingDemoRecordingTests
        // actually taps (EmailAuthView.signInWithEmail -> grant_type=
        // password) -- this was never stubbed, so every login attempt
        // decoded an empty body and looped forever on "Something went
        // wrong. Please try again." Gated to demo mode only -- otherwise
        // this would also intercept refreshSession()/signInWithApple()
        // under plain --ui-test-fixtures and hand back a session for the
        // wrong (demo) user id instead of the scenario's seeded one.
        case UITestSupport.isOnboardingDemo && path.hasSuffix("/auth/v1/token"):
            return ([
                "access_token": "demo-recording-access-token",
                "refresh_token": "demo-recording-refresh-token",
                "expires_in": 3600,
                "user": ["id": "00000000-0000-0000-0000-0000000000fe", "email": requestBody["email"] as? String ?? "demo@example.com"],
            ] as [String: Any], 200)

        // Plain fixture mode: sign-in/sign-up/refresh succeed offline with
        // the SEEDED user id (not the demo one), so manual login works too.
        case path.hasSuffix("/auth/v1/token") || path.hasSuffix("/auth/v1/signup"):
            return ([
                "access_token": "fixture-access-token",
                "refresh_token": "fixture-refresh-token",
                "expires_in": 10 * 365 * 86400,
                "user": ["id": "00000000-0000-0000-0000-0000000000ff", "email": requestBody["email"] as? String ?? "fixture@example.com"],
            ] as [String: Any], 200)

        // Catalog. Sport goals are live to everyone now (status='live'),
        // so the fixture always serves it -- no opt-in gate to model.
        case path.hasSuffix("/rest/v1/sports"):
            return (FixtureData.sports, 200)
        case path.hasSuffix("/rest/v1/sport_goals"):
            return (FixtureData.sportGoals, 200)

        // Goal rows
        case path.hasSuffix("/rest/v1/user_goal") && method == "GET":
            let exists = scenario.hasActiveGoal || Self.goalCreated
            let row: [String: Any]? = {
                guard exists else { return nil }
                if Self.goalCreated, !scenario.hasActiveGoal {
                    return scenario == .customCoachFlow
                        ? FixtureData.customGoalRow(ageDays: 0, status: Self.goalStatus, pauseReason: Self.goalPauseReason)
                        : FixtureData.presetGoalRow(ageDays: 0, status: Self.goalStatus, pauseReason: Self.goalPauseReason)
                }
                return FixtureData.goalRow(scenario: scenario, status: Self.goalStatus, pauseReason: Self.goalPauseReason)
            }()
            if query.contains("status=eq.active") {
                return (row.flatMap { Self.goalStatus == "active" ? [$0] : [] } ?? [], 200)
            }
            // History: everything that isn't active.
            return (row.flatMap { Self.goalStatus == "active" ? [] : [$0] } ?? [], 200)
        case path.contains("/rest/v1/user_goal") && method == "PATCH":
            if let status = requestBody["status"] as? String { Self.goalStatus = status }
            Self.goalPauseReason = requestBody["pause_reason"] as? String
            return ([:] as [String: Any], 204)

        case path.hasSuffix("/rest/v1/goal_measurement_log") && method == "GET":
            return (FixtureData.measurements(scenario: scenario) + Self.insertedMeasurements, 200)
        case path.hasSuffix("/rest/v1/goal_measurement_log") && method == "POST":
            Self.insertedMeasurements.append([
                "id": "m-new-\(Self.insertedMeasurements.count + 1)",
                "user_goal_id": FixtureData.userGoalID,
                "kind": requestBody["kind"] as? String ?? "checkpoint",
                "value": requestBody["value"] as? Double ?? 0,
                "measured_at": FixtureData.iso(daysAgo: 0),
            ])
            return ([:] as [String: Any], 201)

        case path.hasSuffix("/functions/v1/create-goal"):
            Self.goalCreated = true
            Self.goalStatus = "active"
            let goal = scenario == .customCoachFlow
                ? FixtureData.customGoalRow(ageDays: 0)
                : FixtureData.presetGoalRow(ageDays: 0)
            return (["created": true, "goal": goal], 200)

        // A fixed sentinel substring drives the low-confidence branch,
        // same idea as the real endpoint's isAssignment/confidence gate.
        case path.hasSuffix("/functions/v1/parse-goal-assignment"):
            let text = requestBody["text"] as? String ?? ""
            if text.contains("zzz-unparseable") {
                return (["parsed": NSNull(), "confidence": 0.2, "lowConfidence": true], 200)
            }
            return (["parsed": FixtureData.parsedAssignment, "confidence": 0.92, "lowConfidence": false], 200)

        // Home data. Both real query shapes carry a date filter (eq or
        // gte/lte), so day-filtering serves today AND history correctly.
        case path.hasSuffix("/rest/v1/daily_recommendation"):
            let todayRow = FixtureData.recommendation(scenario: scenario, requested: Self.requestedCategory)
            return (filterByDate(FixtureData.recommendationHistory() + [todayRow], query: query), 200)
        case path.hasSuffix("/rest/v1/daily_snapshot"):
            guard let source = SleepSourceFixture.current else { return ([], 200) }
            return ([[
                "source": source.rawValue, "recovery_score": NSNull(), "readiness_score": NSNull(),
                "hrv_ms": NSNull(), "sleep_hours": 6.3, "resting_hr": NSNull(),
                "strain_score": NSNull(), "stress_score": NSNull(),
                "sleep_light_hours": 2.3, "sleep_deep_hours": 1.7, "sleep_rem_hours": 2.1, "sleep_awake_hours": 0.2,
            ]], 200)

        // Manual sleep check-in (9g): real POST/GET round trip, same
        // "mutable state visible to a later read" shape as workout_log --
        // lets a test tap a chip and assert the widget actually flips to
        // the logged state, not just that both states can independently render.
        case path.hasSuffix("/rest/v1/daily_sleep_log") && method == "GET":
            return (Self.loggedSleep.map { [$0] } ?? [], 200)
        case path.hasSuffix("/rest/v1/daily_sleep_log") && method == "POST":
            Self.loggedSleep = [
                "date": FixtureData.today,
                "bucket": requestBody["bucket"] as? String ?? "seven_eight",
                "logged_at": FixtureData.iso(daysAgo: 0),
            ]
            return ([:] as [String: Any], 201)

        case path.hasSuffix("/rest/v1/ai_workout_plan"):
            if query.contains("date=gte.") {
                return (filterByDate(FixtureData.goalTrainingPlanRows(scenario: scenario), query: query), 200)
            }
            switch scenario {
            case .activeGoalWeek2: return (FixtureData.todaysAIPlan, 200)
            case .activeGoalNoBlockToday: return (FixtureData.todaysAIPlanNoGoalBlock, 200)
            case .customGoalWeek2: return (FixtureData.customTodaysAIPlan, 200)
            default: return ([], 200)
            }

        case path.hasSuffix("/rest/v1/nutrition_targets") && method == "GET":
            return (NutritionFixtureState.current != nil ? [FixtureData.nutritionTargetsRow] : [], 200)
        case path.hasSuffix("/rest/v1/meal_log") && method == "GET":
            guard let nutritionState = NutritionFixtureState.current else { return ([], 200) }
            return (filterByDate(FixtureData.mealLogRows(state: nutritionState), query: query), 200)

        // The rest-day override (C3): category=null clears the request.
        case path.hasSuffix("/functions/v1/set-recommendation-override"):
            Self.requestedCategory = requestBody["category"] as? String
            return (FixtureData.recommendation(scenario: scenario, requested: Self.requestedCategory), 200)

        // Workout log: writes recorded, reads day-filtered like PostgREST.
        // Carries plan_snapshot through when the caller sent one (real
        // AI-plan completions always do, see SupabaseClient.logWorkout) --
        // otherwise a completed-AI-plan round trip in this harness would
        // always decode a nil planSnapshot and CompletedWorkoutView could
        // never exercise its real "What you did" / per-exercise-tap path
        // in a UI test, only its manual/device-detected fallback.
        case path.hasSuffix("/rest/v1/workout_log") && method == "POST":
            var row: [String: Any] = [
                "id": "wl-\(Self.loggedWorkouts.count + 1)",
                "date": requestBody["date"] as? String ?? FixtureData.today,
                "title": requestBody["title"] as? String ?? "Workout",
                "body_part": requestBody["body_part"] as? String ?? "full_body",
                "category": requestBody["category"] as? String ?? "moderate",
                "source": requestBody["source"] as? String ?? "ai_plan",
                "calories_estimated": false,
                "completed_at": FixtureData.iso(daysAgo: 0),
            ]
            if let planSnapshot = requestBody["plan_snapshot"] {
                row["plan_snapshot"] = planSnapshot
            }
            Self.loggedWorkouts.append(row)
            return ([:] as [String: Any], 201)
        case path.contains("/rest/v1/workout_log"):
            // Custom-goal journeys keep exactly 3 seeded logs ("3 of 16");
            // activeGoalWeek2 additionally seeds yesterday's completed
            // AI-plan log (plan_snapshot included) so CompletedWorkoutView's
            // per-exercise tap is reachable without completing a workout.
            let seeded: [[String: Any]]
            switch scenario {
            case .customGoalWeek2: seeded = FixtureData.customGoalPastLogs
            case .activeGoalWeek2: seeded = FixtureData.pastWorkoutLogs + [FixtureData.pastAIWorkoutLog]
            default: seeded = FixtureData.pastWorkoutLogs
            }
            return (filterByDate(seeded + Self.loggedWorkouts, query: query), 200)

        // Paywall bypass: far-future referral bonus means the detail sheet
        // never routes through Superwall in tests. date_of_birth feeds the
        // history calendar's recurring birthday badge (Aug 16). The empty
        // collection keys are UserProfile's non-optional fields -- without
        // them fetchProfile's decode throws and try? call sites see nil.
        case path.hasSuffix("/rest/v1/users") && method == "GET":
            // The promo-chip scenario wants a REAL countdown ("5 DAYS"),
            // not the year-2099 paywall bypass every other scenario uses.
            var userRow: [String: Any] = [
                "date_of_birth": "1999-08-16",
                "contact_email": "fixture@soma4health.com",
                "country": "US", "city": "New York",
                "goals": [], "equipment": [], "household_equipment": [],
                "injury_tags": [], "injury_severity": [:], "injury_type": [:],
                "injury_pain_level": [:], "anchor_sessions": [],
            ]
            // Onboarding-paywall matrix suppresses the bonus entirely (it
            // would short-circuit presentOnboardingPaywall before
            // Superwall ever runs); the "free" chip scenario gets a real
            // 5-day countdown; everything else keeps the 2099 bypass.
            // Never `nil as Any` in this dict -- an Optional inside a
            // JSON object fails serialization and the whole stub row
            // silently degrades.
            if ProcessInfo.processInfo.environment["UITEST_NO_REFERRAL_BONUS"] == nil {
                userRow["referral_bonus_until"] = ProcessInfo.processInfo.environment["UITEST_SUBSCRIPTION"] == "free"
                    ? FixtureData.iso(daysAgo: -5)
                    : "2099-01-01T00:00:00Z"
            }
            return ([userRow], 200)

        // Account deletion: identities say "email" so no SIWA prompt runs
        // in tests; the function stub just confirms.
        case path.hasSuffix("/auth/v1/user") && method == "GET":
            return (["identities": [["provider": "email"]]] as [String: Any], 200)
        // Mood/sleep round-trip (the widgets refetch right after logging).
        case path.contains("/rest/v1/daily_mood") && method == "POST":
            Self.savedMood = [
                "date": requestBody["date"] as? String ?? FixtureData.today,
                "rating": requestBody["rating"] as? Int ?? 3,
                "logged_at": FixtureData.iso(daysAgo: 0),
            ]
            return ([:] as [String: Any], 201)
        case path.contains("/rest/v1/daily_mood") && method == "GET":
            return (Self.savedMood.map { [$0] } ?? [], 200)
        case path.contains("/rest/v1/daily_sleep_log") && method == "POST":
            Self.savedSleep = [
                "date": requestBody["date"] as? String ?? FixtureData.today,
                "bucket": requestBody["bucket"] as? String ?? "seven_eight",
                "logged_at": FixtureData.iso(daysAgo: 0),
            ]
            return ([:] as [String: Any], 201)
        case path.contains("/rest/v1/daily_sleep_log") && method == "GET":
            return (Self.savedSleep.map { [$0] } ?? [], 200)

        case path.hasSuffix("/functions/v1/get-referral-code"):
            return (["code": "SOMA-TEST7", "bonusDays": 7, "redemptionCount": 2] as [String: Any], 200)
        case path.hasSuffix("/functions/v1/redeem-referral-code"):
            return (["referral_bonus_until": "2099-01-01T00:00:00Z"] as [String: Any], 200)
        case path.hasSuffix("/functions/v1/delete-account"):
            return (["deleted": true] as [String: Any], 200)

        case path.hasSuffix("/functions/v1/generate-recommendation"):
            return (FixtureData.recommendation(scenario: scenario, requested: Self.requestedCategory), 200)

        // Affirmation widget/sheet (16a/16b) -- deterministic lines; the
        // passive daily_affirmation read falls through to the generic
        // empty-GET case below, which is what routes the client here.
        // forceRegenerate returns a different line with the quota spent,
        // so "Generate new" visibly works exactly once, like production.
        case path.hasSuffix("/functions/v1/generate-affirmation"):
            let force = requestBody["forceRegenerate"] as? Bool == true
            // Batch mode: extras land in the in-memory list, mirroring the
            // real function's server-side inserts.
            let count = min(max(requestBody["count"] as? Int ?? 1, 1), 10)
            // Real affirmations (first person, owned statements), not
            // placeholder filler -- the fixture sim is also the demo build.
            let pool = [
                "I am building strength with every honest effort.",
                "I show up for myself, even on slow days.",
                "I trust the work I put in today.",
                "I let rest count as part of my training.",
                "I am more consistent than I give myself credit for.",
                "I choose progress over perfection.",
                "I keep promises I make to my body.",
                "I am patient with what takes time.",
                "I make space for ten honest minutes today.",
            ]
            if count > 1 {
                for index in 1..<count {
                    Self.savedAffirmations.insert([
                        "id": "aff-gen-\(Self.savedAffirmations.count + index)",
                        "text": pool[(Self.savedAffirmations.count + index) % pool.count],
                        "source": "generated",
                        "in_rotation": true,
                        "created_at": FixtureData.iso(daysAgo: 0),
                    ], at: 0)
                }
            }
            return ([
                "text": force
                    ? "I am stronger than the excuse I almost made."
                    : "I don't need a perfect day -- just ten honest minutes.",
                "generatedAt": FixtureData.iso(daysAgo: 0),
                "regenerationAvailable": !force,
                "extraSavedCount": count - 1,
            ] as [String: Any], 200)

        // 16b list CRUD -- in-memory only. POST echoes the created row
        // (the client sends Prefer: return=representation and decodes
        // [AffirmationLine]; the generic default's `{}` broke that with
        // "data couldn't be read").
        case path.contains("/rest/v1/user_affirmations") && method == "POST":
            let row: [String: Any] = [
                "id": "aff-\(Self.savedAffirmations.count + 1)",
                "text": requestBody["text"] as? String ?? "",
                "source": requestBody["source"] as? String ?? "custom",
                "in_rotation": true,
                "created_at": FixtureData.iso(daysAgo: 0),
            ]
            Self.savedAffirmations.insert(row, at: 0)
            return ([row], 201)
        case path.contains("/rest/v1/user_affirmations") && method == "PATCH":
            if let id = queryFilterValue(query, field: "id"),
               let index = Self.savedAffirmations.firstIndex(where: { $0["id"] as? String == id }) {
                if let inRotation = requestBody["in_rotation"] as? Bool {
                    Self.savedAffirmations[index]["in_rotation"] = inRotation
                }
                if let text = requestBody["text"] as? String {
                    Self.savedAffirmations[index]["text"] = text
                }
            }
            return ([:] as [String: Any], 204)
        case path.contains("/rest/v1/user_affirmations") && method == "DELETE":
            if let id = queryFilterValue(query, field: "id") {
                Self.savedAffirmations.removeAll { $0["id"] as? String == id }
            }
            return ([:] as [String: Any], 204)
        case path.contains("/rest/v1/user_affirmations"):
            return (Self.savedAffirmations, 200)

        // Deterministic fake translation (real endpoint calls Claude) --
        // enough for a test to assert the swap actually happens.
        case path.hasSuffix("/functions/v1/translate-exercise-guide"):
            return ([
                "name": "Прыжок на тумбу",
                "instructions": ["Встаньте перед тумбой.", "Запрыгните, мягко приземлитесь.", "Сойдите по одной ноге."],
            ] as [String: Any], 200)

        // Query-aware: resolves `id=eq.X` (generate-gym-workout's path) or
        // `name=eq.X` (generate-workout-plan's path) the same way PostgREST
        // actually would, against the small real-row fixture set above --
        // matched exercises load a real photo (unstubbed, over real
        // network); anything else returns [], the same genuine no-match
        // shape as the real table, so ExerciseDetailView's fallback
        // illustration is reachable in tests too, not just the happy path.
        case path.contains("/rest/v1/exercise_library"):
            if let id = queryFilterValue(query, field: "id"), let row = FixtureData.exerciseLibraryRowsById[id] {
                return ([row], 200)
            }
            if let name = queryFilterValue(query, field: "name"), let row = FixtureData.exerciseLibraryRowsByName[name] {
                return ([row], 200)
            }
            return ([], 200)

        // Everything else: harmless empties in the right container shape.
        case method == "GET" && path.contains("/rest/v1/"):
            return ([], 200)
        default:
            return ([:] as [String: Any], 200)
        }
    }
}

#endif
