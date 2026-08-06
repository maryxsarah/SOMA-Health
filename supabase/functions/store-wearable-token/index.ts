// store-wearable-token
//
// The iOS app never sees a Whoop/Oura client_secret (it must not ship
// inside the app binary), so it does NOT perform the OAuth code->token
// exchange itself. Instead it sends the raw authorization `code` (plus the
// PKCE verifier and the redirect_uri it used) here, and this function
// performs the exchange server-side using a secret that only it holds.
//
// Body: { provider: "whoop" | "oura", code, codeVerifier, redirectUri }
// Response: { provider, connected: true } -- raw tokens are never returned
// to the client.

import { handleOptions, jsonResponse } from "../_shared/cors.ts";
import { requireUser, serviceRoleClient } from "../_shared/clients.ts";

const WHOOP_TOKEN_URL = "https://api.prod.whoop.com/oauth/oauth2/token";
const OURA_TOKEN_URL = "https://api.ouraring.com/oauth/token";

Deno.serve(async (req: Request) => {
  const preflight = handleOptions(req);
  if (preflight) return preflight;

  try {
    const userId = await requireUser(req);
    const body = await req.json().catch(() => ({}));
    const { provider, code, codeVerifier, redirectUri } = body as {
      provider?: "whoop" | "oura";
      code?: string;
      codeVerifier?: string;
      redirectUri?: string;
    };

    if (!provider || !code || !redirectUri) {
      return jsonResponse(
        { error: "missing provider, code, or redirectUri" },
        400,
      );
    }
    if (provider !== "whoop" && provider !== "oura") {
      return jsonResponse({ error: "unknown provider" }, 400);
    }

    const tokenResponse =
      provider === "whoop"
        ? await exchangeWhoop(code, codeVerifier, redirectUri)
        : await exchangeOura(code, codeVerifier, redirectUri);

    const supabase = serviceRoleClient();
    const expiresAt = new Date(
      Date.now() + tokenResponse.expires_in * 1000,
    ).toISOString();

    const { error } = await supabase.from("wearable_tokens").upsert(
      {
        user_id: userId,
        provider,
        access_token: tokenResponse.access_token,
        refresh_token: tokenResponse.refresh_token ?? null,
        expires_at: expiresAt,
        // A fresh authorization-code exchange always produces a brand new
        // token pair -- clears any needs_reconnect left over from a prior
        // dead refresh token (see generate-recommendation's
        // ensureFreshWhoopToken/ensureFreshOuraToken), whether this is a
        // first-time connect or the user tapping "Reconnect".
        needs_reconnect: false,
      },
      { onConflict: "user_id,provider" },
    );

    if (error) {
      return jsonResponse({ error: error.message }, 500);
    }

    return jsonResponse({ provider, connected: true });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    if (msg === "unauthorized") return jsonResponse({ error: msg }, 401);

    // Upstream failures answer 502 with a sanitized message. The detail goes
    // to the function log, never to the client: SupabaseClient.assertSuccess
    // puts the whole response body into the error it throws, and ProfileView
    // interpolates that straight into on-screen text. Without this the user
    // saw a raw nested OAuth JSON blob, and a misconfigured deployment
    // handed any authenticated caller the internal hint naming the exact
    // secrets that were missing.
    //
    // The 502-vs-500 split also matters operationally: 502 means Whoop/Oura
    // failed, 500 means we did. Collapsing them made provider outages
    // indistinguishable from our own bugs in monitoring.
    if (err instanceof UpstreamError) {
      console.error(`[store-wearable-token] ${msg}`);
      return jsonResponse(
        { error: "Couldn't connect that device right now. Please try again." },
        502,
      );
    }

    console.error(`[store-wearable-token] ${msg}`);
    return jsonResponse({ error: "Something went wrong storing that connection." }, 500);
  }
});

/// Marks a failure that originated with Whoop or Oura rather than with us,
/// so the handler can answer 502 and keep the upstream body out of the
/// client-visible response.
class UpstreamError extends Error {}

interface TokenResponse {
  access_token: string;
  refresh_token?: string;
  expires_in: number;
}

async function exchangeWhoop(
  code: string,
  codeVerifier: string | undefined,
  redirectUri: string,
): Promise<TokenResponse> {
  const clientId = Deno.env.get("WHOOP_CLIENT_ID");
  const clientSecret = Deno.env.get("WHOOP_CLIENT_SECRET");
  if (!clientId || !clientSecret) {
    // Deliberately NOT an UpstreamError: this is our misconfiguration, so it
    // answers 500. The actionable text stays in the function log.
    throw new Error(
      "WHOOP_CLIENT_ID/WHOOP_CLIENT_SECRET are not set as Supabase secrets -- run `supabase secrets set WHOOP_CLIENT_ID=... WHOOP_CLIENT_SECRET=...`",
    );
  }

  const params = new URLSearchParams({
    grant_type: "authorization_code",
    code,
    redirect_uri: redirectUri,
    client_id: clientId,
    client_secret: clientSecret,
  });
  if (codeVerifier) params.set("code_verifier", codeVerifier);

  const res = await fetch(WHOOP_TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: params,
  });
  if (!res.ok) {
    const errBody = await res.text();
    throw new UpstreamError(`Whoop token exchange failed (${res.status}): ${errBody}`);
  }
  return await res.json();
}

async function exchangeOura(
  code: string,
  codeVerifier: string | undefined,
  redirectUri: string,
): Promise<TokenResponse> {
  const clientId = Deno.env.get("OURA_CLIENT_ID");
  const clientSecret = Deno.env.get("OURA_CLIENT_SECRET");
  if (!clientId || !clientSecret) {
    throw new Error(
      "OURA_CLIENT_ID/OURA_CLIENT_SECRET are not set as Supabase secrets -- run `supabase secrets set OURA_CLIENT_ID=... OURA_CLIENT_SECRET=...`",
    );
  }

  const params = new URLSearchParams({
    grant_type: "authorization_code",
    code,
    redirect_uri: redirectUri,
    client_id: clientId,
    client_secret: clientSecret,
  });
  if (codeVerifier) params.set("code_verifier", codeVerifier);

  const res = await fetch(OURA_TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: params,
  });
  if (!res.ok) {
    const errBody = await res.text();
    throw new UpstreamError(`Oura token exchange failed (${res.status}): ${errBody}`);
  }
  return await res.json();
}
