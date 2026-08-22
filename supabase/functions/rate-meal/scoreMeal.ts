// Deterministic meal-fit scoring -- item 8 fix. The old rate-meal asked
// Claude to invent both the 1-10 score AND the rationale directly from raw
// macros, with no signal at all for alcohol, food-processing level, or fat
// share of calories -- "Beer And Burger" scored 7/10 "Great fit" for a
// bulking goal. The score is now computed entirely here: a protein-density
// base score, adjusted by deterministic modifiers, each carrying a stable
// key so buildRationale (below) can never write text that contradicts the
// number it's describing -- same "split into a pure module, colocated
// *_test.ts" shape as parse-meal-text/estimateBounds.ts.
//
// rate-meal/index.ts's one remaining Claude call only ever extracts
// containsAlcohol/processedLevel from the meal's free-text label -- a
// structured boolean/enum, never a numeric judgment.
//
// TARGETS-RELATIVE SCORING: index.ts already fetched the user's real
// nutrition_targets row before this change, but never actually passed it
// in here -- "against the user's real nutrition_targets" (this file's own
// header comment, historically) was aspirational, not true. `targets` is
// now a real parameter: largeCutShare compares against the user's actual
// daily_calories instead of a flat 900 kcal guess (falling back to that
// flat guess only when targets genuinely don't exist yet), and a new
// strongProteinShare modifier rewards a meal that covers a large chunk of
// the day's real protein goal -- distinct from highProteinDensity/
// solidProteinDensity below, which measure protein-per-calorie efficiency,
// not contribution toward today's actual target.

export interface MealMacros {
  calories: number;
  proteinG: number;
  carbsG: number | null;
  fatG: number | null;
}

/// Matches the raw nutrition_targets row shape (snake_case columns) --
/// index.ts passes this straight through from its own Supabase read, no
/// remapping. null means the user has no computed targets yet (never
/// uploaded goal photos or set a goal weight) -- every targets-relative
/// modifier below degrades gracefully rather than throwing when this is
/// null.
export interface NutritionTargets {
  daily_calories: number;
  daily_protein_g: number;
  daily_carbs_g: number;
  daily_fat_g: number;
}

export type TrainingEmphasis = "cut" | "bulk" | "recomp" | "maintain" | null;
export type ProcessedLevel = "whole" | "processed" | "ultra_processed";
export type MealSlot = "breakfast" | "lunch" | "dinner" | "snack";

export type ModifierKey =
  | "highProteinDensity"
  | "solidProteinDensity"
  | "lowProteinDensity"
  | "largeCutShare"
  | "strongProteinShare"
  | "veryHighFatShare"
  | "highFatShare"
  | "ultraProcessed"
  | "alcohol";

export interface ScoreModifier {
  key: ModifierKey;
  /// "+" if this modifier pushed the score up, "-" if it pushed it down --
  /// drives the +/- breakdown list in MealDetailView.
  sign: "+" | "-";
}

export interface MealScore {
  score: number;
  breakdown: ScoreModifier[];
}

/// Share of the day's calorie budget this single meal represents, above
/// which a "cut" goal treats it as a large share -- applied only when
/// real targets exist (see largeCutShare below for the no-targets
/// fallback).
const LARGE_CUT_SHARE_FRACTION = 0.4;
/// Flat kcal fallback for largeCutShare when the user has no computed
/// nutrition_targets yet -- the ORIGINAL threshold this modifier used
/// before targets-relative scoring existed, kept only as a degrade path,
/// not the primary rule anymore.
const LARGE_CUT_SHARE_FALLBACK_KCAL = 900;
/// Share of the day's protein target a single meal needs to cover to
/// count as a strong contribution -- a genuinely substantial chunk, not
/// just "more than average" (roughly a third of the day in one sitting).
const STRONG_PROTEIN_SHARE_FRACTION = 0.35;

/// Local hour, not UTC -- "breakfast" should mean breakfast in the user's
/// own day, not whatever the server's clock reads. Extracted/tagged for
/// future use; NOT wired into scoring yet -- the spec is explicit that
/// meal timing is a weak signal and the real gap here is alcohol/quality,
/// not timing.
export function mealSlotFromHour(localHour: number): MealSlot {
  if (localHour < 11) return "breakfast";
  if (localHour < 16) return "lunch";
  if (localHour < 21) return "dinner";
  return "snack";
}

/// Protein density (g protein per 100 kcal) is a goal-agnostic signal of
/// "does this meal actually support training", used as the base score
/// regardless of cut/bulk/recomp -- goal direction only adjusts for
/// calorie-share fit on top of that, never protein itself.
function baseScore(macros: MealMacros, trainingEmphasis: TrainingEmphasis): { score: number; modifier: ScoreModifier | null } {
  const proteinPer100kcal = macros.calories > 0 ? (macros.proteinG * 100) / macros.calories : 0;
  let score = 5;
  let modifier: ScoreModifier | null = null;
  if (proteinPer100kcal >= 12) {
    score = 8;
    modifier = { key: "highProteinDensity", sign: "+" };
  } else if (proteinPer100kcal >= 8) {
    score = 7;
    modifier = { key: "solidProteinDensity", sign: "+" };
  } else if (proteinPer100kcal < 4) {
    score = 4;
    modifier = { key: "lowProteinDensity", sign: "-" };
  }
  return { score, modifier };
}

export function scoreMeal(
  macros: MealMacros,
  targets: NutritionTargets | null,
  trainingEmphasis: TrainingEmphasis,
  containsAlcohol: boolean,
  processedLevel: ProcessedLevel,
): MealScore {
  const breakdown: ScoreModifier[] = [];
  const base = baseScore(macros, trainingEmphasis);
  let score = base.score;
  if (base.modifier) breakdown.push(base.modifier);

  // Cut: a single meal eating up a large share of a day's calorie budget
  // works against the goal even if the macros look fine in isolation.
  // Bulk/recomp/maintain: the same large share is fine/expected, never
  // penalized for it. Prefers the user's real daily_calories; only falls
  // back to the flat kcal guess when targets genuinely don't exist yet.
  if (trainingEmphasis === "cut") {
    const isLargeShare = targets && targets.daily_calories > 0
      ? macros.calories / targets.daily_calories > LARGE_CUT_SHARE_FRACTION
      : macros.calories > LARGE_CUT_SHARE_FALLBACK_KCAL;
    if (isLargeShare) {
      score -= 1;
      breakdown.push({ key: "largeCutShare", sign: "-" });
    }
  }

  // Positive signal, any goal: this one meal alone covers a substantial
  // share of today's real protein target -- meaningfully different from
  // highProteinDensity/solidProteinDensity above, which are about
  // efficiency per calorie, not progress toward the day's actual number.
  if (targets && targets.daily_protein_g > 0 && macros.proteinG / targets.daily_protein_g >= STRONG_PROTEIN_SHARE_FRACTION) {
    score += 1;
    breakdown.push({ key: "strongProteinShare", sign: "+" });
  }

  const fatShareOfCalories = macros.fatG !== null && macros.calories > 0 ? (macros.fatG * 9) / macros.calories : null;
  if (fatShareOfCalories !== null && fatShareOfCalories > 0.55) {
    score -= 2;
    breakdown.push({ key: "veryHighFatShare", sign: "-" });
  } else if (fatShareOfCalories !== null && fatShareOfCalories > 0.4) {
    score -= 1;
    breakdown.push({ key: "highFatShare", sign: "-" });
  }

  if (processedLevel === "ultra_processed") {
    score -= 1;
    breakdown.push({ key: "ultraProcessed", sign: "-" });
  }

  if (containsAlcohol) {
    // Ceiling, not a delta -- alcohol directly suppresses protein
    // synthesis/recovery regardless of how good the macros otherwise
    // look, so it caps whatever the modifiers above already computed
    // rather than just subtracting a fixed amount off it. Applied last.
    score = Math.min(score, 5);
    breakdown.push({ key: "alcohol", sign: "-" });
  }

  score = Math.max(1, Math.min(10, Math.round(score)));
  return { score, breakdown };
}
