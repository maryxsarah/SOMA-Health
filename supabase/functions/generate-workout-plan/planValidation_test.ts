import { assertEquals } from "jsr:@std/assert";
import { findDuplicateExerciseNames, type PlanExerciseNames } from "./planValidation.ts";

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
