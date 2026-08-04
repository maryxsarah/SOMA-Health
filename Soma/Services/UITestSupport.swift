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
        // Animations only cost wall-clock and simulator memory here.
        UIView.setAnimationsEnabled(false)
        KeychainStore().save(StoredSession(
            userID: "00000000-0000-0000-0000-0000000000ff",
            accessToken: "fixture-access-token",
            refreshToken: "fixture-refresh-token",
            expiresAt: Date().addingTimeInterval(10 * 365 * 86400)
        ))
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: "com.soma.app.onboardingComplete")
        let scenario = FixtureScenario.current
        defaults.set(scenario.promoDismissedAtLaunch, forKey: "sportGoalPromoDismissed")
        defaults.set(scenario.onboardingSeenAtLaunch, forKey: "sportGoalOnboardingSeen")
    }
    #else
    static let isActive = false
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

        // Home data
        case path.hasSuffix("/rest/v1/daily_recommendation"):
            return ([FixtureData.recommendation(scenario: scenario, requested: Self.requestedCategory)], 200)
        case path.hasSuffix("/rest/v1/daily_snapshot"):
            return ([], 200)
        case path.hasSuffix("/rest/v1/ai_workout_plan"):
            return (scenario == .activeGoalWeek2 ? FixtureData.todaysAIPlan : [], 200)

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

        // Everything else: harmless empties in the right container shape.
        case method == "GET" && path.contains("/rest/v1/"):
            return ([], 200)
        default:
            return ([:] as [String: Any], 200)
        }
    }
}

#endif
