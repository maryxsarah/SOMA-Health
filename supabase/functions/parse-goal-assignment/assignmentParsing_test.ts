import { assertEquals } from "jsr:@std/assert";
import { normalizeAssignment, type RawAssignmentResult } from "./assignmentParsing.ts";

function raw(overrides: Partial<RawAssignmentResult> = {}): RawAssignmentResult {
  return {
    isAssignment: true,
    confidence: 0.9,
    givenText: "add 10cm to vertical",
    workoutText: "3x10 box jumps, 3x8 depth jumps, 3x12 calf raises",
    coachName: "Coach Priya",
    durationWeeks: 8,
    frequencyPerWeek: 3,
    scheduleRule: "weekdays",
    scheduleDays: [1, 3, 5],
    courtDays: [],
    ...overrides,
  };
}

Deno.test("a confident, well-formed assignment parses cleanly", () => {
  const result = normalizeAssignment(raw());
  assertEquals(result.lowConfidence, false);
  assertEquals(result.parsed?.workoutText, "3x10 box jumps, 3x8 depth jumps, 3x12 calf raises");
  assertEquals(result.parsed?.coachName, "Coach Priya");
  assertEquals(result.parsed?.durationWeeks, 8);
  assertEquals(result.parsed?.scheduleDays, [1, 3, 5]);
});

Deno.test("isAssignment=false forces low confidence regardless of the score", () => {
  const result = normalizeAssignment(raw({ isAssignment: false, confidence: 0.95 }));
  assertEquals(result.parsed, null);
  assertEquals(result.lowConfidence, true);
});

Deno.test("confidence below the threshold is low confidence even when isAssignment is true", () => {
  const result = normalizeAssignment(raw({ confidence: 0.4 }));
  assertEquals(result.parsed, null);
  assertEquals(result.lowConfidence, true);
});

Deno.test("empty workoutText fails closed even with high self-reported confidence", () => {
  const result = normalizeAssignment(raw({ workoutText: "", confidence: 0.99 }));
  assertEquals(result.parsed, null);
  assertEquals(result.lowConfidence, true);
});

// REGRESSION: MIN_WORKOUT_TEXT_LENGTH was declared but never checked, so a
// near-empty parse like "." passed as trustworthy and would overwrite a
// user's real, already-typed workoutText.
Deno.test("REGRESSION: near-empty workoutText below MIN_WORKOUT_TEXT_LENGTH fails closed", () => {
  const result = normalizeAssignment(raw({ workoutText: ".", confidence: 0.99 }));
  assertEquals(result.parsed, null);
  assertEquals(result.lowConfidence, true);
});

Deno.test("empty-string sentinels convert to null on optional fields", () => {
  const result = normalizeAssignment(raw({ givenText: "", coachName: "" }));
  assertEquals(result.parsed?.givenText, null);
  assertEquals(result.parsed?.coachName, null);
});

Deno.test("zero sentinels convert to null on numeric fields", () => {
  const result = normalizeAssignment(raw({ durationWeeks: 0, frequencyPerWeek: 0 }));
  assertEquals(result.parsed?.durationWeeks, null);
  assertEquals(result.parsed?.frequencyPerWeek, null);
});

Deno.test("durationWeeks is clamped to the form's 1...26 range", () => {
  const result = normalizeAssignment(raw({ durationWeeks: 52 }));
  assertEquals(result.parsed?.durationWeeks, 26);
});

// REGRESSION: frequencyPerWeek had no upper bound, so a model hallucination
// (e.g. misreading a rep count as "sessions per week") passed straight
// through and rendered as a nonsensical "N of 120 sessions" in the goal hub.
Deno.test("REGRESSION: frequencyPerWeek is clamped to a physical 7/week ceiling", () => {
  const result = normalizeAssignment(raw({ frequencyPerWeek: 15 }));
  assertEquals(result.parsed?.frequencyPerWeek, 7);
});

Deno.test("an unrecognized scheduleRule string falls back to null, not garbage", () => {
  const result = normalizeAssignment(raw({ scheduleRule: "whenever_i_feel_like_it" }));
  assertEquals(result.parsed?.scheduleRule, null);
});

Deno.test("scheduleDays only survives when scheduleRule is actually weekdays", () => {
  const result = normalizeAssignment(raw({ scheduleRule: "readiness", scheduleDays: [1, 2] }));
  assertEquals(result.parsed?.scheduleRule, "readiness");
  assertEquals(result.parsed?.scheduleDays, null);
});

Deno.test("out-of-range weekday ints are filtered out of scheduleDays", () => {
  const result = normalizeAssignment(raw({ scheduleDays: [1, 7, -1, 3] }));
  assertEquals(result.parsed?.scheduleDays, [1, 3]);
});

Deno.test("an all-out-of-range scheduleDays list becomes null, not empty", () => {
  const result = normalizeAssignment(raw({ scheduleDays: [9, -3] }));
  assertEquals(result.parsed?.scheduleDays, null);
});
