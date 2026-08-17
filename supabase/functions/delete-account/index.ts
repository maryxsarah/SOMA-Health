// delete-account
//
// In-app account deletion (App Review Guideline 5.1.1(v)). Body:
// { appleAuthorizationCode?: string }. The caller is resolved ONLY from
// the Authorization JWT -- a user id in the body would let any signed-in
// user delete someone else.
//
// Order of operations (each step best-effort where noted, so a transient
// third-party failure can't strand the user in a half-deleted state):
// 1. Revoke Sign in with Apple tokens (Apple mandate since June 2022,
//    TN3194) -- FIRST, because the fresh authorization code the client
//    obtained at confirmation expires in ~5 minutes. Best-effort: needs
//    the APPLE_* secrets below; skipped with a warning when absent or
//    when the user didn't sign in with Apple.
// 2. Delete the user's Storage objects (body-photos / avatars /
//    coach-assignments, all keyed by a `${userId}/` prefix) -- owned
//    objects BLOCK auth.admin.deleteUser, and files must go through the
//    Storage API (SQL deletion orphans the underlying blobs).
// 3. PostHog person deletion (GDPR erasure) -- best-effort, only when
//    POSTHOG_* secrets are configured.
// 4. Delete the public.users row (cascades to every app table via FKs),
//    then auth.admin.deleteUser (hard delete; also kills sessions).
//
// Required secrets for Apple revocation (supabase secrets set ...):
//   APPLE_TEAM_ID      -- e.g. G52G32NA32
//   APPLE_KEY_ID       -- the .p8 key's ID
//   APPLE_PRIVATE_KEY  -- the .p8 file's full PEM contents
//   APPLE_CLIENT_ID    -- optional, defaults to com.skollnitzer.soma

import { importPKCS8, SignJWT } from "https://esm.sh/jose@5";
import { handleOptions, jsonResponse } from "../_shared/cors.ts";
import { requireUser, serviceRoleClient } from "../_shared/clients.ts";

const USER_BUCKETS = ["body-photos", "avatars", "coach-assignments"];
const APPLE_CLIENT_ID = Deno.env.get("APPLE_CLIENT_ID") ?? "com.skollnitzer.soma";

Deno.serve(async (req: Request) => {
  const preflight = handleOptions(req);
  if (preflight) return preflight;

  try {
    const userId = await requireUser(req);
    const body = await req.json().catch(() => ({}));
    const appleAuthorizationCode: string | undefined = body.appleAuthorizationCode;

    const supabase = serviceRoleClient();

    let appleTokenRevoked: boolean | null = null;
    if (appleAuthorizationCode) {
      appleTokenRevoked = await revokeAppleTokens(appleAuthorizationCode);
    }

    for (const bucket of USER_BUCKETS) {
      await deleteUserObjects(supabase, bucket, userId);
    }

    await deletePostHogPerson(userId);

    // Explicit first (works even against a pre-cascade-migration schema),
    // then the auth row -- which cascades sessions and, post-migration,
    // would have covered public.users anyway.
    const { error: profileError } = await supabase.from("users").delete().eq("id", userId);
    if (profileError) throw new Error(`could not delete profile: ${profileError.message}`);

    const { error: authError } = await supabase.auth.admin.deleteUser(userId);
    if (authError) throw new Error(`could not delete auth user: ${authError.message}`);

    return jsonResponse({ deleted: true, appleTokenRevoked });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    const status = msg === "unauthorized" ? 401 : 500;
    return jsonResponse({ error: msg }, status);
  }
});

/// TN3194: exchange the fresh authorization code for Apple tokens, then
/// revoke the refresh token. Client secret = ES256 JWT signed with the
/// team's .p8 key. Returns false (never throws) on any failure -- Apple
/// being unreachable must not block the user's right to erasure; the
/// failure is logged for follow-up.
async function revokeAppleTokens(authorizationCode: string): Promise<boolean> {
  const teamId = Deno.env.get("APPLE_TEAM_ID");
  const keyId = Deno.env.get("APPLE_KEY_ID");
  const privateKeyPEM = Deno.env.get("APPLE_PRIVATE_KEY");
  if (!teamId || !keyId || !privateKeyPEM) {
    console.warn("[delete-account] APPLE_* secrets not configured -- skipping SIWA token revocation");
    return false;
  }

  try {
    const key = await importPKCS8(privateKeyPEM.replace(/\\n/g, "\n"), "ES256");
    const clientSecret = await new SignJWT({})
      .setProtectedHeader({ alg: "ES256", kid: keyId })
      .setIssuer(teamId)
      .setSubject(APPLE_CLIENT_ID)
      .setAudience("https://appleid.apple.com")
      .setIssuedAt()
      .setExpirationTime("5m")
      .sign(key);

    const tokenRes = await fetch("https://appleid.apple.com/auth/token", {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: APPLE_CLIENT_ID,
        client_secret: clientSecret,
        grant_type: "authorization_code",
        code: authorizationCode,
      }),
    });
    if (!tokenRes.ok) {
      console.error(`[delete-account] Apple /auth/token failed: ${tokenRes.status} ${await tokenRes.text()}`);
      return false;
    }
    const tokens = await tokenRes.json() as { refresh_token?: string; access_token?: string };
    const tokenToRevoke = tokens.refresh_token ?? tokens.access_token;
    if (!tokenToRevoke) {
      console.error("[delete-account] Apple /auth/token returned no revocable token");
      return false;
    }

    const revokeRes = await fetch("https://appleid.apple.com/auth/revoke", {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: APPLE_CLIENT_ID,
        client_secret: clientSecret,
        token: tokenToRevoke,
        token_type_hint: tokens.refresh_token ? "refresh_token" : "access_token",
      }),
    });
    if (!revokeRes.ok) {
      console.error(`[delete-account] Apple /auth/revoke failed: ${revokeRes.status} ${await revokeRes.text()}`);
      return false;
    }
    return true;
  } catch (err) {
    console.error(`[delete-account] SIWA revocation error: ${err instanceof Error ? err.message : err}`);
    return false;
  }
}

/// Removes every object under `${userId}/` in `bucket`, paging the listing
/// and batching removals (Storage caps remove() at 1000 per call). Owned
/// objects block auth user deletion, so failures here are fatal upstream
/// by design -- but an empty/missing prefix is a normal no-op.
async function deleteUserObjects(
  supabase: ReturnType<typeof serviceRoleClient>,
  bucket: string,
  userId: string,
): Promise<void> {
  const pageSize = 1000;
  while (true) {
    const { data: objects, error } = await supabase.storage.from(bucket).list(userId, { limit: pageSize });
    if (error) {
      // A bucket that doesn't exist in this environment is a no-op, not
      // a reason to strand deletion.
      console.warn(`[delete-account] list ${bucket}/${userId} failed: ${error.message}`);
      return;
    }
    if (!objects || objects.length === 0) return;
    const paths = objects.map((o) => `${userId}/${o.name}`);
    const { error: removeError } = await supabase.storage.from(bucket).remove(paths);
    if (removeError) throw new Error(`could not delete ${bucket} objects: ${removeError.message}`);
    if (objects.length < pageSize) return;
  }
}

/// GDPR-side analytics erasure -- deletes the PostHog person (and its
/// events) whose distinct_id is the Supabase user id. Best-effort and
/// entirely optional: runs only when POSTHOG_PERSONAL_API_KEY and
/// POSTHOG_PROJECT_ID secrets are configured.
async function deletePostHogPerson(userId: string): Promise<void> {
  const apiKey = Deno.env.get("POSTHOG_PERSONAL_API_KEY");
  const projectId = Deno.env.get("POSTHOG_PROJECT_ID");
  if (!apiKey || !projectId) return;
  const host = Deno.env.get("POSTHOG_API_HOST") ?? "https://us.posthog.com";

  try {
    const lookup = await fetch(
      `${host}/api/projects/${projectId}/persons/?distinct_id=${encodeURIComponent(userId)}`,
      { headers: { Authorization: `Bearer ${apiKey}` } },
    );
    if (!lookup.ok) {
      console.warn(`[delete-account] PostHog person lookup failed: ${lookup.status}`);
      return;
    }
    const found = await lookup.json() as { results?: { id: number }[] };
    for (const person of found.results ?? []) {
      const res = await fetch(
        `${host}/api/projects/${projectId}/persons/${person.id}/?delete_events=true`,
        { method: "DELETE", headers: { Authorization: `Bearer ${apiKey}` } },
      );
      if (!res.ok) console.warn(`[delete-account] PostHog person delete failed: ${res.status}`);
    }
  } catch (err) {
    console.warn(`[delete-account] PostHog cleanup error: ${err instanceof Error ? err.message : err}`);
  }
}
