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

Deno.test("REGRESSION: unmapped tags (bike, pool, other) contribute nothing, never unlock the full unfiltered library", () => {
  // Previously returned null ("no narrowing" -- the entire library,
  // barbells included) the moment ANY tag was unmapped, even alongside a
  // real preset. Fixed after a real BUG report of unavailable equipment
  // (including barbells) being recommended to a user who never selected
  // a barbell-granting preset.
  assertEquals(resolveLibraryEquipment(["bike", "pool", "other"]), ["body only"]);
  assertEquals(resolveLibraryEquipment(["other"]), ["body only"]);
});

Deno.test("an unmapped tag alongside a real preset still applies the preset's narrowing", () => {
  const values = resolveLibraryEquipment(["gym", "other"]);
  assert(values.includes("barbell"), "the real 'gym' preset must still apply");
  assertFalse(values.length > new Set(resolveLibraryEquipment(["gym"])).size, "the unmapped 'other' tag must not add anything extra");
});

Deno.test("gym unlocks its library values on top of body only", () => {
  const values = resolveLibraryEquipment(["gym"]);
  assert(values.includes("body only"));
  assert(values.includes("barbell"));
  assert(values.includes("e-z curl bar"));
});

Deno.test("REGRESSION: home_gym no longer assumes a barbell", () => {
  // A loadable barbell + plates + rack is a much bigger footprint than
  // dumbbells/kettlebells/bands -- assuming it for every "Home Gym"
  // selection recommended barbell exercises to real users who didn't
  // have one. Users with a genuine home barbell can still be recognized
  // via free-text equipment notes (see equipment.ts) or by selecting
  // "Gym" instead.
  const values = resolveLibraryEquipment(["home_gym"]);
  assertFalse(values.includes("barbell"), "home_gym must not assume a barbell");
  assert(values.includes("dumbbell"), "home_gym should still unlock dumbbell");
  assert(values.includes("kettlebells"), "home_gym should still unlock kettlebells");
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
  requires_partner: boolean;
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
  { id: "bodyweight-flyes", name: "Bodyweight Flyes", category: "strength", equipment: "e-z curl bar", primary_muscles: ["chest"], level: "intermediate", requires_partner: false },
  { id: "pushups", name: "Pushups", category: "strength", equipment: "body only", primary_muscles: ["chest"], level: "beginner", requires_partner: false },
  { id: "barbell-bench-press", name: "Barbell Bench Press", category: "strength", equipment: "barbell", primary_muscles: ["chest"], level: "beginner", requires_partner: false },
  { id: "one-arm-push-up", name: "One-Arm Push-Up", category: "strength", equipment: "body only", primary_muscles: ["chest"], level: "expert", requires_partner: false },
  { id: "bodyweight-squat", name: "Bodyweight Squat", category: "strength", equipment: "body only", primary_muscles: ["quadriceps"], level: "beginner", requires_partner: false },
  { id: "behind-head-chest-stretch", name: "Behind Head Chest Stretch", category: "stretching", equipment: "body only", primary_muscles: ["chest"], level: "beginner", requires_partner: false },
  { id: "exercise-ball-stretch", name: "Exercise Ball Stretch", category: "stretching", equipment: "exercise ball", primary_muscles: ["chest"], level: "beginner", requires_partner: false },
  { id: "running-treadmill", name: "Running, Treadmill", category: "cardio", equipment: "machine", primary_muscles: ["quadriceps"], level: "beginner", requires_partner: false },
  { id: "jumping-jacks", name: "Jumping Jacks", category: "cardio", equipment: "body only", primary_muscles: ["quadriceps"], level: "beginner", requires_partner: false },
  { id: "trail-running-walking", name: "Trail Running/Walking", category: "cardio", equipment: null, primary_muscles: ["quadriceps"], level: "beginner", requires_partner: false },
  { id: "arm-circles", name: "Arm Circles", category: "strength", equipment: null, primary_muscles: ["shoulders"], level: "beginner", requires_partner: false },
  { id: "depth-jump-leap", name: "Depth Jump Leap", category: "plyometrics", equipment: "body only", primary_muscles: ["quadriceps"], level: "intermediate", requires_partner: false },
  { id: "barbell-back-squat", name: "Barbell Back Squat", category: "strength", equipment: "barbell", primary_muscles: ["quadriceps"], level: "intermediate", requires_partner: false },
  { id: "prone-manual-hamstring", name: "Prone Manual Hamstring", category: "strength", equipment: "body only", primary_muscles: ["hamstrings"], level: "beginner", requires_partner: true },
  { id: "overhead-lat", name: "Overhead Lat", category: "stretching", equipment: "body only", primary_muscles: ["lats"], level: "beginner", requires_partner: true },
  { id: "return-push-from-stance", name: "Return Push from Stance", category: "cardio", equipment: "medicine ball", primary_muscles: ["shoulders"], level: "beginner", requires_partner: true },
  // Real data uses "machine" for both cardio and strength machines --
  // see the extraCardioLibraryEquipment tests below.
  { id: "leg-press", name: "Leg Press", category: "strength", equipment: "machine", primary_muscles: ["quadriceps"], level: "beginner", requires_partner: false },
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

Deno.test("REGRESSION: an unmapped equipment tag alone never unlocks the full unfiltered catalog", async () => {
  const names = await fetchCandidateExerciseNames(mockSupabase(LIBRARY), "upper_body", ["other"], []);
  assertFalse(names.includes("Barbell Bench Press"), "unmapped tag must not unlock a barbell exercise");
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

Deno.test("REGRESSION: a partner-required strength exercise never joins the main candidate pool", async () => {
  const names = await fetchCandidateExerciseNames(mockSupabase(LIBRARY), "lower_body", [], []);
  assertFalse(names.includes("Prone Manual Hamstring"), "partner-required exercise leaked into a solo user's plan");
});

Deno.test("REGRESSION: a partner-required stretch never joins the candidate pool", async () => {
  const names = await fetchCandidateExerciseNames(mockSupabase(LIBRARY), "upper_body", [], []);
  assertFalse(names.includes("Overhead Lat"), "partner-required stretch leaked into a solo user's plan");
  // The (non-partner) stretch fixture still joins normally.
  assert(names.includes("Behind Head Chest Stretch"));
});

Deno.test("REGRESSION: a partner-required cardio exercise never joins the candidate pool", async () => {
  const names = await fetchCandidateExerciseNames(mockSupabase(LIBRARY), "cardio", [], []);
  assertFalse(names.includes("Return Push from Stance"), "partner-required cardio drill leaked into a solo user's plan");
});

Deno.test("REGRESSION: a partner-required goal-mapped exercise is unioned out, same as an equipment/level mismatch", async () => {
  const names = await fetchCandidateExerciseNames(
    mockSupabase(LIBRARY), "lower_body", [], [], null, ["prone-manual-hamstring", "depth-jump-leap"],
  );
  assertFalse(names.includes("Prone Manual Hamstring"), "partner-required goal exercise bypassed the filter");
  assert(names.includes("Depth Jump Leap"));
});

Deno.test("INVARIANT: excluding partner-required exercises never empties the enum when solo alternatives exist", async () => {
  const names = await fetchCandidateExerciseNames(mockSupabase(LIBRARY), "lower_body", [], []);
  assert(names.length > 0);
});

// --- extraLibraryEquipment / unlockCardioCandidates (free-text equipment) ---
//
// REGRESSION coverage for the real bug report: told Soma about a
// treadmill in free text, but warm-up on a leg day could never actually
// name one -- because cardio-category candidates were only ever merged in
// when the body part itself was "cardio".

Deno.test("REGRESSION: a non-cardio body part never sees MACHINE-equipment cardio by default", async () => {
  // Separately, NOTE: the main query has no category filter, so a
  // body-only-equipment cardio exercise whose muscles happen to overlap
  // (e.g. "Jumping Jacks" x lower_body/quadriceps) can already leak in via
  // the ordinary muscle-overlap match -- that's real, pre-existing, and
  // NOT what unlockCardioCandidates is about (equipment gating is the
  // point here, not category purity); tracked separately, not fixed here.
  const names = await fetchCandidateExerciseNames(mockSupabase(LIBRARY), "lower_body", [], []);
  assertFalse(names.includes("Running, Treadmill"), "machine-equipment cardio must still respect the equipment filter");
});

Deno.test("REGRESSION: unlockCardioCandidates merges cardio candidates into a non-cardio body part's pool", async () => {
  const names = await fetchCandidateExerciseNames(
    mockSupabase(LIBRARY), "lower_body", ["gym"], [], null, [], [], true,
  );
  assert(names.includes("Running, Treadmill") || names.includes("Jumping Jacks"), "cardio candidates should be available for warm-up");
});

Deno.test("unlockCardioCandidates still respects the equipment filter -- no treadmill without machine access", async () => {
  const names = await fetchCandidateExerciseNames(
    mockSupabase(LIBRARY), "lower_body", ["bodyweight_only"], [], null, [], [], true,
  );
  assertFalse(names.includes("Running, Treadmill"), "treadmill needs machine equipment");
  assert(names.includes("Jumping Jacks"), "bodyweight cardio should still be available");
});

Deno.test("unlockCardioCandidates never fires for an already-cardio day (no redundant duplicate query)", async () => {
  const names = await fetchCandidateExerciseNames(
    mockSupabase(LIBRARY), "cardio", ["gym"], [], null, [], [], true,
  );
  assert(names.includes("Running, Treadmill"));
});

Deno.test("REGRESSION: extraLibraryEquipment (parsed free text) unions in on top of the structured tags", async () => {
  // The user selected nothing structured (equipment: []), which alone
  // resolves to body-only -- but free text named a barbell.
  const names = await fetchCandidateExerciseNames(
    mockSupabase(LIBRARY), "upper_body", [], [], null, [], ["barbell"],
  );
  assert(names.includes("Barbell Bench Press"), "free-text-named equipment must unlock matching exercises");
});

Deno.test("REGRESSION: cardio-only free-text equipment (treadmill) never unlocks a strength machine in the main tier", async () => {
  // extraCardioLibraryEquipment must only widen the cardio slice, not the main query.
  const names = await fetchCandidateExerciseNames(
    mockSupabase(LIBRARY), "lower_body", ["bodyweight_only"], [], null, [], [], false, [], ["machine"],
  );
  assertFalse(names.includes("Leg Press"), "cardio-only equipment leaked into the main tier's equipment filter");
});

Deno.test("REGRESSION: cardio-only free-text equipment (treadmill) still unlocks the cardio warm-up slice", async () => {
  const names = await fetchCandidateExerciseNames(
    mockSupabase(LIBRARY), "lower_body", ["bodyweight_only"], [], null, [], [], true, [], ["machine"],
  );
  assert(names.includes("Running, Treadmill"), "cardio-only equipment should still unlock the cardio-specific tier");
  assertFalse(names.includes("Leg Press"), "cardio slice must not leak into unlocking the main strength tier either");
});

// --- recentlyUsedNames (day-over-day variety) ---
//
// REGRESSION coverage for the real bug report: the same workout, day
// after day -- picking "Leg Day" (or any suggestion) twice in a row used
// to hand back the identical exercise list both times.

Deno.test("REGRESSION: a recently-used name is excluded when enough other candidates remain", async () => {
  const names = await fetchCandidateExerciseNames(
    mockSupabase(LIBRARY), "upper_body", ["gym"], [], null, [], [], false, ["Pushups"],
  );
  assertFalse(names.includes("Pushups"), "recently-used exercise should be excluded for freshness");
  assert(names.includes("Barbell Bench Press"), "other equipment-matched candidates should still be present");
});

Deno.test("freshness exclusion backs off rather than starve a small candidate pool", async () => {
  // Bodyweight-only + upper_body is a small pool in this fixture --
  // excluding a name must never shrink it below the safety floor.
  const withoutExclusion = await fetchCandidateExerciseNames(
    mockSupabase(LIBRARY), "upper_body", ["bodyweight_only"], [],
  );
  const withExclusion = await fetchCandidateExerciseNames(
    mockSupabase(LIBRARY), "upper_body", ["bodyweight_only"], [], null, [], [], false, withoutExclusion,
  );
  // Excluding EVERY candidate that exists must never leave zero -- the
  // function backs off the freshness filter entirely rather than starve
  // the pool below its safety floor.
  assert(withExclusion.length > 0, "freshness exclusion must never empty the candidate pool");
});
