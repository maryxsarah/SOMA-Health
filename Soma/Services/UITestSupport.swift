import Foundation

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
        ProcessInfo.processInfo.arguments.contains("--ui-test-fixtures")
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
        KeychainStore().save(StoredSession(
            userID: "00000000-0000-0000-0000-0000000000ff",
            accessToken: "fixture-access-token",
            refreshToken: "fixture-refresh-token",
            expiresAt: Date().addingTimeInterval(10 * 365 * 86400)
        ))
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: "com.soma.app.onboardingComplete")
        // J1 exercises the first-tap beta popup; every other journey skips
        // straight past the promo affordances.
        let firstRun = FixtureScenario.current == .catalogOpen
        defaults.set(!firstRun, forKey: "sportGoalPromoDismissed")
        defaults.set(!firstRun, forKey: "sportGoalOnboardingSeen")
    }
    #else
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
    /// J2: active jump goal in week 2 + today's AI plan carrying a goal block.
    case activeGoalWeek2
    /// J3: week 4, ETA slipped +9 days (2 missed + 3 low-readiness).
    case activeGoalWeek4Slipped
    /// J4: day 28, baseline confirmed, checkpoint re-test open, moderate day.
    case activeGoalDay28
    /// J4 negative: same day-28 state on a requested rest day.
    case activeGoalDay28Rest

    static var current: FixtureScenario {
        ProcessInfo.processInfo.environment["UITEST_SCENARIO"]
            .flatMap(FixtureScenario.init(rawValue:)) ?? .catalogOpen
    }

    var hasActiveGoal: Bool { self != .catalogOpen }

    var recommendationCategory: String {
        self == .activeGoalDay28Rest ? "rest" : "moderate"
    }

    /// Days since the goal block started.
    var goalAgeDays: Int {
        switch self {
        case .catalogOpen: 0
        case .activeGoalWeek2: 10
        case .activeGoalWeek4Slipped: 27
        case .activeGoalDay28, .activeGoalDay28Rest: 28
        }
    }
}

// MARK: - Fixture data (PostgREST wire shapes)

/// All rows are built at request time so relative dates (week 4, day 28)
/// hold no matter when the test runs.
enum FixtureData {
    static let goalID = "00000000-0000-0000-0000-00000000aa01"
    static let userGoalID = "00000000-0000-0000-0000-00000000bb01"

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

    static let sports: [[String: Any]] = [
        ["id": "sp-volleyball", "name": "Volleyball", "variant": NSNull()],
    ]

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
            "target_table": [
                "bands": [
                    "novice": ["min": 10, "max": 55, "gain_low": 3, "gain_high": 6,
                               "horizon_weeks_low": 10, "horizon_weeks_high": 12],
                    "intermediate": ["min": 55, "max": 75, "gain_low": 2, "gain_high": 4,
                                     "horizon_weeks_low": 10, "horizon_weeks_high": 12],
                ],
            ],
        ],
    ]

    static func userGoal(scenario: FixtureScenario) -> [String: Any] {
        var row: [String: Any] = [
            "id": userGoalID,
            "goal_id": goalID,
            "kind": "preset",
            "target_kind": "metric",
            "status": "active",
            "baseline_value": 42,
            "target_low": 3,
            "target_high": 6,
            "created_at": iso(daysAgo: scenario.goalAgeDays),
            "eta_start": day(fromNow: 70 - scenario.goalAgeDays),
            "eta_end": day(fromNow: 84 - scenario.goalAgeDays),
            "phase": scenario.goalAgeDays > 21 ? "build" : "foundation",
        ]
        if scenario == .activeGoalWeek4Slipped {
            row["eta_slip_days"] = 9
            row["eta_slip_reason"] = "2 missed sessions + 3 low-readiness days"
        }
        return row
    }

    static func measurements(scenario: FixtureScenario) -> [[String: Any]] {
        func row(_ id: String, _ kind: String, _ value: Double, daysAgo: Int) -> [String: Any] {
            ["id": id, "user_goal_id": userGoalID, "kind": kind,
             "value": value, "measured_at": iso(daysAgo: daysAgo)]
        }
        switch scenario {
        case .catalogOpen:
            return []
        case .activeGoalWeek2:
            return [row("m-1", "baseline", 42, daysAgo: 10)]
        case .activeGoalWeek4Slipped:
            return [row("m-1", "baseline", 42, daysAgo: 27),
                    row("m-2", "baseline_confirm", 43, daysAgo: 22)]
        case .activeGoalDay28, .activeGoalDay28Rest:
            return [row("m-1", "baseline", 42, daysAgo: 28),
                    row("m-2", "baseline_confirm", 43, daysAgo: 23)]
        }
    }

    static func recommendation(scenario: FixtureScenario) -> [String: Any] {
        var row: [String: Any] = [
            "date": today,
            "category": scenario.recommendationCategory,
            "message": "Solid day for quality work.",
            "reason": "healthkit_medium",
            "data_confidence": "high",
            "sleep_cap_applied": false,
            "injury_cap_applied": false,
            "load_cap_applied": false,
        ]
        if scenario == .activeGoalDay28Rest {
            row["user_requested_category"] = "rest"
        }
        return row
    }

    static let planExercise: [String: Any] = [
        "name": "Box jump",
        "sets": 3,
        "reps": "5",
        "weight_guidance": "Bodyweight",
        "intensity": "Explosive, full recovery between sets",
        "duration_minutes": 8,
        "instructions": "Land soft, step down between reps.",
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

    /// The row create-goal answers with in J1 (mirrors the edge function's
    /// { created: true, goal } response).
    static var createdGoalResponse: [String: Any] {
        [
            "created": true,
            "goal": [
                "id": userGoalID,
                "goal_id": goalID,
                "kind": "preset",
                "target_kind": "metric",
                "status": "active",
                "baseline_value": 42,
                "target_low": 3,
                "target_high": 6,
                "created_at": iso(daysAgo: 0),
                "eta_start": day(fromNow: 70),
                "eta_end": day(fromNow: 84),
                "phase": "foundation",
            ] as [String: Any],
        ]
    }
}

// MARK: - URLProtocol stub

/// Routes every SupabaseClient request to a canned wire response. Mutable
/// state (created goal, logged workouts, inserted measurements) lives in
/// statics so a journey's writes are visible to its later reads.
final class FixtureURLProtocol: URLProtocol {
    private static let stateLock = NSLock()
    private static var goalCreated = false
    private static var loggedWorkouts: [[String: Any]] = []
    private static var insertedMeasurements: [[String: Any]] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let scenario = FixtureScenario.current
        let path = request.url?.path ?? ""
        let query = request.url?.query ?? ""
        let method = request.httpMethod ?? "GET"

        let body = route(scenario: scenario, path: path, query: query, method: method)

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

    private func route(
        scenario: FixtureScenario, path: String, query: String, method: String
    ) -> (payload: Any, status: Int) {
        Self.stateLock.lock()
        defer { Self.stateLock.unlock() }

        switch true {
        // Catalog
        case path.hasSuffix("/rest/v1/sports"):
            return (FixtureData.sports, 200)
        case path.hasSuffix("/rest/v1/sport_goals"):
            return (FixtureData.sportGoals, 200)

        // Goal rows
        case path.hasSuffix("/rest/v1/user_goal") && method == "GET":
            let hasGoal = scenario.hasActiveGoal || Self.goalCreated
            if query.contains("status=eq.active") {
                let age = Self.goalCreated && !scenario.hasActiveGoal ? FixtureScenario.catalogOpen : scenario
                return (hasGoal ? [FixtureData.userGoal(scenario: age)] : [], 200)
            }
            return ([], 200) // history
        case path.hasSuffix("/rest/v1/user_goal"): // PATCH lifecycle writes
            return ([:] as [String: Any], 204)

        case path.hasSuffix("/rest/v1/goal_measurement_log") && method == "GET":
            return (FixtureData.measurements(scenario: scenario) + Self.insertedMeasurements, 200)
        case path.hasSuffix("/rest/v1/goal_measurement_log") && method == "POST":
            Self.insertedMeasurements.append([
                "id": "m-new-\(Self.insertedMeasurements.count + 1)",
                "user_goal_id": FixtureData.userGoalID,
                "kind": "checkpoint",
                "value": 46,
                "measured_at": FixtureData.iso(daysAgo: 0),
            ])
            return ([:] as [String: Any], 201)

        case path.hasSuffix("/functions/v1/create-goal"):
            Self.goalCreated = true
            return (FixtureData.createdGoalResponse, 200)

        // Home data
        case path.hasSuffix("/rest/v1/daily_recommendation"):
            return ([FixtureData.recommendation(scenario: scenario)], 200)
        case path.hasSuffix("/rest/v1/daily_snapshot"):
            return ([], 200)
        case path.hasSuffix("/rest/v1/ai_workout_plan"):
            return (scenario == .activeGoalWeek2 ? FixtureData.todaysAIPlan : [], 200)

        // Workout log (J2 writes, Home/detail reads)
        case path.hasSuffix("/rest/v1/workout_log") && method == "POST":
            Self.loggedWorkouts.append([
                "id": "wl-\(Self.loggedWorkouts.count + 1)",
                "date": FixtureData.today,
                "title": "Lower body strength",
                "body_part": "legs",
                "category": "moderate",
                "completed_at": FixtureData.iso(daysAgo: 0),
            ])
            return ([:] as [String: Any], 201)
        case path.contains("/rest/v1/workout_log"):
            return (Self.loggedWorkouts, 200)

        // Paywall bypass: far-future referral bonus means the detail sheet
        // never routes through Superwall in tests.
        case path.hasSuffix("/rest/v1/users") && method == "GET":
            return ([["referral_bonus_until": "2099-01-01T00:00:00Z"]], 200)

        case path.hasSuffix("/functions/v1/set-recommendation-override"),
             path.hasSuffix("/functions/v1/generate-recommendation"):
            return (FixtureData.recommendation(scenario: scenario), 200)

        // Everything else: harmless empties in the right container shape.
        case method == "GET" && path.contains("/rest/v1/"):
            return ([], 200)
        default:
            return ([:] as [String: Any], 200)
        }
    }
}

#endif
