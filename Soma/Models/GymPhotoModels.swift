import Foundation

/// analyze-gym-photo's response.
struct GymPhotoEquipmentResult: Decodable {
    let equipment: [String]
    let confidence: Double
    let lowConfidence: Bool
}

/// generate-gym-workout's response is one of two shapes -- a full
/// AIWorkoutPlan-equivalent (plus the template's title/bodyPart, needed to
/// populate RecommendationDetailView's selectedTitle/selectedBodyPart the
/// same way picking from the fixed suggestion list does), or a
/// safety-guardrail block. Modeled as an enum rather than a single
/// optional-heavy struct so call sites can't forget to check which case
/// they got.
enum GymWorkoutOutcome {
    case plan(AIWorkoutPlan, title: String, bodyPart: String)
    case safetyBlocked(message: String)
}
