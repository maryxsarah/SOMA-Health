// Everything both generate-meal-recommendation modes (on-demand and
// daily-autopilot) need to build the prompt: household equipment,
// today's remaining macros (recovery-day adjusted), goal direction, and
// recent meals to avoid repeating. Pulled out of index.ts so both modes
// share one read/adjustment path with zero duplication -- this is how
// the daily-autopilot plan automatically inherits recoveryDayAdjustment.ts's
// effectiveCarbsTargetG and all existing macro/goal logic.

import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { effectiveCarbsTargetG } from "./recoveryDayAdjustment.ts";

// Mirrors Soma/Models/KitchenEquipmentTag.swift's displayName exactly --
// kept in sync by hand (same small-fixed-vocabulary duplication this
// codebase already accepts for EquipmentTag; there's no shared package
// between the Swift client and Deno functions to import it from instead).
export const EQUIPMENT_LABELS: Record<string, string> = {
  stove: "Stove",
  oven: "Oven",
  microwave: "Microwave",
  air_fryer: "Air Fryer",
  blender: "Blender",
  mixer: "Mixer",
  thermomix: "Thermomix",
  grill: "Grill",
  rice_cooker: "Rice Cooker",
  slow_cooker: "Slow Cooker",
  pressure_cooker: "Pressure Cooker / Instant Pot",
  food_processor: "Food Processor",
  toaster: "Toaster",
};

// Mirrors KitchenEquipmentTag.skipDefault -- applied when
// household_equipment is empty (never set, or explicitly skipped at
// onboarding) so a recipe request always has real, plausible equipment to
// work with instead of failing equipment validation against an empty set.
export const SKIP_DEFAULT_KEYS = ["stove", "oven", "microwave"];

export interface PromptContext {
  equipmentOptions: string[];
  equipmentDescriptionForPrompt: string;
  remainingLine: string;
  /// Non-empty only on a rest/light recovery day -- steers framing toward
  /// protein/hydration/anti-inflammatory coaching.
  recoveryLine: string;
  goalLine: string;
  recentLine: string;
  category: string | null;
}

export async function buildPromptContext(supabase: SupabaseClient, userId: string, date: string): Promise<PromptContext> {
  const { data: userRow } = await supabase
    .from("users")
    .select("household_equipment, other_household_equipment_notes, training_emphasis")
    .eq("id", userId)
    .maybeSingle();

  const { data: targetsRow } = await supabase
    .from("nutrition_targets")
    .select("daily_calories, daily_protein_g, daily_carbs_g, daily_fat_g")
    .eq("user_id", userId)
    .maybeSingle();

  // Best-effort: a missing row (no recommendation generated yet today)
  // just means no category-specific framing, not an error.
  const { data: recommendationRow } = await supabase
    .from("daily_recommendation")
    .select("category")
    .eq("user_id", userId)
    .eq("date", date)
    .maybeSingle();
  const category = (recommendationRow?.category as string | null) ?? null;
  const isRecoveryDay = category === "rest" || category === "light";

  const { data: todaysMeals } = await supabase
    .from("meal_log")
    .select("calories, protein_g, carbs_g, fat_g")
    .eq("user_id", userId)
    .eq("date", date);

  // Last 3 days' labelled entries -- purely context so today's
  // suggestion doesn't repeat something just eaten, not a strict rule.
  const since = new Date(Date.now() - 3 * 24 * 60 * 60 * 1000).toISOString().slice(0, 10);
  const { data: recentMeals } = await supabase
    .from("meal_log")
    .select("label")
    .eq("user_id", userId)
    .gte("date", since)
    .not("label", "is", null)
    .order("logged_at", { ascending: false })
    .limit(10);

  const equipmentKeys: string[] = (userRow?.household_equipment ?? []).length > 0
    ? (userRow!.household_equipment as string[])
    : SKIP_DEFAULT_KEYS;
  const knownEquipmentKeys = equipmentKeys.filter((k) => k !== "other" && EQUIPMENT_LABELS[k]);
  const otherEquipment = equipmentKeys.includes("other")
    ? (userRow?.other_household_equipment_notes ?? "").split(",").map((s: string) => s.trim()).filter(Boolean)
    : [];
  let equipmentOptions = [...knownEquipmentKeys, ...otherEquipment];
  // Defends the one edge case the two derivations above don't cover on
  // their own: household_equipment = ['other'] with no notes text ever
  // saved, which would otherwise produce an empty allow-list a real
  // recipe can never validate against.
  if (equipmentOptions.length === 0) equipmentOptions = SKIP_DEFAULT_KEYS;
  const equipmentDescriptionForPrompt = [
    ...knownEquipmentKeys.map((k) => `${k} (${EQUIPMENT_LABELS[k]})`),
    ...otherEquipment,
  ].join(", ");

  const consumed = (todaysMeals ?? []).reduce(
    (acc, m) => ({
      calories: acc.calories + (m.calories ?? 0),
      proteinG: acc.proteinG + (m.protein_g ?? 0),
      carbsG: acc.carbsG + (m.carbs_g ?? 0),
      fatG: acc.fatG + (m.fat_g ?? 0),
    }),
    { calories: 0, proteinG: 0, carbsG: 0, fatG: 0 },
  );

  // See recoveryDayAdjustment.ts for why this is a LOCAL-ONLY adjustment
  // (never written back to the persisted nutrition_targets row).
  const effectiveCarbsTarget = targetsRow ? effectiveCarbsTargetG(targetsRow.daily_carbs_g, isRecoveryDay) : null;

  const remainingLine = targetsRow
    ? `They have ${Math.max(0, targetsRow.daily_calories - consumed.calories)} kcal, ${
      Math.max(0, targetsRow.daily_protein_g - consumed.proteinG)
    }g protein, ${Math.max(0, (effectiveCarbsTarget ?? targetsRow.daily_carbs_g) - consumed.carbsG)}g carbs, and ${
      Math.max(0, targetsRow.daily_fat_g - consumed.fatG)
    }g fat remaining in today's target (they've had ${consumed.calories} kcal so far today).`
    : "No daily nutrition target is on file for this user -- suggest a generally balanced, reasonably portioned meal instead.";

  const recoveryLine = isRecoveryDay
    ? `Today is a "${category}" recovery day (${
      category === "rest" ? "no training" : "light active recovery"
    } scheduled) -- lean the suggestion toward real recovery-day nutrition: protein-forward (muscle repair, satiety without excess calories), well-hydrating (water-rich ingredients, not just "drink water" advice), and anti-inflammatory where reasonable (e.g. oily fish, leafy greens, berries, olive oil, turmeric/ginger) over heavy/greasy comfort food. Carbs can run a little lighter than a hard-training day's -- today's target already reflects that.`
    : "";

  const goalLine = userRow?.training_emphasis
    ? `Their current goal direction is "${userRow.training_emphasis}" (cut = losing fat, bulk = gaining size, recomp = both/composition change, maintain = staying steady).`
    : "";

  const recentLine = (recentMeals ?? []).length > 0
    ? `They've recently eaten: ${(recentMeals ?? []).map((m) => m.label).join(", ")}. Suggest something different from these where reasonable.`
    : "";

  return { equipmentOptions, equipmentDescriptionForPrompt, remainingLine, recoveryLine, goalLine, recentLine, category };
}
