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
    /// exercise_library.id -- only sent by generate-gym-workout, and only
    /// for the subset of fixed template exercises hand-verified against the
    /// library (see generate-gym-workout/templates.ts). Nil there means "no
    /// confident media match," a deliberate no-image fallback rather than a
    /// guess. Always nil for generate-workout-plan; that flow instead
    /// guarantees `name` itself is a real exercise_library.name (its `name`
    /// field is schema-constrained to a request-scoped enum drawn from the
    /// library, see _shared/exerciseLibraryMatch.ts), so the client looks
    /// that flow's media up by exact name instead of by id.
    let libraryId: String?

    enum CodingKeys: String, CodingKey {
        case name, sets, reps, intensity, instructions
        case weightGuidance = "weight_guidance"
        case durationMinutes = "duration_minutes"
        case targetArea = "target_area"
        case libraryId = "library_id"
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

/// Compact goal-block marker generate-workout-plan stores inside the plan
/// jsonb (goalBlockMeta in its index.ts) -- non-nil only when this plan
/// actually contains a goal block. All fields lenient; the shape is
/// server-owned and may grow.
struct AIGoalBlockMarker: Codable {
    let kind: String?
    let text: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try? c.decodeIfPresent(String.self, forKey: .kind)
        text = try? c.decodeIfPresent(String.self, forKey: .text)
    }

    enum CodingKeys: String, CodingKey { case kind, text }
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
    /// The template's body part, only sent by generate-gym-workout (its
    /// cached plan object carries `bodyPart`); nil for the suggestion flow.
    let templateBodyPart: String?
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
    /// Non-nil only when the plan actually includes a goal block -- gates
    /// the GOAL BLOCK eyebrow (an active goal alone doesn't imply one today).
    let goalBlock: AIGoalBlockMarker?
    /// Non-nil only when outdoor cardio was actually excluded from today's
    /// candidate pool for weather -- e.g. "It's 42°C (feels like) right
    /// now -- too hot for safe outdoor cardio." Real feedback: "when the
    /// user is in Dubai, and the temperature ... is 42 degrees celsius,
    /// SOMA should not recommend a run outside." See
    /// _shared/weatherSafety.ts server-side. Absent-means-nil for plans
    /// cached before this field existed.
    let weatherNote: String?

    enum CodingKeys: String, CodingKey {
        case date, category, focus, blocks, source
        case warmUp = "warm_up"
        case coolDown = "cool_down"
        case actualDurationMinutes = "actual_duration_minutes"
        case substitutedBodyPart = "substituted_body_part"
        case templateBodyPart = "bodyPart"
        case exceptionalFinisher = "exceptional_finisher"
        case goalBlock = "goal_block"
        case weatherNote = "weather_note"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Absent-means-default: neither field is nested inside the stored
        // `plan` jsonb blob (generate-workout-plan/generate-gym-workout only
        // add `date`/`category` at the top level of their own JSON
        // response, never inside the plan object they cache) -- reading
        // the *stored* row's `plan` column directly (TodaysAIPlan, used by
        // Home's persistent card and RecommendationDetailView's reopen-
        // restore) always hit this and silently failed the whole decode
        // via `try?`, which is why the confirmed-plan state never actually
        // stuck. Neither field is read anywhere in the app (confirmed by
        // search), so a safe placeholder default is fine either way.
        date = try container.decodeIfPresent(String.self, forKey: .date) ?? ""
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? ""
        focus = try container.decode(String.self, forKey: .focus)
        warmUp = try container.decode([AIExercise].self, forKey: .warmUp)
        blocks = try container.decode([AIWorkoutBlock].self, forKey: .blocks)
        coolDown = try container.decode([AIExercise].self, forKey: .coolDown)
        actualDurationMinutes = try container.decodeIfPresent(Int.self, forKey: .actualDurationMinutes)
        substitutedBodyPart = try container.decodeIfPresent(String.self, forKey: .substitutedBodyPart)
        templateBodyPart = try container.decodeIfPresent(String.self, forKey: .templateBodyPart)
        exceptionalFinisher = try container.decodeIfPresent(Bool.self, forKey: .exceptionalFinisher) ?? false
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? "suggestion"
        // Lenient: absent, null, or an unexpected shape all mean "no marker".
        goalBlock = try? container.decodeIfPresent(AIGoalBlockMarker.self, forKey: .goalBlock)
        weatherNote = try container.decodeIfPresent(String.self, forKey: .weatherNote)
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
