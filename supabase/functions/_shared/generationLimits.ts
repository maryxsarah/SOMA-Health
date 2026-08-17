import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

// Cost-control soft limit, not a security boundary -- subscription_tier is
// client-reported (see the users.subscription_tier migration comment).
// 1/day for free AND monthly, 3/day for annual only -- an explicit product
// decision, not a monthly/annual parity oversight.
export type SubscriptionTier = "free" | "monthly" | "annual";

export function dailyGenerationLimit(tier: SubscriptionTier): number {
  return tier === "annual" ? 3 : 1;
}

// The two `logGeneration` sources that actually represent "an AI workout
// was generated" -- the only thing this specific limit is meant to gate.
const WORKOUT_GENERATION_SOURCES = ["suggestion", "gym_photo"];

export async function checkGenerationLimit(
  supabase: SupabaseClient,
  userId: string,
  date: string,
  tier: SubscriptionTier,
): Promise<{ allowed: boolean; remaining: number }> {
  const limit = dailyGenerationLimit(tier);
  // BUG: this used to count every row in ai_generation_log for the day
  // with no source filter -- but rate-meal/parse-meal-text/suggest-workout
  // -addons all log their OWN, separately-limited activity (via
  // checkFlatDailyLimit below, correctly scoped to their own source) into
  // this SAME shared table. Real feedback: "I haven't done my workout for
  // the day yet, and SOMA does not give me a workout generated" -- rating
  // a meal or dictating one earlier that day silently consumed the "1 AI
  // workout generation" quota this function exists to gate, before the
  // user ever tried to generate a workout at all.
  const { count, error } = await supabase
    .from("ai_generation_log")
    .select("id", { count: "exact", head: true })
    .eq("user_id", userId)
    .eq("date", date)
    .in("source", WORKOUT_GENERATION_SOURCES);
  if (error) {
    throw new Error(`could not read ai_generation_log: ${error.message}`);
  }
  const used = count ?? 0;
  return { allowed: used < limit, remaining: Math.max(0, limit - used) };
}

/// Call only on an actual new generation (a cache miss that really hit the
/// LLM), never on a cache hit -- serving an already-cached plan back to the
/// user isn't a new generation and shouldn't count against their limit.
export async function logGeneration(
  supabase: SupabaseClient,
  userId: string,
  date: string,
  source: "suggestion" | "gym_photo" | "addon_suggestion" | "meal_text_estimate" | "meal_rating" | "goal_assignment_parse" | "meal_recommendation" | "exercise_translation" | "affirmation",
): Promise<void> {
  const { error } = await supabase.from("ai_generation_log").insert({ user_id: userId, date, source });
  if (error) console.error(`could not write ai_generation_log (${source}) for ${userId}: ${error.message}`);
}

/// A flat (non-tiered) daily cap, for endpoints that don't need
/// generate-workout-plan's subscription-tier-scaled limit -- defense-in-
/// depth against a single authenticated account scripting repeated calls,
/// not a product-facing quota. Same ai_generation_log table, a different
/// `source` value per endpoint so caps don't interfere with each other.
export async function checkFlatDailyLimit(
  supabase: SupabaseClient,
  userId: string,
  date: string,
  source: string,
  limit: number,
): Promise<boolean> {
  const { count, error } = await supabase
    .from("ai_generation_log")
    .select("id", { count: "exact", head: true })
    .eq("user_id", userId)
    .eq("date", date)
    .eq("source", source);
  if (error) {
    throw new Error(`could not read ai_generation_log: ${error.message}`);
  }
  return (count ?? 0) < limit;
}

export const GENERATION_LIMIT_MESSAGE =
  "You've used today's AI workout generations. Upgrade to Soma Premium (Annual) for up to 3 a day, or come back tomorrow.";
