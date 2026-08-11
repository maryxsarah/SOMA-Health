import { assert, assertEquals } from "jsr:@std/assert";
import {
  activityLevelFromWorkoutsPerWeek,
  computeNutritionTargets,
  isMeasuredBmrFresh,
  trainingEmphasisFromWeights,
} from "./nutritionTargets.ts";

Deno.test("Mifflin-St Jeor: known worked example matches by hand (male, moderate, maintain)", () => {
  // BMR = 10*80 + 6.25*180 - 5*30 + 5 = 800 + 1125 - 150 + 5 = 1780
  // TDEE = 1780 * 1.55 = 2759 -> maintain adjustment 0 -> 2759
  const result = computeNutritionTargets({
    weightKg: 80,
    heightCm: 180,
    age: 30,
    sex: "male",
    activityLevel: "moderate",
    trainingEmphasis: "maintain",
  });
  assertEquals(result.dailyCalories, 2759);
});

Deno.test("cut applies a calorie deficit relative to maintain", () => {
  const maintain = computeNutritionTargets({
    weightKg: 70, heightCm: 165, age: 28, sex: "female", activityLevel: "sedentary", trainingEmphasis: "maintain",
  });
  const cut = computeNutritionTargets({
    weightKg: 70, heightCm: 165, age: 28, sex: "female", activityLevel: "sedentary", trainingEmphasis: "cut",
  });
  assertEquals(maintain.dailyCalories - cut.dailyCalories, 500);
});

Deno.test("bulk applies a calorie surplus relative to maintain", () => {
  const maintain = computeNutritionTargets({
    weightKg: 70, heightCm: 175, age: 25, sex: "male", activityLevel: "very_active", trainingEmphasis: "maintain",
  });
  const bulk = computeNutritionTargets({
    weightKg: 70, heightCm: 175, age: 25, sex: "male", activityLevel: "very_active", trainingEmphasis: "bulk",
  });
  assertEquals(bulk.dailyCalories - maintain.dailyCalories, 300);
});

Deno.test("recomp targets more protein per kg than bulk at the same weight", () => {
  const recomp = computeNutritionTargets({
    weightKg: 75, heightCm: 170, age: 35, sex: "female", activityLevel: "moderate", trainingEmphasis: "recomp",
  });
  const bulk = computeNutritionTargets({
    weightKg: 75, heightCm: 170, age: 35, sex: "female", activityLevel: "moderate", trainingEmphasis: "bulk",
  });
  assert(recomp.dailyProteinG > bulk.dailyProteinG);
});

Deno.test("macros reconcile back to the total calorie target within rounding", () => {
  const result = computeNutritionTargets({
    weightKg: 90, heightCm: 190, age: 40, sex: "male", activityLevel: "very_active", trainingEmphasis: "bulk",
  });
  const reconstructed = result.dailyProteinG * 4 + result.dailyCarbsG * 4 + result.dailyFatG * 9;
  assert(Math.abs(reconstructed - result.dailyCalories) <= 4, `reconstructed ${reconstructed} vs target ${result.dailyCalories}`);
});

Deno.test("INVARIANT: calories never drop below the 1200 floor even at a low TDEE plus a cut", () => {
  const result = computeNutritionTargets({
    weightKg: 45, heightCm: 150, age: 65, sex: "female", activityLevel: "sedentary", trainingEmphasis: "cut",
  });
  assert(result.dailyCalories >= 1200);
});

Deno.test("INVARIANT: carbs never go negative even in a floored low-calorie edge case", () => {
  const result = computeNutritionTargets({
    weightKg: 40, heightCm: 145, age: 70, sex: "female", activityLevel: "sedentary", trainingEmphasis: "cut",
  });
  assert(result.dailyCarbsG >= 0);
});

Deno.test("'other' sex uses the midpoint of the male/female constant, flagged in basis", () => {
  const male = computeNutritionTargets({
    weightKg: 75, heightCm: 175, age: 30, sex: "male", activityLevel: "moderate", trainingEmphasis: "maintain",
  });
  const female = computeNutritionTargets({
    weightKg: 75, heightCm: 175, age: 30, sex: "female", activityLevel: "moderate", trainingEmphasis: "maintain",
  });
  const other = computeNutritionTargets({
    weightKg: 75, heightCm: 175, age: 30, sex: "other", activityLevel: "moderate", trainingEmphasis: "maintain",
  });
  assert(other.dailyCalories > female.dailyCalories && other.dailyCalories < male.dailyCalories);
  assert(other.basis.includes("sex=other"));
});

Deno.test("activityLevelFromWorkoutsPerWeek maps every known band and defaults unknowns to sedentary", () => {
  assertEquals(activityLevelFromWorkoutsPerWeek("zero_to_two"), "sedentary");
  assertEquals(activityLevelFromWorkoutsPerWeek("three_to_five"), "moderate");
  assertEquals(activityLevelFromWorkoutsPerWeek("six_plus"), "very_active");
  assertEquals(activityLevelFromWorkoutsPerWeek(null), "sedentary");
  assertEquals(activityLevelFromWorkoutsPerWeek("garbage"), "sedentary");
});

Deno.test("basis string names the formula and every input that drove the result", () => {
  const result = computeNutritionTargets({
    weightKg: 60, heightCm: 160, age: 22, sex: "female", activityLevel: "sedentary", trainingEmphasis: "recomp",
  });
  assertEquals(result.basis, "mifflin_st_jeor:recomp:activity=sedentary:sex=female");
});

Deno.test("trainingEmphasisFromWeights: a meaningfully lower target reads as cut", () => {
  assertEquals(trainingEmphasisFromWeights(80, 74), "cut");
});

Deno.test("trainingEmphasisFromWeights: a meaningfully higher target reads as bulk", () => {
  assertEquals(trainingEmphasisFromWeights(70, 76), "bulk");
});

Deno.test("trainingEmphasisFromWeights: a target within 2% of current reads as maintain, not noise", () => {
  assertEquals(trainingEmphasisFromWeights(80, 80.5), "maintain");
  assertEquals(trainingEmphasisFromWeights(80, 79.5), "maintain");
});

Deno.test("trainingEmphasisFromWeights: the 2% threshold is proportional, not a flat kg amount", () => {
  // 2kg on a 50kg person (4%) is a real signal; 2kg on a 120kg person
  // (1.7%) is inside normal fluctuation -- a flat kg threshold would get
  // these backwards or treat them the same.
  assertEquals(trainingEmphasisFromWeights(50, 48), "cut");
  assertEquals(trainingEmphasisFromWeights(120, 118), "maintain");
});

Deno.test("trainingEmphasisFromWeights: missing either input returns null rather than guessing", () => {
  assertEquals(trainingEmphasisFromWeights(null, 74), null);
  assertEquals(trainingEmphasisFromWeights(80, null), null);
  assertEquals(trainingEmphasisFromWeights(null, null), null);
});

Deno.test("measuredBmrKcal overrides the formula BMR, flagged in basis", () => {
  const formula = computeNutritionTargets({
    weightKg: 80, heightCm: 180, age: 30, sex: "male", activityLevel: "moderate", trainingEmphasis: "maintain",
  });
  // A measured BMR well above the formula's ~1780 estimate should move
  // calories up, not just get silently ignored.
  const measured = computeNutritionTargets({
    weightKg: 80, heightCm: 180, age: 30, sex: "male", activityLevel: "moderate", trainingEmphasis: "maintain",
    measuredBmrKcal: 2000,
  });
  assert(measured.dailyCalories > formula.dailyCalories);
  assertEquals(measured.basis, "measured_bmr:maintain:activity=moderate:sex=male");
  assertEquals(formula.basis, "mifflin_st_jeor:maintain:activity=moderate:sex=male");
});

Deno.test("measuredBmrKcal still respects the activity multiplier and emphasis adjustment downstream", () => {
  // BMR fixed at 2000 -> TDEE = 2000*1.55 = 3100 -> cut adjustment -500 -> 2600
  const result = computeNutritionTargets({
    weightKg: 80, heightCm: 180, age: 30, sex: "male", activityLevel: "moderate", trainingEmphasis: "cut",
    measuredBmrKcal: 2000,
  });
  assertEquals(result.dailyCalories, 2600);
});

Deno.test("measuredBmrKcal of null, undefined, zero, or negative all fall back to the formula", () => {
  const formula = computeNutritionTargets({
    weightKg: 80, heightCm: 180, age: 30, sex: "male", activityLevel: "moderate", trainingEmphasis: "maintain",
  });
  for (const bad of [null, undefined, 0, -100]) {
    const result = computeNutritionTargets({
      weightKg: 80, heightCm: 180, age: 30, sex: "male", activityLevel: "moderate", trainingEmphasis: "maintain",
      measuredBmrKcal: bad,
    });
    assertEquals(result.dailyCalories, formula.dailyCalories, `measuredBmrKcal=${bad} should fall back to formula`);
    assert(result.basis.startsWith("mifflin_st_jeor"), `measuredBmrKcal=${bad} should not be flagged as measured`);
  }
});

Deno.test("isMeasuredBmrFresh: same day and within the 7-day window are fresh", () => {
  assert(isMeasuredBmrFresh("2026-08-08", "2026-08-08"));
  assert(isMeasuredBmrFresh("2026-08-01", "2026-08-08"));
});

Deno.test("isMeasuredBmrFresh: older than 7 days is stale", () => {
  assert(!isMeasuredBmrFresh("2026-07-31", "2026-08-08"));
});

Deno.test("isMeasuredBmrFresh: a future-dated snapshot (clock skew) is rejected rather than trusted", () => {
  assert(!isMeasuredBmrFresh("2026-08-09", "2026-08-08"));
});
