import Foundation

/// Client-side mirror of supabase/functions/_shared/nutritionTargets.ts's
/// TrainingEmphasis -- a coarser directional read than GoalTag, from the
/// same goal/current photo comparison (analyze-body-photo). Shown directly
/// on the Progress screen (a product-owner decision reversing this
/// feature's original "never shown to the user" posture -- see
/// Config.enableBodyPhotoVisionAnalysis's doc comment).
enum TrainingEmphasis: String, Codable {
    case cut, recomp, bulk, maintain

    /// A plain, encouraging sentence fragment -- never phrased as a
    /// clinical judgment about the user's body ("you need to lose fat"),
    /// always as a description of what today's PLAN is doing for them.
    var planDirectionSentence: String {
        switch self {
        case .cut: return String(localized: "trainingEmphasis.cut", defaultValue: "Right now, your plan is focused on leaning out.", comment: "Encouraging sentence describing the current plan's training emphasis, shown on the Progress screen")
        case .bulk: return String(localized: "trainingEmphasis.bulk", defaultValue: "Right now, your plan is focused on building size.", comment: "Encouraging sentence describing the current plan's training emphasis, shown on the Progress screen")
        case .recomp: return String(localized: "trainingEmphasis.recomp", defaultValue: "Right now, your plan is focused on building strength while leaning out.", comment: "Encouraging sentence describing the current plan's training emphasis, shown on the Progress screen")
        case .maintain: return String(localized: "trainingEmphasis.maintain", defaultValue: "Right now, your plan is focused on maintaining where you are.", comment: "Encouraging sentence describing the current plan's training emphasis, shown on the Progress screen")
        }
    }
}
