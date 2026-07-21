import Foundation

/// Mirrors the `users` row. `wakeTimePref` is stored/sent as "HH:mm" text
/// to match Postgres `time` column formatting over PostgREST.
struct UserRecord: Codable {
    let id: String
    var wakeTimePref: String
    var onboardingComplete: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case wakeTimePref = "wake_time_pref"
        case onboardingComplete = "onboarding_complete"
    }
}
