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
import { decideShapingGoalGuidance } from "./shapingGoalGuidance.ts";
import { describeAnchorSessions } from "./anchorSessionGuidance.ts";
import { describeSexAwareConsiderations, describeSexAwareGoalDoseConsideration } from "./sexAwareGuidance.ts";
import { type CyclePhaseResult, deriveCyclePhase } from "../_shared/cyclePhaseGuidance.ts";
import { resolveBodyPartForInjuries } from "../_shared/injurySubstitution.ts";
import { EXCEPTIONAL_OURA_READINESS, EXCEPTIONAL_WHOOP_RECOVERY } from "../_shared/readinessThresholds.ts";
import { decideFinisher, type FinisherDecision } from "./finisherCatalog.ts";
import type { TrainingEmphasis } from "../_shared/nutritionTargets.ts";
import { coolDownRepeatsYesterday, findDuplicateExerciseNames, finisherMissing } from "./planValidation.ts";
import { findWeightCeilingViolations } from "./weightValidation.ts";
import { reconcileExerciseDurations } from "./durationValidation.ts";
import { buildLoadGuidance } from "./loadGuidance.ts";
import { buildWorkoutSchema } from "./workoutSchema.ts";
import { fetchCandidateExerciseNames } from "../_shared/exerciseLibraryMatch.ts";
import { resolveFreeTextEquipment } from "../_shared/equipment.ts";
import { fetchOutdoorSafetyForCity, isOutdoorCardioExerciseName } from "../_shared/weatherSafety.ts";
import {
  computeEtaShift,
  conceptFromRow,
  decideGoalWork,
  decideSafetyPause,
  describeUpcomingGoalWork,
  deriveEtaInputs,
  derivePhase,
  type GoalBlockHistoryEntry,
  type GoalState,
  type GoalWorkBlock,
  type GoalWorkConcept,
} from "./goalWork.ts";
import { languageName, normalizeLanguageCode } from "../_shared/language.ts";

const ANTHROPIC_API_URL = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_VERSION = "2023-06-01";
// Cheap/fast tier -- appropriate for a short, structured, once-a-day
// generation task like this one.
const MODEL = "claude-haiku-4-5";

// Mirrors exerciseLibraryMatch.ts's MIN_CANDIDATES_AFTER_FRESHNESS_EXCLUSION
// -- never shrink the candidate pool so far a weather-unsafe exercise
// becomes preferable to what's left. In practice this floor is rarely
// tested: the exercise library is mostly gym/strength content, so outdoor
// cardio is a small slice of any given candidate pool.
const MIN_CANDIDATES_AFTER_WEATHER_EXCLUSION = 5;

// buildExerciseSchema/buildBlockSchema/buildWorkoutSchema live in
// workoutSchema.ts (pure, no dependency on anything else in this file) --
// pulled out specifically so they're directly unit-testable (importing
// index.ts itself for a test would run its top-level Deno.serve as a side
// effect). See that file for buildWorkoutSchema's minItems guarantee.

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
  /// Onboarding's "what else do you have access to?" free text -- see
  /// resolveFreeTextEquipment for why this is now actually read.
  other_equipment_notes: string | null;
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
  /// Silent output of analyze-body-photo's goal/current comparison (same
  /// source as body_photo_emphasis_tags above) -- a coarser directional
  /// read (cut/recomp/bulk/maintain) than the tag set, used here to bias
  /// finisher selection and to add one more prompt line. Kept separate
  /// from `goals`, same reasoning as body_photo_emphasis_tags.
  training_emphasis: TrainingEmphasis | null;
  /// Optional, user-stated real working weights (Profile's "your current
  /// lifts" section) keyed by the same bilateral pattern names as
  /// loadGuidance.ts's LOAD_FRACTION_OF_BODYWEIGHT -- when present for a
  /// pattern, buildLoadGuidance uses it instead of the population-level
  /// bodyweight-ratio estimate. See that function's own comment for the
  /// bug this exists to fix.
  known_lifts: Record<string, number> | null;
  /// Feeds the outdoor-cardio weather safety check (weatherSafety.ts) --
  /// real feedback: "when the user is in Dubai, and the temperature ...
  /// is 42 degrees celsius, SOMA should not recommend a run outside."
  country: string | null;
  city: string | null;
  /// Phase 4 (docs/coaching-personalization-plan.md): up to 5 recurring
  /// classes/activities the rest of the week gets built around, set at
  /// onboarding or from ProfileView (item 6 fix: was a single name/days
  /// pair). See anchorSessionGuidance.ts for how this feeds the prompt.
  anchor_sessions: { id: string; name: string; days: number[] }[] | null;
  /// Phase 5 (docs/coaching-personalization-plan.md): opt-in cycle-phase
  /// tracking, set only from ProfileView (never onboarding, same posture
  /// as pregnancy/pregnancy_week). Null date = not opted in. See
  /// _shared/cyclePhaseGuidance.ts for the derivation this feeds.
  last_period_start_date: string | null;
  typical_cycle_length_days: number | null;
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
  // Nullable here (unlike the schema's own required integer, which Claude
  // always fills in): buildCoachBlock below hand-builds a placeholder
  // exercise with no parseable rest prescription and needs an honest "not
  // known" rather than a fabricated number.
  rest_seconds: number | null;
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
    const languageCode = normalizeLanguageCode(body.language);
    const language = languageName(body.language);
    const notes: string | undefined = typeof body.notes === "string" && body.notes.trim().length > 0 ? body.notes.trim() : undefined;
    // "Regenerate" (11d): the user wants a fresh take on the SAME
    // selection, not just whatever's already cached for today. Only
    // bypasses the cache-hit return below -- the already-logged guard a
    // few lines down still wins regardless, so a completed workout can
    // never be swapped out from under its own log.
    const forceRegenerate = body.forceRegenerate === true;
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
    // The injury state belongs in the cache key -- same fix already applied
    // to generate-gym-workout (see that function's own comment on this
    // exact bug), never carried over here. Without it, a plan generated
    // before the user noted an injury replayed unchanged after they added
    // one: a "back" tag added mid-morning never invalidated a deadlift
    // already cached from a generation minutes earlier, because nothing
    // about the cache-hit path below ever re-consulted injury state. A
    // severity edit (mild -> severe) must also miss the cache -- it changes
    // which keywords get excluded, not just whether any do.
    const injurySignature =
      (safety.excludeHighImpact ? "no-impact|" : "") +
      (safety.excludedKeywords.length > 0 ? "kw:" + [...safety.excludedKeywords].sort().join(",") : "");

    // Active sport goal (Sport Goal Programs) -- fetched before the cache
    // read because its state hash joins cache identity below.
    const goalRow = await fetchActiveGoal(supabase, userId);
    // Runs BEFORE the signature/cache read so a pregnancy or severe injury
    // reported today strips the goal block today, not tomorrow.
    await applySafetyPause(supabase, goalRow, userId);
    // Phase follows elapsed time (foundation -> build -> peak) instead of
    // pinning to creation-time 'foundation'; the signature below then
    // carries the new phase and regenerates today's plan naturally.
    await maybeAdvancePhase(supabase, goalRow, date);
    const goalSignature = goalSignatureOf(goalRow);

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
    // Today's logs, read before the cache decision: a plan whose workout
    // is already logged must never be regenerated out from under the log.
    // NOT maybeSingle: multiple logs per day are supported (no
    // unique(user_id, date) on workout_log), and maybeSingle errors on 2+
    // rows -- with the error unread, `data` came back null and the lock
    // silently disengaged on exactly the days it was written for.
    // device_detected included: the old silent auto-log path (which wrote
    // one with zero user input) is gone -- HomeView's confirmDetectedWorkout
    // is the only remaining writer of this source, and it only ever runs
    // after an explicit "Yes, that was my workout" tap, so a device_detected
    // row is exactly as deliberate as any other and must lock generation too.
    const { data: existingLogs, error: logReadError } = await supabase
      .from("workout_log")
      .select("title")
      .eq("user_id", userId)
      .eq("date", date);
    if (logReadError) {
      throw new Error(`could not check today's workout log: ${logReadError.message}`);
    }
    // Goal state belongs in the cache key (BUG-37 lesson): a goal edit --
    // phase advance, pause, schedule change -- must regenerate, or the
    // cache replays a plan the new state exists to change. A null cached
    // signature is served as-is: a goal started AFTER today's plan existed
    // does NOT invalidate it, by design ("starts with tomorrow's plan").
    // A signature MISMATCH still serves the cache once the cached workout
    // is logged: the record of what the user actually did outranks any
    // goal-state change that arrived after the fact.
    const cachedGoalSignature =
      ((cached?.plan as { goal_signature?: string | null } | undefined)?.goal_signature) ?? null;
    // Unlike goal_signature/injury_signature below, a language mismatch is
    // NEVER waved through by cachedSelectionLogged, and a null (pre-existing)
    // cached language is NOT treated as compatible either -- those other
    // fields default to "don't know, trust it" because an unknown goal/
    // injury state has no clear right answer, but a plan in the wrong
    // language is unambiguously wrong, full stop, logged or not. The app's
    // own language switcher tells the user to force-quit and relaunch to
    // "finish switching" (ProfileView's profile.language.restartAlert) --
    // that promise has to hold for AI-generated content too, not just the
    // static catalog strings a relaunch already picks up. In practice this
    // only fires right after such a relaunch (the client doesn't change its
    // request language mid-session), so it doesn't fight the "don't
    // regenerate over a logged workout" protection the other two checks
    // exist for. See generate-gym-workout's equipment_signature for the same
    // fix baked directly into that cache's key instead.
    const cachedLanguage = ((cached?.plan as { language?: string | null } | undefined)?.language) ?? null;
    const cachedSelectionLogged = (existingLogs ?? []).some((log) => log.title === selection.title);
    // Deliberately stricter than the goal-signature null-passes rule above:
    // a cache row from before this column existed (cachedInjurySignature ===
    // null) only serves as-is when the user currently has NO active
    // exclusions (injurySignature === "") -- there is nothing it could have
    // gotten wrong in that case. If the user currently has an injury
    // exclusion active, an old-format row can never be verified safe and
    // regenerates, same as an explicit signature mismatch would.
    const cachedInjurySignature =
      ((cached?.plan as { injury_signature?: string | null } | undefined)?.injury_signature) ?? null;
    const injurySignatureOk = cachedSelectionLogged ||
      (cachedInjurySignature !== null ? cachedInjurySignature === injurySignature : injurySignature === "");
    if (
      cached && cached.selected_title === selection.title &&
      (cachedSelectionLogged || !forceRegenerate) &&
      (cachedGoalSignature === null || cachedGoalSignature === goalSignature || cachedSelectionLogged) &&
      cachedLanguage === languageCode &&
      injurySignatureOk
    ) {
      return jsonResponse({ date, category: cached.category, source: cached.source, ...cached.plan });
    }

    // A different selection than what's cached, but the day is already
    // logged -- refuse rather than silently swapping the plan behind an
    // already-completed workout. A log matching this selection's title
    // falls through normally (the cache-read above already served it).
    // The refusal fires when ANY of today's logs differs from this
    // selection; a day whose every log matches falls through normally.
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
    const limitCheck = await checkGenerationLimit(supabase, userId, date, subscriptionTier, "suggestion");
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

    const { data: userRow, error: userReadError } = await supabase
      .from("users")
      .select("goals, equipment, other_equipment_notes, injury_tags, injury_notes, injury_severity, experience_level, sex, date_of_birth, weight_kg, pregnancy, pregnancy_week, body_photo_emphasis_tags, workouts_per_week, diet_type, goal_pace, blockers, accomplishment_goals, desired_weight_kg, training_emphasis, known_lifts, country, city, anchor_sessions, last_period_start_date, typical_cycle_length_days")
      .eq("id", userId)
      .maybeSingle();
    // Fail loud (BUG-70): an unread error here left userRow null, silently
    // dropping ALL personalization -- injuries and pregnancy included.
    if (userReadError) {
      throw new Error(`could not read user personalization: ${userReadError.message}`);
    }
    // Kicked off here (not awaited yet) so the geocode+weather round trip
    // overlaps with everything else this handler does before candidate
    // exercises are actually filtered, below -- awaited only once
    // candidateExerciseNames exists. Real feedback: "when the user is in
    // Dubai, and the temperature ... is 42 degrees celsius, SOMA should
    // not recommend a run outside." Best-effort: resolves to null on any
    // failure (no city on file, geocoding miss, network error/timeout),
    // treated identically to "safe" by the caller below.
    const outdoorSafetyPromise = fetchOutdoorSafetyForCity(
      (userRow as UserRow | null)?.city ?? null,
      (userRow as UserRow | null)?.country ?? null,
    );

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

    // Moved up from where it used to be computed (further down, alongside
    // candidate-exercise filtering) so the finisher decision below can see
    // it too -- depends only on userRow, already fetched, so there's no
    // ordering hazard in moving it earlier.
    const freeTextEquipment = resolveFreeTextEquipment((userRow as UserRow | null)?.other_equipment_notes ?? null);
    // Deterministic finisher decision -- whether one appears at all today,
    // and whether it's the exceptional max-effort version. Never left to
    // the LLM: gated on category, readiness, injury contraindications, and
    // yesterday's logged split, all computed here before the prompt exists.
    const { excludedKeywords: finisherExcludedKeywords } = describeContraindications(
      (userRow as UserRow | null)?.injury_tags ?? [],
      ((userRow as UserRow | null)?.injury_severity ?? {}) as Record<string, InjurySeverityLevel>,
    );
    // BUG report: decideFinisher had no equipment signal at all, so a
    // "sprints on the treadmill" style finisher could never be selected
    // even for a user who owns one -- see finisherCatalog.ts's
    // selectFinisher for how this is used (full_body day + real cardio
    // equipment -> prefers the cardio/sprint_interval concept). Free text
    // is the only source specific enough to mean "the user has a
    // treadmill/bike/rower/etc" (unlocksCardio); "bike" is the one
    // structured EquipmentTag preset that's equally unambiguous -- the
    // others (gym, crossfit, ...) only make cardio-machine access
    // plausible, not confirmed, so they're deliberately left out.
    const hasCardioEquipment = freeTextEquipment.unlocksCardio ||
      ((userRow as UserRow | null)?.equipment ?? []).includes("bike");
    const finisherDecision = decideFinisher(
      category,
      resolvedBodyPart,
      isExceptionalReadiness(category, (snapshots ?? []) as SnapshotRow[]),
      finisherExcludedKeywords,
      (recentLogs ?? []) as WorkoutLogRow[],
      addDays(date, -1),
      (userRow as UserRow | null)?.training_emphasis ?? null,
      hasCardioEquipment,
    );

    // Same closed-vocabulary keyword exclusions used to keep the finisher
    // decision safe also keep the candidate exercise-name list safe --
    // pregnancy adds its own trimester-scaled exclusions on top.
    const pregnancyExcludedKeywords = (userRow as UserRow | null)?.pregnancy
      ? describePregnancyGuidance((userRow as UserRow | null)?.pregnancy_week ?? null).excludedKeywords
      : [];
    const goalExcludedKeywords = [...finisherExcludedKeywords, ...pregnancyExcludedKeywords];

    // Deterministic goal-block decision (mirrors decideFinisher): whether
    // goal work appears today, which concept, and its dose -- the LLM only
    // words it. Custom (coach's task) blocks stay verbatim, injected below.
    let goalDecision: GoalWorkBlock | null = null;
    let goalExerciseIds: string[] = [];
    // Advisory-only forward-looking hint (Phase 2: see
    // docs/coaching-personalization-plan.md) -- null whenever there's no
    // active goal, or its schedule isn't knowable this far ahead.
    let upcomingGoalLine: string | null = null;
    if (goalRow) {
      // Independent fetches, so they run in parallel; the safety pause
      // above already settled the goal state they all read against.
      const fromCatalog = goalRow.kind === "preset" && goalRow.goal_id ? goalRow.goal_id : null;
      const [sportVisibility, concepts, recentGoalBlocks, exerciseIds] = await Promise.all([
        isGoalSportVisible(supabase, goalRow, userId),
        fromCatalog ? fetchGoalConcepts(supabase, fromCatalog) : Promise.resolve([]),
        fetchRecentGoalBlocks(supabase, userId, date),
        fromCatalog ? fetchGoalExerciseIds(supabase, fromCatalog) : Promise.resolve([]),
      ]);
      goalExerciseIds = exerciseIds;
      const goalState: GoalState = {
        id: goalRow.id,
        kind: goalRow.kind === "custom" ? "custom" : "preset",
        targetKind: (goalRow.target_kind ?? "metric") as "metric" | "milestone" | "qualitative" | "commitment",
        phase: goalRow.phase ?? null,
        paused: goalRow.status === "paused",
        sportVisible: sportVisibility.visible,
        // deno-lint-ignore no-explicit-any
        scheduleRule: (goalRow.schedule_rule ?? null) as any,
        scheduleDays: goalRow.schedule_days ?? null,
        courtDays: goalRow.court_days ?? null,
        workoutText: goalRow.workout_text ?? null,
        coachName: goalRow.coach_name ?? null,
        frequencyPerWeek: goalRow.frequency_per_week ?? null,
      };
      goalDecision = decideGoalWork({
        category,
        date,
        goal: goalState,
        concepts,
        excludedKeywords: goalExcludedKeywords,
        recentGoalBlocks,
      });
      upcomingGoalLine = describeUpcomingGoalWork({
        goal: goalState,
        date,
        recentGoalBlocks,
        todaysDecision: goalDecision,
        sportGoalName: sportVisibility.name,
      });
      const profilePerWeek = Number.parseInt((userRow as UserRow | null)?.workouts_per_week ?? "", 10);
      await maybeUpdateEtaSlip(supabase, goalRow, userId, date, Number.isFinite(profilePerWeek) ? profilePerWeek : null);
    }

    // Phase 4 (docs/coaching-personalization-plan.md): purely advisory,
    // same "never overrides safety/category" framing as upcomingGoalLine --
    // independent of the goal-work machinery above (no user_goal row
    // needed), so it's computed here rather than inside that `if (goalRow)`
    // block.
    const anchorSessionLine = describeAnchorSessions((userRow as UserRow | null)?.anchor_sessions ?? [], date);

    // Phase 5 (docs/coaching-personalization-plan.md): null whenever the
    // user hasn't opted in (no last_period_start_date) or the projection
    // is too stale to trust -- describeSexAwareConsiderations treats null
    // identically to "not opted in" either way, same fallback line.
    const cyclePhase = deriveCyclePhase(
      (userRow as UserRow | null)?.last_period_start_date ?? null,
      (userRow as UserRow | null)?.typical_cycle_length_days ?? null,
      date,
    );

    // Same fallback formula buildPrompt uses internally for its own copy
    // of this (loadGuidance's prompt text) -- needed again out here so
    // the weight-ceiling retry below checks the model's output against
    // the EXACT SAME ceiling the prompt just told it about.
    const experience = (userRow as UserRow | null)?.experience_level ?? "moderate";
    const prompt = buildPrompt(
      category,
      resolvedSelection,
      substituted,
      finisherDecision,
      goalDecision,
      userRow as UserRow | null,
      (snapshots ?? []) as SnapshotRow[],
      (recentLogs ?? []) as WorkoutLogRow[],
      notes,
      upcomingGoalLine,
      anchorSessionLine,
      cyclePhase,
      language,
    );

    // Goal-mapped exercise ids join the closed vocabulary inside, under
    // the SAME equipment/level filters and BEFORE the exclusion drop --
    // a goal never smuggles in gear the user lacks or an unsafe name.
    //
    // Free-text equipment (BUG report: "dumbbells, a workout bench, a
    // yoga mat and a treadmill" typed in onboarding's "what else do you
    // have access to?" field was captured and saved, but never read by
    // any generation path at all) -- now parsed and unioned into the
    // structured EquipmentTag resolution, and specifically unlocks a
    // small cardio slice (see WARMUP_CARDIO_LIMIT) so warm-up can
    // actually name a real treadmill/bike/etc item when the user has one.
    // (freeTextEquipment itself is now computed earlier, alongside the
    // finisher decision above, which also needs it -- kept here only as
    // the point where it's actually consumed for candidate filtering.)
    // Same suggestion title picked in the last 2 days -- BUG report: the
    // same workout, day after day (now also covers cool_down -- BUG
    // report: cool_down never varies). Soft-excluded, see
    // MIN_CANDIDATES_AFTER_FRESHNESS_EXCLUSION.
    const recentExerciseNames = await fetchRecentExerciseNames(supabase, userId, selection.title, date);
    // Exact single-day comparison for the deterministic cool_down-repeat
    // check below -- see fetchYesterdaysCoolDownNames's own doc comment
    // for why this is separate from recentExerciseNames above.
    const yesterdaysCoolDownNames = await fetchYesterdaysCoolDownNames(supabase, userId, selection.title, date);
    let candidateExerciseNames = await fetchCandidateExerciseNames(
      supabase,
      resolvedBodyPart,
      (userRow as UserRow | null)?.equipment ?? [],
      goalExcludedKeywords,
      (userRow as UserRow | null)?.experience_level ?? null,
      goalDecision?.kind === "preset" ? goalExerciseIds : [],
      freeTextEquipment.libraryEquipment,
      freeTextEquipment.unlocksCardio,
      recentExerciseNames,
      freeTextEquipment.cardioLibraryEquipment,
    );
    // Post-filter rather than folded into fetchCandidateExerciseNames's own
    // excludedKeywords param -- that mechanism is plain substring matching
    // with no equipment-awareness, which would also drop safe indoor
    // equivalents (see weatherSafety.ts's isOutdoorCardioExerciseName doc
    // comment for why). Same "never shrink to a degenerate pool" guard as
    // the freshness exclusion in exerciseLibraryMatch.ts.
    const outdoorSafety = await outdoorSafetyPromise;
    let weatherUnsafeNote: string | null = null;
    if (outdoorSafety && !outdoorSafety.safe) {
      const withoutOutdoorCardio = candidateExerciseNames.filter((name) => !isOutdoorCardioExerciseName(name));
      if (withoutOutdoorCardio.length >= MIN_CANDIDATES_AFTER_WEATHER_EXCLUSION) {
        candidateExerciseNames = withoutOutdoorCardio;
        weatherUnsafeNote = outdoorSafety.reason ?? null;
      }
    }
    const workoutSchema = buildWorkoutSchema(candidateExerciseNames);

    // Every callClaude result below is immediately reconciled against its
    // own deterministic per-exercise time estimate (BUG report: a plan
    // self-reported "~47 min total" that actually took 30-35 min -- see
    // durationValidation.ts) before anything downstream reads its
    // duration_minutes or computes a total from it.
    let plan = reconcileExerciseDurations(await callClaude(prompt, workoutSchema));
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
      const retryPlan = reconcileExerciseDurations(await callClaude(gapPrompt, workoutSchema));
      const retryDuration = computeTotalDuration(retryPlan);
      const targetMid = (targetDurationRange.min + targetDurationRange.max) / 2;
      if (Math.abs(retryDuration - targetMid) < Math.abs(actualDurationMinutes - targetMid)) {
        plan = retryPlan;
        actualDurationMinutes = retryDuration;
      }
    }

    // One bounded retry when the same specific exercise was named more
    // than once across the session (BUG report: "Barbell Squat" 4 times
    // in one plan) -- the prompt already instructs against this, but a
    // prompt instruction is a request, not a guarantee, so this is the
    // deterministic backstop. If the retry doesn't fully fix it, keep
    // whichever attempt had fewer duplicates rather than silently
    // pretending the first (possibly worse) one was fine.
    const duplicateNames = findDuplicateExerciseNames(plan);
    if (duplicateNames.length > 0) {
      const dedupPrompt = `${prompt}\n\nYour previous attempt used the exact same exercise more than once in this session: ${duplicateNames.join(", ")}. Every named exercise must appear AT MOST ONCE across the whole session (warm_up + every block + cool_down combined) -- replace each repeat with a different candidate exercise that targets a different specific muscle or movement pattern within the same body part, exactly as instructed above.`;
      const dedupRetryPlan = reconcileExerciseDurations(await callClaude(dedupPrompt, workoutSchema));
      const retryDuplicates = findDuplicateExerciseNames(dedupRetryPlan);
      if (retryDuplicates.length < duplicateNames.length) {
        plan = dedupRetryPlan;
        actualDurationMinutes = computeTotalDuration(plan);
      }
      // Keep whichever attempt had fewer duplicates rather than silently
      // pretending the first (possibly worse) one was fine -- log loud
      // instead of failing the whole request, since an imperfect plan
      // still beats no plan at all.
      const remainingDuplicates = retryDuplicates.length < duplicateNames.length ? retryDuplicates : duplicateNames;
      if (remainingDuplicates.length > 0) {
        console.warn(`generate-workout-plan: plan still repeats exercises after retry: ${remainingDuplicates.join(", ")}`);
      }
    }

    // One bounded retry when cool_down is the EXACT same set of exercises
    // as yesterday's for this same suggestion title (BUG report: cool_down
    // never varies) -- the prompt already instructs body-part-specific
    // cooldowns, and fetchRecentExerciseNames above now soft-excludes
    // cool_down names from the candidate pool too, but neither is a
    // guarantee, so this is the deterministic backstop, same retry
    // mechanism as the duplicate-name check right above.
    if (coolDownRepeatsYesterday(plan, yesterdaysCoolDownNames)) {
      const coolDownPrompt = `${prompt}\n\nYour previous attempt used the EXACT SAME cool_down as yesterday's "${selection.title}" session: ${(yesterdaysCoolDownNames ?? []).join(", ")}. Today's cool_down must be different -- pick different stretches/mobility work (still appropriate to today's body part and intensity), not the identical set again.`;
      const coolDownRetryPlan = reconcileExerciseDurations(await callClaude(coolDownPrompt, workoutSchema));
      if (!coolDownRepeatsYesterday(coolDownRetryPlan, yesterdaysCoolDownNames)) {
        plan = coolDownRetryPlan;
        actualDurationMinutes = computeTotalDuration(plan);
      } else {
        // Keep the (still-repeating) retry's other improvements are moot
        // here -- there's nothing "less wrong" about a second exact repeat,
        // so just keep the original and log loud, same posture as the
        // duplicate-name check when a retry doesn't fully land.
        console.warn(`generate-workout-plan: cool_down still matches yesterday's exactly after retry (title="${selection.title}")`);
      }
    }

    // One bounded retry when decideFinisher says a finisher block should be
    // present but the generated plan doesn't have one (BUG report:
    // "finisher rarely shows"). A real query against ai_workout_plan ruled
    // out the eligibility gate as the cause -- it's already permissive
    // (include=true for every moderate/push_hard plan); the gap is prompt
    // adherence, same "instruction is a request, not a guarantee" posture
    // as every other check in this section.
    if (finisherMissing(plan, finisherDecision.include)) {
      const finisherPrompt = `${prompt}\n\nYour previous attempt did not include a finisher block, even though one is required today (see the finisher instructions above). Add exactly one finisher as the LAST block, named "Block N - Optional Finisher" (is_finisher: true, every other block is_finisher: false), following the finisher guidance already given above.`;
      const finisherRetryPlan = reconcileExerciseDurations(await callClaude(finisherPrompt, workoutSchema));
      if (!finisherMissing(finisherRetryPlan, finisherDecision.include)) {
        plan = finisherRetryPlan;
        actualDurationMinutes = computeTotalDuration(plan);
      } else {
        console.warn(`generate-workout-plan: plan still missing its required finisher block after retry (title="${selection.title}")`);
      }
    }

    // One bounded retry when a two-dumbbell squat/hinge exercise's stated
    // weight_guidance exceeds the derated per-dumbbell ceiling (BUG
    // report: a 168cm/60kg woman prescribed 16-24kg PER DUMBBELL, ~double
    // a sane number) -- buildLoadGuidance's prompt already states this
    // ceiling explicitly (see loadGuidance.ts), but same "instruction is
    // a request, not a guarantee" posture as the duplicate-name check
    // right above, reusing that exact retry mechanism rather than a new
    // one.
    const weightViolations = findWeightCeilingViolations(plan, userRow?.weight_kg ?? null, experience, userRow?.known_lifts ?? null);
    if (weightViolations.length > 0) {
      const violationList = weightViolations.map((v) => `${v.exerciseName} (stated ${v.statedPerImplementKg}kg each, ceiling is ${v.ceilingPerImplementKg.toFixed(0)}kg each)`).join("; ");
      const weightPrompt = `${prompt}\n\nYour previous attempt prescribed too much weight PER DUMBBELL on a two-dumbbell exercise -- this is the barbell-equivalent TOTAL used as if it were a single dumbbell's weight, which is roughly double the safe amount: ${violationList}. Fix these specific exercises using the two-dumbbell guidance above -- state weight_guidance as "2xNkg dumbbells" with N at or under the ceiling given for that exercise, exactly as instructed above.`;
      const weightRetryPlan = reconcileExerciseDurations(await callClaude(weightPrompt, workoutSchema));
      const retryViolations = findWeightCeilingViolations(weightRetryPlan, userRow?.weight_kg ?? null, experience, userRow?.known_lifts ?? null);
      if (retryViolations.length < weightViolations.length) {
        plan = weightRetryPlan;
        actualDurationMinutes = computeTotalDuration(plan);
      }
      // Keep whichever attempt had fewer violations rather than silently
      // pretending the first (possibly worse) one was fine -- log loud
      // instead of failing the whole request, an imperfect plan still
      // beats no plan at all.
      const remainingViolations = retryViolations.length < weightViolations.length ? retryViolations : weightViolations;
      if (remainingViolations.length > 0) {
        console.warn(`generate-workout-plan: plan still exceeds the two-dumbbell weight ceiling after retry: ${remainingViolations.map((v) => v.exerciseName).join(", ")}`);
      }
    }

    // Custom goal: the coach's session is prepended server-side, VERBATIM
    // (workout_text travels untouched in instructions) -- the model never
    // sees it, so it can never rewrite it.
    if (goalDecision?.kind === "custom") {
      plan = { ...plan, blocks: [buildCoachBlock(goalDecision), ...plan.blocks] };
      actualDurationMinutes = computeTotalDuration(plan);
    }

    const planWithDuration = {
      ...plan,
      actual_duration_minutes: actualDurationMinutes,
      substituted_body_part: substituted ? resolvedBodyPart : null,
      // Cache identity (see the cache read above) + tomorrow's goal-block
      // history (hangs-never-consecutive-days rule in goalWork.ts).
      goal_signature: goalSignature,
      language: languageCode,
      // Cache identity -- see the injurySignature comment near the top of
      // this handler for why this exists at all.
      injury_signature: injurySignature,
      goal_block: goalBlockMeta(goalDecision),
      // Drives the "Optional finisher -- you're well recovered today"
      // badge client-side (AIWorkoutPlanSections.swift) -- only ever true
      // alongside a block whose is_finisher is also true.
      exceptional_finisher: finisherDecision.exceptional,
      // Non-null only when outdoor cardio was actually excluded from
      // today's candidate pool for weather -- surfaced so the client can
      // say why, same "say it out loud" pattern as every other cap's note.
      // Cached alongside the plan (not just in the fresh-generation
      // response) so a same-day cache hit still shows it.
      weather_note: weatherUnsafeNote,
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
  goalDecision: GoalWorkBlock | null,
  userRow: UserRow | null,
  snapshots: SnapshotRow[],
  recentLogs: WorkoutLogRow[],
  notes: string | undefined,
  upcomingGoalLine: string | null,
  anchorSessionLine: string | null,
  cyclePhase: CyclePhaseResult | null,
  language: string,
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
  // Same source, coarser reading (see UserRow.training_emphasis) -- nudges
  // exercise SELECTION/composition (e.g. more conditioning work on a cut,
  // more heavy compound work on a bulk), same secondary-signal framing as
  // bodyPhotoEmphasisLine above. The finisher's own modality is already
  // handled deterministically before this prompt exists (see
  // decideFinisher's trainingEmphasis param) -- this line is for the rest
  // of the session's composition, not a duplicate instruction for that.
  const trainingEmphasisLine = userRow?.training_emphasis
    ? `\nThe same photo comparison also suggests an overall training direction of "${userRow.training_emphasis}" (cut = lean out/reduce fat, bulk = add size, recomp = both/composition change, maintain = little change wanted). Let this gently inform today's exercise mix alongside the goals and emphasis above -- e.g. a "cut" direction favors a bit more conditioning/metabolic work where the day's structure allows it; a "bulk" direction favors sticking with heavier compound work. Never let this override the day's intensity category, injury exclusions, or equipment above.`
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
  const loadGuidance = buildLoadGuidance(userRow?.weight_kg ?? null, experience, userRow?.known_lifts ?? null);
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
  const sexAwareLine = describeSexAwareConsiderations(userRow?.sex ?? null, category, cyclePhase);

  // Phase 3 (docs/coaching-personalization-plan.md): deterministic goal-
  // specific rep-range + recurring-foundation-movement guidance -- decided
  // entirely from the user's own goals/body_photo_emphasis_tags/
  // training_emphasis (same precedence those signals already carry
  // elsewhere in this prompt), never left to the LLM. Null whenever none
  // of the three give a recognized shaping goal, or today's category/body
  // part doesn't call for one -- see decideShapingGoalGuidance's own
  // "omit rather than fabricate" doc comment.
  const shapingGoalGuidance = decideShapingGoalGuidance(
    userRow?.goals ?? null,
    userRow?.body_photo_emphasis_tags ?? null,
    userRow?.training_emphasis ?? null,
    selection.bodyPart,
    category,
  );
  const shapingGoalLine = shapingGoalGuidance
    ? `\nGoal-specific rep-range guidance for today's working sets (${shapingGoalGuidance.repRangeRationale}): aim for ${shapingGoalGuidance.repRangeLabel} reps on the main movements. Build today's session around these recurring foundation movement patterns for this goal -- reuse the SAME patterns session to session (progressing load/reps over time per the recent-workout history below) rather than inventing new ones each time: ${
      shapingGoalGuidance.foundationMovements.join("; ")
    }.${shapingGoalGuidance.hardConstraint ? ` ${shapingGoalGuidance.hardConstraint}` : ""}`
    : "";

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

  // Whether goal work appears, which concept, and its dose were already
  // decided deterministically (decideGoalWork) -- the model only words it.
  const sexAwareGoalDoseLine = describeSexAwareGoalDoseConsideration(userRow?.sex ?? null);
  const goalDose = goalDecision !== null && goalDecision.kind === "preset"
    ? `${goalDecision.concept.durationMinutesRange[0]}-${goalDecision.concept.durationMinutesRange[1]} min${goalDecision.concept.rpeTarget ? ` at ${goalDecision.concept.rpeTarget}` : ""}${goalDecision.concept.doseNotes ? `. Hard dose caps (never exceed): ${goalDecision.concept.doseNotes}` : ""}${sexAwareGoalDoseLine ? ` ${sexAwareGoalDoseLine}` : ""}`
    : "";
  const goalInstruction = goalDecision === null
    ? ""
    : goalDecision.kind === "custom"
    ? `\nThe user also has a coach-assigned session scheduled today. It is inserted into the plan separately, exactly as their coach wrote it -- do NOT restate, rewrite, or duplicate the coach's content anywhere in your blocks. Build the day's blocks as complementary work that leaves the user capacity for that coach session (roughly 15 min of it).`
    : goalDecision.optional
    ? `\nThe user's active sport goal adds an OPTIONAL rest-day mobility dose. Include it as the FIRST block, named "Goal Block (optional) - ${goalDecision.concept.focus}", ${goalDose}, built around this concept -- ${goalDecision.concept.description} State plainly in its instructions that it is optional and skippable today.`
    : `\nThe user's active sport goal opens today's session. Include the goal work as the FIRST block (before every other non-warm-up block -- goal quality demands freshness), named "Goal Block - ${goalDecision.concept.focus}", ${goalDose}, built around this concept -- ${goalDecision.concept.description} Then continue with the day's normal blocks; the day's volume caps and intensity rules above still govern the whole session.`;

  const substitutionLine = wasSubstituted
    ? `This target was already redirected server-side to a safe body part given the user's noted injury (their original selection conflicted with it) -- build the plan around "${selection.bodyPart}" as given, do not try to reintroduce the original focus area.`
    : `Build today's plan as a detailed breakdown of exactly this workout -- do not substitute a different type of workout or body part focus. If equipment or injuries below force a change to a specific exercise, keep it a close, safe variant of the same movement pattern rather than switching focus areas.`;

  // Verified real gap (2026-08-15): the schema's blocks array had no
  // minItems, so a technically-valid response with blocks: [] (nothing
  // but warm_up/cool_down) was legal -- exactly the "sparse/empty-feeling
  // rest day" risk. minItems: 1 (workoutSchema.ts's buildWorkoutSchema) is
  // the hard guarantee; this is the explicit instruction backing it up,
  // since a schema minimum alone doesn't tell the model WHAT to put there.
  const restLightContentLine = category === "rest" || category === "light"
    ? ` Low intensity does NOT mean low content -- even on a "${category}" day, blocks must still contain at least one real block of genuine, well-explained content (gentle mobility work, an easy walk, light stretching), never an empty or near-empty plan just because today isn't a hard training day.`
    : "";

  return `You are a certified strength & conditioning coach writing a single day's workout plan for a fitness app user.

The user has already chosen today's workout from the app's suggestion list: "${selection.title}" (target: ${selection.bodyPart}). ${substitutionLine}

Today's training intensity (already decided by the app's recovery-based rules -- do not override it): ${category}.
Today's actual health data driving that intensity: ${healthLines}
User's goals: ${goals}.${bodyPhotoEmphasisLine}${trainingEmphasisLine}
Training experience: ${experience}. ${experienceGuidance}
Available equipment: ${equipment}.
Noted injuries: ${injuries}.${injuryNotes}
${sexLine}${ageLine ? `\n${ageLine}` : ""}${pregnancyLine}
${loadGuidance}
${volumeGuidanceLine ? `\n${volumeGuidanceLine}` : ""}
${rirGuidanceLine ? `\n${rirGuidanceLine}` : ""}
${shapingGoalLine}
${sexAwareLine ? `\n${sexAwareLine}` : ""}
${workoutsPerWeekLine ? `\n${workoutsPerWeekLine}` : ""}${dietLine ? `\n${dietLine}` : ""}${goalPaceLine ? `\n${goalPaceLine}` : ""}${blockersLine ? `\n${blockersLine}` : ""}${accomplishmentLine ? `\n${accomplishmentLine}` : ""}
${upcomingGoalLine ? `\n${upcomingGoalLine}` : ""}
${anchorSessionLine ? `\n${anchorSessionLine}` : ""}

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
- warm_up: 2-3 items that specifically prepare the body for THIS workout and adjust to today's health data above (e.g. lighter/shorter if recovery or sleep was poor) -- concrete named items like "5 min incline treadmill walk", "2x10 arm circles", "shoulder rolls", not a generic "warm up" placeholder. If the user has cardio equipment (treadmill, bike, etc. -- see equipment above) and today's intensity allows it, a brief cardio warm-up item is a great choice, not just static stretches.
- blocks: an ordered array of named blocks (e.g. "Block 1", "Superset A") that together make up "${selection.title}" for today's "${category}" intensity, following the experience guidance above. Each block has its own rounds (1 for a straight-through block, 2+ for a circuit/superset), a rest_between_rounds, and is_finisher (true only for the optional finisher block described next, false for every other block). VARIETY IS REQUIRED: use each specific named exercise AT MOST ONCE across the ENTIRE session (warm_up + every block + cool_down combined) -- never repeat the same exercise in multiple blocks or rounds of a superset. Like a real strength coach programming a session, deliberately spread the work across different specific muscles within the target body part (e.g. a lower-body day should mix quad-, hamstring-, glute-, and calf-dominant movements, not four variations of the same squat pattern) and different movement patterns (push/pull/hinge/squat/carry/isolation as relevant), not near-duplicates of one exercise.${restLightContentLine} ${finisherInstruction}${goalInstruction}
- cool_down: 2-3 items of static stretching/breathing targeting the muscles just worked.

For every exercise in warm_up, every block's exercises, and cool_down, give: name, sets (integer -- use 1 for anything that's just a held stretch or a single timed activity, not part of a multi-round block), reps (a string, e.g. "8-10", "30 sec", "5 min"), weight_guidance (concrete and actionable -- e.g. "start light, 2x8kg dumbbells" or "bodyweight" or "N/A" for stretches -- not vague advice), intensity (e.g. "RPE 6/10" or "easy/moderate/hard"), duration_minutes for that item including rest, rest_seconds (integer, real prescriptive rest AFTER this exercise before the next -- roughly 0 for a stretch/warm-up cardio item, 30-60s for lighter accessory/circuit work, 60-90s for standard working sets, 120-180s for heavy compound lifts near the top of the day's intensity; scale it with today's intensity and the user's experience level like a real coach would, don't default to the same number every time), and instructions -- 2-3 plain, easy-to-follow sentences giving EXACT form/technique PLUS one concrete, specific coaching cue for this exact movement (e.g. "brace your core like you're about to be punched in the stomach" or "drive through your mid-foot, not your toes" or "keep your ribs stacked over your hips throughout"). A generic filler cue that could apply to any exercise (e.g. "maintain good form", "focus on technique", "go at your own pace") is NOT acceptable -- the cue must be specific enough that it wouldn't make sense pasted onto a different exercise. Also give a one-line "focus" summarizing today's session.

Write every piece of narrative text in ${language} -- reps, weight_guidance, intensity, instructions, block names, rest_between_rounds, and the closing "focus" line. Never translate an exercise's "name" -- copy it exactly as given.`;
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
    // Rounded to 1dp, matching the app's own sleep-hours display
    // convention (HomeView's sleep widget, "%.1f") -- wearable sleep
    // totals arrive as raw seconds/3600 and carry long binary-float tails
    // (9.888888333...), which the LLM would otherwise happily echo
    // verbatim into generated coaching text ("since you slept
    // 9.888888333333h..."). Same bug class already fixed once for the
    // deterministic reasoning text (reasoningMessage.ts's roundSleepHours)
    // but missed here, a sibling readiness-summary builder.
    if (s.sleep_hours !== null) bits.push(`slept ${Math.round(s.sleep_hours * 10) / 10}h`);
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

// --- Sport Goal Programs plumbing (see goalWork.ts for the decision) ---

interface UserGoalRow {
  id: string;
  goal_id: string | null;
  kind: string;
  target_kind: string | null;
  status: string;
  phase: string | null;
  schedule_rule: string | null;
  schedule_days: number[] | null;
  court_days: number[] | null;
  workout_text: string | null;
  coach_name: string | null;
  eta_start: string | null;
  eta_end: string | null;
  frequency_per_week: number | null;
  eta_slip_days: number | null;
  created_at: string | null;
  pause_reason: string | null;
  safety_ack: { warned?: { keyword?: string }[] } | null;
}

/// Non-fatal on error: the daily plan must keep generating exactly as it
/// does without the feature (goal tables may trail this deploy).
// deno-lint-ignore no-explicit-any
async function fetchActiveGoal(supabase: any, userId: string): Promise<UserGoalRow | null> {
  const { data, error } = await supabase
    .from("user_goal")
    .select("id, goal_id, kind, target_kind, status, phase, schedule_rule, schedule_days, court_days, workout_text, coach_name, eta_start, eta_end, frequency_per_week, eta_slip_days, created_at, pause_reason, safety_ack")
    .eq("user_id", userId)
    .eq("status", "active")
    .maybeSingle();
  if (error) {
    console.error(`could not read user_goal (generating goal-free): ${error.message}`);
    return null;
  }
  return (data as UserGoalRow | null) ?? null;
}

/// Spec decision 8: a pregnancy or severe injury that hard-conflicts with
/// the active goal auto-pauses it (pause_reason='safety') instead of
/// serving hollowed-out filler. Mutates goalRow in place on pause so the
/// cache signature and decideGoalWork see the paused state this request.
/// Non-fatal on error: worst case the goal stays active one more day and
/// content filtering still governs every exercise.
// deno-lint-ignore no-explicit-any
async function applySafetyPause(supabase: any, goalRow: UserGoalRow | null, userId: string): Promise<void> {
  if (!goalRow || goalRow.status !== "active") return;
  try {
    const { data: safetyRow, error } = await supabase
      .from("users")
      .select("pregnancy, pregnancy_week, injury_tags, injury_severity")
      .eq("id", userId)
      .maybeSingle();
    if (error) {
      console.error(`safety-pause user read failed: ${error.message}`);
      return;
    }
    const pregnant = safetyRow?.pregnancy === true;
    const severity = (safetyRow?.injury_severity ?? {}) as Record<string, InjurySeverityLevel>;
    const hasSevereInjury = Object.values(severity).includes("severe" as InjurySeverityLevel);
    if (!pregnant && !hasSevereInjury) return;

    let pregnancySafe: boolean | null = null;
    if (pregnant && goalRow.kind === "preset" && goalRow.goal_id) {
      const { data: catalogRow } = await supabase
        .from("sport_goals")
        .select("pregnancy_safe")
        .eq("id", goalRow.goal_id)
        .maybeSingle();
      pregnancySafe = typeof catalogRow?.pregnancy_safe === "boolean" ? catalogRow.pregnancy_safe : null;
    }
    const concepts = hasSevereInjury && goalRow.kind === "preset" && goalRow.goal_id
      ? await fetchGoalConcepts(supabase, goalRow.goal_id)
      : [];
    const injuryKeywords = hasSevereInjury
      ? describeContraindications(
        (safetyRow?.injury_tags as string[] | null) ?? [],
        severity,
      ).excludedKeywords
      : [];
    const decision = decideSafetyPause({
      goalKind: goalRow.kind === "custom" ? "custom" : "preset",
      pregnancySafe,
      pregnant,
      hasSevereInjury,
      ackedKeywords: (goalRow.safety_ack?.warned ?? [])
        .map((w) => w.keyword)
        .filter((k): k is string => typeof k === "string"),
      workoutText: goalRow.workout_text,
      pregnancyKeywords: pregnant
        ? describePregnancyGuidance((safetyRow?.pregnancy_week as number | null) ?? null).excludedKeywords
        : [],
      injuryKeywords,
      concepts,
    });
    if (!decision) return;

    const { error: pauseError } = await supabase
      .from("user_goal")
      .update({ status: "paused", pause_reason: "safety" })
      .eq("id", goalRow.id)
      .eq("status", "active");
    if (pauseError) {
      console.error(`safety-pause write failed: ${pauseError.message}`);
      return;
    }
    goalRow.status = "paused";
    goalRow.pause_reason = "safety";
    console.log(`goal ${goalRow.id} safety-paused (${decision.reason})`);
  } catch (e) {
    console.error(`safety-pause failed: ${e instanceof Error ? e.message : String(e)}`);
  }
}

/// Advances an active preset goal's phase from elapsed time within its
/// horizon (created_at -> eta_end), persisting and mutating goalRow in
/// place so the cache signature carries it. Non-fatal on any error.
// deno-lint-ignore no-explicit-any
async function maybeAdvancePhase(supabase: any, goalRow: UserGoalRow | null, date: string): Promise<void> {
  if (!goalRow || goalRow.kind !== "preset" || goalRow.status !== "active") return;
  const blockStart = goalRow.created_at?.slice(0, 10) ?? null;
  if (!blockStart || !goalRow.eta_end) return;
  try {
    const elapsedWeeks = Math.floor(daysBetween(blockStart, date) / 7);
    const horizonWeeksHigh = Math.max(1, Math.round(daysBetween(blockStart, goalRow.eta_end) / 7));
    const phase = derivePhase(elapsedWeeks, horizonWeeksHigh);
    if (phase === goalRow.phase) return;
    const { error } = await supabase.from("user_goal").update({ phase }).eq("id", goalRow.id);
    if (error) console.error(`phase advance write failed: ${error.message}`);
    // Today's decision/signature use the true phase even if the write
    // failed -- the next request simply retries the persist.
    goalRow.phase = phase;
  } catch (e) {
    console.error(`phase advance failed: ${e instanceof Error ? e.message : String(e)}`);
  }
}

function daysBetween(fromDate: string, toDate: string): number {
  const from = new Date(`${fromDate}T00:00:00.000Z`).getTime();
  const to = new Date(`${toDate}T00:00:00.000Z`).getTime();
  return Math.max(0, Math.floor((to - from) / 86400000));
}

/// Recomputes the visible ETA slip for an active preset goal and persists it
/// when it changed. Non-fatal on any error: the slip is display data.
// deno-lint-ignore no-explicit-any
async function maybeUpdateEtaSlip(
  supabase: any,
  goalRow: UserGoalRow,
  userId: string,
  date: string,
  profileSessionsPerWeek: number | null,
): Promise<void> {
  // eta_start is the re-test window; the block itself starts at creation.
  const blockStart = goalRow.created_at?.slice(0, 10) ?? null;
  if (goalRow.kind !== "preset" || goalRow.status !== "active" || !blockStart || !goalRow.eta_start) return;
  try {
    const [planRows, logRows, lowDays] = await Promise.all([
      supabase
        .from("ai_workout_plan")
        .select("date, plan")
        .eq("user_id", userId)
        .gte("date", blockStart)
        .lte("date", date),
      supabase
        .from("workout_log")
        .select("date")
        .eq("user_id", userId)
        .gte("date", blockStart)
        .lte("date", date),
      supabase
        .from("daily_recommendation")
        .select("id", { count: "exact", head: true })
        .eq("user_id", userId)
        .in("category", ["rest", "light"])
        .gte("date", blockStart)
        .lte("date", date),
    ]);
    if (planRows.error || logRows.error || lowDays.error) {
      console.error(`eta slip reads failed: ${planRows.error?.message ?? logRows.error?.message ?? lowDays.error?.message}`);
      return;
    }
    // A goal session = a day whose plan actually carried a goal block
    // (plan.goal_block, written by goalBlockMeta) AND a logged workout.
    const goalBlockDates = ((planRows.data ?? []) as { date: string; plan: { goal_block?: unknown } | null }[])
      .filter((r) => r.plan?.goal_block != null)
      .map((r) => r.date);
    const plannedPerWeek = goalRow.frequency_per_week ?? profileSessionsPerWeek ?? 3;
    const { completedSessions, lowReadinessDays } = deriveEtaInputs({
      plannedPerWeek,
      elapsedDays: daysBetween(blockStart, date),
      goalBlockDates,
      logDates: ((logRows.data ?? []) as { date: string }[]).map((r) => r.date),
      restLightCount: lowDays.count ?? 0,
    });
    const shift = computeEtaShift({
      goalKind: "preset",
      windowStart: blockStart,
      date,
      plannedSessionsPerWeek: plannedPerWeek,
      completedSessions,
      lowReadinessDays,
    });
    const nextDays = shift?.shiftDays ?? null;
    if (nextDays === (goalRow.eta_slip_days ?? null)) return;
    const { error } = await supabase
      .from("user_goal")
      .update({ eta_slip_days: nextDays, eta_slip_reason: shift?.reason ?? null })
      .eq("id", goalRow.id);
    if (error) console.error(`eta slip write failed: ${error.message}`);
  } catch (e) {
    console.error(`eta slip recompute failed: ${e instanceof Error ? e.message : String(e)}`);
  }
}

/// Cache-identity hash of the goal state (id, phase, paused, schedule) --
/// the BUG-37 lesson applied here. Null when no goal is active.
function goalSignatureOf(goalRow: UserGoalRow | null): string | null {
  if (!goalRow) return null;
  return [
    goalRow.id,
    goalRow.phase ?? "",
    goalRow.status === "paused" ? "paused" : "active",
    goalRow.schedule_rule ?? "",
    (goalRow.schedule_days ?? []).join(","),
    (goalRow.court_days ?? []).join(","),
  ].join("|");
}

/// Per-sport server gate (spec, gating 3): live for everyone, internal for
/// testers, beta for opt-ins (and testers) -- the same rule as the
/// sport_status_visible() RLS helper. Fails closed on any unknown state.
/// Visibility gate, PLUS (new, Phase 2) the sport_goal's own catalog name --
/// piggybacked onto this same existing round trip rather than adding a
/// second query just to label describeUpcomingGoalWork's advisory line.
/// `name` is null for a custom goal (no catalog row to name) or on any
/// read failure; callers must treat that as "no human label available",
/// never fabricate one.
async function isGoalSportVisible(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  goalRow: UserGoalRow,
  userId: string,
): Promise<{ visible: boolean; name: string | null }> {
  if (goalRow.kind === "custom" || !goalRow.goal_id) return { visible: true, name: null };
  const { data, error } = await supabase
    .from("sport_goals")
    .select("id, name, sports(status)")
    .eq("id", goalRow.goal_id)
    .maybeSingle();
  if (error || !data) {
    if (error) console.error(`could not read sport_goals for gating: ${error.message}`);
    return { visible: false, name: null };
  }
  const name = ((data as { name?: string }).name as string | undefined) ?? null;
  // deno-lint-ignore no-explicit-any
  const status = ((data as any).sports?.status as string | undefined) ?? null;
  if (status === "live") return { visible: true, name };
  if (status !== "internal" && status !== "beta") return { visible: false, name };
  // Roster table, not a users column -- users can edit their own users row
  // and could self-grant (see the internal_testers migration comment).
  const { data: tester, error: testerError } = await supabase
    .from("internal_testers")
    .select("user_id")
    .eq("user_id", userId)
    .maybeSingle();
  if (testerError) {
    console.error(`could not read internal_testers for gating: ${testerError.message}`);
    return { visible: false, name };
  }
  if (tester !== null) return { visible: true, name };
  if (status !== "beta") return { visible: false, name };
  // Beta is a self-service opt-in (beta_optins is user-writable by design).
  const { data: optin, error: optinError } = await supabase
    .from("beta_optins")
    .select("user_id")
    .eq("user_id", userId)
    .maybeSingle();
  if (optinError) {
    console.error(`could not read beta_optins for gating: ${optinError.message}`);
    return { visible: false, name };
  }
  return { visible: optin !== null, name };
}

// deno-lint-ignore no-explicit-any
async function fetchGoalConcepts(supabase: any, goalId: string): Promise<GoalWorkConcept[]> {
  const { data, error } = await supabase.from("goal_work_concept").select("*").eq("goal_id", goalId);
  if (error) {
    console.error(`could not read goal_work_concept: ${error.message}`);
    return [];
  }
  // deno-lint-ignore no-explicit-any
  return ((data ?? []) as any[]).map(conceptFromRow).filter((c): c is GoalWorkConcept => c !== null);
}

/// Library ids of the goal's mapped exercises -- resolved to names inside
/// fetchCandidateExerciseNames under its own equipment/level filters, so a
/// goal mapping can never bypass what the user owns or can safely do.
// deno-lint-ignore no-explicit-any
async function fetchGoalExerciseIds(supabase: any, goalId: string): Promise<string[]> {
  const { data, error } = await supabase
    .from("goal_exercise")
    .select("exercise_id")
    .eq("goal_id", goalId);
  if (error) {
    console.error(`could not read goal_exercise: ${error.message}`);
    return [];
  }
  // deno-lint-ignore no-explicit-any
  return ((data ?? []) as any[])
    .map((r) => r.exercise_id)
    .filter((n): n is string => typeof n === "string");
}

/// The trailing 6 days' goal-block metadata from cached plans -- feeds the
/// hangs-never-consecutive-days and every_other_day rules (both only ever
/// check yesterday specifically) and isScheduledToday's frequencyPerWeek
/// gate (counts placements across the whole window).
// deno-lint-ignore no-explicit-any
async function fetchRecentGoalBlocks(supabase: any, userId: string, date: string): Promise<GoalBlockHistoryEntry[]> {
  const windowStart = addDays(date, -6);
  const yesterday = addDays(date, -1);
  const { data, error } = await supabase
    .from("ai_workout_plan")
    .select("date, plan")
    .eq("user_id", userId)
    .gte("date", windowStart)
    .lte("date", yesterday);
  if (error || !data) return [];
  // deno-lint-ignore no-explicit-any
  return (data as any[])
    .map((row) => ({ date: row.date as string, text: (row.plan as { goal_block?: { text?: string } } | null)?.goal_block?.text }))
    .filter((r): r is GoalBlockHistoryEntry => typeof r.text === "string");
}

/// Main-block AND cool_down exercise names from the last 2 days' plans for
/// this SAME suggestion title (e.g. "Leg Day" again) -- soft-excluded from
/// today's candidate pool so picking the same suggestion two days running
/// doesn't hand back an identical (or near-identical) exercise list (BUG
/// report: the same workout, day after day -- and separately, cool_down
/// never varies at all). Deliberately scoped to `selected_title` rather
/// than a stored body-part column (ai_workout_plan doesn't have one) --
/// matching the exact suggestion the user picked is both simpler and a
/// closer match to the actual reported symptom than trying to infer
/// body-part equivalence some other way.
///
/// Deliberately warm_up is still NOT included -- repeating the same warm-up
/// stretch/mobility drill day to day is normal and often correct, unlike
/// repeating the same main lift OR the same cool_down (the latter WAS
/// excluded here too, on the same "normal to repeat" reasoning, until a
/// real user report directly contradicted that for cool_down specifically
/// -- warm_up has no equivalent report). This is a soft nudge only (it
/// just removes these names from the candidate enum); see
/// planValidation.ts's coolDownRepeatsYesterday for the deterministic
/// backstop that actually enforces cool_down varying day to day.
// deno-lint-ignore no-explicit-any
async function fetchRecentExerciseNames(supabase: any, userId: string, title: string, date: string): Promise<string[]> {
  const { data, error } = await supabase
    .from("ai_workout_plan")
    .select("plan")
    .eq("user_id", userId)
    .eq("selected_title", title)
    .gte("date", addDays(date, -2))
    .lt("date", date)
    .limit(3);
  if (error || !data) return [];
  const names = new Set<string>();
  for (const row of data as { plan: { blocks?: { exercises?: { name?: string }[] }[]; cool_down?: { name?: string }[] } | null }[]) {
    for (const block of row.plan?.blocks ?? []) {
      for (const exercise of block.exercises ?? []) {
        if (exercise.name) names.add(exercise.name);
      }
    }
    for (const exercise of row.plan?.cool_down ?? []) {
      if (exercise.name) names.add(exercise.name);
    }
  }
  return Array.from(names);
}

/// EXACTLY yesterday's cool_down exercise names for this same suggestion
/// title, or null when there's nothing to compare against (no plan
/// yesterday, or it named no cool_down at all) -- distinct from
/// fetchRecentExerciseNames above, which flattens up to 2 days into one
/// soft-exclusion set with no per-day structure. This needs the exact
/// single most-recent day's list, unflattened, for
/// planValidation.ts's coolDownRepeatsYesterday to compare against.
// deno-lint-ignore no-explicit-any
async function fetchYesterdaysCoolDownNames(supabase: any, userId: string, title: string, date: string): Promise<string[] | null> {
  const { data, error } = await supabase
    .from("ai_workout_plan")
    .select("plan")
    .eq("user_id", userId)
    .eq("selected_title", title)
    .eq("date", addDays(date, -1))
    .maybeSingle();
  if (error || !data) return null;
  const row = data as { plan: { cool_down?: { name?: string }[] } | null };
  const names = (row.plan?.cool_down ?? []).map((e) => e.name).filter((n): n is string => Boolean(n));
  return names.length > 0 ? names : null;
}

/// The coach's session as a plan block. workout_text lands in instructions
/// byte-identical -- built server-side so the model can never touch it.
function buildCoachBlock(decision: Extract<GoalWorkBlock, { kind: "custom" }>): GeneratedBlock {
  return {
    name: decision.builtWith ? `Coach Block — built with ${decision.builtWith}` : "Coach Block",
    rounds: 1,
    rest_between_rounds: "as written by your coach",
    exercises: [{
      name: decision.builtWith ? `Built with ${decision.builtWith}` : "Your coach's assignment",
      sets: 1,
      reps: "as written",
      weight_guidance: "as written by your coach",
      intensity: "as written by your coach",
      // Nominal goal-block midpoint (spec: 10-20 min) -- the coach's text
      // carries no parseable duration in v1.
      duration_minutes: 15,
      // Same "carries no parseable X in v1" reasoning as duration_minutes
      // above -- the coach's free text has no parseable rest prescription,
      // so this is an honest "not known" (null), never a fabricated number.
      rest_seconds: null,
      instructions: decision.workoutText,
    }],
    is_finisher: false,
  };
}

/// Compact goal-block record stored inside the cached plan -- read back by
/// fetchRecentGoalBlocks tomorrow and by the client for badging.
function goalBlockMeta(decision: GoalWorkBlock | null): Record<string, unknown> | null {
  if (decision === null) return null;
  return decision.kind === "preset"
    ? { kind: "preset", focus: decision.concept.focus, optional: decision.optional, text: `${decision.concept.focus}: ${decision.concept.description}` }
    : { kind: "custom", built_with: decision.builtWith, text: "coach block" };
}
