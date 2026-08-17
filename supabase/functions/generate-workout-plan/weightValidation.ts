// Deterministic, post-generation check for the "two-dumbbell squat/hinge
// prescribed at the barbell-equivalent weight PER DUMBBELL" bug -- pulled
// out as its own small module, same pattern as planValidation.ts, so it's
// unit-testable independent of the Anthropic call itself.
//
// BUG report: a 168cm/60kg woman was prescribed 16-24kg PER DUMBBELL
// (32-48kg total) for a two-dumbbell squat. loadGuidance.ts's
// buildLoadGuidance now states the derated per-dumbbell ceiling
// explicitly in the prompt (see that file's 2026-08-15 comment) -- this
// module is the deterministic backstop for when the model states a
// number over that ceiling anyway, same "a prompt instruction is a
// request, not a guarantee" posture planValidation.ts's duplicate-name
// check already uses. index.ts reuses THAT SAME retry mechanism for this
// check rather than inventing a second one.

import { twoDumbbellLoadRangeKg } from "./loadGuidance.ts";

export type LoadPattern = "squat_pattern" | "hinge_pattern";

/// Keyword classification of an exercise name into the bilateral pattern
/// its load should be checked against -- same "deterministic keyword
/// match, not another LLM call" posture as weatherSafety.ts's
/// isOutdoorCardioExerciseName. Deliberately narrow: only the two
/// patterns loadGuidance.ts documents as "bilateral-only" (a two-dumbbell
/// variant still loads the body symmetrically), which is exactly where
/// this specific per-implement bug can occur. Returns null for anything
/// else, including a barbell variant -- that uses the raw guideline
/// total as-is and isn't this bug's scope.
export function classifyLoadPattern(name: string): LoadPattern | null {
  if (/squat/i.test(name)) return "squat_pattern";
  if (/deadlift|romanian|\brdl\b|good.?morning/i.test(name)) return "hinge_pattern";
  return null;
}

/// True only for a name that plausibly names a TWO-DUMBBELL (or two-
/// kettlebell) variant -- a bare "Dumbbell Squat"/"Dumbbell Romanian
/// Deadlift", as opposed to a single-implement goblet/kettlebell hold
/// (out of scope -- see loadGuidance.ts's own comment on why single-
/// implement stays bilateral-total-as-is) or a barbell variant.
export function isTwoImplementVariant(name: string): boolean {
  return /dumbbell/i.test(name) && !/goblet/i.test(name);
}

/// Parses weight_guidance for an explicit per-dumbbell number -- either
/// "NxWkg" (the exact format buildLoadGuidance now instructs the model to
/// use) or "Wkg each" -- and returns the per-implement weight in kg, or
/// null if the text doesn't state one in a format this can trust.
/// Deliberately narrow, no attempt to parse every possible phrasing: a
/// false negative here just means one exercise silently skips the
/// deterministic check (no worse than before this module existed), while
/// a false positive could trigger a wrong retry.
export function parsePerImplementKg(weightGuidance: string): number | null {
  const countTimes = weightGuidance.match(/(\d+(?:\.\d+)?)\s*x\s*(\d+(?:\.\d+)?)\s*kg/i);
  if (countTimes) {
    const count = parseFloat(countTimes[1]);
    const perImplement = parseFloat(countTimes[2]);
    return count === 2 ? perImplement : null;
  }
  const each = weightGuidance.match(/(\d+(?:\.\d+)?)\s*kg\s*each/i);
  if (each) return parseFloat(each[1]);
  return null;
}

/// The hard per-implement ceiling for a two-dumbbell squat/hinge exercise
/// -- the SAME upper bound buildLoadGuidance already states as a prompt
/// guideline for this user's own bodyweight/experience/known lifts (both
/// call twoDumbbellLoadRangeKg, so they can never drift apart), just
/// mechanically enforced here instead of only ever being a request the
/// model can ignore.
export function twoImplementCeilingKg(
  pattern: LoadPattern,
  weightKg: number,
  experience: string,
  knownLifts?: Record<string, number> | null,
): number {
  return twoDumbbellLoadRangeKg(pattern, weightKg, experience, knownLifts).eachHighKg;
}

export interface WeightCeilingViolation {
  exerciseName: string;
  statedPerImplementKg: number;
  ceilingPerImplementKg: number;
}

interface ExerciseWithWeight {
  name: string;
  weight_guidance: string;
}
interface PlanWithWeight {
  warm_up: ExerciseWithWeight[];
  blocks: { exercises: ExerciseWithWeight[] }[];
  cool_down: ExerciseWithWeight[];
}

/// Scans every exercise in the plan; returns the ones whose weight_guidance
/// states an explicit two-dumbbell per-implement number above the hard
/// ceiling for this user's bodyweight/experience/known lifts. [] if the
/// plan is clean, including when weightKg is unknown -- no population
/// ceiling to check a specific number against in that case (same as
/// buildLoadGuidance itself omitting numbers entirely then).
export function findWeightCeilingViolations(
  plan: PlanWithWeight,
  weightKg: number | null,
  experience: string,
  knownLifts?: Record<string, number> | null,
): WeightCeilingViolation[] {
  if (weightKg === null) return [];
  const allExercises = [
    ...plan.warm_up,
    ...plan.blocks.flatMap((b) => b.exercises),
    ...plan.cool_down,
  ];
  const violations: WeightCeilingViolation[] = [];
  for (const exercise of allExercises) {
    const pattern = classifyLoadPattern(exercise.name);
    if (!pattern || !isTwoImplementVariant(exercise.name)) continue;
    const stated = parsePerImplementKg(exercise.weight_guidance);
    if (stated === null) continue;
    const ceiling = twoImplementCeilingKg(pattern, weightKg, experience, knownLifts);
    if (stated > ceiling) {
      violations.push({ exerciseName: exercise.name, statedPerImplementKg: stated, ceilingPerImplementKg: ceiling });
    }
  }
  return violations;
}
