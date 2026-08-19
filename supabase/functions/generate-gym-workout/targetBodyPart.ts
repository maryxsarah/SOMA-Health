// Resolves which BodyPartFocus today's gym-photo-generated workout should
// target, so selectTemplate (templates.ts) can rank a body-part match
// ahead of equipment specificity instead of letting equipment silently
// decide the day's focus (see BUG report in index.ts's caller comment).
//
// The normal (non-photo) picker flow doesn't have this problem: the client
// (RecommendationDetailView.filteredWorkoutSuggestions/selectTopSuggestion,
// RecommendationDetailView.swift) already derives a goals+injury-aware
// default body part and sends it to generate-workout-plan as
// selection.bodyPart. Gym-photo never gets a client selection, so this
// derives the same answer server-side, reusing the same two signals rather
// than reimplementing them:
//   - the trailing-7-day per-body-part rotation count
//     (countRecentTrainingDaysByBodyPart, _shared/trainingDayCounters.ts)
//   - the injury redirect (resolveBodyPartForInjuries,
//     _shared/injurySubstitution.ts), already used by generate-workout-plan
//     for exactly this purpose.
//
// CATEGORY_BODY_PART_CANDIDATES below is a hand-kept, reduced mirror of the
// category -> {bodyPart, goals} shape declared in
// RecommendationCategory.workoutSuggestions (Soma/Models/
// DailyRecommendation.swift) -- equipment is deliberately left out, since
// this only answers "what body part should today target", and gym-photo's
// equipment axis (the photographed gym) is unrelated to the Swift picker's
// home-equipment axis. There is no way to share the literal Swift catalog
// with a Deno function, so this must be kept in sync by hand if that
// catalog's body parts/goals change -- same posture GymWorkoutTemplate.
// bodyPart's own comment already takes referencing the Swift raw values.

import { resolveBodyPartForInjuries, type BodyPartFocus } from "../_shared/injurySubstitution.ts";
import type { InjurySeverityLevel } from "../_shared/contraindications.ts";

interface CandidateFocus {
  bodyPart: BodyPartFocus;
  goals: string[];
}

const CATEGORY_BODY_PART_CANDIDATES: Record<string, CandidateFocus[]> = {
  push_hard: [
    { bodyPart: "full_body", goals: ["build_strength", "gain_muscle"] },
    { bodyPart: "upper_body", goals: ["build_strength", "gain_muscle"] },
    { bodyPart: "lower_body", goals: ["build_strength", "gain_muscle"] },
    { bodyPart: "full_body", goals: ["leaner_toned", "more_sculpted", "cardio_endurance"] },
    { bodyPart: "cardio", goals: ["cardio_endurance", "leaner_toned"] },
    { bodyPart: "cardio", goals: ["cardio_endurance"] },
    { bodyPart: "full_body", goals: ["build_strength", "gain_muscle"] },
  ],
  moderate: [
    { bodyPart: "full_body", goals: ["build_strength", "gain_muscle", "general_fitness"] },
    { bodyPart: "upper_body", goals: ["build_strength", "gain_muscle", "general_fitness"] },
    { bodyPart: "lower_body", goals: ["build_strength", "gain_muscle", "general_fitness"] },
    { bodyPart: "cardio", goals: ["cardio_endurance"] },
    { bodyPart: "cardio", goals: ["cardio_endurance", "general_fitness"] },
    { bodyPart: "cardio", goals: ["cardio_endurance"] },
    { bodyPart: "full_body", goals: ["build_strength", "more_sculpted", "general_fitness"] },
    { bodyPart: "core", goals: ["improve_flexibility", "general_fitness"] },
  ],
  light: [
    { bodyPart: "core", goals: ["improve_flexibility", "active_recovery"] },
    { bodyPart: "cardio", goals: ["active_recovery"] },
    { bodyPart: "cardio", goals: ["active_recovery", "general_fitness"] },
    { bodyPart: "core", goals: ["improve_flexibility", "active_recovery"] },
    { bodyPart: "cardio", goals: ["active_recovery"] },
  ],
  rest: [
    { bodyPart: "cardio", goals: ["active_recovery", "better_sleep"] },
    { bodyPart: "core", goals: ["improve_flexibility", "active_recovery", "better_sleep"] },
    { bodyPart: "core", goals: ["active_recovery"] },
    { bodyPart: "recovery", goals: ["active_recovery", "better_sleep"] },
  ],
};

/// Same ranking RecommendationDetailView.filteredWorkoutSuggestions uses:
/// a goals overlap match floats to the top; among ties, whichever body part
/// has had FEWER moderate/push_hard training sessions in the trailing 7
/// days floats above one trained more -- deprioritize, never exclude, per
/// BodyPartFocus's doc comment (DailyRecommendation.swift). Injury-aware
/// last: resolveBodyPartForInjuries can still redirect the winning pick to
/// a genuinely safe body part, same as generate-workout-plan does for the
/// client's own selection.
export function resolveTargetBodyPart(
  category: string,
  goals: string[],
  injuryTags: string[],
  severityMap: Record<string, InjurySeverityLevel>,
  recentBodyPartCounts: Record<string, number>,
): BodyPartFocus {
  const candidates = CATEGORY_BODY_PART_CANDIDATES[category] ?? CATEGORY_BODY_PART_CANDIDATES.moderate;
  const goalSet = new Set(goals);
  const ranked = [...candidates].sort((a, b) => {
    const aGoalMatch = a.goals.some((g) => goalSet.has(g));
    const bGoalMatch = b.goals.some((g) => goalSet.has(g));
    if (aGoalMatch !== bGoalMatch) return aGoalMatch ? -1 : 1;
    const aCount = recentBodyPartCounts[a.bodyPart] ?? 0;
    const bCount = recentBodyPartCounts[b.bodyPart] ?? 0;
    return aCount - bCount;
  });
  const top = ranked[0]?.bodyPart ?? "full_body";
  return resolveBodyPartForInjuries(top, injuryTags, severityMap).bodyPart;
}
