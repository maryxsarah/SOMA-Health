import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

// Fixed, non-LLM-generated message -- never let the model diagnose/treat/
// infer a medical condition; this copy is authored once, here, and never
// varies per trigger type (avoids leaking which specific signal fired).
export const SAFETY_MESSAGE =
  "Soma can't generate a personalized workout for you right now based on something you've noted. Please check with a doctor, physiotherapist, or other qualified professional before starting a new workout -- your regular daily recommendation is still available in the meantime.";

export interface SafetyCheckResult {
  flagged: boolean;
  message?: string;
}

/**
 * Deterministic, server-side-only safety gate. Must run BEFORE any
 * template selection or LLM call for the gym-photo-workout feature.
 * Checks three fixed triggers: (a) a noted injury, (b) today's resting HR
 * deviating >20% from the trailing 14-day average, (c) self-reported
 * pregnancy. Any trigger logs to safety_flag_log and short-circuits the
 * caller. This is a plain rules check -- no model judgment involved.
 */
export async function checkSafetyFlags(
  supabase: SupabaseClient,
  userId: string,
  date: string,
): Promise<SafetyCheckResult> {
  const { data: userRow } = await supabase
    .from("users")
    .select("injury_tags, pregnancy")
    .eq("id", userId)
    .maybeSingle();

  const injuryTags = (userRow?.injury_tags as string[] | null) ?? [];
  if (injuryTags.length > 0) {
    await logFlag(supabase, userId, date, "injury", injuryTags.join(", "));
    return { flagged: true, message: SAFETY_MESSAGE };
  }

  if (userRow?.pregnancy === true) {
    await logFlag(supabase, userId, date, "pregnancy", null);
    return { flagged: true, message: SAFETY_MESSAGE };
  }

  const { data: todayRows } = await supabase
    .from("daily_snapshot")
    .select("resting_hr")
    .eq("user_id", userId)
    .eq("date", date);
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
          `today ${todayRestingHr}bpm vs 14-day baseline ${baseline.toFixed(1)}bpm`,
        );
        return { flagged: true, message: SAFETY_MESSAGE };
      }
    }
  }

  return { flagged: false };
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

/// Trailing 14-day resting-HR average, excluding today.
async function fetchRestingHrBaseline(
  supabase: SupabaseClient,
  userId: string,
  date: string,
): Promise<number | null> {
  const end = new Date(`${date}T00:00:00.000Z`);
  const start = new Date(end);
  start.setUTCDate(start.getUTCDate() - 14);
  const startStr = start.toISOString().slice(0, 10);
  const endStr = new Date(end.getTime() - 86400000).toISOString().slice(0, 10);

  const { data } = await supabase
    .from("daily_snapshot")
    .select("resting_hr")
    .eq("user_id", userId)
    .gte("date", startStr)
    .lte("date", endStr)
    .not("resting_hr", "is", null);

  const values = (data ?? [])
    .map((r: { resting_hr: number | null }) => r.resting_hr)
    .filter((v): v is number => v !== null);
  if (values.length === 0) return null;
  return values.reduce((a, b) => a + b, 0) / values.length;
}
