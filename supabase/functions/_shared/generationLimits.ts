import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

// Cost-control soft limit, not a security boundary -- subscription_tier is
// client-reported (see the users.subscription_tier migration comment).
// Product decision 2026-08-18: 3/day free, 3/day monthly, 10/day annual
// -- free raised from 1 to match monthly, since the free tier is what
// internal test accounts run on.
export type SubscriptionTier = "free" | "monthly" | "annual";

export function dailyGenerationLimit(tier: SubscriptionTier): number {
  if (tier === "annual") return 10;
  return 3;
}

// The workout-shaped generation sources. Product decision 2026-08-18:
// back to ONE shared daily bucket across both (reverses the 2026-08-17
// per-source split) -- a workout suggestion and a gym-photo scan now draw
// from the same quota. Affirmations aren't part of this bucket: they run
// on checkFlatDailyLimit below with their own source.
export type WorkoutGenerationSource = "suggestion" | "gym_photo";
const SHARED_BUCKET_SOURCES: WorkoutGenerationSource[] = ["suggestion", "gym_photo"];

export async function checkGenerationLimit(
  supabase: SupabaseClient,
  userId: string,
  date: string,
  tier: SubscriptionTier,
  source: WorkoutGenerationSource,
): Promise<{ allowed: boolean; remaining: number }> {
  const limit = dailyGenerationLimit(tier);
  // `source` still names what THIS call is requesting, but the count
  // spans both sources in the shared bucket -- see SHARED_BUCKET_SOURCES.
  const { count, error } = await supabase
    .from("ai_generation_log")
    .select("id", { count: "exact", head: true })
    .eq("user_id", userId)
    .eq("date", date)
    .in("source", SHARED_BUCKET_SOURCES);
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
  source: "suggestion" | "gym_photo" | "addon_suggestion" | "meal_text_estimate" | "meal_rating" | "goal_assignment_parse" | "meal_recommendation" | "exercise_translation" | "affirmation" | "meal_recommendation_daily",
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
  "You've used today's AI workout generations. Upgrade to Soma Premium (Annual) for up to 10 a day, or come back tomorrow.";
