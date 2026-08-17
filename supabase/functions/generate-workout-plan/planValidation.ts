// Deterministic, post-generation checks on a completed plan -- pulled out
// as their own small module (same pattern as finisherCatalog.ts/goalWork.ts)
// so this logic is unit-testable independent of the Anthropic call itself.

export interface PlanExerciseNames {
  warm_up: { name: string }[];
  blocks: { exercises: { name: string }[] }[];
  cool_down: { name: string }[];
}

/// True when a finisher block SHOULD be present (decideFinisher's own
/// deterministic decision -- finisherCatalog.ts) but the generated plan
/// doesn't actually have one. BUG report: "finisher rarely shows." Before
/// assuming decideFinisher's eligibility gate was too strict, a real query
/// against ai_workout_plan showed the gate is already permissive --
/// `include` is true for EVERY moderate/push_hard plan, no readiness/
/// injury/split condition narrows it further (only `exceptional` is
/// gated) -- yet only ~35-65% of those plans (varies by window queried;
/// small sample) actually contain an `is_finisher: true` block. The gate
/// isn't the bottleneck; prompt adherence is -- the same "instruction is a
/// request, not a guarantee" gap this file's other checks already cover.
export function finisherMissing(
  plan: { blocks: { is_finisher: boolean }[] },
  finisherShouldBeIncluded: boolean,
): boolean {
  if (!finisherShouldBeIncluded) return false;
  return !plan.blocks.some((b) => b.is_finisher === true);
}

/// Every named exercise (warm_up, every block's exercises, cool_down)
/// should appear at most once in a session -- a real coach varies
/// movements rather than repeating the identical named exercise across
/// multiple blocks or superset rounds (BUG report: "Barbell Squat" 4
/// times in one plan). Returns the names that appeared more than once
/// (deduplicated), or [] if the plan is already clean.
export function findDuplicateExerciseNames(plan: PlanExerciseNames): string[] {
  const allNames = [
    ...plan.warm_up.map((e) => e.name),
    ...plan.blocks.flatMap((b) => b.exercises.map((e) => e.name)),
    ...plan.cool_down.map((e) => e.name),
  ];
  const seen = new Set<string>();
  const duplicates = new Set<string>();
  for (const name of allNames) {
    if (seen.has(name)) duplicates.add(name);
    seen.add(name);
  }
  return Array.from(duplicates);
}

/// True when today's cool_down is the exact same set of exercise names as
/// yesterday's cool_down for the SAME suggestion title (both length and
/// membership -- not just an overlapping subset). BUG report: cool_down
/// never varies day to day. Root cause -- fetchRecentExerciseNames
/// (index.ts) deliberately excludes warm_up/cool_down from the freshness
/// exclusion ("repeating the same warm-up stretch or mobility drill day to
/// day is normal and often correct"), which is true for warm_up but was
/// directly contradicted by user feedback for cool_down specifically. That
/// exclusion is now narrower (cool_down IS included, warm_up still isn't --
/// see fetchRecentExerciseNames), but a soft candidate-pool exclusion is
/// still just a nudge, not a guarantee. This is the deterministic backstop
/// -- same "instruction/nudge is a request, not a guarantee" posture as
/// findDuplicateExerciseNames above, checked via the exact same retry
/// mechanism in index.ts.
export function coolDownRepeatsYesterday(
  plan: { cool_down: { name: string }[] },
  yesterdaysCoolDownNames: string[] | null,
): boolean {
  if (!yesterdaysCoolDownNames || yesterdaysCoolDownNames.length === 0) return false;
  const todayNames = plan.cool_down.map((e) => e.name);
  if (todayNames.length !== yesterdaysCoolDownNames.length) return false;
  const todaySet = new Set(todayNames);
  return yesterdaysCoolDownNames.every((name) => todaySet.has(name));
}
