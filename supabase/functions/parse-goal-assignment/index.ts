// parse-goal-assignment
//
// Reads a coach's workout assignment out of either free text or a photo of
// text, for the custom-goal ("coach's task") creation form. Body: exactly
// one of { text: string } or { imageBase64: string }. Response:
// { parsed: {...} | null, confidence, lowConfidence }.
//
// This is an ESTIMATE, never auto-saved server-side -- the client pre-fills
// the same editable CustomGoalFormView fields used for manual entry, so the
// user reviews before create-goal is ever called. parsed is null whenever
// lowConfidence is true; the client must not touch any field in that case.

import { handleOptions, jsonResponse } from "../_shared/cors.ts";
import { requireUser, serviceRoleClient } from "../_shared/clients.ts";
import { checkFlatDailyLimit, logGeneration } from "../_shared/generationLimits.ts";
import { extractOutputText } from "../_shared/openai.ts";
import { normalizeAssignment, SCHEDULE_RULES, type RawAssignmentResult } from "./assignmentParsing.ts";

// Used once per goal creation, not a repeatable daily action like meal
// logging -- a lower flat ceiling than parse-meal-text's 40.
const FLAT_DAILY_LIMIT = 10;

const ANTHROPIC_API_URL = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_VERSION = "2023-06-01";
const ANTHROPIC_MODEL = "claude-haiku-4-5";

const OPENAI_URL = "https://api.openai.com/v1/responses";
const OPENAI_MODEL_PRIMARY = "gpt-5.6-luna";
const OPENAI_MODEL_RETRY = "gpt-5.6-terra";
const LOW_CONFIDENCE_THRESHOLD = 0.6;

// Anthropic's json_schema output doesn't support nullable fields (same
// constraint estimateBounds.ts documents), so "unknown" is a sentinel per
// type -- normalizeAssignment converts these to real nulls.
const RAW_SCHEMA = {
  type: "object",
  properties: {
    isAssignment: { type: "boolean" },
    confidence: { type: "number" },
    givenText: { type: "string" },
    workoutText: { type: "string" },
    coachName: { type: "string" },
    durationWeeks: { type: "integer" },
    frequencyPerWeek: { type: "integer" },
    scheduleRule: { type: "string", enum: [...SCHEDULE_RULES, "none"] },
    scheduleDays: { type: "array", items: { type: "integer" } },
    courtDays: { type: "array", items: { type: "integer" } },
  },
  required: [
    "isAssignment",
    "confidence",
    "givenText",
    "workoutText",
    "coachName",
    "durationWeeks",
    "frequencyPerWeek",
    "scheduleRule",
    "scheduleDays",
    "courtDays",
  ],
  additionalProperties: false,
};

const INSTRUCTIONS =
  `This is a fitness app. The input below should be a coach's workout assignment for their athlete. Extract:
- isAssignment: true only if this genuinely reads like a coach/trainer assignment (a workout, drills, sets/reps, a training plan). false for anything else (random text, an unrelated photo, a menu, a receipt, small talk) -- do not guess or invent a workout when it isn't one.
- confidence: 0 to 1, how sure you are of the whole extraction.
- givenText: the stated goal/purpose, if any, else "".
- workoutText: the actual workout/drills in the coach's own words, preserved close to verbatim -- never invented or embellished. "" if none found.
- coachName: the coach's name if mentioned, else "".
- durationWeeks: how many weeks this assignment runs, if stated, else 0.
- frequencyPerWeek: sessions per week, if stated, else 0.
- scheduleRule: one of "weekdays" (specific weekdays named), "every_other_day", "before_court_days" (scheduled before court/game days), "readiness" (whenever the app decides), or "none" if not stated.
- scheduleDays: 0=Sunday..6=Saturday ints, only if scheduleRule is "weekdays", else [].
- courtDays: same 0-6 ints, only if scheduleRule is "before_court_days", else [].

If isAssignment is false, still return valid JSON with every other field at its empty/zero/"none" default -- never fabricate content for something that isn't an assignment.`;

Deno.serve(async (req: Request) => {
  const preflight = handleOptions(req);
  if (preflight) return preflight;

  try {
    const userId = await requireUser(req);
    const body = await req.json().catch(() => ({}));
    const text: string | undefined = body.text;
    const imageBase64: string | undefined = body.imageBase64;
    // Client's local UTC offset in minutes (e.g. -480 for UTC-8, +780 for
    // UTC+13) -- optional so a client that doesn't send it still works, but
    // without it the daily quota below resets on the server's UTC day
    // rather than the user's actual local midnight.
    const timezoneOffsetMinutes: number | undefined =
      typeof body.timezoneOffsetMinutes === "number" ? body.timezoneOffsetMinutes : undefined;

    if ((!text && !imageBase64) || (text && imageBase64)) {
      return jsonResponse({ error: "send exactly one of 'text' or 'imageBase64'" }, 400);
    }

    const supabase = serviceRoleClient();
    const localNow = timezoneOffsetMinutes !== undefined
      ? new Date(Date.now() + timezoneOffsetMinutes * 60_000)
      : new Date();
    const date = localNow.toISOString().slice(0, 10);
    const allowed = await checkFlatDailyLimit(supabase, userId, date, "goal_assignment_parse", FLAT_DAILY_LIMIT);
    if (!allowed) {
      return jsonResponse(
        { error: "You've used today's AI assignment reads. Fill in the fields yourself, or try again tomorrow." },
        429,
      );
    }

    const raw = text ? await callClaude(text.trim()) : await callOpenAIVisionWithRetry(imageBase64!);
    await logGeneration(supabase, userId, date, "goal_assignment_parse");
    return jsonResponse(normalizeAssignment(raw));
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    const status = msg === "unauthorized" ? 401 : 500;
    return jsonResponse({ error: msg }, status);
  }
});

async function callClaude(text: string): Promise<RawAssignmentResult> {
  const apiKey = Deno.env.get("ANTHROPIC_API_KEY")!;
  const prompt = `${INSTRUCTIONS}\n\nInput:\n"""\n${text}\n"""`;

  const res = await fetch(ANTHROPIC_API_URL, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": ANTHROPIC_VERSION,
    },
    body: JSON.stringify({
      model: ANTHROPIC_MODEL,
      max_tokens: 768,
      output_config: { format: { type: "json_schema", schema: RAW_SCHEMA } },
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
  return JSON.parse(textBlock.text) as RawAssignmentResult;
}

async function callOpenAIVisionWithRetry(imageBase64: string): Promise<RawAssignmentResult> {
  let result = await callOpenAIVision(OPENAI_MODEL_PRIMARY, imageBase64);
  if (result.confidence < LOW_CONFIDENCE_THRESHOLD) {
    result = await callOpenAIVision(OPENAI_MODEL_RETRY, imageBase64);
  }
  return result;
}

async function callOpenAIVision(model: string, imageBase64: string): Promise<RawAssignmentResult> {
  const apiKey = Deno.env.get("OPENAI_API_KEY");
  if (!apiKey) {
    throw new Error("OPENAI_API_KEY is not set as a Supabase secret -- run `supabase secrets set OPENAI_API_KEY=...`");
  }

  const res = await fetch(OPENAI_URL, {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${apiKey}` },
    body: JSON.stringify({
      model,
      input: [
        {
          role: "user",
          content: [
            { type: "input_text", text: INSTRUCTIONS },
            { type: "input_image", image_url: `data:image/jpeg;base64,${imageBase64}` },
          ],
        },
      ],
      text: { format: { type: "json_schema", name: "goal_assignment_extraction", schema: RAW_SCHEMA, strict: true } },
    }),
  });
  if (!res.ok) {
    const errBody = await res.text();
    throw new Error(`OpenAI API error ${res.status}: ${errBody}`);
  }
  const json = await res.json();
  const outputText = extractOutputText(json);
  if (!outputText) throw new Error("No text content in OpenAI response");
  return JSON.parse(outputText) as RawAssignmentResult;
}
