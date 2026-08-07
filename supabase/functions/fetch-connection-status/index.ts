// fetch-connection-status
//
// Plain read-only fetch of the caller's Whoop/Oura connection health --
// distinct from AppState.connectedProviders (a local, device-only cache
// set once at connect time and never re-verified). A refresh-token
// failure (revoked access, expired refresh token) previously had no way
// to reach the client at all: ensureFreshWhoopToken/ensureFreshOuraToken
// in generate-recommendation would just silently return null forever,
// with the local cache still confidently showing "Connected". This
// endpoint is what lets the client ask the server directly. Apple Health
// isn't included -- it's on-device only, nothing server-side to check.
//
// Response: { whoop: { connected, needsReconnect }, oura: { connected,
// needsReconnect } }. A provider with no wearable_tokens row at all is
// connected: false, needsReconnect: false (never connected, not broken).

import { handleOptions, jsonResponse } from "../_shared/cors.ts";
import { requireUser, serviceRoleClient } from "../_shared/clients.ts";

Deno.serve(async (req: Request) => {
  const preflight = handleOptions(req);
  if (preflight) return preflight;

  try {
    const userId = await requireUser(req);
    const supabase = serviceRoleClient();

    const { data, error } = await supabase
      .from("wearable_tokens")
      .select("provider, needs_reconnect")
      .eq("user_id", userId);
    if (error) {
      throw new Error(`could not read wearable_tokens: ${error.message}`);
    }

    const rows = (data ?? []) as { provider: "whoop" | "oura"; needs_reconnect: boolean }[];
    const statusFor = (provider: "whoop" | "oura") => {
      const row = rows.find((r) => r.provider === provider);
      return { connected: row !== undefined, needsReconnect: row?.needs_reconnect ?? false };
    };

    return jsonResponse({
      whoop: statusFor("whoop"),
      oura: statusFor("oura"),
    });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    const status = msg === "unauthorized" ? 401 : 500;
    return jsonResponse({ error: msg }, status);
  }
});
