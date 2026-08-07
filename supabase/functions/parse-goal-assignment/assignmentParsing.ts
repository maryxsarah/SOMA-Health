// Split out of index.ts so it's testable without importing index.ts, same
// pattern as parse-meal-text/estimateBounds.ts.

export const SCHEDULE_RULES = ["weekdays", "every_other_day", "before_court_days", "readiness"] as const;
export type ScheduleRule = typeof SCHEDULE_RULES[number];

export const LOW_CONFIDENCE_THRESHOLD = 0.6;
const MIN_WORKOUT_TEXT_LENGTH = 3;

// Raw shape both vendor schemas are constrained to. Anthropic's json_schema
// output doesn't support nullable fields, so "unknown" is spelled with a
// sentinel per type ("" / 0 / "none" / []) instead of null; normalizeAssignment
// below converts those to real nulls for the client.
export interface RawAssignmentResult {
  isAssignment: boolean;
  confidence: number;
  givenText: string;
  workoutText: string;
  coachName: string;
  durationWeeks: number;
  frequencyPerWeek: number;
  scheduleRule: string;
  scheduleDays: number[];
  courtDays: number[];
}

export interface ParsedAssignment {
  givenText: string | null;
  workoutText: string | null;
  coachName: string | null;
  durationWeeks: number | null;
  frequencyPerWeek: number | null;
  scheduleRule: ScheduleRule | null;
  scheduleDays: number[] | null;
  courtDays: number[] | null;
}

export interface AssignmentParseResult {
  parsed: ParsedAssignment | null;
  confidence: number;
  lowConfidence: boolean;
}

const orNull = (s: string): string | null => (s.trim() ? s.trim() : null);
const validDays = (days: number[]): number[] | null => {
  const filtered = days.filter((d) => Number.isInteger(d) && d >= 0 && d <= 6);
  return filtered.length ? filtered : null;
};

export function normalizeAssignment(raw: RawAssignmentResult): AssignmentParseResult {
  const workoutText = orNull(raw.workoutText ?? "");
  // Belt and braces: a model that self-reports high confidence but returns
  // no actual (or near-empty, e.g. ".") workout text still fails closed,
  // same posture as analyze-gym-photo's post-schema equipment re-check.
  const lowConfidence = !raw.isAssignment || raw.confidence < LOW_CONFIDENCE_THRESHOLD ||
    !workoutText || workoutText.length < MIN_WORKOUT_TEXT_LENGTH;

  if (lowConfidence) {
    return { parsed: null, confidence: raw.confidence, lowConfidence: true };
  }

  const scheduleRule = SCHEDULE_RULES.includes(raw.scheduleRule as ScheduleRule)
    ? (raw.scheduleRule as ScheduleRule)
    : null;

  return {
    parsed: {
      givenText: orNull(raw.givenText ?? ""),
      workoutText,
      coachName: orNull(raw.coachName ?? ""),
      durationWeeks: raw.durationWeeks > 0 ? Math.min(26, Math.round(raw.durationWeeks)) : null,
      // Clamped like durationWeeks -- 7 is the physical ceiling (once a
      // day), guarding against a misread stray number (e.g. a rep count)
      // landing in this field.
      frequencyPerWeek: raw.frequencyPerWeek > 0 ? Math.min(7, Math.round(raw.frequencyPerWeek)) : null,
      scheduleRule,
      scheduleDays: scheduleRule === "weekdays" ? validDays(raw.scheduleDays ?? []) : null,
      courtDays: scheduleRule === "before_court_days" ? validDays(raw.courtDays ?? []) : null,
    },
    confidence: raw.confidence,
    lowConfidence: false,
  };
}
