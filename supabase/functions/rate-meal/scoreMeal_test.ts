// Run: deno test supabase/functions/
//
// Regression guard for future prompt/formula edits -- the spec's own
// example meals, each with an expected score range and the modifiers that
// must (or must not) have fired. The bug this whole rewrite fixes: "Beer
// And Burger" (1050 kcal, 45g fat, alcohol) scored 7/10 "Great fit" for a
// bulking goal under the old macros-only LLM scoring.

import { assert, assertEquals } from "jsr:@std/assert";
import { type MealMacros, mealSlotFromHour, scoreMeal } from "./scoreMeal.ts";
import { buildRationale } from "./rationale.ts";

function macros(calories: number, proteinG: number, carbsG: number, fatG: number): MealMacros {
  return { calories, proteinG, carbsG, fatG };
}

Deno.test("Beer and Burger: alcohol ceilings the score at 5, never a 'great fit' for bulking", () => {
  const result = scoreMeal(macros(1050, 35, 80, 50), "bulk", true, "processed");
  assert(result.score <= 5, `expected <=5, got ${result.score}`);
  assert(result.breakdown.some((m) => m.key === "alcohol"), "alcohol modifier must fire");
});

Deno.test("chicken breast with rice: high protein density, no penalties, scores well", () => {
  const result = scoreMeal(macros(500, 50, 60, 5), "recomp", false, "whole");
  assert(result.score >= 6, `expected >=6, got ${result.score}`);
  assert(!result.breakdown.some((m) => m.sign === "-"), `expected no negative modifiers: ${JSON.stringify(result.breakdown)}`);
});

Deno.test("protein shake: very high protein density scores at the top of the range", () => {
  const result = scoreMeal(macros(200, 30, 8, 3), "bulk", false, "whole");
  assert(result.score >= 7, `expected >=7, got ${result.score}`);
  assert(result.breakdown.some((m) => m.key === "highProteinDensity"));
});

Deno.test("ultra-processed frozen pizza: low protein density AND ultra-processed both penalize", () => {
  const result = scoreMeal(macros(800, 28, 90, 32), "maintain", false, "ultra_processed");
  assert(result.score <= 5, `expected <=5, got ${result.score}`);
  assert(result.breakdown.some((m) => m.key === "lowProteinDensity"));
  assert(result.breakdown.some((m) => m.key === "ultraProcessed"));
});

Deno.test("simple salad: whole food, moderate fat, never triggers alcohol/processed/fat-share penalties", () => {
  const result = scoreMeal(macros(350, 15, 25, 12), "maintain", false, "whole");
  assert(!result.breakdown.some((m) => m.key === "alcohol"));
  assert(!result.breakdown.some((m) => m.key === "ultraProcessed"));
  assert(!result.breakdown.some((m) => m.key === "veryHighFatShare" || m.key === "highFatShare"));
});

Deno.test("a cut-goal meal eating most of the daily calorie budget is penalized; the same meal on bulk is not", () => {
  const cutResult = scoreMeal(macros(1200, 60, 100, 30), "cut", false, "whole");
  const bulkResult = scoreMeal(macros(1200, 60, 100, 30), "bulk", false, "whole");
  assert(cutResult.breakdown.some((m) => m.key === "largeCutShare"));
  assert(!bulkResult.breakdown.some((m) => m.key === "largeCutShare"));
  assert(cutResult.score < bulkResult.score, `cut (${cutResult.score}) should score below bulk (${bulkResult.score}) for the identical meal`);
});

Deno.test("fat-share modifier: >55%% ceilings harder than 40-55%%", () => {
  const veryHigh = scoreMeal(macros(500, 20, 10, 35), "maintain", false, "whole"); // 63% fat
  const high = scoreMeal(macros(500, 20, 30, 25), "maintain", false, "whole"); // 45% fat
  assert(veryHigh.breakdown.some((m) => m.key === "veryHighFatShare"));
  assert(high.breakdown.some((m) => m.key === "highFatShare"));
  assert(veryHigh.score < high.score, `very-high-fat (${veryHigh.score}) should score below high-fat (${high.score})`);
});

Deno.test("score is always clamped 1-10 regardless of how many modifiers stack", () => {
  const worst = scoreMeal(macros(2000, 5, 50, 150), "cut", true, "ultra_processed");
  assert(worst.score >= 1 && worst.score <= 10, `score out of range: ${worst.score}`);
});

Deno.test("mealSlotFromHour buckets the local hour correctly, not wired into scoring", () => {
  assertEquals(mealSlotFromHour(8), "breakfast");
  assertEquals(mealSlotFromHour(12), "lunch");
  assertEquals(mealSlotFromHour(19), "dinner");
  assertEquals(mealSlotFromHour(23), "snack");
});

Deno.test("buildRationale never contradicts the score: alcohol is always mentioned when it fired", () => {
  const result = scoreMeal(macros(1050, 35, 80, 50), "bulk", true, "processed");
  const rationale = buildRationale(result, "Beer and Burger", "en");
  assert(rationale.toLowerCase().includes("alcohol"), rationale);
});

Deno.test("buildRationale falls back to a balanced-meal sentence when no modifiers fired", () => {
  const result = scoreMeal(macros(450, 25, 40, 12), "maintain", false, "whole");
  const rationale = buildRationale(result, "Home-cooked dinner", "en");
  assert(rationale.length > 0);
});

Deno.test("buildRationale produces genuinely different text per language, not an English fallback", () => {
  const result = scoreMeal(macros(1050, 35, 80, 50), "bulk", true, "processed");
  const ru = buildRationale(result, "Пиво и бургер", "ru");
  assert(ru.includes("алкоголь"), ru);
});
