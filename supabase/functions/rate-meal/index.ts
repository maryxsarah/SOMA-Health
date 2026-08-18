// rate-meal
//
// Scores an already-logged meal_log row 1-10 against the user's real
// nutrition_targets and goal direction (training_emphasis), plus a short
// rationale -- "how well does this meal support your goal today", not a
// generic health judgment. Body: { mealLogId: string }. Response:
// { score, rationale, breakdown }.
//
// Item 8 fix: the score used to be a single unconstrained LLM judgment
// from raw macros -- no signal for alcohol, food-processing level, or fat
// share of calories, so "Beer And Burger" (1050 kcal, 45g fat, beer)
// scored 7/10 "Great fit" for a bulking goal. The score is now computed
// deterministically by scoreMeal.ts (baseScore from protein density ->
// modifiers -> clamp), and the rationale by rationale.ts, built FROM the
// same modifiers the score used -- text can never contradict the number
// anymore. The one Claude call left only extracts containsAlcohol/
// processedLevel from the meal's free-text label (a structured tag, never
// a numeric judgment).
//
// Computed once and written back onto the meal_log row itself (not
// re-scored every time the meal is opened) -- a stable score costs one
// API call instead of one per view, and never mysteriously changes
// between visits. `verdict` (excellent/normal/mediocre/offTarget) is
// deliberately NOT returned or stored here -- it's a pure function of
// score, derived client-side (MealVerdict in Swift), same "derive, don't
// duplicate" rule as NutritionDayProgress's fractions.

import { handleOptions, jsonResponse } from "../_shared/cors.ts";
import { requireUser, serviceRoleClient } from "../_shared/clients.ts";
import { checkFlatDailyLimit, logGeneration } from "../_shared/generationLimits.ts";
import { normalizeLanguageCode } from "../_shared/language.ts";
import { type MealMacros, mealSlotFromHour, type ProcessedLevel, scoreMeal, type TrainingEmphasis } from "./scoreMeal.ts";
import { buildRationale } from "./rationale.ts";

// Realistically bounded by how many meals a person logs in a day anyway
// (each rated at most once, ever) -- this is defense-in-depth against a
// single account scripting repeated calls, not a product-facing quota.
const FLAT_DAILY_LIMIT = 40;

const ANTHROPIC_API_URL = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_VERSION = "2023-06-01";
const MODEL = "claude-haiku-4-5";

const TAG_SCHEMA = {
  type: "object",
  properties: {
    containsAlcohol: { type: "boolean" },
    processedLevel: { type: "string", enum: ["whole", "processed", "ultra_processed"] },
  },
  required: ["containsAlcohol", "processedLevel"],
  additionalProperties: false,
};

interface MealTags {
  containsAlcohol: boolean;
  processedLevel: ProcessedLevel;
}

Deno.serve(async (req: Request) => {
  const preflight = handleOptions(req);
  if (preflight) return preflight;

  try {
    const userId = await requireUser(req);
    const body = await req.json().catch(() => ({}));
    const mealLogId: string | undefined = body.mealLogId;
    const language = normalizeLanguageCode(body.language);
    if (!mealLogId) return jsonResponse({ error: "missing 'mealLogId'" }, 400);

    const supabase = serviceRoleClient();

    // .eq("user_id", userId) here is the actual authorization check --
    // never trust a client-supplied id alone to scope a service-role read.
    const { data: meal, error: mealError } = await supabase
      .from("meal_log")
      .select("id, label, calories, protein_g, carbs_g, fat_g, logged_at")
      .eq("id", mealLogId)
      .eq("user_id", userId)
      .maybeSingle();
    if (mealError) throw new Error(`could not read meal_log: ${mealError.message}`);
    if (!meal) return jsonResponse({ error: "meal not found" }, 404);

    const date = new Date().toISOString().slice(0, 10);
    const allowed = await checkFlatDailyLimit(supabase, userId, date, "meal_rating", FLAT_DAILY_LIMIT);
    if (!allowed) {
      return jsonResponse({ error: "Too many meal ratings today. Try again tomorrow." }, 429);
    }

    const { data: targetsRow } = await supabase
      .from("nutrition_targets")
      .select("daily_calories, daily_protein_g, daily_carbs_g, daily_fat_g")
      .eq("user_id", userId)
      .maybeSingle();

    const { data: userRow } = await supabase
      .from("users")
      .select("training_emphasis")
      .eq("id", userId)
      .maybeSingle();

    const trainingEmphasis = (userRow?.training_emphasis ?? null) as TrainingEmphasis;
    const macros: MealMacros = {
      calories: meal.calories,
      proteinG: meal.protein_g,
      carbsG: meal.carbs_g,
      fatG: meal.fat_g,
    };
    const tags = await extractMealTags({ label: meal.label, calories: meal.calories, proteinG: meal.protein_g });
    const mealScore = scoreMeal(macros, trainingEmphasis, tags.containsAlcohol, tags.processedLevel);
    const rationale = buildRationale(mealScore, meal.label, language);
    // Tagged for future use (not wired into scoring this round -- see
    // scoreMeal.ts's own doc comment); logged_at is stored UTC, so this is
    // only a rough local-hour bucket, not exact per-timezone accuracy.
    const loggedHour = new Date(meal.logged_at).getUTCHours();
    void mealSlotFromHour(loggedHour);
    // "<sign>:<key>" -- deliberately raw, not pre-translated server-side
    // text. MealDetailView maps each key to a localized short phrase
    // client-side, same "derive/localize on the client" posture as
    // MealVerdict itself.
    const breakdown = mealScore.breakdown.map((m) => `${m.sign}:${m.key}`);

    const { error: updateError } = await supabase
      .from("meal_log")
      .update({ score: mealScore.score, rationale, score_breakdown: breakdown })
      .eq("id", mealLogId);
    if (updateError) throw new Error(`could not write rating: ${updateError.message}`);

    await logGeneration(supabase, userId, date, "meal_rating");
    return jsonResponse({ score: mealScore.score, rationale, breakdown });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    const status = msg === "unauthorized" ? 401 : 500;
    return jsonResponse({ error: msg }, status);
  }
});

interface TagInput {
  label: string | null;
  calories: number;
  proteinG: number;
}

/// The one Claude call left in this function -- extracts containsAlcohol/
/// processedLevel from the meal's free-text label. A structured tag
/// extraction, never a numeric or qualitative judgment: the score and
/// rationale are both computed deterministically afterward (scoreMeal.ts /
/// rationale.ts) from whatever this returns.
async function extractMealTags(input: TagInput): Promise<MealTags> {
  // No label at all -- nothing to extract from, and guessing "processed"
  // vs "whole" from macros alone would be exactly the kind of unfounded
  // judgment this rewrite is trying to remove. Skip the API call.
  if (!input.label || input.label.trim().length === 0) {
    return { containsAlcohol: false, processedLevel: "whole" };
  }

  const apiKey = Deno.env.get("ANTHROPIC_API_KEY")!;
  const prompt = `A fitness app user logged this meal: "${input.label}" (${input.calories} kcal, ${input.proteinG}g protein).

Based ONLY on what's named, extract two facts:
- containsAlcohol: true if the meal/drink described contains any alcoholic beverage (beer, wine, spirits, cocktails, etc.), false otherwise.
- processedLevel: "whole" for whole/minimally-processed foods (fresh meat, vegetables, fruit, grains, home-cooked meals), "processed" for moderately processed foods (bread, cheese, canned goods, deli meat), "ultra_processed" for heavily industrially processed foods (fast food, packaged snacks, sugary drinks, candy, instant/frozen convenience meals).

Never invent ingredients beyond what was described. If genuinely ambiguous, default containsAlcohol to false and processedLevel to "processed".`;

  const res = await fetch(ANTHROPIC_API_URL, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": ANTHROPIC_VERSION,
    },
    body: JSON.stringify({
      model: MODEL,
      max_tokens: 150,
      output_config: { format: { type: "json_schema", schema: TAG_SCHEMA } },
      messages: [{ role: "user", content: prompt }],
    }),
  });
  if (!res.ok) {
    const errBody = await res.text();
    throw new Error(`Anthropic API error ${res.status}: ${errBody}`);
  }
  const json = await res.json();
  // deno-lint-ignore no-explicit-any
  const textBlock = (json.content ?? []).find((b: any) => b.type === "text");
  if (!textBlock?.text) throw new Error("No text content in Anthropic response");
  return JSON.parse(textBlock.text) as MealTags;
}
