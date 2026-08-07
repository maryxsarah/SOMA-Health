// DRAFTED, NOT EXPERT-REVIEWED -- same standing caveat as volumeLandmarks.ts.
// General, non-diagnostic, evidence-based considerations correlated with
// sex -- NOT cycle-phase tracking. No cycle data is collected anywhere in
// this app (only `pregnancy`/`pregnancy_week`, handled separately in
// pregnancyGuidance.ts); adding real cycle-phase tracking would be a
// separate, larger epic (new onboarding UI, new DB columns, new prompt
// logic) and is explicitly out of scope here. Framed as a general
// consideration a coach would keep in mind, never as a diagnosis or
// individualized medical claim -- built on well-established, published
// exercise-science principles, not affiliated with or endorsed by any
// individual trainer, coach, or author.

export function describeSexAwareConsiderations(sex: string | null, category: string): string {
  if (sex !== "female" || category === "rest") {
    return "";
  }
  return "General consideration: hormonal fluctuation across a natural cycle can affect recovery and connective-tissue laxity for some women -- favor controlled tempo and a thorough warm-up on high-impact or plyometric work. Treat today's actual recovery signals (given above) as the primary guide over any fixed assumption.";
}

/// Dosing-only caveat for a goal-work block -- never adjusts the goal's
/// target numbers, only how conservatively a new block's volume ramps in.
export function describeSexAwareGoalDoseConsideration(sex: string | null): string {
  if (sex !== "female") {
    return "";
  }
  return "General consideration: ease into a new goal block's dose over its first 1-2 weeks rather than the full prescribed volume immediately, and prioritize clean technique over max effort on any explosive/plyometric work.";
}
