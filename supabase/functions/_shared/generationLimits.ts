import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

// Cost-control soft limit, not a security boundary -- subscription_tier is
// client-reported (see the users.subscription_tier migration comment).
// 1/day for free AND monthly, 3/day for annual only -- an explicit product
// decision, not a monthly/annual parity oversight.
export type SubscriptionTier = "free" | "monthly" | "annual";

export function dailyGenerationLimit(tier: SubscriptionTier): number {
  return tier === "annual" ? 3 : 1;
}

export async function checkGenerationLimit(
  supabase: SupabaseClient,
  userId: string,
  date: string,
  tier: SubscriptionTier,
): Promise<{ allowed: boolean; remaining: number }> {
  const limit = dailyGenerationLimit(tier);
  const { count, error } = await supabase
    .from("ai_generation_log")
    .select("id", { count: "exact", head: true })
    .eq("user_id", userId)
    .eq("date", date);
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
  source: "suggestion" | "gym_photo" | "addon_suggestion",
): Promise<void> {
  await supabase.from("ai_generation_log").insert({ user_id: userId, date, source });
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
