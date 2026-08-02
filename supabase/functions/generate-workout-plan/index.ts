// generate-workout-plan
//
// AI-generated exercise plan -- warm-up, one or more named blocks making
// up the selected workout (which may include supersets/circuits), and a
// cool-down -- using Claude Haiku. Body:
// { date: "YYYY-MM-DD", selection: { title, bodyPart }, notes?: string }.
// `notes` is optional freeform text the user typed right after checking a
// workout (e.g. "sore shoulder today", "keep it under 30 min") -- folded
// into the prompt for THIS generation only, not persisted anywhere.
//
// Cost control: capped at one generation per user per (day, selection).
// The first call for a given date + selection calls the Anthropic API and
// caches the result in ai_workout_plan; a later call that day with the
// SAME selection (re-opening the detail view, re-fetching after an app
// relaunch) reads the cached row instead of calling the API again. A call
// with a DIFFERENT selection than what's cached regenerates -- caching
// only on `date` here would silently serve the wrong workout back to a
// user who picked something new after an earlier selection that same day.
//
// Personalization: folds in the user's training experience (newbie /
// moderate / advanced -- drives block count and whether supersets are
// used), today's actual health data from daily_snapshot -- not just the
// derived category -- adjusted per wearable to whatever it actually
// reports (Whoop: recovery, HRV, cycle/day strain, sleep; Oura: readiness,
// HRV, sleep, stress minutes; either: resting HR), and the last 14 days
// of workout_log entries (progressive overload).

import { handleOptions, jsonResponse } from "../_shared/cors.ts";
import { requireUser, serviceRoleClient } from "../_shared/clients.ts";
import { classifyGenerationError } from "../_shared/anthropicErrors.ts";
import { checkSafetyFlags } from "../_shared/safetyFlags.ts";
import { checkGenerationLimit, GENERATION_LIMIT_MESSAGE, logGeneration, type SubscriptionTier } from "../_shared/generationLimits.ts";
import { computeTotalDuration } from "../_shared/duration.ts";
import { describeContraindications, type InjurySeverityLevel } from "../_shared/contraindications.ts";
import { describePregnancyGuidance } from "../_shared/pregnancyGuidance.ts";
import { describeVolumeGuidance, type ExperienceLevel } from "../_shared/volumeLandmarks.ts";
import { describeRirGuidance } from "./rirGuidance.ts";
import { describeSexAwareConsiderations } from "./sexAwareGuidance.ts";
import { resolveBodyPartForInjuries } from "../_shared/injurySubstitution.ts";
import { EXCEPTIONAL_OURA_READINESS, EXCEPTIONAL_WHOOP_RECOVERY } from "../_shared/readinessThresholds.ts";
import { decideFinisher, type FinisherDecision } from "./finisherCatalog.ts";
import { fetchCandidateExerciseNames } from "../_shared/exerciseLibraryMatch.ts";

const ANTHROPIC_API_URL = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_VERSION = "2023-06-01";
// Cheap/fast tier -- appropriate for a short, structured, once-a-day
// generation task like this one.
const MODEL = "claude-haiku-4-5";

// Exercise `name` is constrained to a request-scoped closed vocabulary
// (see _shared/exerciseLibraryMatch.ts) via a JSON-schema enum so every
// name the model can possibly return has real, correctly matched media --
// same "deterministic vocabulary, never free text" pattern already used
// for equipment/goal tags elsewhere in this codebase.
function buildExerciseSchema(candidateNames: string[]) {
  return {
    type: "object",
    properties: {
      name: { type: "string", enum: candidateNames },
      sets: { type: "integer" },
      reps: { type: "string" },
      weight_guidance: { type: "string" },
      intensity: { type: "string" },
      duration_minutes: { type: "integer" },
      instructions: { type: "string" },
    },
    required: [
      "name",
      "sets",
      "reps",
      "weight_guidance",
      "intensity",
      "duration_minutes",
      "instructions",
    ],
    additionalProperties: false,
  };
}

function buildBlockSchema(exerciseSchema: ReturnType<typeof buildExerciseSchema>) {
  return {
    type: "object",
    properties: {
      // e.g. "Block 1", "Superset A", "Block 3 - Optional Finisher"
      name: { type: "string" },
      // How many times to cycle through this block's exercises -- 1 for a
      // straight-through block, >1 for a circuit/superset.
      rounds: { type: "integer" },
      rest_between_rounds: { type: "string" },
      exercises: { type: "array", items: exerciseSchema },
      // True only for the optional finisher block, if one is included today
      // -- an explicit flag rather than string-matching the block name, so
      // the client can reliably show the "optional finisher" badge.
      is_finisher: { type: "boolean" },
    },
    required: ["name", "rounds", "rest_between_rounds", "exercises", "is_finisher"],
    additionalProperties: false,
  };
}

function buildWorkoutSchema(candidateNames: string[]) {
  // The exercise schema (dominated by the candidate-name enum) is defined
  // once via $defs and referenced 3x via $ref, rather than embedded 3
  // separate times -- Anthropic's structured-output schema compiler rejects
  // an inlined-3x version of this schema at candidate counts as low as ~130
  // with "Schema is too complex for compilation", even though the enum
  // itself is well within any documented size limit. $ref alone roughly
  // halves the compiled cost; MAIN/STRETCH_CANDIDATE_LIMIT in
  // exerciseLibraryMatch.ts additionally caps candidates so the deduped
  // list stays well under the empirically-found ~115-130 ceiling.
  const exerciseRef = { "$ref": "#/$defs/exercise" };
  const blockSchema = buildBlockSchema(exerciseRef as unknown as ReturnType<typeof buildExerciseSchema>);
  return {
    "$defs": {
      exercise: buildExerciseSchema(candidateNames),
    },
    type: "object",
    properties: {
      focus: { type: "string" },
      warm_up: { type: "array", items: exerciseRef },
      blocks: { type: "array", items: blockSchema },
      cool_down: { type: "array", items: exerciseRef },
    },
    required: ["focus", "warm_up", "blocks", "cool_down"],
    additionalProperties: false,
  };
}

interface Selection {
  title: string;
  bodyPart: string;
}

interface DurationRange {
  min: number;
  max: number;
}

interface UserRow {
  goals: string[] | null;
  equipment: string[] | null;
  injury_tags: string[] | null;
  injury_notes: string | null;
  injury_severity: Record<string, string> | null;
  experience_level: string | null;
  sex: string | null;
  date_of_birth: string | null;
  weight_kg: number | null;
  pregnancy: boolean | null;
  pregnancy_week: number | null;
  body_photo_emphasis_tags: string[] | null;
  // Collected at onboarding, previously never read here despite being
  // free, real signal already on the row.
  workouts_per_week: string | null;
  diet_type: string | null;
  goal_pace: string | null;
  blockers: string[] | null;
  accomplishment_goals: string[] | null;
  desired_weight_kg: number | null;
}

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

interface WorkoutLogRow {
  date: string;
  title: string;
  body_part: string;
  category: string;
  feedback: string | null;
}

interface GeneratedExercise {
  name: string;
  sets: number;
  reps: string;
  weight_guidance: string;
  intensity: string;
  duration_minutes: number;
  instructions: string;
}
interface GeneratedBlock {
  name: string;
  rounds: number;
  rest_between_rounds: string;
  exercises: GeneratedExercise[];
  is_finisher: boolean;
}
interface WorkoutPlanResult {
  focus: string;
  warm_up: GeneratedExercise[];
  blocks: GeneratedBlock[];
  cool_down: GeneratedExercise[];
}

Deno.serve(async (req: Request) => {
  const preflight = handleOptions(req);
  if (preflight) return preflight;

  try {
    const userId = await requireUser(req);
    const body = await req.json().catch(() => ({}));
    const date: string | undefined = body.date;
    const selection: Selection | undefined = body.selection;
    const notes: string | undefined = typeof body.notes === "string" && body.notes.trim().length > 0 ? body.notes.trim() : undefined;
    const targetDurationRange: DurationRange | undefined =
      body.targetDurationRange && typeof body.targetDurationRange.min === "number" && typeof body.targetDurationRange.max === "number"
        ? body.targetDurationRange
        : undefined;
    if (!date) {
      return jsonResponse({ error: "missing 'date' (YYYY-MM-DD)" }, 400);
    }
    if (!selection?.title || !selection?.bodyPart) {
      return jsonResponse({ error: "missing 'selection' (title, bodyPart) -- the app only calls this after the user checks a workout" }, 400);
    }

    const supabase = serviceRoleClient();

    // Guardrail BEFORE the cache read, so a plan generated before the user
    // reported a condition is not replayed back to them afterwards.
    //
    // Only the hard-block tier (abnormal resting HR) applies here. Neither
    // an injury nor pregnancy blocks this path: generate-recommendation
    // already caps the day's category for both, and safetyFlags.ts's
    // excludedKeywords (merged into the prompt via `injuries` below) narrows
    // what gets suggested -- blocking generation entirely would break the
    // app's main feature for these users instead of adjusting it for them.
    const safety = await checkSafetyFlags(supabase, userId, date);
    if (safety.flagged) {
      return jsonResponse({ date, safety_flag: true, message: safety.message });
    }

    // One generation per user per (day, selection): serve the cached plan
    // on repeat calls for the SAME selection instead of hitting the
    // Anthropic API again. A different selection than what's cached means
    // the user picked a different workout -- regenerate rather than
    // silently handing back a plan for something else.
    const { data: cached } = await supabase
      .from("ai_workout_plan")
      .select("category, plan, selected_title, source")
      .eq("user_id", userId)
      .eq("date", date)
      .maybeSingle();
    if (cached && cached.selected_title === selection.title) {
      return jsonResponse({ date, category: cached.category, source: cached.source, ...cached.plan });
    }

    // A different selection than what's cached, but the day is already
    // logged -- refuse rather than silently swapping the plan behind an
    // already-completed workout. A log matching this selection's title
    // falls through normally (the cache-read above already served it).
    // NOT maybeSingle: multiple logs per day are supported (no
    // unique(user_id, date) on workout_log), and maybeSingle errors on 2+
    // rows -- with the error unread, `data` came back null and the lock
    // silently disengaged on exactly the days it was written for. The
    // refusal fires when ANY of today's logs differs from this selection;
    // a day whose every log matches the selection falls through normally.
    const { data: existingLogs, error: logReadError } = await supabase
      .from("workout_log")
      .select("title")
      .eq("user_id", userId)
      .eq("date", date);
    if (logReadError) {
      throw new Error(`could not check today's workout log: ${logReadError.message}`);
    }
    if ((existingLogs ?? []).some((log) => log.title !== selection.title)) {
      return jsonResponse({
        date,
        locked: true,
        message: "Today's workout is already logged. Generating a different plan won't undo that — pick tomorrow's workout instead.",
      });
    }

    // Only a genuinely new generation reaches here (a matching cache hit
    // already returned above) -- check the daily cap before paying for one.
    const { data: tierRow } = await supabase
      .from("users")
      .select("subscription_tier")
      .eq("id", userId)
      .maybeSingle();
    const subscriptionTier = ((tierRow?.subscription_tier as SubscriptionTier | null) ?? "free");
    const limitCheck = await checkGenerationLimit(supabase, userId, date, subscriptionTier);
    if (!limitCheck.allowed) {
      return jsonResponse({ date, generation_limit_reached: true, message: GENERATION_LIMIT_MESSAGE });
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

    const { data: userRow, error: userRowError } = await supabase
      .from("users")
      .select("goals, equipment, injury_tags, injury_notes, injury_severity, experience_level, sex, date_of_birth, weight_kg, pregnancy, pregnancy_week, body_photo_emphasis_tags, workouts_per_week, diet_type, goal_pace, blockers, accomplishment_goals, desired_weight_kg")
      .eq("id", userId)
      .maybeSingle();
    if (userRowError) {
      throw new Error(`could not read user profile: ${userRowError.message}`);
    }

    const { data: snapshots } = await supabase
      .from("daily_snapshot")
      .select("source, recovery_score, readiness_score, hrv_ms, sleep_hours, resting_hr, strain_score, stress_score")
      .eq("user_id", userId)
      .eq("date", date);

    const { data: recentLogs } = await supabase
      .from("workout_log")
      .select("date, title, body_part, category, feedback")
      .eq("user_id", userId)
      .gte("date", addDays(date, -14))
      .lte("date", date)
      .order("date", { ascending: true });

    // Genuine substitution, not just exclusion: a moderate/severe injury
    // that conflicts with the assigned body part redirects to a
    // different, safe one BEFORE the prompt is built, rather than asking
    // the LLM to reshape an unsafe body part into a "safe variant" of
    // itself. Defense-in-depth -- the client's resolve-injury-
    // substitutions endpoint already steers the suggestion list away from
    // conflicting body parts, but a stale list or direct API call still
    // hits this same resolution here.
    const { bodyPart: resolvedBodyPart, substituted } = resolveBodyPartForInjuries(
      selection.bodyPart,
      (userRow as UserRow | null)?.injury_tags ?? [],
      ((userRow as UserRow | null)?.injury_severity ?? {}) as Record<string, InjurySeverityLevel>,
    );
    // The cache/lock keys above stay on the CLIENT's original selection --
    // "did the user pick something different" is about their choice, not
    // the resolved body part. Only the prompt itself sees the substitution.
    const resolvedSelection: Selection = substituted
      ? { title: `${bodyPartDisplayName(resolvedBodyPart)} (adjusted for your noted injury)`, bodyPart: resolvedBodyPart }
      : selection;

    // Deterministic finisher decision -- whether one appears at all today,
    // and whether it's the exceptional max-effort version. Never left to
    // the LLM: gated on category, readiness, injury contraindications, and
    // yesterday's logged split, all computed here before the prompt exists.
    const { excludedKeywords: finisherExcludedKeywords } = describeContraindications(
      (userRow as UserRow | null)?.injury_tags ?? [],
      ((userRow as UserRow | null)?.injury_severity ?? {}) as Record<string, InjurySeverityLevel>,
    );
    const finisherDecision = decideFinisher(
      category,
      resolvedBodyPart,
      isExceptionalReadiness(category, (snapshots ?? []) as SnapshotRow[]),
      finisherExcludedKeywords,
      (recentLogs ?? []) as WorkoutLogRow[],
      addDays(date, -1),
    );

    const prompt = buildPrompt(
      category,
      resolvedSelection,
      substituted,
      finisherDecision,
      userRow as UserRow | null,
      (snapshots ?? []) as SnapshotRow[],
      (recentLogs ?? []) as WorkoutLogRow[],
      notes,
    );

    // Same closed-vocabulary keyword exclusions used to keep the finisher
    // decision safe also keep the candidate exercise-name list safe --
    // pregnancy adds its own trimester-scaled exclusions on top.
    const pregnancyExcludedKeywords = (userRow as UserRow | null)?.pregnancy
      ? describePregnancyGuidance((userRow as UserRow | null)?.pregnancy_week ?? null).excludedKeywords
      : [];
    const candidateExerciseNames = await fetchCandidateExerciseNames(
      supabase,
      resolvedBodyPart,
      (userRow as UserRow | null)?.equipment ?? [],
      [...finisherExcludedKeywords, ...pregnancyExcludedKeywords],
      (userRow as UserRow | null)?.experience_level ?? null,
    );
    const workoutSchema = buildWorkoutSchema(candidateExerciseNames);

    let plan = await callClaude(prompt, workoutSchema);
    let actualDurationMinutes = computeTotalDuration(plan);

    // One bounded retry when a target was given and the total misses by
    // more than the tolerance -- never a silent claim that a mismatched
    // total matches the label. If the retry doesn't land closer, the
    // response still carries the true (mismatched) total rather than
    // pretending precision the model didn't produce. Tolerance is
    // proportional (min 5 min): the old flat ±2 on a single-valued 50-min
    // target forced a second serial LLM call on almost every fresh
    // generation, which is what pushed first attempts past the client's
    // request timeout while retries were served instantly from cache.
    const durationTolerance = targetDurationRange
      ? Math.max(5, Math.round((targetDurationRange.min + targetDurationRange.max) / 2 * 0.15))
      : 0;
    if (
      targetDurationRange &&
      (actualDurationMinutes < targetDurationRange.min - durationTolerance ||
        actualDurationMinutes > targetDurationRange.max + durationTolerance)
    ) {
      const gapPrompt = `${prompt}\n\nYour previous attempt totaled ~${actualDurationMinutes} min but the target is ${targetDurationRange.min}-${targetDurationRange.max} min -- ${actualDurationMinutes < targetDurationRange.min ? "add 1-2 more working sets or an extra exercise to close the gap" : "trim a set or exercise to fit the target"}, don't just pad or shrink rest periods.`;
      const retryPlan = await callClaude(gapPrompt, workoutSchema);
      const retryDuration = computeTotalDuration(retryPlan);
      const targetMid = (targetDurationRange.min + targetDurationRange.max) / 2;
      if (Math.abs(retryDuration - targetMid) < Math.abs(actualDurationMinutes - targetMid)) {
        plan = retryPlan;
        actualDurationMinutes = retryDuration;
      }
    }

    const planWithDuration = {
      ...plan,
      actual_duration_minutes: actualDurationMinutes,
      substituted_body_part: substituted ? resolvedBodyPart : null,
      // Drives the "Optional finisher -- you're well recovered today"
      // badge client-side (AIWorkoutPlanSections.swift) -- only ever true
      // alongside a block whose is_finisher is also true.
      exceptional_finisher: finisherDecision.exceptional,
    };

    // A freshly generated plan always starts unconfirmed -- added_to_plan is
    // reset explicitly so regenerating requires a fresh "Add to today's
    // plan" confirmation for the NEW content (see generate-gym-workout's
    // matching comment).
    await supabase
      .from("ai_workout_plan")
      .upsert(
        { user_id: userId, date, category, plan: planWithDuration, selected_title: selection.title, source: "suggestion", added_to_plan: false, added_at: null },
        { onConflict: "user_id,date" },
      );
    await logGeneration(supabase, userId, date, "suggestion");

    return jsonResponse({ date, category, source: "suggestion", ...planWithDuration });
  } catch (err) {
    const { status, body } = classifyGenerationError(err);
    return jsonResponse(body, status);
  }
});

// DRAFT -- NOT reviewed by a certified S&C professional. Rough NSCA/ACSM-
// style working-set load bands (fraction of bodyweight) per major lift
// pattern x experience level. Passed into the prompt as guideline RANGES
// the model should stay within, not parsed/clamped from its free-text
// weight_guidance after the fact (that parsing would be unreliable).
// Needs expert sign-off before shipping, same as templates.ts's own
// equipment-coverage disclaimer.
const LOAD_FRACTION_OF_BODYWEIGHT: Record<string, Record<string, [number, number]>> = {
  squat_pattern: { newbie: [0.3, 0.6], moderate: [0.5, 1.0], advanced: [0.75, 1.5] },
  hinge_pattern: { newbie: [0.4, 0.7], moderate: [0.6, 1.2], advanced: [0.9, 1.75] },
  overhead_press: { newbie: [0.15, 0.3], moderate: [0.25, 0.45], advanced: [0.35, 0.6] },
  horizontal_press: { newbie: [0.25, 0.5], moderate: [0.4, 0.7], advanced: [0.55, 1.0] },
  row_pull: { newbie: [0.2, 0.4], moderate: [0.35, 0.6], advanced: [0.5, 0.85] },
};

/// Simple year-diff -- good enough for the general caution language this
/// feeds (age is passed as context, not a numeric load formula: there's no
/// citable evidence-based age->load table to encode as fact here).
function ageFromDOB(dob: string): number {
  const birth = new Date(dob);
  const now = new Date();
  let age = now.getUTCFullYear() - birth.getUTCFullYear();
  const hasHadBirthdayThisYear = now.getUTCMonth() > birth.getUTCMonth() ||
    (now.getUTCMonth() === birth.getUTCMonth() && now.getUTCDate() >= birth.getUTCDate());
  if (!hasHadBirthdayThisYear) age -= 1;
  return age;
}

/// Guideline load ranges for today's experience level, as a prompt-ready
/// paragraph -- omitted entirely when bodyweight is unknown rather than
/// guessing a number.
function buildLoadGuidance(weightKg: number | null, experience: string): string {
  if (weightKg === null) {
    return "The user's bodyweight isn't on file -- for any barbell/dumbbell/kettlebell working set, use conservative, experience-appropriate language ('start light and build') instead of a specific number.";
  }
  const level = LOAD_FRACTION_OF_BODYWEIGHT.squat_pattern[experience] ? experience : "moderate";
  const range = (pattern: string) => {
    const [low, high] = LOAD_FRACTION_OF_BODYWEIGHT[pattern][level];
    return `${(low * weightKg).toFixed(0)}-${(high * weightKg).toFixed(0)}kg`;
  };
  return `The user weighs ${weightKg}kg, ${experience} experience. For any working set targeting these patterns, keep weight_guidance's suggested load within these guideline ranges once warmed up (not a strict per-rep ceiling, use professional judgment for warm-ups): squat pattern ${range("squat_pattern")}; hinge pattern (deadlift-style) ${range("hinge_pattern")}; overhead press ${range("overhead_press")}; horizontal press (bench/push-up-with-added-load) ${range("horizontal_press")}; row/pull ${range("row_pull")}.`;
}

/// Mirrors Soma/Models/OnboardingSurveyModels.swift's WorkoutFrequency enum.
function workoutsPerWeekLabel(raw: string | null): string {
  switch (raw) {
    case "zero_to_two": return "Trains 0-2 times/week currently.";
    case "three_to_five": return "Trains 3-5 times/week currently.";
    case "six_plus": return "Trains 6+ times/week currently.";
    default: return "";
  }
}

/// Mirrors Soma/Models/OnboardingSurveyModels.swift's DietType enum.
function dietLabel(raw: string): string {
  switch (raw) {
    case "whole_food": return "whole food";
    case "low_carb": return "low carb";
    case "none": return "no specific diet";
    default: return raw;
  }
}

/// Mirrors Soma/Models/OnboardingSurveyModels.swift's BlockerTag enum.
function blockerLabel(raw: string): string {
  switch (raw) {
    case "lack_of_consistency": return "lack of consistency";
    case "unhealthy_habits": return "unhealthy habits";
    case "lack_of_support": return "lack of support";
    case "busy_schedule": return "busy schedule";
    case "no_idea_where_to_start": return "not knowing where to start";
    default: return raw;
  }
}

/// Fallback title used only when generate-workout-plan itself substitutes
/// a conflicting body part -- the client's resolve-injury-substitutions
/// endpoint normally steers the suggestion list away from this case
/// before the user ever picks a title, so this only fires as a
/// defense-in-depth fallback.
function bodyPartDisplayName(bodyPart: string): string {
  switch (bodyPart) {
    case "full_body": return "Full Body Strength";
    case "upper_body": return "Upper Body Strength";
    case "lower_body": return "Lower Body Strength";
    case "core": return "Core & Mobility";
    case "cardio": return "Cardio";
    case "recovery": return "Active Recovery";
    default: return "Workout";
  }
}

/// True only on an already-push_hard day where recovery is exceptional, not
/// just sufficient -- lets the existing mandatory finisher (see the `blocks`
/// bullet in buildPrompt below) push harder on the best days instead of
/// treating every push_hard day identically.
function isExceptionalReadiness(category: string, snapshots: SnapshotRow[]): boolean {
  if (category !== "push_hard") return false;
  return snapshots.some((s) =>
    (s.recovery_score !== null && s.recovery_score >= EXCEPTIONAL_WHOOP_RECOVERY) ||
    (s.readiness_score !== null && s.readiness_score >= EXCEPTIONAL_OURA_READINESS)
  );
}

const EXPERIENCE_GUIDANCE: Record<string, string> = {
  newbie:
    "This user is a newbie. Keep it simple: warm_up plus 1-2 non-finisher blocks (no supersets -- rounds: 1), lower volume (2-3 sets per exercise), longer rest, and instructions that over-explain form and cues a beginner wouldn't already know. Avoid complex movement patterns. If a finisher block is called for below, it comes LAST, after these.",
  moderate:
    "This user has moderate training experience. Use warm_up plus 2-3 non-finisher blocks; at most one may be a 2-exercise superset (rounds 2-3). Standard rest periods, instructions can assume basic gym literacy (they know what a \"set\" and \"superset\" mean). If a finisher block is called for below, it comes LAST, after these.",
  advanced:
    "This user is advanced. Use warm_up plus 3+ non-finisher blocks, and make real use of the block/superset structure -- e.g. Block 1 (compound lift), Block 2 (compound lift), a labeled Superset A/B/C pairing accessory movements back-to-back. Higher volume, shorter rest between superset rounds, and instructions can be terse -- assume they know proper form already and just need the prescription. If a finisher block is called for below, it comes LAST, after these.",
};

function buildPrompt(
  category: string,
  selection: Selection,
  wasSubstituted: boolean,
  finisherDecision: FinisherDecision,
  userRow: UserRow | null,
  snapshots: SnapshotRow[],
  recentLogs: WorkoutLogRow[],
  notes: string | undefined,
): string {
  const goals = userRow?.goals?.length ? userRow.goals.join(", ") : "general fitness";
  // A secondary, lower-confidence signal from comparing the user's stored
  // goal/current body photos (see analyze-body-photo) -- kept separate from
  // the user's own stated `goals` above rather than merged into it, so
  // "the user said X" is never indistinguishable from "the model guessed
  // X". Only appended when non-empty.
  const bodyPhotoEmphasisLine = userRow?.body_photo_emphasis_tags?.length
    ? `\nA comparison of the user's current and goal-body photos additionally suggests emphasizing: ${userRow.body_photo_emphasis_tags.join(", ")}. Treat this as a secondary signal alongside -- not a replacement for -- the stated goals above.`
    : "";
  const equipment = userRow?.equipment?.length
    ? userRow.equipment.join(", ")
    : "no equipment (bodyweight only)";
  // Deterministic exclusion sentence -- never left to the model to infer
  // what's safe, same rule this codebase applies everywhere else.
  const { promptLine: injuries } = describeContraindications(
    userRow?.injury_tags ?? [],
    (userRow?.injury_severity ?? {}) as Record<string, InjurySeverityLevel>,
  );
  const injuryNotes = userRow?.injury_notes ? ` User's free-text notes: ${userRow.injury_notes}.` : "";
  const experience = userRow?.experience_level ?? "moderate";
  const experienceGuidance = EXPERIENCE_GUIDANCE[experience] ?? EXPERIENCE_GUIDANCE.moderate;
  const loadGuidance = buildLoadGuidance(userRow?.weight_kg ?? null, experience);
  const ageLine = userRow?.date_of_birth ? `The user is ${ageFromDOB(userRow.date_of_birth)} years old -- use general caution appropriate to their age, but this is context, not a numeric load rule.` : "";
  const sexLine = userRow?.sex ? `Sex: ${userRow.sex}.` : "";
  // Deterministic, trimester-scaled guidance -- never left to the model to
  // infer what's safe during pregnancy, same rule as injuries above. The
  // doctor/midwife disclaimer is shown as a fixed UI banner client-side
  // (RecommendationDetailView), not relied on to appear in the LLM's output.
  const pregnancyLine = userRow?.pregnancy === true
    ? `\nThe user is pregnant. ${describePregnancyGuidance(userRow?.pregnancy_week ?? null).promptLine}.`
    : "";

  // Generic, published exercise-science guidance -- deterministic strings,
  // never left to the model to invent. See volumeLandmarks.ts/rirGuidance.ts/
  // sexAwareGuidance.ts for the framing constraint (principles, never
  // attributed to a named individual).
  const experienceLevel = experience as ExperienceLevel;
  const volumeGuidanceLine = describeVolumeGuidance(experienceLevel, category);
  const rirGuidanceLine = describeRirGuidance(goals, experienceLevel, category);
  const sexAwareLine = describeSexAwareConsiderations(userRow?.sex ?? null, category);

  // Free, real signal already collected at onboarding but not previously
  // threaded into this prompt.
  const workoutsPerWeekLine = workoutsPerWeekLabel(userRow?.workouts_per_week ?? null);
  const dietLine = userRow?.diet_type ? `Diet preference: ${dietLabel(userRow.diet_type)}.` : "";
  const goalPaceLine = userRow?.goal_pace
    ? `Target pace toward their goal: ${userRow.goal_pace} -- treat this as a cue for how aggressive vs. conservative to make today's session, not a numeric calorie rule.`
    : "";
  const blockersLine = userRow?.blockers?.length
    ? `What's gotten in their way before: ${userRow.blockers.map(blockerLabel).join(", ")} -- bias toward simplicity and consistency in how the session is framed if relevant (e.g. shorter/clearer instructions for "busy schedule" or "overwhelmed").`
    : "";
  const accomplishmentLine = userRow?.accomplishment_goals?.length
    ? `In their own words, what they want to accomplish: ${userRow.accomplishment_goals.map((g) => `"${g}"`).join(", ")}.`
    : "";

  const healthLines = describeHealthData(snapshots);

  const historyLines = recentLogs.length
    ? recentLogs.map((l) => `- ${l.date}: ${l.title} (${l.body_part}, ${l.category} day)`).join("\n")
    : "No workouts logged in the last 14 days.";

  const feedbackEntries = recentLogs.filter((l) => l.feedback && l.feedback.trim().length > 0);
  const feedbackLines = feedbackEntries.length
    ? feedbackEntries.map((l) => `- ${l.date} (${l.title}): "${l.feedback}"`).join("\n")
    : null;

  // Optional now, not mandatory ("no exceptions" used to be the rule) --
  // whether a finisher appears at all, and whether it's the full
  // max-effort version, was already decided deterministically by
  // decideFinisher() before this prompt was built (category eligibility,
  // readiness, injury contraindications, and yesterday's logged split).
  // The LLM only elaborates the chosen concept into concrete exercises.
  // The catalog's example movements name gear freely (barbells, rowing) --
  // this constraint re-anchors the elaboration to what the user owns.
  const finisherEquipmentConstraint =
    ` The finisher's movements must use ONLY the user's available equipment listed above -- if they have none, every finisher movement must be strictly bodyweight-only (no bars, no implements), even if the concept's examples mention gear. Keep every finisher movement's difficulty appropriate to the user's training experience described above -- for a newbie that means simple, low-skill movements only.`;
  const finisherInstruction = !finisherDecision.include
    ? `Do NOT include a finisher block today. On a "${category}" day, every block should stay gentle -- no high-effort closer of any kind.`
    : finisherDecision.exceptional && finisherDecision.definition
    ? `Include exactly one finisher as the LAST block, named "Block N - Optional Finisher" (is_finisher: true, every other block is_finisher: false). Your recovery data is exceptionally good today, so make it genuinely max-effort: ${finisherDecision.definition.durationMinutesRange[1]} min, ${finisherDecision.definition.rpeTarget.replace("RPE 8-9", "RPE 9-10").replace("RPE 8", "RPE 9-10")}, built around this concept -- ${finisherDecision.definition.description} Frame it to the user explicitly as "your recovery data is exceptional today, so this finisher pushes harder than usual."${finisherEquipmentConstraint}`
    : finisherDecision.definition
    ? `Include exactly one finisher as the LAST block, named "Block N - Optional Finisher" (is_finisher: true, every other block is_finisher: false), clearly optional and skippable without any penalty to the rest of the session -- state that plainly in its instructions. ${finisherDecision.definition.durationMinutesRange[0]}-${finisherDecision.definition.durationMinutesRange[1]} min, built around this concept -- ${finisherDecision.definition.description} Scale effort to a solid but not maximal ${finisherDecision.definition.rpeTarget}.${finisherEquipmentConstraint}`
    : `Do NOT include a finisher block today.`;

  const substitutionLine = wasSubstituted
    ? `This target was already redirected server-side to a safe body part given the user's noted injury (their original selection conflicted with it) -- build the plan around "${selection.bodyPart}" as given, do not try to reintroduce the original focus area.`
    : `Build today's plan as a detailed breakdown of exactly this workout -- do not substitute a different type of workout or body part focus. If equipment or injuries below force a change to a specific exercise, keep it a close, safe variant of the same movement pattern rather than switching focus areas.`;

  return `You are a certified strength & conditioning coach writing a single day's workout plan for a fitness app user.

The user has already chosen today's workout from the app's suggestion list: "${selection.title}" (target: ${selection.bodyPart}). ${substitutionLine}

Today's training intensity (already decided by the app's recovery-based rules -- do not override it): ${category}.
Today's actual health data driving that intensity: ${healthLines}
User's goals: ${goals}.${bodyPhotoEmphasisLine}
Training experience: ${experience}. ${experienceGuidance}
Available equipment: ${equipment}.
Noted injuries: ${injuries}.${injuryNotes}
${sexLine}${ageLine ? `\n${ageLine}` : ""}${pregnancyLine}
${loadGuidance}
${volumeGuidanceLine ? `\n${volumeGuidanceLine}` : ""}
${rirGuidanceLine ? `\n${rirGuidanceLine}` : ""}
${sexAwareLine ? `\n${sexAwareLine}` : ""}
${workoutsPerWeekLine ? `\n${workoutsPerWeekLine}` : ""}${dietLine ? `\n${dietLine}` : ""}${goalPaceLine ? `\n${goalPaceLine}` : ""}${blockersLine ? `\n${blockersLine}` : ""}${accomplishmentLine ? `\n${accomplishmentLine}` : ""}

Recent logged workouts (last 14 days, oldest first) -- use this for progressive overload: if the user has repeated an exercise, suggest a sensible progression (more reps, more weight, or more sets) rather than repeating the exact same prescription. If an exercise is new, prescribe a safe, moderate starting point.
${historyLines}
${
    feedbackLines
      ? `\nFeedback the user left on recent workouts -- these are standing preferences, not one-off comments. Honor anything still relevant to today's session (same body part or workout type especially) rather than treating it as a single past instance:\n${feedbackLines}\n`
      : ""
  }${
    notes
      ? `\nThe user added this note specifically for TODAY's session -- factor it in directly (e.g. a specific constraint, preference, or how they're feeling right now), even if it means adjusting an exercise choice within the workout above:\n"${notes}"\n`
      : ""
  }
Return the full session as:
- warm_up: 2-3 items that specifically prepare the body for THIS workout and adjust to today's health data above (e.g. lighter/shorter if recovery or sleep was poor) -- concrete named items like "5 min incline treadmill walk", "2x10 arm circles", "shoulder rolls", not a generic "warm up" placeholder.
- blocks: an ordered array of named blocks (e.g. "Block 1", "Superset A") that together make up "${selection.title}" for today's "${category}" intensity, following the experience guidance above. Each block has its own rounds (1 for a straight-through block, 2+ for a circuit/superset), a rest_between_rounds, and is_finisher (true only for the optional finisher block described next, false for every other block). ${finisherInstruction}
- cool_down: 2-3 items of static stretching/breathing targeting the muscles just worked.

For every exercise in warm_up, every block's exercises, and cool_down, give: name, sets (integer -- use 1 for anything that's just a held stretch or a single timed activity, not part of a multi-round block), reps (a string, e.g. "8-10", "30 sec", "5 min"), weight_guidance (concrete and actionable -- e.g. "start light, 2x8kg dumbbells" or "bodyweight" or "N/A" for stretches -- not vague advice), intensity (e.g. "RPE 6/10" or "easy/moderate/hard"), duration_minutes for that item including rest, and instructions (2-3 sentences, plain and easy to follow, describing exact form/technique). Also give a one-line "focus" summarizing today's session.`;
}

/// Turns whichever provider(s) reported today into a plain-language health
/// summary for the prompt -- the model should adjust the session to this,
/// not just to the derived category label.
function describeHealthData(snapshots: SnapshotRow[]): string {
  if (snapshots.length === 0) {
    return "No wearable data reported today; category was derived from on-device signals or defaults.";
  }

  const parts: string[] = [];
  for (const s of snapshots) {
    const bits: string[] = [];
    if (s.recovery_score !== null) bits.push(`Whoop recovery ${s.recovery_score}%`);
    if (s.readiness_score !== null) bits.push(`Oura readiness ${s.readiness_score}`);
    if (s.hrv_ms !== null) bits.push(`HRV ${s.hrv_ms}ms`);
    if (s.sleep_hours !== null) bits.push(`slept ${s.sleep_hours}h`);
    if (s.resting_hr !== null) bits.push(`resting HR ${s.resting_hr}bpm`);
    if (s.strain_score !== null) {
      // Whoop's cycle strain is a 0-21 day-strain number; Oura has no
      // equivalent, so its "strain_score" is a count of recent
      // hard-intensity workouts instead -- label each accordingly rather
      // than implying they're the same scale.
      bits.push(
        s.source === "whoop"
          ? `day strain ${s.strain_score}/21`
          : `${s.strain_score} recent hard-intensity session(s)`,
      );
    }
    if (s.stress_score !== null) bits.push(`${s.stress_score}min in high stress today`);
    if (bits.length > 0) parts.push(`${s.source}: ${bits.join(", ")}`);
  }
  return parts.length > 0 ? parts.join("; ") : "Wearable connected but no metrics reported today.";
}

async function callClaude(
  prompt: string,
  // deno-lint-ignore no-explicit-any
  schema: any,
): Promise<WorkoutPlanResult> {
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
      max_tokens: 4096,
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
  return JSON.parse(textBlock.text);
}

function addDays(dateStr: string, days: number): string {
  const d = new Date(`${dateStr}T00:00:00.000Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}
