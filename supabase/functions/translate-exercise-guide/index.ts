// translate-exercise-guide
//
// Returns an exercise_library row's name + how-to instructions in the
// caller's UI language. Body: { exerciseId: string, language: string }.
// Response: { name: string, instructions: string[] }.
//
// English (or an unrecognized code) short-circuits to the original row.
// Every other language is served from the exercise_library_i18n cache
// when present, else translated once with Claude Haiku, cached, and
// returned -- one model call per (exercise, language) EVER, shared by all
// users, so no per-user generation limit is needed beyond a flat guard.

import { handleOptions, jsonResponse } from "../_shared/cors.ts";
import { requireUser, serviceRoleClient } from "../_shared/clients.ts";
import { checkFlatDailyLimit, logGeneration } from "../_shared/generationLimits.ts";
import { languageName, normalizeLanguageCode } from "../_shared/language.ts";

const ANTHROPIC_API_URL = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_VERSION = "2023-06-01";
const MODEL = "claude-haiku-4-5";

// Generous ceiling: only ever reached by an account scripting cache-miss
// requests across many exercises×languages in one day.
const FLAT_DAILY_LIMIT = 60;

const TRANSLATION_SCHEMA = {
  type: "object",
  properties: {
    name: { type: "string" },
    instructions: { type: "array", items: { type: "string" } },
  },
  required: ["name", "instructions"],
  additionalProperties: false,
};

Deno.serve(async (req: Request) => {
  const preflight = handleOptions(req);
  if (preflight) return preflight;

  try {
    const userId = await requireUser(req);
    const body = await req.json().catch(() => ({}));
    const exerciseId: string | undefined = body.exerciseId;
    const language = normalizeLanguageCode(body.language);
    if (!exerciseId) {
      return jsonResponse({ error: "missing 'exerciseId'" }, 400);
    }

    const supabase = serviceRoleClient();
    const { data: exercise, error: exerciseError } = await supabase
      .from("exercise_library")
      .select("id,name,instructions")
      .eq("id", exerciseId)
      .maybeSingle();
    if (exerciseError) throw exerciseError;
    if (!exercise) return jsonResponse({ error: "unknown exercise" }, 404);

    if (language === "en") {
      return jsonResponse({ name: exercise.name, instructions: exercise.instructions ?? [] });
    }

    const { data: cached } = await supabase
      .from("exercise_library_i18n")
      .select("name,instructions")
      .eq("exercise_id", exerciseId)
      .eq("language", language)
      .maybeSingle();
    if (cached) {
      return jsonResponse({ name: cached.name, instructions: cached.instructions ?? [] });
    }

    const date = new Date().toISOString().slice(0, 10);
    const allowed = await checkFlatDailyLimit(supabase, userId, date, "exercise_translation", FLAT_DAILY_LIMIT);
    if (!allowed) {
      // Cache miss + over the guard: English is still a correct answer.
      return jsonResponse({ name: exercise.name, instructions: exercise.instructions ?? [] });
    }

    const translated = await callClaude(exercise.name, exercise.instructions ?? [], languageName(language));
    await logGeneration(supabase, userId, date, "exercise_translation");
    // Best-effort cache write; a race with another first-requester just
    // means one redundant translation, the upsert keeps a single row.
    await supabase.from("exercise_library_i18n").upsert({
      exercise_id: exerciseId,
      language,
      name: translated.name,
      instructions: translated.instructions,
    });
    return jsonResponse(translated);
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    const status = msg === "unauthorized" ? 401 : 500;
    return jsonResponse({ error: msg }, status);
  }
});

interface Translation {
  name: string;
  instructions: string[];
}

async function callClaude(name: string, instructions: string[], language: string): Promise<Translation> {
  const apiKey = Deno.env.get("ANTHROPIC_API_KEY")!;
  const prompt = `Translate this gym exercise's name and step-by-step instructions into ${language} for a fitness app.

Name: ${name}
Steps:
${instructions.map((step, i) => `${i + 1}. ${step}`).join("\n")}

Rules:
- Natural, concise coaching language a native-speaking trainer would use -- not word-for-word literal.
- Keep the SAME number of steps, same order, one translated string per step.
- Keep established equipment/exercise loanwords the way local gym-goers actually say them.
- name: the translated exercise name only, no extra commentary.`;

  const res = await fetch(ANTHROPIC_API_URL, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": ANTHROPIC_VERSION,
    },
    body: JSON.stringify({
      model: MODEL,
      max_tokens: 1024,
      output_config: { format: { type: "json_schema", schema: TRANSLATION_SCHEMA } },
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
  return JSON.parse(textBlock.text) as Translation;
}
