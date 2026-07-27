// fetch-workout-timeline
//
// Plain read-only fetch of today's actual recorded workout sessions from
// whichever wearables are connected (Oura, Whoop) -- distinct from
// workout_log, which is what the USER told Soma they did. This is what
// the wearable itself detected/recorded. Body: { date: "YYYY-MM-DD" }.
// Returns { entries: [{ source, title, start_time, duration_minutes,
// calories }] } sorted by start time. HealthKit's own workouts are read
// on-device by the app directly (Apple doesn't let a server read
// HealthKit), so this function only covers the two server-side providers;
// the client merges both into one timeline.

import { handleOptions, jsonResponse } from "../_shared/cors.ts";
import { requireUser, serviceRoleClient } from "../_shared/clients.ts";

const WHOOP_TOKEN_URL = "https://api.prod.whoop.com/oauth/oauth2/token";
const WHOOP_WORKOUT_URL = "https://api.prod.whoop.com/developer/v1/activity/workout";
const OURA_WORKOUT_URL = "https://api.ouraring.com/v2/usercollection/workout";

const FETCH_TIMEOUT_MS = 8000;

interface WearableTokenRow {
  id: string;
  provider: "whoop" | "oura";
  access_token: string;
  refresh_token: string | null;
  expires_at: string | null;
}

interface TimelineEntry {
  source: "whoop" | "oura";
  title: string;
  start_time: string;
  duration_minutes: number;
  calories: number | null;
}

Deno.serve(async (req: Request) => {
  const preflight = handleOptions(req);
  if (preflight) return preflight;

  try {
    const userId = await requireUser(req);
    const body = await req.json().catch(() => ({}));
    const date: string | undefined = body.date;
    if (!date) {
      return jsonResponse({ error: "missing 'date' (YYYY-MM-DD)" }, 400);
    }

    const supabase = serviceRoleClient();
    const { data: tokens } = await supabase
      .from("wearable_tokens")
      .select("id, provider, access_token, refresh_token, expires_at")
      .eq("user_id", userId);

    const whoopToken = (tokens ?? []).find((t: WearableTokenRow) => t.provider === "whoop");
    const ouraToken = (tokens ?? []).find((t: WearableTokenRow) => t.provider === "oura");

    const [whoopEntries, ouraEntries] = await Promise.all([
      safely("whoop timeline", [], () => whoopToken ? fetchWhoopWorkouts(supabase, whoopToken, date) : Promise.resolve([])),
      safely("oura timeline", [], () => ouraToken ? fetchOuraWorkouts(supabase, ouraToken, date) : Promise.resolve([])),
    ]);

    const entries = [...whoopEntries, ...ouraEntries].sort((a, b) => a.start_time.localeCompare(b.start_time));
    return jsonResponse({ entries });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    const status = msg === "unauthorized" ? 401 : 500;
    return jsonResponse({ error: msg }, status);
  }
});

async function safely<T>(label: string, fallback: T, fn: () => Promise<T>): Promise<T> {
  try {
    return await fn();
  } catch (err) {
    console.error(`${label} failed, continuing without it:`, err instanceof Error ? err.message : err);
    return fallback;
  }
}

async function fetchWithTimeout(url: string, options: RequestInit): Promise<Response> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);
  try {
    return await fetch(url, { ...options, signal: controller.signal });
  } finally {
    clearTimeout(timeout);
  }
}

async function fetchWhoopWorkouts(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  token: WearableTokenRow,
  date: string,
): Promise<TimelineEntry[]> {
  const accessToken = await ensureFreshWhoopToken(supabase, token);
  if (!accessToken) return [];

  const start = `${date}T00:00:00.000Z`;
  const end = `${date}T23:59:59.999Z`;
  const res = await fetchWithTimeout(
    `${WHOOP_WORKOUT_URL}?start=${start}&end=${end}&limit=25`,
    { headers: { Authorization: `Bearer ${accessToken}` } },
  );
  if (!res.ok) return [];
  const json = await res.json();
  const records = json?.records ?? json ?? [];

  // deno-lint-ignore no-explicit-any
  return records.map((r: any): TimelineEntry => {
    const startMs = new Date(r.start).getTime();
    const endMs = new Date(r.end).getTime();
    const kilojoule = r?.score?.kilojoule;
    return {
      source: "whoop",
      title: r.sport_name ?? (r.sport_id !== undefined ? `Sport ${r.sport_id}` : "Workout"),
      start_time: r.start,
      duration_minutes: Math.max(0, Math.round((endMs - startMs) / 60000)),
      calories: typeof kilojoule === "number" ? Math.round(kilojoule * 0.239006) : null,
    };
  });
}

async function fetchOuraWorkouts(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  token: WearableTokenRow,
  date: string,
): Promise<TimelineEntry[]> {
  const accessToken = await ensureFreshOuraToken(supabase, token);
  if (!accessToken) return [];

  const res = await fetchWithTimeout(
    `${OURA_WORKOUT_URL}?start_date=${date}&end_date=${date}`,
    { headers: { Authorization: `Bearer ${accessToken}` } },
  );
  if (!res.ok) return [];
  const json = await res.json();
  const records = json?.data ?? [];

  // deno-lint-ignore no-explicit-any
  return records.map((r: any): TimelineEntry => {
    const startMs = new Date(r.start_datetime).getTime();
    const endMs = new Date(r.end_datetime).getTime();
    return {
      source: "oura",
      title: typeof r.activity === "string" ? capitalize(r.activity) : "Workout",
      start_time: r.start_datetime,
      duration_minutes: Math.max(0, Math.round((endMs - startMs) / 60000)),
      calories: typeof r.calories === "number" ? Math.round(r.calories) : null,
    };
  });
}

function capitalize(s: string): string {
  return s.charAt(0).toUpperCase() + s.slice(1).replace(/_/g, " ");
}

async function ensureFreshWhoopToken(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  token: WearableTokenRow,
): Promise<string | null> {
  const isExpired = token.expires_at
    ? new Date(token.expires_at).getTime() < Date.now() + 60_000
    : false;
  if (!isExpired) return token.access_token;
  if (!token.refresh_token) return null;

  const clientId = Deno.env.get("WHOOP_CLIENT_ID")!;
  const clientSecret = Deno.env.get("WHOOP_CLIENT_SECRET")!;

  const res = await fetchWithTimeout(WHOOP_TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "refresh_token",
      refresh_token: token.refresh_token,
      client_id: clientId,
      client_secret: clientSecret,
    }),
  });
  if (!res.ok) return null;
  const json = await res.json();

  const expiresAt = new Date(Date.now() + json.expires_in * 1000).toISOString();
  await supabase
    .from("wearable_tokens")
    .update({
      access_token: json.access_token,
      refresh_token: json.refresh_token ?? token.refresh_token,
      expires_at: expiresAt,
    })
    .eq("id", token.id);

  return json.access_token;
}

async function ensureFreshOuraToken(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  token: WearableTokenRow,
): Promise<string | null> {
  const isExpired = token.expires_at
    ? new Date(token.expires_at).getTime() < Date.now() + 60_000
    : false;
  if (!isExpired) return token.access_token;
  if (!token.refresh_token) return null;

  const clientId = Deno.env.get("OURA_CLIENT_ID")!;
  const clientSecret = Deno.env.get("OURA_CLIENT_SECRET")!;

  const res = await fetchWithTimeout("https://api.ouraring.com/oauth/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "refresh_token",
      refresh_token: token.refresh_token,
      client_id: clientId,
      client_secret: clientSecret,
    }),
  });
  if (!res.ok) return null;
  const json = await res.json();

  const expiresAt = new Date(Date.now() + json.expires_in * 1000).toISOString();
  await supabase
    .from("wearable_tokens")
    .update({
      access_token: json.access_token,
      refresh_token: json.refresh_token ?? token.refresh_token,
      expires_at: expiresAt,
    })
    .eq("id", token.id);

  return json.access_token;
}
