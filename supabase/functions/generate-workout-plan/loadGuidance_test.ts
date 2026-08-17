import { assert, assertEquals, assertThrows } from "jsr:@std/assert";
import { buildLoadGuidance, loadFractionRange, twoDumbbellLoadRangeKg } from "./loadGuidance.ts";

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

// --- twoDumbbellLoadRangeKg / two-dumbbell squat-hinge prompt text ---

Deno.test("REGRESSION: the real bug report -- a 60kg woman's two-dumbbell squat ceiling stays clearly under the reported 16-24kg-each", () => {
  // BUG report: a 168cm/60kg woman was prescribed 16-24kg PER DUMBBELL
  // (32-48kg total) for a two-dumbbell squat -- roughly double a sane
  // number, because the barbell-equivalent TOTAL was used directly as a
  // per-dumbbell figure. Checked at moderate AND advanced (the tiers
  // closest to the reported numbers) since the bug report doesn't state
  // which self-reported experience produced it.
  for (const experience of ["moderate", "advanced"]) {
    const { eachHighKg } = twoDumbbellLoadRangeKg("squat_pattern", 60, experience);
    assert(eachHighKg < 16, `${experience}: per-dumbbell ceiling (${eachHighKg.toFixed(1)}kg) must be clearly under the reported unrealistic 16kg floor`);
  }
});

Deno.test("two-dumbbell total is meaningfully lighter than the raw barbell-equivalent total, not just split in half", () => {
  for (const pattern of ["squat_pattern", "hinge_pattern"] as const) {
    for (const experience of ["newbie", "moderate", "advanced"]) {
      const [barbellLowFrac, barbellHighFrac] = loadFractionRange(pattern, experience);
      const barbellTotalHighKg = barbellHighFrac * 70;
      const { totalHighKg } = twoDumbbellLoadRangeKg(pattern, 70, experience);
      assert(
        totalHighKg < barbellTotalHighKg * 0.5,
        `${pattern}/${experience}: two-dumbbell total (${totalHighKg.toFixed(1)}kg) should be well under half the barbell total (${barbellTotalHighKg.toFixed(1)}kg), not just a straight half-split`,
      );
    }
  }
});

Deno.test("two-dumbbell per-implement is always exactly half the two-dumbbell total", () => {
  const { totalLowKg, totalHighKg, eachLowKg, eachHighKg } = twoDumbbellLoadRangeKg("squat_pattern", 70, "moderate");
  assertEquals(eachLowKg, totalLowKg / 2);
  assertEquals(eachHighKg, totalHighKg / 2);
});

Deno.test("higher experience levels get heavier two-dumbbell ranges too", () => {
  for (const pattern of ["squat_pattern", "hinge_pattern"] as const) {
    const newbie = twoDumbbellLoadRangeKg(pattern, 70, "newbie");
    const moderate = twoDumbbellLoadRangeKg(pattern, 70, "moderate");
    const advanced = twoDumbbellLoadRangeKg(pattern, 70, "advanced");
    assert(newbie.eachHighKg < moderate.eachHighKg, `${pattern}: newbie should be lighter than moderate`);
    assert(moderate.eachHighKg < advanced.eachHighKg, `${pattern}: moderate should be lighter than advanced`);
  }
});

Deno.test("a known lift is used as the two-dumbbell base too, not just the population estimate", () => {
  const withKnown = twoDumbbellLoadRangeKg("hinge_pattern", 80, "moderate", { hinge_pattern: 100 });
  const withoutKnown = twoDumbbellLoadRangeKg("hinge_pattern", 80, "moderate");
  assert(
    withKnown.totalHighKg !== withoutKnown.totalHighKg,
    "a stated known lift should change the two-dumbbell derived range, not be ignored",
  );
  // 100kg known lift -> +/-10% band (90-110kg) -> x0.4 derate -> 36-44kg total.
  assertEquals(withKnown.totalLowKg.toFixed(1), (90 * 0.4).toFixed(1));
  assertEquals(withKnown.totalHighKg.toFixed(1), (110 * 0.4).toFixed(1));
});

Deno.test("unknown experience level falls back to moderate for the two-dumbbell range too", () => {
  const unknown = twoDumbbellLoadRangeKg("squat_pattern", 70, "some_unknown_value");
  const moderate = twoDumbbellLoadRangeKg("squat_pattern", 70, "moderate");
  assertEquals(unknown, moderate);
});

Deno.test("prompt text states the two-dumbbell squat/hinge numbers in the exact '2xNkg dumbbells' format, with a total AND a per-dumbbell figure", () => {
  const guidance = buildLoadGuidance(60, "moderate");
  assert(guidance.includes("TWO-DUMBBELL"), "must call out the two-dumbbell case explicitly");
  assert(guidance.includes("2xNkg dumbbells"), "must instruct the exact parseable output format");
  assert(guidance.toLowerCase().includes("dumbbell squat"), "must name a concrete two-dumbbell squat example");
  assert(guidance.toLowerCase().includes("dumbbell romanian deadlift"), "must name a concrete two-dumbbell hinge example");
  assert(guidance.includes("EACH dumbbell"), "must explicitly label the per-dumbbell figure");
  const { totalLowKg, totalHighKg, eachLowKg, eachHighKg } = twoDumbbellLoadRangeKg("squat_pattern", 60, "moderate");
  assert(guidance.includes(`${totalLowKg.toFixed(0)}-${totalHighKg.toFixed(0)}kg`), "must state the derated total range");
  assert(guidance.includes(`${eachLowKg.toFixed(0)}-${eachHighKg.toFixed(0)}kg EACH`), "must state the derated per-dumbbell range");
});

Deno.test("prompt text explicitly warns against reusing the barbell-equivalent number as a per-dumbbell figure", () => {
  const guidance = buildLoadGuidance(60, "moderate");
  assert(
    /never write the barbell-equivalent total/i.test(guidance),
    "must explicitly warn against the exact mistake the bug report showed",
  );
});
