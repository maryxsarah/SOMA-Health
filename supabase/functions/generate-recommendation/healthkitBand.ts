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
  // Per-stage sleep breakdown -- persisted to daily_snapshot for the
  // dashboard's sleep-stage chart, not used by the band-scoring logic
  // below (assessHealthKit only ever used the merged sleepHours total).
  sleepLightHours?: number;
  sleepDeepHours?: number;
  sleepRemHours?: number;
  sleepAwakeHours?: number;
  // Trailing-24h basalEnergyBurned (kcal) -- persisted to daily_snapshot for
  // nutritionTargets.ts's measured-BMR override (see
  // docs/coaching-personalization-plan.md Phase 1), not used by the
  // band-scoring logic below.
  basalEnergyKcal?: number;
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
  // True when the baselines come from fewer days than we would like. Thin
  // history may then only make us MORE cautious: negative points still count,
  // positive ones are dropped. Asymmetric on purpose -- a shaky baseline is
  // reason enough to hold someone back, never to tell them to push hard.
  baselinesAreProvisional = false,
): { band: Band; confidence: DataConfidence; signalCount: number } {
  const sleep = hk.sleepHours ?? null;
  let score = 0;
  let signals = 0;

  // Positive points are what a provisional baseline may not award.
  const credit = (points: number) => {
    score += baselinesAreProvisional && points > 0 ? 0 : points;
  };

  // Resting HR vs personal baseline -- the heaviest signal here, and the only
  // one allowed to reach the -2 that decides a band on its own. Recorded
  // daily, far more stable than SDNN, and elevation above personal baseline
  // is a well-established fatigue/illness marker.
  if (baselineRestingHr !== null && hk.restingHr != null) {
    signals++;
    const delta = (hk.restingHr - baselineRestingHr) / baselineRestingHr;
    if (delta >= 0.07) credit(-2);
    else if (delta >= 0.03) credit(-1);
    else if (delta <= -0.03) credit(+1);
  }

  // HRV vs personal baseline, capped at +/-1 so it can never decide the band
  // alone -- it has to be corroborated by resting HR or sleep.
  //
  // It used to carry the same +/-2 as the other two, which contradicted this
  // function's own docblock and had a real consequence: Apple reports SDNN
  // (not the RMSSD every other recovery tracker uses), sampled passively and
  // noisily, so a single artefact reading at 0.55x baseline was enough to
  // force a rest day off one bad sample.
  if (baselineHrvMs !== null && hk.hrvMs != null) {
    signals++;
    const ratio = hk.hrvMs / baselineHrvMs;
    if (ratio < 0.8) credit(-1);
    else if (ratio < 0.9) credit(-1);
    else if (ratio >= 1.05) credit(+1);
  }

  // Sleep, when we have it.
  if (sleep !== null) {
    signals++;
    if (sleep < 6) credit(-2);
    else if (sleep < 7) credit(-1);
    else if (sleep >= 7.5) credit(+1);
  }

  // Nothing usable -- typically the first days before any baseline exists.
  // Stay conservative and say so, rather than guessing push_hard.
  if (signals === 0) {
    return { band: "medium", confidence: "low", signalCount: 0 };
  }

  const band: Band = score >= 2 ? "high" : score <= -2 ? "low" : "medium";
  // One signal can move the band on its own, so flag that the read is thin.
  // The app uses this to caveat the explanation rather than presenting a
  // guess with the same confidence as a Whoop recovery score.
  return { band, confidence: signals >= 2 ? "high" : "low", signalCount: signals };
}
