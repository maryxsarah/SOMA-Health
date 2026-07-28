// generate-gym-workout
//
// Steps 3+4 of the gym-photo-workout flow, combined into one endpoint
// since they're really one user action ("confirm equipment -> get my
// workout"). Body: { date: "YYYY-MM-DD", confirmedEquipment: string[] }
//
// Step 3 (deterministic, NOT LLM): reads today's already-computed
// daily_recommendation.category (server is the single source of truth
// for that decision, not re-derived here) plus the safety guardrail, and
// picks a fixed, versioned-in-code template (templates.ts) filtered by
// confirmedEquipment.
// Step 4 (Luna, text-only): fills in ONLY the friendly per-exercise
// instructions/tone -- never chooses exercises/sets/reps, those are fixed
// by the template selected in step 3.
//
// The guardrail check in _shared/safetyFlags.ts runs FIRST and gates
// everything below it -- on any trigger, no template is selected and no
// LLM is called at all.

import { handleOptions, jsonResponse } from "../_shared/cors.ts";
import { requireUser, serviceRoleClient } from "../_shared/clients.ts";
import { checkSafetyFlags } from "../_shared/safetyFlags.ts";
import { extractOutputText } from "../_shared/openai.ts";
import { GymWorkoutTemplate, selectTemplate } from "./templates.ts";
import { normalizeEquipment } from "../_shared/equipment.ts";

const OPENAI_URL = "https://api.openai.com/v1/responses";
const MODEL = "gpt-5.6-luna";

const WORDED_EXERCISE_SCHEMA = {
  type: "object",
  properties: { name: { type: "string" }, instructions: { type: "string" } },
  required: ["name", "instructions"],
  additionalProperties: false,
};
const WORDING_SCHEMA = {
  type: "object",
  properties: {
    focus: { type: "string" },
    exercises: { type: "array", items: WORDED_EXERCISE_SCHEMA },
  },
  required: ["focus", "exercises"],
  additionalProperties: false,
};

interface SnapshotRow {
  source: string;
  recovery_score: number | null;
  readiness_score: number | null;
  hrv_ms: number | null;
  sleep_hours: number | null;
  resting_hr: number | null;
  strain_score: number | null;
  stress_score: number | null;
}

Deno.serve(async (req: Request) => {
  const preflight = handleOptions(req);
  if (preflight) return preflight;

  try {
    const userId = await requireUser(req);
    const body = await req.json().catch(() => ({}));
    const date: string | undefined = body.date;
    const confirmedEquipment: string[] | undefined = body.confirmedEquipment;
    if (!date) return jsonResponse({ error: "missing 'date' (YYYY-MM-DD)" }, 400);
    if (!Array.isArray(confirmedEquipment)) {
      return jsonResponse({ error: "missing 'confirmedEquipment' (string array)" }, 400);
    }

    const supabase = serviceRoleClient();

    // Guardrail gate FIRST -- deterministic, before any template pick or
    // LLM call. Never let the model diagnose/treat/infer a condition; on
    // any trigger this is the only thing the caller ever sees.
    const safety = await checkSafetyFlags(supabase, userId, date);
    if (safety.flagged) {
      return jsonResponse({ date, safety_flag: true, message: safety.message });
    }

    const { data: recommendation } = await supabase
      .from("daily_recommendation")
      .select("category")
      .eq("user_id", userId)
      .eq("date", date)
      .maybeSingle();
    if (!recommendation) {
      return jsonResponse({ error: "no recommendation for this date yet" }, 422);
    }
    const category = recommendation.category as string;

    const { data: userRow } = await supabase
      .from("users")
      .select("goals")
      .eq("id", userId)
      .maybeSingle();
    const goals = (userRow?.goals as string[] | null) ?? [];

    const { data: snapshots } = await supabase
      .from("daily_snapshot")
      .select("source, recovery_score, readiness_score, hrv_ms, sleep_hours, resting_hr, strain_score, stress_score")
      .eq("user_id", userId)
      .eq("date", date);

    // Sorted + joined server-side so the client cannot influence cache
    // identity by reordering the list it sends.
    const equipmentSet = normalizeEquipment(confirmedEquipment);
    const equipmentSignature = Array.from(equipmentSet).sort().join("|");

    // Same setup, same day -> same answer, so serve it rather than paying
    // for the wording pass again. A different setup is a different
    // signature and regenerates, which is what "retake photo" should do.
    const { data: cached } = await supabase
      .from("gym_workout_plan")
      .select("category, plan")
      .eq("user_id", userId)
      .eq("date", date)
      .eq("equipment_signature", equipmentSignature)
      .maybeSingle();
    if (cached) {
      return jsonResponse({ date, category: cached.category, safety_flag: false, ...cached.plan });
    }

    const template = selectTemplate(category, equipmentSet, goals, safety.excludeHighImpact);

    const wording = await callLunaForWording(
      template,
      goals,
      (snapshots ?? []) as SnapshotRow[],
      equipmentSet,
    );
    const plan = mergeWording(template, wording);

    await supabase
      .from("gym_workout_plan")
      .upsert(
        { user_id: userId, date, equipment_signature: equipmentSignature, category, plan },
        { onConflict: "user_id,date,equipment_signature" },
      );

    return jsonResponse({ date, category, safety_flag: false, ...plan });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    const status = msg === "unauthorized" ? 401 : 500;
    return jsonResponse({ error: msg }, status);
  }
});

async function callLunaForWording(
  template: GymWorkoutTemplate,
  goals: string[],
  snapshots: SnapshotRow[],
  equipment: Set<string>,
): Promise<{ focus: string; exercises: { name: string; instructions: string }[] }> {
  const apiKey = Deno.env.get("OPENAI_API_KEY");
  if (!apiKey) {
    throw new Error("OPENAI_API_KEY is not set as a Supabase secret -- run `supabase secrets set OPENAI_API_KEY=...`");
  }

  const allExerciseNames = [
    ...template.warm_up.map((e) => e.name),
    ...template.blocks.flatMap((b) => b.exercises.map((e) => e.name)),
    ...template.cool_down.map((e) => e.name),
  ];
  const readinessSummary = describeSnapshots(snapshots);
  // The equipment list is the whole point of having taken a photo, and it
  // previously never reached the model -- it was reduced to keywords for
  // template matching and then dropped, so the instructions read like a
  // generic plan. Passing it lets cues reference what the user is actually
  // standing in front of, without licence to change the prescription.
  const equipmentSummary = equipment.size > 0
    ? Array.from(equipment).sort().join(", ")
    : "no equipment -- bodyweight only";
  const prompt =
    `You are writing friendly, encouraging per-exercise instructions for a gym workout. The exercises, sets, reps, and structure are ALREADY DECIDED -- do not rename, add, remove, or reorder any exercise. Only write clear, encouraging "instructions" text (2-3 sentences, plain language, real form cues) for each of these exercises, in this exact order: ${
      allExerciseNames.join(", ")
    }. The user confirmed they have this equipment available right now: ${equipmentSummary}. Where it helps, make the cues concrete about that setup (e.g. which implement to pick up, how to set it up) -- but never substitute a different exercise or suggest equipment not in that list. User's goals: ${
      goals.length ? goals.join(", ") : "general fitness"
    }. Today's readiness: ${readinessSummary}. Also give a one-line "focus" summarizing this session.`;

  const res = await fetch(OPENAI_URL, {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${apiKey}` },
    body: JSON.stringify({
      model: MODEL,
      input: [{ role: "user", content: [{ type: "input_text", text: prompt }] }],
      text: { format: { type: "json_schema", name: "exercise_wording", schema: WORDING_SCHEMA, strict: true } },
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

/// Same terse style as generate-workout-plan's describeHealthData() --
/// this only feeds tone/wording here, not any decision, so it stays brief.
function describeSnapshots(snapshots: SnapshotRow[]): string {
  if (snapshots.length === 0) return "no wearable data reported today";
  const parts: string[] = [];
  for (const s of snapshots) {
    const bits: string[] = [];
    if (s.recovery_score !== null) bits.push(`Whoop recovery ${s.recovery_score}%`);
    if (s.readiness_score !== null) bits.push(`Oura readiness ${s.readiness_score}`);
    if (s.sleep_hours !== null) bits.push(`slept ${s.sleep_hours}h`);
    if (s.stress_score !== null) bits.push(`${s.stress_score}min in high stress today`);
    if (bits.length > 0) parts.push(`${s.source}: ${bits.join(", ")}`);
  }
  return parts.length > 0 ? parts.join("; ") : "wearable connected but no metrics reported today";
}

function mergeWording(
  template: GymWorkoutTemplate,
  wording: { focus: string; exercises: { name: string; instructions: string }[] },
) {
  const instructionsByName = new Map(wording.exercises.map((e) => [e.name, e.instructions]));
  const withWording = (name: string, fallback: string) => instructionsByName.get(name) ?? fallback;

  return {
    focus: wording.focus || template.focus,
    warm_up: template.warm_up.map((e) => ({ ...e, instructions: withWording(e.name, "") })),
    blocks: template.blocks.map((b) => ({
      ...b,
      exercises: b.exercises.map((e) => ({ ...e, instructions: withWording(e.name, "") })),
    })),
    cool_down: template.cool_down.map((e) => ({ ...e, instructions: withWording(e.name, "") })),
  };
}
