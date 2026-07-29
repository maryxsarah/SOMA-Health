import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { describeContraindications, type InjurySeverityLevel } from "./contraindications.ts";

// Fixed, non-LLM-generated message -- never let the model diagnose/treat/
// infer a medical condition; this copy is authored once, here, and never
// varies per trigger type (avoids leaking which specific signal fired).
export const SAFETY_MESSAGE =
  "Soma can't generate a personalized workout for you right now based on something you've noted. Please check with a doctor, physiotherapist, or other qualified professional before starting a new workout -- your regular daily recommendation is still available in the meantime.";

export interface SafetyCheckResult {
  /// Hard block -- the caller must return `message` and generate nothing.
  flagged: boolean;
  message?: string;
  /// Soft adjustment -- generation proceeds, but high-impact templates are
  /// excluded. Mirrors what RecommendationDetailView already does to the
  /// normal suggestion list when an injury is noted.
  excludeHighImpact: boolean;
  /// Severity-aware exercise/template keywords to exclude, from the
  /// deterministic contraindication map -- a second, more granular filter
  /// layered on top of excludeHighImpact, never replacing it. Severe
  /// injuries exclude more broadly than mild ones.
  excludedKeywords: string[];
}

/**
 * Deterministic, server-side-only safety gate. Must run BEFORE any
 * template selection or LLM call for the gym-photo-workout feature.
 * A plain rules check -- no model judgment involved.
 *
 * Two tiers, deliberately:
 *
 * HARD BLOCK -- self-reported pregnancy, or today's resting HR deviating
 * >20% from the trailing 14-day average. Both warrant a conversation with
 * a professional rather than an automatically generated session.
 *
 * SOFT ADJUSTMENT -- a noted injury excludes high-impact templates but
 * still produces a workout. This used to be a hard block, which was both
 * inconsistent and ineffective: `generate-recommendation` ALREADY caps the
 * day's category at moderate when an injury is noted (injuryCapApplied),
 * and this function reads that already-capped category, so the intensity
 * was reduced upstream regardless. Meanwhile the normal AI-plan path hands
 * the same user a full session on the next screen after filtering
 * high-impact options. Blocking only here protected nobody -- it just made
 * one feature refuse while another obliged, and the user learned to press
 * the other button. Matching the main path's behaviour is both consistent
 * and, in practice, no less safe.
 *
 * NOTE: this is a change to a safety control and should be signed off by
 * whoever owns that decision.
 */
export async function checkSafetyFlags(
  supabase: SupabaseClient,
  userId: string,
  date: string,
): Promise<SafetyCheckResult> {
  // Errors are thrown, never swallowed. This used to destructure only
  // `data`, so a failing query -- functions deployed before the pregnancy
  // migration landed, a transient PostgREST error -- left `data` null, which
  // reads exactly like "not pregnant, no injuries" and silently switched the
  // whole guardrail off with nothing logged. A safety control has to fail
  // CLOSED: the caller turns a throw into a 500 and generates nothing, which
  // is the correct outcome when we cannot establish whether it is safe.
  const { data: userRow, error: userError } = await supabase
    .from("users")
    .select("injury_tags, injury_severity, pregnancy")
    .eq("id", userId)
    .maybeSingle();
  if (userError) {
    throw new Error(`safety check could not read users: ${userError.message}`);
  }

  if (userRow?.pregnancy === true) {
    await logFlag(supabase, userId, date, "pregnancy", null);
    return { flagged: true, message: SAFETY_MESSAGE, excludeHighImpact: true, excludedKeywords: [] };
  }

  const injuryTags = (userRow?.injury_tags as string[] | null) ?? [];
  const severityMap = (userRow?.injury_severity as Record<string, InjurySeverityLevel> | null) ?? {};
  const excludeHighImpact = injuryTags.length > 0;
  const { excludedKeywords } = describeContraindications(injuryTags, severityMap);
  if (excludeHighImpact) {
    await logFlag(supabase, userId, date, "injury_high_impact_excluded", injuryTags.join(", "));
  }

  // Pinned to HealthKit, like fetchMetricBaseline in generate-recommendation.
  // Whoop reports a sleep-derived resting HR and Apple Health a daytime
  // estimate; they differ by 10bpm or more for the same person. Mixing them
  // produced a baseline belonging to neither, and `todayRestingHr` took
  // whichever row the query happened to return first -- so the same user
  // could be told to see a doctor or not depending on row order.
  const { data: todayRows, error: todayError } = await supabase
    .from("daily_snapshot")
    .select("resting_hr")
    .eq("user_id", userId)
    .eq("source", "healthkit")
    .eq("date", date);
  if (todayError) {
    throw new Error(`safety check could not read today's snapshot: ${todayError.message}`);
  }
  const todayRestingHr = (todayRows ?? [])
    .map((r: { resting_hr: number | null }) => r.resting_hr)
    .find((v): v is number => v !== null);

  if (todayRestingHr !== undefined) {
    const baseline = await fetchRestingHrBaseline(supabase, userId, date);
    if (baseline !== null) {
      const deviation = Math.abs(todayRestingHr - baseline) / baseline;
      if (deviation > 0.2) {
        await logFlag(
          supabase,
          userId,
          date,
          "abnormal_resting_hr",
          `today ${todayRestingHr}bpm vs ${MIN_BASELINE_DAYS}+ day median ${baseline.toFixed(1)}bpm`,
        );
        return { flagged: true, message: SAFETY_MESSAGE, excludeHighImpact, excludedKeywords };
      }
    }
  }

  return { flagged: false, excludeHighImpact, excludedKeywords };
}

async function logFlag(
  supabase: SupabaseClient,
  userId: string,
  date: string,
  flagType: string,
  detail: string | null,
): Promise<void> {
  await supabase.from("safety_flag_log").insert({ user_id: userId, date, flag_type: flagType, detail });
}

/// Days of history required before the deviation check is allowed to fire.
/// Matches generate-recommendation's constant deliberately. With a one-day
/// "baseline", ordinary day-to-day resting-HR variance clears the 20% gate
/// routinely -- so the users most likely to be told to see a physician were
/// the newest ones, on no evidence at all.
const MIN_BASELINE_DAYS = 5;
const BASELINE_WINDOW_DAYS = 14;

/// Trailing median resting HR, excluding today. Median rather than mean: one
/// artefact reading should not move the threshold that decides whether we
/// refuse to generate a workout.
async function fetchRestingHrBaseline(
  supabase: SupabaseClient,
  userId: string,
  date: string,
): Promise<number | null> {
  const end = new Date(`${date}T00:00:00.000Z`);
  const start = new Date(end);
  start.setUTCDate(start.getUTCDate() - BASELINE_WINDOW_DAYS);
  const startStr = start.toISOString().slice(0, 10);
  const endStr = new Date(end.getTime() - 86400000).toISOString().slice(0, 10);

  const { data, error } = await supabase
    .from("daily_snapshot")
    .select("resting_hr")
    .eq("user_id", userId)
    .eq("source", "healthkit")
    .gte("date", startStr)
    .lte("date", endStr)
    .not("resting_hr", "is", null);
  if (error) {
    throw new Error(`safety check could not read resting-HR history: ${error.message}`);
  }

  const values = (data ?? [])
    .map((r: { resting_hr: number | null }) => r.resting_hr)
    .filter((v): v is number => v !== null)
    .sort((a, b) => a - b);
  if (values.length < MIN_BASELINE_DAYS) return null;

  const mid = Math.floor(values.length / 2);
  return values.length % 2 === 0 ? (values[mid - 1] + values[mid]) / 2 : values[mid];
}
