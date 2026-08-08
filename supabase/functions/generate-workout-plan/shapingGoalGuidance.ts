// DRAFTED, NOT EXPERT-REVIEWED -- same standing caveat as volumeLandmarks.ts/
// rirGuidance.ts/finisherCatalog.ts. Encodes generic, widely-cited resistance-
// training rep-range guidance (strength vs. hypertrophy vs. higher-rep
// metabolic/definition-focused work) -- NOT attributed to, sourced from, or
// endorsed by any named individual's proprietary material.
//
// Phase 3 (docs/coaching-personalization-plan.md): the deterministic half of
// shaping-goal programming, shaped exactly like finisherCatalog.ts's
// decideFinisher -- WHICH rep range, foundation movements, and hard
// constraint apply is decided HERE from plain inputs; buildPrompt only
// words it into the prompt, same "deterministic policy, LLM elaborates"
// rule as every other catalog in this file's directory.
//
// `foundationMovements` are prose MOVEMENT-PATTERN descriptions (e.g. "hip-
// hinge pattern"), never literal exercise_library names -- same reasoning
// as FINISHER_CATALOG's own descriptions: the LLM still elaborates each
// into a real name from the request-scoped candidate enum
// (_shared/exerciseLibraryMatch.ts), this catalog never asserts an exact
// string exists in the library. The list itself is a FIXED array, not
// date-rotated -- unlike the finisher catalog's variety-seeking rotation,
// the whole point here is the opposite: the same small set of anchor
// movements recurring session to session so progression is trackable,
// which is also what buildPrompt's own recentLogs guidance already assumes
// ("if the user has repeated an exercise, suggest a sensible progression").

import type { TrainingEmphasis } from "../_shared/nutritionTargets.ts";

/// Body parts this module has real guidance for -- matches
/// _shared/exerciseLibraryMatch.ts's own muscle-mapping keys. "cardio" and
/// "recovery" have no meaningful "foundation strength movement" concept,
/// so decideShapingGoalGuidance returns null for them (see below).
type ShapableBodyPart = "upper_body" | "lower_body" | "core" | "full_body";

function isShapableBodyPart(bodyPart: string): bodyPart is ShapableBodyPart {
  return bodyPart === "upper_body" || bodyPart === "lower_body" || bodyPart === "core" || bodyPart === "full_body";
}

/// Only the GoalTag values (_shared/goalTags.ts) with a real, distinct
/// rep-range angle -- deliberately NOT every tag. "maintain",
/// "general_fitness", "active_recovery", "better_sleep",
/// "improve_flexibility", "other", and "cardio_endurance" (conditioning is
/// already handled separately via the "cardio" body part) all fall through
/// to today's existing describeVolumeGuidance/describeRirGuidance defaults
/// unchanged -- this module adds nothing for them rather than fabricating
/// a rule.
type ShapingGoalTag = "build_strength" | "gain_muscle" | "leaner_toned" | "more_sculpted" | "lose_weight";

/// Priority order used ONLY when a user's own `goals` array contains more
/// than one recognized tag at once (e.g. both "build_strength" and
/// "lose_weight" selected) -- build_strength/gain_muscle outrank the
/// aesthetic-leaning tags: someone who explicitly asked to build strength
/// wants heavier work even if they also want to lean out, and the
/// composition side of that is nutrition's job (training_emphasis/
/// nutritionTargets.ts), not a lighter rep range here.
const GOAL_PRIORITY: ShapingGoalTag[] = ["build_strength", "gain_muscle", "leaner_toned", "more_sculpted", "lose_weight"];

export interface ShapingGoalGuidance {
  /// Which recognized tag drove this decision, and which signal it came
  /// from -- surfaced for tests/debugging, not used in the prompt text.
  goalTag: ShapingGoalTag;
  source: "goals" | "body_photo_emphasis_tags" | "training_emphasis";
  repRangeLabel: string;
  repRangeRationale: string;
  foundationMovements: string[];
  /// An explicit "never do X" rule this goal calls for, or null when the
  /// goal has nothing to forbid (build_strength/gain_muscle's whole point
  /// IS heavier/lower-rep work -- there's nothing to exclude).
  hardConstraint: string | null;
}

interface ShapingGoalProfile {
  repRangeLabel: string;
  repRangeRationale: string;
  foundationMovements: Record<ShapableBodyPart, string[]>;
  hardConstraint: string | null;
}

const STRENGTH_HARD_CONSTRAINT = null;
// Shared by leaner_toned/more_sculpted/lose_weight -- the user's own
// example for this phase ("avoid low-rep heavy loading when the goal is
// circumference reduction"). Framed as a hard, unconditional rule (never,
// not "usually") the same way pregnancyGuidance/contraindications phrase
// their own hard rules, distinct from the softer volume/RIR guidance lines
// this sits alongside.
const DEFINITION_HARD_CONSTRAINT =
  "Never program sets of 1-3 reps at near-maximal effort for this goal, even on a push_hard day -- this goal calls for moderate-load, higher-rep, higher-density work, not maximal-strength testing.";

const PROFILES: Record<ShapingGoalTag, ShapingGoalProfile> = {
  build_strength: {
    repRangeLabel: "3-6",
    repRangeRationale: "classic low-rep strength range for developing maximal force production",
    foundationMovements: {
      upper_body: ["bench press or push-up press pattern (horizontal press)", "bent-over or seated row pattern (horizontal pull)", "overhead press pattern"],
      lower_body: ["back squat or goblet squat pattern", "deadlift or Romanian deadlift pattern (hip hinge)"],
      core: ["weighted plank or dead bug pattern (anti-extension bracing)", "farmer's or suitcase carry pattern (loaded carry)"],
      full_body: ["squat pattern", "hip-hinge/deadlift pattern", "horizontal press pattern", "horizontal or vertical pull pattern"],
    },
    hardConstraint: STRENGTH_HARD_CONSTRAINT,
  },
  gain_muscle: {
    repRangeLabel: "6-12",
    repRangeRationale: "classic hypertrophy rep range (widely-cited resistance-training literature)",
    foundationMovements: {
      upper_body: ["flat or incline press pattern (chest)", "row pattern (back)", "overhead press pattern (shoulders)", "curl and press-down accessory pattern (arms)"],
      lower_body: ["squat pattern (quads)", "Romanian deadlift or hip thrust pattern (hamstrings/glutes)", "calf raise pattern"],
      core: ["weighted crunch or cable crunch pattern", "hanging leg raise or reverse crunch pattern"],
      full_body: ["squat pattern", "press pattern (upper push)", "row pattern (upper pull)", "hip-hinge pattern"],
    },
    hardConstraint: STRENGTH_HARD_CONSTRAINT,
  },
  // leaner_toned and more_sculpted are treated identically -- there's no
  // real physiological basis to differentiate "toned" from "sculpted" as
  // distinct training stimuli; both are the same higher-rep, moderate-load,
  // higher-density resistance work (the muscle-building stimulus itself
  // isn't different from hypertrophy training, just the rep range/rest
  // structure, which also raises metabolic demand).
  leaner_toned: {
    repRangeLabel: "12-15",
    repRangeRationale: "higher-rep, moderate-load work commonly recommended for a leaner, more defined look",
    foundationMovements: {
      upper_body: ["push-up or dumbbell press pattern, moderate load/higher rep", "row pattern, moderate load/higher rep", "lateral raise or banded pull-apart pattern"],
      lower_body: ["goblet squat or bodyweight squat pattern, moderate load/higher rep", "glute bridge or hip thrust pattern", "walking lunge pattern"],
      core: ["plank variation", "bicycle crunch or mountain climber pattern"],
      full_body: ["dumbbell thruster or squat-to-press circuit pattern", "kettlebell swing or hinge-carry pattern"],
    },
    hardConstraint: DEFINITION_HARD_CONSTRAINT,
  },
  more_sculpted: {
    repRangeLabel: "12-15",
    repRangeRationale: "higher-rep, moderate-load work commonly recommended for a leaner, more defined look",
    foundationMovements: {
      upper_body: ["push-up or dumbbell press pattern, moderate load/higher rep", "row pattern, moderate load/higher rep", "lateral raise or banded pull-apart pattern"],
      lower_body: ["goblet squat or bodyweight squat pattern, moderate load/higher rep", "glute bridge or hip thrust pattern", "walking lunge pattern"],
      core: ["plank variation", "bicycle crunch or mountain climber pattern"],
      full_body: ["dumbbell thruster or squat-to-press circuit pattern", "kettlebell swing or hinge-carry pattern"],
    },
    hardConstraint: DEFINITION_HARD_CONSTRAINT,
  },
  lose_weight: {
    repRangeLabel: "12-15",
    repRangeRationale: "higher-rep, moderate-load, full-body-leaning work to keep session density and energy expenditure up",
    foundationMovements: {
      upper_body: ["push-up or dumbbell press pattern, higher rep/shorter rest", "row pattern, higher rep/shorter rest"],
      lower_body: ["goblet squat or lunge pattern, higher rep/shorter rest", "kettlebell swing (hip-hinge) pattern"],
      core: ["plank or mountain climber pattern", "bicycle crunch pattern"],
      full_body: ["full-body circuit pattern (squat-to-press, burpee-style compound)", "kettlebell swing or carry pattern"],
    },
    hardConstraint: DEFINITION_HARD_CONSTRAINT,
  },
};

function isShapingGoalTag(tag: string): tag is ShapingGoalTag {
  return tag in PROFILES;
}

/// training_emphasis (cut/bulk/recomp/maintain -- see nutritionTargets.ts)
/// maps to the SAME two profile "families" nutritionTargets.ts itself uses:
/// recomp gets the hypertrophy profile there (protein-wise) for the same
/// reason it does here (muscle retention/gain matters most at maintenance
/// calories, which is a moderate-rep hypertrophy stimulus, not a max-
/// strength one). "maintain" has no shaping-specific direction, same as an
/// unmatched goal tag.
function shapingTagFromTrainingEmphasis(emphasis: TrainingEmphasis): ShapingGoalTag | null {
  switch (emphasis) {
    case "cut": return "lose_weight";
    case "bulk": return "gain_muscle";
    case "recomp": return "gain_muscle";
    case "maintain": return null;
  }
}

/// First recognized tag in GOAL_PRIORITY order found in `tags` -- shared by
/// the goals/body_photo_emphasis_tags lookups below (same shape, same
/// priority rule) so the two never drift apart.
function firstRecognizedTag(tags: string[] | null): ShapingGoalTag | null {
  if (!tags || tags.length === 0) return null;
  const present = new Set(tags);
  return GOAL_PRIORITY.find((tag) => present.has(tag)) ?? null;
}

/// The single entry point -- purely deterministic, never left to the LLM.
/// Returns null whenever there's nothing goal-specific to add (no
/// recognized signal from any of the three inputs, a rest/light day with
/// no real "working sets" to shape, or a body part with no foundation-
/// movement concept) -- callers fall back to today's existing generic
/// volume/RIR guidance unchanged, same "omit rather than fabricate" rule
/// as every other optional prompt line in buildPrompt.
export function decideShapingGoalGuidance(
  goals: string[] | null,
  bodyPhotoEmphasisTags: string[] | null,
  trainingEmphasis: TrainingEmphasis | null,
  bodyPart: string,
  category: string,
): ShapingGoalGuidance | null {
  if (category === "rest" || category === "light") return null;
  if (!isShapableBodyPart(bodyPart)) return null;

  // Precedence exactly mirrors this file's existing bodyPhotoEmphasisLine/
  // trainingEmphasisLine framing: the user's own stated goals always win;
  // the vision-derived tag set is a secondary signal consulted only when
  // the user hasn't stated a recognized shaping goal themselves; the
  // coarse training_emphasis direction is a last-resort nudge, consulted
  // only when NEITHER of the above gives a recognized tag.
  let tag: ShapingGoalTag | null = firstRecognizedTag(goals);
  let source: ShapingGoalGuidance["source"] = "goals";
  if (tag === null) {
    tag = firstRecognizedTag(bodyPhotoEmphasisTags);
    source = "body_photo_emphasis_tags";
  }
  if (tag === null && trainingEmphasis !== null) {
    tag = shapingTagFromTrainingEmphasis(trainingEmphasis);
    source = "training_emphasis";
  }
  if (tag === null) return null;

  const profile = PROFILES[tag];
  return {
    goalTag: tag,
    source,
    repRangeLabel: profile.repRangeLabel,
    repRangeRationale: profile.repRangeRationale,
    foundationMovements: profile.foundationMovements[bodyPart],
    hardConstraint: profile.hardConstraint,
  };
}

// Re-exported only for shapingGoalGuidance_test.ts's own type-guard tests --
// not used outside this module/its tests.
export { isShapingGoalTag };
