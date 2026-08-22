import { assertEquals } from "jsr:@std/assert";
import {
  CONSECUTIVE_DAYS_THRESHOLD,
  computeExceptionalReadinessBypassAllowed,
  computeInjuryProtocolRestApplied,
  computeMoodCapApplied,
  computeProactiveRestCapApplied,
  LOW_MOOD_RATING_THRESHOLD,
  PROACTIVE_REST_MIN_RECOMMENDATIONS,
  RECENT_SEVERE_INJURY_WINDOW_HOURS,
  REST_ESCALATION_THRESHOLD,
  SEVERE_INJURY_BAD_DAYS_TO_REST,
} from "./independentCaps.ts";

const HOUR_MS = 3600 * 1000;

Deno.test("computeInjuryProtocolRestApplied: no severe injuries -> false", () => {
  assertEquals(computeInjuryProtocolRestApplied([], Date.now()), false);
});

Deno.test("computeInjuryProtocolRestApplied: severe injury reported minutes ago -> true", () => {
  const now = Date.now();
  const rows = [{ protocol_started_at: new Date(now - 5 * 60 * 1000).toISOString(), consecutive_bad_days: 0 }];
  assertEquals(computeInjuryProtocolRestApplied(rows, now), true);
});

Deno.test("computeInjuryProtocolRestApplied: severe injury reported exactly at the window boundary -> true", () => {
  const now = Date.now();
  const rows = [{
    protocol_started_at: new Date(now - RECENT_SEVERE_INJURY_WINDOW_HOURS * HOUR_MS).toISOString(),
    consecutive_bad_days: 0,
  }];
  assertEquals(computeInjuryProtocolRestApplied(rows, now), true);
});

Deno.test("computeInjuryProtocolRestApplied: severe injury reported well outside the window with no bad streak -> false", () => {
  const now = Date.now();
  const rows = [{
    protocol_started_at: new Date(now - (RECENT_SEVERE_INJURY_WINDOW_HOURS + 1) * HOUR_MS).toISOString(),
    consecutive_bad_days: 0,
  }];
  assertEquals(computeInjuryProtocolRestApplied(rows, now), false);
});

Deno.test("computeInjuryProtocolRestApplied: old severe injury trending worse for the threshold -> true", () => {
  const now = Date.now();
  const rows = [{
    protocol_started_at: new Date(now - 30 * 24 * HOUR_MS).toISOString(),
    consecutive_bad_days: SEVERE_INJURY_BAD_DAYS_TO_REST,
  }];
  assertEquals(computeInjuryProtocolRestApplied(rows, now), true);
});

Deno.test("computeInjuryProtocolRestApplied: old severe injury one bad day short of the threshold -> false", () => {
  const now = Date.now();
  const rows = [{
    protocol_started_at: new Date(now - 30 * 24 * HOUR_MS).toISOString(),
    consecutive_bad_days: SEVERE_INJURY_BAD_DAYS_TO_REST - 1,
  }];
  assertEquals(computeInjuryProtocolRestApplied(rows, now), false);
});

Deno.test("computeInjuryProtocolRestApplied: one qualifying row among several old, stable ones -> true", () => {
  const now = Date.now();
  const rows = [
    { protocol_started_at: new Date(now - 30 * 24 * HOUR_MS).toISOString(), consecutive_bad_days: 0 },
    { protocol_started_at: new Date(now - 1 * HOUR_MS).toISOString(), consecutive_bad_days: 0 },
  ];
  assertEquals(computeInjuryProtocolRestApplied(rows, now), true);
});

Deno.test("computeMoodCapApplied: rough mood (1) on a push_hard day downgrades", () => {
  assertEquals(computeMoodCapApplied(1, "push_hard"), true);
});

Deno.test("computeMoodCapApplied: not-great mood at the threshold (2) on a moderate day downgrades", () => {
  assertEquals(computeMoodCapApplied(LOW_MOOD_RATING_THRESHOLD, "moderate"), true);
});

Deno.test("computeMoodCapApplied: okay mood (3) does not downgrade", () => {
  assertEquals(computeMoodCapApplied(3, "push_hard"), false);
});

Deno.test("computeMoodCapApplied: great mood (5) never upgrades a rest/light day -- cap simply doesn't apply", () => {
  assertEquals(computeMoodCapApplied(5, "push_hard"), false);
});

Deno.test("computeMoodCapApplied: rough mood on an already-light day doesn't re-fire (nothing lower to cap to via this path)", () => {
  assertEquals(computeMoodCapApplied(1, "light"), false);
});

Deno.test("computeMoodCapApplied: no check-in today (null) never caps", () => {
  assertEquals(computeMoodCapApplied(null, "push_hard"), false);
});

// --- computeExceptionalReadinessBypassAllowed ---
//
// BUG this covers: exceptionalReadinessToday used to bypass the
// consecutive-days/volume/proactive-rest caps unconditionally, with no
// limit on how many consecutive exceptional-readiness days could each
// waive them -- a genuinely great WEEK could go on forever with no real
// rest/active-recovery day ever recommended. Fix reuses consecutiveDays
// (already computed for the consecutive-days cap) as the ceiling rather
// than inventing a new counter.

Deno.test("a non-exceptional day never bypasses, regardless of streak length", () => {
  assertEquals(computeExceptionalReadinessBypassAllowed(false, 0), false);
  assertEquals(computeExceptionalReadinessBypassAllowed(false, REST_ESCALATION_THRESHOLD + 10), false);
});

Deno.test("an exceptional day still bypasses below the ceiling, exactly like before this fix", () => {
  assertEquals(computeExceptionalReadinessBypassAllowed(true, 0), true);
  assertEquals(computeExceptionalReadinessBypassAllowed(true, REST_ESCALATION_THRESHOLD - 1), true);
});

Deno.test("an exceptional day no longer bypasses once the streak reaches the real ceiling", () => {
  assertEquals(computeExceptionalReadinessBypassAllowed(true, REST_ESCALATION_THRESHOLD), false);
  assertEquals(computeExceptionalReadinessBypassAllowed(true, REST_ESCALATION_THRESHOLD + 3), false);
});

Deno.test("REGRESSION: a multi-day run of exceptional readiness eventually stops bypassing -- the exact reported scenario", () => {
  // Simulates the real report: readiness reads exceptional every single
  // day. Walk consecutiveDays up as if each prior day's cap had been
  // (correctly) bypassed and therefore stayed a training day -- exactly
  // how the real streak grows in generate-recommendation/index.ts, since
  // a bypassed day's category stays moderate/push_hard.
  const bypassedByDay: boolean[] = [];
  for (let consecutiveDays = 0; consecutiveDays <= REST_ESCALATION_THRESHOLD + 5; consecutiveDays++) {
    bypassedByDay.push(computeExceptionalReadinessBypassAllowed(true, consecutiveDays));
  }
  // Bypassed every day the streak is still under the ceiling...
  for (let i = 0; i < REST_ESCALATION_THRESHOLD; i++) {
    assertEquals(bypassedByDay[i], true, `day with consecutiveDays=${i} should still bypass`);
  }
  // ...and, critically, NOT bypassed forever -- a rest/light day must
  // eventually get through once the real ceiling is hit, no matter how
  // many more exceptional days follow.
  for (let i = REST_ESCALATION_THRESHOLD; i < bypassedByDay.length; i++) {
    assertEquals(bypassedByDay[i], false, `day with consecutiveDays=${i} must NOT bypass -- this is the bug`);
  }
});

Deno.test("CONSECUTIVE_DAYS_THRESHOLD stays below REST_ESCALATION_THRESHOLD -- the lighter cap must still be reachable before the ceiling", () => {
  // Not a behavior test of the function itself -- a sanity check on the
  // two constants' relative ordering, since computeExceptionalReadinessBypassAllowed
  // implicitly assumes the ceiling (REST_ESCALATION_THRESHOLD) sits at or
  // above the point the consecutive-days cap would otherwise first fire
  // (CONSECUTIVE_DAYS_THRESHOLD) -- if that ever inverted, the bypass
  // could outlive the cap it's supposed to eventually yield to.
  assertEquals(CONSECUTIVE_DAYS_THRESHOLD <= REST_ESCALATION_THRESHOLD, true);
});

// --- computeProactiveRestCapApplied ---
//
// NOTE: this function's 3rd parameter is exceptionalReadinessBypassAllowed
// (see computeExceptionalReadinessBypassAllowed above), not the raw
// same-day exceptional reading -- tests below that pass a bare `true`/
// `false` are exercising this function's own "does bypass=true skip the
// floor" behavior, independent of how that boolean gets computed
// upstream (covered separately above).

const aFullWeekOfHardTraining: ("rest" | "light" | "moderate" | "push_hard")[] = [
  "moderate", "push_hard", "moderate", "push_hard", "moderate", "push_hard", "moderate",
];

Deno.test("REGRESSION: the exact reported scenario -- good signals every day, realistic workouts_per_week, no logged rest, fires", () => {
  // Real reported gap: a user can go a full week on nothing but
  // moderate/push_hard because every existing cap is reactive.
  assertEquals(
    computeProactiveRestCapApplied("three_to_five", aFullWeekOfHardTraining, false, "push_hard"),
    true,
  );
  assertEquals(
    computeProactiveRestCapApplied("six_plus", aFullWeekOfHardTraining, false, "moderate"),
    true,
  );
});

Deno.test("a week that already had a rest or light day anywhere in it never fires", () => {
  const withARestDay = ["moderate", "push_hard", "light", "push_hard", "moderate", "push_hard", "moderate"] as const;
  assertEquals(computeProactiveRestCapApplied("three_to_five", [...withARestDay], false, "push_hard"), false);
  const withAFullRestDay = ["moderate", "push_hard", "rest", "push_hard", "moderate", "push_hard", "moderate"] as const;
  assertEquals(computeProactiveRestCapApplied("three_to_five", [...withAFullRestDay], false, "push_hard"), false);
});

Deno.test("skipped entirely for zero_to_two -- that cadence already includes plenty of rest", () => {
  assertEquals(computeProactiveRestCapApplied("zero_to_two", aFullWeekOfHardTraining, false, "push_hard"), false);
});

Deno.test("applies for three_to_five, six_plus, AND unset/null (unset defaults to applying, not skipping)", () => {
  for (const freq of ["three_to_five", "six_plus", null]) {
    assertEquals(computeProactiveRestCapApplied(freq, aFullWeekOfHardTraining, false, "push_hard"), true, `freq=${freq}`);
  }
});

Deno.test("insufficient data (fewer real recommendation rows than the minimum) never fires", () => {
  const sparse = aFullWeekOfHardTraining.slice(0, PROACTIVE_REST_MIN_RECOMMENDATIONS - 1);
  assertEquals(computeProactiveRestCapApplied("three_to_five", sparse, false, "push_hard"), false);
});

Deno.test("exactly at the minimum row count with no rest/light day still fires", () => {
  const exact = aFullWeekOfHardTraining.slice(0, PROACTIVE_REST_MIN_RECOMMENDATIONS);
  assertEquals(computeProactiveRestCapApplied("three_to_five", exact, false, "push_hard"), true);
});

Deno.test("exceptional readiness today skips the proactive floor, same bar as the consecutive-days/volume caps", () => {
  assertEquals(computeProactiveRestCapApplied("three_to_five", aFullWeekOfHardTraining, true, "push_hard"), false);
});

Deno.test("never fires when today's own band is already light/rest -- nothing to cap further down", () => {
  assertEquals(computeProactiveRestCapApplied("three_to_five", aFullWeekOfHardTraining, false, "light"), false);
  assertEquals(computeProactiveRestCapApplied("three_to_five", aFullWeekOfHardTraining, false, "rest"), false);
});

Deno.test("an empty window (brand-new user, no history yet) never fires", () => {
  assertEquals(computeProactiveRestCapApplied("three_to_five", [], false, "push_hard"), false);
});
