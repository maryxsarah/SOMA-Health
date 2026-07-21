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

    if (!tokenResponse) {
      return jsonResponse({ error: "token exchange failed" }, 502);
    }

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
      },
      { onConflict: "user_id,provider" },
    );

    if (error) {
      return jsonResponse({ error: error.message }, 500);
    }

    return jsonResponse({ provider, connected: true });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    const status = msg === "unauthorized" ? 401 : 500;
    return jsonResponse({ error: msg }, status);
  }
});

interface TokenResponse {
  access_token: string;
  refresh_token?: string;
  expires_in: number;
}

async function exchangeWhoop(
  code: string,
  codeVerifier: string | undefined,
  redirectUri: string,
): Promise<TokenResponse | null> {
  const clientId = Deno.env.get("WHOOP_CLIENT_ID")!;
  const clientSecret = Deno.env.get("WHOOP_CLIENT_SECRET")!;

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
  if (!res.ok) return null;
  return await res.json();
}

async function exchangeOura(
  code: string,
  codeVerifier: string | undefined,
  redirectUri: string,
): Promise<TokenResponse | null> {
  const clientId = Deno.env.get("OURA_CLIENT_ID")!;
  const clientSecret = Deno.env.get("OURA_CLIENT_SECRET")!;

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
  if (!res.ok) return null;
  return await res.json();
}
