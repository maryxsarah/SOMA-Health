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
    // Both informational only -- unlike tags/severity, neither affects
    // contraindication filtering or the recovery-protocol state machine,
    // so no diffing/escalation logic is needed for them, just write-through.
    const injuryType: Record<string, string> = body.injuryType && typeof body.injuryType === "object"
      ? body.injuryType
      : {};
    const injuryPainLevel: Record<string, number> = body.injuryPainLevel && typeof body.injuryPainLevel === "object"
      ? body.injuryPainLevel
      : {};

    // Reject unknown severities outright rather than storing them: a raw
    // value like "critical" would be persisted verbatim, and every later
    // describeContraindications lookup on it would crash generation for
    // this account until the row is repaired by hand. Fail loudly at the
    // door instead.
    const invalid = Object.entries(injurySeverity)
      .filter(([, v]) => !(v in SEVERITY_RANK))
      .map(([k, v]) => `${k}=${v}`);
    if (invalid.length > 0) {
      return jsonResponse(
        { error: `invalid injurySeverity value(s): ${invalid.join(", ")} (expected mild|moderate|severe)` },
        400,
      );
    }

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
    const severityChangedOnly: { tag: string; severity: string }[] = [];
    for (const tag of injuryTags) {
      const severity = injurySeverity[tag] ?? "moderate";
      const wasPresent = oldTags.has(tag);
      // An unset previous severity is treated as moderate everywhere else
      // (contraindications.ts), so it must rank as moderate here too --
      // requiring previousSeverity to be defined meant a pre-severity-era
      // tag raised to "severe" never started a protocol at all.
      const previousRank = SEVERITY_RANK[oldSeverity[tag]] ?? 2;
      const newRank = SEVERITY_RANK[severity] ?? 2;
      if (!wasPresent || newRank > previousRank) {
        newlyAddedOrEscalated.push({ tag, severity });
      } else if (newRank !== previousRank) {
        // Downgrade: the protocol keeps running (recovery evidence, not a
        // severity edit, is what clears it), but its severity must follow
        // the profile -- otherwise a severe->mild edit left the severe cap
        // forcing every day to "light" indefinitely, with a message that
        // no longer matched what the user's profile said.
        severityChangedOnly.push({ tag, severity });
      }
    }

    const removedTags = Array.from(oldTags).filter((tag) => !injuryTags.includes(tag));

    const { error: writeError } = await supabase
      .from("users")
      .update({
        injury_tags: injuryTags,
        injury_severity: injurySeverity,
        injury_type: injuryType,
        injury_pain_level: injuryPainLevel,
      })
      .eq("id", userId);
    if (writeError) {
      throw new Error(`could not write injury tags/severity: ${writeError.message}`);
    }

    // Mild injuries never get a recovery-state row at all -- per product
    // decision, mild is exclusion-only (contraindications.ts handles it
    // within the same body part), with no multi-day protocol/check-in
    // machinery. Only moderate/severe start (or restart) a protocol.
    for (const { tag, severity } of newlyAddedOrEscalated) {
      if (severity === "mild") continue;
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

    for (const { tag, severity } of severityChangedOnly) {
      // A downgrade to mild exits the protocol entirely (same reasoning as
      // above) rather than leaving a mild-severity row that would still
      // gate generation -- clear it instead of just updating severity.
      const { error } = severity === "mild"
        ? await supabase
          .from("injury_recovery_state")
          .update({ status: "cleared", updated_at: new Date().toISOString() })
          .eq("user_id", userId)
          .eq("injury_tag", tag)
          .neq("status", "cleared")
        : await supabase
          .from("injury_recovery_state")
          .update({ severity, updated_at: new Date().toISOString() })
          .eq("user_id", userId)
          .eq("injury_tag", tag)
          .neq("status", "cleared");
      if (error) {
        throw new Error(`could not update severity for ${tag}: ${error.message}`);
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
