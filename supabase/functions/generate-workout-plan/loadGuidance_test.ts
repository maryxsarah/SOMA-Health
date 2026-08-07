import { assert, assertEquals, assertThrows } from "jsr:@std/assert";
import { buildLoadGuidance, loadFractionRange } from "./loadGuidance.ts";

Deno.test("no bodyweight on file -- omits any specific number", () => {
  const guidance = buildLoadGuidance(null, "moderate");
  assert(guidance.includes("isn't on file"));
  assert(!/\d/.test(guidance), "must not contain any digit when bodyweight is unknown");
});

Deno.test("REGRESSION: the real bug report -- a 60kg moderate user's unilateral row range is realistic, not 16-18kg", () => {
  // BUG report: "A woman with 60kg, and 168cm height will not be able to
  // an alternating kettlebell row with 16-18kg each kettlebell."
  const [low, high] = loadFractionRange("unilateral_row_pull", "moderate");
  const loKg = low * 60;
  const hiKg = high * 60;
  assert(hiKg < 16, `unilateral row upper bound (${hiKg}kg) must be well under the reported unrealistic 16-18kg`);
  assert(loKg >= 5 && hiKg <= 15, `expected a realistic single-kettlebell range for a 60kg moderate lifter, got ${loKg}-${hiKg}kg`);
});

Deno.test("unilateral ranges are meaningfully lighter than their bilateral counterpart, not half by coincidence", () => {
  for (const pattern of ["overhead_press", "horizontal_press", "row_pull"]) {
    for (const level of ["newbie", "moderate", "advanced"]) {
      const [biLow, biHigh] = loadFractionRange(pattern, level);
      const [uniLow, uniHigh] = loadFractionRange(`unilateral_${pattern}`, level);
      assert(uniHigh < biHigh, `${pattern}/${level}: unilateral upper (${uniHigh}) must be lighter than bilateral upper (${biHigh})`);
      assert(uniLow < biLow, `${pattern}/${level}: unilateral lower (${uniLow}) must be lighter than bilateral lower (${biLow})`);
    }
  }
});

Deno.test("squat_pattern and hinge_pattern have no unilateral variant (bilateral framing already applies)", () => {
  // There's simply no "unilateral_squat_pattern" key, by design (a goblet
  // squat/single-KB deadlift still loads symmetrically) -- no production
  // call site ever requests one, so this fails loud rather than silently
  // returning something plausible-looking for a key that shouldn't exist.
  assertThrows(() => loadFractionRange("unilateral_squat_pattern", "moderate"));
});

Deno.test("higher experience levels get higher ranges, for every pattern including unilateral ones", () => {
  for (const pattern of ["squat_pattern", "hinge_pattern", "unilateral_row_pull", "unilateral_overhead_press"]) {
    const [, newbieHigh] = loadFractionRange(pattern, "newbie");
    const [, moderateHigh] = loadFractionRange(pattern, "moderate");
    const [, advancedHigh] = loadFractionRange(pattern, "advanced");
    assert(newbieHigh < moderateHigh, `${pattern}: newbie should be lighter than moderate`);
    assert(moderateHigh < advancedHigh, `${pattern}: moderate should be lighter than advanced`);
  }
});

Deno.test("prompt text explicitly distinguishes unilateral from bilateral and names concrete unilateral exercises", () => {
  const guidance = buildLoadGuidance(70, "moderate");
  assert(guidance.includes("UNILATERAL"));
  assert(guidance.includes("BILATERAL"));
  assert(guidance.toLowerCase().includes("kettlebell row"));
  assert(guidance.includes("PER-IMPLEMENT"));
});

Deno.test("prompt text instructs rounding to real dumbbell/kettlebell increments", () => {
  const guidance = buildLoadGuidance(70, "moderate");
  assert(guidance.toLowerCase().includes("increment"));
});

Deno.test("REGRESSION: the real bug report -- an advanced-tier deadlift stays well under the old 125-135kg ceiling for a realistic bodyweight", () => {
  // BUG report: a self-described non-powerlifter was prescribed
  // 125-135kg for a barbell deadlift (near the old advanced ceiling of
  // 1.75x bodyweight -- elite/competitive territory for a working set).
  const [, advancedHigh] = loadFractionRange("hinge_pattern", "advanced");
  const bodyweightKg = 80;
  assert(
    advancedHigh * bodyweightKg < 125,
    `advanced hinge ceiling for an 80kg lifter (${(advancedHigh * bodyweightKg).toFixed(0)}kg) must be well under the reported unrealistic 125-135kg`,
  );
});

Deno.test("a known lift always overrides the population estimate for that pattern", () => {
  const guidance = buildLoadGuidance(80, "advanced", { hinge_pattern: 100 });
  assert(guidance.includes("90-110kg"), `expected a +/-10% band around the stated 100kg, got: ${guidance}`);
});

Deno.test("known lifts only apply to the pattern they were given for -- other patterns stay population-based", () => {
  const withKnown = buildLoadGuidance(80, "moderate", { hinge_pattern: 100 });
  const withoutKnown = buildLoadGuidance(80, "moderate");
  const squatLine = (s: string) => s.match(/squat pattern (\d+-\d+kg)/)?.[1];
  assertEquals(squatLine(withKnown), squatLine(withoutKnown));
});

Deno.test("a missing or zero known lift for a pattern falls back to the population estimate, not a bogus 0-0kg range", () => {
  const guidance = buildLoadGuidance(80, "moderate", { hinge_pattern: 0, squat_pattern: undefined as unknown as number });
  assert(!guidance.includes("0-0kg"));
});

Deno.test("unknown experience level falls back to moderate, same as the rest of this codebase's convention", () => {
  const guidance = buildLoadGuidance(70, "some_unknown_value");
  const moderateGuidance = buildLoadGuidance(70, "moderate");
  // Both should produce the same numeric ranges (same underlying fraction
  // bands), even though the label in the sentence itself differs.
  const extractNumbers = (s: string) => s.match(/\d+-\d+kg/g);
  assertEquals(extractNumbers(guidance), extractNumbers(moderateGuidance));
});
