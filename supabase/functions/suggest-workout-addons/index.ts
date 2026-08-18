// suggest-workout-addons
//
// Turns freeform post-workout feedback (e.g. "I like doing a 5-10min
// incline treadmill before my workout") into exactly 3 concrete add-on
// suggestions for future similar workouts, using Claude Haiku. Body:
// { feedback: string, workoutTitle: string, bodyPart: string }.
//
// Uncached and not scaled by subscription tier like generate-workout-plan --
// feedback is occasional and the prompt/response here are small, so the
// cost profile doesn't need that same tiered "once a day" cap. Still gets a
// generous flat daily ceiling (see FLAT_DAILY_LIMIT below) purely as
// defense-in-depth against a single authenticated account scripting
// repeated calls -- not a product-facing quota.

import { handleOptions, jsonResponse } from "../_shared/cors.ts";
import { requireUser, serviceRoleClient } from "../_shared/clients.ts";
import { checkFlatDailyLimit, logGeneration } from "../_shared/generationLimits.ts";
import { languageName } from "../_shared/language.ts";

const FLAT_DAILY_LIMIT = 20;

const ANTHROPIC_API_URL = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_VERSION = "2023-06-01";
const MODEL = "claude-haiku-4-5";

const SUGGESTIONS_SCHEMA = {
  type: "object",
  properties: {
    suggestions: { type: "array", items: { type: "string" } },
  },
  required: ["suggestions"],
  additionalProperties: false,
};

Deno.serve(async (req: Request) => {
  const preflight = handleOptions(req);
  if (preflight) return preflight;

  try {
    const userId = await requireUser(req);
    const body = await req.json().catch(() => ({}));
    const feedback: string | undefined = body.feedback;
    const workoutTitle: string | undefined = body.workoutTitle;
    const bodyPart: string | undefined = body.bodyPart;
    const language = languageName(body.language);

    if (!feedback || !workoutTitle || !bodyPart) {
      return jsonResponse({ error: "missing 'feedback', 'workoutTitle', or 'bodyPart'" }, 400);
    }

    const supabase = serviceRoleClient();
    const date = new Date().toISOString().slice(0, 10);
    const allowed = await checkFlatDailyLimit(supabase, userId, date, "addon_suggestion", FLAT_DAILY_LIMIT);
    if (!allowed) {
      return jsonResponse({ error: "Too many requests today. Please try again tomorrow." }, 429);
    }

    const prompt = `A fitness app user just finished "${workoutTitle}" (target: ${bodyPart}) and left this feedback: "${feedback}"

Based on this feedback, suggest exactly 3 concrete, specific add-ons the app could include in future similar workouts -- each one a short phrase (under 10 words) naming a specific exercise, warm-up item, or adjustment, not vague advice. If the feedback already names something specific (e.g. a particular warm-up), include a version of it plus 2 closely related, fitting variations -- don't suggest something unrelated to what they said. Write every suggestion in ${language}.`;

    const suggestions = await callClaude(prompt);
    await logGeneration(supabase, userId, date, "addon_suggestion");
    return jsonResponse({ suggestions });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    const status = msg === "unauthorized" ? 401 : 500;
    return jsonResponse({ error: msg }, status);
  }
});

async function callClaude(prompt: string): Promise<string[]> {
  const apiKey = Deno.env.get("ANTHROPIC_API_KEY")!;
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
      output_config: { format: { type: "json_schema", schema: SUGGESTIONS_SCHEMA } },
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
  const parsed = JSON.parse(textBlock.text) as { suggestions: string[] };
  return parsed.suggestions.slice(0, 3);
}
