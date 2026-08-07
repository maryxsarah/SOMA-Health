// confirm-ai-plan
//
// "Add to today's plan" -- marks today's already-generated ai_workout_plan
// row as the day's committed plan (added_to_plan = true). Distinct from
// "Mark Workout Complete" (workout_log), which the user still does
// separately once they've actually done the workout.
//
// Server-side because ai_workout_plan has no client-facing write RLS
// policy (writes only happen via the service-role client, same pattern as
// generate-workout-plan/generate-gym-workout).
// Body: { date: "YYYY-MM-DD" }

import { handleOptions, jsonResponse } from "../_shared/cors.ts";
import { requireUser, serviceRoleClient } from "../_shared/clients.ts";

Deno.serve(async (req: Request) => {
  const preflight = handleOptions(req);
  if (preflight) return preflight;

  try {
    const userId = await requireUser(req);
    const body = await req.json().catch(() => ({}));
    const date: string | undefined = body.date;
    if (!date) return jsonResponse({ error: "missing 'date' (YYYY-MM-DD)" }, 400);

    const supabase = serviceRoleClient();

    const { data: existing, error: readError } = await supabase
      .from("ai_workout_plan")
      .select("id")
      .eq("user_id", userId)
      .eq("date", date)
      .maybeSingle();
    if (readError) throw new Error(`could not read ai_workout_plan: ${readError.message}`);
    if (!existing) {
      return jsonResponse({ error: "no AI plan generated for this date yet" }, 422);
    }

    const { error: updateError } = await supabase
      .from("ai_workout_plan")
      .update({ added_to_plan: true, added_at: new Date().toISOString() })
      .eq("user_id", userId)
      .eq("date", date);
    if (updateError) throw new Error(`could not confirm ai_workout_plan: ${updateError.message}`);

    return jsonResponse({ date, added_to_plan: true });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    const status = msg === "unauthorized" ? 401 : 500;
    return jsonResponse({ error: msg }, status);
  }
});
