// analyze-body-photo
//
// AI vision comparison of a user's already-stored goal/current body
// photos, run silently after both exist. Two outputs, both restricted to
// closed, qualitative vocabularies -- never a numeric or clinical-sounding
// score, and neither shown to the user directly (see Config.swift's
// enableBodyPhotoVisionAnalysis doc comment for the full rationale):
//   1. emphasis_tags -- existing GoalTag values, a secondary signal folded
//      into generate-workout-plan's prompt (unchanged from before).
//   2. training_emphasis -- cut/recomp/bulk/maintain, a coarser directional
//      read used ONLY to drive the deterministic nutrition-target
//      calculation below. Kept its own column, deliberately NOT merged
//      into users.goals -- same reasoning as emphasis_tags: "the user said
//      X" must never become indistinguishable from "the model guessed X".
// Body: { } (no payload needed -- reads the paths already on the user's row)
// Response: { ok: true } | { skipped: true, reason: string }
//
// Deliberately its OWN function, not folded into analyze-gym-photo: body
// photos are a different, more sensitive, already-DURABLY-STORED data
// category (gym photos are transient and never persisted).
//
// Vendor: intentionally still OpenAI, not Claude. The rest of this app's AI
// generation (generate-workout-plan, generate-recommendation) uses Claude,
// but this specific vision call predates that convention, is already
// legally reviewed, and the Privacy Policy names OpenAI specifically for
// this comparison (see Config.swift) -- switching vendors here would
// invalidate that disclosure and needs a deliberate legal re-review, not a
// silent swap made in passing while adding training_emphasis.
//
// Adult-only gate (App Store 4+ rating, no minors handling existed before
// this): server-side re-check on date_of_birth, same "never trust the
// client-side flag alone" posture as ENABLE_BODY_PHOTO_VISION_ANALYSIS
// below. Fails closed -- an unknown/missing date_of_birth is treated as
// NOT confirmed-adult, same as a confirmed minor, rather than assumed safe.

import { handleOptions, jsonResponse } from "../_shared/cors.ts";
import { requireUser, serviceRoleClient } from "../_shared/clients.ts";
import { extractOutputText } from "../_shared/openai.ts";
import { GOAL_TAG_VOCABULARY, normalizeGoalTags } from "../_shared/goalTags.ts";
import { checkSafetyFlags } from "../_shared/safetyFlags.ts";
import { ADULT_AGE, ageFromDOB } from "../_shared/age.ts";
import { activityLevelFromWorkoutsPerWeek, computeNutritionTargets, type TrainingEmphasis } from "../_shared/nutritionTargets.ts";

const OPENAI_URL = "https://api.openai.com/v1/responses";
const MODEL_PRIMARY = "gpt-5.6-luna";
const MODEL_RETRY = "gpt-5.6-terra";
const LOW_CONFIDENCE_THRESHOLD = 0.6;
const BUCKET = "body-photos";

const TRAINING_EMPHASIS_VOCABULARY = ["cut", "recomp", "bulk", "maintain"] as const;

// Closed enums, no numeric/clinical field of any kind -- there is nothing
// clinical-sounding to leak even if the model tried.
const EMPHASIS_SCHEMA = {
  type: "object",
  properties: {
    emphasis_tags: {
      type: "array",
      items: { type: "string", enum: [...GOAL_TAG_VOCABULARY] },
    },
    // Coarser than emphasis_tags -- a single directional read used only to
    // pick which TDEE adjustment applies, never surfaced as a "you should
    // cut" style statement to the user.
    training_emphasis: { type: "string", enum: [...TRAINING_EMPHASIS_VOCABULARY] },
    confidence: { type: "number" },
  },
  required: ["emphasis_tags", "training_emphasis", "confidence"],
  additionalProperties: false,
};

const PROMPT =
  `You are comparing two photos: the FIRST is the user's CURRENT body, the SECOND is their GOAL body (what they're aiming for). Based only on the visual gap between them, return: (1) which of these training-emphasis categories would help close that gap, choosing only values from this list: ${
    GOAL_TAG_VOCABULARY.join(", ")
  } -- return an empty list if you cannot confidently identify a gap; (2) a single overall training_emphasis direction -- exactly one of "cut" (the gap is mainly about reducing body fat), "bulk" (the gap is mainly about adding size/mass), "recomp" (the gap is about both, or about changing composition at a similar overall size), or "maintain" (little to no visible gap). Do NOT describe body composition, weight, health, or give any clinical, numeric, or diagnostic assessment in any field -- only the category selections and a confidence score from 0 to 1.`;

interface EmphasisResult {
  emphasis_tags: string[];
  training_emphasis: string;
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
        "goal_body_photo_path, current_body_photo_path, body_photo_emphasis_source_goal_path, body_photo_emphasis_source_current_path, body_photo_emphasis_tags, training_emphasis, body_photo_emphasis_low_confidence, date_of_birth, weight_kg, height_cm, sex, workouts_per_week",
      )
      .eq("id", userId)
      .maybeSingle();
    if (readError) throw new Error(`could not read users: ${readError.message}`);

    // Adult-only gate. A missing date_of_birth is NOT treated as adult --
    // fails closed, same posture as every other safety gate in this
    // codebase (see safetyFlags.ts's own comment on this).
    const dob = userRow?.date_of_birth as string | null;
    if (!dob || ageFromDOB(dob) < ADULT_AGE) {
      return jsonResponse({ skipped: true, reason: "not_confirmed_adult" });
    }

    const goalPath = userRow?.goal_body_photo_path as string | null;
    const currentPath = userRow?.current_body_photo_path as string | null;
    if (!goalPath || !currentPath) {
      return jsonResponse({ skipped: true, reason: "missing_photo" });
    }

    // Idempotent: skip the OpenAI call if both photos are unchanged since
    // the last analysis and it already reached a verdict (real or low-confidence).
    if (
      userRow?.body_photo_emphasis_source_goal_path === goalPath &&
      userRow?.body_photo_emphasis_source_current_path === currentPath &&
      userRow?.body_photo_emphasis_tags !== null &&
      (userRow?.training_emphasis !== null || userRow?.body_photo_emphasis_low_confidence === true)
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
    const trainingEmphasis: TrainingEmphasis | null =
      !lowConfidence && isTrainingEmphasis(result.training_emphasis) ? result.training_emphasis : null;

    const { error: updateError } = await supabase
      .from("users")
      .update({
        body_photo_emphasis_tags: tags,
        training_emphasis: trainingEmphasis,
        body_photo_emphasis_low_confidence: lowConfidence,
        body_photo_emphasis_source_goal_path: goalPath,
        body_photo_emphasis_source_current_path: currentPath,
        body_photo_emphasis_updated_at: new Date().toISOString(),
      })
      .eq("id", userId);
    if (updateError) throw new Error(`could not write body_photo_emphasis_tags: ${updateError.message}`);

    // Nutrition targets are prescriptive output (constraint: formula-based,
    // never AI-guessed, but still real dietary guidance) -- gated on the
    // same safety-flags check every other prescriptive Edge Function runs
    // before generating anything. Non-fatal: a flag, or missing profile
    // data the formula needs, just leaves nutrition_targets unwritten this
    // cycle rather than failing the whole request (the emphasis-tag write
    // above already succeeded and should not be rolled back for this).
    if (trainingEmphasis !== null) {
      await maybeUpdateNutritionTargets(supabase, userId, trainingEmphasis, {
        dob,
        weightKg: userRow?.weight_kg as number | null,
        heightCm: userRow?.height_cm as number | null,
        sex: userRow?.sex as string | null,
        workoutsPerWeek: userRow?.workouts_per_week as string | null,
      });
    }

    // Deliberately not returning tags/training_emphasis/confidence -- see
    // this function's own header comment. If debug visibility is ever
    // needed, add it explicitly then, not by default now.
    return jsonResponse({ ok: true });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    const status = msg === "unauthorized" ? 401 : 500;
    return jsonResponse({ error: msg }, status);
  }
});

function isTrainingEmphasis(value: string): value is TrainingEmphasis {
  return (TRAINING_EMPHASIS_VOCABULARY as readonly string[]).includes(value);
}

interface NutritionInputs {
  dob: string;
  weightKg: number | null;
  heightCm: number | null;
  sex: string | null;
  workoutsPerWeek: string | null;
}

// deno-lint-ignore no-explicit-any
async function maybeUpdateNutritionTargets(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  userId: string,
  trainingEmphasis: TrainingEmphasis,
  inputs: NutritionInputs,
): Promise<void> {
  try {
    if (inputs.weightKg === null || inputs.heightCm === null) {
      // Height in particular is new (Goal Body onboarding) -- an existing
      // user who hasn't visited Profile/onboarding again since it shipped
      // simply has no nutrition targets yet, rather than a fabricated one.
      console.log(`nutrition targets skipped for ${userId}: missing weight_kg or height_cm`);
      return;
    }
    const sex = inputs.sex === "male" || inputs.sex === "female" ? inputs.sex : "other";
    const today = new Date().toISOString().slice(0, 10);
    const safety = await checkSafetyFlags(supabase, userId, today);
    if (safety.flagged) {
      console.log(`nutrition targets skipped for ${userId}: safety flag active`);
      return;
    }

    const targets = computeNutritionTargets({
      weightKg: inputs.weightKg,
      heightCm: inputs.heightCm,
      age: ageFromDOB(inputs.dob),
      sex,
      activityLevel: activityLevelFromWorkoutsPerWeek(inputs.workoutsPerWeek),
      trainingEmphasis,
    });

    const { error } = await supabase
      .from("nutrition_targets")
      .upsert(
        {
          user_id: userId,
          daily_calories: targets.dailyCalories,
          daily_protein_g: targets.dailyProteinG,
          daily_carbs_g: targets.dailyCarbsG,
          daily_fat_g: targets.dailyFatG,
          computed_at: new Date().toISOString(),
          basis: targets.basis,
        },
        { onConflict: "user_id" },
      );
    if (error) console.error(`could not write nutrition_targets for ${userId}: ${error.message}`);
  } catch (e) {
    console.error(`nutrition target computation failed for ${userId}: ${e instanceof Error ? e.message : String(e)}`);
  }
}

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
