import Foundation

/// Mirrors a `daily_snapshot` row -- read-only, used to pull the real
/// metric value (recovery/readiness score) for substitution into
/// RecommendationReason's fixed explanation templates.
struct DailySnapshotRow: Codable {
    let source: String
    let recoveryScore: Double?
    let readinessScore: Double?
    let hrvMs: Double?
    let sleepHours: Double?
    let restingHr: Double?

    enum CodingKeys: String, CodingKey {
        case source
        case recoveryScore = "recovery_score"
        case readinessScore = "readiness_score"
        case hrvMs = "hrv_ms"
        case sleepHours = "sleep_hours"
        case restingHr = "resting_hr"
    }
}
