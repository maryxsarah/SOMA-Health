// Pure JSON-schema builders for generate-workout-plan's structured-output
// call -- pulled out of index.ts specifically so buildWorkoutSchema's
// shape (in particular its minItems guarantee, see below) is directly
// unit-testable without importing index.ts itself (which would run its
// top-level Deno.serve as a side effect).

// Exercise `name` is constrained to a request-scoped closed vocabulary
// (see _shared/exerciseLibraryMatch.ts) via a JSON-schema enum so every
// name the model can possibly return has real, correctly matched media --
// same "deterministic vocabulary, never free text" pattern already used
// for equipment/goal tags elsewhere in this codebase.
export function buildExerciseSchema(candidateNames: string[]) {
  return {
    type: "object",
    properties: {
      name: { type: "string", enum: candidateNames },
      sets: { type: "integer" },
      reps: { type: "string" },
      weight_guidance: { type: "string" },
      intensity: { type: "string" },
      duration_minutes: { type: "integer" },
      // How long to rest AFTER this exercise (between sets/before the next
      // item) in seconds -- 0 for anything with no meaningful rest (a
      // stretch, a warm-up cardio item). Informational/display-only:
      // duration_minutes above already includes rest in its total, so this
      // is never separately summed into the session duration.
      rest_seconds: { type: "integer" },
      instructions: { type: "string" },
    },
    required: [
      "name",
      "sets",
      "reps",
      "weight_guidance",
      "intensity",
      "duration_minutes",
      "rest_seconds",
      "instructions",
    ],
    additionalProperties: false,
  };
}

export function buildBlockSchema(exerciseSchema: ReturnType<typeof buildExerciseSchema>) {
  return {
    type: "object",
    properties: {
      // e.g. "Block 1", "Superset A", "Block 3 - Optional Finisher"
      name: { type: "string" },
      // How many times to cycle through this block's exercises -- 1 for a
      // straight-through block, >1 for a circuit/superset.
      rounds: { type: "integer" },
      rest_between_rounds: { type: "string" },
      exercises: { type: "array", items: exerciseSchema },
      // True only for the optional finisher block, if one is included today
      // -- an explicit flag rather than string-matching the block name, so
      // the client can reliably show the "optional finisher" badge.
      is_finisher: { type: "boolean" },
    },
    required: ["name", "rounds", "rest_between_rounds", "exercises", "is_finisher"],
    additionalProperties: false,
  };
}

export function buildWorkoutSchema(candidateNames: string[]) {
  // The exercise schema (dominated by the candidate-name enum) is defined
  // once via $defs and referenced 3x via $ref, rather than embedded 3
  // separate times -- Anthropic's structured-output schema compiler rejects
  // an inlined-3x version of this schema at candidate counts as low as ~130
  // with "Schema is too complex for compilation", even though the enum
  // itself is well within any documented size limit. $ref alone roughly
  // halves the compiled cost; MAIN/STRETCH_CANDIDATE_LIMIT in
  // exerciseLibraryMatch.ts additionally caps candidates so the deduped
  // list stays well under the empirically-found ~115-130 ceiling.
  const exerciseRef = { "$ref": "#/$defs/exercise" };
  const blockSchema = buildBlockSchema(exerciseRef as unknown as ReturnType<typeof buildExerciseSchema>);
  return {
    "$defs": {
      exercise: buildExerciseSchema(candidateNames),
    },
    type: "object",
    properties: {
      focus: { type: "string" },
      warm_up: { type: "array", items: exerciseRef },
      // minItems: 1 (added 2026-08-15): without it, `blocks: []` was a
      // legal response -- nothing but warm_up/cool_down, technically
      // schema-valid but a sparse/empty-feeling plan, exactly the risk on
      // a rest/light day where the model might otherwise conclude low
      // intensity means no real content. See index.ts's buildPrompt
      // (restLightContentLine) for the explicit instruction backing this
      // up -- a schema minimum alone doesn't tell the model WHAT to put
      // there, only that it must put SOMETHING.
      blocks: { type: "array", items: blockSchema, minItems: 1 },
      cool_down: { type: "array", items: exerciseRef },
    },
    required: ["focus", "warm_up", "blocks", "cool_down"],
    additionalProperties: false,
  };
}
