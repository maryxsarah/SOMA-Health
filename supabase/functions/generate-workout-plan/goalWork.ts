// Sport Goal Programs: deterministic goal-block decision, shaped like
// finisherCatalog.ts's decideFinisher -- whether goal work appears today,
// which concept, and its dose are decided HERE from plain inputs; the LLM
// only elaborates the chosen concept into wording. Custom (coach's task)
// goals are never elaborated at all: the coach's workout_text is emitted
// VERBATIM, only ever day-shifted, per the spec's "Soma never rewrites the
// coach's content" rule. Concept content itself lives in goal_work_concept
// rows (see docs/features/sport-goal-content-blueprint.md), fetched by the
// caller and passed in -- adding a sport/goal is a data migration.

/// One goal_work_concept row, normalized. `category` is a recommendation
/// category or "any" ("any" covers active days, never rest).
export interface GoalWorkConcept {
  category: string;
  /// Goal phase this concept belongs to; null/"any" = every phase.
  phase: string | null;
  focus: string;
  modality: string;
  durationMinutesRange: [number, number];
  rpeTarget: string | null;
  /// Deterministic safety caps (plyo contacts, wall-session limits, hang
  /// spacing) carried from goal_work_concept.dose_notes.
  doseNotes: string | null;
  description: string;
}

export interface GoalState {
  id: string;
  kind: "preset" | "custom";
  targetKind: "metric" | "milestone" | "qualitative" | "commitment";
  phase: string | null;
  paused: boolean;
  /// Per-sport server gate (sports.status + internal_tester) -- when the
  /// sport isn't visible to this user, no block is emitted (spec, gating 3).
  sportVisible: boolean;
  scheduleRule: "weekdays" | "every_other_day" | "before_court_days" | "readiness" | null;
  /// Weekday ints, JS Date.getUTCDay() numbering: 0=Sun .. 6=Sat.
  scheduleDays: number[] | null;
  courtDays: number[] | null;
  workoutText: string | null;
  coachName: string | null;
  /// The plain "N x a week" chip (scheduleRule null) -- gates placement via
  /// isScheduledToday's default case. Null (no explicit count) keeps the
  /// old unlimited behavior, e.g. for goals predating this field.
  frequencyPerWeek: number | null;
}

/// Recent days that carried a goal block -- `text` is the block's
/// focus+description, used for the hangs-never-consecutive-days rule.
export interface GoalBlockHistoryEntry {
  date: string;
  text: string;
}

export interface GoalWorkInput {
  /// Today's daily_recommendation category -- the safety envelope; never
  /// recomputed here (generate-recommendation stays untouched).
  category: string;
  date: string;
  goal: GoalState;
  concepts: GoalWorkConcept[];
  excludedKeywords: string[];
  recentGoalBlocks: GoalBlockHistoryEntry[];
}

export type GoalWorkBlock =
  | {
    kind: "preset";
    concept: GoalWorkConcept;
    /// True on rest days -- the block is an opt-in 5-min mobility dose.
    optional: boolean;
    /// True when exclusions emptied the normal pick and the safe fallback
    /// was substituted -- logged by decideGoalWork, surfaced for tests.
    usedSafeFallback: boolean;
  }
  | {
    kind: "custom";
    /// Byte-identical to user_goal.workout_text -- never rewritten.
    workoutText: string;
    builtWith: string | null;
  };

/// Keyword-neutral last resort when safety exclusions empty every concept
/// for the goal -- gentle enough to be safe for anyone still training.
const SAFE_FALLBACK_CONCEPT: GoalWorkConcept = {
  category: "any",
  phase: null,
  focus: "gentle goal-adjacent mobility",
  modality: "mobility_flow",
  durationMinutesRange: [5, 10],
  rpeTarget: "RPE 2-3",
  doseNotes: null,
  description:
    "Easy, comfortable mobility for the joints this goal trains -- slow controlled ranges paced by breathing, nothing loaded, nothing forced.",
};

const HANG_PATTERN = /hang/i;

function utcWeekday(dateStr: string): number {
  return new Date(`${dateStr}T00:00:00.000Z`).getUTCDay();
}

function addDaysStr(dateStr: string, days: number): string {
  const d = new Date(`${dateStr}T00:00:00.000Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}

/// Same coarse substring mechanism as isFinisherSafeGivenInjuries.
function conceptSafeGivenExclusions(concept: GoalWorkConcept, excludedKeywords: string[]): boolean {
  if (excludedKeywords.length === 0) return true;
  const haystack = `${concept.description} ${concept.modality} ${concept.focus} ${concept.doseNotes ?? ""}`.toLowerCase();
  return !excludedKeywords.some((kw) => haystack.includes(kw.toLowerCase()));
}

function conceptInvolvesHangs(concept: GoalWorkConcept): boolean {
  return HANG_PATTERN.test(`${concept.description} ${concept.modality} ${concept.focus} ${concept.doseNotes ?? ""}`);
}

/// Schedule check shared by preset and custom goals (spec: the scheduling
/// rules are "also available to preset goals"). Category-independent.
/// Exported for describeUpcomingGoalWork below, which reuses it unchanged
/// against future dates -- the same weekday/every-other-day/court-day math
/// that governs TODAY'S placement is exactly what makes a future date
/// predictable at all.
export function isScheduledToday(goal: GoalState, date: string, recentGoalBlocks: GoalBlockHistoryEntry[]): boolean {
  const dow = utcWeekday(date);
  switch (goal.scheduleRule) {
    case "weekdays":
      // An explicit day picker wins; a bare "weekdays" means Mon-Fri.
      return goal.scheduleDays?.length ? goal.scheduleDays.includes(dow) : dow >= 1 && dow <= 5;
    case "every_other_day":
      return !recentGoalBlocks.some((b) => b.date === addDaysStr(date, -1));
    case "before_court_days":
      // Scheduled on the day BEFORE any court day.
      return (goal.courtDays ?? []).some((court) => (dow + 1) % 7 === court % 7);
    case "readiness":
      // Placement deferred to the readiness envelope -- handled by the
      // caller via category (see decideGoalWork); any day passes here.
      return true;
    default:
      // The plain "N x a week" chip (no explicit schedule rule) -- BUG:
      // frequencyPerWeek used to reach nowhere near placement (only
      // maybeUpdateEtaSlip read it, for ETA math), so every count chip
      // behaved identically and a goal block landed literally every day.
      // Self-limiting like every_other_day, not fixed weekdays: stop
      // placing once the trailing 7-day window (today + the 6 days
      // before it) already has frequencyPerWeek blocks in it.
      if (goal.frequencyPerWeek == null) return true;
      const windowStart = addDaysStr(date, -6);
      const countInWindow = recentGoalBlocks.filter((b) => b.date >= windowStart && b.date < date).length;
      return countInWindow < goal.frequencyPerWeek;
  }
}

/// Deterministic day-varying pick among equally eligible concepts -- same
/// date always picks the same concept, different days rotate.
function rotateByDate(date: string, count: number): number {
  const d = new Date(`${date}T00:00:00.000Z`);
  const dayNumber = Math.floor(d.getTime() / 86400000);
  return ((dayNumber % count) + count) % count;
}

function phaseEligible(concept: GoalWorkConcept, phase: string | null): boolean {
  return concept.phase === null || concept.phase === "any" || phase === null || concept.phase === phase;
}

/// The single entry point -- returns null (no block today) or the block
/// descriptor. Purely deterministic; never left to the LLM.
export function decideGoalWork(input: GoalWorkInput): GoalWorkBlock | null {
  const { category, date, goal, concepts, excludedKeywords, recentGoalBlocks } = input;

  if (goal.paused) return null;
  if (!goal.sportVisible) return null;

  if (goal.kind === "custom") {
    const text = goal.workoutText?.trim() ?? "";
    if (text.length === 0) {
      console.warn(`goalWork: custom goal ${goal.id} has empty workout_text -- no block`);
      return null;
    }
    // Low-readiness placement: rest days shift the coach's session to
    // another day; the prescription itself is never touched.
    if (category === "rest") return null;
    if (goal.scheduleRule === "readiness" && category !== "moderate" && category !== "push_hard") return null;
    if (!isScheduledToday(goal, date, recentGoalBlocks)) return null;
    // VERBATIM -- the exact stored workout_text, never trimmed/rewritten.
    return { kind: "custom", workoutText: goal.workoutText!, builtWith: goal.coachName };
  }

  // Preset goals: an explicit schedule rule day-shifts them too. Must run
  // for scheduleRule === null too now (not just the explicit rules) --
  // that's isScheduledToday's default case, which gates by frequencyPerWeek.
  if (goal.scheduleRule !== "readiness" && !isScheduledToday(goal, date, recentGoalBlocks)) {
    return null;
  }
  if (goal.scheduleRule === "readiness" && category !== "moderate" && category !== "push_hard") {
    return null;
  }

  const inPhase = concepts.filter((c) => phaseEligible(c, goal.phase));

  // Rest day: only an explicit rest concept (short optional mobility) may
  // appear -- "any" concepts cover active days, never rest. None -> null.
  if (category === "rest") {
    const restCandidates = inPhase.filter((c) => c.category === "rest" && conceptSafeGivenExclusions(c, excludedKeywords));
    if (restCandidates.length === 0) return null;
    return { kind: "preset", concept: restCandidates[rotateByDate(date, restCandidates.length)], optional: true, usedSafeFallback: false };
  }

  let eligible = inPhase.filter((c) => c.category === category || c.category === "any");
  // Light day with no light concept degrades toward mobility, not up in
  // intensity (spec decision 6); other categories degrade toward light.
  if (eligible.length === 0) {
    eligible = inPhase.filter((c) => c.category === "light" || c.category === "rest");
  }
  if (eligible.length === 0) return null;

  // Hangs never on consecutive days: a hang block yesterday removes hang
  // concepts from today's pool before selection.
  const yesterday = addDaysStr(date, -1);
  const hungYesterday = recentGoalBlocks.some((b) => b.date === yesterday && HANG_PATTERN.test(b.text));
  const hangFiltered = hungYesterday ? eligible.filter((c) => !conceptInvolvesHangs(c)) : eligible;

  const safe = hangFiltered.filter((c) => conceptSafeGivenExclusions(c, excludedKeywords));
  if (safe.length > 0) {
    return { kind: "preset", concept: safe[rotateByDate(date, safe.length)], optional: false, usedSafeFallback: false };
  }

  // Exclusions (or the hang rule) emptied the pick -- fall back to the
  // goal's own gentlest safe concept, then the generic safe concept.
  const gentle = inPhase.filter((c) =>
    (c.category === "rest" || c.category === "light") &&
    !(hungYesterday && conceptInvolvesHangs(c)) &&
    conceptSafeGivenExclusions(c, excludedKeywords)
  );
  const fallback = gentle.length > 0 ? gentle[rotateByDate(date, gentle.length)] : SAFE_FALLBACK_CONCEPT;
  if (!conceptSafeGivenExclusions(fallback, excludedKeywords)) {
    // Loud, never silent: even the generic fallback is contraindicated.
    console.warn(`goalWork: goal ${goal.id} -- exclusions [${excludedKeywords.join(", ")}] left no safe concept, emitting no block`);
    return null;
  }
  console.warn(`goalWork: goal ${goal.id} -- exclusions emptied the "${category}" pick, substituting safe concept "${fallback.focus}"`);
  return { kind: "preset", concept: fallback, optional: false, usedSafeFallback: true };
}

/// Schedule rules whose placement is knowable purely from the calendar --
/// unlike "readiness" (deferred entirely to a future day's health data,
/// see isScheduledToday's own case for it) or no rule at all (any day is
/// fair game, gated only by that day's category). Forward-looking
/// scheduling only ever fires for these three: saying "scheduled" about a
/// day whose real placement depends on data that doesn't exist yet would
/// be a fabricated certainty, not a real forecast.
const DETERMINISTIC_SCHEDULE_RULES = new Set(["weekdays", "every_other_day", "before_court_days"]);

export interface UpcomingGoalWorkInput {
  goal: GoalState;
  /// Today's date, matching decideGoalWork's own `date` for the same call.
  date: string;
  recentGoalBlocks: GoalBlockHistoryEntry[];
  /// Today's own goal-work decision, already computed by decideGoalWork
  /// for this same date -- folded into the projected history so an
  /// every_other_day check for TOMORROW correctly counts a block landing
  /// TODAY, exactly as it would once today is itself yesterday.
  todaysDecision: GoalWorkBlock | null;
  /// Human label for a preset goal (e.g. sport_goals.name) -- null degrades
  /// to a generic phrase rather than fabricating a name. Ignored for
  /// custom goals, which use goal.coachName instead.
  sportGoalName: string | null;
}

/// One advisory sentence about the NEXT day (within a 2-day lookahead)
/// the user's active goal program has work scheduled, or null when there's
/// no active goal, it's paused/not visible to this user, or its placement
/// isn't knowable this far ahead (see DETERMINISTIC_SCHEDULE_RULES).
/// Feeds buildPrompt as a soft heads-up only -- it never decides anything
/// itself, and explicitly must never be allowed to override the day's own
/// category, injury exclusions, or equipment constraints (buildPrompt's own
/// wording enforces that at the point this gets embedded).
export function describeUpcomingGoalWork(input: UpcomingGoalWorkInput): string | null {
  const { goal, date, recentGoalBlocks, todaysDecision, sportGoalName } = input;
  if (goal.paused || !goal.sportVisible) return null;
  if (!goal.scheduleRule || !DETERMINISTIC_SCHEDULE_RULES.has(goal.scheduleRule)) return null;

  // Extend the real history with today's own outcome so a tomorrow-check
  // sees today as "yesterday" the same way isScheduledToday would once
  // today has actually passed -- without this, every_other_day would
  // wrongly re-offer tomorrow right after a block landed today.
  const history = todaysDecision === null
    ? recentGoalBlocks
    : [...recentGoalBlocks, {
      date,
      text: todaysDecision.kind === "custom" ? todaysDecision.workoutText : todaysDecision.concept.focus,
    }];

  const who = goal.kind === "custom"
    ? (goal.coachName ? `a coach-assigned session with ${goal.coachName}` : "a coach-assigned session")
    : (sportGoalName ? `${sportGoalName} goal work` : "goal-program work");

  for (let daysAhead = 1; daysAhead <= 2; daysAhead++) {
    const future = addDaysStr(date, daysAhead);
    if (isScheduledToday(goal, future, history)) {
      const when = daysAhead === 1 ? "tomorrow" : "in two days";
      return `Heads up for later: assuming ${when} doesn't turn out to be a rest day, ${who} is scheduled ${when} -- where today's other constraints allow it, avoid needlessly pre-fatiguing the muscles or energy systems that session will need. Never let this override today's actual category, injury exclusions, or equipment above.`;
    }
  }
  return null;
}

/// Block phase from elapsed time: foundation through week 3, peak for the
/// final 2 weeks of the horizon, build between. elapsedWeeks is 0-based
/// (week 1 = 0). Short horizons compress foundation/peak so every block
/// still passes through all three phases in order.
export function derivePhase(elapsedWeeks: number, horizonWeeksHigh: number): "foundation" | "build" | "peak" {
  // Foundation never eats the whole block: capped so build+peak still fit.
  const foundationEnd = Math.max(1, Math.min(3, horizonWeeksHigh - 3));
  const peakStart = Math.max(horizonWeeksHigh - 2, foundationEnd + 1);
  if (elapsedWeeks < foundationEnd) return "foundation";
  if (elapsedWeeks >= peakStart) return "peak";
  return "build";
}

/// Days added to the ETA window per missed session / per low-readiness day.
/// Deterministic and explainable -- the spec's own worked example
/// ("2 missed + 3 low-readiness -> +9 days") pins these constants.
const SHIFT_DAYS_PER_MISSED_SESSION = 3;
const SHIFT_DAYS_PER_LOW_READINESS_DAY = 1;

export interface EtaShiftInput {
  goalKind: "preset" | "custom";
  /// Block window start (ETA window start), YYYY-MM-DD.
  windowStart: string;
  date: string;
  plannedSessionsPerWeek: number;
  /// Goal sessions actually completed inside the window.
  completedSessions: number;
  /// Days in the window whose category was rest/light (low readiness).
  lowReadinessDays: number;
}

export interface EtaInputsArgs {
  plannedPerWeek: number;
  elapsedDays: number;
  /// Dates whose generated plan actually carried a goal block.
  goalBlockDates: string[];
  /// Dates the user logged any workout.
  logDates: string[];
  /// Rest/light recommendation days in the window.
  restLightCount: number;
}

/// computeEtaShift's inputs from raw history. A completed goal session =
/// a day the plan carried a goal block AND a workout was logged; an
/// unrelated logged workout on a non-goal day never counts. Only rest/
/// light days beyond the ~2/week already baked into the horizon slip the
/// ETA -- normal recovery weeks are not "low readiness".
export function deriveEtaInputs(args: EtaInputsArgs): { completedSessions: number; lowReadinessDays: number } {
  const logged = new Set(args.logDates);
  const completedSessions = new Set(args.goalBlockDates.filter((d) => logged.has(d))).size;
  const lowReadinessDays = Math.max(0, args.restLightCount - 2 * Math.floor(args.elapsedDays / 7));
  return { completedSessions, lowReadinessDays };
}

/// Deterministic ETA recompute -- goal fixed, date slides. Returns null
/// for custom goals: the coach owns pacing, the re-check date is fixed.
export function computeEtaShift(input: EtaShiftInput): { shiftDays: number; reason: string } | null {
  if (input.goalKind === "custom") return null;

  const start = new Date(`${input.windowStart}T00:00:00.000Z`).getTime();
  const now = new Date(`${input.date}T00:00:00.000Z`).getTime();
  const elapsedDays = Math.max(0, Math.floor((now - start) / 86400000));
  const perWeek = Math.max(0, input.plannedSessionsPerWeek);
  const expectedSessions = Math.floor((elapsedDays * perWeek) / 7);
  const missedSessions = Math.max(0, expectedSessions - Math.max(0, input.completedSessions));
  const lowDays = Math.max(0, input.lowReadinessDays);

  const shiftDays = missedSessions * SHIFT_DAYS_PER_MISSED_SESSION + lowDays * SHIFT_DAYS_PER_LOW_READINESS_DAY;
  if (shiftDays === 0) {
    return { shiftDays: 0, reason: "On track — no change to your estimated finish date." };
  }
  const parts: string[] = [];
  if (missedSessions > 0) parts.push(`${missedSessions} missed session${missedSessions === 1 ? "" : "s"}`);
  if (lowDays > 0) parts.push(`${lowDays} low-readiness day${lowDays === 1 ? "" : "s"}`);
  return { shiftDays, reason: `${parts.join(" + ")} → +${shiftDays} days` };
}

export interface SafetyPauseInput {
  goalKind: "preset" | "custom";
  /// sport_goals.pregnancy_safe for presets; irrelevant for custom.
  pregnancySafe: boolean | null;
  pregnant: boolean;
  /// Any injury currently at 'severe' severity.
  hasSevereInjury: boolean;
  /// Keywords already acknowledged at creation (safety_ack.warned[].keyword)
  /// -- the user decided with eyes open; those never re-pause.
  ackedKeywords: string[];
  /// Custom only: the coach's stored text, scanned for NEW conflicts.
  workoutText: string | null;
  pregnancyKeywords: string[];
  injuryKeywords: string[];
  /// Preset only: the goal's concepts, to detect an injury that empties
  /// its core (moderate/push_hard) work entirely.
  concepts: GoalWorkConcept[];
}

/// Spec decision 8: hard safety conflicts auto-pause the goal (never just
/// filter it hollow). Deterministic; returns null when the goal may live.
export function decideSafetyPause(input: SafetyPauseInput): { reason: "pregnancy" | "injury" } | null {
  const acked = new Set(input.ackedKeywords.map((k) => k.toLowerCase()));
  const unacked = (keywords: string[], haystack: string): boolean => {
    const text = haystack.toLowerCase();
    return keywords.some((kw) => text.includes(kw.toLowerCase()) && !acked.has(kw.toLowerCase()));
  };

  if (input.pregnant) {
    if (input.goalKind === "preset" && input.pregnancySafe === false) return { reason: "pregnancy" };
    if (input.goalKind === "custom" && input.workoutText && unacked(input.pregnancyKeywords, input.workoutText)) {
      return { reason: "pregnancy" };
    }
  }

  if (input.hasSevereInjury) {
    if (input.goalKind === "custom" && input.workoutText && unacked(input.injuryKeywords, input.workoutText)) {
      return { reason: "injury" };
    }
    // A severe injury that excludes every core concept means the injury
    // touches the goal itself -- pause honestly instead of serving filler.
    if (input.goalKind === "preset" && input.concepts.length > 0) {
      const core = input.concepts.filter((c) => c.category === "moderate" || c.category === "push_hard");
      if (core.length > 0 && core.every((c) => !conceptSafeGivenExclusions(c, input.injuryKeywords))) {
        return { reason: "injury" };
      }
    }
  }

  return null;
}

/// Normalizes a goal_work_concept DB row -- tolerant of either a range
/// array or min/max columns, so a schema tweak can't silently zero doses.
// deno-lint-ignore no-explicit-any
export function conceptFromRow(row: any): GoalWorkConcept | null {
  if (!row || typeof row.category !== "string" || typeof row.description !== "string") return null;
  const range: [number, number] = Array.isArray(row.duration_minutes_range) && row.duration_minutes_range.length === 2
    ? [Number(row.duration_minutes_range[0]), Number(row.duration_minutes_range[1])]
    : [Number(row.duration_minutes_min ?? 10), Number(row.duration_minutes_max ?? 20)];
  return {
    category: row.category,
    phase: typeof row.phase === "string" ? row.phase : null,
    focus: typeof row.focus === "string" ? row.focus : "goal work",
    modality: typeof row.modality === "string" ? row.modality : "drill",
    durationMinutesRange: range,
    // No RPE column in goal_work_concept -- dose_notes carries the caps.
    rpeTarget: typeof row.rpe_target === "string" ? row.rpe_target : null,
    doseNotes: typeof row.dose_notes === "string" ? row.dose_notes : null,
    description: row.description,
  };
}
