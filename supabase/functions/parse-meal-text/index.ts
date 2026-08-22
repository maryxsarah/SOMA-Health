// parse-meal-text
//
// Turns a freeform description of what a user ate (e.g. "2 eggs, toast,
// and coffee with milk") into an estimated calorie/macro breakdown. Body:
// { text: string }. Response:
// { label, calories, proteinG, carbsG, fatG, ingredients }.
//
// This is an ESTIMATE, never auto-saved server-side -- the client always
// shows it back in the same editable LogMealView form used for plain
// manual entry, so the user reviews/adjusts before it's actually written
// to meal_log. Keeps this endpoint a pure "estimate" step with no writes
// of its own, same separation as suggest-workout-addons.
//
// PER-INGREDIENT REASONING (not a single-shot total): real feedback --
// this endpoint used to ask for one aggregate total in a single shot
// ("sum the whole meal into one total"), which measurably drifted from
// reality (~400 kcal high on a real reported meal) versus how Claude's
// own nutrition chat estimates the same meal: decompose into ingredients
// with gram portions, estimate each ingredient's macros against
// nutrition-reference knowledge, THEN sum. This function now does the
// same -- Claude returns only the ingredients array; calories/proteinG/
// carbsG/fatG totals are computed by SUMMING it in code (sumIngredients,
// estimateBounds.ts), never asked of the model as an independent second
// number. That guarantees the returned total can never silently disagree
// with the model's own per-item numbers.
//
// MODEL: claude-sonnet-5, not claude-haiku-4-5 (every other Anthropic
// call in this codebase uses Haiku uniformly -- this is a deliberate,
// first-of-its-kind exception, not an oversight). Per-ingredient
// decomposition is a harder compositional-reasoning task than a single
// guess, this is the specific correctness bug driving this whole change,
// and the endpoint is user-initiated and already capped at
// FLAT_DAILY_LIMIT/day/user -- not a bulk/background call -- so the
// extra cost/latency is a reasonable tradeoff for directly fixing a
// correctness complaint users were noticing.

import { handleOptions, jsonResponse } from "../_shared/cors.ts";
import { requireUser, serviceRoleClient } from "../_shared/clients.ts";
import { classifyGenerationError } from "../_shared/anthropicErrors.ts";
import { checkFlatDailyLimit, logGeneration } from "../_shared/generationLimits.ts";
import { clampEstimate, type RawMealEstimate } from "./estimateBounds.ts";
import { languageName } from "../_shared/language.ts";

// Meals are logged multiple times a day (breakfast/lunch/dinner/snacks),
// unlike the once-a-day workout generation -- a generous flat ceiling,
// purely defense-in-depth against a single account scripting repeated
// calls, not a product-facing quota.
const FLAT_DAILY_LIMIT = 40;

const ANTHROPIC_API_URL = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_VERSION = "2023-06-01";
const MODEL = "claude-sonnet-5";

const ESTIMATE_SCHEMA = {
  type: "object",
  properties: {
    label: { type: "string" },
    ingredients: {
      type: "array",
      items: {
        type: "object",
        properties: {
          name: { type: "string" },
          gramsEstimate: { type: "number" },
          calories: { type: "integer" },
          proteinG: { type: "integer" },
          carbsG: { type: "integer" },
          fatG: { type: "integer" },
        },
        required: ["name", "gramsEstimate", "calories", "proteinG", "carbsG", "fatG"],
        additionalProperties: false,
      },
    },
  },
  required: ["label", "ingredients"],
  additionalProperties: false,
};

Deno.serve(async (req: Request) => {
  const preflight = handleOptions(req);
  if (preflight) return preflight;

  try {
    const userId = await requireUser(req);
    const body = await req.json().catch(() => ({}));
    const text: string | undefined = body.text;
    const language = languageName(body.language);

    if (!text || !text.trim()) {
      return jsonResponse({ error: "missing 'text'" }, 400);
    }

    const supabase = serviceRoleClient();
    const date = new Date().toISOString().slice(0, 10);
    const allowed = await checkFlatDailyLimit(supabase, userId, date, "meal_text_estimate", FLAT_DAILY_LIMIT);
    if (!allowed) {
      return jsonResponse({ error: "Too many estimates today. Enter the numbers directly, or try again tomorrow." }, 429);
    }

    const estimate = clampEstimate(await callClaude(text.trim(), language));
    await logGeneration(supabase, userId, date, "meal_text_estimate");
    return jsonResponse(estimate);
  } catch (err) {
    const { status, body } = classifyGenerationError(err);
    return jsonResponse(body, status);
  }
});

async function callClaude(text: string, _language: string): Promise<RawMealEstimate> {
  const apiKey = Deno.env.get("ANTHROPIC_API_KEY")!;
  const prompt = `A fitness app user just typed what they ate: "${text}"

Estimate its nutrition the way a careful nutrition-database lookup would, in two steps:

1. Split the description into individual food items. When the user didn't give amounts, assume typical realistic portion sizes (e.g. "2 eggs" ≈ 100g, "a chicken breast" ≈ 150g cooked, "a bowl of rice" ≈ 1 cup cooked (~158g), "a coffee with milk" ≈ a splash of milk, not a full cup, "a slice of toast" ≈ 30g). Estimate a realistic gram amount for each item.
2. For EACH item independently, estimate its calories, protein, carbs, and fat using standard per-100g nutrition-reference values for that food, scaled to the item's estimated gram amount -- the same way a careful manual calculation would, not a single intuitive guess for the whole plate.

Do NOT return a total for the meal -- only the per-ingredient array. The total is computed by summing your ingredients afterward, so accuracy on each individual ingredient is what actually matters here.

Return:
- label: a short version of what they described (under 8 words, no calorie/macro numbers in it), keeping the user's own language, wording and capitalization -- never convert it to Title Case, never translate a name they typed themselves
- ingredients: array of {name, gramsEstimate, calories, proteinG, carbsG, fatG} -- one entry per distinct food item, name written in the user's own language and wording (same rule as label above, never translated or Title-Cased), gramsEstimate and the four macro fields as realistic numbers for that item's estimated portion

Even if the description is vague, return your single best reasonable per-ingredient estimate rather than zeros -- the user reviews and can edit every number before it's saved, so a reasonable guess is always more useful than a blank.`;

  const res = await fetch(ANTHROPIC_API_URL, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": ANTHROPIC_VERSION,
    },
    body: JSON.stringify({
      model: MODEL,
      max_tokens: 1200,
      output_config: { format: { type: "json_schema", schema: ESTIMATE_SCHEMA } },
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
  return JSON.parse(textBlock.text) as RawMealEstimate;
}
