import Foundation

/// Today's on-device HealthKit readings, sent as the optional `healthkit`
/// field in generate-recommendation's request body.
struct HealthKitSnapshot: Codable {
    var sleepHours: Double?
    var hrvMs: Double?
    var restingHr: Double?
    /// Per-stage breakdown of the same sleep window fetchHours covers --
    /// nil for any stage HealthKit reported nothing for. See
    /// HealthKitManager.fetchSleepStageBreakdown's own comment on why these
    /// four can undercount sleepHours for a mixed-source night (an honest
    /// gap, not a bug).
    var sleepLightHours: Double?
    var sleepDeepHours: Double?
    var sleepRemHours: Double?
    var sleepAwakeHours: Double?
    /// Trailing-24h basalEnergyBurned sum (kcal) -- feeds
    /// nutritionTargets.ts's measured-BMR override server-side (see
    /// docs/coaching-personalization-plan.md Phase 1). Not used anywhere
    /// client-side.
    var basalEnergyKcal: Double?

    enum CodingKeys: String, CodingKey {
        case sleepHours, hrvMs, restingHr
        case sleepLightHours, sleepDeepHours, sleepRemHours, sleepAwakeHours
        case basalEnergyKcal
    }
}
