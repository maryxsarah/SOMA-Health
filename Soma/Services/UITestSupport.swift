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
        defaults.set(true, forKey: "dashboardWidget.sportGoal")
        defaults.set(false, forKey: "dashboardWidget.photoProgress")
    }
    #else
    static let isActive = false
    static let isOnboardingDemo = false
    static let isOnboardingDemoResume = false
    static let onboardingSurveyStartStep: String? = nil
    static let stubbedSession: URLSession? = nil
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
    /// J14: catalog dark until the user flips the beta toggle in Profile.
    case betaGate

    static var current: FixtureScenario {
        ProcessInfo.processInfo.environment["UITEST_SCENARIO"]
            .flatMap(FixtureScenario.init(rawValue:)) ?? .catalogOpen
    }

    var hasActiveGoal: Bool {
        switch self {
        case .catalogOpen, .customCoachFlow, .betaGate: false
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
        case .catalogOpen, .customCoachFlow, .betaGate: 0
        case .activeGoalDay6: 6
        case .activeGoalWeek2, .customGoalWeek2: 10
        case .activeGoalWeek4Slipped: 27
        case .activeGoalDay28, .activeGoalDay28Rest: 28
        case .activeGoalAtEta: 70
        }
    }

    var promoDismissedAtLaunch: Bool {
        switch self {
        case .catalogOpen, .customCoachFlow, .betaGate: false
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
        case .catalogOpen, .customCoachFlow, .betaGate, .customGoalWeek2:
            return []
        case .activeGoalDay6:
            return [row("m-1", "baseline", 42, daysAgo: 6)]
        case .activeGoalWeek2:
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

    /// Three past sessions for the coach's-task hub ("3 of 16"); none today,
    /// so Home still offers "Start workout".
    static var customGoalPastLogs: [[String: Any]] {
        [1, 3, 5].enumerated().map { index, daysAgo in
            ["id": "wl-seed-\(index)",
             "date": day(fromNow: -daysAgo),
             "title": "Coach Alex's task",
             "body_part": "legs",
             "category": "moderate",
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
                    "exercises": [planExercise],
                ]],
                "cool_down": [planExercise],
                "goal_block": ["kind": "preset", "text": "plyo: box jumps, low dose"],
            ],
        ]]
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
    private static var betaOptedIn = false
    private static var loggedWorkouts: [[String: Any]] = []
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

        // Catalog. betaGate serves it dark until the beta toggle is on --
        // the same "empty fetch == off" contract the real RLS enforces.
        case path.hasSuffix("/rest/v1/sports"):
            let visible = scenario != .betaGate || Self.betaOptedIn
            return (visible ? FixtureData.sports : [], 200)
        case path.hasSuffix("/rest/v1/sport_goals"):
            let visible = scenario != .betaGate || Self.betaOptedIn
            return (visible ? FixtureData.sportGoals : [], 200)

        case path.hasSuffix("/rest/v1/beta_optins") && method == "GET":
            return (Self.betaOptedIn ? [["user_id": "00000000-0000-0000-0000-0000000000ff"]] : [], 200)
        case path.hasSuffix("/rest/v1/beta_optins") && method == "POST":
            Self.betaOptedIn = true
            return ([:] as [String: Any], 201)
        case path.contains("/rest/v1/beta_optins") && method == "DELETE":
            Self.betaOptedIn = false
            return ([:] as [String: Any], 204)

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

        // Home data
        case path.hasSuffix("/rest/v1/daily_recommendation"):
            return ([FixtureData.recommendation(scenario: scenario, requested: Self.requestedCategory)], 200)
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
        case path.hasSuffix("/rest/v1/workout_log") && method == "POST":
            Self.loggedWorkouts.append([
                "id": "wl-\(Self.loggedWorkouts.count + 1)",
                "date": requestBody["date"] as? String ?? FixtureData.today,
                "title": requestBody["title"] as? String ?? "Workout",
                "body_part": requestBody["body_part"] as? String ?? "full_body",
                "category": requestBody["category"] as? String ?? "moderate",
                "completed_at": FixtureData.iso(daysAgo: 0),
            ])
            return ([:] as [String: Any], 201)
        case path.contains("/rest/v1/workout_log"):
            let seeded = scenario == .customGoalWeek2 ? FixtureData.customGoalPastLogs : []
            return (filterByDate(seeded + Self.loggedWorkouts, query: query), 200)

        // Paywall bypass: far-future referral bonus means the detail sheet
        // never routes through Superwall in tests.
        case path.hasSuffix("/rest/v1/users") && method == "GET":
            return ([["referral_bonus_until": "2099-01-01T00:00:00Z"]], 200)

        case path.hasSuffix("/functions/v1/generate-recommendation"):
            return (FixtureData.recommendation(scenario: scenario, requested: Self.requestedCategory), 200)

        // Real row (matches the seeded DB exactly) so ExerciseDetailView's
        // image fetch -- unstubbed, goes over real network -- loads a real photo.
        case path.contains("/rest/v1/exercise_library"):
            return ([FixtureData.exerciseLibraryRow], 200)

        // Everything else: harmless empties in the right container shape.
        case method == "GET" && path.contains("/rest/v1/"):
            return ([], 200)
        default:
            return ([:] as [String: Any], 200)
        }
    }
}

#endif
