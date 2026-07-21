import Foundation

/// Today's on-device HealthKit readings, sent as the optional `healthkit`
/// field in generate-recommendation's request body.
struct HealthKitSnapshot: Codable {
    var sleepHours: Double?
    var hrvMs: Double?
    var restingHr: Double?

    enum CodingKeys: String, CodingKey {
        case sleepHours, hrvMs, restingHr
    }
}
