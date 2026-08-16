import { assertEquals, assertFalse } from "jsr:@std/assert";
import { coolDownRepeatsYesterday, findDuplicateExerciseNames, finisherMissing, type PlanExerciseNames } from "./planValidation.ts";

function plan(overrides: Partial<PlanExerciseNames>): PlanExerciseNames {
  return { warm_up: [], blocks: [], cool_down: [], ...overrides };
}

Deno.test("a clean plan with no repeats returns no duplicates", () => {
  const p = plan({
    warm_up: [{ name: "Arm Circles" }],
    blocks: [{ exercises: [{ name: "Barbell Squat" }, { name: "Romanian Deadlift" }] }],
    cool_down: [{ name: "Quad Stretch" }],
  });
  assertEquals(findDuplicateExerciseNames(p), []);
});

Deno.test("REGRESSION: the same exercise repeated across multiple blocks is caught", () => {
  // The actual reported bug: "Barbell Squat" 4 times in one plan.
  const p = plan({
    blocks: [
      { exercises: [{ name: "Barbell Squat" }] },
      { exercises: [{ name: "Barbell Squat" }] },
      { exercises: [{ name: "Barbell Squat" }, { name: "Barbell Squat" }] },
    ],
  });
  assertEquals(findDuplicateExerciseNames(p), ["Barbell Squat"]);
});

Deno.test("a duplicate within the SAME block (e.g. a bad superset) is also caught", () => {
  const p = plan({
    blocks: [{ exercises: [{ name: "Push-Up" }, { name: "Push-Up" }] }],
  });
  assertEquals(findDuplicateExerciseNames(p), ["Push-Up"]);
});

Deno.test("a duplicate spanning warm_up and a block is caught too", () => {
  const p = plan({
    warm_up: [{ name: "Bodyweight Squat" }],
    blocks: [{ exercises: [{ name: "Bodyweight Squat" }] }],
  });
  assertEquals(findDuplicateExerciseNames(p), ["Bodyweight Squat"]);
});

Deno.test("multiple distinct duplicates are all reported, deduplicated", () => {
  const p = plan({
    blocks: [
      { exercises: [{ name: "A" }, { name: "B" }] },
      { exercises: [{ name: "A" }, { name: "B" }, { name: "A" }] },
    ],
  });
  const result = findDuplicateExerciseNames(p);
  assertEquals(result.length, 2);
  assertEquals(new Set(result), new Set(["A", "B"]));
});

// --- coolDownRepeatsYesterday ---

Deno.test("REGRESSION: an identical cool_down to yesterday's is flagged", () => {
  // BUG report: cool_down never varies day to day.
  const p = plan({ cool_down: [{ name: "Standing Quad Stretch" }, { name: "Seated Forward Fold" }] });
  assertEquals(coolDownRepeatsYesterday(p, ["Standing Quad Stretch", "Seated Forward Fold"]), true);
});

Deno.test("order doesn't matter -- same set of names is still a match", () => {
  const p = plan({ cool_down: [{ name: "Seated Forward Fold" }, { name: "Standing Quad Stretch" }] });
  assertEquals(coolDownRepeatsYesterday(p, ["Standing Quad Stretch", "Seated Forward Fold"]), true);
});

Deno.test("a genuinely different cool_down is not flagged", () => {
  const p = plan({ cool_down: [{ name: "Cobra Stretch" }, { name: "Child's Pose" }] });
  assertFalse(coolDownRepeatsYesterday(p, ["Standing Quad Stretch", "Seated Forward Fold"]));
});

Deno.test("a partial overlap (subset/superset) is not treated as an exact match", () => {
  const p = plan({ cool_down: [{ name: "Standing Quad Stretch" }, { name: "Seated Forward Fold" }, { name: "Child's Pose" }] });
  assertFalse(coolDownRepeatsYesterday(p, ["Standing Quad Stretch", "Seated Forward Fold"]));
});

Deno.test("no prior cool_down on file (null or empty) is never flagged", () => {
  const p = plan({ cool_down: [{ name: "Standing Quad Stretch" }] });
  assertFalse(coolDownRepeatsYesterday(p, null));
  assertFalse(coolDownRepeatsYesterday(p, []));
});

// --- finisherMissing ---

function planWithBlocks(blocks: { is_finisher: boolean }[]) {
  return { blocks };
}

Deno.test("REGRESSION: a plan with no finisher block, when one should be included, is flagged", () => {
  // BUG report: finisher rarely shows -- real query against ai_workout_plan
  // showed decideFinisher's gate is already permissive (include=true for
  // every eligible category); this is the deterministic backstop for when
  // the model just doesn't follow the instruction.
  const p = planWithBlocks([{ is_finisher: false }, { is_finisher: false }]);
  assertEquals(finisherMissing(p, true), true);
});

Deno.test("a plan that DOES include a finisher block is not flagged", () => {
  const p = planWithBlocks([{ is_finisher: false }, { is_finisher: true }]);
  assertFalse(finisherMissing(p, true));
});

Deno.test("never flagged when a finisher wasn't supposed to be included (rest/light day)", () => {
  const p = planWithBlocks([{ is_finisher: false }]);
  assertFalse(finisherMissing(p, false));
});

Deno.test("an empty blocks array with no finisher expected is not flagged", () => {
  assertFalse(finisherMissing(planWithBlocks([]), false));
});
