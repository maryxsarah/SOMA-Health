// Canonical GoalTag vocabulary -- mirrors Soma/Models/DailyRecommendation.swift's
// `GoalTag` enum raw values exactly. Kept in sync manually, same maintenance
// pattern as _shared/equipment.ts's EQUIPMENT_VOCABULARY (a different
// closed vocabulary shared between a vision-model schema and Swift).
//
// Used by analyze-body-photo to constrain the vision model's output via a
// JSON-schema `enum`, so a body-photo comparison can only ever suggest
// emphasis in terms the rest of the app (buildPrompt, ProfileView's goal
// picker) already understands -- never a new, uncoordinated category.

export const GOAL_TAG_VOCABULARY = [
  "lose_weight",
  "maintain",
  "build_strength",
  "gain_muscle",
  "leaner_toned",
  "more_sculpted",
  "cardio_endurance",
  "improve_flexibility",
  "better_sleep",
  "general_fitness",
  "active_recovery",
  "lose_belly_fat",
  "lean_out_legs",
  "toned_arms",
  "grow_glutes",
  "stronger_core",
  "more_visible_abs",
  "other",
] as const;

export type GoalTagValue = typeof GOAL_TAG_VOCABULARY[number];

/// Belt-and-braces re-filter against the closed enum, in case a vendor-side
/// schema regression ever lets an unmatched value leak through -- same
/// defensive pattern as analyze-gym-photo's normalizeEquipment.
export function normalizeGoalTags(input: string[]): string[] {
  const known = new Set<string>(GOAL_TAG_VOCABULARY);
  const out = new Set<string>();
  for (const raw of input) {
    if (known.has(raw)) out.add(raw);
  }
  return Array.from(out);
}
