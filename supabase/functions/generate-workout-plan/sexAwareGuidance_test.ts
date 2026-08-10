// Run: deno test supabase/functions/
//
// describeSexAwareConsiderations is Phase 5's ONLY hook (see
// docs/coaching-personalization-plan.md) -- these tests guard the
// byte-identical fallback for anyone not opted in (the design's central
// "no new parallel system" guarantee) and the phase-specific line once
// cyclePhase is supplied. describeSexAwareGoalDoseConsideration is a
// separate, unrelated function (goal-work dosing, not cycle-phase) --
// its own coverage lives at the bottom of this file.

import { assert, assertEquals, assertNotEquals } from "jsr:@std/assert";
import { CYCLE_PHASE_CONSIDERATIONS, type CyclePhaseResult } from "../_shared/cyclePhaseGuidance.ts";
import {
  describeSexAwareConsiderations,
  describeSexAwareGoalDoseConsideration,
  GENERIC_SEX_AWARE_LINE,
} from "./sexAwareGuidance.ts";

Deno.test("BYTE-IDENTICAL FALLBACK: cyclePhase null returns the exact pre-Phase-5 generic line", () => {
  assertEquals(describeSexAwareConsiderations("female", "moderate", null), GENERIC_SEX_AWARE_LINE);
});

Deno.test("non-female sex returns empty regardless of cyclePhase", () => {
  const phase: CyclePhaseResult = { phase: "follicular", confidence: "high" };
  assertEquals(describeSexAwareConsiderations("male", "moderate", phase), "");
  assertEquals(describeSexAwareConsiderations("other", "moderate", phase), "");
  assertEquals(describeSexAwareConsiderations(null, "moderate", phase), "");
});

Deno.test("rest day returns empty regardless of cyclePhase", () => {
  const phase: CyclePhaseResult = { phase: "luteal", confidence: "high" };
  assertEquals(describeSexAwareConsiderations("female", "rest", phase), "");
  assertEquals(describeSexAwareConsiderations("female", "rest", null), "");
});

Deno.test("high-confidence cyclePhase produces a phase-specific line with no staleness hedge", () => {
  const line = describeSexAwareConsiderations("female", "moderate", { phase: "follicular", confidence: "high" });
  assert(line.includes("follicular"));
  assert(line.includes(CYCLE_PHASE_CONSIDERATIONS.follicular));
  assert(!line.toLowerCase().includes("estimated from"));
});

Deno.test("low-confidence cyclePhase includes an explicit estimate hedge", () => {
  const line = describeSexAwareConsiderations("female", "moderate", { phase: "luteal", confidence: "low" });
  assert(line.includes("luteal"));
  assert(line.toLowerCase().includes("estimated from"));
});

Deno.test("every phase produces its own distinct consideration text", () => {
  const phases = ["menstrual", "follicular", "ovulatory", "luteal"] as const;
  const lines = phases.map((phase) => describeSexAwareConsiderations("female", "moderate", { phase, confidence: "high" }));
  for (const [i, phase] of phases.entries()) {
    assert(lines[i].includes(CYCLE_PHASE_CONSIDERATIONS[phase]), phase);
  }
  assertEquals(new Set(lines).size, phases.length, "expected 4 distinct lines");
});

Deno.test("every non-empty line still ends with the 'today's actual signals are the primary guide' caveat", () => {
  const generic = describeSexAwareConsiderations("female", "moderate", null);
  const phaseSpecific = describeSexAwareConsiderations("female", "moderate", { phase: "menstrual", confidence: "high" });
  const caveat = "Treat today's actual recovery signals (given above) as the primary guide over any fixed assumption.";
  assert(generic.endsWith(caveat));
  assert(phaseSpecific.endsWith(caveat));
});

// --- describeSexAwareGoalDoseConsideration (unrelated to Phase 5, from main) ---

Deno.test("describeSexAwareGoalDoseConsideration: female returns the goal-dose caveat", () => {
  const line = describeSexAwareGoalDoseConsideration("female");
  assertNotEquals(line, "");
  assertEquals(line.includes("goal block"), true);
});

Deno.test("describeSexAwareGoalDoseConsideration: male returns nothing", () => {
  assertEquals(describeSexAwareGoalDoseConsideration("male"), "");
});

Deno.test("describeSexAwareGoalDoseConsideration: null sex returns nothing", () => {
  assertEquals(describeSexAwareGoalDoseConsideration(null), "");
});

Deno.test("describeSexAwareGoalDoseConsideration: never mentions target numbers -- dosing only", () => {
  const line = describeSexAwareGoalDoseConsideration("female");
  assertEquals(line.toLowerCase().includes("target"), false);
  assertEquals(line.toLowerCase().includes("gain"), false);
});
