// HealthKit band assessment, split out of index.ts so it can be exercised
// directly -- importing index.ts runs Deno.serve and binds a port, which
// makes the decision logic that matters most here untestable in place.
// Same co-location pattern as generate-gym-workout/templates.ts.

export type Band = "high" | "medium_high" | "medium" | "low";
export type DataConfidence = "high" | "low";

export interface HealthKitPayload {
  sleepHours?: number;
  hrvMs?: number;
  restingHr?: number;
}

/**
 * Scores whatever signals HealthKit actually reported today, instead of
 * demanding a fixed set.
 *
 * The previous version required `sleep >= 7` for a "high" band. Apple's
 * asleep* categories only exist if an Apple Watch was worn overnight, so for
 * every user who takes the watch off at night `sleep` is null and "high" was
 * unreachable -- combined with a self-referential HRV baseline, "medium" was
 * the ONLY outcome the function could ever return. That is what the
 * "I always get the same recommendation" reports were.
 *
 * Design notes, from how Oura and Whoop actually work:
 *
 * - Each available signal contributes points; missing signals contribute
 *   nothing rather than blocking an outcome. Oura deliberately spreads
 *   readiness across several signals for exactly this reason, and weights
 *   HRV at under 5%. Whoop's HRV-dominant model works only because Whoop
 *   controls when HRV is sampled -- we do not.
 * - Resting heart rate carries the most weight here. It is recorded daily,
 *   is far more stable than SDNN, and elevation above personal baseline is a
 *   well-established fatigue/illness signal.
 * - HRV contributes, but cautiously. Apple reports SDNN, not the RMSSD every
 *   other recovery tracker uses, and passive Apple Watch sampling is noisy
 *   enough that it cannot be trusted to carry a decision alone.
 * - Sleep is a strong negative when short and a mild positive when long. It
 *   also still acts as a hard cap downstream in mapBandToCategory.
 *
 * Thresholds are deliberately relative to the user's own baseline, never
 * absolute: population-level SDNN cutoffs are meaningless individually.
 */
export function assessHealthKit(
  hk: HealthKitPayload,
  baselineHrvMs: number | null,
  baselineRestingHr: number | null,
): { band: Band; confidence: DataConfidence } {
  const sleep = hk.sleepHours ?? null;
  let score = 0;
  let signals = 0;

  // Resting HR vs personal baseline. Lower than usual is a good sign;
  // meaningfully elevated is the clearest "back off" signal available here.
  if (baselineRestingHr !== null && hk.restingHr != null) {
    signals++;
    const delta = (hk.restingHr - baselineRestingHr) / baselineRestingHr;
    if (delta >= 0.07) score -= 2;
    else if (delta >= 0.03) score -= 1;
    else if (delta <= -0.03) score += 1;
  }

  // HRV vs personal baseline.
  if (baselineHrvMs !== null && hk.hrvMs != null) {
    signals++;
    const ratio = hk.hrvMs / baselineHrvMs;
    if (ratio < 0.8) score -= 2;
    else if (ratio < 0.9) score -= 1;
    else if (ratio >= 1.05) score += 1;
  }

  // Sleep, when we have it.
  if (sleep !== null) {
    signals++;
    if (sleep < 6) score -= 2;
    else if (sleep < 7) score -= 1;
    else if (sleep >= 7.5) score += 1;
  }

  // Nothing usable -- typically the first days before any baseline exists.
  // Stay conservative and say so, rather than guessing push_hard.
  if (signals === 0) {
    return { band: "medium", confidence: "low" };
  }

  const band: Band = score >= 2 ? "high" : score <= -2 ? "low" : "medium";
  // One signal can move the band on its own, so flag that the read is thin.
  // The app uses this to caveat the explanation rather than presenting a
  // guess with the same confidence as a Whoop recovery score.
  return { band, confidence: signals >= 2 ? "high" : "low" };
}
