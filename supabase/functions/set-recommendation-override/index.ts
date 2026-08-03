// set-recommendation-override
//
// Lets the user directly request a rest or active-recovery day, overriding
// whatever the health-data-driven category would otherwise be -- distinct
// from every cap in generate-recommendation (those are computed from
// wearable/HealthKit signals; this is the user's own explicit choice, and
// wins outright over all of them, see generate-recommendation/index.ts's
// userRequestedCategory handling). Body:
// { date: "YYYY-MM-DD", category: "rest" | "light" | null }
// `category: null` clears an existing request for that date.
//
// Requires today's daily_recommendation row to already exist (an ordinary
// `update`, not an upsert) -- this endpoint only ever overrides an already-
// computed category, never fabricates the rest of that row's required
// fields (message, reason, etc.) from nothing. In practice the row always
// exists by the time this UI is reachable, since Home already loads
// today's recommendation before the override affordance renders.

import { handleOptions, jsonResponse } from "../_shared/cors.ts";
import { requireUser, serviceRoleClient } from "../_shared/clients.ts";

const ALLOWED_CATEGORIES = ["rest", "light"] as const;

Deno.serve(async (req: Request) => {
  const preflight = handleOptions(req);
  if (preflight) return preflight;

  try {
    const userId = await requireUser(req);
    const body = await req.json().catch(() => ({}));
    const date: string | undefined = body.date;
    const category: string | null = body.category ?? null;

    if (!date) {
      return jsonResponse({ error: "missing 'date' (YYYY-MM-DD)" }, 400);
    }
    if (category !== null && !ALLOWED_CATEGORIES.includes(category as typeof ALLOWED_CATEGORIES[number])) {
      return jsonResponse({ error: `invalid category '${category}' (expected 'rest', 'light', or null)` }, 400);
    }

    const supabase = serviceRoleClient();

    const { data, error } = await supabase
      .from("daily_recommendation")
      .update({ user_requested_category: category })
      .eq("user_id", userId)
      .eq("date", date)
      .select("id")
      .maybeSingle();

    if (error) {
      throw new Error(`could not update daily_recommendation: ${error.message}`);
    }
    if (!data) {
      return jsonResponse(
        { error: "no recommendation exists yet for this date -- fetch today's recommendation first" },
        422,
      );
    }

    return jsonResponse({ date, user_requested_category: category });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    const status = msg === "unauthorized" ? 401 : 500;
    return jsonResponse({ error: msg }, status);
  }
});
