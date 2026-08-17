import { assert, assertEquals } from "jsr:@std/assert";
import { buildBlockSchema, buildExerciseSchema, buildWorkoutSchema } from "./workoutSchema.ts";

Deno.test("buildExerciseSchema constrains name to exactly the given candidate names", () => {
  const schema = buildExerciseSchema(["Barbell Squat", "Push-Up"]);
  assertEquals(schema.properties.name.enum, ["Barbell Squat", "Push-Up"]);
});

Deno.test("buildExerciseSchema requires every field the rest of the codebase depends on", () => {
  const schema = buildExerciseSchema([]);
  for (const field of ["name", "sets", "reps", "weight_guidance", "intensity", "duration_minutes", "rest_seconds", "instructions"]) {
    assert(schema.required.includes(field), `missing required field: ${field}`);
  }
  assertEquals(schema.additionalProperties, false);
});

Deno.test("buildBlockSchema requires is_finisher (the client's optional-finisher badge depends on it)", () => {
  const schema = buildBlockSchema(buildExerciseSchema([]));
  assert(schema.required.includes("is_finisher"));
  assert(schema.required.includes("rounds"));
});

// --- REGRESSION: minItems: 1 on blocks (BUG: a technically-valid
// blocks: [] response was a sparse/empty-feeling rest-day risk) ---

Deno.test("REGRESSION: buildWorkoutSchema requires at least one block -- blocks: [] is no longer schema-valid", () => {
  const schema = buildWorkoutSchema(["Bodyweight Squat"]);
  assertEquals(schema.properties.blocks.minItems, 1);
});

Deno.test("buildWorkoutSchema still requires focus/warm_up/blocks/cool_down at the top level", () => {
  const schema = buildWorkoutSchema([]);
  assertEquals(schema.required, ["focus", "warm_up", "blocks", "cool_down"]);
});

Deno.test("buildWorkoutSchema defines the exercise schema once via $defs, referenced by $ref (not inlined 3x)", () => {
  // deno-lint-ignore no-explicit-any
  const schema = buildWorkoutSchema(["Bodyweight Squat"]) as any;
  assertEquals(schema.properties.warm_up.items, { "$ref": "#/$defs/exercise" });
  assertEquals(schema.properties.cool_down.items, { "$ref": "#/$defs/exercise" });
  assertEquals(schema.properties.blocks.items.properties.exercises.items, { "$ref": "#/$defs/exercise" });
  assert("exercise" in schema.$defs);
});
