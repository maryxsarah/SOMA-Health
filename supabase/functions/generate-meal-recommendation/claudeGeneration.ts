// The actual Claude Haiku call + its JSON schema + the wire-format
// mapping, shared unchanged by both generate-meal-recommendation modes
// (on-demand and daily-autopilot) -- pulled out of index.ts purely to
// keep that file's two-mode branching readable; no behavior change from
// when this all lived inline.

const ANTHROPIC_API_URL = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_VERSION = "2023-06-01";
const MODEL = "claude-haiku-4-5";

export interface ClaudeRecommendation {
  name: string;
  why_this_meal: string;
  ingredients: { name: string; quantity: string }[];
  steps: { text: string; duration_seconds: number | null }[];
  equipment_used: string[];
  total_time_minutes: number;
  calories: number;
  protein_g: number;
  carbs_g: number;
  fat_g: number;
}

export interface ClaudeInput {
  ingredients: string;
  equipmentOptions: string[];
  equipmentDescriptionForPrompt: string;
  remainingLine: string;
  recoveryLine: string;
  goalLine: string;
  recentLine: string;
  language: string;
}

function buildSchema(equipmentOptions: string[]) {
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
      // duration_seconds is required (not omittable) so the model must
      // explicitly decide per step rather than silently leaving it out --
      // null for any step that isn't a wait (chopping, seasoning), a
      // whole-number second count for one that is (CookModeView renders a
      // real countdown off this, e.g. "flip the pancakes" -> 30).
      steps: {
        type: "array",
        items: {
          type: "object",
          properties: {
            text: { type: "string" },
            duration_seconds: { type: ["integer", "null"] },
          },
          required: ["text", "duration_seconds"],
          additionalProperties: false,
        },
      },
      // Closed vocabulary, same "deterministic vocabulary, never free
      // text" pattern generate-workout-plan uses for exercise names -- the
      // model literally cannot claim equipment the user doesn't have.
      // Values are stable identifiers (e.g. "stove"), not display labels,
      // so the client can localize known equipment via
      // KitchenEquipmentTag.displayName regardless of the request language.
      equipment_used: { type: "array", items: { type: "string", enum: equipmentOptions } },
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

export async function callClaude(input: ClaudeInput): Promise<ClaudeRecommendation> {
  const apiKey = Deno.env.get("ANTHROPIC_API_KEY")!;
  const schema = buildSchema(input.equipmentOptions);

  const prompt =
    `A fitness app user asked what they can cook. Here's what they said they have: "${input.ingredients}".

They have access to ONLY this kitchen equipment: ${input.equipmentDescriptionForPrompt}. Never write a step that requires equipment outside this list -- if a normal method would need something they don't have (e.g. an oven), find a real way to do it with what they DO have, or say plainly that what they listed can't be cooked with what's on hand rather than assuming equipment they don't own.

${input.remainingLine}
${input.recoveryLine}
${input.goalLine}
${input.recentLine}

Suggest ONE complete meal using primarily what they listed (a few common pantry basics -- salt, pepper, cooking oil, water -- are fine to assume even if unlisted). Prefer what they actually have over inventing new ingredients; only add something extra if it's essential and genuinely likely to already be on hand.

Return:
- name: a short, appetizing meal name
- why_this_meal: one or two encouraging sentences on why this fits their remaining macros and goal today -- reference the actual numbers, write like a supportive coach, never clinical
- ingredients: array of {name, quantity} with realistic quantities for one serving
- steps: array of {text, duration_seconds}. text is a clear, sequential instruction as a full sentence -- any step involving heat must name the exact equipment (from the allowed list), the temperature if relevant, and the cook time stated in the sentence itself (e.g. "Preheat the oven to 200°C/400°F and roast for 18 minutes"), so it still reads correctly on its own. duration_seconds is that same wait, in whole seconds, ONLY when the step genuinely involves waiting/cooking passively (roasting, simmering, resting, a timed flip) -- null for anything active (chopping, seasoning, stirring, plating) or with no specific duration. A short, precise wait like "flip after 30 seconds" should use duration_seconds: 30, not be rounded away.
- equipment_used: which of the allowed equipment this recipe actually needs -- return using the identifier before the parenthesis above (e.g. "stove", not "Stove"), a subset of the list (omit anything unused)
- total_time_minutes: realistic total time including prep
- calories, protein_g, carbs_g, fat_g: realistic totals for the whole plated meal, whole numbers

Write every piece of narrative text in ${input.language} -- name, why_this_meal, ingredient names, and steps. Never translate equipment_used values -- return those exactly as the identifiers listed above, regardless of language.`;

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
export function toResponse(r: ClaudeRecommendation) {
  return {
    name: r.name,
    whyThisMeal: r.why_this_meal,
    ingredients: r.ingredients,
    steps: r.steps.map((s) => ({ text: s.text, durationSeconds: s.duration_seconds })),
    equipmentUsed: r.equipment_used,
    totalTimeMinutes: r.total_time_minutes,
    calories: r.calories,
    proteinG: r.protein_g,
    carbsG: r.carbs_g,
    fatG: r.fat_g,
  };
}
