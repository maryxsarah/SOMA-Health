// Run: deno test supabase/functions/
//
// deriveCyclePhase is the deterministic half of Phase 5 (see
// docs/coaching-personalization-plan.md). Reference start date
// "2026-08-01"; `today` is varied to land on an exact daysSince offset.

import { assert, assertEquals } from "jsr:@std/assert";
import { CYCLE_PHASE_CONSIDERATIONS, deriveCyclePhase } from "./cyclePhaseGuidance.ts";

const START = "2026-08-01";

function addDays(dateStr: string, days: number): string {
  const d = new Date(`${dateStr}T00:00:00.000Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}

Deno.test("null when no start date is recorded (not opted in)", () => {
  assertEquals(deriveCyclePhase(null, 28, START), null);
});

Deno.test("null when the recorded start date is in the future (bad data, fails safe)", () => {
  assertEquals(deriveCyclePhase(addDays(START, 5), null, START), null);
});

Deno.test("confidence is HIGH within the first (recorded) cycle", () => {
  const result = deriveCyclePhase(START, 28, addDays(START, 10));
  assert(result);
  assertEquals(result.confidence, "high");
});

Deno.test("confidence is LOW when projected 1-2 cycles forward", () => {
  const oneCycleOut = deriveCyclePhase(START, 28, addDays(START, 30)); // cyclesElapsed = 1
  const twoCyclesOut = deriveCyclePhase(START, 28, addDays(START, 60)); // cyclesElapsed = 2
  assert(oneCycleOut);
  assert(twoCyclesOut);
  assertEquals(oneCycleOut.confidence, "low");
  assertEquals(twoCyclesOut.confidence, "low");
});

Deno.test("STALE: null when projected 3+ cycles forward, never a low-confidence guess that far out", () => {
  assertEquals(deriveCyclePhase(START, 28, addDays(START, 84)), null); // cyclesElapsed = 3
  assertEquals(deriveCyclePhase(START, 28, addDays(START, 200)), null);
});

Deno.test("default cycle length (28 days) is used when typicalCycleLengthDays is null", () => {
  // day 10 of a defaulted 28-day cycle should be follicular (see boundary
  // tests below) -- same result whether 28 is passed explicitly or omitted.
  const withDefault = deriveCyclePhase(START, null, addDays(START, 10));
  const explicit28 = deriveCyclePhase(START, 28, addDays(START, 10));
  assertEquals(withDefault, explicit28);
});

Deno.test("phase boundaries on a 28-day cycle (days 1-5 menstrual, 6-13 follicular, 14-16 ovulatory, 17-28 luteal)", () => {
  const phaseOn = (daysSince: number) => deriveCyclePhase(START, 28, addDays(START, daysSince))?.phase;
  // Menstrual: daysSince 0-4 (day 1-5).
  assertEquals(phaseOn(0), "menstrual");
  assertEquals(phaseOn(4), "menstrual");
  // Follicular: daysSince 5-12 (day 6-13).
  assertEquals(phaseOn(5), "follicular");
  assertEquals(phaseOn(12), "follicular");
  // Ovulatory: daysSince 13-15 (day 14-16).
  assertEquals(phaseOn(13), "ovulatory");
  assertEquals(phaseOn(15), "ovulatory");
  // Luteal: daysSince 16-27 (day 17-28).
  assertEquals(phaseOn(16), "luteal");
  assertEquals(phaseOn(27), "luteal");
});

Deno.test("boundaries scale proportionally for a non-default (35-day) cycle length, not fixed day-counts", () => {
  const phaseOn = (daysSince: number) => deriveCyclePhase(START, 35, addDays(START, daysSince))?.phase;
  // Menstrual end fraction 5/28 * 35 = 6.25 -> daysSince 0-5 menstrual, 6+ not.
  assertEquals(phaseOn(5), "menstrual");
  assertEquals(phaseOn(7), "follicular");
  // A 28-day-shaped boundary (daysSince 13 -> ovulatory on a 28-day cycle)
  // should NOT yet be ovulatory on a 35-day cycle -- still follicular,
  // proving the boundaries actually scale with cycle length.
  assertEquals(phaseOn(13), "follicular");
});

Deno.test("cycle wraps correctly past the recorded cycle (day-in-cycle uses modulo, not raw daysSince)", () => {
  // 30 days into a 28-day-length cycle should read the same as day 2
  // (30 % 28 = 2) of the NEXT cycle -- still menstrual, just low confidence.
  const result = deriveCyclePhase(START, 28, addDays(START, 30));
  assert(result);
  assertEquals(result.phase, "menstrual");
  assertEquals(result.confidence, "low");
});

Deno.test("every phase has a non-empty, non-diagnostic consideration string", () => {
  for (const phase of ["menstrual", "follicular", "ovulatory", "luteal"] as const) {
    const text = CYCLE_PHASE_CONSIDERATIONS[phase];
    assert(text.length > 0, phase);
    assertFalseDiagnosticLanguage(text);
  }
});

function assertFalseDiagnosticLanguage(text: string): void {
  const lower = text.toLowerCase();
  for (const banned of ["diagnos", "fertil", "ovulation window", "pregnan"]) {
    assert(!lower.includes(banned), `unexpected diagnostic/fertility language ("${banned}") in: ${text}`);
  }
}
