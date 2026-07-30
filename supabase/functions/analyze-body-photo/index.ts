// analyze-body-photo
//
// AI vision comparison of a user's already-stored goal/current body
// photos, run silently after both exist. Its ONLY output is a set of
// existing GoalTag values (a secondary, lower-confidence signal alongside
// the user's own stated goals) -- never a numeric or clinical-sounding
// score, and never shown to the user directly (see Config.swift's
// enableBodyPhotoVisionAnalysis doc comment for the full rationale).
// Body: { } (no payload needed -- reads the paths already on the user's row)
// Response: { ok: true } | { skipped: true, reason: string }
//
// Deliberately its OWN function, not folded into analyze-gym-photo: body
// photos are a different, more sensitive, already-DURABLY-STORED data
// category (gym photos are transient and never persisted).
//
// NEW vendor integration on already-stored, more sensitive photos -- same
// "verify against current OpenAI docs at deploy time" caveat as
// analyze-gym-photo.

import { handleOptions, jsonResponse } from "../_shared/cors.ts";
import { requireUser, serviceRoleClient } from "../_shared/clients.ts";
import { extractOutputText } from "../_shared/openai.ts";
import { GOAL_TAG_VOCABULARY, normalizeGoalTags } from "../_shared/goalTags.ts";

const OPENAI_URL = "https://api.openai.com/v1/responses";
const MODEL_PRIMARY = "gpt-5.6-luna";
const MODEL_RETRY = "gpt-5.6-terra";
const LOW_CONFIDENCE_THRESHOLD = 0.6;
const BUCKET = "body-photos";

// Closed enum, no numeric/clinical field of any kind -- there is nothing
// clinical-sounding to leak even if the model tried.
const EMPHASIS_SCHEMA = {
  type: "object",
  properties: {
    emphasis_tags: {
      type: "array",
      items: { type: "string", enum: [...GOAL_TAG_VOCABULARY] },
    },
    confidence: { type: "number" },
  },
  required: ["emphasis_tags", "confidence"],
  additionalProperties: false,
};

const PROMPT =
  `You are comparing two photos: the FIRST is the user's CURRENT body, the SECOND is their GOAL body (what they're aiming for). Based only on the visual gap between them, return which of these training-emphasis categories would help close that gap, choosing only values from this list: ${
    GOAL_TAG_VOCABULARY.join(", ")
  }. Return an empty list if you cannot confidently identify a gap. Do NOT describe body composition, weight, health, or give any clinical, numeric, or diagnostic assessment in any field -- only the category selection and a confidence score from 0 to 1.`;

interface EmphasisResult {
  emphasis_tags: string[];
  confidence: number;
}

Deno.serve(async (req: Request) => {
  const preflight = handleOptions(req);
  if (preflight) return preflight;

  try {
    const userId = await requireUser(req);

    // Server-side flag enforcement -- never trust the client-side
    // Config.enableBodyPhotoVisionAnalysis check alone for a feature this
    // sensitive.
    if (Deno.env.get("ENABLE_BODY_PHOTO_VISION_ANALYSIS") !== "true") {
      return jsonResponse({ skipped: true, reason: "disabled" });
    }

    const supabase = serviceRoleClient();

    const { data: userRow, error: readError } = await supabase
      .from("users")
      .select(
        "goal_body_photo_path, current_body_photo_path, body_photo_emphasis_source_goal_path, body_photo_emphasis_source_current_path, body_photo_emphasis_tags",
      )
      .eq("id", userId)
      .maybeSingle();
    if (readError) throw new Error(`could not read users: ${readError.message}`);

    const goalPath = userRow?.goal_body_photo_path as string | null;
    const currentPath = userRow?.current_body_photo_path as string | null;
    if (!goalPath || !currentPath) {
      return jsonResponse({ skipped: true, reason: "missing_photo" });
    }

    // Idempotent: skip the OpenAI call entirely if both photos are
    // unchanged since the last analysis.
    if (
      userRow?.body_photo_emphasis_source_goal_path === goalPath &&
      userRow?.body_photo_emphasis_source_current_path === currentPath &&
      userRow?.body_photo_emphasis_tags !== null
    ) {
      return jsonResponse({ ok: true, cached: true });
    }

    const [goalBase64, currentBase64] = await Promise.all([
      downloadAsBase64(supabase, goalPath),
      downloadAsBase64(supabase, currentPath),
    ]);

    let result = await callOpenAIVision(MODEL_PRIMARY, currentBase64, goalBase64);
    if (result.confidence < LOW_CONFIDENCE_THRESHOLD) {
      result = await callOpenAIVision(MODEL_RETRY, currentBase64, goalBase64);
    }
    const lowConfidence = result.confidence < LOW_CONFIDENCE_THRESHOLD;
    const tags = lowConfidence ? [] : normalizeGoalTags(result.emphasis_tags ?? []);

    const { error: updateError } = await supabase
      .from("users")
      .update({
        body_photo_emphasis_tags: tags,
        body_photo_emphasis_source_goal_path: goalPath,
        body_photo_emphasis_source_current_path: currentPath,
        body_photo_emphasis_updated_at: new Date().toISOString(),
      })
      .eq("id", userId);
    if (updateError) throw new Error(`could not write body_photo_emphasis_tags: ${updateError.message}`);

    // Deliberately not returning tags/confidence -- see this function's own
    // header comment. If debug visibility is ever needed, add it
    // explicitly then, not by default now.
    return jsonResponse({ ok: true });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    const status = msg === "unauthorized" ? 401 : 500;
    return jsonResponse({ error: msg }, status);
  }
});

// deno-lint-ignore no-explicit-any
async function downloadAsBase64(supabase: any, path: string): Promise<string> {
  const { data, error } = await supabase.storage.from(BUCKET).download(path);
  if (error) throw new Error(`could not download ${path} from ${BUCKET}: ${error.message}`);
  const buffer = await data.arrayBuffer();
  return encodeBase64(new Uint8Array(buffer));
}

function encodeBase64(bytes: Uint8Array): string {
  let binary = "";
  const chunkSize = 0x8000;
  for (let i = 0; i < bytes.length; i += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunkSize));
  }
  return btoa(binary);
}

async function callOpenAIVision(model: string, currentBase64: string, goalBase64: string): Promise<EmphasisResult> {
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
            { type: "input_image", image_url: `data:image/jpeg;base64,${currentBase64}` },
            { type: "input_image", image_url: `data:image/jpeg;base64,${goalBase64}` },
          ],
        },
      ],
      text: { format: { type: "json_schema", name: "body_photo_emphasis", schema: EMPHASIS_SCHEMA, strict: true } },
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
