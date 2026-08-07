import Foundation

/// Mirrors a `daily_snapshot` row -- read-only, used to pull the real
/// metric value (recovery/readiness score) for substitution into
/// RecommendationReason's fixed explanation templates.
struct DailySnapshotRow: Codable {
    /// Only populated by range fetches (`fetchSnapshots(fromDate:toDate:)`)
    /// -- the single-date fetch never needed it since the caller already
    /// knows the date it asked for.
    var date: String?
    let source: String
    let recoveryScore: Double?
    let readinessScore: Double?
    let hrvMs: Double?
    let sleepHours: Double?
    let restingHr: Double?
    let strainScore: Double?
    let stressScore: Double?
    /// Per-stage breakdown of the same night sleepHours covers -- nil for
    /// any stage the source didn't report. See HealthKitManager's
    /// fetchSleepStageBreakdown / generate-recommendation's Whoop/Oura
    /// fetch functions for why these can undercount sleepHours for a
    /// mixed-source night (an honest gap, not a bug).
    let sleepLightHours: Double?
    let sleepDeepHours: Double?
    let sleepRemHours: Double?
    let sleepAwakeHours: Double?

    enum CodingKeys: String, CodingKey {
        case date, source
        case recoveryScore = "recovery_score"
        case readinessScore = "readiness_score"
        case hrvMs = "hrv_ms"
        case sleepHours = "sleep_hours"
        case restingHr = "resting_hr"
        case strainScore = "strain_score"
        case stressScore = "stress_score"
        case sleepLightHours = "sleep_light_hours"
        case sleepDeepHours = "sleep_deep_hours"
        case sleepRemHours = "sleep_rem_hours"
        case sleepAwakeHours = "sleep_awake_hours"
    }
}
