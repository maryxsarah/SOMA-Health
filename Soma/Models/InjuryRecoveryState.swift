import Foundation

/// Mirrors an `injury_recovery_state` row -- one per (user, injury tag)
/// with an active or recovering protocol. Read-only from the client;
/// all writes go through report-injury/record-injury-checkin.
struct InjuryRecoveryState: Codable, Identifiable {
    let injuryTag: String
    let severity: InjurySeverity
    let status: String
    let consecutiveGoodDays: Int
    let consecutiveBadDays: Int
    let lastCheckinDate: String?

    var id: String { injuryTag }

    enum CodingKeys: String, CodingKey {
        case injuryTag = "injury_tag"
        case severity
        case status
        case consecutiveGoodDays = "consecutive_good_days"
        case consecutiveBadDays = "consecutive_bad_days"
        case lastCheckinDate = "last_checkin_date"
    }

    /// True once today's date has already been recorded -- the check-in
    /// card is shown once per day per tag.
    func hasCheckedInToday(_ today: String) -> Bool {
        lastCheckinDate == today
    }
}

enum InjuryCheckinResponse: String {
    case better, same, worse
}

/// Decoded from record-injury-checkin's response body -- distinct shape
/// from InjuryRecoveryState (camelCase, includes the one-off escalation
/// message) rather than reusing that struct's snake_case row shape.
struct InjuryCheckinResult: Decodable {
    let injuryTag: String
    let status: String
    let consecutiveGoodDays: Int
    let consecutiveBadDays: Int
    let escalate: Bool
    let escalationMessage: String?
}
