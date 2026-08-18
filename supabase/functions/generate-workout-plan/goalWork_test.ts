// Run: deno test supabase/functions/
//
// decideGoalWork is the deterministic half of Sport Goal Programs -- if it
// picks wrong (or silently picks nothing), the goal feature is decorative
// and the safety filtering around the coach's-task path is fiction.

import { assert, assertEquals, assertFalse } from "jsr:@std/assert";
import {
  computeEtaShift,
  conceptFromRow,
  decideGoalWork,
  describeUpcomingGoalWork,
  deriveEtaInputs,
  derivePhase,
  isScheduledToday,
  type GoalState,
  type GoalWorkBlock,
  type GoalWorkConcept,
  type GoalWorkInput,
} from "./goalWork.ts";

const CATEGORIES = ["rest", "light", "moderate", "push_hard"] as const;
const PRESET_TARGET_KINDS = ["metric", "milestone", "qualitative"] as const;

function concept(overrides: Partial<GoalWorkConcept>): GoalWorkConcept {
  return {
    category: "moderate",
    phase: null,
    focus: "goal work",
    modality: "drill",
    durationMinutesRange: [10, 20],
    rpeTarget: "RPE 6-7",
    doseNotes: null,
    description: "practice blocks",
    ...overrides,
  };
}

// Mirrors the blueprint's per-goal matrices: one concept per category,
// the shape every seeded preset goal is required to have.
const FULL_CATALOG: GoalWorkConcept[] = [
  concept({ category: "push_hard", focus: "plyo focus", description: "box jumps and depth jumps, capped contacts" }),
  concept({ category: "moderate", focus: "strength base", description: "squat, hinge, and calf strength work" }),
  concept({ category: "light", focus: "technique", description: "landing mechanics and easy mobility" }),
  concept({ category: "rest", focus: "optional mobility", modality: "mobility_flow", durationMinutesRange: [5, 5], description: "five easy minutes of hip and ankle mobility" }),
];

function goal(overrides: Partial<GoalState>): GoalState {
  return {
    id: "goal-1",
    kind: "preset",
    targetKind: "metric",
    phase: null,
    paused: false,
    sportVisible: true,
    scheduleRule: null,
    scheduleDays: null,
    courtDays: null,
    workoutText: null,
    coachName: null,
    frequencyPerWeek: null,
    ...overrides,
  };
}

function input(overrides: Partial<GoalWorkInput>): GoalWorkInput {
  return {
    category: "moderate",
    date: "2026-08-03",
    goal: goal({}),
    concepts: FULL_CATALOG,
    excludedKeywords: [],
    recentGoalBlocks: [],
    ...overrides,
  };
}

Deno.test("INVARIANT: every category yields a block for every preset goal kind with empty exclusions", () => {
  // A fully seeded goal (a concept per category) must produce goal work on
  // every active day and the optional mobility dose on rest days.
  for (const targetKind of PRESET_TARGET_KINDS) {
    for (const category of CATEGORIES) {
      const block = decideGoalWork(input({ category, goal: goal({ targetKind }) }));
      assert(block, `no block for ${targetKind}/${category}`);
      assertEquals(block.kind, "preset");
      if (block.kind === "preset") {
        assertEquals(block.optional, category === "rest", `${category}: wrong optional flag`);
      }
    }
  }
});

Deno.test("INVARIANT: custom block is byte-identical to workout_text and carries the coach name", () => {
  const workoutText = "  3x10 approach jumps\n2x5 depth jumps @ 40cm — exactly as written  ";
  const block = decideGoalWork(input({
    goal: goal({ kind: "custom", targetKind: "commitment", workoutText, coachName: "Coach Ana" }),
  }));
  assert(block && block.kind === "custom");
  // Byte-identical: no trim, no rewrite, no normalization of any kind.
  assertEquals(block.workoutText, workoutText);
  assertEquals(block.builtWith, "Coach Ana");
});

Deno.test("INVARIANT: paused goal is always null, for every category and kind", () => {
  for (const category of CATEGORIES) {
    for (const kind of ["preset", "custom"] as const) {
      const block = decideGoalWork(input({
        category,
        goal: goal({ kind, paused: true, workoutText: kind === "custom" ? "coach text" : null }),
      }));
      assertEquals(block, null, `paused ${kind} goal emitted a block on ${category}`);
    }
  }
});

Deno.test("INVARIANT: exclusions never silently empty the pick -- a safe concept is substituted", () => {
  // "jump" wipes push_hard; the pick must degrade to a safe concept from
  // the goal's own gentler rows, flagged so the caller can see it.
  const block = decideGoalWork(input({ category: "push_hard", excludedKeywords: ["jump"] }));
  assert(block && block.kind === "preset");
  assertFalse(/jump/i.test(block.concept.description));
  assert(block.usedSafeFallback);
});

Deno.test("INVARIANT: when every concept is excluded, the generic safe fallback still appears", () => {
  const wipeEverything = ["jump", "squat", "landing", "ankle"];
  const block = decideGoalWork(input({ category: "moderate", excludedKeywords: wipeEverything }));
  assert(block && block.kind === "preset", "exclusions silently emptied the pick");
  assert(block.usedSafeFallback);
  const text = `${block.concept.description} ${block.concept.modality} ${block.concept.focus}`.toLowerCase();
  assertFalse(wipeEverything.some((kw) => text.includes(kw)), "fallback itself is contraindicated");
});

Deno.test("dose_notes participate in exclusion filtering, not just the description", () => {
  const catalog = [
    concept({ category: "moderate", focus: "footwork", description: "cone patterns", doseNotes: "finish with jump landings" }),
    concept({ category: "light", focus: "easy technique", description: "slow footwork patterns" }),
  ];
  const block = decideGoalWork(input({ concepts: catalog, excludedKeywords: ["jump"] }));
  assert(block && block.kind === "preset");
  assertEquals(block.concept.focus, "easy technique");
});

Deno.test("sport not visible to this user emits no block (server-side gate)", () => {
  assertEquals(decideGoalWork(input({ goal: goal({ sportVisible: false }) })), null);
});

Deno.test("REGRESSION: before_court_days schedules the day BEFORE each court day only", () => {
  // 2026-08-03 is a Monday (getUTCDay 1). Court day Tuesday (2) -> Monday
  // is scheduled; Tuesday itself and Wednesday are not.
  const custom = (date: string) =>
    decideGoalWork(input({
      date,
      goal: goal({ kind: "custom", scheduleRule: "before_court_days", courtDays: [2], workoutText: "coach session" }),
    }));
  assert(custom("2026-08-03"), "Monday before a Tuesday court day should be scheduled");
  assertEquals(custom("2026-08-04"), null, "the court day itself is not a goal-session day");
  assertEquals(custom("2026-08-05"), null);
  // Sunday court day (0) wraps: Saturday (6) is the day before.
  const beforeSunday = decideGoalWork(input({
    date: "2026-08-08",
    goal: goal({ kind: "custom", scheduleRule: "before_court_days", courtDays: [0], workoutText: "coach session" }),
  }));
  assert(beforeSunday, "Saturday before a Sunday court day should be scheduled");
});

Deno.test("REGRESSION: hangs never land on consecutive days", () => {
  const hangCatalog: GoalWorkConcept[] = [
    concept({ category: "push_hard", focus: "hang intervals", description: "sub-max dead hang intervals on a bar" }),
    concept({ category: "push_hard", focus: "pull strength", description: "scapular pull-ups and rows" }),
    concept({ category: "light", focus: "forearm mobility", description: "wrist and forearm mobility" }),
  ];
  // Whatever the rotation picks, a hang concept must not follow a hang day.
  for (const date of ["2026-08-03", "2026-08-05", "2026-08-07"]) {
    const block = decideGoalWork(input({
      category: "push_hard",
      date,
      concepts: hangCatalog,
      recentGoalBlocks: [{ date: addDays(date, -1), text: "hang intervals: sub-max dead hang intervals" }],
    }));
    assert(block && block.kind === "preset");
    assertFalse(/hang/i.test(`${block.concept.focus} ${block.concept.description}`), `${date}: hang block on consecutive days`);
  }
  // Without a hang yesterday, hang concepts stay pickable on some date.
  const dates = ["2026-08-03", "2026-08-04", "2026-08-05"];
  const picked = dates.map((d) => decideGoalWork(input({ category: "push_hard", date: d, concepts: hangCatalog })));
  assert(picked.some((b) => b && b.kind === "preset" && /hang/i.test(b.concept.focus)));
});

Deno.test("REGRESSION: rest day returns null-or-mobility only", () => {
  // With a rest concept: an optional, mobility-dosed block.
  const withRest = decideGoalWork(input({ category: "rest" }));
  assert(withRest && withRest.kind === "preset");
  assert(withRest.optional);
  assertEquals(withRest.concept.category, "rest");
  // Without one: nothing -- "any" concepts never leak onto rest days.
  const noRestCatalog = [
    concept({ category: "any", focus: "daily mobility block" }),
    concept({ category: "push_hard" }),
  ];
  assertEquals(decideGoalWork(input({ category: "rest", concepts: noRestCatalog })), null);
  // Custom goals shift off rest days entirely -- coach content untouched.
  assertEquals(
    decideGoalWork(input({ category: "rest", goal: goal({ kind: "custom", workoutText: "coach session" }) })),
    null,
  );
});

Deno.test("custom goal on an unscheduled weekday returns null (day-shifted, never rewritten)", () => {
  // 2026-08-03 is Monday (1); schedule only Wed (3).
  const block = decideGoalWork(input({
    goal: goal({ kind: "custom", scheduleRule: "weekdays", scheduleDays: [3], workoutText: "coach session" }),
  }));
  assertEquals(block, null);
});

Deno.test("every_other_day skips the day after a goal block", () => {
  const g = goal({ kind: "custom", scheduleRule: "every_other_day", workoutText: "coach session" });
  const afterBlock = decideGoalWork(input({
    goal: g,
    recentGoalBlocks: [{ date: "2026-08-02", text: "coach block" }],
  }));
  assertEquals(afterBlock, null);
  assert(decideGoalWork(input({ goal: g, recentGoalBlocks: [{ date: "2026-08-01", text: "coach block" }] })));
});

Deno.test("readiness rule waits for a moderate/push_hard day", () => {
  const g = goal({ kind: "custom", scheduleRule: "readiness", workoutText: "coach session" });
  assertEquals(decideGoalWork(input({ category: "light", goal: g })), null);
  assert(decideGoalWork(input({ category: "moderate", goal: g })));
  const preset = goal({ scheduleRule: "readiness" });
  assertEquals(decideGoalWork(input({ category: "light", goal: preset })), null);
  assert(decideGoalWork(input({ category: "push_hard", goal: preset })));
});

Deno.test("phase filters concepts; null-phase concepts serve every phase", () => {
  const phased: GoalWorkConcept[] = [
    concept({ category: "moderate", phase: "foundation", focus: "foundation strength" }),
    concept({ category: "moderate", phase: "peak", focus: "peak reactive" }),
    concept({ category: "light", phase: null, focus: "shared technique" }),
  ];
  const block = decideGoalWork(input({ concepts: phased, goal: goal({ phase: "peak" }) }));
  assert(block && block.kind === "preset");
  assertEquals(block.concept.focus, "peak reactive");
});

// --- derivePhase ---

Deno.test("derivePhase: foundation through week 3, peak for the final 2 weeks, build between", () => {
  // 10-week horizon; elapsedWeeks is 0-based (week 1 = 0).
  assertEquals(derivePhase(0, 10), "foundation");
  assertEquals(derivePhase(2, 10), "foundation", "week 3 is still foundation");
  assertEquals(derivePhase(3, 10), "build", "week 4 starts build");
  assertEquals(derivePhase(7, 10), "build");
  assertEquals(derivePhase(8, 10), "peak", "final 2 weeks are peak");
  assertEquals(derivePhase(9, 10), "peak");
  // A 12-week horizon peaks in weeks 11-12 only.
  assertEquals(derivePhase(9, 12), "build");
  assertEquals(derivePhase(10, 12), "peak");
});

Deno.test("derivePhase: an overdue block stays in peak, never regresses", () => {
  assertEquals(derivePhase(15, 10), "peak");
});

Deno.test("derivePhase: degenerate short horizons still pass through all three phases in order", () => {
  for (const horizon of [3, 4, 5]) {
    const phases = Array.from({ length: horizon }, (_, w) => derivePhase(w, horizon));
    assert(phases.includes("foundation"), `horizon ${horizon}: no foundation`);
    assert(phases.includes("build"), `horizon ${horizon}: no build`);
    assert(phases.includes("peak"), `horizon ${horizon}: no peak`);
    // Monotonic: never back from build to foundation or peak to build.
    const order = { foundation: 0, build: 1, peak: 2 };
    for (let i = 1; i < phases.length; i++) {
      assert(order[phases[i]] >= order[phases[i - 1]], `horizon ${horizon}: ${phases.join(" -> ")}`);
    }
  }
});

// --- deriveEtaInputs ---

Deno.test("INVARIANT: fully compliant user with the normal ~2 rest days/week slips zero", () => {
  // 4 weeks, 3 goal-block days/week all logged, 2 rest/light days/week.
  const goalBlockDates = ["-07-06", "-07-08", "-07-10", "-07-13", "-07-15", "-07-17", "-07-20", "-07-22", "-07-24", "-07-27", "-07-29", "-07-31"].map((d) => `2026${d}`);
  const inputs = deriveEtaInputs({
    plannedPerWeek: 3,
    elapsedDays: 28,
    goalBlockDates,
    logDates: goalBlockDates,
    restLightCount: 8,
  });
  assertEquals(inputs, { completedSessions: 12, lowReadinessDays: 0 });
  const shift = computeEtaShift({
    goalKind: "preset",
    windowStart: "2026-07-06",
    date: "2026-08-03",
    plannedSessionsPerWeek: 3,
    completedSessions: inputs.completedSessions,
    lowReadinessDays: inputs.lowReadinessDays,
  });
  assertEquals(shift?.shiftDays, 0);
});

Deno.test("only rest/light days BEYOND ~2/week count against the ETA", () => {
  // 12 rest/light days in 4 weeks (3/wk): only the 4 above the baked-in
  // 2/wk baseline slip the date -- not all 12 as the old inputs did.
  const inputs = deriveEtaInputs({ plannedPerWeek: 3, elapsedDays: 28, goalBlockDates: [], logDates: [], restLightCount: 12 });
  assertEquals(inputs.lowReadinessDays, 4);
});

Deno.test("REGRESSION: unrelated logged workouts never count as goal sessions", () => {
  // Every goal-block day was skipped; the user logged other workouts on
  // other days. Completed must be 0, and the shift counts real misses.
  const inputs = deriveEtaInputs({
    plannedPerWeek: 3,
    elapsedDays: 7,
    goalBlockDates: ["2026-07-27", "2026-07-29", "2026-07-31"],
    logDates: ["2026-07-28", "2026-08-01"],
    restLightCount: 2,
  });
  assertEquals(inputs, { completedSessions: 0, lowReadinessDays: 0 });
  const shift = computeEtaShift({
    goalKind: "preset",
    windowStart: "2026-07-27",
    date: "2026-08-03",
    plannedSessionsPerWeek: 3,
    completedSessions: inputs.completedSessions,
    lowReadinessDays: inputs.lowReadinessDays,
  });
  assertEquals(shift?.shiftDays, 9, "3 missed sessions -> +9 days");
});

Deno.test("a goal-block day both planned and logged counts once, mixed with misses", () => {
  const inputs = deriveEtaInputs({
    plannedPerWeek: 3,
    elapsedDays: 7,
    goalBlockDates: ["2026-07-27", "2026-07-29", "2026-07-31"],
    logDates: ["2026-07-27", "2026-07-27", "2026-08-01"],
    restLightCount: 0,
  });
  assertEquals(inputs.completedSessions, 1);
});

// --- computeEtaShift ---

Deno.test("ETA shift reproduces the spec's worked example: 2 missed + 3 low-readiness -> +9 days", () => {
  // 4 weeks at 3/wk = 12 expected; 10 done = 2 missed.
  const shift = computeEtaShift({
    goalKind: "preset",
    windowStart: "2026-07-06",
    date: "2026-08-03",
    plannedSessionsPerWeek: 3,
    completedSessions: 10,
    lowReadinessDays: 3,
  });
  assert(shift);
  assertEquals(shift.shiftDays, 9);
  assertEquals(shift.reason, "2 missed sessions + 3 low-readiness days → +9 days");
});

Deno.test("ETA shift is zero -- with an explanation -- when the user is on pace", () => {
  const shift = computeEtaShift({
    goalKind: "preset",
    windowStart: "2026-07-27",
    date: "2026-08-03",
    plannedSessionsPerWeek: 3,
    completedSessions: 3,
    lowReadinessDays: 0,
  });
  assert(shift);
  assertEquals(shift.shiftDays, 0);
  assert(shift.reason.length > 0);
});

Deno.test("ETA shift is skipped entirely for custom goals -- the coach owns pacing", () => {
  assertEquals(
    computeEtaShift({
      goalKind: "custom",
      windowStart: "2026-07-06",
      date: "2026-08-03",
      plannedSessionsPerWeek: 3,
      completedSessions: 0,
      lowReadinessDays: 5,
    }),
    null,
  );
});

Deno.test("ETA shift never goes negative when the user is ahead of schedule", () => {
  const shift = computeEtaShift({
    goalKind: "preset",
    windowStart: "2026-07-27",
    date: "2026-08-03",
    plannedSessionsPerWeek: 2,
    completedSessions: 6,
    lowReadinessDays: 0,
  });
  assert(shift);
  assertEquals(shift.shiftDays, 0);
});

// --- conceptFromRow ---

Deno.test("conceptFromRow accepts min/max columns and rejects malformed rows", () => {
  const fromMinMax = conceptFromRow({
    category: "moderate",
    phase: "build",
    focus: "plyo focus",
    modality: "drill",
    duration_minutes_min: 8,
    duration_minutes_max: 15,
    dose_notes: "80-100 contacts max, 48-72h between plyo days",
    description: "hurdle hops",
  });
  assert(fromMinMax);
  assertEquals(fromMinMax.durationMinutesRange, [8, 15]);
  assertEquals(fromMinMax.doseNotes, "80-100 contacts max, 48-72h between plyo days");
  assertEquals(fromMinMax.rpeTarget, null);
  assertEquals(conceptFromRow({ focus: "no category or description" }), null);
  assertEquals(conceptFromRow(null), null);
});

function addDays(dateStr: string, days: number): string {
  const d = new Date(`${dateStr}T00:00:00.000Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}

// --- decideSafetyPause (spec decision 8: hard conflicts pause, not filter) ---

import { decideSafetyPause, type SafetyPauseInput } from "./goalWork.ts";

function pauseInput(overrides: Partial<SafetyPauseInput>): SafetyPauseInput {
  return {
    goalKind: "preset",
    pregnancySafe: null,
    pregnant: false,
    hasSevereInjury: false,
    ackedKeywords: [],
    workoutText: null,
    pregnancyKeywords: ["depth jump", "plyometric", "jump"],
    injuryKeywords: ["depth jump", "box jump"],
    concepts: FULL_CATALOG,
    ...overrides,
  };
}

Deno.test("INVARIANT: healthy user never triggers a safety pause, any goal kind", () => {
  assertEquals(decideSafetyPause(pauseInput({})), null);
  assertEquals(decideSafetyPause(pauseInput({ goalKind: "custom", workoutText: "depth jumps 4x5" })), null);
});

Deno.test("INVARIANT: pregnancy pauses a pregnancy-unsafe preset and spares a safe one", () => {
  assertEquals(decideSafetyPause(pauseInput({ pregnant: true, pregnancySafe: false }))?.reason, "pregnancy");
  assertEquals(decideSafetyPause(pauseInput({ pregnant: true, pregnancySafe: true })), null);
});

Deno.test("pregnancy with an unknown catalog flag does not pause (fails open to content filtering)", () => {
  // Null = column missing/unreadable; the exclusion filter still governs
  // every exercise, so the goal survives rather than vanishing on a glitch.
  assertEquals(decideSafetyPause(pauseInput({ pregnant: true, pregnancySafe: null })), null);
});

Deno.test("INVARIANT: pregnancy pauses a custom goal whose text has UNacknowledged conflicts", () => {
  const paused = decideSafetyPause(pauseInput({
    goalKind: "custom",
    pregnant: true,
    workoutText: "Depth jumps 4x5 after warm-up",
  }));
  assertEquals(paused?.reason, "pregnancy");
});

Deno.test("INVARIANT: an acknowledgment given with eyes open never re-pauses", () => {
  // create-goal warns on every matching keyword at once, so a real ack
  // covers the full matched set -- the fixture mirrors that.
  const spared = decideSafetyPause(pauseInput({
    goalKind: "custom",
    pregnant: true,
    workoutText: "Depth jumps 4x5 after warm-up",
    ackedKeywords: ["depth jump", "jump"],
  }));
  assertEquals(spared, null);
});

Deno.test("a NEW conflict keyword appearing after the ack still pauses", () => {
  // Acked "depth jump" alone does not cover the broader "jump" match --
  // e.g. the exclusion list widened when the pregnancy week was updated.
  const paused = decideSafetyPause(pauseInput({
    goalKind: "custom",
    pregnant: true,
    workoutText: "Depth jumps 4x5 after warm-up",
    ackedKeywords: ["depth jump"],
  }));
  assertEquals(paused?.reason, "pregnancy");
});

Deno.test("INVARIANT: severe injury pauses a preset only when it empties the goal's core work", () => {
  const allCoreExcluded = decideSafetyPause(pauseInput({
    hasSevereInjury: true,
    injuryKeywords: ["plyo", "strength"],
  }));
  assertEquals(allCoreExcluded?.reason, "injury");
  const coreSurvives = decideSafetyPause(pauseInput({
    hasSevereInjury: true,
    injuryKeywords: ["box jump"],
  }));
  assertEquals(coreSurvives, null);
});

Deno.test("severe injury pauses a custom goal on unacked conflicts; mild injuries never pause", () => {
  assertEquals(
    decideSafetyPause(pauseInput({ goalKind: "custom", hasSevereInjury: true, workoutText: "Box jumps 3x6" }))?.reason,
    "injury",
  );
  assertEquals(
    decideSafetyPause(pauseInput({ goalKind: "custom", hasSevereInjury: false, workoutText: "Box jumps 3x6" })),
    null,
  );
});

Deno.test("INVARIANT: coach text stays byte-identical even when exclusions match it", () => {
  // Exclusions govern preset concept picking; an acknowledged custom block
  // is day-shifted or safety-paused, never silently rewritten.
  const text = "Depth drops 4x5, approach jumps 3x6 — after warm-up.";
  const block = decideGoalWork(input({
    goal: goal({ kind: "custom", targetKind: "commitment", workoutText: text, coachName: "Reyes" }),
    excludedKeywords: ["depth drop", "approach jump"],
    category: "moderate",
  }));
  assertEquals(block?.kind, "custom");
  assert(block?.kind === "custom" && block.workoutText === text);
});

// --- isScheduledToday (exported for describeUpcomingGoalWork) / describeUpcomingGoalWork ---

const PRESET_BLOCK: GoalWorkBlock = {
  kind: "preset",
  concept: concept({ focus: "goal work" }),
  optional: false,
  usedSafeFallback: false,
};

Deno.test("isScheduledToday: weekdays rule matches only the listed weekday ints", () => {
  const g = goal({ scheduleRule: "weekdays", scheduleDays: [2] }); // Tuesday
  assertFalse(isScheduledToday(g, "2026-08-03", [])); // Monday
  assert(isScheduledToday(g, "2026-08-04", [])); // Tuesday
});

Deno.test("isScheduledToday: every_other_day is false the day right after a block, true otherwise", () => {
  const g = goal({ scheduleRule: "every_other_day" });
  assertFalse(isScheduledToday(g, "2026-08-04", [{ date: "2026-08-03", text: "x" }]));
  assert(isScheduledToday(g, "2026-08-04", [{ date: "2026-08-02", text: "x" }]));
});

Deno.test("REGRESSION: the plain 'N x a week' chip (scheduleRule null) used to be ignored entirely -- frequencyPerWeek now caps the trailing 7-day window", () => {
  // No history yet: any frequency allows today.
  const twicePerWeek = goal({ scheduleRule: null, frequencyPerWeek: 2 });
  assert(isScheduledToday(twicePerWeek, "2026-08-07", []));
  // One block already this window: still under the cap of 2.
  assert(isScheduledToday(twicePerWeek, "2026-08-07", [{ date: "2026-08-03", text: "x" }]));
  // Two blocks already in the trailing 7-day window (today - 6 .. today - 1):
  // the cap is reached, today is not scheduled.
  assertFalse(isScheduledToday(twicePerWeek, "2026-08-07", [
    { date: "2026-08-02", text: "x" },
    { date: "2026-08-04", text: "x" },
  ]));
  // A block from 8 days ago is outside the window and doesn't count.
  assert(isScheduledToday(twicePerWeek, "2026-08-07", [
    { date: "2026-07-30", text: "x" },
    { date: "2026-08-04", text: "x" },
  ]));
  // No explicit count (legacy goals predating this field): unlimited, same
  // as the old always-true default.
  assert(isScheduledToday(goal({ scheduleRule: null, frequencyPerWeek: null }), "2026-08-07", [
    { date: "2026-08-02", text: "x" },
    { date: "2026-08-03", text: "x" },
    { date: "2026-08-04", text: "x" },
  ]));
});

Deno.test("REGRESSION: decideGoalWork actually withholds a preset block once frequencyPerWeek is reached, and a custom goal too", () => {
  const cappedPreset = goal({ frequencyPerWeek: 1 });
  const first = decideGoalWork(input({ date: "2026-08-07", goal: cappedPreset, recentGoalBlocks: [] }));
  assert(first, "first session of the week should still be scheduled");
  const second = decideGoalWork(input({
    date: "2026-08-07",
    goal: cappedPreset,
    recentGoalBlocks: [{ date: "2026-08-05", text: "goal work" }],
  }));
  assertEquals(second, null, "a second session this week should be withheld once frequencyPerWeek: 1 is already met");

  const cappedCustom = goal({ kind: "custom", frequencyPerWeek: 1, workoutText: "coach session" });
  const custom = decideGoalWork(input({
    date: "2026-08-07",
    goal: cappedCustom,
    recentGoalBlocks: [{ date: "2026-08-05", text: "coach session" }],
  }));
  assertEquals(custom, null, "custom goals must respect the same weekly cap");
});

Deno.test("describeUpcomingGoalWork: null for paused or not-visible goals", () => {
  const base = { date: "2026-08-03", recentGoalBlocks: [], todaysDecision: null, sportGoalName: null };
  assertEquals(
    describeUpcomingGoalWork({ ...base, goal: goal({ scheduleRule: "weekdays", scheduleDays: [2], paused: true }) }),
    null,
  );
  assertEquals(
    describeUpcomingGoalWork({ ...base, goal: goal({ scheduleRule: "weekdays", scheduleDays: [2], sportVisible: false }) }),
    null,
  );
});

Deno.test("describeUpcomingGoalWork: null for readiness/unset schedule rules -- unknowable this far ahead", () => {
  const base = { date: "2026-08-03", recentGoalBlocks: [], todaysDecision: null, sportGoalName: null };
  assertEquals(describeUpcomingGoalWork({ ...base, goal: goal({ scheduleRule: "readiness" }) }), null);
  assertEquals(describeUpcomingGoalWork({ ...base, goal: goal({ scheduleRule: null }) }), null);
});

Deno.test("describeUpcomingGoalWork: says 'tomorrow' when scheduled 1 day out, 'in two days' when 2 days out", () => {
  const base = { date: "2026-08-03", recentGoalBlocks: [], todaysDecision: null, sportGoalName: null };
  // Monday 2026-08-03; Tuesday (2) is tomorrow.
  const tomorrow = describeUpcomingGoalWork({ ...base, goal: goal({ scheduleRule: "weekdays", scheduleDays: [2] }) });
  assert(tomorrow?.includes("tomorrow"));
  // Wednesday (3) is two days out -- Tuesday isn't scheduled, so this
  // must skip past it to day+2 rather than stopping at "not scheduled".
  const inTwoDays = describeUpcomingGoalWork({ ...base, goal: goal({ scheduleRule: "weekdays", scheduleDays: [3] }) });
  assert(inTwoDays?.includes("in two days"));
});

Deno.test("describeUpcomingGoalWork: names the coach for custom goals, the catalog name for preset goals", () => {
  const base = { date: "2026-08-03", recentGoalBlocks: [], todaysDecision: null };
  const customLine = describeUpcomingGoalWork({
    ...base,
    goal: goal({ kind: "custom", scheduleRule: "weekdays", scheduleDays: [2], coachName: "Coach Ana", workoutText: "x" }),
    sportGoalName: null,
  });
  assert(customLine?.includes("Coach Ana"));
  const presetLine = describeUpcomingGoalWork({
    ...base,
    goal: goal({ scheduleRule: "weekdays", scheduleDays: [2] }),
    sportGoalName: "Climb V5",
  });
  assert(presetLine?.includes("Climb V5"));
});

Deno.test("describeUpcomingGoalWork: degrades to a generic phrase when no catalog name is available", () => {
  const line = describeUpcomingGoalWork({
    date: "2026-08-03",
    recentGoalBlocks: [],
    todaysDecision: null,
    goal: goal({ scheduleRule: "weekdays", scheduleDays: [2] }),
    sportGoalName: null,
  });
  assert(line?.includes("goal-program work"));
});

Deno.test("describeUpcomingGoalWork: today's own decision correctly suppresses an every_other_day 'tomorrow', then resumes at day+2", () => {
  const g = goal({ scheduleRule: "every_other_day" });
  const line = describeUpcomingGoalWork({
    date: "2026-08-03",
    recentGoalBlocks: [],
    todaysDecision: PRESET_BLOCK, // a block lands TODAY
    goal: g,
    sportGoalName: null,
  });
  // Tomorrow is skipped (a block just landed today); day+2 resumes.
  assert(line?.includes("in two days"), `expected day+2, got: ${line}`);
});

Deno.test("describeUpcomingGoalWork: never fires when there's simply nothing scheduled in the 2-day window", () => {
  // Weekday-only Sunday goal, checked from a Monday -- 6 days away, outside
  // the lookahead entirely.
  const line = describeUpcomingGoalWork({
    date: "2026-08-03",
    recentGoalBlocks: [],
    todaysDecision: null,
    goal: goal({ scheduleRule: "weekdays", scheduleDays: [0] }),
    sportGoalName: null,
  });
  assertEquals(line, null);
});
