// suggest-workout-addons
//
// Turns freeform post-workout feedback (e.g. "I like doing a 5-10min
// incline treadmill before my workout") into exactly 3 concrete add-on
// suggestions for future similar workouts, using Claude Haiku. Body:
// { feedback: string, workoutTitle: string, bodyPart: string }.
//
// Uncached and not rate-limited like generate-workout-plan -- feedback is
// occasional and the prompt/response here are small, so the cost profile
// doesn't need the same "once a day" cap.

import { handleOptions, jsonResponse } from "../_shared/cors.ts";
import { requireUser } from "../_shared/clients.ts";

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
    await requireUser(req);
    const body = await req.json().catch(() => ({}));
    const feedback: string | undefined = body.feedback;
    const workoutTitle: string | undefined = body.workoutTitle;
    const bodyPart: string | undefined = body.bodyPart;

    if (!feedback || !workoutTitle || !bodyPart) {
      return jsonResponse({ error: "missing 'feedback', 'workoutTitle', or 'bodyPart'" }, 400);
    }

    const prompt = `A fitness app user just finished "${workoutTitle}" (target: ${bodyPart}) and left this feedback: "${feedback}"

Based on this feedback, suggest exactly 3 concrete, specific add-ons the app could include in future similar workouts -- each one a short phrase (under 10 words) naming a specific exercise, warm-up item, or adjustment, not vague advice. If the feedback already names something specific (e.g. a particular warm-up), include a version of it plus 2 closely related, fitting variations -- don't suggest something unrelated to what they said.`;

    const suggestions = await callClaude(prompt);
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
