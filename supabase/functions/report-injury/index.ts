// report-injury
//
// Called from ProfileView.save() for the injury-related fields only (goals,
// equipment, experience, pregnancy etc. keep going through the existing
// direct-RLS profile update). Body: { injuryTags: string[], injurySeverity:
// Record<string, "mild"|"moderate"|"severe"> }.
//
// Diffs the new tags/severities against the CURRENT server-side row rather
// than trusting a client-computed "this is new/escalated" flag -- the
// client can't be trusted to self-report an escalation event honestly, same
// reasoning as the user_metadata rule in _shared/clients.ts. A tag that's
// newly added, or whose severity increased, starts (or restarts) a fresh
// injury_recovery_state protocol. A tag the user removed entirely has its
// existing protocol row (if any) marked 'cleared' -- the tag is no longer
// noted, so nothing should keep constraining generation for it.

import { handleOptions, jsonResponse } from "../_shared/cors.ts";
import { requireUser, serviceRoleClient } from "../_shared/clients.ts";

const SEVERITY_RANK: Record<string, number> = { mild: 1, moderate: 2, severe: 3 };

Deno.serve(async (req: Request) => {
  const preflight = handleOptions(req);
  if (preflight) return preflight;

  try {
    const userId = await requireUser(req);
    const body = await req.json().catch(() => ({}));
    const injuryTags: string[] = Array.isArray(body.injuryTags) ? body.injuryTags : [];
    const injurySeverity: Record<string, string> = body.injurySeverity && typeof body.injurySeverity === "object"
      ? body.injurySeverity
      : {};

    const supabase = serviceRoleClient();

    const { data: currentRow, error: readError } = await supabase
      .from("users")
      .select("injury_tags, injury_severity")
      .eq("id", userId)
      .maybeSingle();
    if (readError) {
      throw new Error(`could not read current injury state: ${readError.message}`);
    }

    const oldTags = new Set((currentRow?.injury_tags as string[] | null) ?? []);
    const oldSeverity = (currentRow?.injury_severity as Record<string, string> | null) ?? {};

    const newlyAddedOrEscalated: { tag: string; severity: string }[] = [];
    for (const tag of injuryTags) {
      const severity = injurySeverity[tag] ?? "moderate";
      const wasPresent = oldTags.has(tag);
      const previousSeverity = oldSeverity[tag];
      const escalated = wasPresent && previousSeverity !== undefined &&
        (SEVERITY_RANK[severity] ?? 2) > (SEVERITY_RANK[previousSeverity] ?? 2);
      if (!wasPresent || escalated) {
        newlyAddedOrEscalated.push({ tag, severity });
      }
    }

    const removedTags = Array.from(oldTags).filter((tag) => !injuryTags.includes(tag));

    const { error: writeError } = await supabase
      .from("users")
      .update({ injury_tags: injuryTags, injury_severity: injurySeverity })
      .eq("id", userId);
    if (writeError) {
      throw new Error(`could not write injury tags/severity: ${writeError.message}`);
    }

    for (const { tag, severity } of newlyAddedOrEscalated) {
      const { error } = await supabase
        .from("injury_recovery_state")
        .upsert(
          {
            user_id: userId,
            injury_tag: tag,
            severity,
            status: "active",
            protocol_started_at: new Date().toISOString(),
            last_checkin_date: null,
            last_checkin_response: null,
            consecutive_good_days: 0,
            consecutive_bad_days: 0,
            updated_at: new Date().toISOString(),
          },
          { onConflict: "user_id,injury_tag" },
        );
      if (error) {
        throw new Error(`could not start recovery protocol for ${tag}: ${error.message}`);
      }
    }

    if (removedTags.length > 0) {
      const { error } = await supabase
        .from("injury_recovery_state")
        .update({ status: "cleared", updated_at: new Date().toISOString() })
        .eq("user_id", userId)
        .in("injury_tag", removedTags);
      if (error) {
        throw new Error(`could not clear removed injury protocols: ${error.message}`);
      }
    }

    return jsonResponse({ injuryTags, injurySeverity, protocolsStarted: newlyAddedOrEscalated.map((e) => e.tag) });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    const status = msg === "unauthorized" ? 401 : 500;
    return jsonResponse({ error: msg }, status);
  }
});
