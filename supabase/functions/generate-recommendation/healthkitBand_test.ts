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
  // Same absolute HRV, different people: 40ms is poor for someone whose
  // baseline is 60 and excellent for someone whose baseline is 30. Absolute
  // SDNN cutoffs from population data would get both of these wrong.
  assertEquals(assessHealthKit({ hrvMs: 40 }, 60, null).band, "low");
  assertEquals(assessHealthKit({ hrvMs: 40 }, 30, null).band, "medium");
});
