// rate-meal
//
// Scores an already-logged meal_log row 1-10 against the user's real
// nutrition_targets and goal direction (training_emphasis), plus a short
// rationale -- "how well does this meal support your goal today", not a
// generic health judgment. Body: { mealLogId: string }. Response:
// { score, rationale }.
//
// Computed once and written back onto the meal_log row itself (not
// re-scored every time the meal is opened) -- a stable score costs one
// API call instead of one per view, and never mysteriously changes
// between visits. `verdict` (good/ok/not_great) is deliberately NOT
// returned or stored here -- it's a pure function of score, derived
// client-side (MealVerdict in Swift), same "derive, don't duplicate"
// rule as NutritionDayProgress's fractions.

import { handleOptions, jsonResponse } from "../_shared/cors.ts";
import { requireUser, serviceRoleClient } from "../_shared/clients.ts";
import { checkFlatDailyLimit, logGeneration } from "../_shared/generationLimits.ts";

// Realistically bounded by how many meals a person logs in a day anyway
// (each rated at most once, ever) -- this is defense-in-depth against a
// single account scripting repeated calls, not a product-facing quota.
const FLAT_DAILY_LIMIT = 40;

const ANTHROPIC_API_URL = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_VERSION = "2023-06-01";
const MODEL = "claude-haiku-4-5";

const RATING_SCHEMA = {
  type: "object",
  properties: {
    score: { type: "integer" },
    rationale: { type: "string" },
  },
  required: ["score", "rationale"],
  additionalProperties: false,
};

interface MealRating {
  score: number;
  rationale: string;
}

Deno.serve(async (req: Request) => {
  const preflight = handleOptions(req);
  if (preflight) return preflight;

  try {
    const userId = await requireUser(req);
    const body = await req.json().catch(() => ({}));
    const mealLogId: string | undefined = body.mealLogId;
    if (!mealLogId) return jsonResponse({ error: "missing 'mealLogId'" }, 400);

    const supabase = serviceRoleClient();

    // .eq("user_id", userId) here is the actual authorization check --
    // never trust a client-supplied id alone to scope a service-role read.
    const { data: meal, error: mealError } = await supabase
      .from("meal_log")
      .select("id, label, calories, protein_g, carbs_g, fat_g")
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

    const rating = await callClaude({
      label: meal.label,
      calories: meal.calories,
      proteinG: meal.protein_g,
      carbsG: meal.carbs_g,
      fatG: meal.fat_g,
      targets: targetsRow ?? null,
      trainingEmphasis: userRow?.training_emphasis ?? null,
    });

    const { error: updateError } = await supabase
      .from("meal_log")
      .update({ score: rating.score, rationale: rating.rationale })
      .eq("id", mealLogId);
    if (updateError) throw new Error(`could not write rating: ${updateError.message}`);

    await logGeneration(supabase, userId, date, "meal_rating");
    return jsonResponse(rating);
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    const status = msg === "unauthorized" ? 401 : 500;
    return jsonResponse({ error: msg }, status);
  }
});

interface RateInput {
  label: string | null;
  calories: number;
  proteinG: number;
  carbsG: number | null;
  fatG: number | null;
  targets: { daily_calories: number; daily_protein_g: number; daily_carbs_g: number; daily_fat_g: number } | null;
  trainingEmphasis: string | null;
}

async function callClaude(input: RateInput): Promise<MealRating> {
  const apiKey = Deno.env.get("ANTHROPIC_API_KEY")!;

  const mealDescription = input.label && input.label.trim().length > 0
    ? `"${input.label}"`
    : "an unnamed meal (only the numbers below were logged, no description)";

  const macroLine = `${input.calories} kcal, ${input.proteinG}g protein` +
    (input.carbsG !== null ? `, ${input.carbsG}g carbs` : "") +
    (input.fatG !== null ? `, ${input.fatG}g fat` : "");

  const targetsLine = input.targets
    ? `Their daily target is ${input.targets.daily_calories} kcal, ${input.targets.daily_protein_g}g protein, ${input.targets.daily_carbs_g}g carbs, ${input.targets.daily_fat_g}g fat.`
    : "No daily nutrition target is on file for this user -- judge the meal on general nutritional balance instead.";

  const goalLine = input.trainingEmphasis
    ? `Their current goal direction is "${input.trainingEmphasis}" (cut = losing fat, bulk = gaining size, recomp = both/composition change, maintain = staying steady).`
    : "";

  const prompt = `A fitness app user logged this meal: ${mealDescription} -- ${macroLine}.

${targetsLine}
${goalLine}

Rate how well this single meal supports their goal today, on a scale of 1 (not a great fit) to 10 (a great fit). Consider protein adequacy, how the calories/macros fit within a reasonable share of their daily target, and -- if the meal is named -- what that food typically offers. Do not be preachy or clinical -- write like a supportive coach giving one honest, specific sentence, referencing the actual numbers or food where it's useful. Never invent ingredients or nutrients beyond what was described.

Return:
- score: integer 1-10
- rationale: one short sentence (under 30 words) explaining the score`;

  const res = await fetch(ANTHROPIC_API_URL, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": ANTHROPIC_VERSION,
    },
    body: JSON.stringify({
      model: MODEL,
      max_tokens: 300,
      output_config: { format: { type: "json_schema", schema: RATING_SCHEMA } },
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
  const parsed = JSON.parse(textBlock.text) as MealRating;
  // Clamp defensively -- the schema doesn't enforce a numeric range, only
  // that it's an integer.
  return { score: Math.max(1, Math.min(10, Math.round(parsed.score))), rationale: parsed.rationale };
}
