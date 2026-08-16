// DRAFTED, NOT EXPERT-REVIEWED -- same standing caveat as contraindications.ts,
// LOAD_FRACTION_OF_BODYWEIGHT (generate-workout-plan/index.ts), and
// finisherCatalog.ts. Encodes generic, widely-published MEV/MAV/MRV-style
// volume-landmark ranges (working sets per body-part focus per week) -- NOT
// attributed to, sourced from, or endorsed by any named individual's
// proprietary material. Built on well-established, published exercise-science
// principles (progressive overload, volume landmarks, periodization) -- not
// affiliated with or endorsed by any individual trainer, coach, or author.
//
// Lives in _shared/ (not inside generate-workout-plan/) because both
// generate-workout-plan (prompt guidance) and generate-recommendation (the
// volume_cap_applied cap) use it.
//
// Keyed by BodyPartFocus (this codebase's existing, coarse categorization --
// see Soma/Models/DailyRecommendation.swift), not fine-grained muscle groups
// (chest/back/legs/etc), because that's the only granularity workout_log
// actually tracks (`body_part` column). A finer breakdown would be fabricated
// precision this codebase's own convention avoids (see HealthMetricFamily's
// "no fabricated fields" rule for the same reasoning applied elsewhere).

export type ExperienceLevel = "newbie" | "moderate" | "advanced";

export interface VolumeLandmark {
  /// Minimum Effective Volume -- sets/week below which progress stalls.
  mev: number;
  /// Maximum Adaptive Volume -- the productive range, [low, high].
  mav: [number, number];
  /// Maximum Recoverable Volume -- sets/week beyond which fatigue outpaces
  /// adaptation for most people at this experience level.
  mrv: number;
}

export const VOLUME_LANDMARKS: Record<string, Record<ExperienceLevel, VolumeLandmark>> = {
  upper_body: {
    newbie: { mev: 6, mav: [8, 12], mrv: 16 },
    moderate: { mev: 8, mav: [12, 16], mrv: 20 },
    advanced: { mev: 10, mav: [14, 20], mrv: 24 },
  },
  lower_body: {
    newbie: { mev: 6, mav: [8, 12], mrv: 16 },
    moderate: { mev: 8, mav: [12, 16], mrv: 20 },
    advanced: { mev: 10, mav: [14, 20], mrv: 24 },
  },
  full_body: {
    // full_body sessions hit every major group at once, so the weekly
    // landmark here is per-session count, not per-muscle-group sets --
    // this is also the shape generate-recommendation's volume_cap_applied
    // cap reuses, since workout_log only tracks session-level data (no
    // per-set logging exists), not true per-muscle-group set counts.
    newbie: { mev: 2, mav: [2, 3], mrv: 4 },
    moderate: { mev: 3, mav: [3, 4], mrv: 5 },
    advanced: { mev: 3, mav: [4, 5], mrv: 6 },
  },
  core: {
    newbie: { mev: 4, mav: [6, 8], mrv: 10 },
    moderate: { mev: 6, mav: [8, 10], mrv: 12 },
    advanced: { mev: 6, mav: [10, 14], mrv: 16 },
  },
};

/// DRAFTED, NOT EXPERT-REVIEWED, added 2026-08-15 alongside
/// generate-recommendation's volume cap becoming body-part-aware (see that
/// function's own comment). Session-count-shaped per body part, same unit
/// choice as VOLUME_LANDMARKS.full_body above and for the identical
/// reason (workout_log has no per-set logging) -- NOT the same numbers as
/// VOLUME_LANDMARKS.upper_body/lower_body/core's mrv above, which are in
/// sets/week and describe a DIFFERENT thing (describeVolumeGuidance's
/// prompt-text sanity check on a single session's set count, not a
/// weekly session-frequency cap).
///
/// Tighter than full_body's session mrv (4/5/6) by design: repeatedly
/// training the SAME specific body part is more concentrated fatigue on
/// that tissue than a full_body day that spreads load across every major
/// group at once, so real recovery guidance for a single muscle group
/// generally calls for at least 48h+ between sessions targeting it --
/// roughly 2-4x/week depending on experience, not the 4-6x/week full_body
/// figure. `core` and `cardio` are deliberately excluded: core work is
/// commonly programmed daily/near-daily even in mainstream guidance (low
/// systemic fatigue cost), and cardio has no comparable "hits one specific
/// group repeatedly" concern this cap exists to catch.
export const BODY_PART_SESSION_MRV: Partial<Record<string, Record<ExperienceLevel, number>>> = {
  upper_body: { newbie: 2, moderate: 3, advanced: 4 },
  lower_body: { newbie: 2, moderate: 3, advanced: 4 },
};

/// Prompt-ready guidance sentence -- feeds generate-workout-plan's
/// buildPrompt as additional context, same "describeXxx returns a prompt
/// line" convention as describeContraindications.
export function describeVolumeGuidance(experience: ExperienceLevel, category: string): string {
  if (category === "rest" || category === "light") {
    return "";
  }
  const upper = VOLUME_LANDMARKS.upper_body[experience];
  const lower = VOLUME_LANDMARKS.lower_body[experience];
  return `General volume guidance for this experience level (published training-volume landmarks, not a hard rule): roughly ${upper.mav[0]}-${upper.mav[1]} weekly working sets per upper-body muscle group and ${lower.mav[0]}-${lower.mav[1]} for lower-body is a productive range without excess fatigue -- use this only as a sanity check on today's total set count, not as a target to hit in a single session.`;
}
