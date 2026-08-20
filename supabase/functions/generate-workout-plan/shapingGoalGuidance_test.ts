// Run: deno test supabase/functions/
//
// decideShapingGoalGuidance is the deterministic half of Phase 3 (see
// docs/coaching-personalization-plan.md) -- if it picks wrong (or silently
// picks nothing), the rep-range/foundation-movement personalization is
// decorative. These tests check the precedence chain (goals >
// body_photo_emphasis_tags > training_emphasis), the graceful-degrade
// nulls, and that the "hard constraint" only ever appears for the goals
// that actually call for one.

import { assert, assertEquals, assertFalse } from "jsr:@std/assert";
import { decideShapingGoalGuidance } from "./shapingGoalGuidance.ts";

Deno.test("build_strength: low rep range, no hard constraint", () => {
  const g = decideShapingGoalGuidance(["build_strength"], null, null, "lower_body", "push_hard");
  assert(g);
  assertEquals(g.repRangeLabel, "3-6");
  assertEquals(g.hardConstraint, null);
  assert(g.foundationMovements.length > 0);
});

Deno.test("gain_muscle: hypertrophy rep range, no hard constraint", () => {
  const g = decideShapingGoalGuidance(["gain_muscle"], null, null, "upper_body", "moderate");
  assert(g);
  assertEquals(g.repRangeLabel, "6-12");
  assertEquals(g.hardConstraint, null);
});

Deno.test("leaner_toned and more_sculpted produce identical guidance for the same body part", () => {
  const a = decideShapingGoalGuidance(["leaner_toned"], null, null, "full_body", "moderate");
  const b = decideShapingGoalGuidance(["more_sculpted"], null, null, "full_body", "moderate");
  assert(a && b);
  assertEquals(a.repRangeLabel, b.repRangeLabel);
  assertEquals(a.hardConstraint, b.hardConstraint);
  assertEquals(a.foundationMovements, b.foundationMovements);
});

Deno.test("leaner_toned/more_sculpted/lose_weight all carry the same hard 'no near-max low-rep sets' constraint", () => {
  for (const tag of ["leaner_toned", "more_sculpted", "lose_weight"]) {
    const g = decideShapingGoalGuidance([tag], null, null, "core", "moderate");
    assert(g, tag);
    assert(g.hardConstraint, `${tag} should carry a hard constraint`);
    assert(g.hardConstraint!.toLowerCase().includes("1-3"), tag);
  }
});

Deno.test("grow_glutes/stronger_core are hypertrophy/strength-family: no hard constraint, and their lower_body/core movements name the target muscle", () => {
  const glutes = decideShapingGoalGuidance(["grow_glutes"], null, null, "lower_body", "moderate");
  assert(glutes);
  assertEquals(glutes.repRangeLabel, "6-12");
  assertEquals(glutes.hardConstraint, null);
  assert(glutes.foundationMovements.some((m) => m.toLowerCase().includes("glute")), "expected a glute-named movement");

  const core = decideShapingGoalGuidance(["stronger_core"], null, null, "core", "moderate");
  assert(core);
  assertEquals(core.hardConstraint, null);
  assert(core.foundationMovements.length > 0);
});

Deno.test("lose_belly_fat/lean_out_legs/toned_arms/more_visible_abs are definition-family: same hard constraint as leaner_toned, body-part-biased movements", () => {
  const cases: [string, "core" | "lower_body" | "upper_body", string][] = [
    ["lose_belly_fat", "core", "crunch"],
    ["lean_out_legs", "lower_body", "lunge"],
    ["toned_arms", "upper_body", "curl"],
    ["more_visible_abs", "core", "crunch"],
  ];
  for (const [tag, bodyPart, expectedSubstring] of cases) {
    const g = decideShapingGoalGuidance([tag], null, null, bodyPart, "moderate");
    assert(g, tag);
    assert(g.hardConstraint, `${tag} should carry the definition hard constraint`);
    assert(g.hardConstraint!.toLowerCase().includes("1-3"), tag);
    assert(g.foundationMovements.some((m) => m.toLowerCase().includes(expectedSubstring)), `${tag}/${bodyPart} expected a movement mentioning "${expectedSubstring}"`);
  }
});

Deno.test("REGRESSION: when multiple recognized goals are present, build_strength/gain_muscle outrank the aesthetic tags", () => {
  const g = decideShapingGoalGuidance(["lose_weight", "build_strength"], null, null, "full_body", "moderate");
  assert(g);
  assertEquals(g.goalTag, "build_strength");
  assertEquals(g.hardConstraint, null);
});

Deno.test("priority: a body-part-specific tag outranks its generic same-family sibling, but still loses to an explicit general strength/hypertrophy ask", () => {
  // Within the definition family, specific beats generic (free improvement --
  // every definition tag shares the same 12-15 rep range).
  const specificOverGeneric = decideShapingGoalGuidance(["leaner_toned", "lose_belly_fat"], null, null, "core", "moderate");
  assert(specificOverGeneric);
  assertEquals(specificOverGeneric.goalTag, "lose_belly_fat");

  // grow_glutes/stronger_core still lose to an explicit build_strength/
  // gain_muscle ask.
  const generalStillWins = decideShapingGoalGuidance(["grow_glutes", "build_strength"], null, null, "lower_body", "moderate");
  assert(generalStillWins);
  assertEquals(generalStillWins.goalTag, "build_strength");

  // ...but grow_glutes/stronger_core still outrank every definition-family tag.
  const strengthFamilyOverDefinition = decideShapingGoalGuidance(["more_visible_abs", "stronger_core"], null, null, "core", "moderate");
  assert(strengthFamilyOverDefinition);
  assertEquals(strengthFamilyOverDefinition.goalTag, "stronger_core");
});

Deno.test("unrecognized goal tags are ignored, not treated as a match", () => {
  const g = decideShapingGoalGuidance(["general_fitness", "better_sleep"], null, null, "upper_body", "moderate");
  assertEquals(g, null);
});

Deno.test("body_photo_emphasis_tags is consulted only when goals has no recognized tag", () => {
  // goals has nothing recognized -> falls through to body photo tags.
  const fallsThrough = decideShapingGoalGuidance(["general_fitness"], ["gain_muscle"], null, "upper_body", "moderate");
  assert(fallsThrough);
  assertEquals(fallsThrough.goalTag, "gain_muscle");
  assertEquals(fallsThrough.source, "body_photo_emphasis_tags");

  // goals already has a recognized tag -> body photo tags are ignored
  // entirely, even though they'd pick something different.
  const goalsWins = decideShapingGoalGuidance(["build_strength"], ["lose_weight"], null, "upper_body", "moderate");
  assert(goalsWins);
  assertEquals(goalsWins.goalTag, "build_strength");
  assertEquals(goalsWins.source, "goals");
});

Deno.test("training_emphasis is a last resort, consulted only when neither goals nor body_photo_emphasis_tags match", () => {
  const cut = decideShapingGoalGuidance(null, null, "cut", "lower_body", "moderate");
  assert(cut);
  assertEquals(cut.goalTag, "lose_weight");
  assertEquals(cut.source, "training_emphasis");

  const bulk = decideShapingGoalGuidance(null, null, "bulk", "lower_body", "moderate");
  assert(bulk);
  assertEquals(bulk.goalTag, "gain_muscle");

  const recomp = decideShapingGoalGuidance(null, null, "recomp", "lower_body", "moderate");
  assert(recomp);
  assertEquals(recomp.goalTag, "gain_muscle");

  // maintain has no shaping-specific direction, same as no signal at all.
  assertEquals(decideShapingGoalGuidance(null, null, "maintain", "lower_body", "moderate"), null);

  // A recognized goals tag still wins over training_emphasis even when
  // both are present.
  const goalsWins = decideShapingGoalGuidance(["build_strength"], null, "cut", "lower_body", "moderate");
  assert(goalsWins);
  assertEquals(goalsWins.goalTag, "build_strength");
  assertEquals(goalsWins.source, "goals");
});

Deno.test("degrades gracefully to null when none of the three signals are present", () => {
  assertEquals(decideShapingGoalGuidance(null, null, null, "upper_body", "moderate"), null);
  assertEquals(decideShapingGoalGuidance([], [], null, "upper_body", "moderate"), null);
});

Deno.test("INVARIANT: never fires on rest or light days, regardless of goal", () => {
  for (const category of ["rest", "light"]) {
    assertEquals(decideShapingGoalGuidance(["build_strength"], null, null, "upper_body", category), null);
  }
});

Deno.test("INVARIANT: never fires for cardio or recovery body parts, regardless of goal", () => {
  for (const bodyPart of ["cardio", "recovery"]) {
    assertEquals(decideShapingGoalGuidance(["build_strength"], null, null, bodyPart, "moderate"), null);
  }
});

Deno.test("foundation movements are stable across repeated calls -- a fixed recurring list, not randomized", () => {
  const first = decideShapingGoalGuidance(["gain_muscle"], null, null, "lower_body", "moderate");
  const second = decideShapingGoalGuidance(["gain_muscle"], null, null, "lower_body", "moderate");
  assert(first && second);
  assertEquals(first.foundationMovements, second.foundationMovements);
});

Deno.test("every shapable body part yields a non-empty foundation list for every recognized goal", () => {
  const goals = [
    "build_strength", "gain_muscle", "leaner_toned", "more_sculpted", "lose_weight",
    "grow_glutes", "stronger_core", "lose_belly_fat", "lean_out_legs", "toned_arms", "more_visible_abs",
  ];
  const bodyParts = ["upper_body", "lower_body", "core", "full_body"];
  for (const goal of goals) {
    for (const bodyPart of bodyParts) {
      const g = decideShapingGoalGuidance([goal], null, null, bodyPart, "moderate");
      assert(g, `${goal}/${bodyPart}`);
      assertFalse(g.foundationMovements.length === 0, `${goal}/${bodyPart} has an empty foundation list`);
    }
  }
});
