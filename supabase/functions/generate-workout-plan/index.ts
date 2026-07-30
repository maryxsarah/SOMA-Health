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
import { checkSafetyFlags } from "../_shared/safetyFlags.ts";
import { computeTotalDuration } from "../_shared/duration.ts";
import { describeContraindications, type InjurySeverityLevel } from "../_shared/contraindications.ts";

const ANTHROPIC_API_URL = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_VERSION = "2023-06-01";
// Cheap/fast tier -- appropriate for a short, structured, once-a-day
// generation task like this one.
const MODEL = "claude-haiku-4-5";

const EXERCISE_SCHEMA = {
  type: "object",
  properties: {
    name: { type: "string" },
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

const BLOCK_SCHEMA = {
  type: "object",
  properties: {
    // e.g. "Block 1", "Superset A", "Block 3 - Finisher"
    name: { type: "string" },
    // How many times to cycle through this block's exercises -- 1 for a
    // straight-through block, >1 for a circuit/superset.
    rounds: { type: "integer" },
    rest_between_rounds: { type: "string" },
    exercises: { type: "array", items: EXERCISE_SCHEMA },
  },
  required: ["name", "rounds", "rest_between_rounds", "exercises"],
  additionalProperties: false,
};

const WORKOUT_SCHEMA = {
  type: "object",
  properties: {
    focus: { type: "string" },
    warm_up: { type: "array", items: EXERCISE_SCHEMA },
    blocks: { type: "array", items: BLOCK_SCHEMA },
    cool_down: { type: "array", items: EXERCISE_SCHEMA },
  },
  required: ["focus", "warm_up", "blocks", "cool_down"],
  additionalProperties: false,
};

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
    // ProfileView tells the user that while pregnancy is set "Soma won't
    // auto-generate workouts for you" -- but only the gym-photo path honoured
    // that, so the main Generate button handed them a full plan anyway. The
    // promise was strengthened without checking every path that has to keep
    // it.
    //
    // Only the hard-block tier applies here. An injury must NOT block this
    // path: generate-recommendation already caps the day's category when one
    // is noted, and RecommendationDetailView filters high-impact suggestions,
    // so injured users are handled -- blocking them here would break the
    // app's main feature for them.
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
      .select("category, plan, selected_title")
      .eq("user_id", userId)
      .eq("date", date)
      .maybeSingle();
    if (cached && cached.selected_title === selection.title) {
      return jsonResponse({ date, category: cached.category, ...cached.plan });
    }

    // A different selection than what's cached, but the day is already
    // logged -- refuse rather than silently swapping the plan behind an
    // already-completed workout. A log matching this selection's title
    // falls through normally (the cache-read above already served it).
    const { data: existingLog } = await supabase
      .from("workout_log")
      .select("title")
      .eq("user_id", userId)
      .eq("date", date)
      .maybeSingle();
    if (existingLog && existingLog.title !== selection.title) {
      return jsonResponse({
        date,
        locked: true,
        message: "Today's workout is already logged. Generating a different plan won't undo that — pick tomorrow's workout instead.",
      });
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
      .select("goals, equipment, injury_tags, injury_notes, injury_severity, experience_level, sex, date_of_birth, weight_kg")
      .eq("id", userId)
      .maybeSingle();

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

    const prompt = buildPrompt(
      category,
      selection,
      userRow as UserRow | null,
      (snapshots ?? []) as SnapshotRow[],
      (recentLogs ?? []) as WorkoutLogRow[],
      notes,
    );
    let plan = await callClaude(prompt);
    let actualDurationMinutes = computeTotalDuration(plan);

    // One bounded retry when a target was given and the total misses by
    // more than the ~2 min tolerance -- never a silent claim that a
    // mismatched total matches the label. If the retry doesn't land closer,
    // the response still carries the true (mismatched) total rather than
    // pretending precision the model didn't produce.
    if (
      targetDurationRange &&
      (actualDurationMinutes < targetDurationRange.min - 2 || actualDurationMinutes > targetDurationRange.max + 2)
    ) {
      const gapPrompt = `${prompt}\n\nYour previous attempt totaled ~${actualDurationMinutes} min but the target is ${targetDurationRange.min}-${targetDurationRange.max} min -- ${actualDurationMinutes < targetDurationRange.min ? "add 1-2 more working sets or an extra exercise to close the gap" : "trim a set or exercise to fit the target"}, don't just pad or shrink rest periods.`;
      const retryPlan = await callClaude(gapPrompt);
      const retryDuration = computeTotalDuration(retryPlan);
      const targetMid = (targetDurationRange.min + targetDurationRange.max) / 2;
      if (Math.abs(retryDuration - targetMid) < Math.abs(actualDurationMinutes - targetMid)) {
        plan = retryPlan;
        actualDurationMinutes = retryDuration;
      }
    }

    const planWithDuration = { ...plan, actual_duration_minutes: actualDurationMinutes };

    await supabase
      .from("ai_workout_plan")
      .upsert(
        { user_id: userId, date, category, plan: planWithDuration, selected_title: selection.title },
        { onConflict: "user_id,date" },
      );

    return jsonResponse({ date, category, ...planWithDuration });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    const status = msg === "unauthorized" ? 401 : 500;
    return jsonResponse({ error: msg }, status);
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

// DRAFTED, NOT EXPERT-REVIEWED -- thresholds for "exceptionally" high
// readiness, distinct from the ordinary push_hard bar (Whoop 67+ recovery,
// Oura 85+ readiness -- see generate-recommendation/index.ts's
// bandFromWhoop/bandFromOura). Gates a materially more aggressive finisher
// prescription, so these should get the same sign-off as
// LOAD_FRACTION_OF_BODYWEIGHT above before this is treated as authoritative.
const EXCEPTIONAL_WHOOP_RECOVERY = 90;
const EXCEPTIONAL_OURA_READINESS = 95;

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
    "This user is a newbie. Keep it simple: warm_up plus 2 blocks total, the LAST of which is the required finisher (no supersets in the non-finisher block -- rounds: 1), lower volume (2-3 sets per exercise), longer rest, and instructions that over-explain form and cues a beginner wouldn't already know. Avoid complex movement patterns.",
  moderate:
    "This user has moderate training experience. Use warm_up plus 2-3 blocks total, the LAST of which is the required finisher; among the non-finisher blocks, at most one may be a 2-exercise superset (rounds 2-3). Standard rest periods, instructions can assume basic gym literacy (they know what a \"set\" and \"superset\" mean).",
  advanced:
    "This user is advanced. Use warm_up plus 3+ blocks, and make real use of the block/superset/finisher structure -- e.g. Block 1 (compound lift), Block 2 (compound lift), a labeled Superset A/B/C pairing accessory movements back-to-back, and a final Block - Finisher (short, high-effort closer, scaled per the finisher rule below). Higher volume, shorter rest between superset rounds, and instructions can be terse -- assume they know proper form already and just need the prescription.",
};

function buildPrompt(
  category: string,
  selection: Selection,
  userRow: UserRow | null,
  snapshots: SnapshotRow[],
  recentLogs: WorkoutLogRow[],
  notes: string | undefined,
): string {
  const goals = userRow?.goals?.length ? userRow.goals.join(", ") : "general fitness";
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

  const healthLines = describeHealthData(snapshots);

  const historyLines = recentLogs.length
    ? recentLogs.map((l) => `- ${l.date}: ${l.title} (${l.body_part}, ${l.category} day)`).join("\n")
    : "No workouts logged in the last 14 days.";

  const feedbackEntries = recentLogs.filter((l) => l.feedback && l.feedback.trim().length > 0);
  const feedbackLines = feedbackEntries.length
    ? feedbackEntries.map((l) => `- ${l.date} (${l.title}): "${l.feedback}"`).join("\n")
    : null;

  const exceptional = isExceptionalReadiness(category, snapshots);
  const finisherPushHardClause = exceptional
    ? `on today's exceptionally high-readiness day, make the finisher genuinely max-effort (2-4 min, RPE 9-10) -- more rounds or heavier load than an ordinary push_hard day's finisher, and frame it to the user explicitly as "your recovery data is exceptional today, so this finisher pushes harder than usual"`
    : `on "push_hard" days make it short but hard (1-3 min, RPE 8-10, e.g. a max-effort carry, sprint, or hold)`;

  return `You are a certified strength & conditioning coach writing a single day's workout plan for a fitness app user.

The user has already chosen today's workout from the app's suggestion list: "${selection.title}" (target: ${selection.bodyPart}). Build today's plan as a detailed breakdown of exactly this workout -- do not substitute a different type of workout or body part focus. If equipment or injuries below force a change to a specific exercise, keep it a close, safe variant of the same movement pattern rather than switching focus areas.

Today's training intensity (already decided by the app's recovery-based rules -- do not override it): ${category}.
Today's actual health data driving that intensity: ${healthLines}
User's goals: ${goals}.
Training experience: ${experience}. ${experienceGuidance}
Available equipment: ${equipment}.
Noted injuries: ${injuries}.${injuryNotes}
${sexLine}${ageLine ? `\n${ageLine}` : ""}
${loadGuidance}

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
- blocks: an ordered array of named blocks (e.g. "Block 1", "Superset A", "Block 3 - Finisher") that together make up "${selection.title}" for today's "${category}" intensity, following the experience guidance above. Each block has its own rounds (1 for a straight-through block, 2+ for a circuit/superset) and a rest_between_rounds. The LAST block in this array must always be a finisher (name it something like "Block N - Finisher") -- with NO exceptions, even on a low-readiness or short-sleep day. Scale its intensity and duration to today's actual intensity instead of omitting it: ${finisherPushHardClause}; on "moderate" days shorter and less intense (~1-2 min, moderate effort); on "light"/"rest" days very short and gentle (1-2 min, e.g. a held stretch or breathing drill, RPE 2-4 at most). Only its intensity and duration shrink on a harder recovery day -- it must never be left out entirely.
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

async function callClaude(prompt: string): Promise<WorkoutPlanResult> {
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
      output_config: { format: { type: "json_schema", schema: WORKOUT_SCHEMA } },
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
