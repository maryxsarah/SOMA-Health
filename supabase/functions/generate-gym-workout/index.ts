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
import { classifyGenerationError } from "../_shared/anthropicErrors.ts";
import { checkSafetyFlags } from "../_shared/safetyFlags.ts";
import { checkGenerationLimit, GENERATION_LIMIT_MESSAGE, logGeneration, type SubscriptionTier } from "../_shared/generationLimits.ts";
import { extractOutputText } from "../_shared/openai.ts";
import { GymWorkoutTemplate, selectTemplate } from "./templates.ts";
import { resolveTargetBodyPart } from "./targetBodyPart.ts";
import { normalizeEquipment } from "../_shared/equipment.ts";
import { computeTotalDuration } from "../_shared/duration.ts";
import { languageName, normalizeLanguageCode } from "../_shared/language.ts";
import { countRecentTrainingDaysByBodyPart } from "../_shared/trainingDayCounters.ts";

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
    const languageCode = normalizeLanguageCode(body.language);
    const language = languageName(body.language);
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

    // Four independent reads -- each depends only on userId/date, already
    // known, and none depends on another's result -- issued together
    // rather than paying four round-trip latencies in series. injury_tags/
    // injury_severity are NOT re-fetched here: checkSafetyFlags already
    // read them for this same user a moment ago (see its own
    // SafetyCheckResult.injuryTags/severityMap), so a second, separate
    // `users` query for the same columns would just be a redundant round
    // trip to the same row.
    const [
      { data: recommendation },
      { data: userRow },
      { data: snapshots },
      recentBodyPartCounts,
    ] = await Promise.all([
      supabase
        .from("daily_recommendation")
        .select("category")
        .eq("user_id", userId)
        .eq("date", date)
        .maybeSingle(),
      supabase
        .from("users")
        .select("goals, subscription_tier")
        .eq("id", userId)
        .maybeSingle(),
      supabase
        .from("daily_snapshot")
        .select("source, recovery_score, readiness_score, hrv_ms, sleep_hours, resting_hr, strain_score, stress_score")
        .eq("user_id", userId)
        .eq("date", date),
      countRecentTrainingDaysByBodyPart(supabase, userId, date),
    ]);
    if (!recommendation) {
      return jsonResponse({ error: "no recommendation for this date yet" }, 422);
    }
    const category = recommendation.category as string;
    const goals = (userRow?.goals as string[] | null) ?? [];
    const subscriptionTier = ((userRow?.subscription_tier as SubscriptionTier | null) ?? "free");

    // Which body part today's session should actually target -- the same
    // goals+injury-aware signal RecommendationDetailView's own default-
    // suggestion picker already applies for the normal (non-photo) flow,
    // plus the existing 7-day per-body-part rotation signal, reused rather
    // than reimplemented. See targetBodyPart.ts for why gym-photo needs its
    // own resolution step: unlike the normal flow, there's no client
    // selection to read here.
    const targetBodyPart = resolveTargetBodyPart(category, goals, safety.injuryTags, safety.severityMap, recentBodyPartCounts);

    // Sorted + joined server-side so the client cannot influence cache
    // identity by reordering the list it sends.
    const equipmentSet = normalizeEquipment(confirmedEquipment);
    // The injury state belongs in the cache key. Without it, a plan generated
    // in the morning with no injury noted was replayed unchanged after the
    // user added an injury tag -- serving them back the high-impact jumping
    // session that safety.excludeHighImpact exists to withhold, because the
    // cache hit returns before selectTemplate is ever consulted.
    // ALL injury-derived constraints belong here, not just the high-impact
    // flag: the severity-derived keyword exclusions change which template
    // is selectable, so a severity edit (mild -> severe knee) must miss
    // the cache and re-select -- otherwise the cache replays the morning's
    // squat/lunge session that the new severity exists to withhold.
    // The requested language belongs here too, same reasoning as the
    // injury state above -- otherwise a language switch mid-day replays the morning's wording verbatim.
    // The resolved target body part belongs here for the same reason: it's
    // a new input to selectTemplate, derived from state (injury/rotation)
    // that can change between calls the same way the injury flags above
    // can, so a stale target must miss the cache and re-select rather than
    // replay a plan built around this morning's rotation snapshot.
    // goals belongs here too -- it feeds both selectTemplate's goal
    // tie-break and Luna's wording prompt (goalsText), so a profile goals
    // edit between two same-day calls with identical equipment must also
    // miss the cache, the same way an injury/language change already does.
    const equipmentSignature = Array.from(equipmentSet).sort().join("|") +
      (safety.excludeHighImpact ? "|no-impact" : "") +
      (safety.excludedKeywords.length > 0
        ? "|kw:" + [...safety.excludedKeywords].sort().join(",")
        : "") +
      "|lang:" + languageCode +
      "|target:" + targetBodyPart +
      "|goals:" + [...goals].sort().join(",");

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
      // Refresh the display row too: without this, a user who retakes a
      // photo of a setup they already used today sees the AI-plan card
      // still showing whichever plan was generated most recently, not the
      // one they are looking at.
      await supabase
        .from("ai_workout_plan")
        .upsert(
          {
            user_id: userId,
            date,
            category: cached.category,
            plan: cached.plan,
            selected_title: cached.plan.title,
            source: "gym_photo",
            added_to_plan: false,
            added_at: null,
          },
          { onConflict: "user_id,date" },
        );
      return jsonResponse({ date, category: cached.category, safety_flag: false, source: "gym_photo", ...cached.plan });
    }

    // Reaching here means this equipment setup wasn't already generated
    // today (that would have hit the cache above). If a workout is already
    // logged for today, refuse to generate a different one rather than
    // silently swapping the plan behind an already-completed session --
    // re-viewing the SAME setup that produced today's log is still allowed
    // via the cache hit above; only a genuinely different setup is blocked.
    // NOT maybeSingle: multiple logs per day are supported (the schema has
    // no unique(user_id, date)), and maybeSingle errors on 2+ rows -- with
    // the error unread, `data` came back null and the lock silently
    // disengaged on exactly the days it was written for. The read error is
    // also surfaced now: a guard that fails open on error isn't a guard.
    // device_detected rows now count too: the old silent auto-log path
    // (which wrote one with zero user input) is gone -- HomeView's
    // confirmDetectedWorkout is the only remaining writer of this source,
    // and it only ever runs after an explicit "Yes, that was my workout"
    // tap, so a device_detected row is exactly as deliberate as any other.
    const { data: existingLogs, error: logReadError } = await supabase
      .from("workout_log")
      .select("title")
      .eq("user_id", userId)
      .eq("date", date)
      .limit(1);
    if (logReadError) {
      throw new Error(`could not check today's workout log: ${logReadError.message}`);
    }
    if ((existingLogs ?? []).length > 0) {
      return jsonResponse({
        date,
        locked: true,
        message: "Today's workout is already logged. Generating a different plan won't undo that — pick tomorrow's workout instead.",
      });
    }

    // Only a genuinely new generation reaches here (a cache hit already
    // returned above) -- check the daily cap before paying for one.
    const limitCheck = await checkGenerationLimit(supabase, userId, date, subscriptionTier, "gym_photo");
    if (!limitCheck.allowed) {
      return jsonResponse({ date, generation_limit_reached: true, message: GENERATION_LIMIT_MESSAGE });
    }

    const template = selectTemplate(category, equipmentSet, goals, safety.excludeHighImpact, safety.excludedKeywords, targetBodyPart);

    const wording = await callLunaForWording(
      template,
      goals,
      (snapshots ?? []) as SnapshotRow[],
      equipmentSet,
      language,
    );
    // title/bodyPart travel inside the cached object so a cache hit can
    // return them without re-running selection. actual_duration_minutes is
    // computed from the fixed template (not the wording pass -- Luna never
    // touches sets/reps/duration), so it's always the true total, never an
    // LLM guess.
    const merged = mergeWording(template, wording);
    const plan = {
      ...merged,
      title: template.title,
      bodyPart: template.bodyPart,
      actual_duration_minutes: computeTotalDuration(merged),
    };

    // Two writes, two different jobs -- not a duplicate.
    //
    // gym_workout_plan is the cost cache: keyed on (user, date, equipment,
    // injury state) so retaking a photo of a DIFFERENT setup regenerates
    // while reopening the SAME one is free, and so a plan made before an
    // injury was noted is never replayed after it.
    //
    // ai_workout_plan is the display integration: keyed (user, date) and
    // read by the normal AI-plan card, which is what lets today's
    // gym-photo workout survive closing and reopening the detail sheet.
    // It is deliberately overwritten each time, since the user only has
    // one plan for the day -- whichever they generated last.
    await supabase
      .from("gym_workout_plan")
      .upsert(
        { user_id: userId, date, equipment_signature: equipmentSignature, category, plan },
        { onConflict: "user_id,date,equipment_signature" },
      );
    // A freshly generated plan always starts unconfirmed -- added_to_plan is
    // reset explicitly (not just left to the INSERT default) so regenerating
    // after an earlier same-day plan requires a fresh "Add to today's plan"
    // confirmation for the NEW content, rather than inheriting an old
    // confirmation that was never about this plan.
    await supabase
      .from("ai_workout_plan")
      .upsert(
        { user_id: userId, date, category, plan, selected_title: template.title, source: "gym_photo", added_to_plan: false, added_at: null },
        { onConflict: "user_id,date" },
      );
    await logGeneration(supabase, userId, date, "gym_photo");

    // title/bodyPart arrive via ...plan -- they are stored inside the
    // cached object so the cache-hit path returns them too, without having
    // to re-run selection just to recover two strings.
    return jsonResponse({ date, category, safety_flag: false, source: "gym_photo", ...plan });
  } catch (err) {
    const { status, body } = classifyGenerationError(err);
    return jsonResponse(body, status);
  }
});

async function callLunaForWording(
  template: GymWorkoutTemplate,
  goals: string[],
  snapshots: SnapshotRow[],
  equipment: Set<string>,
  language: string,
): Promise<{ focus: string; exercises: { name: string; instructions: string }[] }> {
  const apiKey = Deno.env.get("OPENAI_API_KEY");
  if (!apiKey) {
    throw new Error("OPENAI_API_KEY is not set as a Supabase secret -- run `supabase secrets set OPENAI_API_KEY=...`");
  }

  const allExercises = [
    ...template.warm_up,
    ...template.blocks.flatMap((b) => b.exercises),
    ...template.cool_down,
  ];
  const exerciseList = allExercises.map((e) => `${e.name} (targets: ${e.target_area})`).join("; ");
  const readinessSummary = describeSnapshots(snapshots);
  // Their target-area framing plus the equipment context. Both matter: the
  // target areas are what the redesigned result screen explains, and the
  // equipment list is the whole point of having taken a photo -- it used to
  // be reduced to matching keywords and then dropped, so the instructions
  // read like a generic plan.
  const goalsText = goals.length ? goals.join(", ") : "general fitness";
  const equipmentSummary = equipment.size > 0
    ? Array.from(equipment).sort().join(", ")
    : "no equipment -- bodyweight only";
  const prompt =
    `You are writing friendly, encouraging per-exercise instructions for a gym workout. The exercises, sets, reps, structure, and target muscle areas are ALREADY DECIDED -- do not rename, add, remove, or reorder any exercise, and do not change which muscles it targets. Write "instructions" text (2-3 sentences) for each of these exercises, in this exact order: ${exerciseList}. Open each one by briefly naming what it targets and why that supports the user's goal (${goalsText}), then give plain-language form cues. The user confirmed they have this equipment available right now: ${equipmentSummary} -- make the cues concrete about that setup where it helps, but never substitute a different exercise or suggest equipment not in that list. Today's readiness: ${readinessSummary}. Also give a one-line "focus" summarizing this session. Write "instructions" and "focus" in ${language}; echo each exercise's "name" back exactly as given above, untranslated.`;

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
  // Two-step lookup. Exact-name matching alone was brittle: the model
  // returning "Cat-Cow Stretch" for "Cat-cow stretch", or "Push Up" for
  // "Push-up", missed and fell back to an empty string -- so the user got a
  // workout with blank instructions, which is the entire point of this step,
  // and the blank version was then cached for the rest of the day.
  //
  // Normalized name first, then position. The prompt fixes the order and the
  // schema enforces it, so index N of the response corresponds to index N of
  // the flattened template; position is a sound fallback, not a guess.
  const normalize = (n: string) => n.toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();
  const byName = new Map(wording.exercises.map((e) => [normalize(e.name), e.instructions]));

  let position = 0;
  const withWording = (name: string) => {
    const byPosition = wording.exercises[position++];
    return byName.get(normalize(name)) || byPosition?.instructions || "";
  };

  return {
    focus: wording.focus || template.focus,
    warm_up: template.warm_up.map((e) => ({ ...e, instructions: withWording(e.name) })),
    blocks: template.blocks.map((b) => ({
      ...b,
      exercises: b.exercises.map((e) => ({ ...e, instructions: withWording(e.name) })),
    })),
    cool_down: template.cool_down.map((e) => ({ ...e, instructions: withWording(e.name) })),
  };
}
