import Foundation

/// Mirrors a `daily_sleep_log` row -- a one-tap "how long did you sleep?"
/// check-in for users without a connected wearable (same category as
/// daily_mood: user-entered content, no derived/safety logic). A
/// wearable-sourced `DailySnapshotRow.sleepHours` always takes priority over
/// this in the UI when both exist for the same day.
struct DailySleepLogEntry: Codable, Identifiable {
    let date: String
    let bucket: String
    let loggedAt: String

    var id: String { date }

    enum CodingKeys: String, CodingKey {
        case date, bucket
        case loggedAt = "logged_at"
    }
}

/// The 4 fixed duration chips shown on Home's sleep widget when no wearable
/// reported last night -- same "closed vocabulary" pattern as MoodRating.
enum SleepDurationBucket: String, CaseIterable, Identifiable {
    case underSix = "under_6"
    case sixSeven = "six_seven"
    case sevenEight = "seven_eight"
    case eightPlus = "eight_plus"

    var id: String { rawValue }

    var chipLabel: String {
        switch self {
        case .underSix: String(localized: "sleepBucket.underSix.chip", defaultValue: "< 6 h", comment: "Sleep check-in chip: under 6 hours")
        case .sixSeven: String(localized: "sleepBucket.sixSeven.chip", defaultValue: "6\u{2013}7", comment: "Sleep check-in chip: 6 to 7 hours")
        case .sevenEight: String(localized: "sleepBucket.sevenEight.chip", defaultValue: "7\u{2013}8", comment: "Sleep check-in chip: 7 to 8 hours")
        case .eightPlus: String(localized: "sleepBucket.eightPlus.chip", defaultValue: "8 h +", comment: "Sleep check-in chip: 8 or more hours")
        }
    }

    /// Single serif word shown once logged, in place of an hours number
    /// (design: "Solid" for the 7-8h bucket -- the app already treats >=7h
    /// as the "good" threshold, see `sleepHero.headline.good`). The other
    /// three reuse MoodRating's own vocabulary for in-app consistency.
    var verdict: String {
        switch self {
        case .underSix: String(localized: "sleepBucket.underSix.verdict", defaultValue: "Short", comment: "Sleep check-in verdict word once logged: under 6 hours")
        case .sixSeven: String(localized: "sleepBucket.sixSeven.verdict", defaultValue: "Okay", comment: "Sleep check-in verdict word once logged: 6 to 7 hours")
        case .sevenEight: String(localized: "sleepBucket.sevenEight.verdict", defaultValue: "Solid", comment: "Sleep check-in verdict word once logged: 7 to 8 hours")
        case .eightPlus: String(localized: "sleepBucket.eightPlus.verdict", defaultValue: "Great", comment: "Sleep check-in verdict word once logged: 8 or more hours")
        }
    }
}
