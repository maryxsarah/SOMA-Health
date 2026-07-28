// analyze-gym-photo
//
// Step 1 of the gym-photo-workout flow: vision recognition of equipment
// visible in a user-supplied gym photo. Body: { imageBase64: string }
// (client-compressed JPEG, base64-encoded, no data: prefix).
// Response: { equipment: string[], confidence: number, lowConfidence: bool }
//
// NEW vendor integration -- OpenAI, not Anthropic. Requires an
// OPENAI_API_KEY Supabase secret (`supabase secrets set OPENAI_API_KEY=...`).
//
// NOTE: verify the exact Responses API field names (`input`, `text.format`,
// `output_text`) against OpenAI's current docs at implementation/deploy
// time -- same "verify against current docs" caveat this codebase already
// applies to the Whoop API URLs (see generate-recommendation/index.ts).

import { handleOptions, jsonResponse } from "../_shared/cors.ts";
import { requireUser } from "../_shared/clients.ts";
import { extractOutputText } from "../_shared/openai.ts";

const OPENAI_URL = "https://api.openai.com/v1/responses";
// Cheapest, high-volume vision tier -- fits this bounded classification
// task. Terra is the stronger, still cost-reasonable retry tier for a
// low-confidence first pass.
const MODEL_PRIMARY = "gpt-5.6-luna";
const MODEL_RETRY = "gpt-5.6-terra";
const LOW_CONFIDENCE_THRESHOLD = 0.6;

const EQUIPMENT_SCHEMA = {
  type: "object",
  properties: {
    equipment: { type: "array", items: { type: "string" } },
    confidence: { type: "number" },
  },
  required: ["equipment", "confidence"],
  additionalProperties: false,
};

const PROMPT =
  "Identify every distinct piece of gym equipment visible in this photo. Return a concise list of equipment names (e.g. \"barbell\", \"squat rack\", \"dumbbells\", \"treadmill\", \"resistance bands\") and a confidence score from 0 to 1 reflecting how certain you are about the full list. Do not describe people, injuries, or anything unrelated to equipment.";

interface EquipmentResult {
  equipment: string[];
  confidence: number;
}

Deno.serve(async (req: Request) => {
  const preflight = handleOptions(req);
  if (preflight) return preflight;

  try {
    await requireUser(req);
    const body = await req.json().catch(() => ({}));
    const imageBase64: string | undefined = body.imageBase64;
    if (!imageBase64) {
      return jsonResponse({ error: "missing 'imageBase64'" }, 400);
    }

    // If the first (cheap) pass comes back low-confidence, retry once with
    // the stronger tier before falling back to an empty list -- the client
    // then asks the user to enter equipment manually rather than guessing.
    let result = await callOpenAIVision(MODEL_PRIMARY, imageBase64);
    if (result.confidence < LOW_CONFIDENCE_THRESHOLD) {
      result = await callOpenAIVision(MODEL_RETRY, imageBase64);
    }

    const lowConfidence = result.confidence < LOW_CONFIDENCE_THRESHOLD;
    return jsonResponse({
      equipment: lowConfidence ? [] : result.equipment,
      confidence: result.confidence,
      lowConfidence,
    });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    const status = msg === "unauthorized" ? 401 : 500;
    return jsonResponse({ error: msg }, status);
  }
});

async function callOpenAIVision(model: string, imageBase64: string): Promise<EquipmentResult> {
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
            { type: "input_text", text: PROMPT },
            { type: "input_image", image_url: `data:image/jpeg;base64,${imageBase64}` },
          ],
        },
      ],
      text: { format: { type: "json_schema", name: "equipment_detection", schema: EQUIPMENT_SCHEMA, strict: true } },
    }),
  });
  if (!res.ok) {
    const errBody = await res.text();
    throw new Error(`OpenAI API error ${res.status}: ${errBody}`);
  }
  const json = await res.json();
  const outputText = extractOutputText(json);
  if (!outputText) throw new Error("No text content in OpenAI response");
  return JSON.parse(outputText);
}
