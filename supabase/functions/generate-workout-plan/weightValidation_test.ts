import { assert, assertEquals } from "jsr:@std/assert";
import {
  classifyLoadPattern,
  findWeightCeilingViolations,
  isTwoImplementVariant,
  parsePerImplementKg,
  twoImplementCeilingKg,
} from "./weightValidation.ts";

// --- classifyLoadPattern / isTwoImplementVariant ---

Deno.test("classifyLoadPattern recognizes squat and hinge names, ignores everything else", () => {
  assertEquals(classifyLoadPattern("Dumbbell Squat"), "squat_pattern");
  assertEquals(classifyLoadPattern("Barbell Back Squat"), "squat_pattern");
  assertEquals(classifyLoadPattern("Dumbbell Romanian Deadlift"), "hinge_pattern");
  assertEquals(classifyLoadPattern("Conventional Deadlift"), "hinge_pattern");
  assertEquals(classifyLoadPattern("Good Morning"), "hinge_pattern");
  assertEquals(classifyLoadPattern("Push-Up"), null);
  assertEquals(classifyLoadPattern("Barbell Bench Press"), null);
});

Deno.test("isTwoImplementVariant matches a bare dumbbell name but not a goblet or barbell variant", () => {
  assert(isTwoImplementVariant("Dumbbell Squat"));
  assert(isTwoImplementVariant("Dumbbell Romanian Deadlift"));
  assert(!isTwoImplementVariant("Dumbbell Goblet Squat"), "goblet is single-implement, out of this bug's scope");
  assert(!isTwoImplementVariant("Barbell Back Squat"));
  assert(!isTwoImplementVariant("Bodyweight Squat"));
});

// --- parsePerImplementKg ---

Deno.test("parsePerImplementKg reads the '2xNkg' format buildLoadGuidance instructs the model to use", () => {
  assertEquals(parsePerImplementKg("2x12kg dumbbells"), 12);
  assertEquals(parsePerImplementKg("start light, 2x8kg dumbbells"), 8);
});

Deno.test("parsePerImplementKg reads an explicit 'Nkg each' phrasing", () => {
  assertEquals(parsePerImplementKg("12kg each dumbbell"), 12);
  assertEquals(parsePerImplementKg("moderate, 12kg each"), 12);
});

Deno.test("parsePerImplementKg ignores a count other than 2 (not a two-dumbbell case)", () => {
  assertEquals(parsePerImplementKg("1x20kg dumbbell"), null);
  assertEquals(parsePerImplementKg("3x10kg"), null);
});

Deno.test("parsePerImplementKg returns null for text with no parseable per-implement number", () => {
  assertEquals(parsePerImplementKg("bodyweight"), null);
  assertEquals(parsePerImplementKg("N/A"), null);
  assertEquals(parsePerImplementKg("moderate, 24kg total"), null);
  assertEquals(parsePerImplementKg("RPE 7/10"), null);
});

// --- twoImplementCeilingKg ---

Deno.test("twoImplementCeilingKg matches loadGuidance.ts's own two-dumbbell derivation (single source of truth)", () => {
  // Same numbers as loadGuidance_test.ts's own two-dumbbell regression --
  // this ceiling and that prompt-text guideline must never be able to
  // silently drift apart, since they both call twoDumbbellLoadRangeKg.
  const ceiling = twoImplementCeilingKg("squat_pattern", 60, "moderate");
  assert(ceiling < 16, `ceiling (${ceiling.toFixed(1)}kg) must be clearly under the reported unrealistic 16kg floor`);
});

// --- findWeightCeilingViolations ---

function plan(overrides: {
  warm_up?: { name: string; weight_guidance: string }[];
  blocks?: { exercises: { name: string; weight_guidance: string }[] }[];
  cool_down?: { name: string; weight_guidance: string }[];
}) {
  return { warm_up: [], blocks: [], cool_down: [], ...overrides };
}

Deno.test("REGRESSION: the real bug report is caught -- 16kg each for a 60kg moderate user's two-dumbbell squat", () => {
  const p = plan({
    blocks: [{ exercises: [{ name: "Dumbbell Squat", weight_guidance: "2x16kg dumbbells" }] }],
  });
  const violations = findWeightCeilingViolations(p, 60, "moderate");
  assertEquals(violations.length, 1);
  assertEquals(violations[0].exerciseName, "Dumbbell Squat");
  assertEquals(violations[0].statedPerImplementKg, 16);
});

Deno.test("a two-dumbbell prescription within the derated ceiling is not flagged", () => {
  const p = plan({
    blocks: [{ exercises: [{ name: "Dumbbell Squat", weight_guidance: "2x8kg dumbbells" }] }],
  });
  assertEquals(findWeightCeilingViolations(p, 60, "moderate"), []);
});

Deno.test("a barbell squat is never checked against the two-dumbbell ceiling", () => {
  // A real barbell working-set total (e.g. 40kg) would trivially "fail" a
  // per-dumbbell ceiling if wrongly checked against it -- must be a no-op.
  const p = plan({
    blocks: [{ exercises: [{ name: "Barbell Back Squat", weight_guidance: "40kg" }] }],
  });
  assertEquals(findWeightCeilingViolations(p, 60, "moderate"), []);
});

Deno.test("a goblet squat (single implement) is never checked against the two-dumbbell ceiling", () => {
  const p = plan({
    blocks: [{ exercises: [{ name: "Dumbbell Goblet Squat", weight_guidance: "20kg" }] }],
  });
  assertEquals(findWeightCeilingViolations(p, 60, "moderate"), []);
});

Deno.test("a non-squat/hinge dumbbell exercise is never checked (out of this bug's scope)", () => {
  const p = plan({
    blocks: [{ exercises: [{ name: "Dumbbell Bench Press", weight_guidance: "2x40kg dumbbells" }] }],
  });
  assertEquals(findWeightCeilingViolations(p, 60, "moderate"), []);
});

Deno.test("checks warm_up and cool_down, not just blocks", () => {
  const p = plan({
    warm_up: [{ name: "Dumbbell Squat", weight_guidance: "2x16kg dumbbells" }],
    cool_down: [{ name: "Dumbbell Romanian Deadlift", weight_guidance: "2x20kg dumbbells" }],
  });
  const violations = findWeightCeilingViolations(p, 60, "moderate");
  assertEquals(violations.length, 2);
});

Deno.test("no ceiling to violate when bodyweight is unknown", () => {
  const p = plan({
    blocks: [{ exercises: [{ name: "Dumbbell Squat", weight_guidance: "2x99kg dumbbells" }] }],
  });
  assertEquals(findWeightCeilingViolations(p, null, "moderate"), []);
});

Deno.test("an exercise whose weight_guidance has no parseable per-implement number is silently skipped, not flagged", () => {
  const p = plan({
    blocks: [{ exercises: [{ name: "Dumbbell Squat", weight_guidance: "start light and build" }] }],
  });
  assertEquals(findWeightCeilingViolations(p, 60, "moderate"), []);
});

Deno.test("a known lift raises (or lowers) the ceiling exactly like it does in the prompt guideline", () => {
  const p = plan({
    blocks: [{ exercises: [{ name: "Dumbbell Romanian Deadlift", weight_guidance: "2x20kg dumbbells" }] }],
  });
  // Without a known lift, population-estimate ceiling for a 60kg moderate
  // hinge two-dumbbell figure is well under 20kg each -- flagged.
  assertEquals(findWeightCeilingViolations(p, 60, "moderate").length, 1);
  // A stated real 150kg hinge lift raises the derived ceiling well above 20kg.
  assertEquals(findWeightCeilingViolations(p, 60, "moderate", { hinge_pattern: 150 }).length, 0);
});
