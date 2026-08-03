// create-goal
//
// Creates the user's active sport goal (Sport Goal Programs). Two shapes:
// preset (kind:"preset", goal_id from the sport_goals catalog -- validated
// against the per-sport server gate, so a seeded/internal sport can't be
// started by a non-tester) and custom, the coach's task (kind:"custom",
// workout_text + given_text + coach_name typed by the user).
//
// Safety follows the spec's "check, warn, let the user decide" rule for
// custom goals: a deterministic keyword pass (the same injury/pregnancy
// exclusion machinery generate-workout-plan uses) runs over the coach's
// text. Conflicts are returned WITHOUT writing anything; the client shows
// them, and a second call with ack:true writes the goal storing the full
// acknowledgment (what was warned, when, accepted) in safety_ack jsonb.
// One active goal at a time is enforced by the partial unique index on
// user_goal (user_id where status='active') -- surfaced as a clean 409.

import { handleOptions, jsonResponse } from "../_shared/cors.ts";
import { requireUser, serviceRoleClient } from "../_shared/clients.ts";
import { describeContraindications, type InjurySeverityLevel } from "../_shared/contraindications.ts";
import { describePregnancyGuidance } from "../_shared/pregnancyGuidance.ts";
import { type Conflict, findConflicts } from "../_shared/goalConflicts.ts";

function addDays(dateStr: string, days: number): string {
  const d = new Date(`${dateStr}T00:00:00.000Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}

const GOAL_KINDS = ["preset", "custom"] as const;
const TARGET_KINDS = ["metric", "milestone", "qualitative", "commitment"] as const;
const SCHEDULE_RULES = ["weekdays", "every_other_day", "before_court_days", "readiness"] as const;

function isValidDay(d: unknown): d is number {
  return typeof d === "number" && Number.isInteger(d) && d >= 0 && d <= 6;
}

Deno.serve(async (req: Request) => {
  const preflight = handleOptions(req);
  if (preflight) return preflight;

  try {
    const userId = await requireUser(req);
    const body = await req.json().catch(() => ({}));
    // The iOS client sends camelCase; snake_case is accepted for parity
    // with the column names (curl/smoke-test friendliness).
    const field = (camel: string, snake: string): unknown => body[camel] ?? body[snake];

    const kind = body.kind as string | undefined;
    if (!kind || !GOAL_KINDS.includes(kind as typeof GOAL_KINDS[number])) {
      return jsonResponse({ error: "missing or invalid 'kind' ('preset' | 'custom')" }, 400);
    }
    const scheduleRule = field("scheduleRule", "schedule_rule") as string | null | undefined;
    if (scheduleRule != null && !SCHEDULE_RULES.includes(scheduleRule as typeof SCHEDULE_RULES[number])) {
      return jsonResponse({ error: `invalid 'schedule_rule' (${SCHEDULE_RULES.join(" | ")})` }, 400);
    }
    const scheduleDays = field("scheduleDays", "schedule_days") as unknown[] | null | undefined;
    const courtDays = field("courtDays", "court_days") as unknown[] | null | undefined;
    if ((scheduleDays ?? []).some((d) => !isValidDay(d)) || (courtDays ?? []).some((d) => !isValidDay(d))) {
      return jsonResponse({ error: "schedule_days/court_days must be weekday integers 0 (Sun) through 6 (Sat)" }, 400);
    }
    if (scheduleRule === "before_court_days" && (courtDays ?? []).length === 0) {
      return jsonResponse({ error: "'before_court_days' requires a non-empty 'court_days'" }, 400);
    }
    const ack = field("acknowledgeConflicts", "ack") === true;

    const supabase = serviceRoleClient();

    // Same fail-loud rule as safetyFlags: an unread error here would read
    // exactly like "no injuries, not pregnant" and skip the warning pass.
    const { data: userRow, error: userError } = await supabase
      .from("users")
      .select("injury_tags, injury_severity, pregnancy, pregnancy_week, experience_level")
      .eq("id", userId)
      .maybeSingle();
    if (userError) {
      throw new Error(`create-goal could not read users: ${userError.message}`);
    }

    let goalId: string | null = null;
    let targetKind: string;
    let customFields: Record<string, unknown> = {};
    let presetDerived: Record<string, unknown> = {};
    const conflicts: Conflict[] = [];

    if (kind === "preset") {
      const rawGoalId = field("goalId", "goal_id");
      goalId = typeof rawGoalId === "string" ? rawGoalId : null;
      if (!goalId) {
        return jsonResponse({ error: "preset goals require 'goal_id'" }, 400);
      }
      // Service role bypasses the catalog RLS, so the visibility gate is
      // re-checked here: live for all, internal for testers, beta for opt-ins.
      const { data: goalRow, error: goalError } = await supabase
        .from("sport_goals")
        .select("id, kind, target_table, sports(status)")
        .eq("id", goalId)
        .maybeSingle();
      if (goalError) {
        throw new Error(`create-goal could not read sport_goals: ${goalError.message}`);
      }
      // deno-lint-ignore no-explicit-any
      const sportStatus = ((goalRow as any)?.sports?.status as string | undefined) ?? null;
      // Service-role-only roster table (never a users column: self-grant
      // risk) -- consulted only when the sport is tester/beta-gated.
      let isTester = false;
      if (sportStatus === "internal" || sportStatus === "beta") {
        const { data: tester, error: testerError } = await supabase
          .from("internal_testers")
          .select("user_id")
          .eq("user_id", userId)
          .maybeSingle();
        if (testerError) {
          throw new Error(`create-goal could not read internal_testers: ${testerError.message}`);
        }
        isTester = tester !== null;
      }
      // Beta is self-service (beta_optins is user-writable); testers see
      // beta sports too, mirroring the sport_status_visible() RLS helper.
      let isBetaOptedIn = false;
      if (sportStatus === "beta" && !isTester) {
        const { data: optin, error: optinError } = await supabase
          .from("beta_optins")
          .select("user_id")
          .eq("user_id", userId)
          .maybeSingle();
        if (optinError) {
          throw new Error(`create-goal could not read beta_optins: ${optinError.message}`);
        }
        isBetaOptedIn = optin !== null;
      }
      const visible = sportStatus === "live" ||
        (sportStatus === "internal" && isTester) ||
        (sportStatus === "beta" && (isBetaOptedIn || isTester));
      if (!goalRow || !visible) {
        return jsonResponse({ error: "unknown or unavailable goal" }, 404);
      }
      const rawTargetKind = field("targetKind", "target_kind");
      targetKind = typeof rawTargetKind === "string" ? rawTargetKind : (goalRow.kind as string);
      if (!TARGET_KINDS.includes(targetKind as typeof TARGET_KINDS[number])) {
        return jsonResponse({ error: `invalid 'target_kind' (${TARGET_KINDS.join(" | ")})` }, 400);
      }
      // The honest target and re-test window come from the catalog's
      // evidence band for this user's level -- never from client input.
      // deno-lint-ignore no-explicit-any
      const bands = ((goalRow as any).target_table?.bands ?? {}) as Record<string, Record<string, unknown>>;
      const level = ((userRow?.experience_level as string | null) ?? "newbie") === "advanced"
        ? "advanced"
        : (userRow?.experience_level === "moderate" ? "intermediate" : "novice");
      const band = bands[level] ?? bands["novice"] ?? null;
      if (band) {
        const num = (k: string) => typeof band[k] === "number" ? band[k] as number : null;
        const weeksLow = num("horizon_weeks_low");
        const weeksHigh = num("horizon_weeks_high");
        const today = new Date().toISOString().slice(0, 10);
        presetDerived = {
          target_low: targetKind === "metric" ? num("gain_low") : null,
          target_high: targetKind === "metric" ? num("gain_high") : null,
          eta_start: weeksLow !== null ? addDays(today, weeksLow * 7) : null,
          eta_end: weeksHigh !== null ? addDays(today, weeksHigh * 7) : null,
        };
      }
    } else {
      const rawWorkoutText = field("workoutText", "workout_text");
      const workoutText = typeof rawWorkoutText === "string" ? rawWorkoutText : "";
      if (workoutText.trim().length === 0) {
        return jsonResponse({ error: "custom goals require a non-empty 'workout_text'" }, 400);
      }
      const rawGivenText = field("givenText", "given_text");
      const givenText = typeof rawGivenText === "string" ? rawGivenText : null;
      const rawTargetKind = field("targetKind", "target_kind");
      targetKind = typeof rawTargetKind === "string" ? rawTargetKind : "commitment";
      if (!TARGET_KINDS.includes(targetKind as typeof TARGET_KINDS[number])) {
        return jsonResponse({ error: `invalid 'target_kind' (${TARGET_KINDS.join(" | ")})` }, 400);
      }
      const coachName = field("coachName", "coach_name");
      const durationWeeks = field("durationWeeks", "duration_weeks");
      const recheckDate = field("recheckDate", "recheck_date");
      const metricName = field("customMetricName", "custom_metric_name");
      const metricUnit = field("customMetricUnit", "custom_metric_unit");
      const photoPath = field("assignmentPhotoPath", "assignment_photo_path");
      customFields = {
        given_text: givenText,
        // Stored exactly as typed -- rendered verbatim on scheduled days.
        workout_text: workoutText,
        coach_name: typeof coachName === "string" && coachName.trim().length > 0 ? coachName.trim() : null,
        duration_weeks: typeof durationWeeks === "number" && Number.isInteger(durationWeeks) && durationWeeks > 0 ? durationWeeks : 8,
        // Fixed re-check date -- the coach owns pacing. Defaults to the
        // coach's block length from today when the client sends none.
        recheck_date: typeof recheckDate === "string" ? recheckDate : addDays(
          new Date().toISOString().slice(0, 10),
          (typeof durationWeeks === "number" && Number.isInteger(durationWeeks) && durationWeeks > 0 ? durationWeeks : 8) * 7,
        ),
        custom_metric_name: typeof metricName === "string" ? metricName : null,
        custom_metric_unit: typeof metricUnit === "string" ? metricUnit : null,
        assignment_photo_path: typeof photoPath === "string" ? photoPath : null,
      };

      // Deterministic safety pass over the coach's text -- warnings, never
      // blocks; the user decides, and the decision is stored.
      const { excludedKeywords: injuryKeywords } = describeContraindications(
        (userRow?.injury_tags as string[] | null) ?? [],
        ((userRow?.injury_severity ?? {}) as Record<string, InjurySeverityLevel>),
      );
      const pregnancyKeywords = userRow?.pregnancy === true
        ? describePregnancyGuidance((userRow?.pregnancy_week as number | null) ?? null).excludedKeywords
        : [];
      const scannedText = [workoutText, givenText ?? ""].join("\n");
      conflicts.push(...findConflicts(scannedText, injuryKeywords, "injury"));
      conflicts.push(...findConflicts(scannedText, pregnancyKeywords, "pregnancy"));
    }

    // Conflicts without an acknowledgment: return them, write NOTHING.
    if (conflicts.length > 0 && !ack) {
      return jsonResponse({ conflicts });
    }

    const safetyAck = conflicts.length > 0
      ? {
        warned: conflicts.map((c) => ({ keyword: c.keyword, source: c.source, message: c.message })),
        warned_at: new Date().toISOString(),
        accepted: true,
      }
      : null;

    const frequencyPerWeek = field("frequencyPerWeek", "frequency_per_week");
    const baselineValue = field("baselineValue", "baseline_value");
    // Non-numeric baseline/target wording, any kind -- previously accepted
    // by the client but silently discarded here.
    const baselineStage = field("baselineStage", "baseline_stage");
    const targetText = field("targetText", "target_text");
    const { data: inserted, error: insertError } = await supabase
      .from("user_goal")
      .insert({
        user_id: userId,
        goal_id: goalId,
        kind,
        target_kind: targetKind,
        status: "active",
        phase: typeof body.phase === "string" ? body.phase : (kind === "preset" ? "foundation" : null),
        baseline_value: typeof baselineValue === "number" ? baselineValue : null,
        baseline_stage: typeof baselineStage === "string" && baselineStage.trim().length > 0 ? baselineStage : null,
        target_text: typeof targetText === "string" && targetText.trim().length > 0 ? targetText : null,
        frequency_per_week: typeof frequencyPerWeek === "number" ? frequencyPerWeek : null,
        schedule_rule: scheduleRule ?? null,
        schedule_days: (scheduleDays as number[] | null | undefined) ?? null,
        court_days: (courtDays as number[] | null | undefined) ?? null,
        safety_ack: safetyAck,
        ...presetDerived,
        ...customFields,
      })
      .select()
      .maybeSingle();
    if (insertError) {
      // The partial unique index (one active goal per user) fires here.
      if (insertError.code === "23505") {
        return jsonResponse({ error: "You already have an active goal. Complete, pause, or cancel it before starting a new one." }, 409);
      }
      throw new Error(`create-goal could not write user_goal: ${insertError.message}`);
    }

    return jsonResponse({ created: true, conflicts_acknowledged: conflicts.length, goal: inserted });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    if (message === "unauthorized") return jsonResponse({ error: "unauthorized" }, 401);
    console.error(`create-goal failed: ${message}`);
    return jsonResponse({ error: message }, 500);
  }
});
