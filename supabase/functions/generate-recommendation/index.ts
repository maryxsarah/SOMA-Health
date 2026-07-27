// generate-recommendation
//
// Called either by the on-device morning trigger (HealthKit observer /
// BGAppRefreshTask) or manually via the Home screen's "Check now" button.
// Body: { date: "YYYY-MM-DD", healthkit?: { sleepHours, hrvMs, restingHr } }
//
// `date` is supplied by the client in the user's LOCAL calendar day, not
// derived from the server's UTC clock -- otherwise a user near a timezone
// boundary could get a recommendation dated "yesterday" or "tomorrow".
//
// This function does all of the following in one place (see SETUP.md /
// plan notes for why): refreshes stored Whoop/Oura tokens if expired,
// pulls today's recovery/readiness from whichever providers are
// connected, folds in an optional on-device HealthKit snapshot, applies
// the exact decision-engine rules from the spec, and upserts the result.

import { handleOptions, jsonResponse } from "../_shared/cors.ts";
import { requireUser, serviceRoleClient } from "../_shared/clients.ts";

const WHOOP_TOKEN_URL = "https://api.prod.whoop.com/oauth/oauth2/token";
// NOTE: verify these paths against the current Whoop developer dashboard
// at setup time -- Whoop has changed API generation prefixes before.
const WHOOP_RECOVERY_URL = "https://api.prod.whoop.com/developer/v1/recovery";
const WHOOP_CYCLE_URL = "https://api.prod.whoop.com/developer/v1/cycle";
const WHOOP_SLEEP_URL = "https://api.prod.whoop.com/developer/v1/activity/sleep";
const WHOOP_WORKOUT_URL = "https://api.prod.whoop.com/developer/v1/activity/workout";

const OURA_READINESS_URL =
  "https://api.ouraring.com/v2/usercollection/daily_readiness";
const OURA_SLEEP_URL = "https://api.ouraring.com/v2/usercollection/sleep";
const OURA_WORKOUT_URL = "https://api.ouraring.com/v2/usercollection/workout";
const OURA_STRESS_URL = "https://api.ouraring.com/v2/usercollection/daily_stress";

// Whoop's own strain scale is 0-21; 15+ is what Whoop classifies as
// "strenuous". Used as a "trained hard very recently" signal for the load
// cap below, not as a recovery metric.
const WHOOP_HIGH_STRAIN_THRESHOLD = 15;

type Band = "high" | "medium_high" | "medium" | "low";
type Category = "rest" | "light" | "moderate" | "push_hard";
type Source = "whoop" | "oura" | "healthkit";

const MESSAGES: Record<Category, string> = {
  push_hard:
    "You're well recovered — today's a good day to push. Go for a hard workout or high-intensity session.",
  moderate:
    "You're in decent shape today. A moderate cardio session or a solid strength workout (30-45 min) is a good call.",
  light:
    "Take it easier today — a short walk, mobility work, or light yoga (20-30 min) is ideal.",
  rest: "Today's a recovery day. Keep movement light and let your body rest — a gentle walk is plenty.",
};

interface HealthKitPayload {
  sleepHours?: number;
  hrvMs?: number;
  restingHr?: number;
}

interface WearableTokenRow {
  id: string;
  provider: "whoop" | "oura";
  access_token: string;
  refresh_token: string | null;
  expires_at: string | null;
}

Deno.serve(async (req: Request) => {
  const preflight = handleOptions(req);
  if (preflight) return preflight;

  try {
    const userId = await requireUser(req);
    const body = await req.json().catch(() => ({}));
    const date: string | undefined = body.date;
    const healthkit: HealthKitPayload | undefined = body.healthkit;

    if (!date) {
      return jsonResponse({ error: "missing 'date' (YYYY-MM-DD)" }, 400);
    }

    const supabase = serviceRoleClient();

    const { data: tokens } = await supabase
      .from("wearable_tokens")
      .select("id, provider, access_token, refresh_token, expires_at")
      .eq("user_id", userId);

    let whoopRecovery: { recoveryScore: number; hrvMs?: number; restingHr?: number } | null = null;
    let ouraReadiness: number | null = null;
    // True if either provider shows a strenuous session in roughly the
    // last day -- feeds the recent-training-load cap alongside the
    // existing sleep/injury caps.
    let recentHighStrain = false;

    const whoopToken = (tokens ?? []).find((t: WearableTokenRow) => t.provider === "whoop");
    if (whoopToken) {
      const [recovery, whoopSleepHours, whoopLoad] = await Promise.all([
        safely("whoop recovery", null, () => fetchWhoopRecovery(supabase, whoopToken, date)),
        safely("whoop sleep", null, () => fetchWhoopSleepHours(supabase, whoopToken, date)),
        safely(
          "whoop training load",
          { strainScore: null, recentHighStrain: false },
          () => fetchWhoopTrainingLoad(supabase, whoopToken, date),
        ),
      ]);
      whoopRecovery = recovery;
      if (whoopLoad.recentHighStrain) recentHighStrain = true;
      if (recovery || whoopSleepHours !== null || whoopLoad.strainScore !== null) {
        await upsertSnapshot(supabase, userId, date, "whoop", {
          recovery_score: recovery?.recoveryScore,
          hrv_ms: recovery?.hrvMs,
          resting_hr: recovery?.restingHr,
          sleep_hours: whoopSleepHours ?? undefined,
          strain_score: whoopLoad.strainScore ?? undefined,
        });
      }
    }

    const ouraToken = (tokens ?? []).find((t: WearableTokenRow) => t.provider === "oura");
    if (ouraToken) {
      const emptySleepData = { sleepHours: null, hrvMs: null, restingHr: null };
      const [readiness, ouraSleep, ouraLoad, ouraStress] = await Promise.all([
        safely("oura readiness", null, () => fetchOuraReadiness(supabase, ouraToken, date)),
        safely("oura sleep", emptySleepData, () => fetchOuraSleepData(supabase, ouraToken, date)),
        safely(
          "oura training load",
          { strainScore: null, recentHighStrain: false },
          () => fetchOuraTrainingLoad(supabase, ouraToken, date),
        ),
        safely("oura stress", null, () => fetchOuraStress(supabase, ouraToken, date)),
      ]);
      ouraReadiness = readiness;
      if (ouraLoad.recentHighStrain) recentHighStrain = true;
      if (
        readiness !== null || ouraSleep.sleepHours !== null || ouraLoad.strainScore !== null ||
        ouraStress !== null
      ) {
        await upsertSnapshot(supabase, userId, date, "oura", {
          readiness_score: readiness ?? undefined,
          sleep_hours: ouraSleep.sleepHours ?? undefined,
          hrv_ms: ouraSleep.hrvMs ?? undefined,
          resting_hr: ouraSleep.restingHr ?? undefined,
          strain_score: ouraLoad.strainScore ?? undefined,
          stress_score: ouraStress ?? undefined,
        });
      }
    }

    if (healthkit) {
      await upsertSnapshot(supabase, userId, date, "healthkit", {
        sleep_hours: healthkit.sleepHours,
        hrv_ms: healthkit.hrvMs,
        resting_hr: healthkit.restingHr,
      });
    }

    // Sleep hours for the safety cap / rest-vs-light split: prefer
    // whichever connected source actually reported it today.
    const { data: todaysRows } = await supabase
      .from("daily_snapshot")
      .select("source, sleep_hours")
      .eq("user_id", userId)
      .eq("date", date);

    const sleepHours = pickSleepHours(todaysRows ?? [], healthkit);

    // Injury-based intensity cap: any noted injury caps the category at
    // moderate max for the day, same safety-first pattern as the sleep cap.
    const { data: userRow } = await supabase
      .from("users")
      .select("injury_tags")
      .eq("id", userId)
      .maybeSingle();
    const hasInjury = ((userRow?.injury_tags as string[] | null) ?? []).length > 0;

    let band: Band;
    let source: Source;
    let clearlyPoorRecovery = false;

    if (whoopRecovery) {
      band = bandFromWhoop(whoopRecovery.recoveryScore);
      source = "whoop";
      clearlyPoorRecovery = whoopRecovery.recoveryScore < 20;
    } else if (ouraReadiness !== null) {
      band = bandFromOura(ouraReadiness);
      source = "oura";
      clearlyPoorRecovery = ouraReadiness < 50;
    } else if (healthkit) {
      const baseline = await fetchHrvBaseline(supabase, userId, date);
      band = bandFromHealthKit(healthkit, baseline);
      source = "healthkit";
      clearlyPoorRecovery = baseline !== null && healthkit.hrvMs !== undefined
        ? healthkit.hrvMs < baseline * 0.6
        : false;
    } else {
      return jsonResponse(
        { error: "no data available for today from any source" },
        422,
      );
    }

    // Recorded from the pre-cap band -- this is the diagnostic "why"
    // (e.g. "whoop_high"), independent of whether the sleep cap then
    // downgraded the final category. Matches the check constraint on
    // daily_recommendation.reason.
    const reason = `${source}_${band}`;
    const { category, sleepCapApplied, injuryCapApplied, loadCapApplied } = mapBandToCategory(
      band,
      sleepHours,
      clearlyPoorRecovery,
      hasInjury,
      recentHighStrain,
    );
    const message = MESSAGES[category];

    await supabase
      .from("daily_recommendation")
      .upsert(
        {
          user_id: userId,
          date,
          category,
          message,
          reason,
          sleep_cap_applied: sleepCapApplied,
          injury_cap_applied: injuryCapApplied,
          load_cap_applied: loadCapApplied,
        },
        { onConflict: "user_id,date" },
      );

    // snake_case in the response to match the PostgREST row shape returned
    // by HomeView's plain "fetch today's recommendation" read -- the app
    // uses one Codable model for both paths.
    return jsonResponse({
      date,
      category,
      message,
      reason,
      sleep_cap_applied: sleepCapApplied,
      injury_cap_applied: injuryCapApplied,
      load_cap_applied: loadCapApplied,
    });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    const status = msg === "unauthorized" ? 401 : 500;
    return jsonResponse({ error: msg }, status);
  }
});

// -- Decision engine ------------------------------------------------------

function bandFromWhoop(recoveryScore: number): Band {
  if (recoveryScore >= 67) return "high";
  if (recoveryScore >= 34) return "medium";
  return "low";
}

function bandFromOura(readinessScore: number): Band {
  if (readinessScore >= 85) return "high";
  if (readinessScore >= 70) return "medium_high";
  if (readinessScore >= 60) return "medium";
  return "low";
}

function bandFromHealthKit(
  hk: HealthKitPayload,
  baselineHrvMs: number | null,
): Band {
  const sleep = hk.sleepHours ?? null;

  // No 30-day baseline yet (e.g. first few days of HealthKit-only data):
  // default to a conservative "medium" rather than guessing push_hard.
  if (baselineHrvMs === null || hk.hrvMs === undefined) {
    if (sleep !== null && sleep < 6) return "low";
    return "medium";
  }

  const hrvRatio = hk.hrvMs / baselineHrvMs;

  if (hrvRatio >= 0.9 && sleep !== null && sleep >= 7) return "high";
  if (hrvRatio < 0.8 || (sleep !== null && sleep < 6)) return "low";
  return "medium";
}

function mapBandToCategory(
  band: Band,
  sleepHours: number | null,
  clearlyPoorRecovery: boolean,
  hasInjury: boolean,
  recentHighStrain: boolean,
): { category: Category; sleepCapApplied: boolean; injuryCapApplied: boolean; loadCapApplied: boolean } {
  let effectiveBand = band;
  let sleepCapApplied = false;
  let injuryCapApplied = false;
  let loadCapApplied = false;

  // Sleep safety cap: never push_hard on severe sleep deprivation.
  if (effectiveBand === "high" && sleepHours !== null && sleepHours < 5.5) {
    effectiveBand = "medium";
    sleepCapApplied = true;
  }

  // Injury safety cap: never push_hard with an active injury noted,
  // same pattern as the sleep cap. Independent of it -- both can apply.
  if (effectiveBand === "high" && hasInjury) {
    effectiveBand = "medium";
    injuryCapApplied = true;
  }

  // Recent training load cap: never push_hard the day right after a
  // strenuous Whoop workout or an Oura "hard"-intensity session, even if
  // this morning's recovery/readiness looks strong -- avoids stacking two
  // max-effort days back to back. Independent of the other two caps.
  if (effectiveBand === "high" && recentHighStrain) {
    effectiveBand = "medium";
    loadCapApplied = true;
  }

  if (effectiveBand === "high") {
    return { category: "push_hard", sleepCapApplied, injuryCapApplied, loadCapApplied };
  }
  if (effectiveBand === "medium_high" || effectiveBand === "medium") {
    return { category: "moderate", sleepCapApplied, injuryCapApplied, loadCapApplied };
  }

  // effectiveBand === "low": split into light vs rest.
  const severelyShortSleep = sleepHours !== null && sleepHours < 5.5;
  const category = severelyShortSleep || clearlyPoorRecovery ? "rest" : "light";
  return { category, sleepCapApplied, injuryCapApplied, loadCapApplied };
}

function pickSleepHours(
  rows: { source: string; sleep_hours: number | null }[],
  healthkit: HealthKitPayload | undefined,
): number | null {
  const bySource = (source: string) =>
    rows.find((r) => r.source === source)?.sleep_hours ?? null;
  return (
    bySource("whoop") ??
    bySource("oura") ??
    bySource("healthkit") ??
    healthkit?.sleepHours ??
    null
  );
}

async function fetchHrvBaseline(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  userId: string,
  date: string,
): Promise<number | null> {
  const end = new Date(date);
  const start = new Date(end);
  start.setDate(start.getDate() - 30);
  const startStr = start.toISOString().slice(0, 10);
  const endStr = new Date(end.getTime() - 86400000).toISOString().slice(0, 10);

  const { data } = await supabase
    .from("daily_snapshot")
    .select("hrv_ms")
    .eq("user_id", userId)
    .eq("source", "healthkit")
    .gte("date", startStr)
    .lte("date", endStr)
    .not("hrv_ms", "is", null);

  if (!data || data.length === 0) return null;
  const sum = data.reduce((acc: number, r: { hrv_ms: number }) => acc + r.hrv_ms, 0);
  return sum / data.length;
}

function addDays(dateStr: string, days: number): string {
  const d = new Date(`${dateStr}T00:00:00.000Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}

// Every external Whoop/Oura call goes through this. Before this file grew
// to 3 calls per provider (recovery/readiness + sleep + workout/cycle, all
// via Promise.all), a single slow call just meant a slightly slower
// response. Now, with nothing bounding any individual call, ONE hanging or
// slow endpoint blocks the whole Promise.all -- and by extension the
// user's entire "Check now" -- until Supabase's own function timeout
// kills it. A hard per-call timeout, paired with the try/catch wrapper
// below, means a single misbehaving endpoint degrades gracefully (that
// one signal is just missing) instead of stalling or failing everything.
const PROVIDER_FETCH_TIMEOUT_MS = 8000;

async function fetchWithTimeout(url: string, options: RequestInit): Promise<Response> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), PROVIDER_FETCH_TIMEOUT_MS);
  try {
    return await fetch(url, { ...options, signal: controller.signal });
  } finally {
    clearTimeout(timeout);
  }
}

/// Runs a provider-fetch function and swallows ANY failure (timeout,
/// network error, malformed JSON) into the given fallback, logging the
/// cause -- one provider signal being unavailable should never crash or
/// stall the whole recommendation.
async function safely<T>(label: string, fallback: T, fn: () => Promise<T>): Promise<T> {
  try {
    return await fn();
  } catch (err) {
    console.error(`${label} failed, continuing without it:`, err instanceof Error ? err.message : err);
    return fallback;
  }
}

// -- Provider fetch/refresh -------------------------------------------------

async function fetchWhoopRecovery(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  token: WearableTokenRow,
  date: string,
): Promise<{ recoveryScore: number; hrvMs?: number; restingHr?: number } | null> {
  const accessToken = await ensureFreshWhoopToken(supabase, token);
  if (!accessToken) return null;

  const start = `${date}T00:00:00.000Z`;
  const end = `${date}T23:59:59.999Z`;
  const res = await fetchWithTimeout(
    `${WHOOP_RECOVERY_URL}?start=${start}&end=${end}&limit=1`,
    { headers: { Authorization: `Bearer ${accessToken}` } },
  );
  if (!res.ok) return null;
  const json = await res.json();
  const record = json?.records?.[0] ?? json?.[0];
  if (!record?.score) return null;

  return {
    recoveryScore: record.score.recovery_score,
    hrvMs: record.score.hrv_rmssd_milli,
    restingHr: record.score.resting_heart_rate,
  };
}

/// Real sleep hours from Whoop's own sleep data, used instead of relying
/// on an on-device HealthKit reading for Whoop users -- feeds the same
/// sleep safety cap as HealthKit/Oura sleep does.
async function fetchWhoopSleepHours(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  token: WearableTokenRow,
  date: string,
): Promise<number | null> {
  const accessToken = await ensureFreshWhoopToken(supabase, token);
  if (!accessToken) return null;

  const start = `${addDays(date, -1)}T00:00:00.000Z`;
  const end = `${date}T23:59:59.999Z`;
  const res = await fetchWithTimeout(
    `${WHOOP_SLEEP_URL}?start=${start}&end=${end}&limit=5`,
    { headers: { Authorization: `Bearer ${accessToken}` } },
  );
  if (!res.ok) return null;
  const json = await res.json();
  const record = (json?.records ?? json ?? [])[0];
  const stages = record?.score?.stage_summary;
  if (!stages) return null;

  const totalMs = (stages.total_light_sleep_time_milli ?? 0) +
    (stages.total_slow_wave_sleep_time_milli ?? 0) +
    (stages.total_rem_sleep_time_milli ?? 0);
  return totalMs > 0 ? totalMs / 3_600_000 : null;
}

/// Yesterday's Whoop day strain (from the cycle endpoint) plus whether any
/// logged workout in the last ~day crossed the "strenuous" threshold --
/// together these feed the recent-training-load cap.
async function fetchWhoopTrainingLoad(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  token: WearableTokenRow,
  date: string,
): Promise<{ strainScore: number | null; recentHighStrain: boolean }> {
  const accessToken = await ensureFreshWhoopToken(supabase, token);
  if (!accessToken) return { strainScore: null, recentHighStrain: false };

  const start = `${addDays(date, -1)}T00:00:00.000Z`;
  const end = `${date}T23:59:59.999Z`;

  const [cycleRes, workoutRes] = await Promise.all([
    fetchWithTimeout(`${WHOOP_CYCLE_URL}?start=${start}&end=${end}&limit=2`, {
      headers: { Authorization: `Bearer ${accessToken}` },
    }),
    fetchWithTimeout(`${WHOOP_WORKOUT_URL}?start=${start}&end=${end}&limit=5`, {
      headers: { Authorization: `Bearer ${accessToken}` },
    }),
  ]);

  let strainScore: number | null = null;
  if (cycleRes.ok) {
    const cycleJson = await cycleRes.json();
    const record = (cycleJson?.records ?? cycleJson ?? [])[0];
    strainScore = record?.score?.strain ?? null;
  }

  let recentHighStrain = false;
  if (workoutRes.ok) {
    const workoutJson = await workoutRes.json();
    const records = workoutJson?.records ?? workoutJson ?? [];
    // deno-lint-ignore no-explicit-any
    recentHighStrain = records.some((r: any) => (r?.score?.strain ?? 0) >= WHOOP_HIGH_STRAIN_THRESHOLD);
  }

  return { strainScore, recentHighStrain };
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

async function fetchOuraReadiness(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  token: WearableTokenRow,
  date: string,
): Promise<number | null> {
  const accessToken = await ensureFreshOuraToken(supabase, token);
  if (!accessToken) return null;

  const res = await fetchWithTimeout(
    `${OURA_READINESS_URL}?start_date=${date}&end_date=${date}`,
    { headers: { Authorization: `Bearer ${accessToken}` } },
  );
  if (!res.ok) return null;
  const json = await res.json();
  const record = json?.data?.[0];
  return record?.score ?? null;
}

/// Real sleep hours PLUS HRV and resting HR from Oura's sleep collection
/// (the longest session in the window, i.e. last night's main sleep) --
/// sleep feeds the same safety cap as HealthKit/Whoop sleep does; HRV and
/// resting HR were previously never populated for Oura snapshot rows at
/// all (only Whoop's recovery endpoint provided those).
async function fetchOuraSleepData(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  token: WearableTokenRow,
  date: string,
): Promise<{ sleepHours: number | null; hrvMs: number | null; restingHr: number | null }> {
  const empty = { sleepHours: null, hrvMs: null, restingHr: null };
  const accessToken = await ensureFreshOuraToken(supabase, token);
  if (!accessToken) return empty;

  const startDate = addDays(date, -1);
  const res = await fetchWithTimeout(
    `${OURA_SLEEP_URL}?start_date=${startDate}&end_date=${date}`,
    { headers: { Authorization: `Bearer ${accessToken}` } },
  );
  if (!res.ok) return empty;
  const json = await res.json();
  const records = json?.data ?? [];
  if (records.length === 0) return empty;

  // deno-lint-ignore no-explicit-any
  const longest = records.reduce((a: any, b: any) =>
    (b.total_sleep_duration ?? 0) > (a.total_sleep_duration ?? 0) ? b : a
  );
  return {
    sleepHours: longest.total_sleep_duration ? longest.total_sleep_duration / 3600 : null,
    hrvMs: longest.average_hrv ?? null,
    // Lowest overnight HR is the standard resting-HR proxy; Oura's sleep
    // endpoint doesn't expose a separately-labeled "resting_heart_rate".
    restingHr: longest.lowest_heart_rate ?? null,
  };
}

/// Minutes spent in a high-stress state today -- Oura-specific; Whoop has
/// no equivalent metric.
async function fetchOuraStress(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  token: WearableTokenRow,
  date: string,
): Promise<number | null> {
  const accessToken = await ensureFreshOuraToken(supabase, token);
  if (!accessToken) return null;

  const res = await fetchWithTimeout(
    `${OURA_STRESS_URL}?start_date=${date}&end_date=${date}`,
    { headers: { Authorization: `Bearer ${accessToken}` } },
  );
  if (!res.ok) return null;
  const json = await res.json();
  const record = json?.data?.[0];
  if (!record?.stress_high) return null;
  // stress_high is reported in seconds; store as minutes for readability.
  return Math.round(record.stress_high / 60);
}

/// Oura doesn't expose a single 0-21 strain number the way Whoop does, so
/// the count of recent "hard"-intensity workouts is used as a rough load
/// proxy; a hard-intensity session in the last ~day also feeds the
/// recent-training-load cap directly.
async function fetchOuraTrainingLoad(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  token: WearableTokenRow,
  date: string,
): Promise<{ strainScore: number | null; recentHighStrain: boolean }> {
  const accessToken = await ensureFreshOuraToken(supabase, token);
  if (!accessToken) return { strainScore: null, recentHighStrain: false };

  const startDate = addDays(date, -1);
  const res = await fetchWithTimeout(
    `${OURA_WORKOUT_URL}?start_date=${startDate}&end_date=${date}`,
    { headers: { Authorization: `Bearer ${accessToken}` } },
  );
  if (!res.ok) return { strainScore: null, recentHighStrain: false };
  const json = await res.json();
  const records = json?.data ?? [];

  // deno-lint-ignore no-explicit-any
  const hardCount = records.filter((r: any) => r?.intensity === "hard").length;
  return { strainScore: hardCount || null, recentHighStrain: hardCount > 0 };
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

async function upsertSnapshot(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  userId: string,
  date: string,
  source: "whoop" | "oura" | "healthkit",
  fields: Record<string, number | undefined>,
) {
  await supabase
    .from("daily_snapshot")
    .upsert(
      { user_id: userId, date, source, ...fields },
      { onConflict: "user_id,date,source" },
    );
}
