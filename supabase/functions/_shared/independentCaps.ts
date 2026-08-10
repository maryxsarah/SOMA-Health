// Pure, unit-testable predicates behind two of generate-recommendation's
// independent category caps -- pulled out of the handler (unlike this
// file's older caps, which are inline `const`s with no direct test
// coverage) specifically because these two are what real, explicit
// feedback called out as safety-critical: "when the user shared a
// specific injury, if needed a rest day needs to be recommended ... the
// application needs to be flawless on this one." Same shared-pure-module
// pattern as contraindications.ts/safetyFlags.ts/nutritionTargets.ts.

export type Category = "rest" | "light" | "moderate" | "push_hard";

export interface SevereInjuryRow {
  protocol_started_at: string;
  consecutive_bad_days: number;
}

// DRAFTED, NOT EXPERT-REVIEWED -- same as every other cap threshold in
// generate-recommendation, this is a product decision that needs clinical
// sign-off, not a default to trust blindly.
export const RECENT_SEVERE_INJURY_WINDOW_HOURS = 24;
export const SEVERE_INJURY_BAD_DAYS_TO_REST = 3;
export const LOW_MOOD_RATING_THRESHOLD = 2;

/**
 * True when a severe injury_recovery_state protocol should force the
 * whole day to full "rest" rather than the ordinary severe-injury cap's
 * ceiling of "light" -- either it was just reported/escalated to severe
 * within the last RECENT_SEVERE_INJURY_WINDOW_HOURS (a fresh acute injury
 * needs actual rest on day one), or it's been trending worse for
 * SEVERE_INJURY_BAD_DAYS_TO_REST+ consecutive check-ins (the same
 * threshold record-injury-checkin already escalates to a "see a
 * professional" message at -- by that point "light" isn't a safe enough
 * cap).
 *
 * Deliberately NOT gated on bandCategory the way the ordinary caps are --
 * a fresh/worsening severe injury forces rest even on a day the wearable
 * band alone would only have called "light", since the band reflects
 * recovery signals like sleep/HRV, not injury status.
 */
export function computeInjuryProtocolRestApplied(
  severeInjuryRows: SevereInjuryRow[],
  nowMs: number,
): boolean {
  const justReported = severeInjuryRows.some(
    (r) => nowMs - new Date(r.protocol_started_at).getTime() <= RECENT_SEVERE_INJURY_WINDOW_HOURS * 3600 * 1000,
  );
  const worsening = severeInjuryRows.some(
    (r) => r.consecutive_bad_days >= SEVERE_INJURY_BAD_DAYS_TO_REST,
  );
  return justReported || worsening;
}

/**
 * True when today's daily_mood check-in should downgrade the day one
 * step. Asymmetric by design -- a rough/not-great mood (rating 1-2 of the
 * 1-5 MoodRating scale) can downgrade, but a good mood (4-5) never
 * upgrades, mirroring every other cap in this file: mood alone isn't
 * evidence the body actually recovered, only self-report that the user
 * feels up to training, and a low rating already covers that case by NOT
 * overriding a harder day upward. Only fires on a day the band would
 * otherwise call moderate/push_hard, same gating as sleep/HRV/stress.
 */
export function computeMoodCapApplied(
  todaysMoodRating: number | null,
  bandCategory: Category,
): boolean {
  return todaysMoodRating !== null &&
    todaysMoodRating <= LOW_MOOD_RATING_THRESHOLD &&
    (bandCategory === "moderate" || bandCategory === "push_hard");
}
