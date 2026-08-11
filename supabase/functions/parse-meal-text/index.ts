// parse-meal-text
//
// Turns a freeform description of what a user ate (e.g. "2 eggs, toast,
// and coffee with milk") into an estimated calorie/macro breakdown, using
// Claude Haiku. Body: { text: string }. Response:
// { label, calories, proteinG, carbsG, fatG }.
//
// This is an ESTIMATE, never auto-saved server-side -- the client always
// shows it back in the same editable LogMealView form used for plain
// manual entry, so the user reviews/adjusts before it's actually written
// to meal_log. Keeps this endpoint a pure "estimate" step with no writes
// of its own, same separation as suggest-workout-addons.

import { handleOptions, jsonResponse } from "../_shared/cors.ts";
import { requireUser, serviceRoleClient } from "../_shared/clients.ts";
import { checkFlatDailyLimit, logGeneration } from "../_shared/generationLimits.ts";
import { clampEstimate, type MealEstimate } from "./estimateBounds.ts";
import { languageName } from "../_shared/language.ts";

// Meals are logged multiple times a day (breakfast/lunch/dinner/snacks),
// unlike the once-a-day workout generation -- a generous flat ceiling,
// purely defense-in-depth against a single account scripting repeated
// calls, not a product-facing quota.
const FLAT_DAILY_LIMIT = 40;

const ANTHROPIC_API_URL = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_VERSION = "2023-06-01";
const MODEL = "claude-haiku-4-5";

const ESTIMATE_SCHEMA = {
  type: "object",
  properties: {
    label: { type: "string" },
    calories: { type: "integer" },
    proteinG: { type: "integer" },
    carbsG: { type: "integer" },
    fatG: { type: "integer" },
  },
  required: ["label", "calories", "proteinG", "carbsG", "fatG"],
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
    const msg = err instanceof Error ? err.message : String(err);
    const status = msg === "unauthorized" ? 401 : 500;
    return jsonResponse({ error: msg }, status);
  }
});

async function callClaude(text: string, language: string): Promise<MealEstimate> {
  const apiKey = Deno.env.get("ANTHROPIC_API_KEY")!;
  const prompt = `A fitness app user just typed what they ate: "${text}"

Estimate its nutrition as realistically as you can. When the user didn't give amounts, assume typical realistic portion sizes (e.g. "a chicken breast" ≈ 150g cooked, "a bowl of rice" ≈ 1 cup cooked, "a coffee with milk" ≈ a splash of milk, not a full cup). If they described multiple items, sum the whole meal into one total.

Return:
- label: a short, cleaned-up version of what they described (under 8 words, title case, no calorie/macro numbers in it), written in ${language} regardless of what language the user typed in -- unless it's a specific dish/brand name better left as-is
- calories: total kcal for the whole meal, whole number
- proteinG, carbsG, fatG: total grams for the whole meal, whole numbers

Even if the description is vague, return your single best reasonable estimate rather than zeros -- the user reviews and can edit every number before it's saved, so a reasonable guess is always more useful than a blank.`;

  const res = await fetch(ANTHROPIC_API_URL, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": ANTHROPIC_VERSION,
    },
    body: JSON.stringify({
      model: MODEL,
      max_tokens: 512,
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
  return JSON.parse(textBlock.text) as MealEstimate;
}
