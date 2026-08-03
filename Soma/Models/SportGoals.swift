import Foundation

// MARK: - Catalog

/// Mirrors a `sports` row. Visibility is server-gated via RLS on `status`
/// (live/internal) -- an empty fetch means the feature is off.
struct Sport: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let variant: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        variant = try c.decodeIfPresent(String.self, forKey: .variant)
    }

    enum CodingKeys: String, CodingKey { case id, name, variant }

    /// SF Symbol per sport -- keyed off the name, no custom illustrations.
    var iconSystemName: String {
        let lower = name.lowercased()
        if lower.contains("volley") { return "figure.volleyball" }
        if lower.contains("yoga") { return "figure.yoga" }
        if lower.contains("climb") { return "figure.climbing" }
        if lower.contains("padel") || lower.contains("tennis") { return "tennis.racket" }
        return "sportscourt"
    }
}

/// Server-owned vocabulary -- unknown raw values decode as `.unknown`
/// (same forward-compat rule as RecommendationReason).
enum SportGoalKind: String, Codable {
    case metric, milestone, qualitative, unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SportGoalKind(rawValue: raw) ?? .unknown
    }

    var badgeText: String {
        switch self {
        case .metric: "metric"
        case .milestone: "milestone"
        case .qualitative: "in words"
        case .unknown: ""
        }
    }
}

/// One row of a goal's evidence-backed target table: a starting-level band
/// mapped to an honest gain range and horizon. All fields lenient.
struct SportGoalTargetBand: Codable, Hashable {
    var label: String?
    var min: Double?
    var max: Double?
    var sessionsMin: Int?
    var sessionsMax: Int?
    var gainLow: Double?
    var gainHigh: Double?
    var weeksLow: Int?
    var weeksHigh: Int?

    enum CodingKeys: String, CodingKey {
        case label, min, max
        case sessionsMin = "sessions_min"
        case sessionsMax = "sessions_max"
        case gainLow = "gain_low"
        case gainHigh = "gain_high"
        case weeksLow = "horizon_weeks_low"
        case weeksHigh = "horizon_weeks_high"
        case weeksLowAlt = "weeks_low"
        case weeksHighAlt = "weeks_high"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try? c.decodeIfPresent(String.self, forKey: .label)
        min = try? c.decodeIfPresent(Double.self, forKey: .min)
        max = try? c.decodeIfPresent(Double.self, forKey: .max)
        sessionsMin = try? c.decodeIfPresent(Int.self, forKey: .sessionsMin)
        sessionsMax = try? c.decodeIfPresent(Int.self, forKey: .sessionsMax)
        gainLow = try? c.decodeIfPresent(Double.self, forKey: .gainLow)
        gainHigh = try? c.decodeIfPresent(Double.self, forKey: .gainHigh)
        weeksLow = (try? c.decodeIfPresent(Int.self, forKey: .weeksLow))
            ?? (try? c.decodeIfPresent(Int.self, forKey: .weeksLowAlt))
        weeksHigh = (try? c.decodeIfPresent(Int.self, forKey: .weeksHigh))
            ?? (try? c.decodeIfPresent(Int.self, forKey: .weeksHighAlt))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(label, forKey: .label)
        try c.encodeIfPresent(min, forKey: .min)
        try c.encodeIfPresent(max, forKey: .max)
        try c.encodeIfPresent(sessionsMin, forKey: .sessionsMin)
        try c.encodeIfPresent(sessionsMax, forKey: .sessionsMax)
        try c.encodeIfPresent(gainLow, forKey: .gainLow)
        try c.encodeIfPresent(gainHigh, forKey: .gainHigh)
        try c.encodeIfPresent(weeksLow, forKey: .weeksLow)
        try c.encodeIfPresent(weeksHigh, forKey: .weeksHigh)
    }

    /// A band is only shown when it can make an honest claim.
    var hasHonestTarget: Bool {
        gainLow != nil && gainHigh != nil && weeksLow != nil && weeksHigh != nil
    }
}

/// Mirrors a `sport_goals` row -- the evidence table lives server-side as
/// data; the client never invents a number outside `targetTable`.
struct SportGoal: Codable, Identifiable, Hashable {
    let id: String
    let sportId: String
    let key: String
    let name: String
    let kind: SportGoalKind
    let unit: String?
    let promise: String?
    let protocolText: String?
    let noiseBand: Double?
    let targetTable: [SportGoalTargetBand]

    enum CodingKeys: String, CodingKey {
        case id, name, kind, unit, key, promise
        case sportId = "sport_id"
        case protocolText = "measurement_protocol"
        case protocolAlt = "protocol_text"
        case noiseBand = "noise_band"
        case targetTable = "target_table"
    }

    /// The seeded `target_table` is a wrapper object with the bands inside.
    private struct TargetTableWrapper: Decodable {
        let bands: [String: SportGoalTargetBand]?
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        sportId = try c.decodeIfPresent(String.self, forKey: .sportId) ?? ""
        key = try c.decodeIfPresent(String.self, forKey: .key) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        kind = try c.decodeIfPresent(SportGoalKind.self, forKey: .kind) ?? .unknown
        unit = try c.decodeIfPresent(String.self, forKey: .unit)
        promise = try? c.decodeIfPresent(String.self, forKey: .promise)
        protocolText = (try? c.decodeIfPresent(String.self, forKey: .protocolText))
            ?? (try? c.decodeIfPresent(String.self, forKey: .protocolAlt))
        noiseBand = try? c.decodeIfPresent(Double.self, forKey: .noiseBand)
        // Tolerates an array of bands, a dict keyed by band label, and the
        // seeded wrapper shape `{"bands": {"novice": {...}}, ...}`.
        func bands(fromDict dict: [String: SportGoalTargetBand]) -> [SportGoalTargetBand] {
            dict.map { key, band in
                var b = band
                if b.label == nil { b.label = key }
                return b
            }.sorted { ($0.min ?? 0) < ($1.min ?? 0) }
        }
        if let array = try? c.decodeIfPresent([SportGoalTargetBand].self, forKey: .targetTable) {
            targetTable = array
        } else if let wrapper = try? c.decodeIfPresent(TargetTableWrapper.self, forKey: .targetTable),
                  let wrapped = wrapper.bands {
            targetTable = bands(fromDict: wrapped)
        } else if let dict = try? c.decodeIfPresent([String: SportGoalTargetBand].self, forKey: .targetTable) {
            targetTable = bands(fromDict: dict)
        } else {
            targetTable = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(sportId, forKey: .sportId)
        try c.encode(key, forKey: .key)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(unit, forKey: .unit)
    }

    /// One-line row caption -- server copy when present, else derived
    /// deterministically from unit/kind (fixed copy, not fabricated data).
    var promiseLine: String {
        if let promise, !promise.isEmpty { return promise }
        if let unit, !unit.isEmpty { return "Measurable in \(unit)" }
        switch kind {
        case .milestone: return "Tracked in stages"
        case .qualitative: return "A target in your own words"
        default: return "Measured, honestly"
        }
    }

    /// The three-numbered-lines protocol from the server's protocol text.
    var protocolLines: [String] {
        guard let protocolText, !protocolText.isEmpty else { return [] }
        let separators = CharacterSet.newlines
        let lines = protocolText.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if lines.count > 1 { return lines }
        return protocolText.components(separatedBy: "·")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// The band an entered baseline falls into (metric), or by stage label.
    func band(forBaseline value: Double) -> SportGoalTargetBand? {
        // Level-keyed bands (the seeded shape) carry no min/max -- an
        // unbounded band would match any baseline, so require real bounds.
        targetTable.first { band in
            guard band.min != nil || band.max != nil else { return false }
            let lo = band.min ?? -Double.infinity
            let hi = band.max ?? Double.infinity
            return value >= lo && value <= hi
        }
    }

    /// Seeded bands are keyed by training level, not baseline range.
    func band(forLevel level: ExperienceLevel?) -> SportGoalTargetBand? {
        let label: String = switch level {
        case .newbie, nil: "novice"
        case .moderate: "intermediate"
        case .advanced: "advanced"
        }
        return targetTable.first { $0.label == label } ?? targetTable.first { $0.label == "novice" }
    }

    func band(forStage label: String) -> SportGoalTargetBand? {
        targetTable.first { $0.label == label }
    }

    /// Stage chips for milestone goals come from the target table's labels
    /// -- never invented client-side.
    var stageLabels: [String] {
        targetTable.compactMap(\.label)
    }

    /// Ruler bounds derived from the band edges when present.
    var entryRange: ClosedRange<Double> {
        let mins = targetTable.compactMap(\.min)
        let maxs = targetTable.compactMap(\.max)
        let lo = mins.min() ?? 0
        let hi = maxs.max() ?? 120
        return lo...Swift.max(hi, lo + 1)
    }
}

/// The fetched, RLS-gated catalog. Empty `sports` == feature off.
struct SportCatalog {
    var sports: [Sport] = []
    var goals: [SportGoal] = []

    var isEmpty: Bool { sports.isEmpty }

    /// Unknown kinds come from a newer server -- hidden rather than shown
    /// half-broken (forward compat, same spirit as `.unknown` decoding).
    func goals(for sport: Sport) -> [SportGoal] {
        goals.filter { $0.sportId == sport.id && $0.kind != .unknown }
    }

    func goal(id: String) -> SportGoal? {
        goals.first { $0.id == id }
    }

    func sport(for goal: SportGoal) -> Sport? {
        sports.first { $0.id == goal.sportId }
    }
}

// MARK: - User goal

enum UserGoalKind: String, Codable {
    case preset, custom, unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = UserGoalKind(rawValue: raw) ?? .unknown
    }
}

enum GoalTargetKind: String, Codable {
    case metric, milestone, qualitative, commitment, unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = GoalTargetKind(rawValue: raw) ?? .unknown
    }
}

enum UserGoalStatus: String, Codable {
    case active, completed, paused, abandoned, unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = UserGoalStatus(rawValue: raw) ?? .unknown
    }
}

enum GoalPauseReason: String, Codable {
    case user, safety, unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = GoalPauseReason(rawValue: raw) ?? .unknown
    }
}

enum GoalScheduleRule: String, Codable {
    case weekdays
    case everyOtherDay = "every_other_day"
    case beforeCourtDays = "before_court_days"
    case readiness
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = GoalScheduleRule(rawValue: raw) ?? .unknown
    }
}

/// Mirrors a `user_goal` row. Every field beyond `id` decodes leniently --
/// the column set is server-owned and still growing.
struct UserGoal: Codable, Identifiable, Hashable {
    let id: String
    let goalId: String?
    let kind: UserGoalKind
    let targetKind: GoalTargetKind
    let status: UserGoalStatus
    let baselineValue: Double?
    let targetLow: Double?
    let targetHigh: Double?
    let etaStart: String?
    let etaEnd: String?
    let phase: String?
    let pauseReason: GoalPauseReason?
    let resultValue: Double?
    let completedAt: String?
    let createdAt: String?
    let etaSlipDays: Int?
    let etaSlipReason: String?
    // Custom (coach's task) fields
    let givenText: String?
    let workoutText: String?
    let coachName: String?
    let durationWeeks: Int?
    let recheckDate: String?
    let customMetricName: String?
    let customMetricUnit: String?
    let assignmentPhotoPath: String?
    // Scheduling
    let frequencyPerWeek: Int?
    let scheduleRule: GoalScheduleRule?
    let scheduleDays: [Int]?
    let courtDays: [Int]?

    enum CodingKeys: String, CodingKey {
        case id, kind, status, phase
        case goalId = "goal_id"
        case targetKind = "target_kind"
        case baselineValue = "baseline_value"
        case targetLow = "target_low"
        case targetHigh = "target_high"
        case etaStart = "eta_start"
        case etaEnd = "eta_end"
        case pauseReason = "pause_reason"
        case resultValue = "result_value"
        case completedAt = "completed_at"
        case createdAt = "created_at"
        case etaSlipDays = "eta_slip_days"
        case etaSlipReason = "eta_slip_reason"
        case givenText = "given_text"
        case workoutText = "workout_text"
        case coachName = "coach_name"
        case durationWeeks = "duration_weeks"
        case recheckDate = "recheck_date"
        case customMetricName = "custom_metric_name"
        case customMetricUnit = "custom_metric_unit"
        case assignmentPhotoPath = "assignment_photo_path"
        case frequencyPerWeek = "frequency_per_week"
        case scheduleRule = "schedule_rule"
        case scheduleDays = "schedule_days"
        case courtDays = "court_days"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        goalId = try? c.decodeIfPresent(String.self, forKey: .goalId)
        kind = (try? c.decodeIfPresent(UserGoalKind.self, forKey: .kind)) ?? .unknown
        targetKind = (try? c.decodeIfPresent(GoalTargetKind.self, forKey: .targetKind)) ?? .unknown
        status = (try? c.decodeIfPresent(UserGoalStatus.self, forKey: .status)) ?? .unknown
        baselineValue = try? c.decodeIfPresent(Double.self, forKey: .baselineValue)
        targetLow = try? c.decodeIfPresent(Double.self, forKey: .targetLow)
        targetHigh = try? c.decodeIfPresent(Double.self, forKey: .targetHigh)
        etaStart = try? c.decodeIfPresent(String.self, forKey: .etaStart)
        etaEnd = try? c.decodeIfPresent(String.self, forKey: .etaEnd)
        phase = try? c.decodeIfPresent(String.self, forKey: .phase)
        pauseReason = try? c.decodeIfPresent(GoalPauseReason.self, forKey: .pauseReason)
        resultValue = try? c.decodeIfPresent(Double.self, forKey: .resultValue)
        completedAt = try? c.decodeIfPresent(String.self, forKey: .completedAt)
        createdAt = try? c.decodeIfPresent(String.self, forKey: .createdAt)
        etaSlipDays = try? c.decodeIfPresent(Int.self, forKey: .etaSlipDays)
        etaSlipReason = try? c.decodeIfPresent(String.self, forKey: .etaSlipReason)
        givenText = try? c.decodeIfPresent(String.self, forKey: .givenText)
        workoutText = try? c.decodeIfPresent(String.self, forKey: .workoutText)
        coachName = try? c.decodeIfPresent(String.self, forKey: .coachName)
        durationWeeks = try? c.decodeIfPresent(Int.self, forKey: .durationWeeks)
        recheckDate = try? c.decodeIfPresent(String.self, forKey: .recheckDate)
        customMetricName = try? c.decodeIfPresent(String.self, forKey: .customMetricName)
        customMetricUnit = try? c.decodeIfPresent(String.self, forKey: .customMetricUnit)
        assignmentPhotoPath = try? c.decodeIfPresent(String.self, forKey: .assignmentPhotoPath)
        frequencyPerWeek = try? c.decodeIfPresent(Int.self, forKey: .frequencyPerWeek)
        scheduleRule = try? c.decodeIfPresent(GoalScheduleRule.self, forKey: .scheduleRule)
        scheduleDays = try? c.decodeIfPresent([Int].self, forKey: .scheduleDays)
        courtDays = try? c.decodeIfPresent([Int].self, forKey: .courtDays)
    }
}

extension UserGoal {
    /// Preset goals are named by their catalog row; customs by their own
    /// metric or the coach framing. Never a fabricated title.
    func displayName(in catalog: SportCatalog?) -> String {
        if kind == .custom {
            if let customMetricName, !customMetricName.isEmpty { return customMetricName }
            if let coachName, !coachName.isEmpty { return "Coach \(coachName)'s task" }
            return "Coach's task"
        }
        if let goalId, let goal = catalog?.goal(id: goalId) { return goal.name }
        return "Your goal"
    }

    var startDate: Date? {
        createdAt.flatMap(SportGoalFormat.parseTimestamp)
    }

    /// 1-based training week since the block started.
    var currentWeek: Int? {
        guard let startDate else { return nil }
        let days = Calendar.current.dateComponents([.day], from: startDate, to: Date()).day ?? 0
        return days / 7 + 1
    }

    /// Horizon in weeks derived from the ETA window -- nil when the server
    /// hasn't set one (nothing is invented in its place).
    var horizonWeeks: (low: Int, high: Int)? {
        guard let startDate,
              let lo = etaStart.flatMap(SportGoalFormat.parseDay),
              let hi = etaEnd.flatMap(SportGoalFormat.parseDay) else { return nil }
        let cal = Calendar.current
        let lowDays = cal.dateComponents([.day], from: startDate, to: lo).day ?? 0
        let highDays = cal.dateComponents([.day], from: startDate, to: hi).day ?? 0
        guard lowDays > 0 else { return nil }
        return (Int((Double(lowDays) / 7).rounded()), Int((Double(highDays) / 7).rounded()))
    }

    /// "week 4 of 10–12" -- only when both halves are real.
    var weekLine: String? {
        guard let currentWeek, let horizon = horizonWeeks else { return nil }
        return "week \(currentWeek) of \(horizon.low)–\(horizon.high)"
    }

    /// "+3–6 cm" from the stored target range.
    func targetRangeText(unit: String?) -> String? {
        guard let targetLow, let targetHigh else { return nil }
        return SportGoalFormat.gainRange(low: targetLow, high: targetHigh, unit: unit)
    }

    /// Total committed sessions for a custom block ("N of M").
    var committedSessions: Int? {
        guard let durationWeeks, let frequencyPerWeek else { return nil }
        return durationWeeks * frequencyPerWeek
    }
}

// MARK: - Measurements

enum GoalMeasurementKind: String, Codable {
    case baseline
    case baselineConfirm = "baseline_confirm"
    case checkpoint
    case final
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = GoalMeasurementKind(rawValue: raw) ?? .unknown
    }
}

/// Mirrors a `goal_measurement_log` row -- the chart's only data source.
struct GoalMeasurement: Codable, Identifiable, Hashable {
    let id: String
    let userGoalId: String
    let kind: GoalMeasurementKind
    let value: Double
    let measuredAt: String

    enum CodingKeys: String, CodingKey {
        case id, kind, value
        case userGoalId = "user_goal_id"
        case measuredAt = "measured_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        userGoalId = try c.decodeIfPresent(String.self, forKey: .userGoalId) ?? ""
        kind = try c.decodeIfPresent(GoalMeasurementKind.self, forKey: .kind) ?? .unknown
        value = try c.decodeIfPresent(Double.self, forKey: .value) ?? 0
        measuredAt = try c.decodeIfPresent(String.self, forKey: .measuredAt) ?? ""
    }

    var dayString: String {
        guard let date = SportGoalFormat.parseTimestamp(measuredAt) else {
            return String(measuredAt.prefix(10))
        }
        return SportGoalFormat.dayString(date)
    }
}

// MARK: - Create-goal request/response

/// One safety conflict from the create-goal keyword pass. Decodes either a
/// bare string or an object -- the shape is server-owned.
struct GoalSafetyConflict: Decodable, Identifiable, Hashable {
    let message: String
    let isPregnancyRelated: Bool

    var id: String { message }

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let text = try? single.decode(String.self) {
            message = text
            isPregnancyRelated = text.lowercased().contains("pregnan")
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        message = (try? c.decodeIfPresent(String.self, forKey: .message)) ?? "This assignment may conflict with your noted health situation."
        let pregnancyFlag = (try? c.decodeIfPresent(Bool.self, forKey: .pregnancy)) ?? false
        isPregnancyRelated = pregnancyFlag || message.lowercased().contains("pregnan")
    }

    enum CodingKeys: String, CodingKey { case message, pregnancy }
}

/// Everything the create-goal edge function needs; nil fields are omitted.
struct CreateGoalRequest {
    var goalId: String?
    var kind: UserGoalKind
    var targetKind: GoalTargetKind
    var baselineValue: Double?
    var baselineStage: String?
    var targetText: String?
    var givenText: String?
    var workoutText: String?
    var coachName: String?
    var durationWeeks: Int?
    var customMetricName: String?
    var customMetricUnit: String?
    var assignmentPhotoPath: String?
    var frequencyPerWeek: Int?
    var scheduleRule: GoalScheduleRule?
    var scheduleDays: [Int]?
    var courtDays: [Int]?
    var acknowledgeConflicts: Bool = false
}

enum CreateGoalOutcome {
    /// Carries the row create-goal returned -- its id feeds the baseline
    /// insert directly, no post-create refetch needed.
    case created(UserGoal)
    case conflicts([GoalSafetyConflict])
}

// MARK: - Formatting

/// Shared date/number formatting for goal surfaces. Ranges, never points.
enum SportGoalFormat {
    static func parseDay(_ string: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f.date(from: String(string.prefix(10)))
    }

    static func parseTimestamp(_ string: String) -> Date? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFractional.date(from: string) { return d }
        let plain = ISO8601DateFormatter()
        if let d = plain.date(from: string) { return d }
        return parseDay(string)
    }

    static func dayString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f.string(from: date)
    }

    static func value(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", v) : String(format: "%.1f", v)
    }

    static func value(_ v: Double, unit: String?) -> String {
        guard let unit, !unit.isEmpty else { return value(v) }
        return "\(value(v)) \(unit)"
    }

    /// "+3–6 cm" -- a signed gain range, never a single point.
    static func gainRange(low: Double, high: Double, unit: String?) -> String {
        let sign = low >= 0 ? "+" : ""
        let core = "\(sign)\(value(low))–\(value(high))"
        guard let unit, !unit.isEmpty else { return core }
        return "\(core) \(unit)"
    }

    /// Signed delta, e.g. "+5 cm" / "−1 cm".
    static func delta(_ d: Double, unit: String?) -> String {
        let sign = d >= 0 ? "+" : "−"
        return "\(sign)\(value(abs(d), unit: unit))"
    }

    /// "Oct 12–26" or "Oct 28 – Nov 11" when the months differ.
    static func dateRange(_ from: Date, _ to: Date) -> String {
        let month = DateFormatter()
        month.dateFormat = "MMM d"
        let dayOnly = DateFormatter()
        dayOnly.dateFormat = "d"
        let sameMonth = Calendar.current.isDate(from, equalTo: to, toGranularity: .month)
        if sameMonth {
            return "\(month.string(from: from))–\(dayOnly.string(from: to))"
        }
        return "\(month.string(from: from)) – \(month.string(from: to))"
    }

    static func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }

    /// "Aug–Oct 2026" for achievement cards.
    static func monthRange(_ from: Date, _ to: Date) -> String {
        let month = DateFormatter()
        month.dateFormat = "MMM"
        let year = DateFormatter()
        year.dateFormat = "yyyy"
        if Calendar.current.isDate(from, equalTo: to, toGranularity: .month) {
            return "\(month.string(from: to)) \(year.string(from: to))"
        }
        return "\(month.string(from: from))–\(month.string(from: to)) \(year.string(from: to))"
    }
}
