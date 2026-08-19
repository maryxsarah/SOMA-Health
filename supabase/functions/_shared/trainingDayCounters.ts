// Pure + query logic behind generate-recommendation's consecutive-days,
// volume, and proactive-rest caps -- originally pulled out of that
// function's index.ts so it's directly unit-testable (importing index.ts
// itself for a test would run its top-level Deno.serve as a side effect),
// same posture independentCaps.ts already takes for that function's other
// safety-critical cap predicates. Moved here (2026-08-19) because
// countRecentTrainingDaysByBodyPart is generic -- just a windowed
// workout_log/daily_recommendation read -- and generate-gym-workout needs
// the same 7-day per-body-part rotation signal to resolve today's target
// body part (see generate-gym-workout/targetBodyPart.ts). This is the
// established way functions share code in this codebase (see
// docs/deployment-runbook.md) -- functions don't import each other's
// directories directly.

import type { Category } from "./independentCaps.ts";

function addDays(dateStr: string, days: number): string {
  const d = new Date(`${dateStr}T00:00:00.000Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}

/// Consecutive prior days with a TRAINING day (moderate or push_hard),
/// strictly before `date`, stopping at the first gap -- e.g. training on
/// d-1, d-2, d-3 but not d-4 counts as 3, regardless of what happened
/// further back. `trainingDates` should already be filtered to
/// moderate/push_hard dates (see fetchTrainingDates below) -- rest/light
/// days are the streak BREAKING, not the streak continuing.
export function countConsecutiveTrainingDays(trainingDates: Set<string>, date: string): number {
  let count = 0;
  let cursor = addDays(date, -1);
  while (trainingDates.has(cursor)) {
    count++;
    cursor = addDays(cursor, -1);
  }
  return count;
}

/// Rolling count of training days in the set, gaps allowed -- distinct
/// from countConsecutiveTrainingDays above (which stops at the first
/// gap). A user who trains hard 6 of the last 7 days with one rest day in
/// the middle has a LOW consecutive-streak count but a real
/// accumulated-fatigue signal this rolling count catches instead.
export function countRecentTrainingDays(trainingDates: Set<string>): number {
  return trainingDates.size;
}

/// BUG report: the two counters above used to only ever see workout_log
/// rows (what the user manually logged as completed) -- a user who
/// follows every recommendation but never explicitly logs completion was
/// invisible to this whole safety net regardless of real accumulated
/// load. Fixed 2026-08-15: a date now counts as a training day if EITHER
/// workout_log has a logged moderate/push_hard row OR
/// daily_recommendation.category was moderate/push_hard that day (union,
/// not intersection) -- a served recommendation is real accumulated-load
/// exposure whether or not the user bothered to log it.
/// daily_recommendation is the same table generate-recommendation's
/// handler upserts every call, so this adds no new table, just a second
/// read of an existing one.
// deno-lint-ignore no-explicit-any
export async function fetchTrainingDates(supabase: any, userId: string, date: string): Promise<Set<string>> {
  const windowStart = addDays(date, -7);
  const [{ data: loggedRows }, { data: recommendedRows }] = await Promise.all([
    supabase
      .from("workout_log")
      .select("date")
      .eq("user_id", userId)
      .in("category", ["moderate", "push_hard"])
      .gte("date", windowStart)
      .lt("date", date),
    supabase
      .from("daily_recommendation")
      .select("date")
      .eq("user_id", userId)
      .in("category", ["moderate", "push_hard"])
      .gte("date", windowStart)
      .lt("date", date),
  ]);
  const dates = new Set<string>();
  for (const r of (loggedRows ?? []) as { date: string }[]) dates.add(r.date);
  for (const r of (recommendedRows ?? []) as { date: string }[]) dates.add(r.date);
  return dates;
}

/// Per-body-part session counts in the trailing 7 days, LOGGED rows only
/// (workout_log.body_part) -- no recommendation fallback here, since
/// daily_recommendation doesn't carry a body-part column to fall back to.
/// Feeds the body-part-aware half of volumeCapApplied (BODY_PART_SESSION_MRV,
/// _shared/volumeLandmarks.ts): the coarse full_body-only session count can
/// miss a legs-heavy (or upper-heavy) week that this catches instead.
// deno-lint-ignore no-explicit-any
export async function countRecentTrainingDaysByBodyPart(supabase: any, userId: string, date: string): Promise<Record<string, number>> {
  const { data } = await supabase
    .from("workout_log")
    .select("date, body_part")
    .eq("user_id", userId)
    .in("category", ["moderate", "push_hard"])
    .gte("date", addDays(date, -7))
    .lt("date", date);
  const byBodyPart: Record<string, Set<string>> = {};
  for (const r of (data ?? []) as { date: string; body_part: string | null }[]) {
    if (!r.body_part) continue;
    (byBodyPart[r.body_part] ??= new Set()).add(r.date);
  }
  return Object.fromEntries(Object.entries(byBodyPart).map(([bodyPart, dates]) => [bodyPart, dates.size]));
}

/// Every daily_recommendation.category in the trailing 7 days (NOT
/// filtered to moderate/push_hard -- unlike fetchTrainingDates above, the
/// proactive-rest floor needs to see rest/light rows too, to know whether
/// the week already had one). Rows only exist for days the user actually
/// opened the app / a recommendation was generated -- an empty or sparse
/// result is handled by computeProactiveRestCapApplied's own minimum-rows
/// check, not by this fetch.
// deno-lint-ignore no-explicit-any
export async function fetchRecentRecommendationCategories(supabase: any, userId: string, date: string): Promise<Category[]> {
  const { data } = await supabase
    .from("daily_recommendation")
    .select("category")
    .eq("user_id", userId)
    .gte("date", addDays(date, -7))
    .lt("date", date);
  return ((data ?? []) as { category: Category }[]).map((r) => r.category);
}
