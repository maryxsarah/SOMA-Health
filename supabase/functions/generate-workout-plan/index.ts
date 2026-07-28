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

interface UserRow {
  goals: string[] | null;
  equipment: string[] | null;
  injury_tags: string[] | null;
  injury_notes: string | null;
  experience_level: string | null;
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

Deno.serve(async (req: Request) => {
  const preflight = handleOptions(req);
  if (preflight) return preflight;

  try {
    const userId = await requireUser(req);
    const body = await req.json().catch(() => ({}));
    const date: string | undefined = body.date;
    const selection: Selection | undefined = body.selection;
    const notes: string | undefined = typeof body.notes === "string" && body.notes.trim().length > 0 ? body.notes.trim() : undefined;
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
      .select("goals, equipment, injury_tags, injury_notes, experience_level")
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
    const plan = await callClaude(prompt);

    await supabase
      .from("ai_workout_plan")
      .upsert(
        { user_id: userId, date, category, plan, selected_title: selection.title },
        { onConflict: "user_id,date" },
      );

    return jsonResponse({ date, category, ...plan });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    const status = msg === "unauthorized" ? 401 : 500;
    return jsonResponse({ error: msg }, status);
  }
});

const EXPERIENCE_GUIDANCE: Record<string, string> = {
  newbie:
    "This user is a newbie. Keep it simple: warm_up plus 2 blocks (no supersets -- every block should have rounds: 1), lower volume (2-3 sets per exercise), longer rest, and instructions that over-explain form and cues a beginner wouldn't already know. Avoid complex movement patterns.",
  moderate:
    "This user has moderate training experience. Use warm_up plus 2-3 blocks; at most one of those blocks may be a 2-exercise superset (rounds 2-3). Standard rest periods, instructions can assume basic gym literacy (they know what a \"set\" and \"superset\" mean).",
  advanced:
    "This user is advanced. Use warm_up plus 3+ blocks, and make real use of the block/superset/finisher structure -- e.g. Block 1 (compound lift), Block 2 (compound lift), a labeled Superset A/B/C pairing accessory movements back-to-back, and a Block 3 - Finisher (short, high-effort closer). Higher volume, shorter rest between superset rounds, and instructions can be terse -- assume they know proper form already and just need the prescription.",
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
  const injuries = userRow?.injury_tags?.length ? userRow.injury_tags.join(", ") : "none noted";
  const injuryNotes = userRow?.injury_notes ? ` (${userRow.injury_notes})` : "";
  const experience = userRow?.experience_level ?? "moderate";
  const experienceGuidance = EXPERIENCE_GUIDANCE[experience] ?? EXPERIENCE_GUIDANCE.moderate;

  const healthLines = describeHealthData(snapshots);

  const historyLines = recentLogs.length
    ? recentLogs.map((l) => `- ${l.date}: ${l.title} (${l.body_part}, ${l.category} day)`).join("\n")
    : "No workouts logged in the last 14 days.";

  const feedbackEntries = recentLogs.filter((l) => l.feedback && l.feedback.trim().length > 0);
  const feedbackLines = feedbackEntries.length
    ? feedbackEntries.map((l) => `- ${l.date} (${l.title}): "${l.feedback}"`).join("\n")
    : null;

  return `You are a certified strength & conditioning coach writing a single day's workout plan for a fitness app user.

The user has already chosen today's workout from the app's suggestion list: "${selection.title}" (target: ${selection.bodyPart}). Build today's plan as a detailed breakdown of exactly this workout -- do not substitute a different type of workout or body part focus. If equipment or injuries below force a change to a specific exercise, keep it a close, safe variant of the same movement pattern rather than switching focus areas.

Today's training intensity (already decided by the app's recovery-based rules -- do not override it): ${category}.
Today's actual health data driving that intensity: ${healthLines}
User's goals: ${goals}.
Training experience: ${experience}. ${experienceGuidance}
Available equipment: ${equipment}.
Noted injuries: ${injuries}${injuryNotes}.

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
- blocks: an ordered array of named blocks (e.g. "Block 1", "Superset A", "Block 3 - Finisher") that together make up "${selection.title}" for today's "${category}" intensity, following the experience guidance above. Each block has its own rounds (1 for a straight-through block, 2+ for a circuit/superset) and a rest_between_rounds.
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

async function callClaude(prompt: string): Promise<{
  focus: string;
  warm_up: unknown[];
  blocks: unknown[];
  cool_down: unknown[];
}> {
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
