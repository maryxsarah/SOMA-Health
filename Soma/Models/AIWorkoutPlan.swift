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
    /// True only for the optional finisher block, if today's plan includes
    /// one -- see AIWorkoutPlan.exceptionalFinisher for whether it's the
    /// full max-effort version. Absent-means-false: plans cached before
    /// this field existed (ai_workout_plan.plan jsonb) simply omit it.
    let isFinisher: Bool

    enum CodingKeys: String, CodingKey {
        case name, rounds, exercises
        case restBetweenRounds = "rest_between_rounds"
        case isFinisher = "is_finisher"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        rounds = try container.decode(Int.self, forKey: .rounds)
        restBetweenRounds = try container.decode(String.self, forKey: .restBetweenRounds)
        exercises = try container.decode([AIExercise].self, forKey: .exercises)
        isFinisher = try container.decodeIfPresent(Bool.self, forKey: .isFinisher) ?? false
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
    /// Non-nil only when generate-workout-plan itself redirected today's
    /// body part away from one conflicting with a noted injury -- see
    /// _shared/injurySubstitution.ts. Absent-means-nil for plans cached
    /// before this field existed.
    let substitutedBodyPart: String?
    /// True only when today's finisher (see AIWorkoutBlock.isFinisher) is
    /// the full max-effort version, gated on exceptional readiness + no
    /// injury/split conflict -- drives the "Optional finisher -- you're
    /// well recovered today" badge. Absent-means-false, same reasoning.
    let exceptionalFinisher: Bool
    /// "suggestion" (the normal fixed-suggestion-list flow) or "gym_photo"
    /// -- drives the "Generated with your gym picture" label. Absent-means-
    /// "suggestion" for plans cached before this field existed, since that
    /// was the only flow that existed then.
    let source: String

    enum CodingKeys: String, CodingKey {
        case date, category, focus, blocks, source
        case warmUp = "warm_up"
        case coolDown = "cool_down"
        case actualDurationMinutes = "actual_duration_minutes"
        case substitutedBodyPart = "substituted_body_part"
        case exceptionalFinisher = "exceptional_finisher"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(String.self, forKey: .date)
        category = try container.decode(String.self, forKey: .category)
        focus = try container.decode(String.self, forKey: .focus)
        warmUp = try container.decode([AIExercise].self, forKey: .warmUp)
        blocks = try container.decode([AIWorkoutBlock].self, forKey: .blocks)
        coolDown = try container.decode([AIExercise].self, forKey: .coolDown)
        actualDurationMinutes = try container.decodeIfPresent(Int.self, forKey: .actualDurationMinutes)
        substitutedBodyPart = try container.decodeIfPresent(String.self, forKey: .substitutedBodyPart)
        exceptionalFinisher = try container.decodeIfPresent(Bool.self, forKey: .exceptionalFinisher) ?? false
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? "suggestion"
    }
}

/// Mirrors an `ai_workout_plan` row -- used for the persistent Home card
/// (today's plan survives app relaunch, not just the current view session).
/// `plan`/`source` here are the sibling top-level columns, not nested inside
/// the `plan` jsonb blob's own fields.
struct TodaysAIPlan: Codable {
    let category: String
    let plan: AIWorkoutPlan
    let selectedTitle: String
    /// True once the user tapped "Add to today's plan" -- distinct from
    /// having merely generated/previewed it, and distinct from having
    /// completed it (see WorkoutLogEntry, a separate table).
    let addedToPlan: Bool
    let source: String

    enum CodingKeys: String, CodingKey {
        case category, plan, source
        case selectedTitle = "selected_title"
        case addedToPlan = "added_to_plan"
    }
}
