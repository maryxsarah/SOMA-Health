// DRAFTED, NOT EXPERT-REVIEWED -- needs sign-off from a certified S&C
// professional before this is treated as authoritative, same caveat as
// contraindications.ts and LOAD_FRACTION_OF_BODYWEIGHT. Fixed, versioned-
// in-code library, same pattern as generate-gym-workout/templates.ts --
// which finisher CONCEPT gets used is a deterministic decision (matched to
// today's body part), not something left to the LLM to invent from
// scratch; the LLM still elaborates the concept into concrete
// exercises/instructions, same as it does for the rest of the plan.

import type { TrainingEmphasis } from "../_shared/nutritionTargets.ts";

export type FinisherModality =
  | "emom"
  | "density_set"
  | "complex"
  | "metabolic_conditioning"
  | "carry"
  | "sprint_interval";

export interface FinisherDefinition {
  /// Matches BodyPartFocus rawValue (Soma/Models/DailyRecommendation.swift).
  focusArea: string;
  modality: FinisherModality;
  /// 5-10 min per the product requirement -- an add-on, not a second workout.
  durationMinutesRange: [number, number];
  rpeTarget: string;
  description: string;
}

const FINISHER_CATALOG: FinisherDefinition[] = [
  {
    focusArea: "upper_body",
    modality: "density_set",
    durationMinutesRange: [5, 8],
    rpeTarget: "RPE 8-9",
    description:
      "As many quality reps as possible of a paired push/pull movement (e.g. push-ups + inverted rows) within the time cap, resting only as needed to keep form.",
  },
  {
    focusArea: "lower_body",
    modality: "complex",
    durationMinutesRange: [6, 9],
    rpeTarget: "RPE 8-9",
    description:
      "A barbell/dumbbell/bodyweight complex chaining 3-4 lower-body movements back-to-back (e.g. squat, reverse lunge, glute bridge) for 3-4 rounds with minimal rest between movements.",
  },
  {
    focusArea: "full_body",
    modality: "metabolic_conditioning",
    durationMinutesRange: [6, 10],
    rpeTarget: "RPE 8-9",
    description:
      "A short, hard full-body metabolic circuit (e.g. burpees, kettlebell swings, rowing) cycling continuously for the full duration.",
  },
  {
    focusArea: "core",
    modality: "density_set",
    durationMinutesRange: [5, 7],
    rpeTarget: "RPE 7-8",
    description:
      "As many quality reps as possible of a core-focused movement pair (e.g. planks + hollow holds) within the time cap.",
  },
  {
    focusArea: "cardio",
    modality: "sprint_interval",
    durationMinutesRange: [5, 8],
    rpeTarget: "RPE 9-10",
    description:
      "Short, hard sprint or high-intensity cardio intervals (e.g. 20-30 sec max effort, equal rest) repeated for the full duration.",
  },
  {
    focusArea: "recovery",
    modality: "emom",
    durationMinutesRange: [5, 6],
    rpeTarget: "RPE 3-4",
    description:
      "A gentle every-minute-on-the-minute mobility flow (e.g. cat-cow, hip circles, breathing drills) -- not a real finisher, but recovery days never get one anyway (see the caller).",
  },
];

/// Picks the finisher matching today's body part -- falls back to the
/// full-body metabolic-conditioning entry if there's no exact match
/// (e.g. an injury-substituted body part this catalog doesn't cover yet).
///
/// On a "cut" training_emphasis (from the goal-photo comparison), the
/// cardio/sprint_interval entry is preferred over the body-part match --
/// e.g. leg day would otherwise always get a strength-flavored "complex"
/// finisher (see FINISHER_CATALOG's lower_body entry) with nothing that
/// actually raises heart rate, even for someone whose stated direction is
/// leaning out. bulk/recomp/maintain/unknown keep the existing body-part
/// match unchanged -- this is deliberately a "cut" override, not a general
/// rebalancing, since more compound/heavy work is exactly right for bulk.
/// Equipment isn't checked here: the cardio concept's concrete exercises
/// are still elaborated under the prompt's existing "ONLY the user's
/// available equipment" constraint (index.ts's finisherEquipmentConstraint),
/// so a bodyweight-only user gets bodyweight cardio (e.g. high knees,
/// mountain climbers), not an assumed treadmill.
function selectFinisher(bodyPart: string, trainingEmphasis: TrainingEmphasis | null): FinisherDefinition {
  if (trainingEmphasis === "cut") {
    const cardio = FINISHER_CATALOG.find((f) => f.focusArea === "cardio");
    if (cardio) return cardio;
  }
  return (
    FINISHER_CATALOG.find((f) => f.focusArea === bodyPart) ??
    FINISHER_CATALOG.find((f) => f.focusArea === "full_body")!
  );
}

/// A finisher is safe from a given set of contraindication keywords
/// (from contraindications.ts's describeContraindications) if none of them
/// appear in its description/modality/focus text -- same coarse substring
/// mechanism the rest of this codebase already uses for keyword filtering.
function isFinisherSafeGivenInjuries(finisher: FinisherDefinition, excludedKeywords: string[]): boolean {
  if (excludedKeywords.length === 0) return true;
  const haystack = `${finisher.description} ${finisher.modality} ${finisher.focusArea}`.toLowerCase();
  return !excludedKeywords.some((kw) => haystack.includes(kw.toLowerCase()));
}

/// True if yesterday's logged workout was itself a push_hard day targeting
/// the SAME focus area as this finisher -- avoids stacking two max-effort
/// sessions on the same muscle group back to back.
function conflictsWithRecentSplit(
  finisher: FinisherDefinition,
  recentLogs: { date: string; body_part: string; category: string }[],
  yesterday: string,
): boolean {
  return recentLogs.some((l) => l.date === yesterday && l.category === "push_hard" && l.body_part === finisher.focusArea);
}

export interface FinisherDecision {
  /// False on light/rest days -- no finisher at all, per product decision
  /// (previously mandatory on every category, "no exceptions").
  include: boolean;
  /// True only on an eligible category (moderate/push_hard) with
  /// exceptional readiness AND no injury/split-position conflict -- gates
  /// the full 5-10 min max-effort version. False (but include=true) means
  /// a shorter, ordinary, clearly-optional finisher instead.
  exceptional: boolean;
  definition: FinisherDefinition | null;
}

/// The single entry point the caller uses -- decides whether a finisher
/// appears at all, and if so whether it's the exceptional max-effort
/// version, from purely deterministic inputs (never left to the LLM).
export function decideFinisher(
  category: string,
  bodyPart: string,
  exceptionalReadiness: boolean,
  excludedKeywords: string[],
  recentLogs: { date: string; body_part: string; category: string }[],
  yesterday: string,
  trainingEmphasis: TrainingEmphasis | null = null,
): FinisherDecision {
  const eligibleCategory = category === "moderate" || category === "push_hard";
  if (!eligibleCategory) {
    return { include: false, exceptional: false, definition: null };
  }

  const candidate = selectFinisher(bodyPart, trainingEmphasis);
  const safeFromInjury = isFinisherSafeGivenInjuries(candidate, excludedKeywords);
  const safeFromSplit = !conflictsWithRecentSplit(candidate, recentLogs, yesterday);
  return {
    include: true,
    exceptional: exceptionalReadiness && safeFromInjury && safeFromSplit,
    definition: candidate,
  };
}
