// DRAFTED, NOT EXPERT-REVIEWED -- same standing caveat as volumeLandmarks.ts.
// General, non-diagnostic, evidence-based considerations correlated with
// sex. Phase 5 (docs/coaching-personalization-plan.md): now cycle-phase-
// aware when the user has opted in (see _shared/cyclePhaseGuidance.ts for
// the derivation/science and users.last_period_start_date/
// typical_cycle_length_days for storage) -- falls back to the original
// generic line, byte-identical, for anyone who hasn't (the vast majority
// of female users, at least at launch) or whose data is too stale to
// trust. This is the ONLY hook Phase 5 wires up -- nutrition was
// explicitly deferred, see the design doc.

import { type CyclePhaseResult, CYCLE_PHASE_CONSIDERATIONS } from "../_shared/cyclePhaseGuidance.ts";

/// The original, pre-Phase-5 line -- unchanged wording, still the fallback
/// for every non-opted-in female user (and the only ever line prior to
/// this phase). Kept as a named constant so the "byte-identical fallback"
/// guarantee is trivially testable.
export const GENERIC_SEX_AWARE_LINE =
  "General consideration: hormonal fluctuation across a natural cycle can affect recovery and connective-tissue laxity for some women -- favor controlled tempo and a thorough warm-up on high-impact or plyometric work. Treat today's actual recovery signals (given above) as the primary guide over any fixed assumption.";

export function describeSexAwareConsiderations(
  sex: string | null,
  category: string,
  cyclePhase: CyclePhaseResult | null,
): string {
  if (sex !== "female" || category === "rest") {
    return "";
  }
  if (cyclePhase === null) {
    return GENERIC_SEX_AWARE_LINE;
  }

  // Low confidence = projected forward from a stated typical length rather
  // than freshly confirmed against a recent recorded date -- hedged in the
  // line itself rather than silently presented with the same certainty as
  // a high-confidence read.
  const estimateHedge = cyclePhase.confidence === "low"
    ? " (estimated from your typical cycle length, not a recently confirmed date)"
    : "";
  return `Cycle-phase consideration -- the user is likely in the ${cyclePhase.phase} phase of their cycle right now${estimateHedge}: ${
    CYCLE_PHASE_CONSIDERATIONS[cyclePhase.phase]
  }. Treat today's actual recovery signals (given above) as the primary guide over any fixed assumption.`;
}

/// Dosing-only caveat for a goal-work block -- never adjusts the goal's
/// target numbers, only how conservatively a new block's volume ramps in.
export function describeSexAwareGoalDoseConsideration(sex: string | null): string {
  if (sex !== "female") {
    return "";
  }
  return "General consideration: ease into a new goal block's dose over its first 1-2 weeks rather than the full prescribed volume immediately, and prioritize clean technique over max effort on any explosive/plyometric work.";
}
