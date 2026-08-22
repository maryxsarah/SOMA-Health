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

/// Real, self-reported training frequency (Soma/Models/OnboardingSurveyModels.swift's
/// WorkoutFrequency enum, mirrored server-side in generate-workout-plan/
/// index.ts's workoutsPerWeekLabel) below which this cap never applies --
/// that population's natural cadence already includes plenty of rest, so a
/// forced "you need a rest day" reads as patronizing rather than useful.
const SKIP_PROACTIVE_REST_BELOW = "zero_to_two";
/// Below this many real daily_recommendation rows in the trailing window,
/// there isn't enough data to say "no rest day all week" -- a user who
/// only opens the app 2-3x/week simply has no row (not a "moderate" row)
/// on the days they didn't check in, so an empty/sparse window must never
/// be read as "a solid week of nothing but hard training".
export const PROACTIVE_REST_MIN_RECOMMENDATIONS = 5;

/// Consecutive prior days with a TRAINING day (moderate or push_hard),
/// strictly before the day being evaluated, stopping at the first gap --
/// e.g. training on d-1, d-2, d-3 but not d-4 counts as 3, regardless of
/// what happened further back.
///
/// The category filter is what makes the cap releasable: counting every
/// workout_log row meant a dutifully-logged "Full rest day" or recovery
/// walk extended the streak, and -- worse -- each capped "light" day the
/// user then logged re-extended it again, so the cap never let go and a
/// well-recovered user never saw another moderate/push_hard day. Rest and
/// light days are the streak BREAKING, not the streak continuing; that is
/// the entire point of capping to light.
///
/// Moved here from generate-recommendation/index.ts (2026-08-22) so
/// computeExceptionalReadinessBypassAllowed below and index.ts's own
/// consecutive-days/volume caps share one definition instead of risking
/// drift between two copies.
export const CONSECUTIVE_DAYS_THRESHOLD = 4;

/// DRAFTED, NOT EXPERT-REVIEWED -- past this many consecutive hard-training
/// days, the accumulated load calls for more than active recovery: the day
/// lands on full "rest" instead of "light".
///
/// 2026-08-15 recalibration (both this and CONSECUTIVE_DAYS_THRESHOLD
/// above, 6->5 and 5->4): general recovery guidance discourages more than
/// ~4-5 consecutive high-intensity days without at least a lighter one;
/// the old 5/6 was already on the lenient edge of that. The proactive rest
/// floor (computeProactiveRestCapApplied, below) provides the PRIMARY
/// guarantee of a real week-over-week rest day independent of streaks --
/// this pair is the secondary backstop for a genuine back-to-back grind.
///
/// Also, since 2026-08-22, this is the ceiling
/// computeExceptionalReadinessBypassAllowed reuses to stop an exceptional
/// same-day reading from waiving caps indefinitely -- see that function's
/// own doc comment for why this number (not CONSECUTIVE_DAYS_THRESHOLD)
/// is the right one to reuse for that.
export const REST_ESCALATION_THRESHOLD = 5;

/**
 * Whether an exceptional same-day readiness reading (WHOOP recovery >=
 * EXCEPTIONAL_WHOOP_RECOVERY or Oura readiness >= EXCEPTIONAL_OURA_READINESS,
 * computed in generate-recommendation/index.ts) should still be allowed to
 * bypass the consecutive-days/volume/proactive-rest caps today.
 *
 * BUG this fixes: exceptionalReadinessToday used to bypass all three caps
 * with a flat `if (exceptionalReadinessToday)`, with NO memory of how many
 * prior days had already been bypassed the same way -- a user with a
 * genuinely great WEEK (exceptional readiness every day) could go
 * indefinitely without a real rest/active-recovery day ever being
 * recommended, defeating the exact purpose the proactive-rest floor was
 * built for. Muscles need programmed recovery to actually adapt/build
 * regardless of how good daily readiness looks.
 *
 * Fix: reuses consecutiveDays (generate-recommendation/index.ts's own
 * countConsecutiveTrainingDays result, already computed for the
 * consecutive-days cap) rather than inventing a new parallel counter --
 * a bypassed day's category stays moderate/push_hard, so consecutiveDays
 * ALREADY organically counts a bypassed day as a training day. Once the
 * streak reaches REST_ESCALATION_THRESHOLD -- the same ceiling that
 * already forces a *non*-exceptional streak down to full "rest" -- an
 * exceptional reading stops being able to extend it further. Below that
 * ceiling, exceptional readiness still waives the caps exactly as before
 * (a body that's clearly recovered exceptionally well for a day or two
 * isn't forced down just because of the calendar); it just can no longer
 * do so forever.
 */
export function computeExceptionalReadinessBypassAllowed(
  exceptionalReadinessToday: boolean,
  consecutiveDays: number,
): boolean {
  return exceptionalReadinessToday && consecutiveDays < REST_ESCALATION_THRESHOLD;
}

/**
 * True when the trailing window (generate-recommendation/index.ts passes
 * the last 7 days of daily_recommendation.category, excluding today) shows
 * real recommendation history with NOT ONE rest/light day in it -- BUG:
 * every existing cap in this file is reactive (fires off a bad signal);
 * nothing ever proactively guarantees a calendar-based recovery day when
 * the wearable signals simply look fine all week, which isn't how real
 * hypertrophy/general-fitness programming works.
 *
 * Independent of every other cap (same "any one can fire" pattern as the
 * rest of this file) -- this only ever caps to "light" (the floor), never
 * escalates to "rest" the way the consecutive-days/severe-injury paths do.
 *
 * `exceptionalReadinessBypassAllowed` (NOT the raw same-day reading --
 * see computeExceptionalReadinessBypassAllowed above) skips this cap, same
 * bar the consecutive-days and volume caps use: a genuinely great week
 * isn't forced down, only a week that's simply had no bad signal at all --
 * but that grace period has a ceiling now, same as the other two caps.
 */
export function computeProactiveRestCapApplied(
  workoutsPerWeek: string | null,
  recommendationCategoriesInWindow: Category[],
  exceptionalReadinessBypassAllowed: boolean,
  bandCategory: Category,
): boolean {
  if (workoutsPerWeek === SKIP_PROACTIVE_REST_BELOW) return false;
  if (exceptionalReadinessBypassAllowed) return false;
  if (bandCategory !== "moderate" && bandCategory !== "push_hard") return false;
  if (recommendationCategoriesInWindow.length < PROACTIVE_REST_MIN_RECOMMENDATIONS) return false;
  return !recommendationCategoriesInWindow.some((c) => c === "rest" || c === "light");
}
