// Pure, unit-testable piece of generate-meal-recommendation's category
// awareness (BUG report: this function had zero read of today's category
// at all) -- pulled out specifically so the numeric adjustment is directly
// testable without importing index.ts itself (top-level Deno.serve).
//
// Investigated whether to shift the PERSISTED nutrition_targets row itself
// on a rest/light day: nutrition_targets is written only by
// analyze-body-photo -- a stable, periodically-recomputed baseline other
// systems (progress bars, weekly tracking) depend on, not something
// recalculated daily. Shifting the persisted row per category would be a
// much bigger, unrelated architecture change and would make that "stable"
// target fluctuate under systems that assume it isn't. This is a
// LOCAL-ONLY adjustment to one day's remaining-macro math -- protein held
// as-is (muscle repair still matters on a rest day), carbs trimmed --
// never written back to nutrition_targets.

/// DRAFTED, NOT EXPERT-REVIEWED, same standing caveat as every other
/// numeric coaching constant in this codebase (loadGuidance.ts,
/// volumeLandmarks.ts, ...). A modest trim (not a big swing) reflecting
/// that recovery-day glycogen demand is lower without today's training
/// load, while still leaving a real, satisfying amount of carbs -- this
/// is framing/behavior, not a strict metabolic prescription.
export const REST_DAY_CARB_TRIM = 0.88;

/// The carb target to use for TODAY's remaining-macro calculation only --
/// trimmed on a rest/light day, unchanged otherwise. `dailyCarbsG` is
/// always the real, persisted nutrition_targets value; this never mutates
/// or returns anything meant to be written back to that row.
export function effectiveCarbsTargetG(dailyCarbsG: number, isRecoveryDay: boolean): number {
  return isRecoveryDay ? dailyCarbsG * REST_DAY_CARB_TRIM : dailyCarbsG;
}
