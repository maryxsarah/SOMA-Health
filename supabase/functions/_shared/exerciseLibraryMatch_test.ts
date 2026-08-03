// Run: deno test supabase/functions/
//
// Pins the equipment filtering of the candidate-name enum. The failure
// mode this guards: a bodyweight-only user was handed an unfiltered
// catalog (empty equipment used to mean "no filter"), so the model picked
// "Bodyweight Flyes" -- an exercise whose name says bodyweight but whose
// library equipment is 'e-z curl bar'.

import { assert, assertEquals, assertFalse, assertRejects } from "jsr:@std/assert";
import { fetchCandidateExerciseNames, resolveLibraryEquipment, resolveLibraryLevels } from "./exerciseLibraryMatch.ts";

Deno.test("empty equipment resolves to body only, never no-filter", () => {
  assertEquals(resolveLibraryEquipment([]), ["body only"]);
});

Deno.test("bodyweight_only resolves to body only without duplicates", () => {
  assertEquals(resolveLibraryEquipment(["bodyweight_only"]), ["body only"]);
});

Deno.test("unmapped tags (bike, pool, other) mean no narrowing, not body-only", () => {
  assertEquals(resolveLibraryEquipment(["bike", "pool", "other"]), null);
  assertEquals(resolveLibraryEquipment(["other"]), null);
});

Deno.test("gym unlocks its library values on top of body only", () => {
  const values = resolveLibraryEquipment(["gym"]);
  assert(values !== null);
  assert(values.includes("body only"));
  assert(values.includes("barbell"));
  assert(values.includes("e-z curl bar"));
});

Deno.test("newbie experience resolves to beginner-level movements only", () => {
  assertEquals(resolveLibraryLevels("newbie"), ["beginner"]);
});

Deno.test("unknown or absent experience defaults to moderate (no expert)", () => {
  assertEquals(resolveLibraryLevels(null), ["beginner", "intermediate"]);
  assertEquals(resolveLibraryLevels("something_new"), ["beginner", "intermediate"]);
});

Deno.test("advanced experience unlocks expert movements", () => {
  assert(resolveLibraryLevels("advanced").includes("expert"));
});

// --- fetchCandidateExerciseNames against a filtering mock client ---

interface Row {
  id: string;
  name: string;
  category: string;
  equipment: string | null;
  primary_muscles: string[];
  level: string;
}

/// Chainable thenable mimicking the small slice of postgrest-js the
/// function uses -- filters actually apply, so these tests exercise real
/// query semantics rather than just recording calls.
class MockQuery {
  #rows: Row[];
  #limit = Infinity;
  constructor(rows: Row[]) {
    this.#rows = [...rows];
  }
  select(_cols: string) {
    return this;
  }
  limit(n: number) {
    this.#limit = n;
    return this;
  }
  eq(col: keyof Row, value: unknown) {
    this.#rows = this.#rows.filter((r) => r[col] === value);
    return this;
  }
  in(col: keyof Row, values: unknown[]) {
    this.#rows = this.#rows.filter((r) => values.includes(r[col]));
    return this;
  }
  overlaps(col: keyof Row, values: string[]) {
    this.#rows = this.#rows.filter((r) => (r[col] as string[]).some((v) => values.includes(v)));
    return this;
  }
  // Understands only the equipment clause the module generates:
  // `equipment.is.null,equipment.in.("a","b")` -- NULL rows always pass.
  or(clause: string) {
    const match = clause.match(/^equipment\.is\.null,equipment\.in\.\((.*)\)$/);
    if (!match) throw new Error(`unsupported or() clause: ${clause}`);
    const values = match[1].split(",").map((s) => s.replace(/^"|"$/g, ""));
    this.#rows = this.#rows.filter((r) => r.equipment === null || values.includes(r.equipment));
    return this;
  }
  then(resolve: (v: { data: Row[] }) => void) {
    resolve({ data: this.#rows.slice(0, this.#limit) });
  }
}

function mockSupabase(rows: Row[]) {
  return { from: (_table: string) => new MockQuery(rows) };
}

const LIBRARY: Row[] = [
  { id: "bodyweight-flyes", name: "Bodyweight Flyes", category: "strength", equipment: "e-z curl bar", primary_muscles: ["chest"], level: "intermediate" },
  { id: "pushups", name: "Pushups", category: "strength", equipment: "body only", primary_muscles: ["chest"], level: "beginner" },
  { id: "barbell-bench-press", name: "Barbell Bench Press", category: "strength", equipment: "barbell", primary_muscles: ["chest"], level: "beginner" },
  { id: "one-arm-push-up", name: "One-Arm Push-Up", category: "strength", equipment: "body only", primary_muscles: ["chest"], level: "expert" },
  { id: "bodyweight-squat", name: "Bodyweight Squat", category: "strength", equipment: "body only", primary_muscles: ["quadriceps"], level: "beginner" },
  { id: "behind-head-chest-stretch", name: "Behind Head Chest Stretch", category: "stretching", equipment: "body only", primary_muscles: ["chest"], level: "beginner" },
  { id: "exercise-ball-stretch", name: "Exercise Ball Stretch", category: "stretching", equipment: "exercise ball", primary_muscles: ["chest"], level: "beginner" },
  { id: "running-treadmill", name: "Running, Treadmill", category: "cardio", equipment: "machine", primary_muscles: ["quadriceps"], level: "beginner" },
  { id: "jumping-jacks", name: "Jumping Jacks", category: "cardio", equipment: "body only", primary_muscles: ["quadriceps"], level: "beginner" },
  { id: "trail-running-walking", name: "Trail Running/Walking", category: "cardio", equipment: null, primary_muscles: ["quadriceps"], level: "beginner" },
  { id: "arm-circles", name: "Arm Circles", category: "strength", equipment: null, primary_muscles: ["shoulders"], level: "beginner" },
  { id: "depth-jump-leap", name: "Depth Jump Leap", category: "plyometrics", equipment: "body only", primary_muscles: ["quadriceps"], level: "intermediate" },
  { id: "barbell-back-squat", name: "Barbell Back Squat", category: "strength", equipment: "barbell", primary_muscles: ["quadriceps"], level: "intermediate" },
];

Deno.test("REGRESSION: floor-only user never sees the EZ-bar 'Bodyweight Flyes'", async () => {
  for (const equipment of [[], ["bodyweight_only"]]) {
    const names = await fetchCandidateExerciseNames(mockSupabase(LIBRARY), "upper_body", equipment, []);
    assertFalse(names.includes("Bodyweight Flyes"), `leaked for equipment=${JSON.stringify(equipment)}`);
    assertFalse(names.includes("Barbell Bench Press"));
    assert(names.includes("Pushups"));
  }
});

Deno.test("gym user keeps the full equipment-matched catalog", async () => {
  const names = await fetchCandidateExerciseNames(mockSupabase(LIBRARY), "upper_body", ["gym"], []);
  assert(names.includes("Bodyweight Flyes"));
  assert(names.includes("Barbell Bench Press"));
  assert(names.includes("Pushups"));
});

Deno.test("stretch candidates are equipment-filtered too", async () => {
  const names = await fetchCandidateExerciseNames(mockSupabase(LIBRARY), "upper_body", [], []);
  assert(names.includes("Behind Head Chest Stretch"));
  assertFalse(names.includes("Exercise Ball Stretch"));
});

Deno.test("muscle-mismatch fallback broadens muscles but never equipment", async () => {
  // No body-only entry matches core muscles, so the first query is empty;
  // the fallback must stay inside the user's equipment.
  const names = await fetchCandidateExerciseNames(mockSupabase(LIBRARY), "core", [], []);
  assert(names.includes("Pushups"));
  assert(names.includes("Bodyweight Squat"));
  assertFalse(names.includes("Bodyweight Flyes"));
  assertFalse(names.includes("Barbell Bench Press"));
});

Deno.test("cardio candidates are equipment-filtered", async () => {
  const names = await fetchCandidateExerciseNames(mockSupabase(LIBRARY), "cardio", [], []);
  assert(names.includes("Jumping Jacks"));
  assertFalse(names.includes("Running, Treadmill"));
});

Deno.test("NULL-equipment rows stay pickable through every filter", async () => {
  for (const equipment of [[], ["gym"]]) {
    const names = await fetchCandidateExerciseNames(mockSupabase(LIBRARY), "upper_body", equipment, []);
    assert(names.includes("Arm Circles"), `dropped for equipment=${JSON.stringify(equipment)}`);
  }
  const cardio = await fetchCandidateExerciseNames(mockSupabase(LIBRARY), "cardio", [], []);
  assert(cardio.includes("Trail Running/Walking"));
});

Deno.test("unmapped equipment tags keep the catalog unfiltered", async () => {
  const names = await fetchCandidateExerciseNames(mockSupabase(LIBRARY), "upper_body", ["other"], []);
  assert(names.includes("Barbell Bench Press"));
  assert(names.includes("Pushups"));
});

Deno.test("REGRESSION: cardio day broadens past equipment instead of going stretch-only", async () => {
  // A library whose only cardio rows need a machine -- the primary
  // equipment-filtered query returns nothing for a bodyweight user.
  const machineOnlyCardio = LIBRARY.filter((r) => r.category !== "cardio" || r.equipment === "machine");
  const names = await fetchCandidateExerciseNames(mockSupabase(machineOnlyCardio), "cardio", ["bodyweight_only"], []);
  assert(names.includes("Running, Treadmill"), "cardio enum collapsed to stretches");
});

Deno.test("injury keyword exclusions still apply after equipment filtering", async () => {
  const names = await fetchCandidateExerciseNames(mockSupabase(LIBRARY), "upper_body", [], ["pushup"]);
  assertFalse(names.includes("Pushups"));
  assert(names.includes("Behind Head Chest Stretch"));
});

Deno.test("REGRESSION: exclusions that empty the list never come back via fallback", async () => {
  // Wipes every upper-body candidate; the safe fallback must re-apply the
  // exclusions, not resurrect the contraindicated names.
  const names = await fetchCandidateExerciseNames(
    mockSupabase(LIBRARY),
    "upper_body",
    [],
    ["push", "stretch", "circle"],
  );
  assertFalse(names.some((n) => /push|stretch|circle/i.test(n)));
  assert(names.includes("Bodyweight Squat"));
});

Deno.test("fails closed when safety exclusions empty even the broadest set", async () => {
  const everything = LIBRARY.map((r) => r.name.toLowerCase());
  await assertRejects(() => fetchCandidateExerciseNames(mockSupabase(LIBRARY), "upper_body", [], everything));
});

Deno.test("REGRESSION: a newbie never sees intermediate/expert movements", async () => {
  const names = await fetchCandidateExerciseNames(mockSupabase(LIBRARY), "upper_body", ["gym"], [], "newbie");
  assertFalse(names.includes("Bodyweight Flyes"), "intermediate leaked to a newbie");
  assertFalse(names.includes("One-Arm Push-Up"), "expert leaked to a newbie");
  assert(names.includes("Pushups"));
});

Deno.test("moderate (and unknown) experience excludes expert movements", async () => {
  for (const experience of ["moderate", null]) {
    const names = await fetchCandidateExerciseNames(mockSupabase(LIBRARY), "upper_body", ["gym"], [], experience);
    assert(names.includes("Bodyweight Flyes"), "intermediate should be allowed at moderate");
    assertFalse(names.includes("One-Arm Push-Up"), `expert leaked for experience=${experience}`);
  }
});

Deno.test("advanced experience gets the full difficulty range", async () => {
  const names = await fetchCandidateExerciseNames(mockSupabase(LIBRARY), "upper_body", ["gym"], [], "advanced");
  assert(names.includes("One-Arm Push-Up"));
});

Deno.test("goal exercises are unioned in by id but safety exclusions still govern them", async () => {
  // A goal-mapped id outside today's body-part filter joins the enum...
  const unioned = await fetchCandidateExerciseNames(
    mockSupabase(LIBRARY), "upper_body", [], [], null, ["depth-jump-leap"],
  );
  assert(unioned.includes("Depth Jump Leap"));
  assert(unioned.includes("Pushups"));
  // ...but never past the exclusion filter -- unioning happens BEFORE it.
  const excluded = await fetchCandidateExerciseNames(
    mockSupabase(LIBRARY), "upper_body", [], ["jump"], null, ["depth-jump-leap"],
  );
  assertFalse(excluded.includes("Depth Jump Leap"), "goal exercise bypassed the safety filter");
  assert(excluded.includes("Pushups"));
});

Deno.test("REGRESSION: a goal exercise needing equipment the user lacks stays out of the vocabulary", async () => {
  // Barbell squat is goal-mapped, but the user trains bodyweight-only --
  // the goal union obeys the same equipment filter as the main query.
  const names = await fetchCandidateExerciseNames(
    mockSupabase(LIBRARY), "upper_body", ["bodyweight_only"], [], null, ["barbell-back-squat", "depth-jump-leap"],
  );
  assertFalse(names.includes("Barbell Back Squat"), "goal exercise bypassed the equipment filter");
  assert(names.includes("Depth Jump Leap"), "equipment-matched goal exercise should join");
  // A gym user's equipment covers the barbell -- now it joins.
  const gym = await fetchCandidateExerciseNames(
    mockSupabase(LIBRARY), "upper_body", ["gym"], [], null, ["barbell-back-squat"],
  );
  assert(gym.includes("Barbell Back Squat"));
});

Deno.test("REGRESSION: goal exercises above the user's level stay out of the vocabulary", async () => {
  // Intermediate goal movements never reach a newbie...
  const newbie = await fetchCandidateExerciseNames(
    mockSupabase(LIBRARY), "upper_body", [], [], "newbie", ["depth-jump-leap"],
  );
  assertFalse(newbie.includes("Depth Jump Leap"), "goal exercise bypassed the level filter");
  // ...but are fine at moderate, same as the main query's level rule.
  const moderate = await fetchCandidateExerciseNames(
    mockSupabase(LIBRARY), "upper_body", [], [], "moderate", ["depth-jump-leap"],
  );
  assert(moderate.includes("Depth Jump Leap"));
});
