// Run: deno test supabase/functions/
//
// These cover the decision that a tester actually reported as broken: on the
// Apple-Health-only path, `medium` used to be the only band the code could
// ever return. The regression tests below use that user's real production
// values.

import { assertEquals } from "jsr:@std/assert";
import { assessHealthKit } from "./healthkitBand.ts";

// Values taken from the reporting user's daily_snapshot rows: HRV identical
// to its own baseline (because the client kept resubmitting one stale
// sample), resting HR at baseline, and no sleep data because the watch was
// not worn overnight.
const REPORTED = { hrvMs: 52.8, restingHr: 67 };
const HRV_BASELINE = 52.8;
const RHR_BASELINE = 67;

Deno.test("an unremarkable day is still medium", () => {
  const { band } = assessHealthKit(REPORTED, HRV_BASELINE, RHR_BASELINE);
  assertEquals(band, "medium");
});

Deno.test("REGRESSION: high is reachable without any sleep data", () => {
  // The old implementation required `sleep !== null && sleep >= 7` for high,
  // so every user who takes the watch off at night was capped at medium
  // forever regardless of how recovered they were.
  const { band } = assessHealthKit(
    { hrvMs: 60, restingHr: 62 },
    HRV_BASELINE,
    RHR_BASELINE,
  );
  assertEquals(band, "high");
});

Deno.test("resting HR alone can drive the band down", () => {
  // No HRV, no sleep -- just a resting heart rate 12% above baseline, which
  // is a well-established fatigue/illness signal and should be actioned.
  const { band } = assessHealthKit({ restingHr: 75 }, null, RHR_BASELINE);
  assertEquals(band, "low");
});

Deno.test("a single good signal is not enough for high", () => {
  // Guards against over-correcting: one +1 signal should leave us at medium,
  // not promote a thin read to "push hard".
  const { band } = assessHealthKit({ restingHr: 62 }, null, RHR_BASELINE);
  assertEquals(band, "medium");
});

Deno.test("short sleep pulls the band down", () => {
  const { band } = assessHealthKit(
    { sleepHours: 5, ...REPORTED },
    HRV_BASELINE,
    RHR_BASELINE,
  );
  assertEquals(band, "low");
});

Deno.test("long sleep plus a good HRV reaches high", () => {
  const { band } = assessHealthKit(
    { sleepHours: 8, hrvMs: 60, restingHr: 67 },
    HRV_BASELINE,
    RHR_BASELINE,
  );
  assertEquals(band, "high");
});

Deno.test("missing baselines mean those signals are ignored, not assumed good", () => {
  // A value with nothing to compare it against contributes nothing. It must
  // not be read as "normal", which would silently manufacture confidence.
  const result = assessHealthKit({ hrvMs: 60, restingHr: 62 }, null, null);
  assertEquals(result.band, "medium");
  assertEquals(result.confidence, "low");
});

Deno.test("no usable signals at all is medium, flagged low confidence", () => {
  const result = assessHealthKit({}, null, null);
  assertEquals(result.band, "medium");
  assertEquals(result.confidence, "low");
});

Deno.test("confidence reflects how many signals were available", () => {
  assertEquals(
    assessHealthKit({ restingHr: 67 }, null, RHR_BASELINE).confidence,
    "low",
  );
  assertEquals(
    assessHealthKit(REPORTED, HRV_BASELINE, RHR_BASELINE).confidence,
    "high",
  );
  assertEquals(
    assessHealthKit({ sleepHours: 8, ...REPORTED }, HRV_BASELINE, RHR_BASELINE)
      .confidence,
    "high",
  );
});

Deno.test("thresholds are relative to the user's own baseline", () => {
  // Same absolute HRV, different people: 40ms is poor against a baseline of
  // 60 and fine against 30. Absolute SDNN cutoffs from population data would
  // get both of these wrong. Here it shows up as a point difference (-1 vs
  // +0) rather than a band change, since HRV alone can no longer move a band.
  const poor = assessHealthKit({ hrvMs: 40, sleepHours: 6.5 }, 60, null);
  const fine = assessHealthKit({ hrvMs: 40, sleepHours: 6.5 }, 30, null);
  assertEquals(poor.band, "low");
  assertEquals(fine.band, "medium");
});

Deno.test("REGRESSION: HRV alone cannot decide the band", () => {
  // HRV used to carry the same +/-2 as resting HR, contradicting the
  // function's own docblock. Apple reports SDNN, sampled passively and
  // noisily, so one artefact reading at half baseline was enough to force a
  // rest day. It is now capped at +/-1 and must be corroborated.
  assertEquals(assessHealthKit({ hrvMs: 20 }, 60, null).band, "medium");
  assertEquals(assessHealthKit({ hrvMs: 90 }, 60, null).band, "medium");
});

Deno.test("resting HR is the one signal allowed to decide alone", () => {
  assertEquals(assessHealthKit({ restingHr: 75 }, null, 67).band, "low");
});

Deno.test("REGRESSION: a provisional baseline may only hold the user back", () => {
  // Thin history is reason enough to be cautious, never to promote someone
  // to "push hard". Negative points still count; positive ones are dropped.
  const good = { hrvMs: 60, restingHr: 62, sleepHours: 8 };
  assertEquals(assessHealthKit(good, 52.8, 67, false).band, "high");
  assertEquals(assessHealthKit(good, 52.8, 67, true).band, "medium");

  const bad = { restingHr: 75, sleepHours: 5 };
  assertEquals(assessHealthKit(bad, null, 67, true).band, "low");
});
