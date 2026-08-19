// Run: deno test supabase/functions/

import { assertEquals } from "jsr:@std/assert";
import { resolveTargetBodyPart } from "./targetBodyPart.ts";

Deno.test("no goal match, no rotation history -> stable default for the category", () => {
  // moderate's first candidate is full_body -- with nothing to break the
  // tie, the stable sort must leave it in place.
  assertEquals(resolveTargetBodyPart("moderate", [], [], {}, {}), "full_body");
});

Deno.test("a goal match floats its body part above an earlier-declared non-match", () => {
  // Every "cardio" candidate in moderate's list wants cardio_endurance, not
  // build_strength -- so a build_strength goal must keep the winner among
  // full_body/upper_body/lower_body (which all declare it), landing on
  // full_body (the first-declared, with no rotation history to break the
  // tie), rather than falling through to a non-matching cardio candidate.
  assertEquals(resolveTargetBodyPart("moderate", ["build_strength"], [], {}, {}), "full_body");
});

Deno.test("REGRESSION: rotation deprioritizes the body part trained most in the trailing 7 days", () => {
  // All three strength candidates match "build_strength" equally -- the
  // rotation count must be what breaks the tie, per BodyPartFocus's doc
  // comment ("deprioritize repeating the same body part on consecutive
  // days"). full_body and upper_body were both trained recently; lower_body
  // wasn't touched at all.
  const result = resolveTargetBodyPart(
    "moderate",
    ["build_strength"],
    [],
    {},
    { full_body: 3, upper_body: 2, lower_body: 0 },
  );
  assertEquals(result, "lower_body");
});

Deno.test("REGRESSION: a moderate/severe injury redirects the resolved target, not just the fixed suggestion list", () => {
  // lower_body wins on rotation (see test above), but a moderate knee
  // injury must redirect it to upper_body -- same rule
  // resolveBodyPartForInjuries applies to the client's own selection in
  // generate-workout-plan.
  const result = resolveTargetBodyPart(
    "moderate",
    ["build_strength"],
    ["knee"],
    { knee: "moderate" },
    { full_body: 3, upper_body: 2, lower_body: 0 },
  );
  assertEquals(result, "upper_body");
});

Deno.test("a mild injury does not redirect the resolved target", () => {
  // Mild injuries stay exclusion-only (contraindications.ts handles it
  // within the same body part) -- only moderate/severe redirect.
  const result = resolveTargetBodyPart(
    "moderate",
    ["build_strength"],
    ["knee"],
    { knee: "mild" },
    { full_body: 3, upper_body: 2, lower_body: 0 },
  );
  assertEquals(result, "lower_body");
});

Deno.test("REGRESSION: the injury redirect never overrides the rotation signal with the MOST recently-trained body part", () => {
  // BUG report: resolveTargetBodyPart used to rank ALL candidates first
  // (ignoring injury), then redirect only the single winner via a fixed
  // substitution-table lookup. For a severe shoulder injury (which
  // redirects full_body/upper_body -> lower_body) with empty goals, the
  // old code ranked full_body first (lowest rotation count) and then
  // redirected it to "lower_body" -- even though lower_body had the
  // HIGHEST recent count (5) of any candidate, exactly what rotation
  // exists to avoid. Excluding unsafe candidates BEFORE ranking (the fix)
  // must never do this: with full_body/upper_body excluded, the safe
  // candidates are cardio (count 0) and core (count 0), both beating
  // lower_body's count of 5 -- the result must be one of those, never
  // lower_body.
  const result = resolveTargetBodyPart(
    "moderate",
    [],
    ["shoulder"],
    { shoulder: "severe" },
    { lower_body: 5, core: 0 },
  );
  assertEquals(result, "cardio");
});

Deno.test("an unrecognized category falls back to moderate's candidate list rather than throwing", () => {
  assertEquals(resolveTargetBodyPart("not_a_category", [], [], {}, {}), "full_body");
});

Deno.test("every declared category resolves without throwing", () => {
  for (const category of ["rest", "light", "moderate", "push_hard"]) {
    resolveTargetBodyPart(category, [], [], {}, {});
  }
});
