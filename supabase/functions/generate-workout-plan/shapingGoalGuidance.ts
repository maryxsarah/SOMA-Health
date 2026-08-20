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
///
/// The six body-part-targeted tags (lose_belly_fat/lean_out_legs/
/// toned_arms/grow_glutes/stronger_core/more_visible_abs) are more specific
/// siblings of leaner_toned/more_sculpted/gain_muscle -- same rep-range
/// families, but with foundationMovements biased toward the named body
/// part so the recurring anchor movements actually reflect what the user
/// asked to change, not just a generic full-body list.
type ShapingGoalTag =
  | "build_strength"
  | "gain_muscle"
  | "leaner_toned"
  | "more_sculpted"
  | "lose_weight"
  | "grow_glutes"
  | "stronger_core"
  | "lose_belly_fat"
  | "lean_out_legs"
  | "toned_arms"
  | "more_visible_abs";

/// Priority order used ONLY when a user's own `goals` array contains more
/// than one recognized tag at once (e.g. both "build_strength" and
/// "lose_weight" selected) -- build_strength/gain_muscle outrank every
/// definition-family tag: someone who explicitly asked to build strength
/// wants heavier work even if they also want to lean out, and the
/// composition side of that is nutrition's job (training_emphasis/
/// nutritionTargets.ts), not a lighter rep range here. grow_glutes/
/// stronger_core rank right after build_strength/gain_muscle for the same
/// reason (their rep ranges are close enough kin to the general strength/
/// hypertrophy families that an explicit general ask should still win the
/// TIE, but a body-part-specific hypertrophy/strength ask still beats any
/// definition-family tag). Within the definition family, the four
/// body-part-specific tags (lose_belly_fat/lean_out_legs/toned_arms/
/// more_visible_abs) rank ABOVE leaner_toned/more_sculpted/lose_weight --
/// unlike the strength family, every definition-family tag shares the
/// identical "12-15" rep range, so preferring the more specific tag only
/// ever changes which foundation movements get picked, never the rep
/// range itself, making specific-over-generic a free improvement here.
const GOAL_PRIORITY: ShapingGoalTag[] = [
  "build_strength",
  "gain_muscle",
  "grow_glutes",
  "stronger_core",
  "lose_belly_fat",
  "lean_out_legs",
  "toned_arms",
  "more_visible_abs",
  "leaner_toned",
  "more_sculpted",
  "lose_weight",
];

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
  // grow_glutes is gain_muscle's hypertrophy stimulus, biased toward the
  // glutes specifically on a lower_body/full_body day -- upper_body/core
  // foundation movements have no real glute angle, so those reuse
  // gain_muscle's own list rather than inventing a distinct one.
  grow_glutes: {
    repRangeLabel: "6-12",
    repRangeRationale: "classic hypertrophy rep range (widely-cited resistance-training literature), glute-emphasized",
    foundationMovements: {
      upper_body: ["flat or incline press pattern (chest)", "row pattern (back)", "overhead press pattern (shoulders)"],
      lower_body: ["hip thrust or glute bridge pattern (primary glute driver)", "Romanian deadlift or single-leg RDL pattern (hamstrings/glutes)", "walking lunge or Bulgarian split squat pattern", "cable or banded glute kickback pattern"],
      core: ["weighted crunch or cable crunch pattern", "hanging leg raise or reverse crunch pattern"],
      full_body: ["squat pattern", "hip-hinge pattern, glute-focused", "row pattern (upper pull)"],
    },
    hardConstraint: STRENGTH_HARD_CONSTRAINT,
  },
  // stronger_core is build_strength's loaded, controlled-tempo stimulus
  // applied to the core specifically -- unlike gain_muscle's higher-rep
  // ab work, this is about real anti-extension/anti-rotation strength and
  // stability, not just muscle size.
  stronger_core: {
    repRangeLabel: "6-10",
    repRangeRationale: "moderate-load, controlled-tempo work that builds real core strength and stability, not just endurance",
    foundationMovements: {
      upper_body: ["bench press or push-up press pattern (horizontal press)", "bent-over or seated row pattern (horizontal pull)"],
      lower_body: ["back squat or goblet squat pattern", "deadlift or Romanian deadlift pattern (hip hinge)"],
      core: ["weighted plank or loaded carry pattern (anti-extension bracing)", "cable or banded anti-rotation pattern (Pallof press)", "hanging leg raise or weighted sit-up pattern", "dead bug or bird-dog pattern (core stability)"],
      full_body: ["loaded carry pattern (farmer's or suitcase carry)", "squat or hip-hinge pattern with a strong core-bracing cue"],
    },
    hardConstraint: STRENGTH_HARD_CONSTRAINT,
  },
  // The remaining four tags are all leaner_toned's higher-rep, definition-
  // focused stimulus, each biased toward a specific body part -- same
  // "no real physiological basis to differentiate the rep range itself"
  // reasoning leaner_toned/more_sculpted's shared comment already gives,
  // just applied to a narrower target than "overall look." None of these
  // claim spot-reduction is real (it isn't -- fat loss is systemic): the
  // rationale text frames each as building/revealing the muscle under
  // regional fat, on top of the same session-density fat-loss work the
  // other definition tags already call for.
  lose_belly_fat: {
    repRangeLabel: "12-15",
    repRangeRationale: "higher-rep, moderate-load, full-body-leaning work for overall fat loss (spot-reduction isn't real), paired with extra core work so the muscle underneath shows as fat comes down",
    foundationMovements: {
      upper_body: ["push-up or dumbbell press pattern, higher rep/shorter rest", "row pattern, higher rep/shorter rest"],
      lower_body: ["goblet squat or lunge pattern, higher rep/shorter rest", "kettlebell swing (hip-hinge) pattern"],
      core: ["weighted or cable crunch pattern, higher rep", "hanging or lying leg raise pattern", "plank-to-mountain-climber circuit pattern (metabolic core work)"],
      full_body: ["full-body circuit pattern (squat-to-press, burpee-style compound)", "kettlebell swing or carry pattern"],
    },
    hardConstraint: DEFINITION_HARD_CONSTRAINT,
  },
  lean_out_legs: {
    repRangeLabel: "12-15",
    repRangeRationale: "higher-rep, moderate-load lower-body work commonly recommended for a leaner, more defined look in the legs",
    foundationMovements: {
      upper_body: ["push-up or dumbbell press pattern, moderate load/higher rep", "row pattern, moderate load/higher rep"],
      lower_body: ["goblet squat or bodyweight squat pattern, moderate load/higher rep", "walking lunge or reverse lunge pattern, higher rep", "glute bridge or hip thrust pattern, higher rep", "calf raise pattern, higher rep"],
      core: ["plank variation", "bicycle crunch or mountain climber pattern"],
      full_body: ["kettlebell swing or hinge-carry pattern", "squat-to-press or lunge-circuit pattern"],
    },
    hardConstraint: DEFINITION_HARD_CONSTRAINT,
  },
  toned_arms: {
    repRangeLabel: "12-15",
    repRangeRationale: "higher-rep, moderate-load arm and shoulder work commonly recommended for a leaner, more defined look in the arms",
    foundationMovements: {
      upper_body: ["dumbbell curl and triceps press-down or dip pattern, higher rep", "lateral raise or banded pull-apart pattern", "push-up or dumbbell press pattern, moderate load/higher rep", "row pattern, moderate load/higher rep"],
      lower_body: ["goblet squat or bodyweight squat pattern, moderate load/higher rep", "glute bridge or hip thrust pattern", "walking lunge pattern"],
      core: ["plank variation", "bicycle crunch or mountain climber pattern"],
      full_body: ["dumbbell thruster or squat-to-press circuit pattern", "kettlebell swing or hinge-carry pattern"],
    },
    hardConstraint: DEFINITION_HARD_CONSTRAINT,
  },
  more_visible_abs: {
    repRangeLabel: "12-15",
    repRangeRationale: "higher-rep ab work paired with overall fat-loss-supporting training -- visible abs come from lower body fat, not ab exercises alone, so this pairs direct ab work with the same higher-density approach as the other definition-focused goals",
    foundationMovements: {
      upper_body: ["push-up or dumbbell press pattern, moderate load/higher rep", "row pattern, moderate load/higher rep"],
      lower_body: ["goblet squat or bodyweight squat pattern, moderate load/higher rep", "walking lunge pattern"],
      core: ["weighted or cable crunch pattern, higher rep", "hanging or lying leg raise pattern", "bicycle crunch or mountain climber pattern", "plank variation with rotation"],
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
