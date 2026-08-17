import { assert, assertEquals } from "jsr:@std/assert";
import { estimateExerciseMinutes, reconcileExerciseDurations } from "./durationValidation.ts";
import { computeTotalDuration } from "../_shared/duration.ts";

// --- estimateExerciseMinutes ---

Deno.test("estimateExerciseMinutes: 3 sets, 90 sec rest -- work + 2 rest gaps + buffer", () => {
  // 3 x 40s work + 2 x 90s rest (between sets, never after the last one)
  // + 15s buffer = 120 + 180 + 15 = 315s = 5.25 min.
  const minutes = estimateExerciseMinutes({ sets: 3, rest_seconds: 90 });
  assertEquals(minutes, 315 / 60);
});

Deno.test("estimateExerciseMinutes: a single set has no rest gap at all", () => {
  // 1 x 40s work + 0 rest gaps + 15s buffer = 55s.
  const minutes = estimateExerciseMinutes({ sets: 1, rest_seconds: 90 });
  assertEquals(minutes, 55 / 60);
});

Deno.test("estimateExerciseMinutes: null rest_seconds (coach block placeholder) is treated as zero, not NaN", () => {
  const minutes = estimateExerciseMinutes({ sets: 1, rest_seconds: null });
  assert(!Number.isNaN(minutes));
  assertEquals(minutes, 55 / 60);
});

Deno.test("estimateExerciseMinutes: more sets and more rest both increase the estimate", () => {
  const base = estimateExerciseMinutes({ sets: 3, rest_seconds: 60 });
  assert(estimateExerciseMinutes({ sets: 5, rest_seconds: 60 }) > base, "more sets should take longer");
  assert(estimateExerciseMinutes({ sets: 3, rest_seconds: 120 }) > base, "more rest should take longer");
});

// --- reconcileExerciseDurations ---

function exercise(overrides: Partial<{ name: string; sets: number; rest_seconds: number | null; duration_minutes: number }>) {
  return { name: "Exercise", sets: 3, rest_seconds: 60, duration_minutes: 5, instructions: "", reps: "8-10", weight_guidance: "bodyweight", intensity: "moderate", ...overrides };
}
function plan(overrides: {
  warm_up?: ReturnType<typeof exercise>[];
  blocks?: { name?: string; rounds?: number; rest_between_rounds?: string; is_finisher?: boolean; exercises: ReturnType<typeof exercise>[] }[];
  cool_down?: ReturnType<typeof exercise>[];
}) {
  return {
    focus: "test",
    warm_up: overrides.warm_up ?? [],
    blocks: (overrides.blocks ?? []).map((b) => ({ name: "Block 1", rounds: 1, rest_between_rounds: "N/A", is_finisher: false, ...b })),
    cool_down: overrides.cool_down ?? [],
  };
}

Deno.test("REGRESSION: the real bug report -- a plan self-reported ~47 min is reconciled well below that, not just cosmetically", () => {
  // 6 strength exercises, each genuinely 3 sets/75 sec rest (real time per
  // exercise ~4.75 min), but the LLM stated an inflated ~6-8 min each --
  // summing (with a 2-min warm_up and 2-min cool_down) to the reported 47.
  const p = plan({
    warm_up: [exercise({ name: "Warm-up", sets: 1, duration_minutes: 2 })],
    blocks: [{
      exercises: [
        exercise({ name: "Ex 1", sets: 3, rest_seconds: 75, duration_minutes: 7 }),
        exercise({ name: "Ex 2", sets: 3, rest_seconds: 75, duration_minutes: 7 }),
        exercise({ name: "Ex 3", sets: 3, rest_seconds: 75, duration_minutes: 7 }),
        exercise({ name: "Ex 4", sets: 3, rest_seconds: 75, duration_minutes: 7 }),
        exercise({ name: "Ex 5", sets: 3, rest_seconds: 75, duration_minutes: 8 }),
        exercise({ name: "Ex 6", sets: 3, rest_seconds: 75, duration_minutes: 7 }),
      ],
    }],
    cool_down: [exercise({ name: "Cool-down", sets: 1, duration_minutes: 2 })],
  });
  // Before reconciliation: matches the reported "~47 min total" exactly.
  assertEquals(computeTotalDuration(p), 47);

  const reconciled = reconcileExerciseDurations(p);
  const reconciledTotal = computeTotalDuration(reconciled);
  // Real per-exercise estimate: (3x40 + 2x75 + 15)/60 = 285/60 = 4.75 ->
  // rounds to 5 min each x 6 = 30, + 2 (warm_up) + 2 (cool_down) = 34.
  assertEquals(reconciledTotal, 34);
  assert(reconciledTotal < 40, `reconciled total (${reconciledTotal}) must land well under the reported unrealistic 47 min`);
  assert(reconciledTotal >= 28 && reconciledTotal <= 38, `reconciled total (${reconciledTotal}) should land in the reported real ~30-35 min range`);
});

Deno.test("a stated duration within tolerance of the estimate is left untouched", () => {
  // Estimate for sets:3/rest:60 = (120+120+15)/60 = 4.25 min. Stated 5 min
  // is within tolerance (max(2, 4.25*0.3)=2 min) -- must NOT be overwritten.
  const p = plan({ blocks: [{ exercises: [exercise({ sets: 3, rest_seconds: 60, duration_minutes: 5 })] }] });
  const reconciled = reconcileExerciseDurations(p);
  assertEquals(reconciled.blocks[0].exercises[0].duration_minutes, 5);
});

Deno.test("a stated duration far outside tolerance is overwritten with the rounded estimate", () => {
  const p = plan({ blocks: [{ exercises: [exercise({ sets: 3, rest_seconds: 60, duration_minutes: 15 })] }] });
  const reconciled = reconcileExerciseDurations(p);
  assertEquals(reconciled.blocks[0].exercises[0].duration_minutes, Math.round(estimateExerciseMinutes({ sets: 3, rest_seconds: 60 })));
});

Deno.test("single-set exercises (held stretches, single timed activities) are never touched", () => {
  const p = plan({ blocks: [{ exercises: [exercise({ sets: 1, rest_seconds: 90, duration_minutes: 30 })] }] });
  const reconciled = reconcileExerciseDurations(p);
  assertEquals(reconciled.blocks[0].exercises[0].duration_minutes, 30, "sets:1 must be left exactly as stated, however implausible");
});

Deno.test("REGRESSION: the coach block's placeholder exercise (sets:1, rest_seconds:null) is never touched", () => {
  // Mirrors buildCoachBlock's hand-built exercise shape exactly.
  const p = plan({
    blocks: [{
      name: "Coach Block",
      exercises: [exercise({ name: "Your coach's assignment", sets: 1, rest_seconds: null, duration_minutes: 15 })],
    }],
  });
  const reconciled = reconcileExerciseDurations(p);
  assertEquals(reconciled.blocks[0].exercises[0].duration_minutes, 15);
});

Deno.test("warm_up and cool_down are never touched, even with an implausible stated duration", () => {
  const p = plan({
    warm_up: [exercise({ sets: 3, rest_seconds: 60, duration_minutes: 99 })],
    blocks: [{ exercises: [] }],
    cool_down: [exercise({ sets: 3, rest_seconds: 60, duration_minutes: 99 })],
  });
  const reconciled = reconcileExerciseDurations(p);
  assertEquals(reconciled.warm_up[0].duration_minutes, 99);
  assertEquals(reconciled.cool_down[0].duration_minutes, 99);
});

Deno.test("reconciliation does not mutate the input plan", () => {
  const p = plan({ blocks: [{ exercises: [exercise({ sets: 3, rest_seconds: 60, duration_minutes: 15 })] }] });
  const originalDuration = p.blocks[0].exercises[0].duration_minutes;
  reconcileExerciseDurations(p);
  assertEquals(p.blocks[0].exercises[0].duration_minutes, originalDuration, "input plan must be left untouched");
});

Deno.test("multiple blocks and multiple exercises per block are all reconciled independently", () => {
  const p = plan({
    blocks: [
      { exercises: [exercise({ name: "A", sets: 3, rest_seconds: 60, duration_minutes: 20 })] },
      { exercises: [exercise({ name: "B", sets: 4, rest_seconds: 90, duration_minutes: 30 })] },
    ],
  });
  const reconciled = reconcileExerciseDurations(p);
  assertEquals(reconciled.blocks[0].exercises[0].duration_minutes, Math.round(estimateExerciseMinutes({ sets: 3, rest_seconds: 60 })));
  assertEquals(reconciled.blocks[1].exercises[0].duration_minutes, Math.round(estimateExerciseMinutes({ sets: 4, rest_seconds: 90 })));
});
