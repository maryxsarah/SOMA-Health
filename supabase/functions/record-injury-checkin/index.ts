// record-injury-checkin
//
// Body: { injuryTag: string, response: "better" | "same" | "worse" }.
// Advances the injury_recovery_state state machine for one tag. Fixed
// transition rules -- deterministic, never left to the model:
//
// worse -> back to (or stays) "active", resets the good-day streak,
//   extends the bad-day streak. 3+ consecutive "worse"/non-improving
//   check-ins escalates to a stronger fixed "see a professional" message
//   (same fixed-copy pattern as safetyFlags.ts's SAFETY_MESSAGE -- never
//   LLM-generated).
// same -> no streak progress either direction; status unchanged.
// better -> moves to (or stays) "recovering", extends the good-day streak.
//   5+ consecutive "better" check-ins while recovering clears the protocol
//   entirely (mirrors generate-recommendation's MIN_BASELINE_DAYS = 5
//   convention for "enough consecutive evidence").
//
// A stale (3+ day old) check-in is handled by simple inaction: nothing here
// auto-clears a protocol based on time passing, only an explicit run of good
// check-ins does -- fail closed, same philosophy as safetyFlags.ts's
// missing-data handling.

import { handleOptions, jsonResponse } from "../_shared/cors.ts";
import { requireUser, serviceRoleClient } from "../_shared/clients.ts";

// DRAFTED, NOT EXPERT-REVIEWED -- these thresholds are invented for this
// feature, matching this codebase's existing MIN_BASELINE_DAYS = 5
// convention but not derived from clinical guidance. Needs sign-off.
const GOOD_DAYS_TO_CLEAR = 5;
const BAD_DAYS_TO_ESCALATE = 3;

const ESCALATION_MESSAGE =
  "This injury doesn't seem to be improving after several check-ins. Please consider seeing a doctor or physiotherapist -- Soma's guidance here is informational only, not a diagnosis.";

type CheckinResponse = "better" | "same" | "worse";

Deno.serve(async (req: Request) => {
  const preflight = handleOptions(req);
  if (preflight) return preflight;

  try {
    const userId = await requireUser(req);
    const body = await req.json().catch(() => ({}));
    const injuryTag: string | undefined = body.injuryTag;
    const response: CheckinResponse | undefined = body.response;
    if (!injuryTag || !response || !["better", "same", "worse"].includes(response)) {
      return jsonResponse({ error: "missing or invalid 'injuryTag'/'response'" }, 400);
    }

    const supabase = serviceRoleClient();

    const { data: row, error: readError } = await supabase
      .from("injury_recovery_state")
      .select("*")
      .eq("user_id", userId)
      .eq("injury_tag", injuryTag)
      .maybeSingle();
    if (readError) {
      throw new Error(`could not read recovery state: ${readError.message}`);
    }
    if (!row) {
      return jsonResponse({ error: `no active recovery protocol for injury '${injuryTag}'` }, 404);
    }
    if (row.status === "cleared") {
      return jsonResponse({ error: "this injury's protocol is already cleared" }, 400);
    }

    let status: string = row.status;
    let consecutiveGoodDays: number = row.consecutive_good_days;
    let consecutiveBadDays: number = row.consecutive_bad_days;
    let escalate = false;

    if (response === "worse") {
      consecutiveGoodDays = 0;
      consecutiveBadDays += 1;
      status = "active";
      escalate = consecutiveBadDays >= BAD_DAYS_TO_ESCALATE;
    } else if (response === "same") {
      consecutiveGoodDays = 0;
      consecutiveBadDays = 0;
    } else {
      consecutiveBadDays = 0;
      consecutiveGoodDays += 1;
      status = "recovering";
      if (consecutiveGoodDays >= GOOD_DAYS_TO_CLEAR) {
        status = "cleared";
      }
    }

    const today = new Date().toISOString().slice(0, 10);
    const { error: writeError } = await supabase
      .from("injury_recovery_state")
      .update({
        status,
        last_checkin_date: today,
        last_checkin_response: response,
        consecutive_good_days: consecutiveGoodDays,
        consecutive_bad_days: consecutiveBadDays,
        updated_at: new Date().toISOString(),
      })
      .eq("id", row.id);
    if (writeError) {
      throw new Error(`could not record check-in: ${writeError.message}`);
    }

    return jsonResponse({
      injuryTag,
      status,
      consecutiveGoodDays,
      consecutiveBadDays,
      escalate,
      escalationMessage: escalate ? ESCALATION_MESSAGE : undefined,
    });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    const status = msg === "unauthorized" ? 401 : 500;
    return jsonResponse({ error: msg }, status);
  }
});
