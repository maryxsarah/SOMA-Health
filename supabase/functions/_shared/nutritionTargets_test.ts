import { assert, assertEquals } from "jsr:@std/assert";
import { activityLevelFromWorkoutsPerWeek, computeNutritionTargets } from "./nutritionTargets.ts";

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
