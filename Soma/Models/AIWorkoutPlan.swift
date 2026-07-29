import Foundation

/// One exercise from an AI-generated plan -- mirrors the JSON schema
/// enforced server-side in generate-workout-plan (Claude Haiku, structured
/// output), so decoding failures here would mean the schema drifted.
struct AIExercise: Codable, Identifiable {
    var id: String { name }
    let name: String
    let sets: Int
    let reps: String
    let weightGuidance: String
    let intensity: String
    let durationMinutes: Int
    let instructions: String
    /// Which muscles/body area this exercise targets -- currently only
    /// populated by the gym-photo-workout flow (deterministic, set per
    /// exercise in the template, never LLM-guessed); nil for the normal
    /// generate-workout-plan flow, which doesn't send this field.
    let targetArea: String?

    enum CodingKeys: String, CodingKey {
        case name, sets, reps, intensity, instructions
        case weightGuidance = "weight_guidance"
        case durationMinutes = "duration_minutes"
        case targetArea = "target_area"
    }
}

/// One named segment of the main workout -- e.g. "Block 1", "Superset A",
/// "Block 3 - Finisher". `rounds` > 1 means cycle through `exercises` that
/// many times (a circuit/superset), with `restBetweenRounds` between each
/// pass; `rounds` == 1 is just a straight-through block.
struct AIWorkoutBlock: Codable, Identifiable {
    var id: String { name }
    let name: String
    let rounds: Int
    let restBetweenRounds: String
    let exercises: [AIExercise]

    enum CodingKeys: String, CodingKey {
        case name, rounds, exercises
        case restBetweenRounds = "rest_between_rounds"
    }
}

/// Mirrors the generate-workout-plan response -- cached server-side per
/// (user, date, selected workout), so repeat fetches for the same
/// selection don't re-call Claude. Always structured as warm-up, one or
/// more named blocks making up the selected workout, and cool-down.
struct AIWorkoutPlan: Codable {
    let date: String
    let category: String
    let focus: String
    let warmUp: [AIExercise]
    let blocks: [AIWorkoutBlock]
    let coolDown: [AIExercise]
    /// Server-computed sum of every exercise's duration_minutes (plus rest
    /// between rounds) -- the real total, shown instead of trusting a
    /// static suggestion-list label that may not match what was actually
    /// generated.
    let actualDurationMinutes: Int?

    enum CodingKeys: String, CodingKey {
        case date, category, focus, blocks
        case warmUp = "warm_up"
        case coolDown = "cool_down"
        case actualDurationMinutes = "actual_duration_minutes"
    }
}
