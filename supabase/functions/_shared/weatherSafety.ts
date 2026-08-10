// Real feedback: "When the user is in Dubai, and the temperature in Dubai
// is 42 degrees celsius, SOMA should not recommend a run outside, as this
// could be a health risk." Two independent pieces:
//
//   1. assessOutdoorSafety / isOutdoorCardioExerciseName -- pure,
//      unit-tested predicates over already-fetched weather data and an
//      exercise name. No network, no Supabase.
//   2. fetchOutdoorSafetyForCity -- the actual network calls (geocode a
//      city name, then fetch current weather for it), best-effort and
//      never blocking: any failure (city unset, geocoding miss, network
//      error, timeout) resolves to null, which callers treat exactly like
//      "safe" -- this is an enhancement layered on top of generation,
//      never a hard requirement the way an injury exclusion is.
//
// Uses Open-Meteo (open-meteo.com) for both geocoding and weather -- free
// and keyless for this volume of non-commercial use, so this needed no
// API key setup on the ops side, unlike most weather providers.

const GEOCODE_URL = "https://geocoding-api.open-meteo.com/v1/search";
const WEATHER_URL = "https://api.open-meteo.com/v1/forecast";
const FETCH_TIMEOUT_MS = 4000;

export interface OutdoorSafetyAssessment {
  safe: boolean;
  /// Human-readable, only set when unsafe -- shown to the user as-is (same
  /// "surfaced note" pattern as every other cap's message in this codebase).
  reason?: string;
}

// DRAFTED, NOT EXPERT-REVIEWED -- same convention as this codebase's other
// invented thresholds (e.g. generate-recommendation's HIGH_STRESS_MINUTES).
// Apparent ("feels like") temperature is used over raw air temperature
// since it factors in humidity, which is what actually drives heat-illness
// risk during exertion -- NOAA's heat-index "danger" tier starts around
// 39°C/103°F; this sits a little more conservative given exercise raises
// core temperature further on top of ambient heat. Matches the real
// feedback example (Dubai at 42°C).
const DANGEROUS_HEAT_APPARENT_C = 38;
const DANGEROUS_COLD_APPARENT_C = -15;
// WMO weather codes (Open-Meteo's `weather_code`) for genuinely hazardous
// conditions to be outside in, not just "a bit of rain": thunderstorm
// (95/96/99), heavy snow (75/86), dense freezing rain/drizzle (66/67),
// violent rain showers (82).
const HAZARDOUS_WEATHER_CODES = new Set([66, 67, 75, 82, 86, 95, 96, 99]);

export function assessOutdoorSafety(
  temperatureC: number | null,
  apparentTemperatureC: number | null,
  weatherCode: number | null,
): OutdoorSafetyAssessment {
  const apparent = apparentTemperatureC ?? temperatureC;
  if (apparent !== null && apparent >= DANGEROUS_HEAT_APPARENT_C) {
    return {
      safe: false,
      reason: `It's ${Math.round(apparent)}°C (feels like) right now -- too hot for safe outdoor cardio.`,
    };
  }
  if (apparent !== null && apparent <= DANGEROUS_COLD_APPARENT_C) {
    return {
      safe: false,
      reason: `It's ${Math.round(apparent)}°C (feels like) right now -- too cold for safe outdoor cardio.`,
    };
  }
  if (weatherCode !== null && HAZARDOUS_WEATHER_CODES.has(weatherCode)) {
    return { safe: false, reason: "Hazardous weather conditions right now -- outdoor cardio isn't safe." };
  }
  return { safe: true };
}

// Verified against the LIVE exercise_library table's actual names (not
// guessed): "Bicycling" (equipment: other -- a real outdoor bike) vs.
// "Bicycling, Stationary" (equipment: machine); "Trail Running/Walking"
// vs. "Running, Treadmill" / "Jogging, Treadmill". The library is mostly
// gym/strength content, so outdoor-cardio entries are a small, specific
// set, not a broad category -- a blunt single-keyword blocklist would
// have wrongly caught the safe indoor equivalents too (exerciseLibraryMatch
// .ts's exclusion mechanism is plain substring matching with no
// equipment-awareness), hence the dual-condition check below rather than
// reusing that same excludedKeywords plumbing directly.
const OUTDOOR_SIGNAL_KEYWORDS = ["running", "jog", "bicycling", "cycling", "trail"];
const INDOOR_QUALIFIER_KEYWORDS = ["treadmill", "stationary", "recumbent", "machine", "indoor", "spin bike"];

/**
 * True when an exercise NAME implies genuinely outdoor cardio -- needs an
 * outdoor-cardio signal AND the absence of an indoor-equipment qualifier.
 * Not exhaustive (a future exercise name outside this pattern could slip
 * through in either direction) -- a deliberately conservative middle
 * ground given what the exclusion mechanism this feeds can express.
 */
export function isOutdoorCardioExerciseName(name: string): boolean {
  const lower = name.toLowerCase();
  const hasOutdoorSignal = OUTDOOR_SIGNAL_KEYWORDS.some((kw) => lower.includes(kw));
  const hasIndoorQualifier = INDOOR_QUALIFIER_KEYWORDS.some((kw) => lower.includes(kw));
  return hasOutdoorSignal && !hasIndoorQualifier;
}

async function fetchWithTimeout(url: string): Promise<Response | null> {
  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);
    try {
      const res = await fetch(url, { signal: controller.signal });
      return res.ok ? res : null;
    } finally {
      clearTimeout(timeout);
    }
  } catch {
    // Network error, timeout, DNS failure, whatever -- best-effort, same
    // fail-open-to-null posture as the rest of this module.
    return null;
  }
}

async function geocodeCity(city: string, countryCode: string | null): Promise<{ latitude: number; longitude: number } | null> {
  const params = new URLSearchParams({ name: city, count: "1", language: "en", format: "json" });
  if (countryCode) params.set("country_code", countryCode);
  const res = await fetchWithTimeout(`${GEOCODE_URL}?${params.toString()}`);
  if (!res) return null;
  // deno-lint-ignore no-explicit-any
  const data: any = await res.json().catch(() => null);
  const first = data?.results?.[0];
  if (!first || typeof first.latitude !== "number" || typeof first.longitude !== "number") return null;
  return { latitude: first.latitude, longitude: first.longitude };
}

/**
 * The one function callers actually use. `city`/`countryCode` come
 * straight from `users.city`/`users.country`. Returns null (never throws)
 * for every failure mode -- no city on file, geocoding miss, network
 * error -- so callers can uniformly treat null the same as "no weather
 * signal today, proceed as normal."
 */
export async function fetchOutdoorSafetyForCity(
  city: string | null,
  countryCode: string | null,
): Promise<OutdoorSafetyAssessment | null> {
  if (!city) return null;
  const location = await geocodeCity(city, countryCode);
  if (!location) return null;

  const params = new URLSearchParams({
    latitude: String(location.latitude),
    longitude: String(location.longitude),
    current: "temperature_2m,apparent_temperature,weather_code",
    temperature_unit: "celsius",
  });
  const res = await fetchWithTimeout(`${WEATHER_URL}?${params.toString()}`);
  if (!res) return null;
  // deno-lint-ignore no-explicit-any
  const data: any = await res.json().catch(() => null);
  const current = data?.current;
  if (!current) return null;

  return assessOutdoorSafety(
    typeof current.temperature_2m === "number" ? current.temperature_2m : null,
    typeof current.apparent_temperature === "number" ? current.apparent_temperature : null,
    typeof current.weather_code === "number" ? current.weather_code : null,
  );
}
