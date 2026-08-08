import { assertEquals } from "jsr:@std/assert";
import { assessOutdoorSafety, isOutdoorCardioExerciseName } from "./weatherSafety.ts";

// -- assessOutdoorSafety --

Deno.test("assessOutdoorSafety: the exact real-usage report (Dubai, 42C) is unsafe", () => {
  const result = assessOutdoorSafety(42, 46, 0);
  assertEquals(result.safe, false);
  assertEquals(result.reason?.includes("46"), true);
});

Deno.test("assessOutdoorSafety: apparent temperature is preferred over raw temperature", () => {
  // Raw temp alone looks fine, but the heat index (apparent) is dangerous.
  const result = assessOutdoorSafety(34, 39, 0);
  assertEquals(result.safe, false);
});

Deno.test("assessOutdoorSafety: falls back to raw temperature when apparent is unavailable", () => {
  const result = assessOutdoorSafety(40, null, 0);
  assertEquals(result.safe, false);
});

Deno.test("assessOutdoorSafety: mild pleasant weather is safe", () => {
  const result = assessOutdoorSafety(20, 19, 0);
  assertEquals(result.safe, true);
  assertEquals(result.reason, undefined);
});

Deno.test("assessOutdoorSafety: extreme cold is unsafe", () => {
  const result = assessOutdoorSafety(-20, -22, 0);
  assertEquals(result.safe, false);
});

Deno.test("assessOutdoorSafety: thunderstorm weather code is unsafe regardless of temperature", () => {
  const result = assessOutdoorSafety(22, 21, 95);
  assertEquals(result.safe, false);
});

Deno.test("assessOutdoorSafety: light rain (weather code 61, not in the hazardous set) stays safe", () => {
  const result = assessOutdoorSafety(18, 17, 61);
  assertEquals(result.safe, true);
});

Deno.test("assessOutdoorSafety: all-null inputs (no data) default to safe -- fail open, not closed", () => {
  const result = assessOutdoorSafety(null, null, null);
  assertEquals(result.safe, true);
});

// -- isOutdoorCardioExerciseName --
// Every name below is a REAL row from the live exercise_library table
// (queried directly), not invented -- the exact collision risk this
// dual-condition check exists to avoid.

Deno.test("isOutdoorCardioExerciseName: 'Bicycling' (equipment: other) is outdoor", () => {
  assertEquals(isOutdoorCardioExerciseName("Bicycling"), true);
});

Deno.test("isOutdoorCardioExerciseName: 'Bicycling, Stationary' (equipment: machine) is NOT outdoor", () => {
  assertEquals(isOutdoorCardioExerciseName("Bicycling, Stationary"), false);
});

Deno.test("isOutdoorCardioExerciseName: 'Trail Running/Walking' is outdoor", () => {
  assertEquals(isOutdoorCardioExerciseName("Trail Running/Walking"), true);
});

Deno.test("isOutdoorCardioExerciseName: 'Running, Treadmill' is NOT outdoor", () => {
  assertEquals(isOutdoorCardioExerciseName("Running, Treadmill"), false);
});

Deno.test("isOutdoorCardioExerciseName: 'Jogging, Treadmill' is NOT outdoor", () => {
  assertEquals(isOutdoorCardioExerciseName("Jogging, Treadmill"), false);
});

Deno.test("isOutdoorCardioExerciseName: 'Recumbent Bike' is NOT outdoor (no outdoor signal at all)", () => {
  assertEquals(isOutdoorCardioExerciseName("Recumbent Bike"), false);
});

Deno.test("isOutdoorCardioExerciseName: 'Elliptical Trainer' is NOT outdoor", () => {
  assertEquals(isOutdoorCardioExerciseName("Elliptical Trainer"), false);
});

Deno.test("isOutdoorCardioExerciseName: 'Rowing, Stationary' is NOT outdoor", () => {
  assertEquals(isOutdoorCardioExerciseName("Rowing, Stationary"), false);
});

Deno.test("isOutdoorCardioExerciseName: an unrelated strength name with 'run' as a substring is NOT a false positive", () => {
  // "Chest Push with Run Release" -- contains "run" but not "running".
  assertEquals(isOutdoorCardioExerciseName("Chest Push with Run Release"), false);
});

Deno.test("isOutdoorCardioExerciseName: unrelated strength/plyo names are unaffected", () => {
  assertEquals(isOutdoorCardioExerciseName("Bent Over Barbell Row"), false);
  assertEquals(isOutdoorCardioExerciseName("Barbell Walking Lunge"), false);
  assertEquals(isOutdoorCardioExerciseName("Farmer's Walk"), false);
});
