// resolve-injury-substitutions
//
// Called from RecommendationDetailView before rendering the day's workout
// suggestion list, so the list itself steers away from any body part a
// moderate/severe injury conflicts with -- rather than only resolving the
// conflict later, at generation time (generate-workout-plan/index.ts also
// runs the same resolution as a defense-in-depth fallback, in case a stale
// list is shown or the endpoint is bypassed).
//
// No request body needed -- reads the caller's own injury_tags/
// injury_severity from `users`. Returns every body-part redirect currently
// active for that user, e.g. { "lower_body": "upper_body" } for a knee
// injury -- an empty object means no injury currently redirects anything.

import { handleOptions, jsonResponse } from "../_shared/cors.ts";
import { requireUser, serviceRoleClient } from "../_shared/clients.ts";
import { activeSubstitutionMap } from "../_shared/injurySubstitution.ts";
import type { InjurySeverityLevel } from "../_shared/contraindications.ts";

Deno.serve(async (req: Request) => {
  const preflight = handleOptions(req);
  if (preflight) return preflight;

  try {
    const userId = await requireUser(req);
    const supabase = serviceRoleClient();

    const { data: userRow, error } = await supabase
      .from("users")
      .select("injury_tags, injury_severity")
      .eq("id", userId)
      .maybeSingle();
    if (error) {
      throw new Error(`could not read injury state: ${error.message}`);
    }

    const injuryTags = (userRow?.injury_tags as string[] | null) ?? [];
    const severityMap = (userRow?.injury_severity as Record<string, InjurySeverityLevel> | null) ?? {};

    return jsonResponse({ substitutions: activeSubstitutionMap(injuryTags, severityMap) });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    const status = msg === "unauthorized" ? 401 : 500;
    return jsonResponse({ error: msg }, status);
  }
});
