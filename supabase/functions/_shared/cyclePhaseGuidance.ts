// DRAFTED, NOT EXPERT-REVIEWED -- same standing caveat as pregnancyGuidance.ts/
// volumeLandmarks.ts/sexAwareGuidance.ts. General, non-diagnostic, widely-
// published four-phase menstrual-cycle model (menstrual/follicular/
// ovulatory/luteal), mapped proportionally onto the user's own typical
// cycle length rather than fixed day-counts -- NOT a fertility/ovulation
// predictor, NOT attributed to or endorsed by any individual, and never
// framed as an individualized medical claim. See docs/coaching-
// personalization-plan.md's Phase 5 design section for the full scope
// discussion (out of scope: symptom tracking, ovulation prediction,
// irregularity/condition detection).
//
// Phase 5: training-hook only (sexAwareGuidance.ts consumes this module).
// Nutrition was explicitly deferred -- see the design doc for why.
//
// Lives in _shared/ (not generate-workout-plan/) so a future nutrition
// hook, or any other caller, can reuse the SAME derivation and phase
// descriptions rather than a second copy drifting from this one -- same
// reasoning as pregnancyGuidance.ts's own placement.

export type CyclePhase = "menstrual" | "follicular" | "ovulatory" | "luteal";
export type CyclePhaseConfidence = "high" | "low";

export interface CyclePhaseResult {
  phase: CyclePhase;
  confidence: CyclePhaseConfidence;
}

/// Population average, used only when the user hasn't stated their own
/// typical length -- same "personal value overrides population estimate,
/// never required" pattern as loadGuidance.ts's known_lifts override.
export const DEFAULT_CYCLE_LENGTH_DAYS = 28;

/// Cycles elapsed since the recorded start date before the projection is
/// too stale to trust at all (returns null rather than a low-confidence
/// guess -- see deriveCyclePhase's own comment). 0 elapsed = still inside
/// the cycle the recorded date actually describes (high confidence); 1-2
/// elapsed = projected forward assuming regularity (low confidence); 3+
/// (~2+ months since the user last updated it) = stale, no guidance shown.
const MAX_TRUSTED_CYCLES_ELAPSED = 2;

// Proportional phase-boundary fractions, mapped from the commonly-cited
// ~28-day consumer model (menstrual days 1-5, follicular days 6-13,
// ovulatory ~days 14-16, luteal days 17-28) onto a 0..1 fraction of
// whatever the user's own typical_cycle_length_days actually is -- so a
// 35-day cycle gets proportionally scaled boundaries, not the 28-day
// model's raw day-counts.
const MENSTRUAL_END_FRACTION = 5 / 28;
const FOLLICULAR_END_FRACTION = 13 / 28;
const OVULATORY_END_FRACTION = 16 / 28;

function daysBetween(fromDate: string, toDate: string): number {
  const from = new Date(`${fromDate}T00:00:00.000Z`).getTime();
  const to = new Date(`${toDate}T00:00:00.000Z`).getTime();
  return Math.floor((to - from) / 86400000);
}

/// Null whenever there's nothing usable to derive from: no recorded start
/// date (not opted in), a future-dated start (bad data/clock skew -- fails
/// safe rather than guessing), or a projection too stale to trust (see
/// MAX_TRUSTED_CYCLES_ELAPSED). Callers (sexAwareGuidance.ts) treat null
/// identically to "not opted in" -- same fallback either way, no separate
/// "stale" UI state.
export function deriveCyclePhase(
  lastPeriodStartDate: string | null,
  typicalCycleLengthDays: number | null,
  today: string,
): CyclePhaseResult | null {
  if (lastPeriodStartDate === null) return null;

  const cycleLength = typicalCycleLengthDays ?? DEFAULT_CYCLE_LENGTH_DAYS;
  const daysSince = daysBetween(lastPeriodStartDate, today);
  if (daysSince < 0) return null;

  const cyclesElapsed = Math.floor(daysSince / cycleLength);
  if (cyclesElapsed > MAX_TRUSTED_CYCLES_ELAPSED) return null;

  const dayFraction = (daysSince % cycleLength) / cycleLength;
  const phase: CyclePhase = dayFraction < MENSTRUAL_END_FRACTION
    ? "menstrual"
    : dayFraction < FOLLICULAR_END_FRACTION
    ? "follicular"
    : dayFraction < OVULATORY_END_FRACTION
    ? "ovulatory"
    : "luteal";

  return { phase, confidence: cyclesElapsed === 0 ? "high" : "low" };
}

/// Neutral, non-diagnostic descriptive text per phase -- general training-
/// relevant considerations only, reused (not duplicated) by whichever
/// hook builds the final prompt line. Deliberately doesn't mention
/// fertility/ovulation timing itself, only the training-relevant physical
/// considerations commonly associated with each phase.
export const CYCLE_PHASE_CONSIDERATIONS: Record<CyclePhase, string> = {
  menstrual: "energy and recovery capacity can run lower for some people early in the cycle -- it's fine to favor a bit more moderate effort and not chase a personal best today",
  follicular: "recovery capacity and tolerance for intensity often trend upward through this part of the cycle for some people -- a reasonable window to push a bit harder if the day's other signals support it",
  ovulatory: "connective-tissue laxity can be slightly elevated around this point in the cycle for some people -- favor controlled tempo and a thorough warm-up, especially on high-impact or plyometric work",
  luteal: "energy and tolerance for high intensity can dip for some people later in the cycle -- it's fine to favor moderate effort and prioritize consistency over hitting a peak session",
};
