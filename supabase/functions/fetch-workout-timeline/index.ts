// fetch-workout-timeline
//
// Plain read-only fetch of today's actual recorded workout sessions from
// whichever wearables are connected (Oura, Whoop) -- distinct from
// workout_log, which is what the USER told Soma they did. This is what
// the wearable itself detected/recorded. Body: { date: "YYYY-MM-DD",
// startTime?, endTime? (ISO8601) }. Returns { entries: [{ source, title,
// start_time, duration_minutes, calories, average_heart_rate,
// max_heart_rate }] } sorted by start time. HealthKit's own workouts are
// read on-device by the app directly (Apple doesn't let a server read
// HealthKit), so this function only covers the two server-side providers;
// the client merges both into one timeline.
//
// `startTime`/`endTime`, if given, narrow the window to a specific logged
// workout's exact span (DayDetailView's wearable-HR-matched-to-workout
// feature) instead of the whole day -- Whoop's own API takes an
// arbitrary start/end already, so that window is used directly; Oura's
// workout endpoint only accepts a date, so its records are still fetched
// for the whole day and then filtered here for overlap with the window.
//
// Heart-rate fields: verify against LIVE Whoop/Oura API responses before
// relying on this, not just this comment -- per this repo's standing
// SETUP.md caution about external API shapes drifting. As documented,
// Whoop's workout `score` object includes `average_heart_rate`/
// `max_heart_rate`; Oura's v2 workout collection does not expose heart
// rate at all, so Oura entries always report null for both -- an honest
// gap, not a fabricated number.

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
  average_heart_rate: number | null;
  max_heart_rate: number | null;
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
    const startTime: string | undefined = typeof body.startTime === "string" ? body.startTime : undefined;
    const endTime: string | undefined = typeof body.endTime === "string" ? body.endTime : undefined;

    const supabase = serviceRoleClient();
    const { data: tokens } = await supabase
      .from("wearable_tokens")
      .select("id, provider, access_token, refresh_token, expires_at")
      .eq("user_id", userId);

    const whoopToken = (tokens ?? []).find((t: WearableTokenRow) => t.provider === "whoop");
    const ouraToken = (tokens ?? []).find((t: WearableTokenRow) => t.provider === "oura");

    const [whoopEntries, ouraEntries] = await Promise.all([
      safely("whoop timeline", [], () => whoopToken ? fetchWhoopWorkouts(supabase, whoopToken, date, startTime, endTime) : Promise.resolve([])),
      safely("oura timeline", [], () => ouraToken ? fetchOuraWorkouts(supabase, ouraToken, date, startTime, endTime) : Promise.resolve([])),
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
  startTime: string | undefined,
  endTime: string | undefined,
): Promise<TimelineEntry[]> {
  const accessToken = await ensureFreshWhoopToken(supabase, token);
  if (!accessToken) return [];

  // Whoop's own API already takes an arbitrary start/end -- use the
  // caller's exact window directly when given, instead of the whole day.
  const start = startTime ?? `${date}T00:00:00.000Z`;
  const end = endTime ?? `${date}T23:59:59.999Z`;
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
    const averageHeartRate = r?.score?.average_heart_rate;
    const maxHeartRate = r?.score?.max_heart_rate;
    return {
      source: "whoop",
      title: r.sport_name ?? (r.sport_id !== undefined ? `Sport ${r.sport_id}` : "Workout"),
      start_time: r.start,
      duration_minutes: Math.max(0, Math.round((endMs - startMs) / 60000)),
      calories: typeof kilojoule === "number" ? Math.round(kilojoule * 0.239006) : null,
      average_heart_rate: typeof averageHeartRate === "number" ? Math.round(averageHeartRate) : null,
      max_heart_rate: typeof maxHeartRate === "number" ? Math.round(maxHeartRate) : null,
    };
  });
}

async function fetchOuraWorkouts(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  token: WearableTokenRow,
  date: string,
  startTime: string | undefined,
  endTime: string | undefined,
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

  // Oura's workout endpoint is date-only, so all of today's records come
  // back regardless -- filter here for overlap with the caller's exact
  // window, if one was given, same as the client would otherwise have to.
  const windowStartMs = startTime ? new Date(startTime).getTime() : null;
  const windowEndMs = endTime ? new Date(endTime).getTime() : null;

  // deno-lint-ignore no-explicit-any
  return records
    .filter((r: any) => {
      if (windowStartMs === null || windowEndMs === null) return true;
      const recordStartMs = new Date(r.start_datetime).getTime();
      const recordEndMs = new Date(r.end_datetime).getTime();
      return recordStartMs <= windowEndMs && recordEndMs >= windowStartMs;
    })
    // deno-lint-ignore no-explicit-any
    .map((r: any): TimelineEntry => {
      const startMs = new Date(r.start_datetime).getTime();
      const endMs = new Date(r.end_datetime).getTime();
      return {
        source: "oura",
        title: typeof r.activity === "string" ? capitalize(r.activity) : "Workout",
        start_time: r.start_datetime,
        duration_minutes: Math.max(0, Math.round((endMs - startMs) / 60000)),
        calories: typeof r.calories === "number" ? Math.round(r.calories) : null,
        // Oura's v2 workout collection doesn't expose heart rate -- an
        // honest gap, not a fabricated number.
        average_heart_rate: null,
        max_heart_rate: null,
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
