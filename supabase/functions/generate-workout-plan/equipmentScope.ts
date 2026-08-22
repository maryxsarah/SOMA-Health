// Scopes exercise-candidate equipment (and the matching prompt text) to
// the specific EquipmentTag a WorkoutSuggestion promised, instead of the
// user's entire stored equipment profile. BUG this fixes: a suggestion
// like "30 min resistance band circuit" (EquipmentTag.resistanceBands)
// generated a session pulling in kettlebells/bench/machines whenever the
// user's profile ALSO had .gym/gym-catalog equipment set -- nothing
// constrained exercise selection back to the narrow category the
// suggestion actually promised. Confirmed root cause: index.ts passed
// userRow.equipment (the user's WHOLE profile) into
// fetchCandidateExerciseNames regardless of which suggestion was picked,
// for every category, not just resistance bands.
//
// Scoping rule (confirmed): only .gym/.home_gym mean "pull from the
// user's real stored equipment profile" -- every other EquipmentTag
// promises a specific modality (bands, yoga, bodyweight, a specific class
// type, etc.) and is scoped strictly to that, never widened by whatever
// else happens to be in the user's profile. Includes .bike/.pool (no
// exercise_library equipment mapping exists for either -- narrowing them
// means a cardio-only bike/pool suggestion gets bodyweight-only warm-up/
// cooldown candidates, not the user's full gym; a deliberate, confirmed
// behavior change from today, not an oversight).
//
// A missing/unrecognized tag (an older client that hasn't sent one yet,
// or a future suggestion nobody's classified) falls back to today's
// existing full-profile behavior -- silently narrowing something this
// code can't confidently scope would be worse than the status quo.

import type { FreeTextEquipmentResolution } from "../_shared/equipment.ts";

/// EquipmentTag raw values (Soma/Models/DailyRecommendation.swift) that
/// mean "pull from the user's real stored equipment profile." Every other
/// tag -- including ones no suggestion in the catalog uses yet, kept here
/// for forward-compatibility -- is narrow-scoped.
export const FULL_PROFILE_EQUIPMENT_TAGS = new Set(["gym", "home_gym"]);

/// Natural-language description of what a narrow category actually means,
/// for the prompt's "Available equipment: ..." line -- distinct from the
/// exercise_library equipment keys (e.g. "bands"), which read as
/// database internals, not something to hand an LLM as prose. Every
/// non-full-profile EquipmentTag needs an entry here (enforced by test,
/// not just by convention) so a forgotten case fails loudly rather than
/// falling through to something unhelpful.
export const NARROW_EQUIPMENT_DESCRIPTION: Record<string, string> = {
  yoga_studio: "yoga studio equipment (mat, blocks, straps) and bodyweight only -- no free weights or machines",
  resistance_bands: "resistance bands only -- no free weights or machines",
  bike: "a stationary bike -- this is a cardio-only cycling session; bodyweight movements only for any warm-up/cool-down portion",
  pool: "a pool -- this is a cardio-only swimming session; bodyweight movements only for any warm-up/cool-down portion",
  boxing_gym: "boxing gym equipment (bag, gloves, wraps) and bodyweight only",
  mat_pilates: "a pilates mat and bodyweight only",
  calisthenics_gymnastics: "bodyweight/calisthenics equipment only (bars, rings) -- no free weights or machines",
  crossfit: "typical CrossFit box equipment (barbell, dumbbell, kettlebells, bodyweight, medicine ball, cable/machine stations)",
  hiit_circuit_studio: "typical HIIT circuit studio equipment (bodyweight, dumbbell, kettlebells, bands, medicine ball)",
  bodyweight_only: "bodyweight only, no equipment",
  other: "only what the user described in their own equipment notes -- nothing else from their broader profile applies to this specific session",
};

export interface EquipmentScope {
  /// The RAW equipment-tag array to pass as fetchCandidateExerciseNames's
  /// `equipment` param -- that function resolves tags -> library-equipment
  /// keys itself (resolveLibraryEquipment, _shared/exerciseLibraryMatch.ts),
  /// so this stays tags, not pre-resolved keys. Narrow: exactly the one
  /// suggestion tag. Full profile: the user's whole stored array,
  /// unchanged from today.
  equipment: string[];
  /// fetchCandidateExerciseNames's `extraLibraryEquipment` param (already-
  /// resolved library keys from free-text notes/gym-catalog selections)
  /// -- empty for a narrow scope. A resistance-bands session must never
  /// also pull in the user's separately-logged gym-catalog kettlebells;
  /// that's exactly the bug being fixed.
  extraLibraryEquipment: string[];
  unlocksCardio: boolean;
  cardioLibraryEquipment: string[];
  /// The prompt's "Available equipment: ..." line -- derived from the
  /// SAME scope decision as the fields above, so the prose and the
  /// schema-constrained candidate list can never disagree with each other
  /// the way two independently-maintained computations could.
  promptDescription: string;
}

export function resolveEquipmentScope(
  suggestionEquipmentTag: string | null | undefined,
  fullProfileEquipment: string[],
  freeTextEquipment: FreeTextEquipmentResolution,
  gymEquipmentDisplayLine: string,
): EquipmentScope {
  // Narrow ONLY for a tag we explicitly recognize as narrow (has its own
  // NARROW_EQUIPMENT_DESCRIPTION entry) -- an unrecognized/future tag
  // must fall through to full-profile below, not be silently treated as
  // narrow just because it isn't literally "gym"/"home_gym". Silently
  // narrowing something this code can't confidently scope would be worse
  // than the status quo.
  const isNarrow = !!suggestionEquipmentTag &&
    !FULL_PROFILE_EQUIPMENT_TAGS.has(suggestionEquipmentTag) &&
    suggestionEquipmentTag in NARROW_EQUIPMENT_DESCRIPTION;

  if (!isNarrow) {
    // Today's exact existing full-profile computation, unchanged --
    // .gym/.home_gym suggestions, and the defensive missing/unrecognized-
    // tag fallback, both land here.
    const equipmentLine = fullProfileEquipment.length
      ? fullProfileEquipment.join(", ")
      : "no equipment (bodyweight only)";
    return {
      equipment: fullProfileEquipment,
      extraLibraryEquipment: freeTextEquipment.libraryEquipment,
      unlocksCardio: freeTextEquipment.unlocksCardio,
      cardioLibraryEquipment: freeTextEquipment.cardioLibraryEquipment,
      promptDescription: gymEquipmentDisplayLine
        ? `${equipmentLine} Specific gym equipment available: ${gymEquipmentDisplayLine}.`
        : equipmentLine,
    };
  }

  // Narrow: only this ONE tag reaches fetchCandidateExerciseNames's own
  // resolveLibraryEquipment call (not the user's whole profile array).
  // Never unlocks cardio candidates or the user's other free-text/gym-
  // catalog gear; this session promised one specific thing.
  return {
    equipment: [suggestionEquipmentTag!],
    extraLibraryEquipment: [],
    unlocksCardio: false,
    cardioLibraryEquipment: [],
    promptDescription: NARROW_EQUIPMENT_DESCRIPTION[suggestionEquipmentTag!] ??
      // Shouldn't happen (every narrow tag has an entry above, enforced
      // by test) -- but if a new EquipmentTag case is ever added to the
      // Swift enum without a matching entry here, fail toward the safest
      // available description rather than an empty/undefined string.
      "bodyweight only, no equipment",
  };
}
