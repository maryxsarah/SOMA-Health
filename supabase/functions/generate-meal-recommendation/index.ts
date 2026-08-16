// generate-meal-recommendation
//
// "What can I make?" -- turns a freeform description of what's in the
// user's fridge/pantry (typed or dictated, see Soma's SpeechRecognizer)
// into ONE complete recipe suggestion: why it fits what's left of today's
// nutrition target and goal direction, exact ingredient quantities, and
// step-by-step prep instructions using ONLY equipment the user actually
// owns (users.household_equipment). Body: { ingredients: string }.
// Response: { name, whyThisMeal, ingredients: [{name, quantity}],
// steps: string[], equipmentUsed: string[], totalTimeMinutes, calories,
// proteinG, carbsG, fatG }.
//
// Like parse-meal-text, this is a SUGGESTION, never auto-saved server-side
// -- the client shows it back and only writes to meal_log if the user
// taps "Log this meal" (source 'recipe_ai', see the migration that widens
// meal_log_source_check alongside this function).

import { handleOptions, jsonResponse } from "../_shared/cors.ts";
import { requireUser, serviceRoleClient } from "../_shared/clients.ts";
import { checkFlatDailyLimit, logGeneration } from "../_shared/generationLimits.ts";
import { effectiveCarbsTargetG } from "./recoveryDayAdjustment.ts";

// A user asking "what can I make?" a few times while actually standing in
// the kitchen deciding is the real use case -- generous like
// parse-meal-text's own limit, still bounded against a scripted account.
const FLAT_DAILY_LIMIT = 20;

const ANTHROPIC_API_URL = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_VERSION = "2023-06-01";
const MODEL = "claude-haiku-4-5";

// Mirrors Soma/Models/KitchenEquipmentTag.swift's displayName exactly --
// kept in sync by hand (same small-fixed-vocabulary duplication this
// codebase already accepts for EquipmentTag; there's no shared package
// between the Swift client and Deno functions to import it from instead).
const EQUIPMENT_LABELS: Record<string, string> = {
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
const SKIP_DEFAULT_KEYS = ["stove", "oven", "microwave"];

interface ClaudeRecommendation {
  name: string;
  why_this_meal: string;
  ingredients: { name: string; quantity: string }[];
  steps: string[];
  equipment_used: string[];
  total_time_minutes: number;
  calories: number;
  protein_g: number;
  carbs_g: number;
  fat_g: number;
}

Deno.serve(async (req: Request) => {
  const preflight = handleOptions(req);
  if (preflight) return preflight;

  try {
    const userId = await requireUser(req);
    const body = await req.json().catch(() => ({}));
    const ingredients: string | undefined = body.ingredients;
    if (!ingredients || !ingredients.trim()) {
      return jsonResponse({ error: "missing 'ingredients'" }, 400);
    }

    const supabase = serviceRoleClient();
    const date = new Date().toISOString().slice(0, 10);

    const allowed = await checkFlatDailyLimit(supabase, userId, date, "meal_recommendation", FLAT_DAILY_LIMIT);
    if (!allowed) {
      return jsonResponse({ error: "Too many meal ideas today. Try again tomorrow." }, 429);
    }

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

    // BUG report: this function had zero awareness of today's category --
    // meal guidance was macro-target-only regardless of whether today was
    // push_hard or rest. Same table generate-recommendation upserts every
    // call, read here read-only. Best-effort: a missing row (no
    // recommendation generated yet today) just means no category-specific
    // framing, not an error -- the rest of this function already degrades
    // gracefully with no daily_recommendation on file.
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
    // Same "informational, not authoritative" role recent history plays
    // in rate-meal's own prompt.
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
    const equipmentLabels = equipmentKeys
      .filter((k) => k !== "other")
      .map((k) => EQUIPMENT_LABELS[k])
      .filter((label): label is string => Boolean(label));
    const otherEquipment = equipmentKeys.includes("other")
      ? (userRow?.other_household_equipment_notes ?? "").split(",").map((s: string) => s.trim()).filter(Boolean)
      : [];
    let allEquipmentLabels = [...equipmentLabels, ...otherEquipment];
    // Defends the one edge case the two derivations above don't cover on
    // their own: household_equipment = ['other'] with no notes text ever
    // saved, which would otherwise produce an empty allow-list a real
    // recipe can never validate against.
    if (allEquipmentLabels.length === 0) allEquipmentLabels = SKIP_DEFAULT_KEYS.map((k) => EQUIPMENT_LABELS[k]);

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

    // Real coaching behavior, not just a calorie/macro number blind to
    // training status -- BUG report: this function had zero awareness of
    // today's category at all.
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

    const recommendation = await callClaude({
      ingredients: ingredients.trim(),
      equipmentLabels: allEquipmentLabels,
      remainingLine,
      recoveryLine,
      goalLine,
      recentLine,
    });

    await logGeneration(supabase, userId, date, "meal_recommendation");
    return jsonResponse(toResponse(recommendation));
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    const status = msg === "unauthorized" ? 401 : 500;
    return jsonResponse({ error: msg }, status);
  }
});

function buildSchema(equipmentLabels: string[]) {
  return {
    type: "object",
    properties: {
      name: { type: "string" },
      why_this_meal: { type: "string" },
      ingredients: {
        type: "array",
        items: {
          type: "object",
          properties: {
            name: { type: "string" },
            quantity: { type: "string" },
          },
          required: ["name", "quantity"],
          additionalProperties: false,
        },
      },
      steps: { type: "array", items: { type: "string" } },
      // Closed vocabulary, same "deterministic vocabulary, never free
      // text" pattern generate-workout-plan uses for exercise names -- the
      // model literally cannot claim equipment the user doesn't have.
      equipment_used: { type: "array", items: { type: "string", enum: equipmentLabels } },
      total_time_minutes: { type: "integer" },
      calories: { type: "integer" },
      protein_g: { type: "integer" },
      carbs_g: { type: "integer" },
      fat_g: { type: "integer" },
    },
    required: [
      "name",
      "why_this_meal",
      "ingredients",
      "steps",
      "equipment_used",
      "total_time_minutes",
      "calories",
      "protein_g",
      "carbs_g",
      "fat_g",
    ],
    additionalProperties: false,
  };
}

interface ClaudeInput {
  ingredients: string;
  equipmentLabels: string[];
  remainingLine: string;
  /// Non-empty only on a rest/light recovery day -- steers framing toward
  /// protein/hydration/anti-inflammatory coaching, real behavior a
  /// category-blind macro-fill prompt can't produce.
  recoveryLine: string;
  goalLine: string;
  recentLine: string;
}

async function callClaude(input: ClaudeInput): Promise<ClaudeRecommendation> {
  const apiKey = Deno.env.get("ANTHROPIC_API_KEY")!;
  const schema = buildSchema(input.equipmentLabels);

  const prompt =
    `A fitness app user asked what they can cook. Here's what they said they have: "${input.ingredients}".

They have access to ONLY this kitchen equipment: ${input.equipmentLabels.join(", ")}. Never write a step that requires equipment outside this list -- if a normal method would need something they don't have (e.g. an oven), find a real way to do it with what they DO have, or say plainly that what they listed can't be cooked with what's on hand rather than assuming equipment they don't own.

${input.remainingLine}
${input.recoveryLine}
${input.goalLine}
${input.recentLine}

Suggest ONE complete meal using primarily what they listed (a few common pantry basics -- salt, pepper, cooking oil, water -- are fine to assume even if unlisted). Prefer what they actually have over inventing new ingredients; only add something extra if it's essential and genuinely likely to already be on hand.

Return:
- name: a short, appetizing meal name
- why_this_meal: one or two encouraging sentences on why this fits their remaining macros and goal today -- reference the actual numbers, write like a supportive coach, never clinical
- ingredients: array of {name, quantity} with realistic quantities for one serving
- steps: array of clear, sequential instructions as full sentences -- any step involving heat must name the exact equipment (from the allowed list), the temperature if relevant, and the cook time (e.g. "Preheat the oven to 200°C/400°F and roast for 18 minutes")
- equipment_used: which of the allowed equipment this recipe actually needs (a subset of the list above -- omit anything unused)
- total_time_minutes: realistic total time including prep
- calories, protein_g, carbs_g, fat_g: realistic totals for the whole plated meal, whole numbers`;

  const res = await fetch(ANTHROPIC_API_URL, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": ANTHROPIC_VERSION,
    },
    body: JSON.stringify({
      model: MODEL,
      max_tokens: 1500,
      output_config: { format: { type: "json_schema", schema } },
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
  return JSON.parse(textBlock.text) as ClaudeRecommendation;
}

// camelCase over the wire, same convention as parse-meal-text's
// MealEstimate response -- the Swift side decodes with a plain
// JSONDecoder() and no snake_case conversion strategy.
function toResponse(r: ClaudeRecommendation) {
  return {
    name: r.name,
    whyThisMeal: r.why_this_meal,
    ingredients: r.ingredients,
    steps: r.steps,
    equipmentUsed: r.equipment_used,
    totalTimeMinutes: r.total_time_minutes,
    calories: r.calories,
    proteinG: r.protein_g,
    carbsG: r.carbs_g,
    fatG: r.fat_g,
  };
}
