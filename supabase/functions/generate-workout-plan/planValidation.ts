// Deterministic, post-generation checks on a completed plan -- pulled out
// as their own small module (same pattern as finisherCatalog.ts/goalWork.ts)
// so this logic is unit-testable independent of the Anthropic call itself.

export interface PlanExerciseNames {
  warm_up: { name: string }[];
  blocks: { exercises: { name: string }[] }[];
  cool_down: { name: string }[];
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
