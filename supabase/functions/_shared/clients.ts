import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

// SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY are injected
// automatically into every Edge Function's environment by the Supabase
// runtime -- no manual `supabase secrets set` needed for these three.
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

/**
 * Client scoped to the calling user's JWT. Use this only to resolve
 * `auth.getUser()` -- RLS makes it safe for nothing else matters here since
 * all actual reads/writes go through the service-role client below.
 */
export function callerClient(req: Request): SupabaseClient {
  const authHeader = req.headers.get("Authorization") ?? "";
  return createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });
}

/**
 * Full-privilege client that bypasses RLS. Used for every read/write to
 * wearable_tokens, daily_snapshot, and daily_recommendation. Never expose
 * this client or its key to the iOS app.
 */
export function serviceRoleClient(): SupabaseClient {
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false },
  });
}

/**
 * Standing rule: NEVER use Supabase Auth's `user_metadata` / `app_metadata`
 * (fields embedded in the JWT) for any server-side authorization or
 * eligibility decision (subscription status, referral bonus, safety
 * flags, etc.). Both are client-settable via `supabase.auth.updateUser`
 * and must be treated as untrusted input. Every such decision in this
 * codebase reads instead from the `users`/`daily_snapshot`/etc. Postgres
 * tables via `serviceRoleClient()` above, which only Edge Functions can
 * write -- that's the actual source of truth.
 */
export async function requireUser(req: Request): Promise<string> {
  const { data, error } = await callerClient(req).auth.getUser();
  if (error || !data.user) {
    throw new Error("unauthorized");
  }
  return data.user.id;
}
